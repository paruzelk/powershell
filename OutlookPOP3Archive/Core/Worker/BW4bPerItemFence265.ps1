#requires -Version 5.1
# BW4b: pure per-message read-only fence. Witnesses are untrusted until real independent Outlook capture.
function Get-OPA265BW4bPerItemDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Fence,
        [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [string]$TransactionId='',
        [object]$Primary=$null,
        [object]$Independent=$null
    )
    [void](Assert-OPA265BW4aHistoricalFence -Fence $Fence)
    $boundary=Get-OPA265BW4aWorkerBoundaryDecision -Fence $Fence -Mode $Mode -TransactionId $TransactionId -SourcePst $SourcePst
    $matched=New-Object 'System.Collections.Generic.List[string]'
    foreach($hit in @($boundary.MatchedHistoricalIdentities)) {
        if (-not [string]::IsNullOrEmpty([string]$hit)) { [void]$matched.Add([string]$hit) }
    }
    foreach($o in @($Primary,$Independent)) {
        if ($null -eq $o) { continue }
        foreach($pair in @(
            @('HistoricalSourceEntryId','SourceEntryId','SourceEntryId'),
            @('HistoricalDestinationEntryId','SourceEntryId','DestinationEntryId'),
            @('HistoricalInternetMessageId','InternetMessageId','InternetMessageId'))) {
            $v=[string]$o.($pair[1])
            if (-not [string]::IsNullOrEmpty($v) -and
                [string]::Equals($v,[string]$Fence.($pair[2]),[StringComparison]::OrdinalIgnoreCase) -and
                -not $matched.Contains([string]$pair[0])) { [void]$matched.Add([string]$pair[0]) }
        }
    }
    $consistent=$false
    $formatValid=$false
    if ($matched.Count -gt 0) {
        $status='BlockedKnownHistoricalOperationNeverRetry'
    } elseif ($null -eq $Primary -or $null -eq $Independent) {
        $status='BlockedMissingPerItemEvidence'
    } else {
        $expected=@('Schema','CaptureId','CaptureMethod','SourcePst','SourceStoreId','SourceEntryId','InternetMessageId','SearchKeySha256','ContentSha256','ObservedItemCount')
        $formatValid=$true
        foreach($o in @($Primary,$Independent)) {
            if ($o -isnot [pscustomobject] -or @($o.PSObject.Properties.Name).Count -ne $expected.Count) { $formatValid=$false; continue }
            foreach($f in $expected) {
                if ($o.PSObject.Properties.Name -cnotcontains $f) { $formatValid=$false }
            }
            if (-not $formatValid) { continue }
            $id=[guid]::Empty
            if ([string]$o.Schema -cne '2.6.5-BW4b.PerItemWitness.1' -or
                -not [guid]::TryParse([string]$o.CaptureId,[ref]$id) -or $id -eq [guid]::Empty -or
                [string]::IsNullOrWhiteSpace([string]$o.SourceStoreId) -or
                [string]::IsNullOrWhiteSpace([string]$o.SourceEntryId) -or
                [string]::IsNullOrWhiteSpace([string]$o.InternetMessageId) -or
                [string]$o.SearchKeySha256 -cnotmatch '^[a-fA-F0-9]{64}$' -or
                [string]$o.ContentSha256 -cnotmatch '^[a-fA-F0-9]{64}$' -or
                $o.ObservedItemCount -isnot [int] -or $o.ObservedItemCount -ne 1 -or
                -not [IO.Path]::IsPathRooted([string]$o.SourcePst) -or
                -not [string]::Equals([IO.Path]::GetFullPath([string]$o.SourcePst),[IO.Path]::GetFullPath($SourcePst),[StringComparison]::OrdinalIgnoreCase)) { $formatValid=$false }
        }
        if (-not $formatValid -or
            [string]$Primary.CaptureMethod -cne 'PrimaryReadOnly' -or
            [string]$Independent.CaptureMethod -cne 'IndependentReadOnly' -or
            [string]$Primary.CaptureId -ieq [string]$Independent.CaptureId) {
            $status='BlockedUnverifiedPerItemEvidence'
            $formatValid=$false
        } else {
            $consistent=$true
            foreach($key in @('SourcePst','SourceStoreId','SourceEntryId','InternetMessageId','SearchKeySha256','ContentSha256','ObservedItemCount')) {
                if ([string]$Primary.$key -cne [string]$Independent.$key) { $consistent=$false }
            }
            $status=if ($consistent) {'PerItemEvidenceConsistentDesignOnlyNoWorkerDispatch'} else {'BlockedConflictingPerItemEvidence'}
        }
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4b.PerItemFenceDecision.1'
        Status=$status
        Mode=$Mode
        HistoricalMatches=$matched.ToArray()
        SharedHistoricalPst=[bool]$boundary.SharedSourcePst
        PerItemEvidenceFormatValid=[bool]$formatValid
        PerItemEvidenceConsistent=[bool]$consistent
        IndependentOutlookReadbackVerified=$false
        HistoricalIntentStillUnresolved=$true
        CanDispatchWorker=$false
        CanInvokeMailMove=$false
        CanWriteHistoricalJournal=$false
        CanCreateHistoricalClaim=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='TrustedIndependentReadbackAndSeparateSyntheticMoveAuthorizationRequired'
    }
}
