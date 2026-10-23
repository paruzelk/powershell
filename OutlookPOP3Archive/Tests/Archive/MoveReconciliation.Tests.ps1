#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Archive/MoveReconciliation.ps1')
    function Get-OPAInternetMessageId { param([object]$Item) [string]$Item.InternetMessageId }
    function Release-OPAComObject { param([object]$Object) }

    function New-OPA263Item {
        param(
            [string]$Id='A1', [string]$MessageId='<msg@example.test>',
            [string]$Subject='subject', [string]$Sender='sender@example.test',
            [long]$Size=256
        )
        [pscustomobject]@{
            EntryID=$Id; InternetMessageId=$MessageId
            Subject=$Subject; SenderEmailAddress=$Sender; Sender=$Sender
            Size=$Size; Class=43
        }
    }

    function New-OPA263Snapshot {
        param(
            [string]$Role='Source',
            [object[]]$Rows=@(),
            [bool]$Complete=$true,
            [string]$FolderPath='',
            [string]$Store='',
            [string]$Archive=''
        )
        if (-not $FolderPath) { $FolderPath = if ($Role -eq 'Source') { '\\POP3\\Inbox' } else { '\\Archive\\2020' } }
        if (-not $Store) { $Store = if ($Role -eq 'Source') { 'source-store' } else { 'archive-store' } }
        [pscustomobject]@{
            Role=$Role; FolderPath=$FolderPath; StoreIdentity=$Store
            ArchivePst=$Archive; ScanComplete=$Complete
            Items=$Rows; Errors=@()
        }
    }

    function New-OPA263FakeFolder {
        param([string]$Path,[string]$Store,[object[]]$Rows=@())
        $items = [pscustomobject]@{ Count=$Rows.Count; Rows=$Rows }
        $items | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param([int]$Index)
            return $this.Rows[$Index - 1]
        }
        [pscustomobject]@{ FolderPath=$Path; StoreID=$Store; Items=$items }
    }

    function Write-OPA263Intent {
        param([string]$Path,[string]$Archive,[switch]$Legacy)
        $params = @{
            Path=$Path; TransactionId='tx-263'; OperationId='move-1'
            Sequence=1; Phase='Intent'; OperationKind='MailMove'
            SourceEntryId='source-1'; ArchivePst=$Archive
        }
        if (-not $Legacy) {
            $params.SourceStoreId='source-store'
            $params.SourceFolderPath='\\POP3\\Inbox'
            $params.TargetFolderPath='\\Archive\\2020'
            $params.InternetMessageId='<msg@example.test>'
            $params.Subject='subject'
            $params.Sender='sender@example.test'
            $params.Size=[long]256
        }
        Write-OPAOperationJournalEvent @params | Out-Null
    }
}
Describe '2.6.3 independent read-only interrupted Move reconciliation' {
    BeforeEach {
        $script:path = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.operations.jsonl')
        $script:archive = Join-Path $TestDrive 'Archive-2020.pst'
        Write-OPA263Intent -Path $script:path -Archive $script:archive
        $script:source = New-OPA263Snapshot -Role Source
        $script:destination = New-OPA263Snapshot -Role Destination -Archive $script:archive
    }

    It 'reports a single destination fingerprint as candidate, NEVER a proved Move' {
        $script:destination.Items = @((New-OPA263Item -Id 'A1'))
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'DestinationCandidate'
        $r.DestinationEntryId | Should -Be 'A1'
        $r.ProvenMoved | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
        $r.RequiresManualReview | Should -BeTrue
    }

    It 'reports source-only without permitting a second Move' {
        $script:source.Items = @((New-OPA263Item -Id 'source-1'))
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'SourceOnly'
        $r.AutomaticRetryAllowed | Should -BeFalse
    }

    It 'reports both-present as a duplicate or copy risk' {
        $script:source.Items = @((New-OPA263Item -Id 'source-1'))
        $script:destination.Items = @((New-OPA263Item -Id 'A1'))
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'BothPresent'
        $r.AutomaticRetryAllowed | Should -BeFalse
    }

    It 'does not assume a missing pair proves a failed Move' {
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'MissingBoth'
        $r.AutomaticRetryAllowed | Should -BeFalse
    }

    It 'rejects multiple archive matches even when all fingerprints agree' {
        $script:destination.Items = @((New-OPA263Item -Id 'A1'),(New-OPA263Item -Id 'A2'))
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'Ambiguous'
    }

    It 'rejects multiple source matches' {
        $script:source.Items = @((New-OPA263Item -Id 'source-1'),(New-OPA263Item -Id 'S2'))
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'Ambiguous'
    }

    It 'rejects an EntryId that now belongs to a different message' {
        $script:source.Items = @((New-OPA263Item -Id 'source-1' -Subject 'different'))
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'IdentityConflict'
    }

    It 'rejects a source snapshot from another POP3 store' {
        $script:source.StoreIdentity = 'wrong-source-store'
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'ScopeMismatch'
    }

    It 'rejects an archive snapshot from another PST' {
        $script:destination.ArchivePst = (Join-Path $TestDrive 'other.pst')
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'ScopeMismatch'
    }

    It 'rejects a different destination folder' {
        $script:destination.FolderPath = '\\Archive\\Elsewhere'
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'ScopeMismatch'
    }

    It 'rejects an incomplete COM scan even if it found a destination match' {
        $script:destination.Items = @((New-OPA263Item -Id 'A1'))
        $script:source.ScanComplete = $false
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'IncompleteScan'
        $r.AutomaticRetryAllowed | Should -BeFalse
    }

    It 'does not interpret an old 2.6.2 Intent without identity fields as evidence' {
        $path2=Join-Path $TestDrive (([guid]::NewGuid().ToString('N'))+'.operations.jsonl')
        Write-OPA263Intent -Path $path2 -Archive $script:archive -Legacy
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $path2) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'InsufficientEvidence'
    }

    It 'rejects a confirmed terminal journal event for reconciliation' {
        Write-OPAOperationJournalEvent -Path $script:path -TransactionId 'tx-263' -OperationId 'move-1' -Sequence 2 -Phase Completed -ArchiveEntryId 'A1' | Out-Null
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'AlreadyTerminal'
    }

    It 'never uses a truncated tail for automatic confirmation' {
        [IO.File]::AppendAllText($script:path, '{"V":', (New-Object System.Text.UTF8Encoding($false)))
        $r=Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'UntrustedJournal'
        $r.ProvenMoved | Should -BeFalse
    }

    It 'throws when the requested operation is absent from the journal' {
        { Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'unknown' -SourceSnapshot $script:source -DestinationSnapshot $script:destination } | Should -Throw
    }

    It 'refuses to treat a WorkerDiagnostic as a MailMove intent' {
        $p=Join-Path $TestDrive (([guid]::NewGuid().ToString('N'))+'.operations.jsonl')
        Write-OPAOperationJournalEvent -Path $p -TransactionId 'tx-263' -OperationId 'ping-1' -Sequence 1 -Phase Intent -OperationKind WorkerDiagnostic | Out-Null
        { Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $p) -OperationId 'ping-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination } | Should -Throw
    }

    It 'fully enumerates a mock source folder without Outlook COM' {
        $folder=New-OPA263FakeFolder -Path '\\POP3\\Inbox' -Store 'source-store' -Rows @((New-OPA263Item -Id 'source-1'))
        $snap=New-OPAReadOnlyMoveSnapshot -Folder $folder -FolderPath '\\POP3\\Inbox' -StoreIdentity 'source-store'
        $snap.ScanComplete | Should -BeTrue
        @($snap.Items).Count | Should -Be 1
        $snap.Items[0].EntryId | Should -Be 'source-1'
    }

    It 'marks source enumeration incomplete on wrong folder identity' {
        $folder=New-OPA263FakeFolder -Path '\\IMAP\\Inbox' -Store 'imap-store'
        $snap=New-OPAReadOnlyMoveSnapshot -Folder $folder -FolderPath '\\POP3\\Inbox' -StoreIdentity 'source-store'
        $snap.ScanComplete | Should -BeFalse
    }

    It 'marks source enumeration incomplete when Outlook item access fails' {
        $folder=New-OPA263FakeFolder -Path '\\POP3\\Inbox' -Store 'source-store'
        $folder.Items.Count=1
        $snap=New-OPAReadOnlyMoveSnapshot -Folder $folder -FolderPath '\\POP3\\Inbox' -StoreIdentity 'source-store'
        $snap.ScanComplete | Should -BeFalse
        @($snap.Errors).Count | Should -BeGreaterThan 0
    }

    It 'uses a read-only wrapped scan and leaves the journal unchanged' {
        $src=New-OPA263FakeFolder -Path '\\POP3\\Inbox' -Store 'source-store'
        $dst=New-OPA263FakeFolder -Path '\\Archive\\2020' -Store 'archive-store' -Rows @((New-OPA263Item -Id 'A1'))
        $before=(Get-Item -LiteralPath $script:path).Length
        $r=Invoke-OPAReadOnlyInterruptedMoveReview -JournalPath $script:path -OperationId 'move-1' -SourceFolder $src -DestinationFolder $dst -SourceStoreId 'source-store' -SourceFolderPath '\\POP3\\Inbox' -DestinationStoreId 'archive-store' -TargetFolderPath '\\Archive\\2020' -ArchivePst $script:archive
        $r.Status | Should -Be 'DestinationCandidate'
        (Get-Item -LiteralPath $script:path).Length | Should -Be $before
        @((Read-OPAOperationJournal -Path $script:path).Events).Count | Should -Be 1
    }

    It 'does not mark a MailItem with absent MessageId as completely scanned' {
        $item = New-OPA263Item -Id 'source-1' -MessageId ''
        $folder = New-OPA263FakeFolder -Path '\\POP3\\Inbox' -Store 'source-store' -Rows @($item)
        $snap = New-OPAReadOnlyMoveSnapshot -Folder $folder -FolderPath '\\POP3\\Inbox' -StoreIdentity 'source-store'
        $snap.ScanComplete | Should -BeFalse
        @($snap.Errors).Count | Should -BeGreaterThan 0
    }

    It 'fails closed if the caller supplies no destination inventory' {
        $script:destination.Items = $null
        $r = Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'IncompleteScan'
        $r.AutomaticRetryAllowed | Should -BeFalse
    }

    It 'does not confuse equal message IDs with different senders' {
        $script:destination.Items = @((New-OPA263Item -Id 'A1' -Sender 'another@example.test'))
        $r = Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'MissingBoth'
        $r.DestinationMatches | Should -Be 0
    }

    It 'does not confuse equal message IDs with different sizes' {
        $script:destination.Items = @((New-OPA263Item -Id 'A1' -Size 257))
        $r = Resolve-OPAInterruptedMoveEvidence -Journal (Read-OPAOperationJournal -Path $script:path) -OperationId 'move-1' -SourceSnapshot $script:source -DestinationSnapshot $script:destination
        $r.Status | Should -Be 'MissingBoth'
    }
}
