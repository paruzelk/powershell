#requires -Version 5.1
BeforeAll {
    $script:restart = Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA263RestartReadOnly.ps1'
    $script:source = [IO.File]::ReadAllText($script:restart)
}
Describe '2.6.3 restart read-only COM test safety policy' {
    It 'requires an existing journal and one unresolved MailMove Intent' {
        $script:source | Should -Match 'Read-OPAOperationJournal'
        $script:source | Should -Match 'Resolve-OPAOperationRecovery'
        $script:source | Should -Match "pending.Count -ne 1"
    }
    It 'uses attached Outlook only and does not create, attach or detach PSTs' {
        $script:source | Should -Match 'GetActiveObject'
        $script:source | Should -Not -Match 'New-Object -ComObject'
        $script:source | Should -Not -Match '\.AddStore'
        $script:source | Should -Not -Match '\.RemoveStore'
    }
    It 'does not mutate items or append journal terminal events' {
        $script:source | Should -Not -Match '\.Move\('
        $script:source | Should -Not -Match '\.Copy\('
        $script:source | Should -Not -Match '\.Delete\('
        $script:source | Should -Not -Match 'Write-OPAOperationJournalEvent\s+-'
    }
    It 'requires exact persisted StoreID and destination PST path' {
        $script:source | Should -Match 'SourceStoreId'
        $script:source | Should -Match 'GetFullPath'
        $script:source | Should -Match 'StoreID'
        $script:source | Should -Match 'ExpectedPath'
        $script:source | Should -Match 'Do NOT substitute another store'
    }
    It 'enforces journal SHA-256 unchanged and reject automatic retry' {
        $script:source | Should -Match 'hashBefore'
        $script:source | Should -Match 'hashAfter'
        $script:source | Should -Match 'AutomaticRetryAllowed'
        $script:source | Should -Match 'ProvenMoved'
        $script:source | Should -Match 'RequiresManualReview'
    }
    It 'fails closed if Outlook shows a different state after restart' {
        $script:source | Should -Match 'ExpectedStatus'
        $script:source | Should -Match 'Restart read-only classification mismatch'
    }
}
