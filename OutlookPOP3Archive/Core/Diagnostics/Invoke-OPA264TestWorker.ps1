#requires -Version 5.1
# 2.6.4-B DEV — standalone, manually invoked TEST ONLY entry point.
# No production WorkerProtocol allowlist, no Archive/Resume/Auto integration.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RequestFile,
    [Parameter(Mandatory=$true)][string]$ResponseFile,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
if (-not $Execute) { throw '2.6.4-B test Worker requires explicit -Execute.' }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw '2.6.4-B test Worker requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/WorkerTestMove.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')

$request = Read-OPAWorkerJson -Path $RequestFile
$paths = Assert-OPA264TestMoveScope -Request $request
if (-not [string]::Equals($RequestFile,$paths.RequestPath,[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals($ResponseFile,$paths.ResponsePath,[StringComparison]::OrdinalIgnoreCase)) {
    throw '2.6.4-B test Worker refuses request/response outside the exact disposable run.'
}
[void](Assert-OPA264TestMoveIntent -Request $request -Paths $paths)
$app = $null
$ns = $null
$status = 'Indeterminate'
$result = $null
$errorMessage = ''
try {
    # Attach only to already-running Outlook; never create a profile or start it.
    $app = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'Outlook.Application is not running.' }
    $ns = $app.GetNamespace('MAPI')
    $result = Invoke-OPA264TestOneShotMove -Request $request -Namespace $ns
    $status = 'ReturnedNeedsReview'
}
catch {
    $errorMessage = [string]$_.Exception.Message
}
finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
$response = [pscustomobject]@{
    RunId = $paths.RunId
    OperationId = [string]$request.OperationId
    WorkerProcessId = [int]$PID
    Status = $status
    Result = $result
    Error = $errorMessage
    AutomaticRetryAllowed = $false
    JournalCompleted = $false
    RequiresIndependentReconciliation = $true
    ObservedUtc = [datetime]::UtcNow.ToString('o')
}
# Diagnostic response is NOT an authoritative MailMove completion.
Write-OPAWorkerJsonAtomic -Path $paths.ResponsePath -Value $response
if ($status -cne 'ReturnedNeedsReview') { exit 10 }
exit 0
