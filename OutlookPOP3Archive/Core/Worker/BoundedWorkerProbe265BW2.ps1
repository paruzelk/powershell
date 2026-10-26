#requires -Version 5.1
# BW2 parent-side one-shot read-only synthetic Outlook Worker dispatch.
# Requires preloaded LIVE3/LIVE5/LIVE6 + journal modules and WorkerControl.
function Assert-OPA265BW2CanaryGate {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Gate,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SourcePst)
    if ([string]$Gate.Schema -cne '2.6.5.BoundedWorkerRoute.1' -or
        [string]$Gate.Route -cne 'ReadOnlyCanary' -or
        [string]$Gate.WorkerOperation -cne 'Ping' -or
        [string]$Gate.Mode -cnotin @('Archive','Resume') -or
        [string]$Gate.ProfileName -cne 'Outlook' -or
        [int]$Gate.MaxOperations -ne 1 -or
        [int]$Gate.TimeoutSeconds -lt 1 -or
        [int]$Gate.TimeoutSeconds -gt 30 -or
        [bool]$Gate.AutomaticRetryAllowed -or
        [bool]$Gate.RealMailMoveViaWorker -or
        [bool]$Gate.ProductionReady -or
        [string]::IsNullOrWhiteSpace($RunId) -or
        [string]::IsNullOrWhiteSpace($SourcePst)) {
        throw 'BW2: explicit bounded dev canary gate invalid; no child Worker may start.'
    }
    return $true
}
# Convert a failed one-shot read-only Worker result into bounded local
# diagnostic details. Never automatically re-dispatch.
function Get-OPA265BW2WorkerFailureDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Outcome)
    $status=if ([string]$Outcome.Status -cin @('Failed','Indeterminate','Succeeded')) {
        [string]$Outcome.Status
    } else {'Unknown'}
    $kind=if ([string]$Outcome.FailureKind -cin @(
        'None','WorkerReportedFailure','HostError','MissingResponse','Timeout','InvalidResponse')) {
        [string]$Outcome.FailureKind
    } else {'Unknown'}
    $reason=[string]$Outcome.Error
    if ([string]::IsNullOrWhiteSpace($reason) -and $null -ne $Outcome.Response) {
        $reason=[string]$Outcome.Response.Error
    }
    if ([string]::IsNullOrWhiteSpace($reason)) {$reason='No error details from Worker.'}
    # Untrusted COM error becomes printable text. It is never evaluated.
    $reason=[regex]::Replace($reason,'[\x00-\x1F\x7F]',' ')
    if ($reason.Length -gt 400) {$reason=$reason.Substring(0,400)+'...'}
    $exit='Unknown'
    if ($null -ne $Outcome.ExitCode -and
        [string]$Outcome.ExitCode -match '^-?\d{1,10}$') {
        $exit=[string]$Outcome.ExitCode
    }
    return ('Status={0}; FailureKind={1}; ExitCode={2}; ChildPID={3}; Cause={4}' -f
        $status,$kind,$exit,[int]$Outcome.WorkerProcessId,$reason)
}
function Assert-OPA265BW2Outcome {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Outcome,
          [Parameter(Mandatory=$true)][object]$Proof)
    if ([string]$Outcome.Status -cne 'Succeeded' -or
        [string]$Outcome.FailureKind -cne 'None' -or
        [bool]$Outcome.RequiresReconciliation) {
        $details=Get-OPA265BW2WorkerFailureDetails -Outcome $Outcome
        throw ('BW2: Worker refused/failed (NO AUTO RETRY). '+$details)
    }
    if ([string]$Outcome.Operation -cne 'ProbeSyntheticPstReadOnly' -or
        [int]$Outcome.WorkerProcessId -le 0 -or
        $null -eq $Outcome.Response -or
        [string]$Outcome.Response.Status -cne 'Succeeded' -or
        [string]$Outcome.Response.Operation -cne 'ProbeSyntheticPstReadOnly' -or
        [int]$Outcome.Response.WorkerProcessId -ne [int]$Outcome.WorkerProcessId -or
        [string]$Outcome.Response.RequestId -cne [string]$Outcome.RequestId -or
        [string]$Outcome.Response.ApartmentState -cne 'STA' -or
        $null -eq $Outcome.Response.Result) {
        throw 'BW2: isolated Worker outcome invalid/indeterminate; fail closed without retry.'
    }
    $id=[guid]::Empty
    if (-not [guid]::TryParse([string]$Outcome.RequestId,[ref]$id) -or $id -eq [guid]::Empty) {
        throw 'BW2 Worker response has invalid request GUID.'
    }
    $r=$Outcome.Response.Result
    if ([string]$r.Schema -cne '2.6.5-BW2.SyntheticReadOnlyResult.1' -or
        [string]$r.RunId -cne [string]$Proof.RunId -or
        [string]$r.OperationId -cne [string]$Proof.OperationId -or
        [string]$r.State -cne [string]$Proof.State -or
        [string]$r.JournalSha256 -cne [string]$Proof.JournalSha256 -or
        [string]$r.OutlookProfile -cne 'Outlook' -or
        -not [bool]$r.OnlySyntheticFoldersInspected -or
        [bool]$r.OutlookMoveExecuted -or
        [bool]$r.JournalChanged -or
        [bool]$r.AutomaticRetryAllowed -or
        [bool]$r.RealMailMoveViaWorker -or
        [bool]$r.ProductionReady) {
        throw 'BW2: child read-only proof differs from exact parent fixture.'
    }
    $decision=Assert-OPA265BW2ObservedCounts -State ([string]$r.State) -SourceCount ([int]$r.SourceItemCount) -ArchiveCount ([int]$r.ArchiveItemCount) -SourceMatches ([int]$r.SyntheticSourceMatches) -ArchiveMatches ([int]$r.SyntheticArchiveMatches)
    if ([string]$r.Decision -cne $decision) {
        throw 'BW2 child decision and independent parent count proof disagree.'
    }
    if ([string]$r.State -ceq 'Reconciled' -and
        [string]$r.ArchiveEntryId -cne [string]$Proof.ExpectedArchiveEntryId) {
        throw 'BW2 reconciled destination EntryID differs from LIVE6 claim.'
    }
    if ([string]$r.State -ceq 'UnresolvedIntent' -and
        -not [string]::IsNullOrWhiteSpace([string]$r.ArchiveEntryId)) {
        throw 'BW2 unresolved Intent cannot have a confirmed archive EntryID.'
    }
    return $true
}
function Invoke-OPA265BW2BoundedReadOnlyCanary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Gate,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [switch]$KeepArtifacts)
    [void](Assert-OPA265BW2CanaryGate -Gate $Gate -RunId $RunId -SourcePst $SourcePst)
    $proof=Get-OPA265BW2FixtureProof -RunId $RunId -SourcePst $SourcePst
    $payload=[pscustomobject]@{
        Schema='2.6.5-BW2.SyntheticProbeRequest.1'
        RunId=[string]$proof.RunId
        SourcePst=[string]$proof.SourcePst
        OperationId=[string]$proof.OperationId
        JournalSha256=[string]$proof.JournalSha256
        State=[string]$proof.State
    }
    [void](Assert-OPA265BW2Payload -Payload $payload)
    # EXACTLY one child process and operation. No retry/fallback to MailMover.
    $outcome=Invoke-OPAWorkerControlledOperation -Operation 'ProbeSyntheticPstReadOnly' -Payload $payload -TimeoutSeconds ([int]$Gate.TimeoutSeconds) -KeepArtifacts:$KeepArtifacts
    [void](Assert-OPA265BW2Outcome -Outcome $outcome -Proof $proof)
    if ([string]$proof.JournalSha256 -cne
        (Get-FileHash -LiteralPath $proof.Paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()) {
        throw 'BW2 journal changed during child Worker inspection.'
    }
    $r=$outcome.Response.Result
    return [pscustomobject]@{
        Schema='2.6.5-BW2.BoundedWorkerProbeResult.1'
        Status='SyntheticReadOnlyProbePassed'
        Mode=[string]$Gate.Mode
        Route='ReadOnlySyntheticWorker'
        WorkerOperation='ProbeSyntheticPstReadOnly'
        OperationsExecuted=1
        WorkerProcessId=[int]$outcome.WorkerProcessId
        RequestId=[string]$outcome.RequestId
        WorkerApartmentState=[string]$outcome.Response.ApartmentState
        RunId=[string]$r.RunId
        OperationId=[string]$r.OperationId
        State=[string]$r.State
        Decision=[string]$r.Decision
        SourceItemCount=[int]$r.SourceItemCount
        ArchiveItemCount=[int]$r.ArchiveItemCount
        SyntheticSourceMatches=[int]$r.SyntheticSourceMatches
        SyntheticArchiveMatches=[int]$r.SyntheticArchiveMatches
        ArchiveEntryId=[string]$r.ArchiveEntryId
        JournalSha256=[string]$r.JournalSha256
        OnlySyntheticFoldersInspected=$true
        OutlookComAccessExecuted=$true
        OutlookMoveExecuted=$false
        ArchiveTransactionCreated=$false
        JournalChanged=$false
        RealMailMoveViaWorker=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='StopBeforeArchiveOrResume'
    }
}
