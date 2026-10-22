#requires -Version 5.1
# Non-mutating worker smoke test. Does NOT execute Archive or Resume.
[CmdletBinding()]
param(
    [switch]$IncludeOutlookProbe,
    [ValidateRange(1,120)][int]$TimeoutSeconds = 15
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Core\Worker\WorkerProtocol.ps1"
. "$PSScriptRoot\Core\Worker\WorkerHost.ps1"
. "$PSScriptRoot\Core\Worker\WorkerControl.ps1"

Write-Host '== OutlookPOP3Archive 2.6.1 controlled worker self-test =='
Write-Host 'Archive/Resume integration: DISABLED in 2.6.1-PREVIEW1a'

$ping = Invoke-OPAWorkerRequest -Operation Ping -TimeoutSeconds $TimeoutSeconds
if ($ping.Status -ne 'Succeeded' -or -not $ping.Result.Alive -or
    [string]$ping.ApartmentState -ne 'STA' -or [int]$ping.WorkerProcessId -eq $PID) {
    throw 'Worker Ping failed: worker is not a separate STA process.'
}
Write-Host ("PASS Ping: parent PID={0}; worker PID={1}; apartment={2}" -f $PID,$ping.WorkerProcessId,$ping.ApartmentState)

$echo = Invoke-OPAWorkerRequest -Operation Echo -Payload @{Value='OPA-Worker-2.6.1'; Number=42} -TimeoutSeconds $TimeoutSeconds
if ($echo.Status -ne 'Succeeded' -or [string]$echo.Result.Payload.Value -ne 'OPA-Worker-2.6.1' -or [int]$echo.Result.Payload.Number -ne 42) {
    throw 'Worker Echo protocol roundtrip failed.'
}
Write-Host 'PASS Echo: request/response data integrity'

$failed = Invoke-OPAWorkerRequest -Operation Fail -TimeoutSeconds $TimeoutSeconds
if ($failed.Status -ne 'Failed' -or [string]$failed.Error -notmatch 'Simulated worker error') {
    throw 'Worker error propagation failed.'
}
Write-Host 'PASS Fail: child error propagated with nonzero exit code'

# Short synthetic delay checks that a worker can finish within its deadline.
$delay = Invoke-OPAWorkerRequest -Operation Delay -Payload @{Milliseconds=50} -TimeoutSeconds $TimeoutSeconds
if ($delay.Status -ne 'Succeeded' -or [int]$delay.Result.SleptMilliseconds -ne 50) {
    throw 'Worker Delay failed.'
}
Write-Host 'PASS Delay: bounded synthetic work'

$controlled = Invoke-OPAWorkerControlledOperation -Operation Ping -TimeoutSeconds $TimeoutSeconds
if ($controlled.Status -ne 'Succeeded' -or $controlled.RequiresReconciliation -or
    (Get-OPAWorkerRecoveryDisposition -Status $controlled.Status) -ne 'Proceed') {
    throw 'Worker controlled Ping failed.'
}
Write-Host ('PASS Controlled Ping: RequestId={0}; PID={1}; duration={2} ms' -f $controlled.RequestId,$controlled.WorkerProcessId,$controlled.ElapsedMilliseconds)

$controlledError = Invoke-OPAWorkerControlledOperation -Operation Fail -TimeoutSeconds $TimeoutSeconds
if ($controlledError.Status -ne 'Failed' -or $controlledError.FailureKind -ne 'WorkerReportedFailure') {
    throw 'Worker controlled error classification failed.'
}
Write-Host 'PASS Controlled Fail: failed result is not misclassified as timeout'

if ($IncludeOutlookProbe) {
    Write-Host 'NOTE: COM probe may start Outlook if it is not already running. No mail is moved.'
    $probe = Invoke-OPAWorkerControlledOperation -Operation ProbeOutlook -TimeoutSeconds $TimeoutSeconds
    if ($probe.Status -ne 'Succeeded') { throw "Worker Outlook COM probe failed [$($probe.Status)]: $($probe.Error)" }
    Write-Host ("PASS ProbeOutlook: worker PID={0}; Accounts={1}; Stores={2}" -f $probe.WorkerProcessId,$probe.Response.Result.Accounts,$probe.Response.Result.Stores)
}
else {
    Write-Host 'SKIP ProbeOutlook: use -IncludeOutlookProbe to test isolated Outlook COM.'
}
Write-Host 'Worker self-test completed.'
