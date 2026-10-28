#requires -Version 5.1
# BW4c opt-in LIVE MAPI read-only dual-path witness review. No PST/journal/claim writes.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
    [string]$Transaction='',
    [Parameter(Mandatory=$true)][string]$FolderEntryId,
    [Parameter(Mandatory=$true)][string]$CandidateEntryId,
    [Parameter(Mandatory=$true)][string]$ExpectedProfileName,
    [ValidateRange(1,5000)][int]$MaxFolderItems=1000,
    [switch]$Review,
    [switch]$ConfirmExistingOutlookReadOnly
)
$ErrorActionPreference='Stop'
if (-not $Review -or -not $ConfirmExistingOutlookReadOnly -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4c requires -Review and -ConfirmExistingOutlookReadOnly under Windows PowerShell 5.1 STA.'
}
if ([string]::IsNullOrWhiteSpace($FolderEntryId) -or
    [string]::IsNullOrWhiteSpace($CandidateEntryId) -or
    [string]::IsNullOrWhiteSpace($ExpectedProfileName)) {
    throw 'BW4c requires exact folder, item and Outlook profile identities.'
}
foreach($file in @('../Worker/Live3SyntheticScope.ps1','../Worker/BW3OneShotProtocol265.ps1',
    '../Worker/BW3bIndependentAudit265.ps1','../Worker/BW3dSyntheticSizeEvidence265.ps1',
    '../Worker/BW3eSyntheticBodyTailEvidence265.ps1','../Worker/BW3gManualSizeAcceptance265.ps1',
    '../Worker/BW3hIndependentEvidenceChain265.ps1','../Worker/BW3iJournalResolutionPreflight265.ps1',
    '../Worker/BW3jResolutionDesign265.ps1','../Worker/WorkerProtocol.ps1',
    '../Archive/OperationJournal.ps1','../Worker/BW4aHistoricalIntentIsolation265.ps1',
    '../Worker/BW4aHistoricalFenceReadOnly265.ps1','../Worker/BW4bPerItemFence265.ps1',
    '../Worker/BW4cOutlookReadOnlyCapture265.ps1')) {
    . (Join-Path $PSScriptRoot $file)
}
$stage='Pre-COM immutable historical evidence preflight'
$app=$null
$ns=$null
try {
    $pre=Invoke-OPA265BW4aHistoricalFenceReview -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode $Mode -Transaction $Transaction
    if (-not $pre.SevenHistoricalEvidenceHashesUnchanged -or
        $pre.HistoricJournalEventCount -ne 1 -or $pre.HistoricJournalPhase -cne 'Intent') {
        throw 'BW4c historical preflight refused.'
    }
    $p=Get-OPA265BW3hPinnedChain
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $snap=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $p
    $journal=Read-OPAOperationJournal -Path ([string]$paths.JournalPath)
    if ($journal.TrailingPartial -or @($journal.Events).Count -ne 1) { throw 'BW4c historical journal not one complete Intent.' }
    $fence=Get-OPA265BW4aKnownHistoricalFence -Pinned $p -Paths $paths -Snapshot $snap -Intent $journal.Events[0]
    if ([string]::Equals($CandidateEntryId,[string]$fence.SourceEntryId,[StringComparison]::Ordinal) -or
        [string]::Equals($CandidateEntryId,[string]$fence.DestinationEntryId,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'BW4c explicitly blocks direct readback of historical EntryID candidates.'
    }
    $stage='Get existing Outlook session ONLY; no new Outlook profile or PST mount'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'BW4c requires Outlook to already be running.' }
    $ns=$app.GetNamespace('MAPI')
    if ([string]$ns.CurrentProfileName -cne $ExpectedProfileName) { throw 'BW4c: active Outlook profile is not the explicitly selected profile.' }
    $stage='Read exact candidate using two Outlook COM lookup paths'
    $readback=Get-OPA265BW4cDualReadback -Namespace $ns -SourcePst $SourcePst -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -MaxFolderItems $MaxFolderItems
    $stage='Apply BW4b permanent historical item fence'
    $decision=Get-OPA265BW4bPerItemDecision -Fence $fence -Mode $Mode -TransactionId $Transaction -SourcePst $SourcePst -Primary $readback.Primary -Independent $readback.Independent
    $stage='Post-COM immutable historical evidence and journal recheck'
    $post=Invoke-OPA265BW4aHistoricalFenceReview -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode $Mode -Transaction $Transaction
    if (-not $post.SevenHistoricalEvidenceHashesUnchanged -or
        $post.HistoricJournalEventCount -ne 1 -or $post.HistoricJournalPhase -cne 'Intent' -or
        $decision.CanDispatchWorker -or $decision.CanInvokeMailMove -or $decision.CanWriteHistoricalJournal -or
        $decision.CanCreateHistoricalClaim) {
        throw 'BW4c postflight historical journal or no-dispatch invariant failed.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4c.OutlookDualPathPerItemReadOnly.1'
        Status='OutlookReadOnlyDualPathEvidenceReviewedNoWorkerDispatch'
        Mode=$Mode
        CandidateStatus=$decision.Status
        HistoricalMatches=$decision.HistoricalMatches
        SourceStoreId=$readback.Primary.SourceStoreId
        CandidateEntryId=$readback.Primary.SourceEntryId
        InternetMessageId=$readback.Primary.InternetMessageId
        SearchKeySha256=$readback.Primary.SearchKeySha256
        ContentFieldFingerprintSha256=$readback.Primary.ContentSha256
        FolderItemsScanned=$readback.FolderItemsScanned
        SameOutlookSession=$true
        TwoSeparateOutlookReadPaths=$true
        IndependentlyAuthenticatedExternalEvidence=$false
        FullMAPIContentByteEqualityVerified=$false
        SourcePstUnmodifiedAtByteLevelProven=$false
        SevenHistoricalEvidenceHashesUnchanged=$true
        HistoricJournalEventCount=1
        HistoricJournalPhase='Intent'
        HistoricalJournalChanged=$false
        HistoricalClaimCreated=$false
        HistoricRetryBlocked=$true
        WorkerDispatchAllowed=$false
        OutlookComAccessExecuted=$true
        OutlookMoveExecuted=$false
        ArchiveResumeIntegrationActivated=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='NoMoveConsent;IndependentExternalEvidenceAndSeparateSyntheticPermitNeeded'
    }
} catch {
    throw ('BW4c FAIL CLOSED at ['+$stage+']: '+[string]$_.Exception.Message+'. No MailItem.Move, journal writer, claim or Worker dispatch.')
} finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
