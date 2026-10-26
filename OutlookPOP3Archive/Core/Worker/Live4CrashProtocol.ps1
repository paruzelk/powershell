#requires -Version 5.1
# LIVE4 controlled crash protocol; test-only. NO Outlook COM.
function Get-OPA264Live4Paths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$FixturePaths)
    return [pscustomobject]@{
        DispatchClaim=(Join-Path $FixturePaths.Directory 'controller-dispatch.claim')
        CrashBarrier=(Join-Path $FixturePaths.Directory 'crash-barrier.json')
        ControllerResult=(Join-Path $FixturePaths.Directory 'controller-result.json')
    }
}
function Assert-OPA264Live4Mode {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)
    if($Name -cnotin @('WorkerStartedBeforeMove','AfterMoveBeforeResponse')){
        throw 'LIVE4 supports only two named Worker crash windows.'
    }
    return $Name
}
function Assert-OPA264Live4Barrier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Record,
          [Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][string]$Window,
          [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$ExpectedWorkerPid)
    [void](Assert-OPA264Live4Mode -Name $Window)
    if($null -eq $Record -or
       [string]$Record.Schema -cne '2.6.4-LIVE4.CrashBarrier.1' -or
       [string]$Record.RunId -cne [string]$Request.RunId -or
       [string]$Record.OperationId -cne [string]$Request.OperationId -or
       [string]$Record.CrashWindow -cne $Window -or
       [int]$Record.WorkerProcessId -ne $ExpectedWorkerPid -or
       [bool]$Record.AutomaticRetryAllowed -or
       [bool]$Record.JournalCompleted -or
       -not [bool]$Record.RequiresIndependentReconciliation){
        throw 'LIVE4 crash barrier identity or flags mismatch.'
    }
    return $true
}
function Assert-OPA264Live4Claim {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][string]$OperationId)
    if(-not [IO.File]::Exists($Path)){throw 'LIVE4 durable claim is missing.'}
    if(([IO.File]::ReadAllText($Path)).Trim() -cne $OperationId){
        throw 'LIVE4 durable claim belongs to another operation.'
    }
    return $true
}
function Write-OPA264Live4Barrier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$FixturePaths,
          [Parameter(Mandatory=$true)][string]$Window,
          [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$WorkerProcessId)
    [void](Assert-OPA264Live4Mode -Name $Window)
    if($WorkerProcessId -ne [int]$PID){
        throw 'LIVE4 barrier must be written by its own Worker process.'
    }
    $checked=Assert-OPA264Live3Request -Request $Request
    if([string]$checked.RunId -cne [string]$FixturePaths.RunId -or
       [string]$checked.SourcePst -cne [string]$FixturePaths.SourcePst -or
       [string]$checked.ArchivePst -cne [string]$FixturePaths.ArchivePst){
        throw 'LIVE4 barrier fixture path mismatch.'
    }
    [void](Assert-OPA264Live3Intent -Request $Request -Paths $checked)
    $paths=Get-OPA264Live4Paths -FixturePaths $FixturePaths
    [void](Assert-OPA264Live4Claim -Path $paths.DispatchClaim -OperationId ([string]$Request.OperationId))
    if([IO.File]::Exists($FixturePaths.ResponsePath) -or
       [IO.File]::Exists($paths.ControllerResult)){
        throw 'LIVE4 cannot write crash barrier after terminal response.'
    }
    if($Window -ceq 'WorkerStartedBeforeMove'){
        if([IO.File]::Exists($FixturePaths.ClaimPath)){
            throw 'LIVE4 pre-Move barrier rejects an already claimed Move.'
        }
    }else{
        [void](Assert-OPA264Live4Claim -Path $FixturePaths.ClaimPath -OperationId ([string]$Request.OperationId))
    }
    $value=[pscustomobject]@{
        Schema='2.6.4-LIVE4.CrashBarrier.1'
        RunId=[string]$Request.RunId
        OperationId=[string]$Request.OperationId
        CrashWindow=$Window
        WorkerProcessId=[int]$WorkerProcessId
        Utc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        JournalCompleted=$false
        RequiresIndependentReconciliation=$true
    }
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(
        (ConvertTo-Json -InputObject $value -Depth 5))
    $stream=$null
    try{
        $stream=[IO.FileStream]::new($paths.CrashBarrier,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }finally{if($null -ne $stream){$stream.Dispose()}}
    return $value
}
function Wait-OPA264Live4OwnedBarrier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Process,
          [Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$FixturePaths,
          [Parameter(Mandatory=$true)][string]$Window,
          [ValidateRange(5,300)][int]$TimeoutSeconds=45)
    [void](Assert-OPA264Live4Mode -Name $Window)
    $paths=Get-OPA264Live4Paths -FixturePaths $FixturePaths
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try{
        while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            if([IO.File]::Exists($paths.CrashBarrier)){
                # CreateNew/FileShare.None makes the filename visible BEFORE
                # the Worker has flushed and closed the JSON. Poll past
                # transient sharing violations; never accept partial JSON.
                $barrierText=$null
                try{$barrierText=[IO.File]::ReadAllText($paths.CrashBarrier)}
                catch [IO.IOException]{
                    if($Process.HasExited){throw 'LIVE4 Worker exited while writing crash barrier.'}
                    Start-Sleep -Milliseconds 50
                    continue
                }
                $record=ConvertFrom-Json -InputObject $barrierText -ErrorAction Stop
                [void](Assert-OPA264Live4Barrier -Record $record -Request $Request -Window $Window -ExpectedWorkerPid ([int]$Process.Id))
                if($Window -ceq 'AfterMoveBeforeResponse'){
                    [void](Assert-OPA264Live4Claim -Path $FixturePaths.ClaimPath -OperationId ([string]$Request.OperationId))
                }elseif([IO.File]::Exists($FixturePaths.ClaimPath)){
                    throw 'LIVE4 observed claimed Move in pre-Move crash window.'
                }
                if([IO.File]::Exists($FixturePaths.ResponsePath)){
                    throw 'LIVE4 Worker emitted a response before crash termination.'
                }
                if($Process.HasExited){throw 'LIVE4 Worker exited before parent terminated it.'}
                return $true
            }
            if($Process.HasExited){throw 'LIVE4 Worker exited without reaching the crash barrier.'}
            Start-Sleep -Milliseconds 50
        }
        throw 'LIVE4 Worker crash barrier timed out.'
    }finally{$watch.Stop()}
}
