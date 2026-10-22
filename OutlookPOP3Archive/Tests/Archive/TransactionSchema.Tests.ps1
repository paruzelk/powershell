BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'Core\Version.ps1')
    . (Join-Path $repoRoot 'Core\Runtime\JsonSupport.ps1')
    . (Join-Path $repoRoot 'Core\Runtime\ComManager.ps1')
    . (Join-Path $repoRoot 'Core\Archive\DuplicateIndex.ps1')
    . (Join-Path $repoRoot 'Core\Archive\ArchiveTransaction.ps1')
    . (Join-Path $repoRoot 'Core\Archive\MailMover.ps1')

    function New-TestTransaction {
        $src = Join-Path $TestDrive ('src-{0}.pst' -f [guid]::NewGuid().ToString('N'))
        New-OPAArchiveTransaction -SourcePst $src -ArchivePst '' -Limit 10 -ArchiveGrouping 'YearQuarter' `
            -OlderThanMonths 12 -ArchiveCutoff (Get-Date).AddMonths(-12) -SourcePstSizeBeforeBytes 1024 -AccountEmail 'a@b.c'
    }
}

Describe 'Test-OPAArchiveTransactionSchema' {
    It 'accepts a freshly created transaction' {
        $tx = New-TestTransaction
        Test-OPAArchiveTransactionSchema -TransactionState $tx.State | Should -BeTrue
    }
    It 'rejects a null state' {
        { Test-OPAArchiveTransactionSchema -TransactionState $null } | Should -Throw
    }
    It 'rejects a missing required field' {
        $tx = New-TestTransaction
        # PSObject.Properties.Remove() is a no-op on [ordered]@{} under PS 5.1.
        # Use the IDictionary API which actually removes the entry.
        $tx.State.Remove('SourcePst')
        { Test-OPAArchiveTransactionSchema -TransactionState $tx.State } | Should -Throw
    }
    It 'rejects an unsupported schema version' {
        $tx = New-TestTransaction
        $tx.State.SchemaVersion = '1.0'
        { Test-OPAArchiveTransactionSchema -TransactionState $tx.State } | Should -Throw
    }
    It 'rejects a non-positive limit' {
        $tx = New-TestTransaction
        $tx.State.Limit = 0
        { Test-OPAArchiveTransactionSchema -TransactionState $tx.State } | Should -Throw
    }
}

Describe 'New-OPAArchiveTransaction' {
    It 'writes the current schema version and application version' {
        $tx = New-TestTransaction
        $tx.State.SchemaVersion | Should -Be $script:OPATransactionSchemaVersion
        $tx.State.ApplicationVersion | Should -Be $script:OPAApplicationVersion
        Test-Path -LiteralPath $tx.Path | Should -BeTrue
    }
    It 'creates a loadable checkpoint' {
        $tx = New-TestTransaction
        $loaded = Get-OPAArchiveTransaction -SourcePst $tx.State.SourcePst -TransactionId $tx.TransactionId
        $loaded.TransactionId | Should -Be $tx.TransactionId
    }

    It 'initializes performance state for new transactions' {
        $tx = New-TestTransaction
        $tx.State.Performance | Should -Not -BeNullOrEmpty
        $tx.State.Performance.MovesThisRun | Should -Be 0
        $tx.State.Performance.ResumeMovedNow | Should -Be 0
    }

    It 'adds performance state to a legacy PSCustomObject transaction' {
        $legacy = [pscustomobject]@{ TransactionId = 'legacy' }
        $perf = Ensure-OPATransactionPerformance -TransactionState $legacy
        $perf | Should -Not -BeNullOrEmpty
        $legacy.PSObject.Properties.Name | Should -Contain 'Performance'
        $perf['MovesThisRun'] = 7
        $legacy.Performance['MovesThisRun'] | Should -Be 7
    }
}

Describe 'Step journal' {
    It 'appends steps to the journal and keeps the sliding window' {
        $tx = New-TestTransaction
        1..($script:OPAStepsInlineLimit + 20) | ForEach-Object {
            Save-OPAArchiveTransaction -Transaction $tx -Status 'Running' -Step "Move $_/300" -Message 'm' -EntryId "E$_"
        }
        $journal = @(Read-OPAStepJournal -Transaction $tx)
        $journal.Count | Should -Be ($script:OPAStepsInlineLimit + 20)
        @($tx.State.Steps).Count | Should -Be $script:OPAStepsInlineLimit
        Save-OPAArchiveTransaction -Transaction $tx -Status 'Completed' -Step 'Verify' -Message 'done'
        $loaded = Get-OPAArchiveTransaction -SourcePst $tx.State.SourcePst -TransactionId $tx.TransactionId
        @($loaded.State.Steps).Count | Should -Be $script:OPAStepsInlineLimit
        $loaded.State.Status | Should -Be 'Completed'
    }
}

Describe 'Get-OPAResumeCompletionState' {
    It 'unions steps and duplicate index entries' {
        $tx = New-TestTransaction
        $tx.State.PlannedItems = @(
            [pscustomobject]@{ EntryId = 'A' }, [pscustomobject]@{ EntryId = 'B' }, [pscustomobject]@{ EntryId = 'C' }
        )
        $tx.State.Steps = @([pscustomobject]@{ Step = 'Move 1/10'; EntryId = 'A'; ArchiveEntryId = 'A1' })
        $idx = [pscustomobject]@{
            Entries = @(
                [pscustomobject]@{ TransactionId = $tx.TransactionId; SourceEntryId = 'B'; ArchiveEntryId = 'B1' },
                [pscustomobject]@{ TransactionId = $tx.TransactionId; SourceEntryId = 'X'; ArchiveEntryId = 'X1' }
            )
        }
        $c = Get-OPAResumeCompletionState -Transaction $tx -DuplicateIndex $idx
        $c.CompletedCount | Should -Be 2
        $c.SourceEntryIds | Should -Be @('A','B')
        $c.ArchiveEntryIds | Should -Be @('A1','B1')
    }
}

Describe 'Get-OPAArchivePstGrowthRatio' {
    BeforeEach {
        $script:tmpSrc = Join-Path $TestDrive 'src.pst'
        $script:tmpArc = Join-Path $TestDrive 'a.pst'
    }

    It 'returns default ratio when logical sample is below threshold' {
        $tx = New-OPAArchiveTransaction -SourcePst $script:tmpSrc -ArchivePst '' `
            -Limit 10 -SourcePstSizeBeforeBytes 0 -AccountEmail 'a@b.c'
        Register-OPAArchivePstInTransaction -Transaction $tx -ArchivePst $script:tmpArc `
            -Year 2020 -Part 1 -PhysicalSizeBeforeBytes 1000
        $idx = @($tx.State.ArchivePsts | Where-Object { $_.Path -eq $script:tmpArc })[0]
        $idx.LogicalAddedBytes = 1MB
        $idx.PhysicalGrowthBytes = 3MB

        $ratio = Get-OPAArchivePstGrowthRatio -Transaction $tx -ArchivePst $script:tmpArc
        $ratio | Should -Be 2.0
    }

    It 'clamps ratio to the configured maximum' {
        $tx = New-OPAArchiveTransaction -SourcePst $script:tmpSrc -ArchivePst '' `
            -Limit 10 -SourcePstSizeBeforeBytes 0 -AccountEmail 'a@b.c'
        Register-OPAArchivePstInTransaction -Transaction $tx -ArchivePst $script:tmpArc `
            -Year 2020 -Part 1 -PhysicalSizeBeforeBytes 1000
        $idx = @($tx.State.ArchivePsts | Where-Object { $_.Path -eq $script:tmpArc })[0]
        $idx.LogicalAddedBytes = 100MB
        $idx.PhysicalGrowthBytes = 5000MB

        $ratio = Get-OPAArchivePstGrowthRatio -Transaction $tx -ArchivePst $script:tmpArc
        $ratio | Should -Be 5.0
    }

    It 'returns observed ratio within [min, max] once sample is large enough' {
        $tx = New-OPAArchiveTransaction -SourcePst $script:tmpSrc -ArchivePst '' `
            -Limit 10 -SourcePstSizeBeforeBytes 0 -AccountEmail 'a@b.c'
        Register-OPAArchivePstInTransaction -Transaction $tx -ArchivePst $script:tmpArc `
            -Year 2020 -Part 1 -PhysicalSizeBeforeBytes 1000
        $idx = @($tx.State.ArchivePsts | Where-Object { $_.Path -eq $script:tmpArc })[0]
        $idx.LogicalAddedBytes = 100MB
        $idx.PhysicalGrowthBytes = 180MB

        $ratio = Get-OPAArchivePstGrowthRatio -Transaction $tx -ArchivePst $script:tmpArc
        [Math]::Abs($ratio - 1.8) | Should -BeLessThan 0.01
    }

    It 'returns default for an unregistered PST' {
        $tx = New-OPAArchiveTransaction -SourcePst $script:tmpSrc -ArchivePst '' `
            -Limit 10 -SourcePstSizeBeforeBytes 0 -AccountEmail 'a@b.c'
        (Get-OPAArchivePstGrowthRatio -Transaction $tx -ArchivePst 'C:\nope.pst') | Should -Be 2.0
    }
}

AfterAll {
    if (Get-Command Close-OPAStepJournalStreams -ErrorAction SilentlyContinue) {
        Close-OPAStepJournalStreams
    }
}

Describe 'Move completion semantics' {
    It 'does not count Move Started as completed' {
        (Test-OPAMoveCompletionStep -Step ([pscustomobject]@{ Step='Move Started'; EntryId='A' })) | Should -BeFalse
    }
    It 'counts Move Completed and legacy Move n/n' {
        (Test-OPAMoveCompletionStep -Step ([pscustomobject]@{ Step='Move Completed'; EntryId='A' })) | Should -BeTrue
        (Test-OPAMoveCompletionStep -Step ([pscustomobject]@{ Step='Move 1/50'; EntryId='A' })) | Should -BeTrue
    }
}


Describe 'Test-OPAStateHasKey' {
    It 'detects keys in an ordered dictionary used by new transactions' {
        $state = [ordered]@{ DurabilityMode = 'Safe' }
        Test-OPAStateHasKey -State $state -Name 'DurabilityMode' | Should -BeTrue
        Test-OPAStateHasKey -State $state -Name 'Missing' | Should -BeFalse
    }
    It 'detects properties in a loaded PSCustomObject checkpoint' {
        $state = [pscustomobject]@{ DurabilityMode = 'Safe' }
        Test-OPAStateHasKey -State $state -Name 'DurabilityMode' | Should -BeTrue
        Test-OPAStateHasKey -State $state -Name 'Missing' | Should -BeFalse
    }
    It 'returns false for a null state' {
        Test-OPAStateHasKey -State $null -Name 'DurabilityMode' | Should -BeFalse
    }
}
