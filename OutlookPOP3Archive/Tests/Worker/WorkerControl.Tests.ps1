BeforeAll {
    . "$PSScriptRoot/../../Core/Worker/WorkerProtocol.ps1"
    . "$PSScriptRoot/../../Core/Worker/WorkerHost.ps1"
    . "$PSScriptRoot/../../Core/Worker/WorkerControl.ps1"
}
Describe '2.6.1 controller outcome decisions (safe synthetic operations)' {
    It 'returns a correlated success with a separate STA worker PID' {
        $r = Invoke-OPAWorkerControlledOperation -Operation Ping -TimeoutSeconds 20
        $r.Status | Should -Be 'Succeeded'
        $r.FailureKind | Should -Be 'None'
        $r.RequiresReconciliation | Should -BeFalse
        $r.WorkerProcessId | Should -Not -Be $PID
        $r.Response.ApartmentState | Should -Be 'STA'
        $r.RequestId | Should -Be $r.Response.RequestId
        $r.ElapsedMilliseconds | Should -BeGreaterOrEqual 0
        (Get-OPAWorkerRecoveryDisposition -Status $r.Status) | Should -Be 'Proceed'
    }
    It 'classifies a structured failure as Failed without claiming a timeout' {
        $r = Invoke-OPAWorkerControlledOperation -Operation Fail -TimeoutSeconds 20
        $r.Status | Should -Be 'Failed'
        $r.FailureKind | Should -Be 'WorkerReportedFailure'
        $r.RequiresReconciliation | Should -BeFalse
        $r.Error | Should -Match 'Simulated worker error'
        (Get-OPAWorkerRecoveryDisposition -Status $r.Status) | Should -Be 'Stop'
    }
    It 'classifies abrupt exit without a response as Indeterminate' {
        $r = Invoke-OPAWorkerControlledOperation -Operation Crash -TimeoutSeconds 20
        $r.Status | Should -Be 'Indeterminate'
        $r.FailureKind | Should -Be 'MissingResponse'
        $r.RequiresReconciliation | Should -BeTrue
        $r.Response | Should -BeNullOrEmpty
        $r.WorkerProcessId | Should -BeGreaterThan 0
        (Get-OPAWorkerRecoveryDisposition -Status $r.Status) | Should -Be 'ReconcileBeforeRetry'
    }
    It 'classifies a hard deadline as Indeterminate and never starts a retry' {
        $r = Invoke-OPAWorkerControlledOperation -Operation Delay -Payload @{Milliseconds=10000} -TimeoutSeconds 1
        $r.Status | Should -Be 'Indeterminate'
        $r.FailureKind | Should -Be 'Timeout'
        $r.RequiresReconciliation | Should -BeTrue
        $r.Error | Should -Match 'timed out'
        $r.WorkerProcessId | Should -BeGreaterThan 0
    }
    It 'classifies an untrustworthy worker response as Indeterminate' {
        Mock Assert-OPAWorkerResponse { throw 'synthetic invalid response' }
        $r = Invoke-OPAWorkerControlledOperation -Operation Ping -TimeoutSeconds 20
        $r.Status | Should -Be 'Indeterminate'
        $r.FailureKind | Should -Be 'InvalidResponse'
        $r.RequiresReconciliation | Should -BeTrue
        $r.WorkerProcessId | Should -BeGreaterThan 0
    }
    It 'classifies a locally invalid payload before launch as Failed' {
        $r = Invoke-OPAWorkerControlledOperation -Operation Echo -Payload 'not-an-object' -TimeoutSeconds 20
        $r.Status | Should -Be 'Failed'
        $r.WorkerProcessId | Should -Be 0
        $r.RequiresReconciliation | Should -BeFalse
        $r.Error | Should -Match 'Payload'
    }
    It 'retains only explicitly requested request evidence' {
        $r = Invoke-OPAWorkerControlledOperation -Operation Crash -TimeoutSeconds 20 -KeepArtifacts
        try {
            $r.Status | Should -Be 'Indeterminate'
            Test-Path -LiteralPath $r.ArtifactDirectory -PathType Container | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $r.ArtifactDirectory 'request.json') -PathType Leaf | Should -BeTrue
        }
        finally {
            if ($r.ArtifactDirectory -and (Test-Path -LiteralPath $r.ArtifactDirectory)) {
                Remove-Item -LiteralPath $r.ArtifactDirectory -Recurse -Force
            }
        }
    }
    It 'rejects an unapproved operation before starting any process' {
        { Invoke-OPAWorkerControlledOperation -Operation 'MoveMail' } | Should -Throw
    }
    It 'refuses an unknown recovery status rather than silently retrying' {
        { Get-OPAWorkerRecoveryDisposition -Status 'Retry' } | Should -Throw
    }
    It 'checks a response PID against the process actually launched' {
        $resp = [pscustomobject]@{WorkerProcessId=123}
        { Assert-OPAWorkerHostProcessId -Response $resp -ExpectedProcessId 456 } | Should -Throw '*differs*'
        Assert-OPAWorkerHostProcessId -Response $resp -ExpectedProcessId 123 | Should -BeTrue
    }
    It 'requires valid timestamps and STA in a response' {
        $req = New-OPAWorkerRequest -Operation Ping
        $resp = [pscustomobject]@{
            ProtocolVersion='1.0';RequestId=$req.RequestId;Operation='Ping';Status='Succeeded'
            WorkerProcessId=99;ApartmentState='STA';Result=@{};Error='';
            StartedUtc='2026-01-01T00:00:01Z';FinishedUtc='2026-01-01T00:00:00Z'
        }
        { Assert-OPAWorkerResponse -Response $resp -Request $req } | Should -Throw '*timestamps*'
        $resp.FinishedUtc='2026-01-01T00:00:02Z'
        $resp.ApartmentState='MTA'
        { Assert-OPAWorkerResponse -Response $resp -Request $req } | Should -Throw '*apartment*'
    }
    It 'does not use a worker to move mail in the 2.6.1 preview' {
        $main = Get-Content -LiteralPath "$PSScriptRoot/../../OutlookPOP3Archive.ps1" -Raw
        $mover = Get-Content -LiteralPath "$PSScriptRoot/../../Core/Archive/MailMover.ps1" -Raw
        $entry = Get-Content -LiteralPath "$PSScriptRoot/../../OutlookPOP3Archive.Worker.ps1" -Raw
        $main | Should -Not -Match 'Invoke-OPAWorkerControlledOperation'
        $mover | Should -Not -Match 'Invoke-OPAWorkerControlledOperation'
        $entry | Should -Not -Match '\.Move\('
        $entry | Should -Not -Match 'AddStoreEx'
    }
}
