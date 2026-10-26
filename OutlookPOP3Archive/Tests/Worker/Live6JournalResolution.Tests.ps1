#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live5Reconciliation.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live6JournalResolution.ps1')
}
Describe '2.6.4-LIVE6 explicit synthetic-only journal resolution protocol (offline)' {
    BeforeEach {
        $run=[guid]::NewGuid().ToString('D')
        $op=[guid]::NewGuid().ToString('D')
        $dir=Join-Path $TestDrive $run
        [void][IO.Directory]::CreateDirectory($dir)
        $paths=[pscustomobject]@{
            Directory=$dir;RunId=$run
            JournalPath=(Join-Path $dir 'move.operations.jsonl')
            ArchivePst=(Join-Path $dir 'Archive.pst')
        }
        $req=[pscustomobject]@{
            RunId=$run;OperationId=$op;SourceEntryId='synthetic-source-entry'
            SourceStoreId='TEST-POP3-STORE'
            SourceFolderPath='\POP3\OPA264-LIVE3-synthetic-only'
            ArchiveFolderPath='\TempArchive\OPA264-LIVE3-Archive-synthetic-only'
        }
        $intent=Write-OPAOperationJournalEvent -Path $paths.JournalPath -TransactionId $run -OperationId $op -Sequence 1 -Phase Intent -OperationKind MailMove -SourceEntryId $req.SourceEntryId -SourceStoreId $req.SourceStoreId -SourceFolderPath $req.SourceFolderPath -TargetFolderPath $req.ArchiveFolderPath -ArchivePst $paths.ArchivePst -InternetMessageId ('<opa264-live3-'+$run+'@example.invalid>') -Subject ('OPA264 LIVE3 synthetic '+$run) -Size 0
        $hash=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $archiveEntry='SYNTHETIC-ARCHIVE-ENTRY'
        $review=[pscustomobject]@{
            Schema='2.6.4-LIVE5.ReconciliationReview.1'
            RunId=$run;OperationId=$op;CrashWindow='AfterMoveBeforeResponse'
            Decision='MoveConfirmed'
            SourceItemCount=0;ArchiveItemCount=1
            SyntheticSourceMatches=0;SyntheticArchiveMatches=1
            MoveAttemptClaimExists=$true
            EvidenceSufficientForClassification=$true
            JournalUnchanged=$true;JournalSha256=$hash
            OutlookMoveExecuted=$false;JournalCompleted=$false
            JournalReconciled=$false;AutomaticRetryAllowed=$false
            RequiresManualJournalDecision=$true;ProductionReady=$false
        }
    }
    It 'uses a fixed claim path inside the exact fixture directory' {
        (Get-OPA264Live6ClaimPath -Paths $paths) | Should -Be (Join-Path $dir 'live6-resolution.claim')
    }
    It 'accepts exact independent MoveConfirmed evidence and pinned SHA256' {
        (Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash) | Should -BeTrue
    }
    It 'rejects pre-Move NoMoveObserved as journal success' {
        $review.Decision='NoMoveObserved'
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects missing target fingerprint' {
        $review.SyntheticArchiveMatches=0
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects duplicate archive items' {
        $review.ArchiveItemCount=2
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects matching source mail remaining' {
        $review.SourceItemCount=1
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects crash before the Move' {
        $review.CrashWindow='WorkerStartedBeforeMove'
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects missing Move claim' {
        $review.MoveAttemptClaimExists=$false
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects foreign RunId' {
        $review.RunId=[guid]::NewGuid().ToString('D')
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects foreign OperationId' {
        $review.OperationId=[guid]::NewGuid().ToString('D')
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects stale pinned journal SHA256' {
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 ('a'*64)} | Should -Throw '*proof*'
    }
    It 'rejects optimistic automatically retryable evidence' {
        $review.AutomaticRetryAllowed=$true
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects an already reconciled review' {
        $review.JournalReconciled=$true
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects mutated Outlook inspection claims' {
        $review.OutlookMoveExecuted=$true
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects production ready evidence' {
        $review.ProductionReady=$true
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects incomplete journal inspection' {
        $review.JournalUnchanged=$false
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'rejects missing explicit manual journal decision' {
        $review.RequiresManualJournalDecision=$false
        {Assert-OPA264Live6CommitReview -Review $review -Request $req -ExpectedJournalSha256 $hash} | Should -Throw '*proof*'
    }
    It 'creates a flushed unique, non-retryable claim before any journal append' {
        $c=New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry
        $c.Schema | Should -Be '2.6.4-LIVE6.ResolutionClaim.1'
        $c.AutomaticRetryAllowed | Should -BeFalse
        $c.ProductionReady | Should -BeFalse
        @((Read-OPAOperationJournal -Path $paths.JournalPath).Events).Count | Should -Be 1
    }
    It 'refuses the second CreateNew claim for the same RunId' {
        [void](New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        {New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry} | Should -Throw
    }
    It 'refuses claim without a real archive EntryID' {
        {New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId ' '} | Should -Throw '*nonempty*'
    }
    It 'refuses append without a prior durable claim' {
        {Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry} | Should -Throw '*claim*'
    }
    It 'refuses append if claim belongs to another EntryID' {
        [void](New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        {Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId 'OTHER'} | Should -Throw '*claim*'
    }
    It 'appends exactly one durable Reconciled with destination EntryID' {
        $claim=New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry
        (Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry) | Should -BeTrue
        $journal=Read-OPAOperationJournal -Path $paths.JournalPath
        @($journal.Events).Count | Should -Be 2
        $journal.Events[1].Phase | Should -Be 'Reconciled'
        $journal.Events[1].ArchiveEntryId | Should -Be $archiveEntry
        (Assert-OPA264Live6Completed -Request $req -Paths $paths -Journal $journal -Claim $claim) | Should -BeTrue
    }
    It 'preserves all original Intent bytes when appending' {
        $before=[IO.File]::ReadAllBytes($paths.JournalPath)
        [void](New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        [void](Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        $after=[IO.File]::ReadAllBytes($paths.JournalPath)
        $first=New-Object byte[] $before.Length
        [Array]::Copy($after,$first,$before.Length)
        ([Convert]::ToBase64String($first)) | Should -Be ([Convert]::ToBase64String($before))
    }
    It 'fails closed if pinned SHA256 changed after the claim' {
        [void](New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        [IO.File]::AppendAllText($paths.JournalPath,' ')
        {Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry} | Should -Throw '*changed*'
    }
    It 'blocks re-append if a terminal entry already exists' {
        [void](New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        [void](Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        {Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry} | Should -Throw '*changed*'
        @((Read-OPAOperationJournal -Path $paths.JournalPath).Events).Count | Should -Be 2
    }
    It 'rejects a foreign operation in an existing terminal entry' {
        $claim=New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry
        [void](Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        $claim.OperationId=[guid]::NewGuid().ToString('D')
        {Assert-OPA264Live6Completed -Request $req -Paths $paths -Journal (Read-OPAOperationJournal -Path $paths.JournalPath) -Claim $claim} | Should -Throw '*disagree*'
    }
    It 'rejects extra terminal entries' {
        $claim=New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry
        [void](Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        $j=Read-OPAOperationJournal -Path $paths.JournalPath
        $j.Events=@($j.Events[0],$j.Events[1],$j.Events[1])
        {Assert-OPA264Live6Completed -Request $req -Paths $paths -Journal $j -Claim $claim} | Should -Throw '*exactly*'
    }
    It 'rejects a terminal event containing a different archive identity' {
        $claim=New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry
        [void](Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        $j=Read-OPAOperationJournal -Path $paths.JournalPath
        $j.Events[1].ArchiveEntryId='Different-EntryID'
        {Assert-OPA264Live6Completed -Request $req -Paths $paths -Journal $j -Claim $claim} | Should -Throw '*disagree*'
    }
    It 'refuses an incomplete final journal line' {
        $claim=New-OPA264Live6Claim -Request $req -Paths $paths -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry
        [void](Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $intent -ExpectedJournalSha256 $hash -ArchiveEntryId $archiveEntry)
        $j=Read-OPAOperationJournal -Path $paths.JournalPath
        $j.TrailingPartial=$true
        {Assert-OPA264Live6Completed -Request $req -Paths $paths -Journal $j -Claim $claim} | Should -Throw '*exactly*'
    }
    It 'never invokes Outlook Move or starts new processes from its CLI' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264Live6JournalResolution.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $text=Get-Content -LiteralPath $path -Raw
        $text | Should -Not -Match 'Start-Process|Stop-Process|MailItem.Move'
        $text | Should -Match 'Test-OPA264Live5Reconciliation'
        $text | Should -Match 'ExpectedJournalSha256'
        $text | Should -Match 'ConfirmSyntheticJournalResolution'
        $methods=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object {[string]$_.Member.Value -in @(
            'Move','AddStoreEx','AddStore','RemoveStore','Delete','Save','Kill'
        )}).Count | Should -Be 0
    }
}

Describe '2.6.4-LIVE6a cross-PST store-computed size evidence and explicit approval' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../../Core/Worker/Live6JournalResolution.ps1')
    }
    BeforeEach {
        $same=Get-OPA264Live6SizeEvidence -IntentSizeBytes 3000 -ObservedArchiveSizeBytes 3000
        $changed=Get-OPA264Live6SizeEvidence -IntentSizeBytes 3000 -ObservedArchiveSizeBytes 3024
    }
    It 'reports exact matching pre/post-PST size without drift' {
        $same.CrossPstSizeDiffers | Should -BeFalse
        $same.IntentSizeBytes | Should -Be 3000
        $same.ObservedArchiveSizeBytes | Should -Be 3000
    }
    It 'reports exact changed source/archive byte sizes and signed delta' {
        $changed.CrossPstSizeDiffers | Should -BeTrue
        $changed.SizeDifferenceBytes | Should -Be 24
    }
    It 'reports signed negative delta for smaller destination message' {
        $e=Get-OPA264Live6SizeEvidence -IntentSizeBytes 3000 -ObservedArchiveSizeBytes 2990
        $e.CrossPstSizeDiffers | Should -BeTrue
        $e.SizeDifferenceBytes | Should -Be -10
    }
    It 'rejects unknown zero original Intent size' {
        {Get-OPA264Live6SizeEvidence -IntentSizeBytes 0 -ObservedArchiveSizeBytes 1000} | Should -Throw '*unknown*'
    }
    It 'rejects unknown zero observed archive size' {
        {Get-OPA264Live6SizeEvidence -IntentSizeBytes 3000 -ObservedArchiveSizeBytes 0} | Should -Throw '*unknown*'
    }
    It 'rejects negative observed destination size' {
        {Get-OPA264Live6SizeEvidence -IntentSizeBytes 3000 -ObservedArchiveSizeBytes -1} | Should -Throw '*unknown*'
    }
    It 'allows a matching size without extra flags' {
        (Assert-OPA264Live6SizeApproval -Evidence $same) | Should -BeTrue
    }
    It 'rejects unsolicited size-difference flag on matching sizes' {
        {Assert-OPA264Live6SizeApproval -Evidence $same -ConfirmCrossPstSizeDifference} | Should -Throw '*unsolicited*'
    }
    It 'rejects unsolicited expected size on matching sizes' {
        {Assert-OPA264Live6SizeApproval -Evidence $same -ExpectedArchiveSizeBytes 3000} | Should -Throw '*unsolicited*'
    }
    It 'rejects drift without independent explicit approval' {
        {Assert-OPA264Live6SizeApproval -Evidence $changed} | Should -Throw '*explicit consent*'
    }
    It 'rejects drift when only observed size is pinned' {
        {Assert-OPA264Live6SizeApproval -Evidence $changed -ExpectedArchiveSizeBytes 3024} | Should -Throw '*explicit consent*'
    }
    It 'rejects drift when consent lacks observed size pin' {
        {Assert-OPA264Live6SizeApproval -Evidence $changed -ConfirmCrossPstSizeDifference} | Should -Throw '*exact pinned*'
    }
    It 'rejects stale archive size pin even with manual consent' {
        {Assert-OPA264Live6SizeApproval -Evidence $changed -ConfirmCrossPstSizeDifference -ExpectedArchiveSizeBytes 3023} | Should -Throw '*exact pinned*'
    }
    It 'accepts size drift only with explicit consent and exact observed archive byte pin' {
        (Assert-OPA264Live6SizeApproval -Evidence $changed -ConfirmCrossPstSizeDifference -ExpectedArchiveSizeBytes 3024) | Should -BeTrue
    }
    It 'wires reviewer fields and separate consent flag into the LIVE6 CLI' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264Live6JournalResolution.ps1'
        $content=Get-Content -LiteralPath $path -Raw
        $content | Should -Match 'CanExecuteWithExplicitSizeConsent'
        $content | Should -Match 'ObservedArchiveSizeBytes'
        $content | Should -Match 'IntentSizeBytes'
        $content | Should -Match 'ConfirmCrossPstSizeDifference'
        $content | Should -Match 'Assert-OPA264Live6SizeApproval'
    }
}
