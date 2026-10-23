#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerReadOnlyRecovery.ps1')
}
Describe '2.6.4-D independent read-only recovery (synthetic only, no Outlook)' {
    BeforeEach {
        $runId=[guid]::NewGuid().ToString('D')
        $opId=[guid]::NewGuid().ToString('D')
        $paths=Get-OPA264TestPaths -RunId $runId
        [void][IO.Directory]::CreateDirectory($paths.Directory)
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
            SourceFolderPath='\\Source\\Synthetic'; ArchiveFolderPath='\\Destination\\Synthetic'
            SourceEntryId='synthetic-entry'
        }
        [IO.File]::WriteAllText($paths.RequestPath,(ConvertTo-Json -InputObject $request))
        [void](Write-OPAOperationJournalEvent -Path $paths.JournalPath -TransactionId $runId -OperationId $opId -Sequence 1 -Phase Intent -OperationKind MailMove -SourceEntryId 'synthetic-entry' -SourceStoreId 'src-store' -SourceFolderPath '\\Source\\Synthetic' -TargetFolderPath '\\Destination\\Synthetic' -ArchivePst $paths.ArchivePst -InternetMessageId '<synthetic@example.invalid>' -Subject 'fixture' -Sender 'sender@example.invalid' -Size 123)
        $source=[pscustomobject]@{
            Role='Source'; StoreIdentity='src-store'
            FolderPath='\\Source\\Synthetic'; ArchivePst=''
            ScanComplete=$true; Items=@(); Errors=@()
        }
        $destination=[pscustomobject]@{
            Role='Destination'; StoreIdentity='dst-store'
            FolderPath='\\Destination\\Synthetic'; ArchivePst=$paths.ArchivePst
            ScanComplete=$true; Items=@(); Errors=@()
        }
        $row=[pscustomobject]@{
            EntryId='distinct-test'; InternetMessageId='<synthetic@example.invalid>'
            Subject='fixture'; Sender='sender@example.invalid'; Size=[long]123
        }
    }
    AfterEach {
        if ([IO.Directory]::Exists($paths.Directory)) {
            Remove-Item -LiteralPath $paths.Directory -Recurse -Force
        }
    }
    It 'accepts intact evidence without requiring an empty one-shot claim' {
        [IO.File]::WriteAllText($paths.ClaimPath,($opId+[char]10))
        (Assert-OPA264RecoveryFixture -Request $request -RunId $runId).RunId | Should -Be $runId
    }
    It 'refuses a mismatched requested RunId' {
        { Assert-OPA264RecoveryFixture -Request $request -RunId ([guid]::NewGuid().ToString('D')) } | Should -Throw '*RunId*'
    }
    It 'refuses an unrelated source PST' {
        $request.SourcePst='C:\Mail\Production.pst'
        { Assert-OPA264RecoveryFixture -Request $request -RunId $runId } | Should -Throw '*path escapes*'
    }
    It 'refuses a forged marker' {
        $marker=Get-Content -LiteralPath $paths.MarkerPath -Raw | ConvertFrom-Json
        $marker.RunId=[guid]::NewGuid().ToString('D')
        [IO.File]::WriteAllText($paths.MarkerPath,(ConvertTo-Json -InputObject $marker))
        { Assert-OPA264RecoveryFixture -Request $request -RunId $runId } | Should -Throw '*marker mismatch*'
    }
    It 'refuses a missing archive PST' {
        Remove-Item -LiteralPath $paths.ArchivePst
        { Assert-OPA264RecoveryFixture -Request $request -RunId $runId } | Should -Throw '*does not exist*'
    }
    It 'refuses corrupt persisted operation journal' {
        [IO.File]::AppendAllText($paths.JournalPath,'{"V":1')
        { Assert-OPA264RecoveryFixture -Request $request -RunId $runId } | Should -Throw '*complete durable Intent*'
    }
    It 'refuses an unrelated one-shot worker claim' {
        [IO.File]::WriteAllText($paths.ClaimPath,([guid]::NewGuid().ToString('D')+[char]10))
        { Get-OPA264RecoveryArtifactEvidence -Request $request -Paths $paths } | Should -Throw '*OperationId mismatch*'
    }
    It 'recognizes an intact controller and worker claim without dispatch' {
        [IO.File]::WriteAllText((Join-Path $paths.Directory 'controller-dispatch.claim'),($opId+[char]10))
        [IO.File]::WriteAllText($paths.ClaimPath,($opId+[char]10))
        $e=Get-OPA264RecoveryArtifactEvidence -Request $request -Paths $paths
        $e.ControllerDispatchClaimPresent | Should -BeTrue
        $e.WorkerMoveClaimPresent | Should -BeTrue
    }
    It 'records a missing crash barrier without assuming no Move occurred' {
        (Get-OPA264RecoveryArtifactEvidence -Request $request -Paths $paths).CrashBarrier | Should -Be 'NotRecorded'
    }
    It 'rejects a crash barrier with wrong operation correlation' {
        $b=Write-OPA264CrashBarrier -Request $request -CrashWindow WorkerStartedBeforeMove -ProcessId ([int]$PID)
        $b.OperationId=[guid]::NewGuid().ToString('D')
        [IO.File]::WriteAllText((Get-OPA264CrashBarrierPath -RunId $runId),(ConvertTo-Json -InputObject $b))
        { Get-OPA264RecoveryArtifactEvidence -Request $request -Paths $paths } | Should -Throw '*mismatch*'
    }
    It 'accepts a previously flushed crash barrier as only a diagnostic hint' {
        [void](Write-OPA264CrashBarrier -Request $request -CrashWindow WorkerStartedBeforeMove -ProcessId ([int]$PID))
        (Get-OPA264RecoveryArtifactEvidence -Request $request -Paths $paths).CrashBarrier | Should -Be 'WorkerStartedBeforeMove'
    }
    It 'rejects an optimistic Worker response' {
        $r=[pscustomobject]@{
            RunId=$runId; OperationId=$opId; AutomaticRetryAllowed=$true
            JournalCompleted=$false; RequiresIndependentReconciliation=$true
        }
        [IO.File]::WriteAllText($paths.ResponsePath,(ConvertTo-Json -InputObject $r))
        { Get-OPA264RecoveryArtifactEvidence -Request $request -Paths $paths } | Should -Throw '*Worker response*'
    }
    It 'rejects a corrupted controller report' {
        [IO.File]::WriteAllText((Join-Path $paths.Directory 'controller-result.json'),'{bad')
        { Get-OPA264RecoveryArtifactEvidence -Request $request -Paths $paths } | Should -Throw
    }
    It 'returns MissingBoth without granting replay or journal writes' {
        $r=Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $source -DestinationSnapshot $destination
        $r.Status | Should -Be 'MissingBoth'
        $r.AutomaticRetryAllowed | Should -BeFalse
        $r.JournalWriteAllowed | Should -BeFalse
        $r.MailMoveAllowed | Should -BeFalse
    }
    It 'reports SourceOnly without treating it as safe to retry' {
        $source.Items=@($row)
        $r=Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $source -DestinationSnapshot $destination
        $r.Status | Should -Be 'SourceOnly'
        $r.ProvenMoved | Should -BeFalse
    }
    It 'reports DestinationCandidate but NEVER proven moved' {
        $destination.Items=@($row)
        $r=Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $source -DestinationSnapshot $destination
        $r.Status | Should -Be 'DestinationCandidate'
        $r.ProvenMoved | Should -BeFalse
        $r.RequiresManualReview | Should -BeTrue
    }
    It 'recognizes BothPresent as ambiguous outcome requiring review' {
        $source.Items=@($row); $destination.Items=@($row)
        (Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $source -DestinationSnapshot $destination).Status | Should -Be 'BothPresent'
    }
    It 'recognizes two destination matches as Ambiguous' {
        $destination.Items=@($row,$row)
        (Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $source -DestinationSnapshot $destination).Status | Should -Be 'Ambiguous'
    }
    It 'rejects foreign destination StoreID despite exact PST path' {
        $destination.StoreIdentity='foreign-store'
        { Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $source -DestinationSnapshot $destination } | Should -Throw '*snapshot*scope*'
    }
    It 'returns IncompleteScan without inferring lost messages' {
        $destination.ScanComplete=$false
        (Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $source -DestinationSnapshot $destination).Status | Should -Be 'IncompleteScan'
    }
    It 'leaves the journal byte-identical during independent analysis' {
        $before=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash
        [void](Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $source -DestinationSnapshot $destination)
        $after=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash
        $before | Should -Be $after
    }
    It 'has no Outlook launch, PST mounting or MailItem.Move in the recovery CLI' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264ReadOnlyRecovery.ps1'
        $tokens=$null;$parseErrors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $methods=@($ast.FindAll({
            param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object { [string]$_.Member.Value -in @('Move','Copy','Delete','Kill','AddStore','AddStoreEx','RemoveStore','Quit') }).Count | Should -Be 0
    }
}
