#requires -Version 5.1
# BW4a: PERMANENT OPTION-B HISTORICAL FENCE. Never executes Worker/MailItem.Move.
# This module ONLY reads exact existing BW3a evidence; cannot write claims/journals.
# Future Worker Archive/Resume gates may reuse this pure fail-closed classifier.
function Assert-OPA265BW4aHistoricalEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Snapshot,
          [Parameter(Mandatory=$true)][object]$Intent)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $expectedDir='OPA264-LIVE3-'+(([guid]$Pinned.RunId).ToString('N'))
    if ([string]$Paths.RunId -cne [string]$Pinned.RunId -or
        [string]$Paths.SourcePst -cne [string]$Pinned.SourcePst -or
        [IO.Path]::GetFileName([string]$Paths.Directory) -cne $expectedDir -or
        [string]$Snapshot.Journal -cne [string]$Pinned.JournalSha256 -or
        [string]$Snapshot.ManualSizeAcceptance -cne [string]$Pinned.AcceptanceFileSha256 -or
        [string]$Intent.Phase -cne 'Intent' -or
        [string]$Intent.OperationKind -cne 'MailMove' -or
        [long]$Intent.Sequence -ne 1 -or
        [string]$Intent.TransactionId -cne [string]$Pinned.RunId -or
        [string]$Intent.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Intent.ArchivePst -cne [string]$Paths.ArchivePst -or
        [string]::IsNullOrWhiteSpace([string]$Intent.SourceEntryId) -or
        [string]$Intent.InternetMessageId -cne ('<opa264-live3-'+[string]$Pinned.RunId+'@example.invalid>') -or
        [string]$Intent.Subject -cne ('OPA264 LIVE3 synthetic '+[string]$Pinned.RunId) -or
        [long]$Intent.Size -ne 1436 -or
        -not [string]::IsNullOrEmpty([string]$Intent.ArchiveEntryId)) {
        throw 'BW4a refuses to fence history without exact immutable one-Intent BW3a evidence.'
    }
    return $true
}
function Get-OPA265BW4aKnownHistoricalFence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Snapshot,
          [Parameter(Mandatory=$true)][object]$Intent)
    [void](Assert-OPA265BW4aHistoricalEvidence -Pinned $Pinned -Paths $Paths -Snapshot $Snapshot -Intent $Intent)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4a.HistoricalWorkerIsolationFence.1'
        Policy='OptionBPreserveSingleIntentNeverRedispatch'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        SourcePst=[string]$Pinned.SourcePst
        ArchivePst=[string]$Paths.ArchivePst
        JournalSha256=[string]$Pinned.JournalSha256
        AcceptanceRecordSha256=[string]$Pinned.AcceptanceFileSha256
        SourceEntryId=[string]$Intent.SourceEntryId
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        InternetMessageId=[string]$Intent.InternetMessageId
        HistoricalJournalEventCount=1
        HistoricalJournalPhase='Intent'
        HistoricalMovePreviouslyConfirmed=$true
        JournalReconciliationAuthorized=$false
        HistoricRetryBlocked=$true
        WorkerDispatchAllowed=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4aHistoricalFence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Fence)
    $f=@('Schema','Policy','RunId','OperationId','WorkerRequestId','SourcePst',
        'ArchivePst','JournalSha256','AcceptanceRecordSha256','SourceEntryId',
        'DestinationEntryId','InternetMessageId','HistoricalJournalEventCount',
        'HistoricalJournalPhase','HistoricalMovePreviouslyConfirmed',
        'JournalReconciliationAuthorized','HistoricRetryBlocked',
        'WorkerDispatchAllowed','AutomaticRetryAllowed','ProductionReady')
    $p=Get-OPA265BW3hPinnedChain
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $p)
    if ($null -eq $Fence -or $Fence -is [string] -or $Fence -is [array] -or
        @($Fence.PSObject.Properties.Name).Count -ne $f.Count) {
        throw 'BW4a refuses missing or extended historic fence.'
    }
    foreach($name in $f) {
        if ($Fence.PSObject.Properties.Name -cnotcontains $name) {throw ('BW4a missing fence field '+$name)}
    }
    if ([string]$Fence.Schema -cne '2.6.5-BW4a.HistoricalWorkerIsolationFence.1' -or
        [string]$Fence.Policy -cne 'OptionBPreserveSingleIntentNeverRedispatch' -or
        [string]$Fence.RunId -cne [string]$p.RunId -or
        [string]$Fence.OperationId -cne [string]$p.OperationId -or
        [string]$Fence.WorkerRequestId -cne [string]$p.WorkerRequestId -or
        [string]$Fence.SourcePst -cne [string]$p.SourcePst -or
        [string]$Fence.JournalSha256 -cne [string]$p.JournalSha256 -or
        [string]$Fence.AcceptanceRecordSha256 -cne [string]$p.AcceptanceFileSha256 -or
        [string]$Fence.DestinationEntryId -cne [string]$p.DestinationEntryId -or
        [string]::IsNullOrWhiteSpace([string]$Fence.SourceEntryId) -or
        [string]::IsNullOrWhiteSpace([string]$Fence.ArchivePst) -or
        [string]$Fence.InternetMessageId -cne ('<opa264-live3-'+[string]$p.RunId+'@example.invalid>') -or
        [int]$Fence.HistoricalJournalEventCount -ne 1 -or
        [string]$Fence.HistoricalJournalPhase -cne 'Intent') {
        throw 'BW4a historical fence does not exactly match pinned BW3a.'
    }
    foreach($name in @('HistoricalMovePreviouslyConfirmed','HistoricRetryBlocked')) {
        if ($Fence.$name -isnot [bool] -or -not $Fence.$name) {throw ('BW4a missing historic block '+$name)}
    }
    foreach($name in @('JournalReconciliationAuthorized','WorkerDispatchAllowed',
        'AutomaticRetryAllowed','ProductionReady')) {
        if ($Fence.$name -isnot [bool] -or $Fence.$name) {throw ('BW4a forged write permit '+$name)}
    }
    return $true
}
function Get-OPA265BW4aWorkerBoundaryDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Fence,
          [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
          [string]$TransactionId='',
          [string]$OperationId='',
          [string]$WorkerRequestId='',
          [string]$JournalSha256='',
          [string]$SourcePst='',
          [string]$ArchivePst='',
          [string]$SourceEntryId='',
          [string]$DestinationEntryId='',
          [string]$InternetMessageId='')
    [void](Assert-OPA265BW4aHistoricalFence -Fence $Fence)
    if ([string]::IsNullOrWhiteSpace($SourcePst) -or
        -not [IO.Path]::IsPathRooted($SourcePst) -or
        $SourcePst.StartsWith('\\',[StringComparison]::Ordinal) -or
        [IO.Path]::GetExtension($SourcePst) -ine '.pst') {
        throw 'BW4a requires a local absolute selected source PST path; no implicit wildcard.'
    }
    if ($Mode -ceq 'Resume') {
        $id=[guid]::Empty
        if (-not [guid]::TryParse($TransactionId,[ref]$id) -or $id -eq [guid]::Empty) {
            throw 'BW4a Resume candidate requires exact nonempty GUID transaction ID.'
        }
    } elseif (-not [string]::IsNullOrEmpty($TransactionId)) {
        throw 'BW4a Archive candidate cannot reuse an existing transaction ID.'
    }
    foreach($candidate in @($OperationId,$WorkerRequestId)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $candidateGuid=[guid]::Empty
            if (-not [guid]::TryParse($candidate,[ref]$candidateGuid) -or
                $candidateGuid -eq [guid]::Empty) {
                throw 'BW4a candidate operation/request identity must be a nonempty GUID.'
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($JournalSha256) -and
        $JournalSha256 -cnotmatch '^[a-fA-F0-9]{64}$') {
        throw 'BW4a rejects unpinned journal fingerprint.'
    }
    $matched=New-Object 'System.Collections.Generic.List[string]'
    if ($TransactionId -ieq [string]$Fence.RunId) {$matched.Add('HistoricalRunId')}
    if ($OperationId -ieq [string]$Fence.OperationId) {$matched.Add('HistoricalOperationId')}
    if ($WorkerRequestId -ieq [string]$Fence.WorkerRequestId) {$matched.Add('HistoricalWorkerRequestId')}
    if ($JournalSha256 -ieq [string]$Fence.JournalSha256) {$matched.Add('HistoricalJournalSha256')}
    if ($SourceEntryId -ceq [string]$Fence.SourceEntryId) {$matched.Add('HistoricalSourceEntryId')}
    if ($DestinationEntryId -ieq [string]$Fence.DestinationEntryId) {$matched.Add('HistoricalDestinationEntryId')}
    if ($InternetMessageId -ceq [string]$Fence.InternetMessageId) {$matched.Add('HistoricalInternetMessageId')}
    $sharedSource=[string]::Equals([IO.Path]::GetFullPath($SourcePst),
        [IO.Path]::GetFullPath([string]$Fence.SourcePst),
        [StringComparison]::OrdinalIgnoreCase)
    $sharedArchive=($ArchivePst -ne '' -and
        [string]::Equals([IO.Path]::GetFullPath($ArchivePst),
            [IO.Path]::GetFullPath([string]$Fence.ArchivePst),
            [StringComparison]::OrdinalIgnoreCase))
    $status=if ($matched.Count -gt 0) {
        'BlockedKnownHistoricalOperationNeverRetry'
    } elseif ($sharedSource -or $sharedArchive) {
        'BlockedSharedPstRequiresPerItemFencingInBW4b'
    } else {
        'UnrelatedCandidateDesignOnlyNotAuthorized'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4a.ArchiveResumeWorkerBoundaryDecision.1'
        Status=$status
        Mode=$Mode
        HistoricalRunId=[string]$Fence.RunId
        HistoricalOperationId=[string]$Fence.OperationId
        HistoricalIntentSha256=[string]$Fence.JournalSha256
        MatchedHistoricalIdentities=$matched.ToArray()
        SharedSourcePst=$sharedSource
        SharedArchivePst=$sharedArchive
        HistoricalIntentQuarantined=$true
        CanDispatchWorker=$false
        CanInvokeMailMove=$false
        CanAutomaticallyRetryHistoricalOperation=$false
        HistoricJournalWritePermitIssued=$false
        ArchiveResumeIntegrationActivated=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='BW4bImplementPerItemFencingBeforeWorkerDispatch'
    }
}
