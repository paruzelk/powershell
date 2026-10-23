#requires -Version 5.1
# 2.6.4-C: isolated test-only deterministic crash barriers.
# Never imported by production Archive/Resume/Auto or normal Worker.
. (Join-Path $PSScriptRoot 'WorkerTestMove.ps1')

function Get-OPA264CrashMode {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)
    $modes = @(
        @('None','None',$false),
        @('AfterIntentBeforeDispatch','Controller',$false),
        @('WorkerStartedBeforeMove','Worker',$true),
        @('AfterMoveBeforeResponse','Worker',$true),
        @('AfterResponseBeforeTerminal','Controller',$false)
    )
    foreach ($row in $modes) {
        if ([string]$row[0] -ceq $Name) {
            return [pscustomobject]@{
                Name=[string]$row[0]
                Owner=[string]$row[1]
                RequiresOwnedChildKill=[bool]$row[2]
                ManualReviewRequired=$true
                AutoRetryAllowed=$false
                JournalCompletionAllowed=$false
                MayHaveMoved=([string]$row[0] -in @('AfterMoveBeforeResponse','AfterResponseBeforeTerminal'))
            }
        }
    }
    throw "Unsupported 2.6.4-C controlled crash mode: '$Name'."
}

function Get-OPA264CrashBarrierPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId)
    $paths=Get-OPA264TestPaths -RunId $RunId
    return (Join-Path $paths.Directory 'crash-barrier.json')
}

function Write-OPA264CrashBarrier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Request,
        [Parameter(Mandatory=$true)]
        [ValidateSet('AfterIntentBeforeDispatch','WorkerStartedBeforeMove',
            'AfterMoveBeforeResponse','AfterResponseBeforeTerminal')][string]$CrashWindow,
        [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$ProcessId
    )
    $definition=Get-OPA264CrashMode -Name $CrashWindow
    if ($CrashWindow -in @('AfterMoveBeforeResponse','AfterResponseBeforeTerminal')) {
        # After a MailItem.Move attempt, the durable worker claim MUST exist.
        # The normal pre-Move scope guard intentionally refuses such a claim.
        $paths=Get-OPA264TestPaths -RunId ([string]$Request.RunId)
        foreach ($field in @('SourcePst','ArchivePst','JournalPath')) {
            if (-not [string]::Equals([string]$Request.$field,[string]$paths.$field,
                [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Post-Move crash barrier scope path mismatch.'
            }
        }
        foreach ($pathToCheck in @($paths.SourcePst,$paths.ArchivePst,$paths.MarkerPath,$paths.ClaimPath)) {
            [void](Assert-OPA264TestPath -Actual $pathToCheck -Expected $pathToCheck -Label 'post-Move fixture')
        }
        $marker=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($paths.MarkerPath)) -ErrorAction Stop
        if ([string]$marker.Purpose -cne 'OPA264-Disposable-Pst-Pair' -or
            [string]$marker.RunId -cne $paths.RunId -or
            [string]$marker.SourcePst -cne $paths.SourcePst -or
            [string]$marker.ArchivePst -cne $paths.ArchivePst -or
            [string]([IO.File]::ReadAllText($paths.ClaimPath)).Trim() -cne [string]$Request.OperationId) {
            throw 'Post-Move crash barrier requires an exact disposable marker and one-shot claim.'
        }
    }
    else { $paths=Assert-OPA264TestMoveScope -Request $Request }
    [void](Assert-OPA264TestMoveIntent -Request $Request -Paths $paths)
    if ($ProcessId -ne $PID) {
        throw 'Crash barrier PID must equal the creating process PID.'
    }
    $path=Get-OPA264CrashBarrierPath -RunId $paths.RunId
    $record=[pscustomobject]@{
        Schema='2.6.4-C.1'
        RunId=$paths.RunId
        OperationId=[string]$Request.OperationId
        CrashWindow=$CrashWindow
        Owner=$definition.Owner
        ProcessId=$ProcessId
        Utc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        JournalCompleted=$false
        RequiresIndependentReconciliation=$true
    }
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(
        (ConvertTo-Json -InputObject $record -Depth 5))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
    return $record
}

function Assert-OPA264CrashBarrier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Record,
        [Parameter(Mandatory=$true)][object]$Request,
        [Parameter(Mandatory=$true)][string]$ExpectedWindow,
        [Parameter(Mandatory=$true)][int]$ExpectedProcessId
    )
    $definition=Get-OPA264CrashMode -Name $ExpectedWindow
    if ([string]$ExpectedWindow -ceq 'None' -or
        $null -eq $Record -or
        [string]$Record.Schema -cne '2.6.4-C.1' -or
        [string]$Record.CrashWindow -cne $ExpectedWindow -or
        [string]$Record.Owner -cne $definition.Owner -or
        [string]$Record.RunId -cne [string]$Request.RunId -or
        [string]$Record.OperationId -cne [string]$Request.OperationId -or
        [int]$Record.ProcessId -ne $ExpectedProcessId -or
        [bool]$Record.AutomaticRetryAllowed -or
        [bool]$Record.JournalCompleted -or
        -not [bool]$Record.RequiresIndependentReconciliation) {
        throw 'Crash barrier PID, identity or safety flag mismatch.'
    }
    return $true
}

function Wait-OPA264OwnedWorkerBarrier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Process,
        [Parameter(Mandatory=$true)][object]$Request,
        [Parameter(Mandatory=$true)][ValidateSet('WorkerStartedBeforeMove','AfterMoveBeforeResponse')][string]$CrashWindow,
        [ValidateRange(1,300)][int]$TimeoutSeconds=30
    )
    $path=Get-OPA264CrashBarrierPath -RunId ([string]$Request.RunId)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            if ([IO.File]::Exists($path)) {
                $json=[IO.File]::ReadAllText($path)
                $record=ConvertFrom-Json -InputObject $json -ErrorAction Stop
                [void](Assert-OPA264CrashBarrier -Record $record -Request $Request -ExpectedWindow $CrashWindow -ExpectedProcessId ([int]$Process.Id))
                if ($Process.HasExited) { throw 'Owned child exited before termination barrier.' }
                return $true
            }
            if ($Process.HasExited) { throw 'Owned child exited without requested crash barrier.' }
            Start-Sleep -Milliseconds 50
        }
        throw 'Owned child did not reach crash barrier before timeout.'
    }
    finally { $watch.Stop() }
}
