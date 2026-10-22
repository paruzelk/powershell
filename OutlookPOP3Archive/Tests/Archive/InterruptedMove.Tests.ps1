Describe 'FIX8b interrupted Move safety' {
    BeforeAll {
        $script:mover = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../Core/Archive/MailMover.ps1'))
    }
    It 'requires durable Move Started event' {
        $script:mover | Should -Match 'no durable Move Started event'
    }
    It 'requires unique archive fingerprint match' {
        $script:mover | Should -Match 'missing InternetMessageId'
        $script:mover | Should -Match 'matches.Count -ne 1'
    }
    It 'writes Move Completed and index after archive reconciliation' {
        $script:mover | Should -Match 'ReconciledFromArchive after interrupted Move'
        $script:mover | Should -Match 'Find-OPAInterruptedMoveInArchive'
    }
}
