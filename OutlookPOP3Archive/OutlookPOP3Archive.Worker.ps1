#requires -Version 5.1
# Isolated worker ENTRY POINT. Archive/Resume integration is intentionally disabled in this preview.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RequestFile,
    [Parameter(Mandatory=$true)][string]$ResponseFile
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Core\Worker\WorkerProtocol.ps1"

# Both files must be in one private per-request directory. This entry point
# handles only a strict operation allowlist; it never executes submitted code.
$reqFull = [IO.Path]::GetFullPath($RequestFile)
$resFull = [IO.Path]::GetFullPath($ResponseFile)
if ([string]::IsNullOrWhiteSpace($reqFull) -or [string]::IsNullOrWhiteSpace($resFull) -or
    -not [string]::Equals([IO.Path]::GetDirectoryName($reqFull), [IO.Path]::GetDirectoryName($resFull), [StringComparison]::OrdinalIgnoreCase) -or
    [string]::Equals($reqFull, $resFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Worker entry: request and response must be distinct files in the same directory.'
}
$request = Read-OPAWorkerJson -Path $reqFull
[void](Assert-OPAWorkerRequest -Request $request)

$start = [datetime]::UtcNow
$status = 'Succeeded'
$result = $null
$errorMessage = ''
try {
    switch ([string]$request.Operation) {
        'Ping' {
            $result = [pscustomobject]@{ Alive=$true; PowerShellVersion=[string]$PSVersionTable.PSVersion }
        }
        'Echo' {
            # Data-only round trip; no script or expression evaluation.
            $result = [pscustomobject]@{ Payload=$request.Payload }
        }
        'Fail' {
            throw 'Simulated worker error (test operation).'
        }
        'Crash' {
            # Test-only: emulate abrupt process death without response JSON.
            exit 17
        }
        'Delay' {
            if (@($request.Payload.PSObject.Properties.Name) -notcontains 'Milliseconds') {
                throw 'Worker Delay requires Milliseconds.'
            }
            $milliseconds = [int]$request.Payload.Milliseconds
            if ($milliseconds -lt 0 -or $milliseconds -gt 300000) {
                throw 'Worker Delay must be between 0 and 300000 milliseconds.'
            }
            Start-Sleep -Milliseconds $milliseconds
            $result = [pscustomobject]@{ SleptMilliseconds=$milliseconds }
        }
        'ProbeSyntheticPstReadOnly' {
            # BW2: attach ONLY to the existing Outlook session, inspect EXACT
            # LIVE3 test folders and the reconciled/unresolved journal.
            # No creation, mounting, Move, Save, Delete, retries, or PST edits.
            . "$PSScriptRoot\Core\Worker\Live3SyntheticScope.ps1"
            . "$PSScriptRoot\Core\Worker\Live5Reconciliation.ps1"
            . "$PSScriptRoot\Core\Worker\Live6JournalResolution.ps1"
            . "$PSScriptRoot\Core\Archive\OperationJournal.ps1"
            . "$PSScriptRoot\Core\Worker\SyntheticReadOnlyProbe265BW2.ps1"
            $result=Invoke-OPA265BW2ReadOnlySyntheticProbe -Payload $request.Payload
        }
        'ProbeOutlook' {
            # EXPLICITLY OPT-IN. COM lives entirely within this child process.
            # Read-only enumeration: no PST creation, archive, move, delete,
            # profile logon request or Quit() call to user's Outlook.
            $app = $null; $namespace = $null
            try {
                $app = New-Object -ComObject Outlook.Application -ErrorAction Stop
                $namespace = $app.GetNamespace('MAPI')
                $result = [pscustomobject]@{
                    Accounts = [int]$namespace.Accounts.Count
                    Stores = [int]$namespace.Stores.Count
                }
            }
            finally {
                if ($null -ne $namespace -and [Runtime.InteropServices.Marshal]::IsComObject($namespace)) {
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($namespace)
                }
                if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
                }
            }
        }
        default { throw 'Worker entry: unexpected operation after validation.' }
    }
}
catch {
    $status = 'Failed'
    $errorMessage = [string]$_.Exception.Message
}

$response = [pscustomobject]@{
    ProtocolVersion = $script:OPAWorkerProtocolVersion
    RequestId = [string]$request.RequestId
    Operation = [string]$request.Operation
    Status = $status
    WorkerProcessId = [int]$PID
    ApartmentState = [string][System.Threading.Thread]::CurrentThread.GetApartmentState()
    Result = $result
    Error = $errorMessage
    StartedUtc = $start.ToString('o')
    FinishedUtc = [datetime]::UtcNow.ToString('o')
}
Write-OPAWorkerJsonAtomic -Path $resFull -Value $response
if ($status -eq 'Failed') { exit 10 }
exit 0
