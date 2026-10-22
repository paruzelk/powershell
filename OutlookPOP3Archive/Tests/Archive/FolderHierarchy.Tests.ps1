# FIX10a: behavioral tests for full-depth POP3 folder enumeration and SentOn.
BeforeAll {
    . "$PSScriptRoot/../../Core/Runtime/ComManager.ps1"
    . "$PSScriptRoot/../../Core/Archive/SystemFolders.ps1"
    . "$PSScriptRoot/../../Core/Archive/ArchiveGrouping.ps1"
    . "$PSScriptRoot/../../Core/Archive/ArchiveSelector.ps1"
    . "$PSScriptRoot/../../Core/Archive/ArchivePlanner.ps1"

    function New-OPATestFolder {
        param([string]$Name,[string]$Id,[string]$Path,[int]$Count=0,[object[]]$Children=@(),[int]$ItemType=0)
        [pscustomobject]@{
            Name=$Name;EntryID=$Id;FolderPath=$Path;DefaultItemType=$ItemType
            Items=[pscustomobject]@{Count=$Count};Folders=$Children
        }
    }
}

Describe 'FIX10a recursive POP3 folder policy' {
    It 'includes Sent Items and arbitrary nested user mail folders' {
        $deep = New-OPATestFolder -Name '2021' -Id 'DEEP' -Path '\PST\Sent Items\Clients\2021' -Count 4
        $clients = New-OPATestFolder -Name 'Clients' -Id 'CLIENTS' -Path '\PST\Sent Items\Clients' -Children @($deep)
        $sent = New-OPATestFolder -Name 'Sent Items' -Id 'SENT' -Path '\PST\Sent Items' -Count 3 -Children @($clients)
        $inboxChild = New-OPATestFolder -Name 'SubA' -Id 'SUBA' -Path '\PST\Inbox\SubA' -Count 2
        $inbox = New-OPATestFolder -Name 'Inbox' -Id 'INBOX' -Path '\PST\Inbox' -Count 1 -Children @($inboxChild)
        $root = New-OPATestFolder -Name 'PST' -Id 'ROOT' -Path '\PST' -Children @($sent,$inbox)
        $map = @{ 'SENT'='SentMail' }
        $paths = @(Get-OPAEligiblePop3MailFolders -RootFolder $root -WellKnownEntryIdMap $map | ForEach-Object { $_.FolderPath })
        $paths.Count | Should -Be 4
        $paths | Should -Contain '\PST\Sent Items'
        $paths | Should -Contain '\PST\Sent Items\Clients\2021'
        $paths | Should -Contain '\PST\Inbox'
        $paths | Should -Contain '\PST\Inbox\SubA'
    }

    It 'prunes descendants of excluded system folders but preserves similarly named custom folders' {
        $outChild = New-OPATestFolder -Name 'Secret' -Id 'OUTCHILD' -Path '\PST\Outbox\Secret' -Count 8
        $outbox = New-OPATestFolder -Name 'Outbox' -Id 'OUTBOX' -Path '\PST\Outbox' -Count 1 -Children @($outChild)
        $junkChild = New-OPATestFolder -Name 'Nested' -Id 'JUNKCHILD' -Path '\PST\Junk\Nested' -Count 2
        $junk = New-OPATestFolder -Name 'Junk' -Id 'JUNK' -Path '\PST\Junk' -Count 1 -Children @($junkChild)
        $draftChild = New-OPATestFolder -Name 'Nested' -Id 'DRAFTCHILD' -Path '\PST\Drafts\Nested' -Count 2
        $drafts = New-OPATestFolder -Name 'Drafts' -Id 'DRAFT' -Path '\PST\Drafts' -Count 1 -Children @($draftChild)
        $deleteChild = New-OPATestFolder -Name 'Nested' -Id 'DELCHILD' -Path '\PST\Deleted Items\Nested' -Count 2
        $deleted = New-OPATestFolder -Name 'Deleted Items' -Id 'DELETED' -Path '\PST\Deleted Items' -Count 1 -Children @($deleteChild)
        $userDraft = New-OPATestFolder -Name 'Drafts' -Id 'USERDRAFT' -Path '\PST\Inbox\Drafts' -Count 5
        $inbox = New-OPATestFolder -Name 'Inbox' -Id 'INBOX' -Path '\PST\Inbox' -Children @($userDraft)
        $root = New-OPATestFolder -Name 'PST' -Id 'ROOT' -Path '\PST' -Children @($outbox,$junk,$drafts,$deleted,$inbox)
        $map = @{'OUTBOX'='Outbox';'JUNK'='Junk';'DRAFT'='Drafts';'DELETED'='DeletedItems'}
        $paths = @(Get-OPAEligiblePop3MailFolders -RootFolder $root -WellKnownEntryIdMap $map | ForEach-Object { $_.FolderPath })
        $paths.Count | Should -Be 1
        $paths[0] | Should -Be '\PST\Inbox\Drafts'
        $optInPaths = @(Get-OPAEligiblePop3MailFolders -RootFolder $root -WellKnownEntryIdMap $map -ArchiveJunk -ArchiveDrafts -ArchiveDeletedItems | ForEach-Object { $_.FolderPath })
        $optInPaths | Should -Contain '\PST\Junk\Nested'
        $optInPaths | Should -Contain '\PST\Drafts\Nested'
        $optInPaths | Should -Contain '\PST\Deleted Items\Nested'
        $optInPaths | Should -Not -Contain '\PST\Outbox\Secret'
    }

    It 'recognizes the official Sent root and descendants as sent-like' {
        $sentFolder = [pscustomobject]@{ FolderPath='\PST\Sent Items' }
        $store = [pscustomobject]@{ SentFolder=$sentFolder }
        $store | Add-Member -MemberType ScriptMethod -Name GetDefaultFolder -Value { param([int]$Id) if ($Id -eq 5) { return $this.SentFolder } else { return $null } }
        $map = @{'SENT'='SentMail'}
        Test-OPASentLikeFolder -Name 'Clients' -EntryID 'NESTED' -FolderPath '\PST\Sent Items\Clients' -WellKnownEntryIdMap $map -Store $store | Should -BeTrue
        Test-OPASentLikeFolder -Name 'Drafts' -EntryID 'CUSTOM' -FolderPath '\PST\Inbox\Drafts' -WellKnownEntryIdMap $map -Store $store | Should -BeFalse
        Test-OPASentLikeFolder -Name 'Renamed' -EntryID 'SENT' -FolderPath '\PST\Renamed' -WellKnownEntryIdMap $map -Store $store | Should -BeTrue
    }

    It 'selects old sent mail in nested Sent Items folder by SentOn, not ReceivedTime' {
        $sentFolder = [pscustomobject]@{ FolderPath='\PST\Sent Items' }
        $store = [pscustomobject]@{SentFolder=$sentFolder;StoreID='TEST-STORE'}
        $store | Add-Member -MemberType ScriptMethod -Name GetDefaultFolder -Value {param([int]$I) if ($I -eq 5) {return $this.SentFolder}; return $null }
        $store | Add-Member -MemberType ScriptMethod -Name GetRootFolder -Value {return $null}
        $mail = [pscustomobject]@{
            Class=43;EntryID='SENT-OLD';Subject='sent mail';
            ReceivedTime=[datetime]'2026-01-01';SentOn=[datetime]'2020-06-01';
            CreationTime=[datetime]'2026-01-01';SenderEmailAddress='sender@example.com';Size=100
        }
        $items = [pscustomobject]@{ Count=1; Rows=@($mail) }
        $items | Add-Member -MemberType ScriptMethod -Name Item -Value {param([int]$I) $this.Rows[$I-1]}
        $items | Add-Member -MemberType ScriptMethod -Name Sort -Value {param($A,$B) throw 'Sorting disabled in mock'}
        $items | Add-Member -MemberType ScriptMethod -Name Restrict -Value {param($Q) throw 'Restrict disabled in mock'}
        $folder = [pscustomobject]@{
            Name='Clients';EntryID='SENT-NESTED';FolderPath='\PST\Sent Items\Clients';
            Store=$store; Items=$items
        }
        $candidate = @(Get-OPAArchiveCandidates -SourceFolder $folder -Limit 10 -OlderThanCutoff ([datetime]'2024-01-01'))
        $candidate.Count | Should -Be 1
        $candidate[0].EntryID | Should -Be 'SENT-OLD'
        $candidate[0].ArchiveDate | Should -Be ([datetime]'2020-06-01')
    }

    It 'preserves full source hierarchy in the archive target path' {
        $path = Get-OPAArchiveTargetPath -ReceivedTime ([datetime]'2021-03-04') -SourceFolderName '2021' -SourceFolderPath '\PST\Sent Items\Clients\2021' -Grouping YearQuarter
        $path | Should -Be '2021\Q1\Sent Items\Clients\2021'
    }
}
