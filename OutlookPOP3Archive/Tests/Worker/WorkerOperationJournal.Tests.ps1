#requires -Version 5.1
BeforeAll {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Core\Worker\WorkerOperationJournal.ps1')
}
Describe '2.6.2 journaled worker dispatch (no Outlook COM)' {
    BeforeEach {
        $script:directory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:journal = Get-OPAWorkerOperationJournalPath -TransactionDirectory $script:directory -TransactionId 'T1'
    }

    It 'derives a journal basename but refuses path traversal' {
        [IO.Path]::GetFileName($script:journal) | Should -Be 'T1.operations.jsonl'
        { Get-OPAWorkerOperationJournalPath -TransactionDirectory $TestDrive -TransactionId '../danger' } | Should -Throw
        { Get-OPAWorkerOperationJournalPath -TransactionDirectory $TestDrive -TransactionId '..' } | Should -Throw
    }

    It 'flushes an Intent before dispatch and correlates RequestId exactly' {
        Mock Invoke-OPAWorkerControlledOperation {
            $reader = Read-OPAOperationJournal -Path $script:journal
            @($reader.Events).Count | Should -Be 1
            $reader.Events[0].Phase | Should -Be 'Intent'
            $reader.Events[0].OperationKind | Should -Be 'WorkerDiagnostic'
            $reader.Events[0].OperationId | Should -Be $RequestId
            [pscustomobject]@{ Status='Succeeded'; RequestId=$RequestId; WorkerProcessId=111; FailureKind='None'; Error='' }
        }
        $r = Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Ping
        $r.Status | Should -Be 'Succeeded'
        $r.JournalCommitted | Should -BeTrue
        $state = Get-OPAWorkerOperationJournalState -JournalPath $script:journal
        $state.LastSequence | Should -Be 2
        @($state.Resolved).Count | Should -Be 1
        $state.BlockAutomaticRetry | Should -BeFalse
        @((Read-OPAOperationJournal -Path $script:journal).Events)[1].Phase | Should -Be 'WorkerSucceeded'
    }

    It 'keeps a confirmed worker failure distinct from an unknown outcome' {
        Mock Invoke-OPAWorkerControlledOperation {
            [pscustomobject]@{ Status='Failed'; RequestId=$RequestId; WorkerProcessId=111; FailureKind='WorkerReportedFailure'; Error='test failure' }
        }
        $r = Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Fail
        $r.Status | Should -Be 'Failed'
        $s = Get-OPAWorkerOperationJournalState -JournalPath $script:journal
        @($s.Failed).Count | Should -Be 1
        $s.BlockAutomaticRetry | Should -BeTrue
        { Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Ping } | Should -Throw '*refusing automatic dispatch*'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Exactly -Times 1
    }

    It 'blocks a new dispatch after a crash/timeout outcome' {
        Mock Invoke-OPAWorkerControlledOperation {
            [pscustomobject]@{ Status='Indeterminate'; RequestId=$RequestId; WorkerProcessId=111; FailureKind='Timeout'; Error='timed out' }
        }
        $r = Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Delay
        $r.Status | Should -Be 'Indeterminate'
        (Get-OPAWorkerOperationJournalState -JournalPath $script:journal).BlockAutomaticRetry | Should -BeTrue
        { Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Delay } | Should -Throw
        Should -Invoke Invoke-OPAWorkerControlledOperation -Exactly -Times 1
    }

    It 'does not dispatch after an orphaned Intent from a simulated process kill' {
        [void](Write-OPAOperationJournalEvent -Path $script:journal -TransactionId 'T1' -OperationId 'intent-only' -Sequence 1 -Phase Intent -OperationKind WorkerDiagnostic)
        Mock Invoke-OPAWorkerControlledOperation { throw 'Must not be dispatched' }
        { Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Ping } | Should -Throw
        Should -Invoke Invoke-OPAWorkerControlledOperation -Exactly -Times 0
    }

    It 'refuses a reused journal for a different transaction' {
        [void](Write-OPAOperationJournalEvent -Path $script:journal -TransactionId 'T1' -OperationId 'test' -Sequence 1 -Phase Intent -OperationKind WorkerDiagnostic)
        [void](Write-OPAOperationJournalEvent -Path $script:journal -TransactionId 'T1' -OperationId 'test' -Sequence 2 -Phase WorkerSucceeded -OperationKind WorkerDiagnostic -WorkerProcessId 12)
        Mock Invoke-OPAWorkerControlledOperation { throw 'Must not be dispatched' }
        { Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T2' -Operation Ping } | Should -Throw '*filename does not match*'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Exactly -Times 0
    }

    It 'refuses to dispatch when the journal has an unterminated final line' {
        [IO.Directory]::CreateDirectory($script:directory) | Out-Null
        [IO.File]::WriteAllText($script:journal, '{"V":', (New-Object System.Text.UTF8Encoding($false)))
        Mock Invoke-OPAWorkerControlledOperation { throw 'Must not be dispatched' }
        { Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Ping } | Should -Throw
        Should -Invoke Invoke-OPAWorkerControlledOperation -Exactly -Times 0
    }

    It 'refuses concurrent controllers using a lock file' {
        [IO.Directory]::CreateDirectory($script:directory) | Out-Null
        $lock = [IO.FileStream]::new(($script:journal + '.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            { Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Ping } | Should -Throw
            Test-Path -LiteralPath $script:journal | Should -BeFalse
        }
        finally { $lock.Dispose() }
    }

    It 'does not convert a mismatched response into a verified success' {
        Mock Invoke-OPAWorkerControlledOperation {
            [pscustomobject]@{ Status='Succeeded'; RequestId='mismatched-id'; WorkerProcessId=111; FailureKind='None'; Error='' }
        }
        $r = Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Ping
        $r.Status | Should -Be 'Indeterminate'
        (Get-OPAWorkerOperationJournalState -JournalPath $script:journal).BlockAutomaticRetry | Should -BeTrue
    }

    It 'appends monotonically after an earlier completed diagnostic operation' {
        Mock Invoke-OPAWorkerControlledOperation {
            [pscustomobject]@{ Status='Succeeded'; RequestId=$RequestId; WorkerProcessId=111; FailureKind='None'; Error='' }
        }
        $one = Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Ping
        $two = Invoke-OPAWorkerJournaledOperation -JournalPath $script:journal -TransactionId 'T1' -Operation Echo
        $one.RequestId | Should -Not -Be $two.RequestId
        (Get-OPAWorkerOperationJournalState -JournalPath $script:journal).LastSequence | Should -Be 4
        @((Read-OPAOperationJournal -Path $script:journal).Events).Count | Should -Be 4
    }
}
