#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7pFolderScopeInventory265.ps1')
    function New-BW4k7pFakeStore {
        param([string]$SentStore='pop3-store',[bool]$HasSent=$true)
        $m=@{
            6=[pscustomobject]@{EntryID='id-inbox';StoreID='pop3-store'}
            4=[pscustomobject]@{EntryID='id-outbox';StoreID='pop3-store'}
            3=[pscustomobject]@{EntryID='id-deleted';StoreID='pop3-store'}
        }
        if($HasSent){$m[5]=[pscustomobject]@{EntryID='id-sent';StoreID=$SentStore}}
        $store=[pscustomobject]@{StoreID='pop3-store';Map=$m}
        $store | Add-Member -MemberType ScriptMethod -Name GetDefaultFolder -Value {
            param($k)
            if($this.Map.ContainsKey([int]$k)){return $this.Map[[int]$k]}
            return $null
        }
        return $store
    }
    function New-BW4k7pFakeMail {
        param([datetime]$Received=([datetime]'2023-04-05'),
              [datetime]$Sent=([datetime]'2024-06-01'),
              [int]$Class=43,[long]$Size=1000,
              [int]$AttachCount=0)
        $a=[pscustomobject]@{Count=$AttachCount}
        $a | Add-Member -MemberType ScriptMethod -Name Item -Value {param($i) return [pscustomobject]@{Size=[long]101}}
        return [pscustomobject]@{
            Class=$Class;ReceivedTime=$Received;SentOn=$Sent
            Size=$Size;Attachments=$a
        }
    }
    function New-BW4k7pFakeFolder {
        param([object[]]$Messages=@())
        $it=[pscustomobject]@{Count=[int]$Messages.Count;Messages=$Messages;Position=-1}
        $it | Add-Member -MemberType ScriptMethod -Name GetFirst -Value {
            $this.Position=0
            if($this.Count -eq 0){return $null}
            return $this.Messages[0]
        }
        $it | Add-Member -MemberType ScriptMethod -Name GetNext -Value {
            $this.Position++
            if($this.Position -ge $this.Messages.Count){return $null}
            return $this.Messages[$this.Position]
        }
        return [pscustomobject]@{Items=$it}
    }
    function Get-BW4k7pRole {
        param([string]$Id='id-custom',[string]$ParentRole='Root',[int]$DefaultItemType=0)
        $a=@{
            EntryId=$Id;InboxEntryId='id-inbox';SentEntryId='id-sent'
            OutboxEntryId='id-outbox';ExcludedSystemEntryIds=@('id-deleted','id-drafts')
            ParentRole=$ParentRole;DefaultItemType=$DefaultItemType
        }
        return (Get-OPA265BW4k7pFolderRole @a)
    }
}
Describe 'BW4k7p exact POP3 Sent vs Outbox folder scope and bounded inventory policy' {
  It 'Inbox identified only by EntryID' {
    (Get-BW4k7pRole -Id 'id-inbox') | Should -BeExactly 'Inbox'
  }
  It 'SentMail identified only by EntryID' {
    (Get-BW4k7pRole -Id 'id-sent') | Should -BeExactly 'SentItems'
  }
  It 'Outbox excluded by EntryID' {
    (Get-BW4k7pRole -Id 'id-outbox') | Should -BeExactly 'OutboxExcluded'
  }
  It 'localized Sent-like name is not actual Sent' {
    (Get-BW4k7pRole -Id 'Отправленные') | Should -BeExactly 'UserMail'
  }
  It 'localized Outbox-like name does not change identity' {
    (Get-BW4k7pRole -Id 'Исходящие') | Should -BeExactly 'UserMail'
  }
  It 'user folder under Inbox' {
    (Get-BW4k7pRole -ParentRole 'Inbox') | Should -BeExactly 'UserMail'
  }
  It 'user folder under Sent Items' {
    (Get-BW4k7pRole -ParentRole 'SentItems') | Should -BeExactly 'UserMail'
  }
  It 'subfolder under Outbox stays excluded' {
    (Get-BW4k7pRole -ParentRole 'OutboxExcluded') | Should -BeExactly 'OutboxExcluded'
  }
  It 'subfolder under Deleted stays excluded' {
    (Get-BW4k7pRole -ParentRole 'SystemExcluded') | Should -BeExactly 'SystemExcluded'
  }
  It 'nested nonmail excluded' {
    (Get-BW4k7pRole -ParentRole 'NonMailExcluded') | Should -BeExactly 'NonMailExcluded'
  }
  It 'nested unresolved excluded' {
    (Get-BW4k7pRole -ParentRole 'Unresolved') | Should -BeExactly 'Unresolved'
  }
  It 'calendar default item type excluded' {
    (Get-BW4k7pRole -DefaultItemType 1) | Should -BeExactly 'NonMailExcluded'
  }
  It 'contacts default item type excluded' {
    (Get-BW4k7pRole -DefaultItemType 2) | Should -BeExactly 'NonMailExcluded'
  }
  It 'mail default item type included' {
    (Get-BW4k7pRole -DefaultItemType 0) | Should -BeExactly 'UserMail'
  }
  It 'deleted root explicitly excluded' {
    (Get-BW4k7pRole -Id 'id-deleted') | Should -BeExactly 'SystemExcluded'
  }
  It 'draft root explicitly excluded' {
    (Get-BW4k7pRole -Id 'id-drafts') | Should -BeExactly 'SystemExcluded'
  }
  It 'case insensitive opaque IDs' {
    (Get-BW4k7pRole -Id 'ID-SENT') | Should -BeExactly 'SentItems'
  }
  It 'blank folder EntryID forbidden' {
    {Get-OPA265BW4k7pFolderRole -EntryId ''} | Should -Throw
  }
  It 'Store folder Inbox constant 6' {
    $x=Get-OPA265BW4k7pDefaultFolderMap -Store (New-BW4k7pFakeStore); $x.Inbox | Should -BeExactly 'id-inbox'
  }
  It 'Store folder SentMail constant 5' {
    $x=Get-OPA265BW4k7pDefaultFolderMap -Store (New-BW4k7pFakeStore); $x.SentItems | Should -BeExactly 'id-sent'
  }
  It 'Store folder Outbox constant 4' {
    $x=Get-OPA265BW4k7pDefaultFolderMap -Store (New-BW4k7pFakeStore); $x.Outbox | Should -BeExactly 'id-outbox'
  }
  It 'Sent Mail other store rejected' {
    {Get-OPA265BW4k7pDefaultFolderMap -Store (New-BW4k7pFakeStore -SentStore 'not-pop3')} | Should -Throw
  }
  It 'missing Sent does not silently become Outbox' {
    $x=Get-OPA265BW4k7pDefaultFolderMap -Store (New-BW4k7pFakeStore -HasSent $false); $x.SentItems | Should -BeExactly ''
  }
  It 'Outbox and Sent remain distinct' {
    $x=Get-OPA265BW4k7pDefaultFolderMap -Store (New-BW4k7pFakeStore); ($x.Outbox -eq $x.SentItems) | Should -BeFalse
  }
  It 'default Deleted Items excluded' {
    $x=Get-OPA265BW4k7pDefaultFolderMap -Store (New-BW4k7pFakeStore); $x.SystemExcluded | Should -Contain 'id-deleted'
  }
  It 'no default Inbox rejected' {
    $s=New-BW4k7pFakeStore; [void]$s.Map.Remove(6); {Get-OPA265BW4k7pDefaultFolderMap -Store $s} | Should -Throw
  }
  It 'no StoreID rejected' {
    $s=New-BW4k7pFakeStore; $s.StoreID=''; {Get-OPA265BW4k7pDefaultFolderMap -Store $s} | Should -Throw
  }
  It 'Sent year uses SentOn' {
    $m=New-BW4k7pFakeMail; (Get-OPA265BW4k7pYear -Item $m -Role 'SentItems').Year | Should -Be 2024
  }
  It 'Inbox year uses ReceivedTime' {
    $m=New-BW4k7pFakeMail; (Get-OPA265BW4k7pYear -Item $m -Role 'Inbox').Year | Should -Be 2023
  }
  It 'UserMail year uses ReceivedTime' {
    $m=New-BW4k7pFakeMail; (Get-OPA265BW4k7pYear -Item $m -Role 'UserMail').Year | Should -Be 2023
  }
  It 'SentOn missing falls back ReceivedTime' {
    $m=New-BW4k7pFakeMail -Sent ([datetime]'0001-01-01'); $x=Get-OPA265BW4k7pYear -Item $m -Role 'SentItems'; $x.Year | Should -Be 2023; $x.DateField | Should -BeExactly 'ReceivedTime'
  }
  It 'ReceivedTime missing falls back SentOn' {
    $m=New-BW4k7pFakeMail -Received ([datetime]'0001-01-01'); $x=Get-OPA265BW4k7pYear -Item $m -Role 'Inbox'; $x.Year | Should -Be 2024; $x.DateField | Should -BeExactly 'SentOn'
  }
  It 'both dates unknown not silently 0001' {
    $m=New-BW4k7pFakeMail -Received ([datetime]'0001-01-01') -Sent ([datetime]'0001-01-01'); $x=Get-OPA265BW4k7pYear -Item $m -Role 'Inbox'; $x.DateAvailable | Should -BeFalse
  }
  It 'nonmail class never counted' {
    $m=New-BW4k7pFakeMail -Class 48; (Get-OPA265BW4k7pYear -Item $m -Role 'Inbox').IsMail | Should -BeFalse
  }
  It 'future year 2200 rejected' {
    $m=New-BW4k7pFakeMail -Received ([datetime]'2200-01-01') -Sent ([datetime]'0001-01-01'); (Get-OPA265BW4k7pYear -Item $m -Role 'Inbox').DateAvailable | Should -BeFalse
  }
  It 'account Archive year naming exact' {
    (Get-OPA265BW4k7pArchivePlanName -SourcePst 'C:\mail\info@stios.ru.pst' -Year 2025) | Should -BeExactly 'info@stios.ru.Archive-2025.pst'
  }
  It 'plan no PST creation' {
    $x=@(New-OPA265BW4k7pYearPlan -SourcePst 'C:\mail\test.pst' -YearCounts @{'2025'=5}); $x[0].ArchivePstCreated | Should -BeFalse
  }
  It 'plan no capacity assumptions' {
    $x=@(New-OPA265BW4k7pYearPlan -SourcePst 'C:\mail\test.pst' -YearCounts @{'2025'=5}); $x[0].ArchivePstCapacityValidated | Should -BeFalse
  }
  It 'partial plan counts observed only' {
    $x=@(New-OPA265BW4k7pYearPlan -SourcePst 'C:\mail\test.pst' -YearCounts @{'2025'=5}); $x[0].Coverage | Should -BeExactly 'PartialObservedOnly'
  }
  It 'complete plan requires explicit complete' {
    $x=@(New-OPA265BW4k7pYearPlan -SourcePst 'C:\mail\test.pst' -YearCounts @{'2025'=5} -ScanComplete $true); $x[0].Coverage | Should -BeExactly 'CompleteObservedMailItems'
  }
  It 'relative PST cannot plan' {
    {Get-OPA265BW4k7pArchivePlanName -SourcePst 'relative.pst' -Year 2025} | Should -Throw
  }
  It 'non PST cannot plan' {
    {Get-OPA265BW4k7pArchivePlanName -SourcePst 'C:\mail\test.txt' -Year 2025} | Should -Throw
  }
  It 'year 1980 invalid' {
    {Get-OPA265BW4k7pArchivePlanName -SourcePst 'C:\mail\test.pst' -Year 1980} | Should -Throw
  }
  It 'year 2101 invalid' {
    {Get-OPA265BW4k7pArchivePlanName -SourcePst 'C:\mail\test.pst' -Year 2101} | Should -Throw
  }
  It 'negative observed year count rejected' {
    {New-OPA265BW4k7pYearPlan -SourcePst 'C:\mail\test.pst' -YearCounts @{'2025'=-1}} | Should -Throw
  }
  It 'default maximum scan only 5000' {
    (Assert-OPA265BW4k7pReadOnlyLimits).MaxTotalItems | Should -Be 5000
  }
  It 'explicit bounded maximum scan 50000' {
    (Assert-OPA265BW4k7pReadOnlyLimits -MaxTotalItems 50000).MaxTotalItems | Should -Be 50000
  }
  It 'unsafe folder maximum rejected' {
    {Assert-OPA265BW4k7pReadOnlyLimits -MaxFolders 20001} | Should -Throw
  }
  It 'unsafe attachment maximum rejected' {
    {Assert-OPA265BW4k7pReadOnlyLimits -MaxAttachmentsPerMail 201} | Should -Throw
  }
  It 'empty folder exact count zero' {
    $f=New-BW4k7pFakeFolder; $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 100; $r.ScannedItems | Should -Be 0; $r.FullyScanned | Should -BeTrue
  }
  It 'single Inbox mail year 2023' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 100; $r.YearCounts['2023'] | Should -Be 1
  }
  It 'single SentMail year 2024' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'SentItems' -MaxItems 100; $r.YearCounts['2024'] | Should -Be 1
  }
  It 'SentMail fallback explicitly tracked' {
    $m=New-BW4k7pFakeMail -Sent ([datetime]'0001-01-01'); $f=New-BW4k7pFakeFolder -Messages @($m); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'SentItems' -MaxItems 100; $r.SentOrReceivedFallbackObserved | Should -Be 1
  }
  It 'two mails same year count two' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail),(New-BW4k7pFakeMail)); (Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 100).YearCounts['2023'] | Should -Be 2
  }
  It 'two mails size metadata sums' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail),(New-BW4k7pFakeMail)); (Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 100).MailSizeObservedBytes | Should -Be 2000
  }
  It 'bounded limit marks partial' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail),(New-BW4k7pFakeMail)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 1; $r.FullyScanned | Should -BeFalse; $r.PartialReason | Should -BeExactly 'BoundedLimitReached'
  }
  It 'bounded partial has no inflated count' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail),(New-BW4k7pFakeMail)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 1; $r.YearCounts['2023'] | Should -Be 1
  }
  It 'nonmail metadata tracked' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail -Class 48)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 10; $r.NonMailObserved | Should -Be 1
  }
  It 'unknown dates accounted' {
    $m=New-BW4k7pFakeMail -Received ([datetime]'0001-01-01') -Sent ([datetime]'0001-01-01'); $f=New-BW4k7pFakeFolder -Messages @($m); (Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 10).MailDateUnavailableObserved | Should -Be 1
  }
  It 'attachment data not read by default' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail -AttachCount 2)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 10; $r.AttachmentMetadataInspected | Should -BeFalse
  }
  It 'attachment metadata count explicit' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail -AttachCount 2)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 10 -InspectAttachments; $r.AttachmentCountObserved | Should -Be 2
  }
  It 'attachment size summary is approximate' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail -AttachCount 2)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 10 -InspectAttachments; $r.AttachmentSizeObservedBytes | Should -Be 202; $r.MessageBodiesOrAttachmentPayloadsRead | Should -BeFalse
  }
  It 'attachment excess cap marks incomplete' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail -AttachCount 3)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 10 -MaxAttachmentsPerMail 2 -InspectAttachments; $r.AttachmentSizeEvidenceComplete | Should -BeFalse
  }
  It 'attachment partial scan not full coverage' {
    $f=New-BW4k7pFakeFolder -Messages @((New-BW4k7pFakeMail),(New-BW4k7pFakeMail)); $r=Get-OPA265BW4k7pFolderItems -Folder $f -Role 'Inbox' -MaxItems 1 -InspectAttachments; $r.AttachmentSizeEvidenceComplete | Should -BeFalse
  }
  It 'controller exact POP3 DeliveryStore resolver' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'Get-OPA265BW4cPop3Store'
  }
  It 'controller root folder scoped' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'GetRootFolder\('
  }
  It 'controller never reads other account mail stores' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'OtherImapOrPop3StoresRead=\$false'
  }
  It 'controller Outbox strictly not sent' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'OutboxNeverEquivalentToSentItems=\$true'
  }
  It 'controller year scan not implicit' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'Pop3FolderTopologyIdentifiedYearScanNotRequested'
  }
  It 'controller partial year scan no complete claim' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'Pop3BoundedPartialYearInventoryNoFullCoverageClaim'
  }
  It 'controller no archive creation' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'ProposedArchiveFilesCreated=\$false'
  }
  It 'controller no production writer' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'WriterPermit=\$false'
  }
  It 'controller no production-ready' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'ProductionReady=\$false'
  }
  It 'controller WhatIf no Outlook reads' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'WhatIfNoOutlookAccessNoPstChanges'
  }
  It 'controller protects attachment scan explicit' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Match 'InspectAttachmentMetadata -and -not \$ScanYears'
  }
  It 'controller no Move Save Delete Create PST' {
    $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') -Raw -Encoding UTF8; $s | Should -Not -Match '[.](Move|Save|Delete|Send|SetProperty|AddStoreEx|AddStore)[ ]*[(]'
  }
}
