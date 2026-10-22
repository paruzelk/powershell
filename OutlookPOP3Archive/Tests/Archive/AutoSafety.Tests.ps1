BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'Core/Runtime/JsonSupport.ps1')
    . (Join-Path $root 'Core/Archive/AutoRecoveryPolicy.ps1')
}

Describe 'FIX11 Auto pending transaction safety' {
    It 'permits starting a new Archive only when no checkpoints exist' {
        Resolve-OPAAutoPendingTransaction -Candidates @() | Should -BeNullOrEmpty
    }
    It 'selects exactly one unfinished Running transaction' {
        $one = [pscustomobject]@{TransactionId='T1';Status='Running';IsUnsupported=$false}
        (Resolve-OPAAutoPendingTransaction -Candidates @($one)).TransactionId | Should -Be 'T1'
    }
    It 'permits safe recovery of one unreadable checkpoint (Corrupt)' {
        $one = [pscustomobject]@{TransactionId='T2';Status='Corrupt';IsUnsupported=$false}
        (Resolve-OPAAutoPendingTransaction -Candidates @($one)).TransactionId | Should -Be 'T2'
    }
    It 'fails closed on an unsupported checkpoint' {
        $one = [pscustomobject]@{TransactionId='T3';Status='Unsupported';IsUnsupported=$true}
        { Resolve-OPAAutoPendingTransaction -Candidates @($one) } | Should -Throw '*unsupported transaction*'
    }
    It 'fails closed when valid and unsupported checkpoints coexist' {
        $valid = [pscustomobject]@{TransactionId='T4';Status='Running';IsUnsupported=$false}
        $bad = [pscustomobject]@{TransactionId='T5';Status='Unsupported';IsUnsupported=$true}
        { Resolve-OPAAutoPendingTransaction -Candidates @($valid,$bad) } | Should -Throw '*unsupported transaction*'
    }
    It 'blocks automatic Resume of a transaction whose verification or hard capacity failed' {
        $bad = [pscustomobject]@{TransactionId='T-CAP';Status='VerificationFailed';IsUnsupported=$false}
        { Resolve-OPAAutoPendingTransaction -Candidates @($bad) } | Should -Throw '*manual inspection*'
    }
    It 'fails closed when two unfinished checkpoints coexist' {
        $a = [pscustomobject]@{TransactionId='T6';Status='Running';IsUnsupported=$false}
        $b = [pscustomobject]@{TransactionId='T7';Status='Planned';IsUnsupported=$false}
        { Resolve-OPAAutoPendingTransaction -Candidates @($a,$b) } | Should -Throw '*multiple unfinished*'
    }
}

Describe 'FIX11 conservative stale transaction cleanup' {
    BeforeEach {
        $script:pstDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:pstDir -Force | Out-Null
        $script:pst = Join-Path $script:pstDir 'source.pst'
        [IO.File]::WriteAllBytes($script:pst, [byte[]]@(0))
        $script:txdir = Join-Path $script:pstDir 'OutlookPOP3Archive-Transactions'
        New-Item -ItemType Directory -Path $script:txdir -Force | Out-Null
        $script:discovery = [pscustomobject]@{Pop3Sources=@([pscustomobject]@{FilePath=$script:pst})}
    }
    It 'keeps old Running, Unsupported and VerificationFailed checkpoints' {
        foreach ($state in @('Running','Unsupported','VerificationFailed')) {
            $p = Join-Path $script:txdir ($state + '.json')
            [IO.File]::WriteAllText($p, ('{"Status":"' + $state + '"}'))
            (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddDays(-20)
        }
        [void](Remove-OPAStaleTransactions -Discovery $script:discovery -RetentionDays 7)
        foreach ($state in @('Running','Unsupported','VerificationFailed')) {
            Test-Path -LiteralPath (Join-Path $script:txdir ($state + '.json')) | Should -BeTrue
        }
    }
    It 'removes old Completed checkpoint and its step journal' {
        $p = Join-Path $script:txdir 'Done.json'
        $j = Join-Path $script:txdir 'Done.steps.jsonl'
        [IO.File]::WriteAllText($p, '{"Status":"Completed"}')
        [IO.File]::WriteAllText($j, '{"Step":"Move Completed"}' + "`n")
        (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddDays(-20)
        (Get-Item -LiteralPath $j).LastWriteTime = (Get-Date).AddDays(-20)
        [void](Remove-OPAStaleTransactions -Discovery $script:discovery -RetentionDays 7)
        Test-Path -LiteralPath $p | Should -BeFalse
        Test-Path -LiteralPath $j | Should -BeFalse
    }
    It 'does not delete old Completed checkpoint when WhatIf is set' {
        $p = Join-Path $script:txdir 'DryRun.json'
        [IO.File]::WriteAllText($p, '{"Status":"Completed"}')
        (Get-Item -LiteralPath $p).LastWriteTime = (Get-Date).AddDays(-20)
        [void](Remove-OPAStaleTransactions -Discovery $script:discovery -RetentionDays 7 -WhatIf)
        Test-Path -LiteralPath $p | Should -BeTrue
    }
    It 'preserves old orphan journal for manual recovery' {
        $j = Join-Path $script:txdir 'Orphan.steps.jsonl'
        [IO.File]::WriteAllText($j, '{"Step":"Move Started"}' + "`n")
        (Get-Item -LiteralPath $j).LastWriteTime = (Get-Date).AddDays(-20)
        [void](Remove-OPAStaleTransactions -Discovery $script:discovery -RetentionDays 7)
        Test-Path -LiteralPath $j | Should -BeTrue
    }
    It 'refuses Auto when an orphan journal exists' {
        $j = Join-Path $script:txdir 'Orphan2.steps.jsonl'
        [IO.File]::WriteAllText($j, '{"Step":"Move Started"}' + "`n")
        { Assert-OPAAutoNoOrphanJournals -Discovery $script:discovery } | Should -Throw '*orphan step journal*'
    }
    It 'permits Auto when step journals have matching checkpoints' {
        $j = Join-Path $script:txdir 'Existing.steps.jsonl'
        $p = Join-Path $script:txdir 'Existing.json'
        [IO.File]::WriteAllText($j, '{"Step":"Move Started"}' + "`n")
        [IO.File]::WriteAllText($p, '{"Status":"Running"}')
        { Assert-OPAAutoNoOrphanJournals -Discovery $script:discovery } | Should -Not -Throw
    }
    It 'does not remove a Completed checkpoint newer than retention' {
        $p = Join-Path $script:txdir 'Recent.json'
        [IO.File]::WriteAllText($p, '{"Status":"Completed"}')
        [void](Remove-OPAStaleTransactions -Discovery $script:discovery -RetentionDays 7)
        Test-Path -LiteralPath $p | Should -BeTrue
    }
}
