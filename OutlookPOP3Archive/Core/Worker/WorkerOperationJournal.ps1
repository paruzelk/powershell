#requires -Version 5.1
# 2.6.2: journaled diagnostic worker dispatcher, WITHOUT MailItem.Move.
# The durable Intent precedes worker launch. Never auto-retry an uncertain run.
# Load independently: production Archive/Resume/Auto still follow FIX13b path.
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot 'WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot 'WorkerHost.ps1')
. (Join-Path $PSScriptRoot 'WorkerControl.ps1')

function Get-OPAWorkerOperationJournalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$TransactionDirectory,
        [Parameter(Mandatory=$true)][string]$TransactionId
    )
    # A transaction identifier is a basename, never a path component.
    if ($TransactionId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') {
        throw 'Unsafe transaction ID for worker journal filename.'
    }
    return (Join-Path $TransactionDirectory ($TransactionId + '.operations.jsonl'))
}

function Get-OPAWorkerOperationJournalState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$JournalPath)

    if (-not (Test-Path -LiteralPath $JournalPath -PathType Leaf)) {
        return [pscustomobject]@{
            TransactionId = $null
            LastSequence = [long]0
            Resolved = @()
            Failed = @()
            Indeterminate = @()
            TrailingPartial = $false
            BlockAutomaticRetry = $false
            RequiresPstReconciliation = $false
        }
    }
    return (Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $JournalPath))
}

function Invoke-OPAWorkerJournaledOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$JournalPath,
        [Parameter(Mandatory=$true)][string]$TransactionId,
        [Parameter(Mandatory=$true)]
        [ValidateSet('Ping','Echo','Fail','Crash','Delay','ProbeOutlook')][string]$Operation,
        [object]$Payload = @{},
        [ValidateRange(1,300)][int]$TimeoutSeconds = 15,
        [switch]$KeepArtifacts
    )
    if ([string]::IsNullOrWhiteSpace($TransactionId)) { throw 'TransactionId is required.' }
    $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($JournalPath))
    # Prevent a caller from writing the right transaction to the wrong file:
    # journal identity remains deterministic even after a crash/restart.
    $expected = Get-OPAWorkerOperationJournalPath -TransactionDirectory $parent -TransactionId $TransactionId
    if (-not [string]::Equals([IO.Path]::GetFullPath($JournalPath),
            [IO.Path]::GetFullPath($expected), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Journal filename does not match TransactionId.'
    }
    if (-not [IO.Directory]::Exists($parent)) { [void][IO.Directory]::CreateDirectory($parent) }

    # A persistent lock FILE, but an ephemeral exclusive HANDLE. A crashed
    # process releases its lock; do not delete/recreate the file (race risk).
    $lock = $null
    try {
        $lock = [IO.FileStream]::new(($JournalPath + '.lock'),
            [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None)
        $state = Get-OPAWorkerOperationJournalState -JournalPath $JournalPath
        if ($state.TransactionId -and [string]$state.TransactionId -cne $TransactionId) {
            throw 'Worker journal belongs to a different transaction.'
        }
        if ($state.BlockAutomaticRetry) {
            throw 'Worker journal has unresolved, failed or truncated operations; refusing automatic dispatch until manually reviewed.'
        }
        # IDs are owned by the controller BEFORE dispatch, so a missing
        # response can always be tied back to the Intent.
        $requestId = [guid]::NewGuid().ToString('D')
        $sequence = [long]$state.LastSequence + 1
        if ($sequence -le 0) { throw 'Worker journal sequence overflow.' }
        [void](Write-OPAOperationJournalEvent -Path $JournalPath -TransactionId $TransactionId `
            -OperationId $requestId -Sequence $sequence -OperationKind WorkerDiagnostic `
            -Phase Intent -Message ("Worker: " + $Operation))
        # All operations in this phase are non-mutating. MailItem.Move is NOT
        # in the worker allowlist, and no production archiving route calls us.
        $result = $null
        try {
            $result = Invoke-OPAWorkerControlledOperation -Operation $Operation -Payload $Payload `
                -TimeoutSeconds $TimeoutSeconds -KeepArtifacts:$KeepArtifacts -RequestId $requestId
            if ($null -eq $result -or [string]$result.RequestId -cne $requestId) {
                throw 'Worker outcome request correlation failed.'
            }
        }
        catch {
            # Once Intent has been flushed, any unknown execution state
            # becomes Indeterminate. Never infer "did not start" from a throw.
            $result = [pscustomobject]@{
                Status='Indeterminate'; RequestId=$requestId
                WorkerProcessId=0; FailureKind='DispatcherException'
                Error=[string]$_.Exception.Message; RequiresReconciliation=$true
            }
        }
        $phase = switch ([string]$result.Status) {
            'Succeeded' { 'WorkerSucceeded' }
            'Failed' { 'WorkerFailed' }
            default { 'Indeterminate' }
        }
        $committed = $false
        $commitError = ''
        try {
            [void](Write-OPAOperationJournalEvent -Path $JournalPath -TransactionId $TransactionId `
                -OperationId $requestId -Sequence ($sequence + 1) `
                -OperationKind WorkerDiagnostic -Phase $phase `
                -WorkerProcessId ([int]$result.WorkerProcessId) `
                -FailureKind ([string]$result.FailureKind) -Message ([string]$result.Error))
            $committed = $true
        }
        catch { $commitError = [string]$_.Exception.Message }
        if (-not $committed) {
            # A validated worker response cannot override lost durability.
            return [pscustomobject]@{
                Status='Indeterminate'; RequestId=$requestId
                JournalCommitted=$false; WorkerStatus=[string]$result.Status
                RequiresReconciliation=$true
                Error=("Worker completed but journal terminal write failed: " + $commitError)
                WorkerResult=$result
            }
        }
        return [pscustomobject]@{
            Status=[string]$result.Status
            RequestId=$requestId
            JournalCommitted=$true
            WorkerStatus=[string]$result.Status
            RequiresReconciliation=([string]$result.Status -eq 'Indeterminate')
            Error=[string]$result.Error
            WorkerResult=$result
        }
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose() }
    }
}
