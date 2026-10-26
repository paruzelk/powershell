#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live3SyntheticScope.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live4CrashProtocol.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
}
Describe '2.6.4-LIVE4 controlled Worker crash barriers (offline, no Outlook)' {
    BeforeEach {
        $src=Join-Path $TestDrive ('test-pop3-'+[guid]::NewGuid().ToString('N')+'.pst')
        [IO.File]::WriteAllBytes($src,(New-Object byte[] 4096))
        $run=[guid]::NewGuid().ToString('D')
        $op=[guid]::NewGuid().ToString('D')
        $paths=Get-OPA264Live3Paths -RunId $run -SourcePst $src
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        [IO.File]::WriteAllBytes($paths.ArchivePst,(New-Object byte[] 4096))
        $marker=[pscustomobject]@{
            Purpose='OPA264-LIVE3-OneSyntheticMail'
            RunId=$paths.RunId;SourcePst=$paths.SourcePst;ArchivePst=$paths.ArchivePst
            SourceFolderName=$paths.SourceFolderName
            ArchiveFolderName=$paths.ArchiveFolderName
            AllowExistingMailMove=$false
        }
        [IO.File]::WriteAllText($paths.ScopePath,(ConvertTo-Json -InputObject $marker -Depth 5))
        $req=[pscustomobject]@{
            RunId=$paths.RunId;OperationId=$op
            SourcePst=$paths.SourcePst;ArchivePst=$paths.ArchivePst
            JournalPath=$paths.JournalPath
            SourceStoreId='POP3-Test-Store';ArchiveStoreId='Temporary-Archive-Store'
            SourceFolderEntryId='src-fixture-folder';ArchiveFolderEntryId='dst-fixture-folder'
            SourceFolderPath=('\\POP3\'+$paths.SourceFolderName)
            ArchiveFolderPath=('\\Archive\'+$paths.ArchiveFolderName)
            SourceEntryId='only-synthetic-entry'
        }
        $intentParams=@{
            Path=$paths.JournalPath;TransactionId=$paths.RunId
            OperationId=$op;Sequence=1;Phase='Intent';OperationKind='MailMove'
            SourceEntryId=$req.SourceEntryId;SourceStoreId=$req.SourceStoreId
            SourceFolderPath=$req.SourceFolderPath
            TargetFolderPath=$req.ArchiveFolderPath
            ArchivePst=$paths.ArchivePst
            InternetMessageId=('<opa264-live3-'+$paths.RunId+'@example.invalid>')
            Subject=('OPA264 LIVE3 synthetic '+$paths.RunId)
            Sender='';Size=0
        }
        [void](Write-OPAOperationJournalEvent @intentParams)
        $crashPaths=Get-OPA264Live4Paths -FixturePaths $paths
        $fakeBarrier=[pscustomobject]@{
            Schema='2.6.4-LIVE4.CrashBarrier.1'
            RunId=$paths.RunId;OperationId=$op
            CrashWindow='WorkerStartedBeforeMove'
            WorkerProcessId=[int]$PID
            AutomaticRetryAllowed=$false
            JournalCompleted=$false
            RequiresIndependentReconciliation=$true
        }
    }
    AfterEach {
        if($null -ne $paths -and [IO.Directory]::Exists($paths.Directory)){
            [IO.Directory]::Delete($paths.Directory,$true)
        }
    }
    It 'derives fixed dispatch claim and barrier within exact RunId directory' {
        $crashPaths.DispatchClaim | Should -Be (Join-Path $paths.Directory 'controller-dispatch.claim')
        $crashPaths.CrashBarrier | Should -Be (Join-Path $paths.Directory 'crash-barrier.json')
    }
    It 'derives fixed controller result without an arbitrary user path' {
        $crashPaths.ControllerResult | Should -Be (Join-Path $paths.Directory 'controller-result.json')
    }
    It 'recognizes WorkerStartedBeforeMove crash window' {
        (Assert-OPA264Live4Mode -Name 'WorkerStartedBeforeMove') | Should -Be 'WorkerStartedBeforeMove'
    }
    It 'recognizes AfterMoveBeforeResponse crash window' {
        (Assert-OPA264Live4Mode -Name 'AfterMoveBeforeResponse') | Should -Be 'AfterMoveBeforeResponse'
    }
    It 'rejects arbitrary crash windows' {
        {Assert-OPA264Live4Mode -Name 'DuringMove'} | Should -Throw '*two named*'
    }
    It 'rejects the old disposable-only controller crash window' {
        {Assert-OPA264Live4Mode -Name 'AfterIntentBeforeDispatch'} | Should -Throw '*two named*'
    }
    It 'accepts an exact crash barrier identity' {
        (Assert-OPA264Live4Barrier -Record $fakeBarrier -Request $req -Window 'WorkerStartedBeforeMove' -ExpectedWorkerPid ([int]$PID)) | Should -BeTrue
    }
    It 'rejects barrier from a different RunId' {
        $fakeBarrier.RunId=[guid]::NewGuid().ToString('D')
        {Assert-OPA264Live4Barrier -Record $fakeBarrier -Request $req -Window 'WorkerStartedBeforeMove' -ExpectedWorkerPid ([int]$PID)} | Should -Throw '*mismatch*'
    }
    It 'rejects barrier from a different OperationId' {
        $fakeBarrier.OperationId=[guid]::NewGuid().ToString('D')
        {Assert-OPA264Live4Barrier -Record $fakeBarrier -Request $req -Window 'WorkerStartedBeforeMove' -ExpectedWorkerPid ([int]$PID)} | Should -Throw '*mismatch*'
    }
    It 'rejects barrier from a different crash window' {
        $fakeBarrier.CrashWindow='AfterMoveBeforeResponse'
        {Assert-OPA264Live4Barrier -Record $fakeBarrier -Request $req -Window 'WorkerStartedBeforeMove' -ExpectedWorkerPid ([int]$PID)} | Should -Throw '*mismatch*'
    }
    It 'rejects barrier from a different worker PID' {
        $fakeBarrier.WorkerProcessId=[int]($PID+1)
        {Assert-OPA264Live4Barrier -Record $fakeBarrier -Request $req -Window 'WorkerStartedBeforeMove' -ExpectedWorkerPid ([int]$PID)} | Should -Throw '*mismatch*'
    }
    It 'rejects optimistic automatic retry in barrier' {
        $fakeBarrier.AutomaticRetryAllowed=$true
        {Assert-OPA264Live4Barrier -Record $fakeBarrier -Request $req -Window 'WorkerStartedBeforeMove' -ExpectedWorkerPid ([int]$PID)} | Should -Throw '*mismatch*'
    }
    It 'rejects optimistic journal completion in barrier' {
        $fakeBarrier.JournalCompleted=$true
        {Assert-OPA264Live4Barrier -Record $fakeBarrier -Request $req -Window 'WorkerStartedBeforeMove' -ExpectedWorkerPid ([int]$PID)} | Should -Throw '*mismatch*'
    }
    It 'requires independent reconciliation for any barrier' {
        $fakeBarrier.RequiresIndependentReconciliation=$false
        {Assert-OPA264Live4Barrier -Record $fakeBarrier -Request $req -Window 'WorkerStartedBeforeMove' -ExpectedWorkerPid ([int]$PID)} | Should -Throw '*mismatch*'
    }
    It 'refuses to accept a missing durable dispatch claim' {
        {Assert-OPA264Live4Claim -Path $crashPaths.DispatchClaim -OperationId $op} | Should -Throw '*missing*'
    }
    It 'refuses a dispatch claim belonging to another operation' {
        [IO.File]::WriteAllText($crashPaths.DispatchClaim,([guid]::NewGuid().ToString('D')))
        {Assert-OPA264Live4Claim -Path $crashPaths.DispatchClaim -OperationId $op} | Should -Throw '*another operation*'
    }
    It 'accepts a matching flushed dispatch claim' {
        [IO.File]::WriteAllText($crashPaths.DispatchClaim,($op+[char]10))
        (Assert-OPA264Live4Claim -Path $crashPaths.DispatchClaim -OperationId $op) | Should -BeTrue
    }
    It 'does not write a crash barrier without parent-owned dispatch claim' {
        {Write-OPA264Live4Barrier -Request $req -FixturePaths $paths -Window 'WorkerStartedBeforeMove' -WorkerProcessId ([int]$PID)} | Should -Throw '*missing*'
    }
    It 'writes a unique pre-Move barrier without claiming actual MailItem.Move' {
        [IO.File]::WriteAllText($crashPaths.DispatchClaim,($op+[char]10))
        $barrier=Write-OPA264Live4Barrier -Request $req -FixturePaths $paths -Window 'WorkerStartedBeforeMove' -WorkerProcessId ([int]$PID)
        $barrier.CrashWindow | Should -Be 'WorkerStartedBeforeMove'
        [IO.File]::Exists($paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects pre-Move barrier if a Move claim already exists' {
        [IO.File]::WriteAllText($crashPaths.DispatchClaim,($op+[char]10))
        [IO.File]::WriteAllText($paths.ClaimPath,($op+[char]10))
        {Write-OPA264Live4Barrier -Request $req -FixturePaths $paths -Window 'WorkerStartedBeforeMove' -WorkerProcessId ([int]$PID)} | Should -Throw '*already claimed*'
    }
    It 'requires a Move attempt claim for post-Move barrier' {
        [IO.File]::WriteAllText($crashPaths.DispatchClaim,($op+[char]10))
        {Write-OPA264Live4Barrier -Request $req -FixturePaths $paths -Window 'AfterMoveBeforeResponse' -WorkerProcessId ([int]$PID)} | Should -Throw '*missing*'
    }
    It 'accepts post-Move barrier with matching attempt claim and no response' {
        [IO.File]::WriteAllText($crashPaths.DispatchClaim,($op+[char]10))
        [IO.File]::WriteAllText($paths.ClaimPath,($op+[char]10))
        $barrier=Write-OPA264Live4Barrier -Request $req -FixturePaths $paths -Window 'AfterMoveBeforeResponse' -WorkerProcessId ([int]$PID)
        $barrier.CrashWindow | Should -Be 'AfterMoveBeforeResponse'
        [IO.File]::Exists($paths.ResponsePath) | Should -BeFalse
    }
    It 'rejects post-Move barrier with unrelated attempt claim' {
        [IO.File]::WriteAllText($crashPaths.DispatchClaim,($op+[char]10))
        [IO.File]::WriteAllText($paths.ClaimPath,([guid]::NewGuid().ToString('D')))
        {Write-OPA264Live4Barrier -Request $req -FixturePaths $paths -Window 'AfterMoveBeforeResponse' -WorkerProcessId ([int]$PID)} | Should -Throw '*another operation*'
    }
    It 'rejects duplicate barrier creation for a single RunId' {
        [IO.File]::WriteAllText($crashPaths.DispatchClaim,($op+[char]10))
        [void](Write-OPA264Live4Barrier -Request $req -FixturePaths $paths -Window 'WorkerStartedBeforeMove' -WorkerProcessId ([int]$PID))
        {Write-OPA264Live4Barrier -Request $req -FixturePaths $paths -Window 'WorkerStartedBeforeMove' -WorkerProcessId ([int]$PID)} | Should -Throw
    }
    It 'blocks direct LIVE3 Worker reuse after a LIVE4 dispatch claim' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264Live3SyntheticWorker.ps1') -Raw
        $text | Should -Match 'controller-dispatch.claim'
        $text | Should -Match 'already dispatched by LIVE4'
    }
    It 'LIVE4 Worker requires dispatch claim and blocks existing crash evidence' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264Live4CrashWorker.ps1') -Raw
        $text | Should -Match 'Assert-OPA264Live4Claim'
        $text | Should -Match 'CrashBarrier'
        $text | Should -Match 'ControllerResult'
        $text | Should -Match 'previously crashed or reported RunId'
    }
    It 'the controller terminates only its own created child and never Outlook process' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264Live4CrashController.ps1') -Raw
        $text | Should -Match '\$child\.Kill\(\)'
        $text | Should -Not -Match 'Stop-Process|Get-Process|OUTLOOK\.EXE'
    }
    It 'the independent recovery inspector never mutates Outlook or claims' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA264Live4CrashRecovery.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object {[string]$_.Member.Value -in @(
            'Move','AddStoreEx','AddStore','RemoveStore','Delete','Save','Kill'
        )}).Count | Should -Be 0
    }

}
