#requires -Version 5.1
# LIVE4 controller owns and kills ONLY the exact child it launches.
# Never kills Outlook.exe, never retries a claimed operation.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][ValidateSet('WorkerStartedBeforeMove','AfterMoveBeforeResponse')]
    [string]$ControlledCrashWindow,
    [ValidateRange(5,300)][int]$TimeoutSeconds=45,
    [switch]$Execute,
    [switch]$EnableControlledCrash
)
$ErrorActionPreference='Stop'
if(-not ($Execute -and $EnableControlledCrash)){
    throw 'LIVE4 controller requires -Execute and -EnableControlledCrash.'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'LIVE4 controller requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live4CrashProtocol.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
[void](Assert-OPA264Live4Mode -Name $ControlledCrashWindow)
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$req=Read-OPAWorkerJson -Path $paths.RequestPath
if(-not [string]::Equals([string]$req.SourcePst,[string]$paths.SourcePst,
    [StringComparison]::OrdinalIgnoreCase)){
    throw 'LIVE4 selected POP3 PST disagrees with durable fixture request.'
}
$paths=Assert-OPA264Live3Request -Request $req -BeforeMove
[void](Assert-OPA264Live3Intent -Request $req -Paths $paths)
$crashPaths=Get-OPA264Live4Paths -FixturePaths $paths
if([IO.File]::Exists((Join-Path $paths.Directory 'bw3-dispatch.claim'))){
    throw 'LIVE4 refuses BW3 controller-dispatched RunId; NEVER reuse.'
}
if([IO.File]::Exists($crashPaths.DispatchClaim) -or
   [IO.File]::Exists($crashPaths.CrashBarrier) -or
   [IO.File]::Exists($crashPaths.ControllerResult)){
    throw 'LIVE4 controller has already dispatched or recorded this RunId; NEVER retry.'
}
$workerFile=[IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot 'Invoke-OPA264Live4CrashWorker.ps1'))
$exe=Join-Path $PSHOME 'powershell.exe'
if(-not [IO.File]::Exists($exe) -or -not [IO.File]::Exists($workerFile)){
    throw 'LIVE4 exact Windows PowerShell worker executable or script missing.'
}
if($workerFile.Contains('"') -or $paths.SourcePst.Contains('"')){
    throw 'LIVE4 controller cannot safely pass quoted path arguments.'
}
# Parent-owned durable dispatch claim BEFORE process creation.
$stream=$null
try{
    $stream=[IO.FileStream]::new($crashPaths.DispatchClaim,
        [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $data=[Text.Encoding]::UTF8.GetBytes(([string]$req.OperationId+[char]10))
    $stream.Write($data,0,$data.Length)
    $stream.Flush($true)
}finally{if($null -ne $stream){$stream.Dispose()}}
$child=$null;$started=$false;$workerPid=0;$killed=$false;$exitCode=$null
$status='Indeterminate';$failureKind='NotStarted';$errorText=''
try{
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$exe
    $info.Arguments=('-NoLogo -NoProfile -NonInteractive -STA -File "{0}" -RunId {1} -SourcePst "{2}" -Execute -ConfirmSyntheticOnlyMove -ControlledCrashWindow {3} -EnableControlledCrash' -f
        $workerFile,$paths.RunId,$paths.SourcePst,$ControlledCrashWindow)
    $info.WorkingDirectory=$PSScriptRoot
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $child=New-Object Diagnostics.Process
    $child.StartInfo=$info
    if(-not $child.Start()){throw 'LIVE4 failed to launch the owned test Worker.'}
    $started=$true
    $workerPid=[int]$child.Id
    $failureKind='BarrierNotObserved'
    [void](Wait-OPA264Live4OwnedBarrier -Process $child -Request $req -FixturePaths $paths -Window $ControlledCrashWindow -TimeoutSeconds $TimeoutSeconds)
    # Terminate the one owned Process object, NEVER Outlook and never by arbitrary PID.
    if($child.HasExited){throw 'LIVE4 child exited before the controller killed it.'}
    $child.Kill()
    if(-not $child.WaitForExit(3000) -or -not $child.HasExited){
        throw 'LIVE4 owned child termination could not be confirmed.'
    }
    $killed=$true
    $exitCode=[int]$child.ExitCode
    if([IO.File]::Exists($paths.ResponsePath)){
        throw 'LIVE4 Worker response exists despite pre-response crash.'
    }
    $status='ControlledCrashObserved'
    $failureKind='None'
}catch{
    $errorText=[string]$_.Exception.Message
}finally{
    if($null -ne $child){
        if($started){
            try{
                if(-not $child.HasExited){
                    $child.Kill()
                    [void]$child.WaitForExit(3000)
                }
            }catch{}
            try{if($child.HasExited){$exitCode=[int]$child.ExitCode}}catch{}
        }
        $child.Dispose()
    }
}
$report=[pscustomobject]@{
    Schema='2.6.4-LIVE4.ControllerResult.1'
    RunId=$paths.RunId
    OperationId=[string]$req.OperationId
    ControlledCrashWindow=$ControlledCrashWindow
    Status=$status
    FailureKind=$failureKind
    Error=$errorText
    WorkerStarted=[bool]$started
    WorkerProcessId=[int]$workerPid
    WorkerKilledByOwningController=[bool]$killed
    WorkerExitCode=$exitCode
    WorkerResponseExists=[IO.File]::Exists($paths.ResponsePath)
    MoveAttemptClaimExists=[IO.File]::Exists($paths.ClaimPath)
    AutomaticRetryAllowed=$false
    JournalCompleted=$false
    RequiresIndependentReconciliation=$true
    Utc=[datetime]::UtcNow.ToString('o')
}
Write-OPAWorkerJsonAtomic -Path $crashPaths.ControllerResult -Value $report
Write-Output $report
if($status -cne 'ControlledCrashObserved'){
    throw 'LIVE4 controlled crash not verified. Keep all evidence; never retry claimed RunId.'
}
