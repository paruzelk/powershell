#requires -Version 5.1
# BW4k7v2a2: pure read-only classification of failed ONE-pilot observation.
function Test-OPA265BW4k7v2a2PilotObservation {
    [CmdletBinding()]
    param(
        [bool]$PstFilePresent,
        [bool]$IntentPresent,
        [ValidateRange(0,1000)][int]$TargetStoreMatches,
        [ValidateRange(0,1000)][int]$TestFolderMatches,
        [ValidateRange(-1,100000)][int]$TestFolderItemCount=-1,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Candidates
    )
    $match=@($Candidates | Where-Object { $_.SubjectMatches -eq $true })
    $fullyMatched=@($match | Where-Object {
        $_.ClassIsMail -eq $true -and
        $_.ItemEntryIdPresent -eq $true -and
        $_.ParentStoreMatches -eq $true -and
        $_.ParentFolderMatches -eq $true -and
        $_.GetItemFromIdMatches -eq $true
    })
    $status='IncompleteReadOnlyEvidenceManualReview'
    if(-not $IntentPresent){$status='NoOriginalIntentManualReview'}
    elseif(-not $PstFilePresent){$status='TargetPstFileMissingManualReview'}
    elseif($TargetStoreMatches -ne 1){$status='TargetPstNotUniquelyMountedNoWrites'}
    elseif($TestFolderMatches -ne 1){$status='TestFolderMissingOrDuplicatedNoWrites'}
    elseif($TestFolderItemCount -lt 0){$status='TestFolderCountUnreadableNoWrites'}
    elseif($match.Count -gt 1){$status='MultiplePilotSubjectsManualReview'}
    elseif($match.Count -eq 0){$status='NoMatchingPilotInTargetFolderNoCrossStoreSearch'}
    elseif($match.Count -eq 1 -and $fullyMatched.Count -eq 1 -and
           $TestFolderItemCount -eq 1){$status='OnePilotPresentInExactTargetFolderAfterFailure'}
    else{$status='PilotPresentButOriginalPredicateUnresolvedManualReview'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a2.ReadOnlyPilotDiagnosis.1'
        Status=$status
        CandidateCount=$match.Count
        FullyVerifiedCandidateCount=$fullyMatched.Count
        PstFilePresent=$PstFilePresent
        IntentPresent=$IntentPresent
        TestStoreMatches=$TargetStoreMatches
        TestFolderMatches=$TestFolderMatches
        TestFolderItemCount=$TestFolderItemCount
        ExactOriginalPredicateThatFailedProven=$false
        OtherStoresMailSearched=$false
        AnyOutlookComWriterUsed=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}