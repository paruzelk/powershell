BeforeAll {
    . "$PSScriptRoot/../../Core/Worker/WorkerProtocol.ps1"
}
Describe 'worker protocol 1.0 validation and atomic exchange' {
    It 'builds a versioned request with a unique GUID and UTC timestamp' {
        $a = New-OPAWorkerRequest -Operation Ping
        $b = New-OPAWorkerRequest -Operation Ping
        $a.ProtocolVersion | Should -Be '1.0'
        $a.RequestId | Should -Not -Be $b.RequestId
        [guid]::Parse($a.RequestId) | Should -Not -Be ([guid]::Empty)
        Assert-OPAWorkerRequest -Request $a | Should -BeTrue
    }
    It 'does not accept an unknown operation or executable code' {
        { New-OPAWorkerRequest -Operation 'Invoke-Expression' } | Should -Throw
        $x = New-OPAWorkerRequest -Operation Ping
        $x.Operation = 'Shell'
        { Assert-OPAWorkerRequest -Request $x } | Should -Throw '*not allowed*'
    }
    It 'rejects unsupported protocol versions without interpreting payload' {
        $x = New-OPAWorkerRequest -Operation Echo -Payload @{Value='safe'}
        $x.ProtocolVersion = '9.9'
        { Assert-OPAWorkerRequest -Request $x } | Should -Throw '*unsupported version*'
    }
    It 'rejects a corrupt, absent or empty request ID' {
        $x = New-OPAWorkerRequest -Operation Ping
        $x.RequestId = ''
        { Assert-OPAWorkerRequest -Request $x } | Should -Throw '*RequestId*'
        $x.RequestId = 'not-guid'
        { Assert-OPAWorkerRequest -Request $x } | Should -Throw '*RequestId*'
    }
    It 'rejects request envelopes with missing required fields' {
        $x = [pscustomobject]@{ ProtocolVersion='1.0'; RequestId=[guid]::NewGuid().ToString('D'); Operation='Ping'; Payload=@{} }
        { Assert-OPAWorkerRequest -Request $x } | Should -Throw '*CreatedUtc*'
    }
    It 'requires an object payload and a valid date' {
        { New-OPAWorkerRequest -Operation Echo -Payload 'text' } | Should -Throw '*Payload*'
        $x = New-OPAWorkerRequest -Operation Ping
        $x.CreatedUtc = 'garbled'
        { Assert-OPAWorkerRequest -Request $x } | Should -Throw '*CreatedUtc*'
    }
    It 'roundtrips Unicode data through atomic UTF-8 JSON files' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $path = Join-Path $dir 'request.json'
        $req = New-OPAWorkerRequest -Operation Echo -Payload @{Note='Отправленные\Клиенты'}
        Write-OPAWorkerJsonAtomic -Path $path -Value $req
        $loaded = Read-OPAWorkerJson -Path $path
        [void](Assert-OPAWorkerRequest -Request $loaded)
        $loaded.Payload.Note | Should -Be 'Отправленные\Клиенты'
        @(Get-ChildItem -LiteralPath $dir -File).Count | Should -Be 1
    }
    It 'refuses overwriting an existing request or response file' {
        $path = Join-Path $TestDrive ('immutable-' + [guid]::NewGuid().ToString('N') + '.json')
        Write-OPAWorkerJsonAtomic -Path $path -Value (New-OPAWorkerRequest -Operation Ping)
        { Write-OPAWorkerJsonAtomic -Path $path -Value (New-OPAWorkerRequest -Operation Ping) } | Should -Throw '*already exists*'
    }
    It 'rejects malformed JSON rather than returning a partial object' {
        $path = Join-Path $TestDrive ('invalid-' + [guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($path,'{"bad" :', [Text.Encoding]::UTF8)
        { Read-OPAWorkerJson -Path $path } | Should -Throw '*malformed*'
    }
    It 'requires the exact request ID in a worker response' {
        $req = New-OPAWorkerRequest -Operation Ping
        $resp = [pscustomobject]@{
            ProtocolVersion='1.0';RequestId=[guid]::NewGuid().ToString('D');Operation='Ping'
            Status='Succeeded';WorkerProcessId=99;ApartmentState='STA';Result=@{};Error=''
            StartedUtc='2026-01-01T00:00:00Z';FinishedUtc='2026-01-01T00:00:01Z'
        }
        { Assert-OPAWorkerResponse -Response $resp -Request $req } | Should -Throw '*RequestId mismatch*'
    }
    It 'fails closed for inconsistent result status and missing worker PID' {
        $req = New-OPAWorkerRequest -Operation Ping
        $resp = [pscustomobject]@{
            ProtocolVersion='1.0';RequestId=$req.RequestId;Operation='Ping'
            Status='Failed';WorkerProcessId=0;ApartmentState='STA';Result=$null;Error=''
            StartedUtc='2026-01-01T00:00:00Z';FinishedUtc='2026-01-01T00:00:01Z'
        }
        { Assert-OPAWorkerResponse -Response $resp -Request $req } | Should -Throw '*process ID*'
        $resp.WorkerProcessId = 99
        { Assert-OPAWorkerResponse -Response $resp -Request $req } | Should -Throw '*error*'
    }
}
