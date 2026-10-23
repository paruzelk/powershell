#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerIdentityStability.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
}
Describe '2.6.4-E disposable identity stability (synthetic files only, no Outlook)' {
    BeforeEach {
        $runId=[guid]::NewGuid().ToString('D')
        $opId=[guid]::NewGuid().ToString('D')
        $paths=Get-OPA264TestPaths -RunId $runId
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        [IO.File]::WriteAllBytes($paths.SourcePst,([byte[]]@(1,2,3)))
        [IO.File]::WriteAllBytes($paths.ArchivePst,([byte[]]@(4,5,6)))
        $marker=[pscustomobject]@{Purpose='OPA264-Disposable-Pst-Pair';RunId=$paths.RunId;SourcePst=$paths.SourcePst;ArchivePst=$paths.ArchivePst}
        [IO.File]::WriteAllText($paths.MarkerPath,(ConvertTo-Json -InputObject $marker))
        $request=[pscustomobject]@{
            RunId=$paths.RunId;OperationId=$opId;SourcePst=$paths.SourcePst;ArchivePst=$paths.ArchivePst
            JournalPath=$paths.JournalPath;SourceStoreId='source-store';ArchiveStoreId='archive-store'
            SourceFolderEntryId='source-folder';ArchiveFolderEntryId='archive-folder'
            SourceFolderPath='\\Source\\OPA264-TestSource';ArchiveFolderPath='\\Archive\\OPA264-TestArchive'
            SourceEntryId='fixture-mail-entry'
        }
        [IO.File]::WriteAllText($paths.RequestPath,(ConvertTo-Json -InputObject $request))
        [void](Write-OPAOperationJournalEvent -Path $paths.JournalPath -TransactionId $runId -OperationId $opId -Sequence 1 -Phase Intent -OperationKind MailMove -SourceEntryId 'fixture-mail-entry' -SourceStoreId 'source-store' -SourceFolderPath '\\Source\\OPA264-TestSource' -TargetFolderPath '\\Archive\\OPA264-TestArchive' -ArchivePst $paths.ArchivePst -InternetMessageId '<fixture@example.invalid>' -Subject 'synthetic' -Sender 'sender@example.invalid' -Size 100)
        $before=[pscustomobject]@{
            RunId=$runId;SourcePst=$paths.SourcePst;ArchivePst=$paths.ArchivePst
            SourceStoreId='source-store';ArchiveStoreId='archive-store'
            SourceFolderId='source-folder';ArchiveFolderId='archive-folder'
            SourceFolderPath='\\Source\\OPA264-TestSource';ArchiveFolderPath='\\Archive\\OPA264-TestArchive'
            MessageStoreRole='Source';MailEntryId='fixture-mail-entry'
            SourceMatches=1;ArchiveMatches=0;FullyScanned=$true
        }
        $after=$before | Select-Object *
    }
    AfterEach {
        if ([IO.Directory]::Exists($paths.Directory)) {
            Remove-Item -LiteralPath $paths.Directory -Recurse -Force
        }
    }
    It 'derives unique run-scoped identity probe evidence files' {
        $p=Get-OPA264IdentityProbePaths -RunId $runId
        $p.Claim | Should -Be (Join-Path $paths.Directory 'identity-probe.claim')
    }
    It 'refuses an invalid run GUID for probe path' {
        { Get-OPA264IdentityProbePaths -RunId 'invalid' } | Should -Throw '*GUID*'
    }
    It 'accepts only a pristine, undispatched, run-scoped fixture' {
        (Assert-OPA264IdentityProbeScope -Request $request).RunId | Should -Be $runId
    }
    It 'refuses an existing probe claim (never repeats detach)' {
        [IO.File]::WriteAllText((Get-OPA264IdentityProbePaths -RunId $runId).Claim,$opId)
        { Assert-OPA264IdentityProbeScope -Request $request } | Should -Throw '*unused prepared*'
    }
    It 'refuses an existing probe report' {
        [IO.File]::WriteAllText((Get-OPA264IdentityProbePaths -RunId $runId).Report,'{}')
        { Assert-OPA264IdentityProbeScope -Request $request } | Should -Throw '*unused prepared*'
    }
    It 'refuses an already-dispatched test Worker' {
        [IO.File]::WriteAllText((Join-Path $paths.Directory 'controller-dispatch.claim'),$opId)
        { Assert-OPA264IdentityProbeScope -Request $request } | Should -Throw '*unused prepared*'
    }
    It 'refuses an existing Move claim' {
        [IO.File]::WriteAllText($paths.ClaimPath,$opId)
        { Assert-OPA264IdentityProbeScope -Request $request } | Should -Throw '*unused prepared*'
    }
    It 'refuses pre-existing crash evidence' {
        [IO.File]::WriteAllText((Join-Path $paths.Directory 'crash-barrier.json'),'{}')
        { Assert-OPA264IdentityProbeScope -Request $request } | Should -Throw '*unused prepared*'
    }
    It 'refuses an unrelated PST path in the request' {
        $request.ArchivePst='C:\Mail\Production.pst'
        { Assert-OPA264IdentityProbeScope -Request $request } | Should -Throw '*path escapes*'
    }
    It 'rejects damaged marker before opening Outlook' {
        [IO.File]::WriteAllText($paths.MarkerPath,'{no')
        { Assert-OPA264IdentityProbeScope -Request $request } | Should -Throw
    }
    It 'reports Stable only if store folder and mail identity are unchanged' {
        $r=Compare-OPA264IdentityObservations -Before $before -After $after
        $r.Status | Should -Be 'Stable'
        $r.StoreIdChanged | Should -BeFalse
        $r.FolderIdentityChanged | Should -BeFalse
        $r.MailEntryIdChanged | Should -BeFalse
    }
    It 'detects a reattached source StoreID change' {
        $after.SourceStoreId='changed-store'
        $r=Compare-OPA264IdentityObservations -Before $before -After $after
        $r.Status | Should -Be 'StoreIdChanged'
        $r.StoreIdChanged | Should -BeTrue
    }
    It 'detects a reattached archive StoreID change' {
        $after.ArchiveStoreId='changed-archive-store'
        (Compare-OPA264IdentityObservations -Before $before -After $after).StoreIdChanged | Should -BeTrue
    }
    It 'detects a source folder EntryID change' {
        $after.SourceFolderId='new-folder'
        (Compare-OPA264IdentityObservations -Before $before -After $after).Status | Should -Be 'FolderIdentityChanged'
    }
    It 'detects a changed folder path after reattach' {
        $after.ArchiveFolderPath='\\Different\\OPA264-TestArchive'
        (Compare-OPA264IdentityObservations -Before $before -After $after).FolderIdentityChanged | Should -BeTrue
    }
    It 'detects a changed MailItem EntryID after reattach' {
        $after.MailEntryId='new-mail-id'
        (Compare-OPA264IdentityObservations -Before $before -After $after).Status | Should -Be 'MailEntryIdChanged'
    }
    It 'rejects a source/archive location flip as a stability success' {
        $after.MessageStoreRole='Archive'
        (Compare-OPA264IdentityObservations -Before $before -After $after).Status | Should -Be 'LocationChanged'
    }
    It 'does not hide multiple simultaneous identity changes' {
        $after.SourceStoreId='changed'
        $after.SourceFolderId='changed'
        $after.MailEntryId='changed'
        $r=Compare-OPA264IdentityObservations -Before $before -After $after
        $r.StoreIdChanged | Should -BeTrue
        $r.FolderIdentityChanged | Should -BeTrue
        $r.MailEntryIdChanged | Should -BeTrue
    }
    It 'never permits retry, Move or automatic journal completion' {
        $r=Compare-OPA264IdentityObservations -Before $before -After $after
        $r.AutomaticRetryAllowed | Should -BeFalse
        $r.MailMoveAllowed | Should -BeFalse
        $r.JournalWriteAllowed | Should -BeFalse
        $r.AutomaticCompletionAllowed | Should -BeFalse
        $r.ProvenMoved | Should -BeFalse
    }
    It 'requires manual review even when all identities remained stable' {
        (Compare-OPA264IdentityObservations -Before $before -After $after).RequiresManualReview | Should -BeTrue
    }
    It 'fails closed when the second observation is incomplete' {
        $after.FullyScanned=$false
        { Compare-OPA264IdentityObservations -Before $before -After $after } | Should -Throw '*incomplete*'
    }
    It 'refuses comparing different RunIDs' {
        $after.RunId=[guid]::NewGuid().ToString('D')
        { Compare-OPA264IdentityObservations -Before $before -After $after } | Should -Throw '*scope*'
    }
    It 'refuses comparing a substituted archive PST' {
        $after.ArchivePst='C:\Mail\Production.pst'
        { Compare-OPA264IdentityObservations -Before $before -After $after } | Should -Throw '*scope*'
    }
    It 'refuses an identity observation missing required fields' {
        $after.MailEntryId=''
        { Compare-OPA264IdentityObservations -Before $before -After $after } | Should -Throw '*missing*'
    }
    It 'never mutates the operation journal during pure observation comparison' {
        $hash=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash
        [void](Compare-OPA264IdentityObservations -Before $before -After $after)
        (Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash | Should -Be $hash
    }
    It 'requires three explicit opt-in switches in disposable-only CLI' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264IdentityReopenTest.ps1'
        $scriptText=Get-Content -LiteralPath $file -Raw
        $scriptText | Should -Match '\$Execute -and \$AllowDisposablePstDetach -and \$IsolatedTestProfileConfirmed'
    }
    It 'has no MailMove, Outlook Quit or process Kill call in detach/reopen CLI' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264IdentityReopenTest.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({
            param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object { [string]$_.Member.Value -in @('Move','Copy','Delete','Kill','Quit') }).Count | Should -Be 0
    }
    It 'uses only Unicode PST reopening and not ANSI' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264IdentityReopenTest.ps1'
        $scriptText=Get-Content -LiteralPath $file -Raw
        $scriptText | Should -Match '\$ns\.AddStoreEx\(\$paths\.SourcePst,2\)'
        $scriptText | Should -Match '\$ns\.AddStoreEx\(\$paths\.ArchivePst,2\)'
        $scriptText | Should -Not -Match '\$ns\.AddStoreEx\(\$paths\.(SourcePst|ArchivePst),3\)'
    }
}
