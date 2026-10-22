# Behavioral tests for FIX9 (no Outlook required).
BeforeAll {
    # ArchiveVerifier depends on Test-OPAStateHasKey in ArchiveTransaction.
    # Match the production dot-source dependency order so tests are self-contained.
    . "$PSScriptRoot/../../Core/Archive/ArchiveTransaction.ps1"
    . "$PSScriptRoot/../../Core/Archive/ArchiveVerifier.ps1"
    function Test-OPAMoveCompletionStep { param($Step) return ([string]$Step.Step -eq 'Move Completed') }
    function Read-OPAStepJournal { param($Transaction) return $script:fakeSteps }
    function Release-OPAComObject { param($Object) }
    function Get-OPAInternetMessageId { param($Item) return [string]$Item.InternetMessageId }

    function New-FakeItems {
        param([object[]]$Rows)
        $items = [pscustomobject]@{ Count=$Rows.Count; Rows=$Rows }
        $items | Add-Member -MemberType ScriptMethod -Name Item -Value { param([int]$N) return $this.Rows[$N - 1] }
        return $items
    }
    function New-FakeFolder {
        param([string]$Name,[string]$Path,[object[]]$Messages=@(),[object[]]$Children=@())
        return [pscustomobject]@{Name=$Name;FolderPath=$Path;Items=(New-FakeItems -Rows $Messages);Folders=$Children}
    }
    function New-FakeMessage {
        param([string]$Id,[string]$MsgId,[object]$Parent)
        return [pscustomobject]@{
            EntryID=$Id; InternetMessageId=$MsgId; Class=43; Size=[int64]100;
            Subject='test'; SenderEmailAddress='sender@example.test'; Parent=$Parent
        }
    }
    function New-VerificationFixture {
        $archivePath = Join-Path $TestDrive 'archive.pst'
        $sourcePath = '\\Source\\Inbox'
        $destinationPath = '\\Archive\\2020'
        $source = New-FakeFolder -Name 'Inbox' -Path $sourcePath
        $target = New-FakeFolder -Name '2020' -Path $destinationPath
        $root = New-FakeFolder -Name 'Archive' -Path '\\Archive' -Children @($target)
        $store = [pscustomobject]@{FilePath=$archivePath;StoreID='archive-store';Root=$root}
        $store | Add-Member -MemberType ScriptMethod -Name GetRootFolder -Value { return $this.Root }
        $message = New-FakeMessage -Id 'A1' -MsgId '<abc@example.test>' -Parent $target
        $target.Items = New-FakeItems -Rows @($message)
        $namespace = [pscustomobject]@{ Lookup=@{A1=$message} }
        $namespace | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {
            param([string]$Id,[string]$StoreId)
            if ($this.Lookup.ContainsKey($Id)) { return $this.Lookup[$Id] }
            throw 'Item not found'
        }
        $move = [pscustomobject]@{
            SourceEntryId='S1'; ArchiveEntryId='A1'; ArchivePst=$archivePath;
            TargetFolderPath=$destinationPath; SourceFolderPath=$sourcePath;
            InternetMessageId='<abc@example.test>'; Size=[int64]100;
            Subject='test'; Sender='sender@example.test'
        }
        return [pscustomobject]@{Namespace=$namespace;Store=$store;Source=$source;Target=$target;Move=$move;Message=$message}
    }
}

Describe 'FIX9 independent archive verification' {
    It 'passes only when the message is physically present in its destination folder and absent from the source' {
        $f = New-VerificationFixture
        $r = Test-OPAArchiveMoves -Namespace $f.Namespace -SourceFolder $f.Source -ArchiveStores @($f.Store) -ExpectedMoved 1 -ExpectedMoves @($f.Move)
        $r.Verified | Should -BeTrue
        $r.SourceRemaining | Should -Be 0
        $r.TargetCount | Should -Be 1
    }
    It 'fails if the archive message is missing even when the index says it was moved' {
        $f = New-VerificationFixture
        $f.Namespace.Lookup.Clear()
        $f.Target.Items = New-FakeItems -Rows @()
        $r = Test-OPAArchiveMoves -Namespace $f.Namespace -SourceFolder $f.Source -ArchiveStores @($f.Store) -ExpectedMoved 1 -ExpectedMoves @($f.Move)
        $r.Verified | Should -BeFalse
        @($r.MissingEntryIds | Where-Object { $_ -match 'ARCHIVE_ITEM_NOT_VERIFIED' }).Count | Should -Be 1
    }
    It 'fails if the source item is still present' {
        $f = New-VerificationFixture
        $sourceMessage = New-FakeMessage -Id 'S1' -MsgId '<abc@example.test>' -Parent $f.Source
        $f.Source.Items = New-FakeItems -Rows @($sourceMessage)
        $r = Test-OPAArchiveMoves -Namespace $f.Namespace -SourceFolder $f.Source -ArchiveStores @($f.Store) -ExpectedMoved 1 -ExpectedMoves @($f.Move)
        $r.Verified | Should -BeFalse
        $r.SourceRemaining | Should -Be 1
        @($r.MissingEntryIds | Where-Object { $_ -match 'STILL_IN_SOURCE' }).Count | Should -Be 1
    }
    It 'falls back to a unique message fingerprint when destination EntryID changed' {
        $f = New-VerificationFixture
        $f.Namespace.Lookup.Clear()
        $f.Target.Items.Rows[0].EntryID = 'NEW-A1'
        $r = Test-OPAArchiveMoves -Namespace $f.Namespace -SourceFolder $f.Source -ArchiveStores @($f.Store) -ExpectedMoved 1 -ExpectedMoves @($f.Move)
        $r.Verified | Should -BeTrue
        @($r.WarningEntryIds).Count | Should -Be 1
    }
    It 'rejects ambiguous fingerprint matches' {
        $f = New-VerificationFixture
        $f.Namespace.Lookup.Clear()
        $other = New-FakeMessage -Id 'A2' -MsgId '<abc@example.test>' -Parent $f.Target
        $f.Target.Items = New-FakeItems -Rows @($f.Message, $other)
        $r = Test-OPAArchiveMoves -Namespace $f.Namespace -SourceFolder $f.Source -ArchiveStores @($f.Store) -ExpectedMoved 1 -ExpectedMoves @($f.Move)
        $r.Verified | Should -BeFalse
    }
    It 'requires the number of completed pairs to match the transaction count' {
        $f = New-VerificationFixture
        $r = Test-OPAArchiveMoves -Namespace $f.Namespace -SourceFolder $f.Source -ArchiveStores @($f.Store) -ExpectedMoved 2 -ExpectedMoves @($f.Move)
        $r.Verified | Should -BeFalse
    }
}

Describe 'FIX9 completed-pair construction and accounting' {
    BeforeEach { $script:fakeSteps = @() }
    It 'rebuilds unique completed moves using persisted plan and journal' {
        $p1 = [pscustomobject]@{EntryId='A';SourceFolderPath='x';InternetMessageId='m';Subject='s';Sender='z';Size=[int64]100}
        $p2 = [pscustomobject]@{EntryId='B';SourceFolderPath='x';InternetMessageId='m2';Subject='s2';Sender='z';Size=[int64]200}
        $tx = [pscustomobject]@{Path='dummy';TransactionId='tx1';State=[pscustomobject]@{PlannedItems=@($p1,$p2)}}
        $script:fakeSteps = @(
            [pscustomobject]@{Step='Move Completed';EntryId='A';ArchiveEntryId='A1';ArchivePst='a.pst';TargetFolderPath='\\Arc\\2020'},
            [pscustomobject]@{Step='Move Completed';EntryId='A';ArchiveEntryId='A1';ArchivePst='a.pst';TargetFolderPath='\\Arc\\2020'},
            [pscustomobject]@{Step='Move Completed';EntryId='X';ArchiveEntryId='X1';ArchivePst='a.pst';TargetFolderPath='\\Arc\\2020'}
        )
        $idx = [pscustomobject]@{Entries=@([pscustomobject]@{TransactionId='tx1';SourceEntryId='B';ArchiveEntryId='B1';ArchivePst='a.pst';TargetFolderPath='\\Arc\\2020'})}
        $rows = @(Get-OPAExpectedMovesFromTransaction -Transaction $tx -DuplicateIndex $idx)
        $rows.Count | Should -Be 2
        (Get-OPACompletedLogicalBytes -Transaction $tx -CompletedMoves $rows) | Should -Be 300
    }
    It 'rejects conflicting archive IDs for one source item' {
        $tx = [pscustomobject]@{Path='dummy';TransactionId='tx1';State=[pscustomobject]@{PlannedItems=@([pscustomobject]@{EntryId='A'})}}
        $script:fakeSteps = @([pscustomobject]@{Step='Move Completed';EntryId='A';ArchiveEntryId='A1';ArchivePst='a.pst';TargetFolderPath='\\Arc\\2020'})
        $idx = [pscustomobject]@{Entries=@([pscustomobject]@{TransactionId='tx1';SourceEntryId='A';ArchiveEntryId='A2';ArchivePst='a.pst';TargetFolderPath='\\Arc\\2020'})}
        { Get-OPAExpectedMovesFromTransaction -Transaction $tx -DuplicateIndex $idx } | Should -Throw
    }
    It 'rejects duplicate completion IDs before logical accounting' {
        $tx = [pscustomobject]@{State=[pscustomobject]@{PlannedItems=@()}}
        $rows = @([pscustomobject]@{SourceEntryId='A';Size=[int64]100},[pscustomobject]@{SourceEntryId='A';Size=[int64]100})
        { Get-OPACompletedLogicalBytes -Transaction $tx -CompletedMoves $rows } | Should -Throw
    }
}

Describe 'FIX9 verifier helper dependency' {
    It 'loads Test-OPAStateHasKey for OrderedDictionary and PSCustomObject states' {
        (Get-Command Test-OPAStateHasKey -CommandType Function -ErrorAction Stop).Name | Should -Be 'Test-OPAStateHasKey'
        $dictionaryState = [ordered]@{ LogicalAddedBytes = [int64]0 }
        $objectState = [pscustomobject]@{ LogicalAddedBytes = [int64]0 }
        Test-OPAStateHasKey -State $dictionaryState -Name 'LogicalAddedBytes' | Should -BeTrue
        Test-OPAStateHasKey -State $objectState -Name 'LogicalAddedBytes' | Should -BeTrue
    }
}

Describe 'FIX9 archive PST logical telemetry' {
    It 'reconstructs logical bytes for each archive part from completed moves' {
        $p1 = Join-Path $TestDrive 'a.pst'
        $p2 = Join-Path $TestDrive 'b.pst'
        $tx = [pscustomobject]@{State=[pscustomobject]@{ArchivePsts=@(
            [pscustomobject]@{Path=$p1;LogicalAddedBytes=[int64]9999},
            [pscustomobject]@{Path=$p2;LogicalAddedBytes=[int64]9999}
        )}}
        $moves = @(
            [pscustomobject]@{SourceEntryId='A';ArchivePst=$p1;Size=[int64]100},
            [pscustomobject]@{SourceEntryId='B';ArchivePst=$p1;Size=[int64]300},
            [pscustomobject]@{SourceEntryId='C';ArchivePst=$p2;Size=[int64]200}
        )
        Set-OPAArchiveLogicalTelemetryFromMoves -Transaction $tx -CompletedMoves $moves
        $tx.State.ArchivePsts[0].LogicalAddedBytes | Should -Be 400
        $tx.State.ArchivePsts[1].LogicalAddedBytes | Should -Be 200
    }
}
