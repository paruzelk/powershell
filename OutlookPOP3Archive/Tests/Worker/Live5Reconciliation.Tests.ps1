#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live5Reconciliation.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
}
Describe '2.6.4-LIVE5 independent read-only crash reconciliation (offline)' {
    BeforeEach {
        $run=[guid]::NewGuid().ToString('D')
        $op=[guid]::NewGuid().ToString('D')
        $req=[pscustomobject]@{
            RunId=$run;OperationId=$op;SourceEntryId='one-synthetic-source'
            SourceStoreId='POP3-Test-Store'
            SourceFolderPath='\Source\OPA264-LIVE3-synthetic'
            ArchiveFolderPath='\Archive\OPA264-LIVE3-Archive-synthetic'
        }
        $paths=[pscustomobject]@{
            RunId=$run;ArchivePst='C:\TestOnly\Archive.pst'
        }
        $intent=[pscustomobject]@{
            SchemaVersion='1.0';Sequence=1;Phase='Intent';OperationKind='MailMove'
            TransactionId=$run;OperationId=$op
            SourceEntryId=$req.SourceEntryId;SourceStoreId=$req.SourceStoreId
            SourceFolderPath=$req.SourceFolderPath
            TargetFolderPath=$req.ArchiveFolderPath
            ArchivePst=$paths.ArchivePst
            InternetMessageId=('<opa264-live3-'+$run+'@example.invalid>')
            Subject=('OPA264 LIVE3 synthetic '+$run)
            Size=0
        }
        $journal=[pscustomobject]@{Events=@($intent);TrailingPartial=$false}
        $replay=Resolve-OPAOperationRecovery -Journal $journal
        $recovery=[pscustomobject]@{
            Schema='2.6.4-LIVE4.RecoverySnapshot.1'
            RunId=$run;OperationId=$op
            CrashWindow='WorkerStartedBeforeMove'
            Status='PreMoveCrashNoMoveObserved'
            SourceItemCount=1;ArchiveItemCount=0
            SyntheticSourceMatches=1;SyntheticArchiveMatches=0
            ControllerDispatchClaimExists=$true
            MoveAttemptClaimExists=$false
            WorkerResponseExists=$false
            WorkerKilledByOwningController=$true
            OutlookExaminedOnlySyntheticFolders=$true
            MoveExecutedByThisInspection=$false
            JournalCompleted=$false;AutomaticRetryAllowed=$false
            RequiresIndependentReconciliation=$true;ProductionReady=$false
        }
    }
    It 'replays one unresolved LIVE4 MailMove Intent' {
        $result=Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal
        @($result.Indeterminate).Count | Should -Be 1
        $result.BlockAutomaticRetry | Should -BeTrue
    }
    It 'rejects torn journal tails' {
        $journal.TrailingPartial=$true
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*complete*'
    }
    It 'rejects empty journal' {
        $journal.Events=@()
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*one complete*'
    }
    It 'rejects duplicate journal events' {
        $journal.Events=@($intent,$intent)
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*one complete*'
    }
    It 'rejects stale/completed journal phase' {
        $intent.Phase='Completed'
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*mismatch*'
    }
    It 'rejects different operation in Intent' {
        $intent.OperationId=[guid]::NewGuid().ToString('D')
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*mismatch*'
    }
    It 'rejects a different source EntryID' {
        $intent.SourceEntryId='other-email'
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*mismatch*'
    }
    It 'rejects a different archive PST' {
        $intent.ArchivePst='C:\Other\Archive.pst'
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*mismatch*'
    }
    It 'rejects a different synthetic InternetMessageId' {
        $intent.InternetMessageId='<other@example.invalid>'
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*mismatch*'
    }
    It 'rejects a different synthetic subject' {
        $intent.Subject='Normal inbox item'
        {Assert-OPA264Live5Journal -Request $req -Paths $paths -Journal $journal} | Should -Throw '*mismatch*'
    }
    It 'classifies pre-Move crash with exact source item as NoMoveObserved' {
        $d=Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay
        $d.Decision | Should -Be 'NoMoveObserved'
        $d.EvidenceSufficientForClassification | Should -BeTrue
    }
    It 'classifies post-Move crash with exact archive item as MoveConfirmed' {
        $recovery.CrashWindow='AfterMoveBeforeResponse'
        $recovery.Status='PostMoveCrashMoveObserved'
        $recovery.SourceItemCount=0;$recovery.ArchiveItemCount=1
        $recovery.SyntheticSourceMatches=0;$recovery.SyntheticArchiveMatches=1
        $recovery.MoveAttemptClaimExists=$true
        $d=Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay
        $d.Decision | Should -Be 'MoveConfirmed'
        $d.EvidenceSufficientForClassification | Should -BeTrue
    }
    It 'never authorizes auto retry or journal completion, even on NoMoveObserved' {
        $d=Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay
        $d.AutomaticRetryAllowed | Should -BeFalse
        $d.JournalCompleted | Should -BeFalse
        $d.JournalReconciled | Should -BeFalse
        $d.RequiresManualJournalDecision | Should -BeTrue
        $d.ProductionReady | Should -BeFalse
    }
    It 'classifies exactly one synthetic match in each folder as ambiguous duplicate' {
        $recovery.SourceItemCount=1;$recovery.ArchiveItemCount=1
        $recovery.SyntheticSourceMatches=1;$recovery.SyntheticArchiveMatches=1
        $recovery.Status='IndeterminateNeedsManualReview'
        $d=Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay
        $d.Decision | Should -Be 'AmbiguousDuplicate'
        $d.EvidenceSufficientForClassification | Should -BeFalse
    }
    It 'classifies no items in either folder as MissingItem' {
        $recovery.SourceItemCount=0;$recovery.ArchiveItemCount=0
        $recovery.SyntheticSourceMatches=0
        $recovery.Status='IndeterminateNeedsManualReview'
        (Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay).Decision | Should -Be 'MissingItem'
    }
    It 'blocks unexplained extra archive item as Ambiguous' {
        $recovery.ArchiveItemCount=2
        $recovery.SyntheticArchiveMatches=1
        $recovery.Status='IndeterminateNeedsManualReview'
        (Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay).Decision | Should -Be 'Ambiguous'
    }
    It 'blocks a missing source fingerprint despite one source item' {
        $recovery.SyntheticSourceMatches=0
        $recovery.Status='IndeterminateNeedsManualReview'
        (Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay).Decision | Should -Be 'Ambiguous'
    }
    It 'does not claim pre-Move success when Move claim exists' {
        $recovery.MoveAttemptClaimExists=$true
        $recovery.Status='IndeterminateNeedsManualReview'
        (Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay).Decision | Should -Be 'Ambiguous'
    }
    It 'does not claim post-Move success with missing Move claim' {
        $recovery.CrashWindow='AfterMoveBeforeResponse'
        $recovery.Status='IndeterminateNeedsManualReview'
        $recovery.SourceItemCount=0;$recovery.ArchiveItemCount=1
        $recovery.SyntheticSourceMatches=0;$recovery.SyntheticArchiveMatches=1
        (Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay).Decision | Should -Be 'Ambiguous'
    }
    It 'rejects impossible negative counts' {
        $recovery.SourceItemCount=-1
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*impossible*'
    }
    It 'rejects more matching messages than observed items' {
        $recovery.SyntheticSourceMatches=2
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*impossible*'
    }
    It 'rejects another RunId in recovery data' {
        $recovery.RunId=[guid]::NewGuid().ToString('D')
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*mismatch*'
    }
    It 'rejects another OperationId in recovery data' {
        $recovery.OperationId=[guid]::NewGuid().ToString('D')
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*mismatch*'
    }
    It 'rejects altered journal replay transaction identity' {
        $replay.TransactionId=[guid]::NewGuid().ToString('D')
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*mismatch*'
    }
    It 'rejects recovery snapshots with Worker response' {
        $recovery.WorkerResponseExists=$true
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*untrusted*'
    }
    It 'rejects missing controller claim evidence' {
        $recovery.ControllerDispatchClaimExists=$false
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*untrusted*'
    }
    It 'rejects recovery inspector touching existing inbox' {
        $recovery.OutlookExaminedOnlySyntheticFolders=$false
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*untrusted*'
    }
    It 'rejects any automatic retry flag from recovery' {
        $recovery.AutomaticRetryAllowed=$true
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*untrusted*'
    }
    It 'rejects an already terminal journal' {
        $replay.Resolved=@('a completed operation')
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*untrusted*'
    }
    It 'rejects arbitrary crash windows' {
        $recovery.CrashWindow='DuringMove'
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*untrusted*'
    }
    It 'requires manual review flag from original recovery' {
        $recovery.RequiresIndependentReconciliation=$false
        {Get-OPA264Live5Decision -Request $req -Recovery $recovery -JournalReplay $replay} | Should -Throw '*untrusted*'
    }
    It 'read-only CLI contains no Outlook mutation or journal commit methods' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA264Live5Reconciliation.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object {[string]$_.Member.Value -in @(
            'Move','AddStoreEx','AddStore','RemoveStore','Delete','Save','Kill','AppendAllText','WriteAllText'
        )}).Count | Should -Be 0
        $text=Get-Content -LiteralPath $path -Raw
        $text | Should -Not -Match 'Write-OPAOperationJournalEvent|Stop-Process|Start-Process'
        $text | Should -Match 'Test-OPA264Live4CrashRecovery'
        $text | Should -Match 'Get-FileHash'
    }
}
