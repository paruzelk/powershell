#requires -Version 5.1
# BW4f: operator-created disposable fixture *classification only*.
# Matching user-controlled Subject/Body is NOT cryptographic provenance.
function Get-OPA265BW4fFixtureTag {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Subject,
        [AllowEmptyString()][string]$Body,
        [object]$AttachmentCount=$null
    )
    $none=[pscustomobject][ordered]@{
        IsExactOperatorFixture=$false
        TestId=''
        SubjectBodyExactTagMatched=$false
        AttachmentsAbsentProven=$false
    }
    $pattern='^OPA265 BW4e1 FRESH TEST (?<id>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$'
    $m=[regex]::Match([string]$Subject,$pattern,[Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $m.Success) { return $none }
    $guid=[guid]::Empty
    if (-not [guid]::TryParse([string]$m.Groups['id'].Value,[ref]$guid) -or $guid -eq [guid]::Empty) {
        return $none
    }
    # BW4f2: Outlook text bodies may use CR-only or CRCRLF line endings
    # (including mixed line endings within one received POP3 MailItem).
    # Normalize separator characters ONLY for marker classification:
    # never modify actual MailItem.Body nor BW4c raw content SHA256 pins.
    $normalizedBody=[regex]::Replace([string]$Body,'\r+\n|\r',"`n")
    if ($normalizedBody -cnotmatch '(?m)^OPA265 BW4e1 disposable synthetic test\.$') {
        return $none
    }
    $testLines=@([regex]::Matches($normalizedBody,'(?m)^TestId: (?<id>[0-9a-fA-F-]{36})$'))
    if ($testLines.Count -ne 1 -or
        [string]$testLines[0].Groups['id'].Value -cne [string]$m.Groups['id'].Value) {
        return $none
    }
    if ($null -eq $AttachmentCount) { return $none }
    $count=-1
    try { $count=[int]$AttachmentCount } catch { return $none }
    if ($count -ne 0) { return $none }
    return [pscustomobject][ordered]@{
        IsExactOperatorFixture=$true
        TestId=$guid.ToString('D')
        SubjectBodyExactTagMatched=$true
        AttachmentsAbsentProven=$true
    }
}
function Get-OPA265BW4fScopeDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Bw4eReview,
        [Parameter(Mandatory=$true)][string]$ExpectedTestId
    )
    $gid=[guid]::Empty
    if (-not [guid]::TryParse($ExpectedTestId,[ref]$gid) -or $gid -eq [guid]::Empty -or
        [string]$ExpectedTestId -cne $gid.ToString('D')) {
        throw 'BW4f: require explicit canonical nonempty disposable test GUID.'
    }
    $expectedStatus=@(
        'FreshCandidatePinsConsistentButNoProofOfNewnessOrMovePermit',
        'BlockedPreviouslyUsedSyntheticOrKnownOperation',
        'BlockedCandidateEvidenceNotMatchingPriorReadOnlyPins'
    )
    if ($null -eq $Bw4eReview -or
        [string]$Bw4eReview.Schema -cne '2.6.5-BW4e.FreshSyntheticCandidatePreMoveReadOnly.1' -or
        [string]$Bw4eReview.Status -cnotin $expectedStatus -or
        $Bw4eReview.HistoryEvidenceFilesUnchanged -isnot [bool] -or -not $Bw4eReview.HistoryEvidenceFilesUnchanged -or
        $Bw4eReview.SevenHistoricalEvidenceHashesUnchanged -isnot [bool] -or -not $Bw4eReview.SevenHistoricalEvidenceHashesUnchanged -or
        [string]$Bw4eReview.HistoricJournalPhase -cne 'Intent' -or
        [int]$Bw4eReview.HistoricJournalEventCount -ne 1 -or
        $Bw4eReview.WorkerDispatchAllowed -isnot [bool] -or $Bw4eReview.WorkerDispatchAllowed -or
        $Bw4eReview.OutlookMoveExecuted -isnot [bool] -or $Bw4eReview.OutlookMoveExecuted -or
        $Bw4eReview.CanRetryPreviousMove -isnot [bool] -or $Bw4eReview.CanRetryPreviousMove -or
        $Bw4eReview.CanInvokeMailMove -isnot [bool] -or $Bw4eReview.CanInvokeMailMove -or
        $Bw4eReview.AutomaticRetryAllowed -isnot [bool] -or $Bw4eReview.AutomaticRetryAllowed -or
        $Bw4eReview.ProductionReady -isnot [bool] -or $Bw4eReview.ProductionReady -or
        $Bw4eReview.HistoryCatalogComplete -isnot [bool] -or $Bw4eReview.HistoryCatalogComplete -or
        $Bw4eReview.IndependentlyAuthenticatedExternalMAPIContent -isnot [bool] -or
        $Bw4eReview.IndependentlyAuthenticatedExternalMAPIContent) {
        throw 'BW4f: requires authentic historical no-Move BW4e review and preserved single Intent.'
    }
    $tagged=($Bw4eReview.IsExactOperatorFixture -is [bool] -and
        $Bw4eReview.IsExactOperatorFixture -and
        [string]$Bw4eReview.ObservedOperatorTestId -ceq $ExpectedTestId)
    $blockedByHistory=([string]$Bw4eReview.Status -cne
        'FreshCandidatePinsConsistentButNoProofOfNewnessOrMovePermit')
    $status=if($blockedByHistory) {
        'BlockedByHistoricalOrPinnedEvidence'
    } elseif (-not $tagged) {
        'BlockedNotExactDisposableFixture'
    } elseif (-not $Bw4eReview.TargetedMessageIdReadOnlyUsed) {
        'BlockedNeedsExplicitTargetedOutlookReadOnly'
    } else {
        'DisposableFixtureScopeConsistentButNoMovePermit'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4f.DisposableFixtureScopeReadOnly.1'
        Status=$status
        TestId=$ExpectedTestId
        CandidateEntryId=[string]$Bw4eReview.CandidateEntryId
        InternetMessageId=[string]$Bw4eReview.InternetMessageId
        IsExactOperatorFixture=[bool]$tagged
        TargetedMessageIdReadOnlyUsed=[bool]$Bw4eReview.TargetedMessageIdReadOnlyUsed
        FolderItemsObserved=[int]$Bw4eReview.FolderItemsObserved
        OutlookFixtureProvenIndependent=$false
        CandidateNewnessIndependentlyProven=$false
        HistoryCatalogComplete=$false
        HistoricalEvidenceFilesUnchanged=$true
        SevenHistoricalEvidenceHashesUnchanged=$true
        HistoricJournalEventCount=1
        HistoricJournalPhase='Intent'
        HistoricalJournalChanged=$false
        HistoricalClaimCreated=$false
        WorkerDispatchAllowed=$false
        OutlookMoveExecuted=$false
        CanInvokeMailMove=$false
        CanDispatchWorker=$false
        CanWriteHistoricalJournal=$false
        CanRetryPreviousMove=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='IndependentExternalMessageEvidenceAndSeparateExplicitSyntheticMoveApprovalRequired'
    }
}
