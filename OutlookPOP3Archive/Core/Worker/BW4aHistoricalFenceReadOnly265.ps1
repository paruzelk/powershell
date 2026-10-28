#requires -Version 5.1
# BW4a read-only option-B audit of exact pinned historical BW3a evidence.
# Both Archive/Resume candidate routes STOP before any Worker/PST action.
function Invoke-OPA265BW4aHistoricalFenceReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
          [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
          [string]$Transaction='')
    $p=Get-OPA265BW3hPinnedChain
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $p)
    if ($RunId -cne [string]$p.RunId -or
        $SourcePst -cne [string]$p.SourcePst -or
        $ExpectedJournalSha256 -cne [string]$p.JournalSha256) {
        throw 'BW4a refuses unpinned historical RunId, source PST or journal SHA256.'
    }
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    [void](Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $paths -Pinned $p)
    $before=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $p
    $request=Read-OPAWorkerJson -Path ([string]$paths.RequestPath)
    $assertion=Assert-OPA265BW3jOriginalIntent -Paths $paths -Request $request -Pinned $p
    $j=Read-OPAOperationJournal -Path ([string]$paths.JournalPath)
    if ([bool]$j.TrailingPartial -or @($j.Events).Count -ne 1) {
        throw 'BW4a historical source journal is not exactly one complete Intent.'
    }
    $intent=$j.Events[0]
    [void](Assert-OPA265BW4aHistoricalEvidence -Pinned $p -Paths $paths -Snapshot $before -Intent $intent)
    if ([string]$assertion.JournalSha256 -cne [string]$p.JournalSha256) {
        throw 'BW4a unexpectedly altered historical pinned original.'
    }
    $fence=Get-OPA265BW4aKnownHistoricalFence -Pinned $p -Paths $paths -Snapshot $before -Intent $intent
    [void](Assert-OPA265BW4aHistoricalFence -Fence $fence)
    $candidate=Get-OPA265BW4aWorkerBoundaryDecision -Fence $fence -Mode $Mode -TransactionId $Transaction -SourcePst $SourcePst
    if ([string]$candidate.Status -cnotin @('BlockedKnownHistoricalOperationNeverRetry',
            'BlockedSharedPstRequiresPerItemFencingInBW4b') -or
        $candidate.CanDispatchWorker -isnot [bool] -or $candidate.CanDispatchWorker) {
        throw 'BW4a historical boundary erroneously permitted dispatch.'
    }
    # Check original evidentiary files and resolution-claim slots AGAIN.
    $after=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $p
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $before -After $after -Pinned $p)
    $latest=Assert-OPA265BW3jOriginalIntent -Paths $paths -Request $request -Pinned $p
    [void](Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $paths -Pinned $p)
    if ([string]$latest.JournalSha256 -cne [string]$assertion.JournalSha256) {
        throw 'BW4a original journal changed during read-only isolation audit.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4a.HistoricalIntentIsolationReviewReadOnly.1'
        Status='HistoricalBW3aIntentQuarantinedNoWorkerDispatch'
        Decision='OptionBPreserveHistoricIntentAndBlockArchiveResumeWorkerRetry'
        Mode=$Mode
        CandidateStatus=[string]$candidate.Status
        RunId=[string]$p.RunId
        OperationId=[string]$p.OperationId
        WorkerRequestId=[string]$p.WorkerRequestId
        OriginalJournalSha256=[string]$p.JournalSha256
        ManualSizeAcceptanceSha256=[string]$p.AcceptanceFileSha256
        SevenHistoricalEvidenceHashesUnchanged=$true
        HistoricJournalEventCount=1
        HistoricJournalPhase='Intent'
        HistoricalIntentQuarantined=$true
        HistoricMovePreviouslyConfirmed=$true
        SourcePstSharedWithHistoricalRun=[bool]$candidate.SharedSourcePst
        HistoricRetryBlocked=$true
        WorkerDispatchAllowed=$false
        WorkerOperationsExecuted=0
        OutlookComAccessExecuted=$false
        OutlookMoveExecuted=$false
        HistoricalJournalChanged=$false
        HistoricalResolutionClaimCreated=$false
        ArchiveResumeIntegrationActivated=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='BW4bAddPerItemWorkerFencingInSeparateOptInTestOnlyRoute'
    }
}
