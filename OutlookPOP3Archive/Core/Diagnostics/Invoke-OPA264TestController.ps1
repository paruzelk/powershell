#requires -Version 5.1
# 2.6.4-B2 DEV. Explicitly approved one-shot controller for disposable PSTs.
# Own child only; never terminate Outlook.exe and never retry a Move.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [ValidateRange(5,300)][int]$TimeoutSeconds=45,
    [switch]$Execute
)
$ErrorActionPreference='Stop'
if (-not $Execute) { throw 'Test controller requires -Execute.' }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'Test controller requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/WorkerTestMove.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')

$paths=Get-OPA264TestPaths -RunId $RunId
if (-not [IO.File]::Exists($paths.RequestPath)) {
    throw 'Fixture request not found. Run the approved fixture creator first.'
}
$request=Read-OPAWorkerJson -Path $paths.RequestPath
if ([string]$request.RunId -cne $paths.RunId) { throw 'RunId mismatch.' }
[void](Assert-OPA264TestMoveScope -Request $request)
[void](Assert-OPA264TestMoveIntent -Request $request -Paths $paths)
$dispatchClaim=Join-Path $paths.Directory 'controller-dispatch.claim'
$reportPath=Join-Path $paths.Directory 'controller-result.json'
if ([IO.File]::Exists($reportPath) -or [IO.File]::Exists($dispatchClaim)) {
    throw 'Controller already dispatched or reported this RunId; NEVER retry.'
}
$workerScript=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Invoke-OPA264TestWorker.ps1'))
if (-not [IO.File]::Exists($workerScript)) { throw 'Diagnostic Worker script missing.' }
$exe=Join-Path $PSHOME 'powershell.exe'
if (-not [IO.File]::Exists($exe)) { throw 'Windows powershell.exe not found.' }

# Durable parent-owned one-shot claim precedes launch. Crash before launch
# still blocks retry, intentionally. Journal remains at unresolved Intent.
$claim=$null
try {
    $claim=[IO.FileStream]::new($dispatchClaim,[IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,[IO.FileShare]::None)
    $data=[Text.Encoding]::UTF8.GetBytes(([string]$request.OperationId + [char]10))
    $claim.Write($data,0,$data.Length)
    $claim.Flush($true)
}
finally { if ($null -ne $claim) { $claim.Dispose() } }

$child=$null
$started=$false
$pidValue=0
$exitCode=$null
$status='Indeterminate'
$failureKind='NotStarted'
$errorMessage=''
$startedUtc=[datetime]::UtcNow.ToString('o')
try {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$exe
    # Only locally derived fixed paths are passed. No arbitrary code/payload.
    $info.Arguments=('-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "{0}" -RequestFile "{1}" -ResponseFile "{2}" -Execute' -f
        $workerScript,$paths.RequestPath,$paths.ResponsePath)
    $info.WorkingDirectory=[IO.Path]::GetDirectoryName($workerScript)
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $child=New-Object Diagnostics.Process
    $child.StartInfo=$info
    if (-not $child.Start()) { throw 'Failed to start owned diagnostic child.' }
    $started=$true
    $pidValue=[int]$child.Id
    $failureKind='MissingResponse'
    if (-not $child.WaitForExit([int]($TimeoutSeconds*1000))) {
        $failureKind='Timeout'
        # Only the child represented by the Process object we started.
        try { if (-not $child.HasExited) { $child.Kill() } } catch {}
        try { [void]$child.WaitForExit(3000) } catch {}
        throw 'Diagnostic worker timed out; outcome Indeterminate.'
    }
    $exitCode=[int]$child.ExitCode
    if (-not [IO.File]::Exists($paths.ResponsePath)) {
        throw 'Diagnostic worker exited without a response.'
    }
    $result=Read-OPAWorkerJson -Path $paths.ResponsePath
    $failureKind='InvalidResponse'
    if ([string]$result.RunId -cne $paths.RunId -or
        [string]$result.OperationId -cne [string]$request.OperationId -or
        [int]$result.WorkerProcessId -ne $pidValue -or
        [bool]$result.AutomaticRetryAllowed -or
        [bool]$result.JournalCompleted -or
        -not [bool]$result.RequiresIndependentReconciliation) {
        throw 'Worker response identity or safety invariant failed.'
    }
    if ($exitCode -eq 0 -and [string]$result.Status -ceq 'ReturnedNeedsReview') {
        $status='ReturnedNeedsReview'
        $failureKind='None'
    }
    else {
        $status='Indeterminate'
        $failureKind='WorkerErrorOrMismatch'
    }
}
catch {
    $errorMessage=[string]$_.Exception.Message
    $status='Indeterminate'
}
finally {
    if ($null -ne $child) {
        if ($started) {
            try { if (-not $child.HasExited) { $child.Kill(); [void]$child.WaitForExit(3000) } } catch {}
            try { if ($child.HasExited) { $exitCode=[int]$child.ExitCode } } catch {}
        }
        $child.Dispose()
    }
}
$report=[pscustomobject]@{
    RunId=$paths.RunId; OperationId=[string]$request.OperationId
    Status=$status; FailureKind=$failureKind; Error=$errorMessage
    WorkerProcessId=$pidValue; WorkerStarted=$started; ExitCode=$exitCode
    StartedUtc=$startedUtc; FinishedUtc=[datetime]::UtcNow.ToString('o')
    AutomaticRetryAllowed=$false; JournalCompleted=$false
    RequiresIndependentReconciliation=$true
    JournalPath=$paths.JournalPath
}
# Report must not overwrite anything. It is not a completed journal event.
Write-OPAWorkerJsonAtomic -Path $reportPath -Value $report
Write-Output $report
if ($status -cne 'ReturnedNeedsReview') {
    throw 'Test Worker outcome is Indeterminate. Preserve all artifacts and independently reconcile.'
}
