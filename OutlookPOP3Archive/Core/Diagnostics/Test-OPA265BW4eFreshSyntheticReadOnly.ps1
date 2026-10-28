#requires -Version 5.1
# BW4e explicit read-only operator-pinned candidate preflight. No new PST, mail, claim or Worker Move.
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
    [Parameter(Mandatory=$true)][string]$CandidateReviewId,
    [Parameter(Mandatory=$true)][string]$ExpectedInternetMessageId,
    [Parameter(Mandatory=$true)][string]$ExpectedSearchKeySha256,
    [Parameter(Mandatory=$true)][string]$ExpectedContentFingerprintSha256,
    [ValidateRange(1,5000)][int]$MaxFolderItems=1000,
    [string]$HistoryRoot=([IO.Path]::GetTempPath()),
    [ValidateRange(1,512)][int]$MaxHistoryRuns=256,
    [switch]$Review,
    [switch]$ConfirmExistingOutlookReadOnly
)
$ErrorActionPreference='Stop'
if (-not $Review -or -not $ConfirmExistingOutlookReadOnly -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4e requires -Review and -ConfirmExistingOutlookReadOnly under Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4eFreshSyntheticCandidate265.ps1')
try {
    # Invalid candidate pins fail BEFORE the existing Outlook or journal inspection.
    [void](Assert-OPA265BW4eCandidatePins -CandidateReviewId $CandidateReviewId -HistoricalRunId $RunId -ExpectedCandidateEntryId $CandidateEntryId -ExpectedInternetMessageId $ExpectedInternetMessageId -ExpectedSearchKeySha256 $ExpectedSearchKeySha256 -ExpectedContentFingerprintSha256 $ExpectedContentFingerprintSha256)
    # BW4d performs seven original pinned historical SHA checks pre/post Outlook,
    # and snapshots all visible Live3/Live4 journal files before/after the read.
    $review=& (Join-Path $PSScriptRoot 'Test-OPA265BW4dHistoryReplayReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode $Mode -Transaction $Transaction -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -ExpectedProfileName $ExpectedProfileName -MaxFolderItems $MaxFolderItems -HistoryRoot $HistoryRoot -MaxHistoryRuns $MaxHistoryRuns -Review -ConfirmExistingOutlookReadOnly
    $result=Get-OPA265BW4eFreshCandidateDecision -Bw4dReview $review -CandidateReviewId $CandidateReviewId -HistoricalRunId $RunId -ExpectedCandidateEntryId $CandidateEntryId -ExpectedInternetMessageId $ExpectedInternetMessageId -ExpectedSearchKeySha256 $ExpectedSearchKeySha256 -ExpectedContentFingerprintSha256 $ExpectedContentFingerprintSha256
    if ($result.CanInvokeMailMove -or $result.CanDispatchWorker -or
        $result.CanRetryPreviousMove -or $result.CanWriteHistoricalJournal) {
        throw 'BW4e critical immutable no-Move invariant failed.'
    }
    return [pscustomobject][ordered]@{
        Schema=$result.Schema
        Status=$result.Status
        CandidateReviewId=$CandidateReviewId
        CandidateEntryId=$result.CandidateEntryId
        InternetMessageId=$result.InternetMessageId
        HistoricalOperationMatches=$result.HistoricalOperationMatches
        SyntheticLive3Identity=$result.SyntheticLive3Identity
        PriorReadOnlyPinsMatch=$result.PriorReadOnlyPinsMatch
        SourcePstPop3ItemObserved=$result.SourcePstPop3ItemObserved
        CandidateNewnessIndependentlyProven=$false
        HistoryRunDirectoriesScanned=[int]$review.RunDirectoriesScanned
        HistoryJournalsScanned=[int]$review.JournalsScanned
        HistoryEvidenceSnapshotSha256=[string]$review.HistoryEvidenceSnapshotSha256
        HistoryEvidenceFilesUnchanged=$true
        HistoryCatalogComplete=$false
        IndependentlyAuthenticatedExternalMAPIContent=$false
        ReplaySafetyProven=$false
        SevenHistoricalEvidenceHashesUnchanged=$true
        HistoricJournalEventCount=1
        HistoricJournalPhase='Intent'
        HistoricalJournalChanged=$false
        HistoricalClaimCreated=$false
        WorkerDispatchAllowed=$false
        OutlookComAccessExecuted=$true
        OutlookMoveExecuted=$false
        CanRetryPreviousMove=$false
        CanInvokeMailMove=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='SeparateIndependentExternalEvidenceAndExplicitFreshSyntheticOnlyMoveAuthorizationRequired'
    }
} catch {
    throw ('BW4e STOP: '+[string]$_.Exception.Message+'. No Worker, Move, PST edit, journal write or automatic retry.')
}
