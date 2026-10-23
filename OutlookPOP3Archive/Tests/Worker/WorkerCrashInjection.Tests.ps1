#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerCrashInjection.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
}
Describe '2.6.4-C crash barriers on synthetic files (NO Outlook COM)' {
    BeforeEach {
        $runId=[guid]::NewGuid().ToString('D')
        $opId=[guid]::NewGuid().ToString('D')
        $paths=Get-OPA264TestPaths -RunId $runId
        New-Item -ItemType Directory -Path $paths.Directory -ErrorAction Stop | Out-Null
        [IO.File]::WriteAllBytes($paths.SourcePst,([byte[]]@(1,2,3)))
        [IO.File]::WriteAllBytes($paths.ArchivePst,([byte[]]@(4,5,6)))
        $marker=[pscustomobject]@{
            Purpose='OPA264-Disposable-Pst-Pair'; RunId=$paths.RunId
            SourcePst=$paths.SourcePst; ArchivePst=$paths.ArchivePst
        }
        [IO.File]::WriteAllText($paths.MarkerPath,(ConvertTo-Json -InputObject $marker))
        $request=[pscustomobject]@{
            RunId=$paths.RunId; OperationId=$opId
            SourcePst=$paths.SourcePst; ArchivePst=$paths.ArchivePst
            JournalPath=$paths.JournalPath
            SourceStoreId='src-store'; ArchiveStoreId='dst-store'
            SourceFolderEntryId='src-folder'; ArchiveFolderEntryId='dst-folder'
            SourceFolderPath='\\Src\Test'; ArchiveFolderPath='\\Dst\Test'
            SourceEntryId='synthetic-entry'
        }
        [void](Write-OPAOperationJournalEvent -Path $paths.JournalPath -TransactionId $paths.RunId -OperationId $opId -Sequence 1 -Phase Intent -OperationKind MailMove -SourceEntryId 'synthetic-entry' -SourceStoreId 'src-store' -SourceFolderPath '\\Src\Test' -TargetFolderPath '\\Dst\Test' -ArchivePst $paths.ArchivePst -InternetMessageId 'synthetic@invalid' -Subject 'fixture' -Sender 'test@invalid' -Size 123)
    }
    AfterEach {
        if ([IO.Directory]::Exists($paths.Directory)) {
            Remove-Item -LiteralPath $paths.Directory -Force -Recurse
        }
    }
    It 'declares None as nonterminating' {
        (Get-OPA264CrashMode -Name None).RequiresOwnedChildKill | Should -BeFalse
    }
    It 'supports exactly the four named injection modes plus None' {
        foreach ($name in @('None','AfterIntentBeforeDispatch','WorkerStartedBeforeMove','AfterMoveBeforeResponse','AfterResponseBeforeTerminal')) {
            (Get-OPA264CrashMode -Name $name).Name | Should -Be $name
        }
    }
    It 'rejects arbitrary and DuringMove injection' {
        { Get-OPA264CrashMode -Name 'DuringMove' } | Should -Throw '*Unsupported*'
    }
    It 'attributes pre-dispatch to Controller' {
        (Get-OPA264CrashMode -Name AfterIntentBeforeDispatch).Owner | Should -Be 'Controller'
    }
    It 'attributes pre-Move to Worker' {
        (Get-OPA264CrashMode -Name WorkerStartedBeforeMove).Owner | Should -Be 'Worker'
    }
    It 'requires parent ownership for both worker-side crashes' {
        (Get-OPA264CrashMode -Name WorkerStartedBeforeMove).RequiresOwnedChildKill | Should -BeTrue
        (Get-OPA264CrashMode -Name AfterMoveBeforeResponse).RequiresOwnedChildKill | Should -BeTrue
    }
    It 'never enables automatic retry in any injection mode' {
        foreach ($name in @('None','AfterIntentBeforeDispatch','WorkerStartedBeforeMove','AfterMoveBeforeResponse','AfterResponseBeforeTerminal')) {
            (Get-OPA264CrashMode -Name $name).AutoRetryAllowed | Should -BeFalse
        }
    }
    It 'never enables journal completion in any injection mode' {
        foreach ($name in @('None','AfterIntentBeforeDispatch','WorkerStartedBeforeMove','AfterMoveBeforeResponse','AfterResponseBeforeTerminal')) {
            (Get-OPA264CrashMode -Name $name).JournalCompletionAllowed | Should -BeFalse
        }
    }
    It 'marks post-Move evidence as possibly moved, not guaranteed' {
        (Get-OPA264CrashMode -Name AfterMoveBeforeResponse).MayHaveMoved | Should -BeTrue
        (Get-OPA264CrashMode -Name WorkerStartedBeforeMove).MayHaveMoved | Should -BeFalse
    }
    It 'derives one barrier path strictly from RunId' {
        (Get-OPA264CrashBarrierPath -RunId $paths.RunId) | Should -Be (Join-Path $paths.Directory 'crash-barrier.json')
    }
    It 'rejects a zero GUID in barrier path derivation' {
        { Get-OPA264CrashBarrierPath -RunId ([guid]::Empty.ToString('D')) } | Should -Throw '*GUID*'
    }
    It 'writes and validates a flushed pre-dispatch barrier' {
        $record=Write-OPA264CrashBarrier -Request $request -CrashWindow AfterIntentBeforeDispatch -ProcessId ([int]$PID)
        (Assert-OPA264CrashBarrier -Record $record -Request $request -ExpectedWindow AfterIntentBeforeDispatch -ExpectedProcessId ([int]$PID)) | Should -BeTrue
    }
    It 'rejects a second barrier in the same run' {
        [void](Write-OPA264CrashBarrier -Request $request -CrashWindow AfterIntentBeforeDispatch -ProcessId ([int]$PID))
        { Write-OPA264CrashBarrier -Request $request -CrashWindow AfterIntentBeforeDispatch -ProcessId ([int]$PID) } | Should -Throw
    }
    It 'rejects barrier PID forgery' {
        { Write-OPA264CrashBarrier -Request $request -CrashWindow WorkerStartedBeforeMove -ProcessId ([int]($PID + 500)) } | Should -Throw '*PID*'
    }
    It 'rejects a different process ID during parent verification' {
        $record=Write-OPA264CrashBarrier -Request $request -CrashWindow WorkerStartedBeforeMove -ProcessId ([int]$PID)
        { Assert-OPA264CrashBarrier -Record $record -Request $request -ExpectedWindow WorkerStartedBeforeMove -ExpectedProcessId ([int]($PID + 1)) } | Should -Throw '*mismatch*'
    }
    It 'rejects an operation-ID mismatch in the barrier' {
        $record=Write-OPA264CrashBarrier -Request $request -CrashWindow WorkerStartedBeforeMove -ProcessId ([int]$PID)
        $record.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA264CrashBarrier -Record $record -Request $request -ExpectedWindow WorkerStartedBeforeMove -ExpectedProcessId ([int]$PID) } | Should -Throw '*mismatch*'
    }
    It 'rejects optimistic retry flags in a barrier' {
        $record=Write-OPA264CrashBarrier -Request $request -CrashWindow WorkerStartedBeforeMove -ProcessId ([int]$PID)
        $record.AutomaticRetryAllowed=$true
        { Assert-OPA264CrashBarrier -Record $record -Request $request -ExpectedWindow WorkerStartedBeforeMove -ExpectedProcessId ([int]$PID) } | Should -Throw '*mismatch*'
    }
    It 'allows a pre-Move Worker barrier before the worker Move claim' {
        $record=Write-OPA264CrashBarrier -Request $request -CrashWindow WorkerStartedBeforeMove -ProcessId ([int]$PID)
        $record.CrashWindow | Should -Be 'WorkerStartedBeforeMove'
    }
    It 'blocks a post-Move barrier when no one-shot Move claim exists' {
        { Write-OPA264CrashBarrier -Request $request -CrashWindow AfterMoveBeforeResponse -ProcessId ([int]$PID) } | Should -Throw '*does not exist*'
    }
    It 'accepts a post-Move barrier after a matching one-shot Move claim' {
        [IO.File]::WriteAllText($paths.ClaimPath,($opId + [char]10))
        $record=Write-OPA264CrashBarrier -Request $request -CrashWindow AfterMoveBeforeResponse -ProcessId ([int]$PID)
        $record.CrashWindow | Should -Be 'AfterMoveBeforeResponse'
    }
    It 'rejects post-Move claim with an unrelated operation ID' {
        [IO.File]::WriteAllText($paths.ClaimPath,([guid]::NewGuid().ToString('D') + [char]10))
        { Write-OPA264CrashBarrier -Request $request -CrashWindow AfterMoveBeforeResponse -ProcessId ([int]$PID) } | Should -Throw '*one-shot claim*'
    }
    It 'accepts post-response barrier only with prior Move claim' {
        [IO.File]::WriteAllText($paths.ClaimPath,($opId + [char]10))
        $record=Write-OPA264CrashBarrier -Request $request -CrashWindow AfterResponseBeforeTerminal -ProcessId ([int]$PID)
        $record.Owner | Should -Be 'Controller'
    }
    It 'rejects a modified durable Intent before barrier writing' {
        [IO.File]::AppendAllText($paths.JournalPath,'{"V":1')
        { Write-OPA264CrashBarrier -Request $request -CrashWindow WorkerStartedBeforeMove -ProcessId ([int]$PID) } | Should -Throw '*complete durable Intent*'
    }
    It 'keeps real Outlook and production Worker outside crash helper' {
        $helper=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/WorkerCrashInjection.ps1') -Raw
        $helper | Should -Not -Match 'Outlook.Application'
        $protocol=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/WorkerProtocol.ps1') -Raw
        $protocol | Should -Not -Match "'MailMove'"
    }
}
