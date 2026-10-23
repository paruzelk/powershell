#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerTestMove.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
}
Describe '2.6.4-B disposable test MailMove isolation (no Outlook COM)' {
    BeforeEach {
        $runId = [guid]::NewGuid().ToString('D')
        $operationId = [guid]::NewGuid().ToString('D')
        $paths = Get-OPA264TestPaths -RunId $runId
        New-Item -ItemType Directory -Path $paths.Directory -ErrorAction Stop | Out-Null
        [IO.File]::WriteAllBytes($paths.SourcePst,([byte[]]@(1,2,3)))
        [IO.File]::WriteAllBytes($paths.ArchivePst,([byte[]]@(4,5,6)))
        $marker = [pscustomobject]@{
            Purpose = 'OPA264-Disposable-Pst-Pair'
            RunId = $paths.RunId
            SourcePst = $paths.SourcePst
            ArchivePst = $paths.ArchivePst
        }
        [IO.File]::WriteAllText($paths.MarkerPath,(ConvertTo-Json -InputObject $marker))
        $request = [pscustomobject]@{
            RunId=$paths.RunId; OperationId=$operationId
            SourcePst=$paths.SourcePst; ArchivePst=$paths.ArchivePst
            JournalPath=$paths.JournalPath
            SourceStoreId='test-source-store'; ArchiveStoreId='test-archive-store'
            SourceFolderEntryId='test-source-folder'; ArchiveFolderEntryId='test-archive-folder'
            SourceFolderPath='\\DisposableSource\Test'; ArchiveFolderPath='\\DisposableArchive\Test'
            SourceEntryId='test-entry'
        }
        [void](Write-OPAOperationJournalEvent -Path $paths.JournalPath -TransactionId $paths.RunId -OperationId $operationId -Sequence 1 -Phase Intent -OperationKind MailMove -SourceEntryId 'test-entry' -SourceStoreId 'test-source-store' -SourceFolderPath '\\DisposableSource\Test' -TargetFolderPath '\\DisposableArchive\Test' -ArchivePst $paths.ArchivePst -InternetMessageId 'test-message@invalid' -Subject 'fixture' -Sender 'sender@invalid' -Size 123)
    }
    AfterEach {
        # Only the unique disposable synthetic directory created by this test.
        if ([IO.Directory]::Exists($paths.Directory)) {
            Remove-Item -LiteralPath $paths.Directory -Recurse -Force
        }
    }
    It 'derives a fixed run-unique path below OS TEMP' {
        $paths.Directory | Should -Match ('OPA264-Test-' + ($runId -replace '-','') + '$')
    }
    It 'rejects zero RunId' {
        { Get-OPA264TestPaths -RunId ([guid]::Empty.ToString('D')) } | Should -Throw '*GUID*'
    }
    It 'accepts a matching marker and two distinct disposable PST paths' {
        $result = Assert-OPA264TestMoveScope -Request $request
        $result.RunId | Should -Be $paths.RunId
    }
    It 'refuses a real or arbitrary source PST path' {
        $request.SourcePst = 'C:\Mail\Production.pst'
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*scope*'
    }
    It 'refuses a different archive PST path' {
        $request.ArchivePst = (Join-Path $paths.Directory 'other.pst')
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*scope*'
    }
    It 'refuses a traversal or noncanonical source path' {
        $request.SourcePst = (Join-Path $paths.Directory '..\Source.pst')
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*scope*'
    }
    It 'refuses absent scope marker' {
        Remove-Item -LiteralPath $paths.MarkerPath
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*marker*'
    }
    It 'refuses marker with mismatched RunId' {
        $marker = Get-Content -LiteralPath $paths.MarkerPath -Raw | ConvertFrom-Json
        $marker.RunId = [guid]::NewGuid().ToString('D')
        [IO.File]::WriteAllText($paths.MarkerPath,(ConvertTo-Json -InputObject $marker))
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*marker*'
    }
    It 'refuses equal source and destination StoreIDs' {
        $request.ArchiveStoreId = $request.SourceStoreId
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*StoreID*'
    }
    It 'refuses missing source identity field' {
        $request.SourceEntryId = ''
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*SourceEntryId*'
    }
    It 'reads exactly one valid durable MailMove Intent' {
        $intent = Assert-OPA264TestMoveIntent -Request $request -Paths $paths
        $intent.OperationId | Should -Be $operationId
    }
    It 'refuses an operation ID that disagrees with the journal' {
        $request.OperationId = [guid]::NewGuid().ToString('D')
        { Assert-OPA264TestMoveIntent -Request $request -Paths $paths } | Should -Throw '*conflicts*'
    }
    It 'refuses a truncated durable journal' {
        [IO.File]::AppendAllText($paths.JournalPath,'{"V":1')
        { Assert-OPA264TestMoveIntent -Request $request -Paths $paths } | Should -Throw '*one complete*'
    }
    It 'refuses a journal with an extra terminal event' {
        [void](Write-OPAOperationJournalEvent -Path $paths.JournalPath -TransactionId $paths.RunId -OperationId $operationId -Sequence 2 -Phase Indeterminate -OperationKind MailMove)
        { Assert-OPA264TestMoveIntent -Request $request -Paths $paths } | Should -Throw '*one complete*'
    }
    It 'refuses a pre-existing one-shot claim or response' {
        [IO.File]::WriteAllText($paths.ClaimPath,'already attempted')
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*never replay*'
        Remove-Item -LiteralPath $paths.ClaimPath
        [IO.File]::WriteAllText($paths.ResponsePath,'already returned')
        { Assert-OPA264TestMoveScope -Request $request } | Should -Throw '*never replay*'
    }
    It 'keeps mutation isolated from the production Worker allowlist' {
        $protocol = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/WorkerProtocol.ps1') -Raw
        $protocol | Should -Not -Match "'MailMove'"
        $entry = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264TestWorker.ps1') -Raw
        $entry | Should -Match 'explicit -Execute'
        $release = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../RELEASE.json') -Raw | ConvertFrom-Json
        $release.Integration.ArchiveWorkerEnabled | Should -BeFalse
        $release.Integration.ResumeWorkerEnabled | Should -BeFalse
        $release.Integration.AutoWorkerEnabled | Should -BeFalse
    }
}
