#requires -Version 5.1
BeforeAll {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Core\Archive\OperationJournal.ps1')
}
Describe '2.6.2 durable operation journal' {
    BeforeEach {
        $script:path = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.operations.jsonl')
    }

    It 'records and reads a hash-verified Intent' {
        $written = Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Intent -SourceEntryId 'S1' -ArchivePst 'archive.pst'
        $written.Phase | Should -Be 'Intent'
        $read = Read-OPAOperationJournal -Path $script:path
        @($read.Events).Count | Should -Be 1
        $read.TrailingPartial | Should -BeFalse
        $read.Events[0].SourceEntryId | Should -Be 'S1'
    }

    It 'does not allow completion without an archive EntryId' {
        { Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Completed } | Should -Throw
        Test-Path -LiteralPath $script:path | Should -BeFalse
    }

    It 'reports an Intent without a durable completion as Indeterminate' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Intent -SourceEntryId 'S1' | Out-Null
        $recovery = Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path)
        @($recovery.Indeterminate).Count | Should -Be 1
        $recovery.BlockAutomaticRetry | Should -BeTrue
        $recovery.RequiresPstReconciliation | Should -BeTrue
    }

    It 'recognizes durable Completed without marking it for retry' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Intent -SourceEntryId 'S1' | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 2 -Phase Completed -ArchiveEntryId 'A1' | Out-Null
        $recovery = Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path)
        @($recovery.Resolved).Count | Should -Be 1
        $recovery.BlockAutomaticRetry | Should -BeFalse
        $recovery.Resolved[0].ArchiveEntryId | Should -Be 'A1'
    }

    It 'rejects a completion with no preceding Intent' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Completed -ArchiveEntryId 'A1' | Out-Null
        { Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path) } | Should -Throw
    }

    It 'rejects altered hash-verification metadata' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Intent -SourceEntryId 'S1' | Out-Null
        $line = [IO.File]::ReadAllText($script:path)
        $corrupt = $line -replace '("Sha256":"?)[a-f0-9]{64}', ('${1}' + ('0' * 64))
        [IO.File]::WriteAllText($script:path, $corrupt, (New-Object Text.UTF8Encoding($false)))
        { Read-OPAOperationJournal -Path $script:path } | Should -Throw
    }

    It 'detects and preserves a truncated final record, blocking auto retry and append' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Intent -SourceEntryId 'S1' | Out-Null
        [IO.File]::AppendAllText($script:path, '{"V":1,"Payload":', (New-Object Text.UTF8Encoding($false)))
        $read = Read-OPAOperationJournal -Path $script:path
        $read.TrailingPartial | Should -BeTrue
        $read.Events.Count | Should -Be 1
        (Resolve-OPAOperationRecovery -Journal $read).BlockAutomaticRetry | Should -BeTrue
        { Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 2 -Phase Completed -ArchiveEntryId 'A1' } | Should -Throw
    }

    It 'rejects non-monotonic sequence values' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 2 -Phase Intent -SourceEntryId 'S1' | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Completed -ArchiveEntryId 'A1' | Out-Null
        { Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path) } | Should -Throw
    }

    It 'rejects a second terminal event for the same operation' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 1 -Phase Intent -SourceEntryId 'S1' | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 2 -Phase Completed -ArchiveEntryId 'A1' | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'O1' -Sequence 3 -Phase Completed -ArchiveEntryId 'A1' | Out-Null
        { Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path) } | Should -Throw
    }

    It 'supports a diagnostic worker success without claiming a MailMove completed' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'req-1' -Sequence 1 -Phase Intent -OperationKind WorkerDiagnostic | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'req-1' -Sequence 2 -Phase WorkerSucceeded -OperationKind WorkerDiagnostic -WorkerProcessId 20 | Out-Null
        $state = Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path)
        $state.BlockAutomaticRetry | Should -BeFalse
        $state.Resolved[0].Status | Should -Be 'WorkerSucceeded'
    }

    It 'requires a positive PID when recording worker success' {
        { Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'req-1' -Sequence 1 -Phase WorkerSucceeded -OperationKind WorkerDiagnostic } | Should -Throw
    }

    It 'disallows late success after an explicit Indeterminate event' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'req-1' -Sequence 1 -Phase Intent -OperationKind WorkerDiagnostic | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'req-1' -Sequence 2 -Phase Indeterminate -OperationKind WorkerDiagnostic | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'req-1' -Sequence 3 -Phase WorkerSucceeded -OperationKind WorkerDiagnostic -WorkerProcessId 20 | Out-Null
        { Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path) } | Should -Throw
    }

    It 'rejects changing OperationKind across Intent and terminal event' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'same' -Sequence 1 -Phase Intent -OperationKind WorkerDiagnostic | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'same' -Sequence 2 -Phase Reconciled -ArchiveEntryId 'A1' | Out-Null
        { Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path) } | Should -Throw
    }

    It 'permits only independently proven Reconciled after a MailMove Indeterminate' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'same' -Sequence 1 -Phase Intent -SourceEntryId 'S1' | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'same' -Sequence 2 -Phase Indeterminate | Out-Null
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'T1' -OperationId 'same' -Sequence 3 -Phase Reconciled -ArchiveEntryId 'A1' | Out-Null
        $state = Resolve-OPAOperationRecovery -Journal (Read-OPAOperationJournal -Path $script:path)
        $state.BlockAutomaticRetry | Should -BeFalse
        $state.Resolved[0].ArchiveEntryId | Should -Be 'A1'
    }
}
