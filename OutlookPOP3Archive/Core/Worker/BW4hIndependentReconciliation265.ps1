#requires -Version 5.1
# BW4h: purely read-only claim and source/destination reconciliation decisions.
# A returned Outlook MailItem.Move is NOT proof of persistence or byte equality.
function Assert-OPA265BW4hClaim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Claim,
        [Parameter(Mandatory=$true)][string]$TestId,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$DestinationPst,
        [Parameter(Mandatory=$true)][string]$SourceEntryId,
        [Parameter(Mandatory=$true)][string]$DestinationFolderEntryId,
        [Parameter(Mandatory=$true)][string]$InternetMessageId
    )
    $expected=@('Schema','TestId','CandidateReviewId','SourcePst','SourceEntryId',
        'InternetMessageId','DestinationPst','DestinationFolderEntryId','Utc',
        'AutomaticRetryAllowed','ProductionReady')
    if ($Claim -isnot [pscustomobject] -or
        @($Claim.PSObject.Properties.Name).Count -ne $expected.Count) {
        throw 'BW4h rejects claim without exact original BW4g schema.'
    }
    foreach($p in $expected) {
        if ($Claim.PSObject.Properties.Name -cnotcontains $p) {
            throw ('BW4h rejects claim missing property '+$p)
        }
    }
    $tid=[guid]::Empty;$rid=[guid]::Empty
    if ($Claim.Schema -cne '2.6.5-BW4g.ImmutableOneShotClaim.1' -or
        -not [guid]::TryParse([string]$TestId,[ref]$tid) -or
        $tid -eq [guid]::Empty -or [string]$TestId -cne $tid.ToString('D') -or
        [string]$Claim.TestId -cne [string]$TestId -or
        -not [guid]::TryParse([string]$Claim.CandidateReviewId,[ref]$rid) -or
        $rid -eq [guid]::Empty -or
        [string]$Claim.CandidateReviewId -cne $rid.ToString('D') -or
        [string]$Claim.SourceEntryId -cne [string]$SourceEntryId -or
        [string]$Claim.DestinationFolderEntryId -cne [string]$DestinationFolderEntryId -or
        [string]$Claim.InternetMessageId -cne [string]$InternetMessageId -or
        $Claim.AutomaticRetryAllowed -isnot [bool] -or $Claim.AutomaticRetryAllowed -or
        $Claim.ProductionReady -isnot [bool] -or $Claim.ProductionReady) {
        throw 'BW4h rejects unpinned or unsafe once-only attempt claim.'
    }
    $expectedLeaf='OPA265-BW4g-'+$tid.ToString('N')+'.pst'
    if ([IO.Path]::GetFileName($DestinationPst) -cne $expectedLeaf -or
        [string]::Equals([IO.Path]::GetFullPath($SourcePst),
            [IO.Path]::GetFullPath($DestinationPst),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'BW4h rejects non-disposable or same-store destination.'
    }
    foreach($pair in @(
        @([string]$Claim.SourcePst,$SourcePst),
        @([string]$Claim.DestinationPst,$DestinationPst))) {
        if (-not [IO.Path]::IsPathRooted($pair[0]) -or
            -not [IO.Path]::IsPathRooted($pair[1]) -or
            -not [string]::Equals([IO.Path]::GetFullPath($pair[0]),
                [IO.Path]::GetFullPath($pair[1]),
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'BW4h rejects claim PST path disagreement.'
        }
    }
    $utc=[datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Claim.Utc,[ref]$utc)) {
        throw 'BW4h rejects invalid original durable claim timestamp.'
    }
    return $true
}
function Get-OPA265BW4hReadOnlyDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][int]$SourceMatches,
        [Parameter(Mandatory=$true)][int]$DestinationMatches,
        [Parameter(Mandatory=$true)][int]$DestinationFolderCount,
        [Parameter(Mandatory=$true)][bool]$DestinationEntryIdMatches,
        [Parameter(Mandatory=$true)][bool]$InternetMessageIdMatches,
        [Parameter(Mandatory=$true)][bool]$FixtureMatches,
        [Parameter(Mandatory=$true)][bool]$SearchKeyMatches,
        [Parameter(Mandatory=$true)][bool]$ContentFingerprintMatches,
        [Parameter(Mandatory=$true)][bool]$HistoricalEvidenceUnchanged,
        [Parameter(Mandatory=$true)][bool]$ClaimUnchanged
    )
    # The only positive status requires all independently observed
    # read-only facts. It is NOT a PST byte-for-byte durability proof.
    $safe=($SourceMatches -eq 0 -and $DestinationMatches -eq 1 -and
        $DestinationFolderCount -eq 1 -and $DestinationEntryIdMatches -and
        $InternetMessageIdMatches -and $FixtureMatches -and
        $SearchKeyMatches -and $ContentFingerprintMatches -and
        $HistoricalEvidenceUnchanged -and $ClaimUnchanged)
    $status=if(-not $HistoricalEvidenceUnchanged -or -not $ClaimUnchanged) {
        'BlockedHistoricalOrClaimEvidenceDrift'
    } elseif($SourceMatches -ne 0 -or $DestinationMatches -ne 1 -or
        $DestinationFolderCount -ne 1 -or -not $DestinationEntryIdMatches -or
        -not $InternetMessageIdMatches -or -not $FixtureMatches) {
        'MoveNotIndependentlyConfirmedNeedsManualReview'
    } elseif(-not $SearchKeyMatches -or -not $ContentFingerprintMatches) {
        'MoveObservedButMAPIFieldFingerprintDriftNeedsManualReview'
    }else{'IndependentOutlookReadOnlyMoveReconciled'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4h.IndependentReadOnlyDecision.1'
        Status=$status
        ReadOnlyReconciliationPassed=[bool]$safe
        SourceMatches=$SourceMatches
        DestinationMatches=$DestinationMatches
        SearchKeyMatches=$SearchKeyMatches
        ContentFieldFingerprintMatches=$ContentFingerprintMatches
        HistoricalEvidenceUnchanged=$HistoricalEvidenceUnchanged
        ClaimUnchanged=$ClaimUnchanged
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
    }
}
