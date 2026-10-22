BeforeAll {
    . "$PSScriptRoot/../../Core/Version.ps1"
    . "$PSScriptRoot/../../Core/Runtime/JsonSupport.ps1"
    . "$PSScriptRoot/../../Core/Archive/ArchiveTransaction.ps1"
    . "$PSScriptRoot/../../Core/Archive/DuplicateIndex.ps1"
}

Describe 'DuplicateIndex round-trip' {
    BeforeEach {
        # Cleanup-Journal-TestDrive: both the legacy .json base and the
        # append-only .jsonl journal must be removed between It blocks,
        # otherwise entries leak across tests. Close any journal FileStream
        # first so Windows lets us delete the file.
        if (Get-Command Close-OPADuplicateJournalStreams -ErrorAction SilentlyContinue) {
            Close-OPADuplicateJournalStreams
        }

        $script:archivePst = Join-Path $TestDrive 'user.Archive-2023.pst'
        [IO.File]::WriteAllBytes($script:archivePst, @())

        $txDir = Join-Path $TestDrive 'OutlookPOP3Archive-Transactions'
        $indexJson  = Join-Path $txDir 'DuplicateIndex.json'
        $indexJsonl = Join-Path $txDir 'DuplicateIndex.jsonl'
        if (Test-Path -LiteralPath $indexJson)  { Remove-Item -LiteralPath $indexJson  -Force }
        if (Test-Path -LiteralPath $indexJsonl) { Remove-Item -LiteralPath $indexJsonl -Force }
    }
    It 'creates an empty index when the file is missing' {
        $idx = Import-OPADuplicateIndex -ArchivePst $script:archivePst
        @($idx.Entries) | Should -Be @()
        $idx.SourceIdSet.Count | Should -Be 0
    }
    It 'persists and reloads entries' {
        $idx = Import-OPADuplicateIndex -ArchivePst $script:archivePst
        Add-OPADuplicateEntry -Index $idx -SourceEntryId 'S1' -ArchiveEntryId 'D1' -TransactionId 'T1' -TransactionLimit 10 -ArchivePst $script:archivePst
        Add-OPADuplicateEntry -Index $idx -SourceEntryId 'S2' -ArchiveEntryId 'D2' -TransactionId 'T1' -TransactionLimit 10 -ArchivePst $script:archivePst
        Save-OPADuplicateIndex -Index $idx -ArchivePst $script:archivePst

        $loaded = Import-OPADuplicateIndex -ArchivePst $script:archivePst
        @($loaded.Entries).Count | Should -Be 2
        $loaded.SourceIdSet.Contains('S1') | Should -BeTrue
        (Test-OPADuplicateEntry -Index $loaded -SourceEntryId 'S2').ArchiveEntryId | Should -Be 'D2'
    }
    It 'does not duplicate entries and enriches empty destination ids' {
        $idx = Import-OPADuplicateIndex -ArchivePst $script:archivePst
        Add-OPADuplicateEntry -Index $idx -SourceEntryId 'S1' -ArchiveEntryId $null -TransactionId 'T1' -ArchivePst $script:archivePst
        Add-OPADuplicateEntry -Index $idx -SourceEntryId 'S1' -ArchiveEntryId 'D1' -TransactionId 'T1' -ArchivePst $script:archivePst
        @($idx.Entries).Count | Should -Be 1
        $idx.Entries[0].ArchiveEntryId | Should -Be 'D1'
    }
    AfterAll {
        if (Get-Command Close-OPADuplicateJournalStreams -ErrorAction SilentlyContinue) {
            Close-OPADuplicateJournalStreams
        }
    }
}

Describe 'Sync-OPADuplicateIndexFromJournal' {
    BeforeEach {
        # Same cleanup as the first Describe: this Describe also writes
        # index files under $TestDrive and would otherwise leak entries
        # or hold journal streams open across runs.
        if (Get-Command Close-OPADuplicateJournalStreams -ErrorAction SilentlyContinue) {
            Close-OPADuplicateJournalStreams
        }
        $txDir = Join-Path $TestDrive 'OutlookPOP3Archive-Transactions'
        foreach ($n in @('DuplicateIndex.json','DuplicateIndex.jsonl')) {
            $p = Join-Path $txDir $n
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
        }
    }
    It 'heals missing entries from the step journal (idempotent)' {
        $src = Join-Path $TestDrive 'src.pst'
        [IO.File]::WriteAllBytes($src, @())
        $tx = New-OPAArchiveTransaction -SourcePst $src -ArchivePst '' -Limit 10 -SourcePstSizeBeforeBytes 1 -AccountEmail 'a@b.c'
        $archivePst = Join-Path $TestDrive 'user.Archive-2023.pst'
        [IO.File]::WriteAllBytes($archivePst, @())
        Save-OPAArchiveTransaction -Transaction $tx -Status 'Running' -Step 'Move 1/10' -Message 'm' `
            -EntryId 'S1' -ArchiveEntryId 'D1' -ArchivePst $archivePst

        $idx = Import-OPADuplicateIndex -ArchivePst $archivePst
        $added = Sync-OPADuplicateIndexFromJournal -Transaction $tx -Index $idx -ArchivePst $archivePst
        $added | Should -Be 1
        $addedAgain = Sync-OPADuplicateIndexFromJournal -Transaction $tx -Index $idx -ArchivePst $archivePst
        $addedAgain | Should -Be 0
        @($idx.Entries).Count | Should -Be 1
    }
    AfterAll {
        if (Get-Command Close-OPADuplicateJournalStreams -ErrorAction SilentlyContinue) {
            Close-OPADuplicateJournalStreams
        }
    }
}

AfterAll {
    # A long-lived FileStream keeps the step journal open for the whole
    # session. Pester needs to delete $TestDrive, and on Windows the file
    # remains locked until the handle is closed. Close it here.
    if (Get-Command Close-OPAStepJournalStreams -ErrorAction SilentlyContinue) {
        Close-OPAStepJournalStreams
    }
}
