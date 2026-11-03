#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7qPop3ScopeExclusionPolicy265.ps1')
    function New-BW4k7qFakeFolderRow {
        param([string]$Name,[string]$Role='UserMail',[long]$Count=0,
              [string]$EntryId='',[string]$Parent='\',
              [string]$ParentRole='Root')
        $path=if($Name -ceq '\'){'\'}
              elseif($Parent -ceq '\'){'\' + $Name}
              else{$Parent + '\' + $Name}
        if(-not $EntryId){$EntryId='entry-'+$path}
        $level=if($path -ceq '\'){0}else{@($path.Trim('\').Split('\')).Count}
        return [pscustomobject][ordered]@{
            FolderPath=$path;FolderEntryId=$EntryId;Role=$Role;Depth=$level
            ParentRole=$ParentRole
            ItemsCount=if($Role -ceq 'Root'){$null}else{[long]$Count}
            IncludedInFutureScope=($Role -in @('Inbox','SentItems','UserMail'))
        }
    }
    function New-BW4k7qFakeInventory {
        $l=New-Object 'System.Collections.Generic.List[object]'
        $l.Add((New-BW4k7qFakeFolderRow -Name '\' -Role 'Root' -EntryId 'root-id'))
        $l.Add((New-BW4k7qFakeFolderRow -Name 'Удаленные' -Role 'SystemExcluded'))
        $l.Add((New-BW4k7qFakeFolderRow -Name 'Входящие' -Role 'Inbox' -EntryId 'inbox-id' -Count 26605))
        $l.Add((New-BW4k7qFakeFolderRow -Name 'Исходящие' -Role 'OutboxExcluded' -EntryId 'outbox-id'))
        $l.Add((New-BW4k7qFakeFolderRow -Name 'Отправленные' -Role 'SentItems' -EntryId 'sent-id'))
        $l.Add((New-BW4k7qFakeFolderRow -Name 'Нежелательная почта' -Role 'SystemExcluded'))
        $l.Add((New-BW4k7qFakeFolderRow -Name 'Настройка действий беседы'))
        $l.Add((New-BW4k7qFakeFolderRow -Name 'Настройка быстрых действий'))
        $l.Add((New-BW4k7qFakeFolderRow -Name 'Черновики' -Role 'SystemExcluded' -Count 2))
        foreach($t in @(
            '586e0c1c12e949f5af7435a9bce9d05b',
            'feec2cd75bb2461fbde3599c8020329d',
            '1e9260165760446f9c5c14cd850dad11',
            '77854a93ecfd42c7b58e2948fe9afa88',
            'c7e87652e50143ffb6225dcd87aee438',
            'e2399ba138e948e8bf43d39cc1c19edb',
            'a7b51427749443f4bc9664915f6bee7e')){
            $c=if($t -in @('77854a93ecfd42c7b58e2948fe9afa88','e2399ba138e948e8bf43d39cc1c19edb')){1}else{0}
            $l.Add((New-BW4k7qFakeFolderRow -Name ('OPA264-LIVE3-'+$t) -Count $c))
        }
        foreach($name in @('Календарь','Контакты','Дневник','Заметки','Задачи','RSS-каналы')){
            $l.Add((New-BW4k7qFakeFolderRow -Name $name -Role 'SystemExcluded'))
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7p.Pop3FolderScopeReadOnlyInventory.1'
            Status='Pop3FolderTopologyIdentifiedYearScanNotRequested'
            ExpectedProfileName='Outlook'
            SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
            SourcePstLengthBytes=[long]7674192896
            ExactPop3DeliveryStoreVerified=$true;ScopeRestrictedToOnePop3Store=$true
            SentItemsResolvedInThisPop3Store=$true;OutboxResolvedInThisPop3Store=$true
            OutboxNeverEquivalentToSentItems=$true
            DefaultStoreFolderNamesNotUsedForIdentity=$true
            OtherImapOrPop3StoresRead=$false
            YearScanRequested=$false;YearScanComplete=$false
            ProposedArchiveFilesCreated=$false
            PstCapacityAndYearRolloverValidated=$false
            ProductionSentCoverageProven=$false
            FullProductionSemanticIntegrityProven=$false
            OutlookMoveExecuted=$false;ClaimOrJournalWritten=$false
            AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
            RootFolderEntryId='root-id';InboxDefaultFolderEntryId='inbox-id'
            SentItemsDefaultFolderEntryId='sent-id';OutboxDefaultFolderEntryId='outbox-id'
            FolderCount=[int]$l.Count
            EligibleFolderItemsObserved=[long]26607
            ExcludedFolderItemsObserved=[long]2
            FolderInventory=@($l.ToArray())
        }
    }
    function Get-BW4k7qFakeDecision {
        param($Inventory)
        if($null -eq $Inventory){$Inventory=New-BW4k7qFakeInventory}
        return (Get-OPA265BW4k7qScopeDecision -Inventory $Inventory)
    }
}
Describe 'BW4k7q strict original POP3 22 folder profile scope no-test-deletion policy' {
    It 'policy identifier versioned' {
        (Get-OPA265BW4k7qScopePolicy).PolicyId | Should -BeExactly 'POP3-SCOPE-001-BW4k7q-v1'
    }
    It 'policy pins original POP3 PST' {
        (Get-OPA265BW4k7qScopePolicy).ExpectedSourcePst | Should -BeExactly 'C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
    }
    It 'profile pinned' {
        (Get-OPA265BW4k7qScopePolicy).ExpectedProfileName | Should -BeExactly 'Outlook'
    }
    It 'POP3 Inbox six and Sent five pinned' {
        $p=Get-OPA265BW4k7qScopePolicy; $p.RequiredDefaultFolderTypes | Should -Contain 6; $p.RequiredDefaultFolderTypes | Should -Contain 5
    }
    It 'Outbox four distinct' {
        (Get-OPA265BW4k7qScopePolicy).OutboxDefaultFolderType | Should -Be 4
    }
    It 'original tests retained on disk' {
        (Get-OPA265BW4k7qScopePolicy).TestFoldersRetainedOnDisk | Should -BeTrue
    }
    It 'original Claim not rewritten' {
        (Get-OPA265BW4k7qScopePolicy).HistoricIrreversibleClaimRewritten | Should -BeFalse
    }
    It 'unknown old 0x10000 not waived' {
        (Get-OPA265BW4k7qScopePolicy).PreviousUnknownMapi0x00010000Waived | Should -BeFalse
    }
    It 'exact operator 22 folder fixture accepted' {
        (Assert-OPA265BW4k7qInventoryContract -Inventory (New-BW4k7qFakeInventory)) | Should -BeTrue
    }
    It 'operator profile count and role accepted' {
        $v=New-BW4k7qFakeInventory; $v.FolderCount | Should -Be 22; $v.EligibleFolderItemsObserved | Should -Be 26607
    }
    It 'original 22 folders read-only decision' {
        (Get-BW4k7qFakeDecision).FoldersObserved | Should -Be 22
    }
    It 'exact seven OPA264 LIVE3 root quarantined' {
        (Get-BW4k7qFakeDecision).ReservedTestRootFolders | Should -Be 7
    }
    It 'two LIVE3 mails quarantined not destroyed' {
        $r=Get-BW4k7qFakeDecision; $r.ReservedTestFolderItemsQuarantined | Should -Be 2; $r.NoTestFoldersDeleted | Should -BeTrue
    }
    It 'two special Outlook settings excluded' {
        (Get-BW4k7qFakeDecision).SpecialOutlookSettingsFoldersExcluded | Should -Be 2
    }
    It 'zero special folder review on empty settings' {
        (Get-BW4k7qFakeDecision).SpecialSettingsFolderReviewCount | Should -Be 0
    }
    It 'real proposed scope excludes two LIVE3 emails' {
        (Get-BW4k7qFakeDecision).ScopeIncludedMailCandidatesObserved | Should -Be 26605
    }
    It 'eligible total minus quarantined recomputed' {
        (Get-BW4k7qFakeDecision).ScopeExcludedItemsObserved | Should -Be 4
    }
    It 'full item coverage reconciles' {
        (Get-BW4k7qFakeDecision).TotalFolderItemsReconciled | Should -BeTrue
    }
    It 'empty Sent in proposed scope' {
        $r=Get-BW4k7qFakeDecision; $r.CurrentSentItemsCount | Should -Be 0; $r.SentItemsIncludedEvenWhenEmpty | Should -BeTrue
    }
    It 'empty Sent historical completeness never proved' {
        (Get-BW4k7qFakeDecision).HistoricSentItemsCoverageProven | Should -BeFalse
    }
    It 'nonempty Sent fixture 37 included in scope' {
        $v=New-BW4k7qFakeInventory; $sent=@($v.FolderInventory | Where-Object Role -eq 'SentItems')[0]; $sent.ItemsCount=[long]37; $v.EligibleFolderItemsObserved=26644; $r=Get-BW4k7qFakeDecision $v; $r.CurrentSentItemsCount | Should -Be 37; $r.ScopeIncludedMailCandidatesObserved | Should -Be 26642
    }
    It 'Sent items never confused with Outbox' {
        $r=Get-BW4k7qFakeDecision; $s=@($r.FinalFolderDecisions | Where-Object PreviousBW4k7pRole -eq 'SentItems')[0]; $o=@($r.FinalFolderDecisions | Where-Object PreviousBW4k7pRole -eq 'OutboxExcluded')[0]; $s.IncludedInProposedPop3Scope | Should -BeTrue; $o.IncludedInProposedPop3Scope | Should -BeFalse
    }
    It 'all seven test root paths marked reserved' {
        $r=Get-BW4k7qFakeDecision; @($r.FinalFolderDecisions | Where-Object RootOfReservedTestFolder).Count | Should -Be 7
    }
    It 'test descendants inherited exclusion' {
        $v=New-BW4k7qFakeInventory; $t=@($v.FolderInventory | Where-Object {$_.FolderPath -like '\OPA264-LIVE3-77854*'})[0]; $v.FolderInventory += @(New-BW4k7qFakeFolderRow -Name 'Nested' -Parent $t.FolderPath -ParentRole 'UserMail' -Count 3); $v.FolderCount++; $v.EligibleFolderItemsObserved+=3; $r=Get-BW4k7qFakeDecision $v; $r.ReservedTestFolderItemsQuarantined | Should -Be 5
    }
    It 'test descendants explicit disposition' {
        $v=New-BW4k7qFakeInventory; $t=@($v.FolderInventory | Where-Object {$_.FolderPath -like '\OPA264-LIVE3-77854*'})[0]; $v.FolderInventory += @(New-BW4k7qFakeFolderRow -Name 'Nested' -Parent $t.FolderPath -ParentRole 'UserMail' -Count 3); $v.FolderCount++; $v.EligibleFolderItemsObserved+=3; $r=Get-BW4k7qFakeDecision $v; @($r.FinalFolderDecisions | Where-Object {$_.InclusionReason -eq 'NestedUnderReservedTestFolder'}).Count | Should -Be 1
    }
    It 'known settings with one item always excluded and manual review' {
        $v=New-BW4k7qFakeInventory; $row=@($v.FolderInventory | Where-Object {$_.FolderPath -eq '\Настройка действий беседы'})[0]; $row.ItemsCount=[long]1; $v.EligibleFolderItemsObserved++; $r=Get-BW4k7qFakeDecision $v; $r.SpecialSettingsFolderReviewCount | Should -Be 1; $r.ScopeIncludedMailCandidatesObserved | Should -Be 26605
    }
    It 'nonempty special settings changes status' {
        $v=New-BW4k7qFakeInventory; $row=@($v.FolderInventory | Where-Object {$_.FolderPath -eq '\Настройка быстрых действий'})[0]; $row.ItemsCount=[long]1; $v.EligibleFolderItemsObserved++; (Get-BW4k7qFakeDecision $v).Status | Should -BeExactly 'ExactPop3ScopeReadOnlySpecialSettingsNonemptyManualReview'
    }
    It 'unknown user named similar settings remains user folder' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory += @(New-BW4k7qFakeFolderRow -Name 'Настройка других действий' -Count 4); $v.FolderCount++; $v.EligibleFolderItemsObserved+=4; (Get-BW4k7qFakeDecision $v).ScopeIncludedMailCandidatesObserved | Should -Be 26609
    }
    It 'user mail nested under inbox is included' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory += @(New-BW4k7qFakeFolderRow -Name 'Проекты' -Parent '\Входящие' -ParentRole 'Inbox' -Count 14); $v.FolderCount++; $v.EligibleFolderItemsObserved+=14; (Get-BW4k7qFakeDecision $v).ScopeIncludedMailCandidatesObserved | Should -Be 26619
    }
    It 'user mail nested under Sent is included' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory += @(New-BW4k7qFakeFolderRow -Name 'Проекты' -Parent '\Отправленные' -ParentRole 'SentItems' -Count 6); $v.FolderCount++; $v.EligibleFolderItemsObserved+=6; (Get-BW4k7qFakeDecision $v).ScopeIncludedMailCandidatesObserved | Should -Be 26611
    }
    It 'reserved test lookalike invalid hex not excluded blindly' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory += @(New-BW4k7qFakeFolderRow -Name 'OPA264-LIVE3-NOTHEX' -Count 1); $v.FolderCount++; $v.EligibleFolderItemsObserved++; (Get-BW4k7qFakeDecision $v).ScopeIncludedMailCandidatesObserved | Should -Be 26606
    }
    It 'reserved OPA265 BW4 fixture exact GUID pattern quarantined' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory += @(New-BW4k7qFakeFolderRow -Name 'OPA265-BW4k7l-d1a68868acf54c70860d5521e1ce2836' -Count 2); $v.FolderCount++; $v.EligibleFolderItemsObserved+=2; $r=Get-BW4k7qFakeDecision $v; $r.ReservedTestRootFolders | Should -Be 8; $r.ReservedTestFolderItemsQuarantined | Should -Be 4
    }
    It 'only POP3 store metadata in policy' {
        (Get-BW4k7qFakeDecision).ImapStoreItemsInspected | Should -BeFalse
    }
    It 'nothing deleted or detached' {
        $r=Get-BW4k7qFakeDecision; $r.NoTestFoldersDeleted | Should -BeTrue; $r.NoTestArchivePstsDetachedOrDeleted | Should -BeTrue
    }
    It 'PST capacity remains unverified' {
        (Get-BW4k7qFakeDecision).YearlyArchiveCapacityRolloverProven | Should -BeFalse
    }
    It 'message content integrity still unproven' {
        (Get-BW4k7qFakeDecision).FullInboxSentCustomFolderMessageContentIntegrityProven | Should -BeFalse
    }
    It 'PST physical durability still unproven' {
        (Get-BW4k7qFakeDecision).PhysicalPstDurabilityProven | Should -BeFalse
    }
    It 'no producer move in pure policy' {
        (Get-BW4k7qFakeDecision).NoOutlookMoveOrOtherWriter | Should -BeTrue
    }
    It 'historic raw MAPI bit remains blocked' {
        (Get-BW4k7qFakeDecision).Unknown0x00010000StillBlocked | Should -BeTrue
    }
    It 'no writer permission with matching folder scope' {
        $r=Get-BW4k7qFakeDecision; $r.WriterPermit | Should -BeFalse; $r.ProductionReady | Should -BeFalse
    }
    It 'wrong source PST rejected' {
        $v=New-BW4k7qFakeInventory; $v.SourcePst='C:\mail\other.pst'; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'wrong Outlook profile rejected' {
        $v=New-BW4k7qFakeInventory; $v.ExpectedProfileName='Different'; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'wrong Inventory schema rejected' {
        $v=New-BW4k7qFakeInventory; $v.Schema='Fake'; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'partial year scan cannot feed production scope validator' {
        $v=New-BW4k7qFakeInventory; $v.YearScanRequested=$true; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'forged production ready rejected' {
        $v=New-BW4k7qFakeInventory; $v.ProductionReady=$true; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'forged Move in inventory rejected' {
        $v=New-BW4k7qFakeInventory; $v.OutlookMoveExecuted=$true; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'forged journal claim rejected' {
        $v=New-BW4k7qFakeInventory; $v.ClaimOrJournalWritten=$true; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'unrelated IMAP mail read assertion rejected' {
        $v=New-BW4k7qFakeInventory; $v.OtherImapOrPop3StoresRead=$true; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'missing exact Sent default rejected' {
        $v=New-BW4k7qFakeInventory; $v.SentItemsResolvedInThisPop3Store=$false; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'Inbox and Sent same EntryID rejected' {
        $v=New-BW4k7qFakeInventory; $v.SentItemsDefaultFolderEntryId='inbox-id'; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'Sent row role forged rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[4].Role='UserMail'; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'Outbox row role forged rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[3].Role='SentItems'; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'duplicate path rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[6].FolderPath=$v.FolderInventory[7].FolderPath; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'duplicate EntryID rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[6].FolderEntryId=$v.FolderInventory[7].FolderEntryId; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'missing parent path rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[5].FolderPath='\Missing\Nested'; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'folder count mismatch rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderCount=21; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'item count tampered rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[2].ItemsCount=26604; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'eligible item count tampered rejected' {
        $v=New-BW4k7qFakeInventory; $v.EligibleFolderItemsObserved=26606; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'nonmail erroneously flagged in P rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[1].IncludedInFutureScope=$true; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'Sent erroneously unflagged in P rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[4].IncludedInFutureScope=$false; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'wrong root entry ID rejected' {
        $v=New-BW4k7qFakeInventory; $v.RootFolderEntryId='other-root'; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'root negative item count rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[0].ItemsCount=-1; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'negative Inbox item count rejected' {
        $v=New-BW4k7qFakeInventory; $v.FolderInventory[2].ItemsCount=-1; {Get-BW4k7qFakeDecision $v} | Should -Throw
    }
    It 'controller chains proven BW4k7p real inventory' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1'); $s | Should -Match 'Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1'
    }
    It 'controller has no Move Save Delete' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1'); $s | Should -Not -Match '[.](Move|Save|Delete|Send|SetProperty|AddStoreEx|AddStore)[ ]*[(]'
    }
    It 'controller WhatIf no Outlook access' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1'); $s | Should -Match 'WhatIfNoOutlookContactNoMailReadNoPstMutation'
    }
    It 'controller retains all original test PSTs' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1'); $s | Should -Match 'AllOriginalTestFoldersAndPstsRetained=\$true'
    }
    It 'controller SEM-001 unchanged' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1'); $s | Should -Match 'HistoricUnknownRaw0x00010000StillBlocked=\$true'
    }
    It 'controller no production permissions' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1'); $s | Should -Match 'WriterPermit=\$false'; $s | Should -Match 'ProductionReady=\$false'
    }
}
