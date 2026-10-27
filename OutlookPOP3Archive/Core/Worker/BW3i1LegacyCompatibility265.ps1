#requires -Version 5.1
# BW3i1: PURE evidence-only compatibility classification.
# Historical BW3a one-shot Worker Move != LIVE4 controlled crash fixture.
# A positive BW3h chain never makes a legacy LIVE6 -Execute safe.
function Assert-OPA265BW3i1LegacyCrashArtifactsAbsent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths)
    $legacy=Get-OPA264Live4Paths -FixturePaths $Paths
    foreach($file in @([string]$legacy.DispatchClaim,
                       [string]$legacy.CrashBarrier,
                       [string]$legacy.ControllerResult)) {
        if ([IO.File]::Exists($file) -or [IO.Directory]::Exists($file) -or
            (Test-Path -LiteralPath $file)) {
            throw 'BW3i1 refuses unexpected LIVE4 crash evidence; never change/remove it.'
        }
    }
    return $true
}
function Assert-OPA265BW3i1InapplicableLive6Review {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    # This is an INAPPLICABLE legacy LIVE6 review, not a Move success verdict.
    # Require exact 20 fields so no forged positive consent can be smuggled.
    $fields=@('Schema','RunId','OperationId','Status','Decision','CanExecute',
        'CanExecuteWithExplicitSizeConsent','CrossPstSizeDiffers',
        'IntentSizeBytes','ObservedArchiveSizeBytes','SizeDifferenceBytes',
        'ArchiveEntryId','ExpectedJournalSha256','JournalEventCount',
        'JournalUnchanged','JournalReconciled','JournalChangedByThisInvocation',
        'OutlookMoveExecuted','AutomaticRetryAllowed','ProductionReady')
    if ($null -eq $Review -or $Review -is [array] -or $Review -is [string] -or
        @($Review.PSObject.Properties.Name).Count -ne $fields.Count) {
        throw 'BW3i1 refuses malformed legacy LIVE6 review object.'
    }
    foreach($name in $fields) {
        if ($Review.PSObject.Properties.Name -cnotcontains $name) {
            throw ('BW3i1 missing legacy LIVE6 field: '+$name)
        }
    }
    if ([string]$Review.Schema -cne '2.6.4-LIVE6.JournalResolutionResult.1' -or
        [string]$Review.Status -cne 'ReviewOnly' -or
        [string]$Review.Decision -cne 'InspectionFailed' -or
        [string]$Review.RunId -cne [string]$Pinned.RunId -or
        [string]$Review.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Review.ExpectedJournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Review.ArchiveEntryId -cne '' -or
        [long]$Review.IntentSizeBytes -ne 0 -or
        [long]$Review.ObservedArchiveSizeBytes -ne 0 -or
        [long]$Review.SizeDifferenceBytes -ne 0 -or
        [int]$Review.JournalEventCount -ne 1) {
        throw 'BW3i1 legacy LIVE6 state differs from expected crash-fixture incompatibility.'
    }
    if ($Review.JournalUnchanged -isnot [bool] -or -not $Review.JournalUnchanged) {
        throw 'BW3i1 legacy read-only review did not preserve original journal.'
    }
    foreach($name in @('CanExecute','CanExecuteWithExplicitSizeConsent',
        'CrossPstSizeDiffers','JournalReconciled',
        'JournalChangedByThisInvocation','OutlookMoveExecuted',
        'AutomaticRetryAllowed','ProductionReady')) {
        if ($Review.$name -isnot [bool] -or [bool]$Review.$name) {
            throw ('BW3i1 legacy executor unexpectedly claims capability: '+$name)
        }
    }
    return $true
}
function Get-OPA265BW3i1LegacyCompatibilityDossier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$Bw3h,
          [Parameter(Mandatory=$true)][object]$LegacyReview,
          [Parameter(Mandatory=$true)][object]$JournalPreflight,
          [Parameter(Mandatory=$true)][object]$SnapshotBefore,
          [Parameter(Mandatory=$true)][object]$SnapshotAfter,
          [Parameter(Mandatory=$true)][string]$RecordPath)
    [void](Assert-OPA265BW3iBw3hVerdict -Verdict $Bw3h -Pinned $Pinned -RecordPath $RecordPath)
    [void](Assert-OPA265BW3i1InapplicableLive6Review -Review $LegacyReview -Pinned $Pinned)
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $SnapshotBefore -After $SnapshotAfter -Pinned $Pinned)
    if ([string]$JournalPreflight.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [int]$JournalPreflight.JournalEventCount -ne 1 -or
        [int]$JournalPreflight.IntentSequence -ne 1 -or
        [long]$JournalPreflight.IntentSizeBytes -ne 1436 -or
        [int]$JournalPreflight.NextProtocolSequence -ne 2 -or
        [string]$JournalPreflight.ProposedNextPhase -cne 'Reconciled') {
        throw 'BW3i1 original one-Intent journal preflight failed.'
    }
    foreach($name in @('Live6ResolutionClaimAbsent','JournalAppendEligibleByCurrentBytes')) {
        if ($JournalPreflight.$name -isnot [bool] -or -not $JournalPreflight.$name) {
            throw ('BW3i1 journal preflight proof false or untyped: '+$name)
        }
    }
    if ($JournalPreflight.JournalAppendAuthorized -isnot [bool] -or
        $JournalPreflight.JournalAppendAuthorized) {
        throw 'BW3i1 refuses any journal authorization through compatibility diagnosis.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3i1.LegacyLive6CompatibilityReadOnly.1'
        Status='HistoricalBW3EvidenceVerifiedLegacyLive6ExecutorBlocked'
        Decision='DoNotUseLegacyLIVE6ExecuteForHistoricalBW3aRun'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        OriginalJournalSha256=[string]$Pinned.JournalSha256
        AcceptanceRecordSha256=[string]$Pinned.AcceptanceFileSha256
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        HistoricBw3hEvidenceChainVerified=$true
        SevenDurableEvidenceHashesUnchanged=$true
        OriginalSingleIntentVerified=$true
        LegacyLive4ControlledCrashArtifactsAbsent=$true
        LegacyLive6ReviewStatus='ReviewOnly'
        LegacyLive6ReviewDecision='InspectionFailed'
        LegacyLive6ApplicableToHistoricalBw3a=$false
        LegacyLive6CanExecute=$false
        LegacyLive6CanExecuteWithExplicitSizeConsent=$false
        WorkerMoveHistoricallyConfirmedByBw3h=$true
        SizeDifferenceBytes=8L
        ManualSizeAcceptancePersisted=$true
        OriginalJournalEventCount=1
        HypotheticalNextJournalSequence=2
        HypotheticalNextJournalPhase='Reconciled'
        FullMAPIItemByteEqualityVerified=$false
        JournalReconciliationAuthorized=$false
        WriteableJournalPermitIssued=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='DesignAndReviewDistinctBW3ScopedResolutionProtocolBeforeSeparateConsent'
    }
}
