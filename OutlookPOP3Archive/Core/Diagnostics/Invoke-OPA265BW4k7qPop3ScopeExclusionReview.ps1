#requires -Version 5.1
# BW4k7q uses BW4k7p uniquely identified POP3 DeliveryStore folder-only inventory.
# Excludes reserved test folders IN MEMORY; never deletes/detaches anything.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst',
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7q requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7qPop3ScopeExclusionPolicy265.ps1')
$p=Get-OPA265BW4k7qScopePolicy
$expected=[IO.Path]::GetFullPath([string]$p.ExpectedSourcePst)
$actual=[IO.Path]::GetFullPath($SourcePst)
if($ExpectedProfileName -cne [string]$p.ExpectedProfileName -or
   -not [string]::Equals($actual,$expected,[StringComparison]::OrdinalIgnoreCase)){
    throw 'BW4k7q wrong profile or wrong source POP3 PST. No other store can be scanned.'
}
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7q.WhatIf.1'
        Status='WhatIfNoOutlookContactNoMailReadNoPstMutation'
        PolicyId=[string]$p.PolicyId
        ExpectedSourcePst=[string]$p.ExpectedSourcePst
        NoTestFoldersDeleted=$true
        NoTestPstsDetachedOrDeleted=$true
        WriterPermit=$false
        ProductionReady=$false
    }
}
$stage='Original BW4k7p full POP3 folder-only read-only inventory'
try{
    $args=@{SourcePst=$SourcePst;ExpectedProfileName=$ExpectedProfileName}
    $base=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7pPop3FolderScopeInventory.ps1') @args
    $stage='POP3-SCOPE-001 exact folder roles / default SentMail and Outbox / reserved tests'
    $decision=Get-OPA265BW4k7qScopeDecision -Inventory $base
    if([bool]$decision.WriterPermit -or [bool]$decision.ProductionReady -or
       [bool]$decision.AutomaticRetryAllowed -or
       -not [bool]$decision.Unknown0x00010000StillBlocked -or
       -not [bool]$decision.NoTestFoldersDeleted -or
       -not [bool]$decision.NoTestArchivePstsDetachedOrDeleted){
        throw 'BW4k7q policy attempted unsafe writer/metadata waiver.'
    }
    $inboxRows=@($decision.FinalFolderDecisions |
        Where-Object {$_.PreviousBW4k7pRole -ceq 'Inbox'})
    if($inboxRows.Count -ne 1){throw 'BW4k7q missing unique POP3 Inbox.'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7q.LivePop3FolderScopeExclusionReview.1'
        Status=[string]$decision.Status
        PolicyId=[string]$decision.PolicyId
        SourcePst=[string]$decision.SourcePst
        SourcePstLengthBytes=[long]$base.SourcePstLengthBytes
        Pop3StoreVerified=$true
        ImapStoreItemsInspected=$false
        InboxDefaultFolderEntryId=[string]$decision.InboxEntryId
        SentItemsDefaultFolderEntryId=[string]$decision.SentItemsEntryId
        OutboxDefaultFolderEntryId=[string]$decision.OutboxEntryId
        SentItemsIncludedEvenWhenEmpty=[bool]$decision.SentItemsIncludedEvenWhenEmpty
        CurrentSentItemsCount=[long]$decision.CurrentSentItemsCount
        HistoricSentItemsCoverageProven=$false
        PreviousBW4k7pFolderCount=22
        CurrentFolderCount=[int]$decision.FoldersObserved
        PreviousBW4k7pInboxCount=26605
        CurrentInboxCount=[long]$inboxRows[0].ItemsCount
        PreviousBW4k7pSentItemsCount=0
        PreviousBW4k7pTestMailCandidates=2
        CurrentReservedTestRootFolders=[int]$decision.ReservedTestRootFolders
        CurrentReservedTestFolderItemsQuarantined=[long]$decision.ReservedTestFolderItemsQuarantined
        CurrentSpecialSettingsFoldersExcluded=[int]$decision.SpecialOutlookSettingsFoldersExcluded
        SpecialSettingsFolderReviewCount=[int]$decision.SpecialSettingsFolderReviewCount
        ProposedScopeItemCount=[long]$decision.ScopeIncludedMailCandidatesObserved
        ExcludedScopeItemCount=[long]$decision.ScopeExcludedItemsObserved
        TotalFolderItemsReconciled=[bool]$decision.TotalFolderItemsReconciled
        ProposedFolderScope=@($decision.FinalFolderDecisions)
        FolderDispositionCounts=$decision.FolderDispositionCounts
        ProposedScopeDoesNotIncludeTestFolders=$true
        AllOriginalTestFoldersAndPstsRetained=$true
        NoUserMailOrAttachmentContentRead=$true
        YearBreakdownScanned=$false
        SourceMailItemsMoved=$false
        PstFilesCreatedOrDeleted=$false
        OriginalBW4k7lEvidenceOrBW4k7mClaimRewritten=$false
        HistoricUnknownRaw0x00010000StillBlocked=$true
        SentAndUserFolderProductionIntegrityProven=$false
        PhysicalPstDurabilityProven=$false
        ArchiveResumeAutoEnabled=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='ReviewProposedFolderScopeAndSentTestCases;DoNotDeleteTestsOrEnableWriter;NoMove'
    }
}catch{
    throw ('BW4k7q READ-ONLY STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Outlook Move, PST delete, test folder delete, journal or Claim writes.')
}
