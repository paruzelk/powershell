#requires -Version 5.1
BeforeAll {
    $script:harness = Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA263LivePstTest.ps1'
    $script:text = [IO.File]::ReadAllText($script:harness)
}
Describe '2.6.3 disposable PST integration harness safety gates' {
    It 'requires explicit Execute opt-in before opening Outlook or creating PSTs' {
        { & $script:harness -SeedPstPath (Join-Path $TestDrive 'fake.pst') } | Should -Throw '*Pass -Execute*'
    }

    It 'never calls a journal terminal event in a crash-window diagnostic' {
        $script:text | Should -Match 'Write-OPAOperationJournalEvent'
        $script:text | Should -Match '\-Phase Intent'
        $script:text | Should -Not -Match '\-Phase Completed'
        $script:text | Should -Not -Match '\-Phase Reconciled'
    }

    It 'stages its own temporary PSTs rather than mounting existing archive part filenames' {
        $script:text | Should -Match 'OPA263-Source\.pst'
        $script:text | Should -Match 'OPA263-Archive\.pst'
        $script:text | Should -Match 'AddStoreEx'
        $script:text | Should -Not -Match '\.Archive-2019\.pst'
        $script:text | Should -Not -Match '\.Archive-2020\.pst'
    }

    It 'performs no deletion or force-removal of existing mail or files' {
        $script:text | Should -Not -Match '\.Delete\('
        $script:text | Should -Not -Match 'Remove-Item\b'
        $script:text | Should -Not -Match 'RemoveStore\('
        $script:text | Should -Not -Match '\.Quit\('
    }

    It 'stages the second destination duplicate by moving the copied item to a disposable folder and back' {
        $script:text | Should -Match '\$duplicate = \$destinationMail.Copy\(\)'
        $script:text | Should -Match '\$duplicateInSource = \$duplicate.Move\(\$sourceFolder\)'
        $script:text | Should -Match '\$duplicateInArchive = \$duplicateInSource.Move\(\$archiveFolder\)'
        $script:text | Should -Match 'DistinctSecondDestinationEntryId'
    }

    It 'records actual source and destination fingerprint observations before expecting Ambiguous' {
        $script:text | Should -Match 'New-OPAReadOnlyMoveSnapshot'
        $script:text | Should -Match 'DestinationFingerprintMatches'
        $script:text | Should -Match 'DestinationMessageIdMatches'
        $script:text | Should -Match 'DestinationSizeValues'
        $script:text | Should -Match 'DuplicateDiagnostics=\$duplicateDiagnostics'
    }

    It 'tests first Move and then keeps journal unresolved and automatic retry blocked' {
        $script:text | Should -Match 'First controlled Move'
        $script:text | Should -Match 'DestinationCandidate'
        $script:text | Should -Match 'BothPresent'
        $script:text | Should -Match 'Ambiguous'
        $script:text | Should -Match 'BlockAutomaticRetry'
        $script:text | Should -Match 'LastSequence -ne 1'
    }
}
