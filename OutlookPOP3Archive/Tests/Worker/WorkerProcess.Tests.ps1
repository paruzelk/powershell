BeforeAll {
    . "$PSScriptRoot/../../Core/Worker/WorkerProtocol.ps1"
    . "$PSScriptRoot/../../Core/Worker/WorkerHost.ps1"
}
Describe 'isolated worker process (synthetic operations only)' {
    It 'uses the current Windows PowerShell 5.1 executable' {
        $path = Get-OPAWorkerPowerShellPath
        [IO.Path]::GetFileName($path) | Should -Be 'powershell.exe'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
    }
    It 'starts Ping in a different process with STA apartment' {
        $r = Invoke-OPAWorkerRequest -Operation Ping -TimeoutSeconds 20
        $r.Status | Should -Be 'Succeeded'
        $r.Result.Alive | Should -BeTrue
        $r.WorkerProcessId | Should -Not -Be $PID
        $r.ApartmentState | Should -Be 'STA'
    }
    It 'transports an object without executing strings from payload' {
        $r = Invoke-OPAWorkerRequest -Operation Echo -Payload @{Text='Клиенты';Script='throw "must not execute"';Number=51} -TimeoutSeconds 20
        $r.Status | Should -Be 'Succeeded'
        $r.Result.Payload.Text | Should -Be 'Клиенты'
        $r.Result.Payload.Script | Should -Be 'throw "must not execute"'
        $r.Result.Payload.Number | Should -Be 51
    }
    It 'returns a structured error when child fails' {
        $r = Invoke-OPAWorkerRequest -Operation Fail -TimeoutSeconds 20
        $r.Status | Should -Be 'Failed'
        $r.Error | Should -Match 'Simulated worker error'
        $r.WorkerProcessId | Should -BeGreaterThan 0
    }
    It 'treats abrupt child death without a response as a hard error' {
        { Invoke-OPAWorkerRequest -Operation Crash -TimeoutSeconds 20 } | Should -Throw '*without a response*'
    }
    It 'can complete a bounded synthetic delay' {
        $r = Invoke-OPAWorkerRequest -Operation Delay -Payload @{Milliseconds=25} -TimeoutSeconds 20
        $r.Status | Should -Be 'Succeeded'
        $r.Result.SleptMilliseconds | Should -Be 25
    }
    It 'terminates only its own timed-out child and reports the failed deadline' {
        { Invoke-OPAWorkerRequest -Operation Delay -Payload @{Milliseconds=10000} -TimeoutSeconds 1 } | Should -Throw '*timed out*'
    }
    It 'keeps the real archiver on the legacy COM path in preview' {
        $main = Get-Content -LiteralPath "$PSScriptRoot/../../OutlookPOP3Archive.ps1" -Raw
        $main | Should -Not -Match 'Invoke-OPAWorkerRequest'
        $worker = Get-Content -LiteralPath "$PSScriptRoot/../../OutlookPOP3Archive.Worker.ps1" -Raw
        $worker | Should -Not -Match '\.Move\('
        $worker | Should -Not -Match 'AddStoreEx'
    }
}
