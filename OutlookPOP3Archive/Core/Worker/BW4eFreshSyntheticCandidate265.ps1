#requires -Version 5.1
# BW4e: operator-pinned fresh synthetic candidate PRE-MOVE evidence check ONLY.
# Operator claims and visible journal absence are NOT proof of no prior Move.
function Assert-OPA265BW4eCandidatePins {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CandidateReviewId,
        [Parameter(Mandatory=$true)][string]$HistoricalRunId,
        [Parameter(Mandatory=$true)][string]$ExpectedCandidateEntryId,
        [Parameter(Mandatory=$true)][string]$ExpectedInternetMessageId,
        [Parameter(Mandatory=$true)][string]$ExpectedSearchKeySha256,
        [Parameter(Mandatory=$true)][string]$ExpectedContentFingerprintSha256
    )
    $reviewGuid=[guid]::Empty
    $historicalGuid=[guid]::Empty
    if (-not [guid]::TryParse($CandidateReviewId,[ref]$reviewGuid) -or
        $reviewGuid -eq [guid]::Empty -or
        -not [guid]::TryParse($HistoricalRunId,[ref]$historicalGuid) -or
        $historicalGuid -eq [guid]::Empty -or
        $reviewGuid -eq $historicalGuid) {
        throw 'BW4e requires a distinct new nonempty candidate review GUID (never the historical RunId).'
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedCandidateEntryId) -or
        $ExpectedCandidateEntryId.Length -gt 8192 -or
        [string]::IsNullOrWhiteSpace($ExpectedInternetMessageId) -or
        $ExpectedInternetMessageId.Length -gt 4096 -or
        $ExpectedInternetMessageId -cnotmatch '^<[^<>\s]+@[^<>\s]+>$' -or
        [string]$ExpectedSearchKeySha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or
        [string]$ExpectedContentFingerprintSha256 -cnotmatch '^[0-9a-fA-F]{64}$') {
        throw 'BW4e requires exact read-only MAPI EntryID, InternetMessageId and two valid SHA256 pins.'
    }
    return $true
}
function Get-OPA265BW4eFreshCandidateDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Bw4dReview,
        [Parameter(Mandatory=$true)][string]$CandidateReviewId,
        [Parameter(Mandatory=$true)][string]$HistoricalRunId,
        [Parameter(Mandatory=$true)][string]$ExpectedCandidateEntryId,
        [Parameter(Mandatory=$true)][string]$ExpectedInternetMessageId,
        [Parameter(Mandatory=$true)][string]$ExpectedSearchKeySha256,
        [Parameter(Mandatory=$true)][string]$ExpectedContentFingerprintSha256
    )
    [void](Assert-OPA265BW4eCandidatePins -CandidateReviewId $CandidateReviewId -HistoricalRunId $HistoricalRunId -ExpectedCandidateEntryId $ExpectedCandidateEntryId -ExpectedInternetMessageId $ExpectedInternetMessageId -ExpectedSearchKeySha256 $ExpectedSearchKeySha256 -ExpectedContentFingerprintSha256 $ExpectedContentFingerprintSha256)
    if ($null -eq $Bw4dReview -or
        [string]$Bw4dReview.Schema -cne '2.6.5-BW4d.IndependentJournalReplayReviewReadOnly.1' -or
        [string]$Bw4dReview.Status -cne 'IndependentReadOnlyJournalAndOutlookEvidenceReviewedNoMovePermit' -or
        $Bw4dReview.SevenHistoricalEvidenceHashesUnchanged -isnot [bool] -or
        -not $Bw4dReview.SevenHistoricalEvidenceHashesUnchanged -or
        $Bw4dReview.HistoryEvidenceFilesUnchanged -isnot [bool] -or
        -not $Bw4dReview.HistoryEvidenceFilesUnchanged -or
        [int]$Bw4dReview.HistoricJournalEventCount -ne 1 -or
        [string]$Bw4dReview.HistoricJournalPhase -cne 'Intent' -or
        $Bw4dReview.HistoricalJournalChanged -isnot [bool] -or $Bw4dReview.HistoricalJournalChanged -or
        $Bw4dReview.HistoricalClaimCreated -isnot [bool] -or $Bw4dReview.HistoricalClaimCreated -or
        $Bw4dReview.WorkerDispatchAllowed -isnot [bool] -or $Bw4dReview.WorkerDispatchAllowed -or
        $Bw4dReview.OutlookMoveExecuted -isnot [bool] -or $Bw4dReview.OutlookMoveExecuted -or
        $Bw4dReview.CanRetryPreviousMove -isnot [bool] -or $Bw4dReview.CanRetryPreviousMove -or
        $Bw4dReview.ReplaySafetyProven -isnot [bool] -or $Bw4dReview.ReplaySafetyProven -or
        $Bw4dReview.HistoryCatalogComplete -isnot [bool] -or $Bw4dReview.HistoryCatalogComplete -or
        $Bw4dReview.IndependentlyAuthenticatedExternalMAPIContent -isnot [bool] -or
        $Bw4dReview.IndependentlyAuthenticatedExternalMAPIContent -or
        $Bw4dReview.ProductionReady -isnot [bool] -or $Bw4dReview.ProductionReady) {
        throw 'BW4e refuses altered Option B historical evidence, trusted history claims or any Worker/Move permit.'
    }
    $knownStatuses=@('BlockedKnownPriorLive3Live4OperationEvidence',
        'BlockedSyntheticLive3OriginCannotProveNoEarlierMove',
        'NoMatchingEventInVisibleHistoryCatalogStillNotReplayClearance')
    $candidateStatus=[string]$Bw4dReview.CandidateStatus
    if ($candidateStatus -cnotin $knownStatuses) {
        throw 'BW4e requires a known fail-closed BW4d history result.'
    }
    foreach($field in @('CandidateEntryId','InternetMessageId','SourceStoreId',
        'SourceItemFingerprintSha256','SearchKeySha256')) {
        if ([string]::IsNullOrWhiteSpace([string]$Bw4dReview.$field)) {
            throw ('BW4e requires actual Outlook readback of '+$field)
        }
    }
    $historyOverlap=@($Bw4dReview.HistoricalOperationMatches)
    $knownLive3=([string]$Bw4dReview.InternetMessageId -match
        '^<opa264-live3-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}@example\.invalid>$')
    $blockedByHistory=($candidateStatus -cne 'NoMatchingEventInVisibleHistoryCatalogStillNotReplayClearance' -or
        $historyOverlap.Count -gt 0 -or [bool]$Bw4dReview.SyntheticLive3Identity -or $knownLive3)
    $pinnedSame=(
        (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$Bw4dReview.CandidateEntryId) -Expected $ExpectedCandidateEntryId) -and
        [string]::Equals([string]$Bw4dReview.InternetMessageId,$ExpectedInternetMessageId,[StringComparison]::Ordinal) -and
        [string]::Equals([string]$Bw4dReview.SearchKeySha256,$ExpectedSearchKeySha256,[StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$Bw4dReview.SourceItemFingerprintSha256,$ExpectedContentFingerprintSha256,[StringComparison]::OrdinalIgnoreCase)
    )
    $status=if ($blockedByHistory) {
        'BlockedPreviouslyUsedSyntheticOrKnownOperation'
    } elseif (-not $pinnedSame) {
        'BlockedCandidateEvidenceNotMatchingPriorReadOnlyPins'
    } else {
        'FreshCandidatePinsConsistentButNoProofOfNewnessOrMovePermit'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4e.FreshSyntheticCandidatePreMoveReadOnly.1'
        Status=$status
        CandidateReviewId=$CandidateReviewId
        CandidateEntryId=[string]$Bw4dReview.CandidateEntryId
        InternetMessageId=[string]$Bw4dReview.InternetMessageId
        SourceStoreId=[string]$Bw4dReview.SourceStoreId
        HistoricalOperationMatches=$historyOverlap
        SyntheticLive3Identity=[bool]$knownLive3
        PriorReadOnlyPinsMatch=[bool]$pinnedSame
        SourcePstPop3ItemObserved=$true
        CandidateNewnessIndependentlyProven=$false
        HistoryCatalogComplete=$false
        HistoricalEvidenceHashesUnchanged=$true
        HistoricalIntentStillUnresolved=$true
        HistoricalJournalChanged=$false
        HistoricalClaimCreated=$false
        IndependentExternalMAPIContentProof=$false
        FullPstByteEqualityProven=$false
        CanRetryPreviousMove=$false
        CanInvokeMailMove=$false
        CanDispatchWorker=$false
        CanWriteHistoricalJournal=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='SeparateIndependentExternalEvidenceAndExplicitFreshSyntheticOnlyMoveDecisionRequired'
    }
}
