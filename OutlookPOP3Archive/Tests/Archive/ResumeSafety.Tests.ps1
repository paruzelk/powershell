Describe 'FIX8 Resume safety invariants' {
    BeforeAll {
        $script:moverSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../Core/Archive/MailMover.ps1'))
    }
    It 'does not create replacement candidates during Resume' {
        $start = $script:moverSource.IndexOf('    # --- Candidate pool ---', [StringComparison]::Ordinal)
        $start | Should -BeGreaterThan -1
        $end = $script:moverSource.IndexOf('    else {', $start, [StringComparison]::Ordinal)
        $end | Should -BeGreaterThan $start
        $resumeBlock = $script:moverSource.Substring($start, $end - $start)
        $resumeBlock | Should -Not -Match '\$resumeRows'
        $resumeBlock | Should -Match 'candidatePool = @\(\$candidates\)'
    }
    It 'checks duplicates and count mismatch before moving' {
        $script:moverSource | Should -Match 'PlannedItems contains an empty or duplicate EntryId'
        $script:moverSource | Should -Match 'PlannedItems count does not match transaction Planned/Limit'
    }
    It 'fails closed on missing source items when resuming' {
        $script:moverSource | Should -Match 'Resume safety: planned source item'
        # FIX8b: missing source item must be reconciled from the persisted archive,
        # not retried as a fresh Move or treated as an ordinary skip.
        $script:moverSource | Should -Match 'Find-OPAInterruptedMoveInArchive -Namespace'
        $script:moverSource | Should -Match 'Resume safety: found \{0\} matching archive messages'
        $script:moverSource | Should -Match 'Resume safety: no durable Move Started event'
    }
}
