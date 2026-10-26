# Parent-side isolated Windows PowerShell 5.1 process boundary.
# Mail mutations remain on the original FIX13b COM path in 2.6.1.
$script:OPAWorkerEntryScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../OutlookPOP3Archive.Worker.ps1'))

function Get-OPAWorkerPowerShellPath {
    [CmdletBinding()]
    param()
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Worker host requires Windows PowerShell 5.1 (powershell.exe), not pwsh.'
    }
    $path = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Worker executable missing: '$path'." }
    return $path
}

function Assert-OPAWorkerHostProcessId {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Response, [Parameter(Mandatory=$true)][int]$ExpectedProcessId)
    if ([int]$Response.WorkerProcessId -ne $ExpectedProcessId) {
        throw ('Worker host: response worker PID {0} differs from spawned process PID {1}.' -f $Response.WorkerProcessId,$ExpectedProcessId)
    }
    return $true
}

function Invoke-OPAWorkerRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Ping','Echo','Fail','Crash','Delay','ProbeOutlook','ProbeSyntheticPstReadOnly','BW3SyntheticOneShotMove')][string]$Operation,
        [object]$Payload = @{},
        [ValidateRange(1,300)][int]$TimeoutSeconds = 15,
        [switch]$KeepArtifacts,
        [string]$RequestId = '',
        # 2.6.1 optional typed result: legacy callers retain existing response
        # and throw behavior unless they deliberately request this outcome mode.
        [switch]$ReturnOutcome
    )
    $startedUtc = [datetime]::UtcNow
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $workerPid = 0
    $exitCode = $null
    $request = $null
    $response = $null
    $failureKind = 'HostError'
    $child = $null
    $started = $false
    $runDir = $null
    try {
        $exe = Get-OPAWorkerPowerShellPath
        $workerScript = [string]$script:OPAWorkerEntryScript
        if (-not (Test-Path -LiteralPath $workerScript -PathType Leaf)) { throw "Worker entry script missing: '$workerScript'." }
        $runDir = Join-Path ([IO.Path]::GetTempPath()) ('OPAWorker-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null
        $requestFile = Join-Path $runDir 'request.json'
        $responseFile = Join-Path $runDir 'response.json'
        $request = New-OPAWorkerRequest -Operation $Operation -Payload $Payload -RequestId $RequestId
        Write-OPAWorkerJsonAtomic -Path $requestFile -Value $request

        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $exe
        # Worker and request paths are generated locally and cannot contain quotes.
        # No payload is inserted into the PowerShell command line.
        $info.Arguments = ('-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "{0}" -RequestFile "{1}" -ResponseFile "{2}"' -f $workerScript,$requestFile,$responseFile)
        $info.WorkingDirectory = [IO.Path]::GetDirectoryName($workerScript)
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $child = New-Object System.Diagnostics.Process
        $child.StartInfo = $info
        if (-not $child.Start()) { throw 'Worker host: failed to start child process.' }
        $started = $true
        $workerPid = [int]$child.Id
        $failureKind = 'MissingResponse'
        if (-not $child.WaitForExit([int]($TimeoutSeconds * 1000))) {
            $failureKind = 'Timeout'
            # End only our own child process; never Outlook.exe or another worker.
            try { if (-not $child.HasExited) { $child.Kill() } } catch {}
            try { [void]$child.WaitForExit(3000) } catch {}
            throw ("Worker host: operation '{0}' timed out after {1} second(s); worker PID={2} was terminated or termination was attempted. Outcome is indeterminate; no automatic retry." -f $Operation,$TimeoutSeconds,$workerPid)
        }
        $exitCode = [int]$child.ExitCode
        if (-not (Test-Path -LiteralPath $responseFile -PathType Leaf)) {
            throw ("Worker host: worker exited ({0}) without a response for request {1}." -f $exitCode,$request.RequestId)
        }
        $failureKind = 'InvalidResponse'
        $response = Read-OPAWorkerJson -Path $responseFile
        [void](Assert-OPAWorkerResponse -Response $response -Request $request)
        [void](Assert-OPAWorkerHostProcessId -Response $response -ExpectedProcessId $workerPid)
        if ($exitCode -eq 0 -and [string]$response.Status -cne 'Succeeded') {
            throw 'Worker host: process exit code and response status disagree.'
        }
        if ($exitCode -ne 0 -and [string]$response.Status -cne 'Failed') {
            throw 'Worker host: process exit code and response status disagree.'
        }
        if (-not $ReturnOutcome) { return $response }
        $watch.Stop()
        $outcomeStatus = if ([string]$response.Status -ceq 'Succeeded') { 'Succeeded' } else { 'Failed' }
        return [pscustomobject]@{
            Status = $outcomeStatus
            FailureKind = if ($outcomeStatus -eq 'Failed') { 'WorkerReportedFailure' } else { 'None' }
            Operation = [string]$Operation
            RequestId = [string]$request.RequestId
            WorkerProcessId = $workerPid
            ExitCode = $exitCode
            StartedUtc = $startedUtc.ToString('o')
            FinishedUtc = [datetime]::UtcNow.ToString('o')
            ElapsedMilliseconds = [int64]$watch.ElapsedMilliseconds
            TimeoutSeconds = [int]$TimeoutSeconds
            RequiresReconciliation = $false
            Error = if ($outcomeStatus -eq 'Failed') { [string]$response.Error } else { '' }
            Response = $response
            ArtifactDirectory = if ($KeepArtifacts) { [string]$runDir } else { '' }
        }
    }
    catch {
        if (-not $ReturnOutcome) { throw }
        $message = [string]$_.Exception.Message
        $watch.Stop()
        # Once a worker has started, a timeout, missing response, or invalid
        # response can never be treated as a known failed COM side effect.
        $status = if ($started) { 'Indeterminate' } else { 'Failed' }
        if ($null -ne $child) {
            try { if ($child.HasExited) { $exitCode = [int]$child.ExitCode } } catch {}
        }
        return [pscustomobject]@{
            Status = $status
            FailureKind = [string]$failureKind
            Operation = [string]$Operation
            RequestId = if ($null -ne $request) { [string]$request.RequestId } else { '' }
            WorkerProcessId = $workerPid
            ExitCode = $exitCode
            StartedUtc = $startedUtc.ToString('o')
            FinishedUtc = [datetime]::UtcNow.ToString('o')
            ElapsedMilliseconds = [int64]$watch.ElapsedMilliseconds
            TimeoutSeconds = [int]$TimeoutSeconds
            RequiresReconciliation = ($status -eq 'Indeterminate')
            Error = $message
            Response = $null
            ArtifactDirectory = if ($KeepArtifacts) { [string]$runDir } else { '' }
        }
    }
    finally {
        $watch.Stop()
        if ($null -ne $child) {
            if ($started) {
                try { if (-not $child.HasExited) { $child.Kill(); [void]$child.WaitForExit(3000) } } catch {}
            }
            $child.Dispose()
        }
        if (-not $KeepArtifacts -and -not [string]::IsNullOrWhiteSpace($runDir) -and (Test-Path -LiteralPath $runDir -PathType Container)) {
            try { Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction Stop } catch {
                Write-Warning "Worker host: unable to remove temporary directory '$runDir': $($_.Exception.Message)"
            }
        }
    }
}
