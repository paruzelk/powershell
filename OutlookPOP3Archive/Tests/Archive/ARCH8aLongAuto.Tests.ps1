#requires -Version 5.1
BeforeAll {
    $script:aRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:aRoot 'Core/Archive/ARCH7eAuto.ps1')
    . (Join-Path $script:aRoot 'Core/Archive/ARCH7dSupervisor.ps1')
    . (Join-Path $script:aRoot 'Core/Archive/ARCH7cRecovery.ps1')
    . (Join-Path $script:aRoot 'Core/Archive/ARCH6Deferred.ps1')
    . (Join-Path $script:aRoot 'Core/Archive/ARCH6Orchestration.ps1')
    . (Join-Path $script:aRoot 'Core/Archive/ARCH4Batch.ps1')
    . (Join-Path $script:aRoot 'Core/Archive/ArchiveTransaction.ps1')
    . (Join-Path $script:aRoot 'Core/Archive/ArchiveVerifier.ps1')
    . (Join-Path $script:aRoot 'Core/Archive/ARCH2bSemanticWitness.ps1')
    $script:aMain=Join-Path $script:aRoot 'OutlookPOP3Archive.ps1'
    $script:aController=Join-Path $script:aRoot 'Invoke-OPALiveArchiveBatches.ps1'
    $script:aPst='C:\Test\Mail.pst'
    $script:aRow=[pscustomobject]@{SourcePst=$script:aPst;Directory='fake'}
    function New-ARCH8aBatch {
        param([string]$Status='BatchLimitReached',[int]$Verified=500,[int]$Deferred=0,[int]$Unprocessed=0,[int]$Batches=1)
        [pscustomobject]@{Schema='2.6.5-ARCH7d.Supervisor.1';Status=$Status;Verified=$Verified;Deferred=$Deferred;Unprocessed=$Unprocessed;Batches=$Batches;ProductionReady=$false;AutomaticMoveRetryAllowed=$false;OutlookRestartRequired=$false;LastBatchResult=$null}
    }
}
Describe 'ARCH8a explicitly scoped autonomous test archive' {
    It 'preserves the original bounded Auto defaults' {
        $r=& $script:aMain -Mode Auto -ConfirmDevAutoArchive -WhatIf
        $r.BatchSize | Should -Be 10
        $r.MaxBatchesPerSource | Should -Be 100
        $r.LongArchive | Should -BeFalse
    }
    It 'exposes 500 and unlimited only in long Auto WhatIf' {
        $r=& $script:aMain -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -LongArchiveSourcePst $script:aPst -Quiet -WhatIf
        $r.Status | Should -BeExactly NoOutlookOrPersistentWrites
        $r.BatchSize | Should -Be 500
        $r.MaxBatchesPerSource | Should -Be 0
        $r.LongArchive | Should -BeTrue
        $r.PinnedSourcePst | Should -BeExactly $script:aPst
        $r.DisableStoragePolicy | Should -BeTrue
        $r.DisableArchivePstSizeLimit | Should -BeTrue
        $r.ProductionReady | Should -BeFalse
    }
    It 'allows a bounded smaller pilot under the explicit long scope' {
        $r=& $script:aMain -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -LongArchiveSourcePst $script:aPst -Limit 100 -AutoDevMaxBatches 2 -WhatIf
        $r.BatchSize | Should -Be 100
        $r.MaxBatchesPerSource | Should -Be 2
    }
    It 'refuses unlimited or a batch of 500 under legacy consent alone' {
        {& $script:aMain -Mode Auto -ConfirmDevAutoArchive -AutoDevMaxBatches 0 -WhatIf} | Should -Throw '*ConfirmDevLongArchive*'
        {& $script:aMain -Mode Auto -ConfirmDevAutoArchive -Limit 500 -WhatIf} | Should -Throw '*requires age-only Auto DEV*'
    }
    It 'rejects missing or nonlocal pin and missing Auto consent' {
        {& $script:aMain -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -WhatIf} | Should -Throw '*exact local test source PST*'
        {& $script:aMain -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -LongArchiveSourcePst '\\server\share\a.pst' -WhatIf} | Should -Throw '*exact local test source PST*'
        {& $script:aMain -Mode Auto -ConfirmDevLongArchive -LongArchiveSourcePst $script:aPst -WhatIf} | Should -Throw
        {& $script:aMain -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -LongArchiveSourcePst $script:aPst -Limit 501 -WhatIf} | Should -Throw
    }
    It 'requires exactly the pinned discovered delivery store before any worker' {
        {Assert-OPAARCH8aPinnedSource -Sources @($script:aRow) -PinnedPath $script:aPst} | Should -Not -Throw
        {Assert-OPAARCH8aPinnedSource -Sources @() -PinnedPath $script:aPst} | Should -Throw '*exactly one discovered POP3*'
        {Assert-OPAARCH8aPinnedSource -Sources @($script:aRow,$script:aRow) -PinnedPath $script:aPst} | Should -Throw '*exactly one discovered POP3*'
        {Assert-OPAARCH8aPinnedSource -Sources @($script:aRow) -PinnedPath 'C:\Other.pst'} | Should -Throw '*exactly one discovered POP3*'
    }
    It 'permits long controller WhatIf but not long controlled interruption or unconfirmed large batch' {
        $r=& $script:aController -SourcePst $script:aPst -ProfileName Outlook -ConfirmTestArchive -ConfirmLiveOutlookVerification -ConfirmDevLongArchive -BatchSize 500 -WhatIf
        $r.Status | Should -BeExactly NoOutlookOrPersistentWrites
        $r.BatchSize | Should -Be 500
        {& $script:aController -SourcePst $script:aPst -ProfileName Outlook -ConfirmTestArchive -ConfirmLiveOutlookVerification -BatchSize 500 -WhatIf} | Should -Throw '*long test scope*'
        {& $script:aController -SourcePst $script:aPst -ProfileName Outlook -ConfirmTestArchive -ConfirmLiveOutlookVerification -ConfirmDevLongArchive -BatchSize 500 -InterruptAfterReturned 2 -WhatIf} | Should -Throw '*long test scope*'
    }
    It 'requires explicit long scope at the public Archive worker entrypoint' {
        $r=& $script:aMain -Mode Archive -SourcePst $script:aPst -ProfileName Outlook -ConfirmTestArchive -ConfirmLiveOutlookVerification -ConfirmDevLongArchive -Limit 500 -WhatIf
        $r.Status | Should -BeExactly NoOutlookOrPersistentWrites
        $r.Limit | Should -Be 500
        {& $script:aMain -Mode Archive -SourcePst $script:aPst -ProfileName Outlook -ConfirmTestArchive -ConfirmLiveOutlookVerification -Limit 500 -WhatIf} | Should -Throw '*explicit test live verification*'
    }
    It 'runs beyond 100 batches until observed exhaustion using synthetic receipts' {
        $script:aCalls=0
        $r=Invoke-OPAARCH7eSourceSequence -Sources @($script:aRow) -MaxBatchesPerSource 0 -ConfirmDevLongArchive -PendingOwner {} -RunSource {
            $script:aCalls++
            if($script:aCalls -le 101){New-ARCH8aBatch}else{New-ARCH8aBatch -Status NoEligibleMessages -Verified 0}
        }
        $script:aCalls | Should -Be 102
        $r.Status | Should -BeExactly AllSourcesExhausted
        $r.Verified | Should -Be 50500
        $r.ProductionReady | Should -BeFalse
    }
    It 'keeps the unlimited path closed under legacy consent' {
        {Invoke-OPAARCH7eSourceSequence -Sources @($script:aRow) -MaxBatchesPerSource 0 -PendingOwner {} -RunSource {throw 'unexpected'}} | Should -Throw '*unlimited requires explicit*'
    }
    It 'stops the unlimited run on zero progress or unknown worker without retry' {
        foreach($state in @('BatchLimitReached','WorkerStillRunning')){
            $script:aCalls=0
            $r=Invoke-OPAARCH7eSourceSequence -Sources @($script:aRow) -MaxBatchesPerSource 0 -ConfirmDevLongArchive -PendingOwner {} -RunSource {
                $script:aCalls++
                if($script:aCalls -gt 1){throw 'unsafe repeat'}
                New-ARCH8aBatch -Status $state -Verified 0
            }
            $script:aCalls | Should -Be 1
            $r.Status | Should -BeExactly PartialOrBlocked
            $r.Sources[0].Status | Should -BeIn @('StoppedNoProgress','WorkerStillRunning')
        }
    }
    It 'rejects inconsistent exhaustion and oversized supervisor result' {
        foreach($state in @('NoEligibleMessages','BatchLimitReached')){
            $r=Invoke-OPAARCH7eSourceSequence -Sources @($script:aRow) -MaxBatchesPerSource 0 -ConfirmDevLongArchive -PendingOwner {} -RunSource {
                New-ARCH8aBatch -Status $state -Verified $(if($state -eq 'NoEligibleMessages'){1}else{501})
            }
            $r.Sources[0].Status | Should -BeExactly SupervisorException
            $r.Sources[0].Attempts | Should -Be 1
        }
    }
    It 'accepts a full deferred-only batch in long supervisor but not the legacy supervisor' {
        $archive={ [pscustomobject]@{Exited=$true;ExitCode=0;WorkerId=1;Result=[pscustomobject]@{Schema='2.6.5-ARCH4.Completed.1';Status='BatchCompletedNoMoves';Planned=500;DeferredRecorded=500;Verified=0;Indexed=0}} }
        $r=Invoke-OPAARCH7dSequence -ReadPending {} -Archive $archive -Resume {throw 'unexpected'} -Record {} -ConfirmDevLongArchive
        $r.Deferred | Should -Be 500
        {Invoke-OPAARCH7dSequence -ReadPending {} -Archive $archive -Resume {throw 'unexpected'} -Record {}} | Should -Throw '*unproven Archive completion*'
    }
    It 'recovers a proven prefix of a 500-item selection without replay' {
        $plan=@(1..500 | ForEach-Object {[pscustomobject]@{EntryId=('id'+$_)}})
        $tx=[pscustomobject]@{State=[pscustomobject]@{Limit=500;PlannedItems=$plan;Status='Running';Executed=1;Verified=0;Skipped=0;SkippedEntryIds=@();SkippedItems=@()}}
        $state=[pscustomobject]@{Planned=500;Returned=1;Claimed=1;Reconciled=0;OperationEventCount=1;AwaitingRestart=$false;Rows=@([pscustomobject]@{SourceEntryId='id1'})}
        $steps=@([pscustomobject]@{Step='ARCH4 Batch Started'},[pscustomobject]@{Step='Candidates'},[pscustomobject]@{Step='Move Started';EntryId='id1'},[pscustomobject]@{Step='ARCH4 Move Returned';EntryId='id1'})
        $r=Get-OPAARCH7cInterruptedReview -Transaction $tx -State $state -Steps $steps -ConfirmDevLongArchive
        $r.Unprocessed | Should -Be 499
        $r.Returned | Should -Be 1
        {Get-OPAARCH7cInterruptedReview -Transaction $tx -State $state -Steps $steps} | Should -Throw '*invalid bounded checkpoint*'
        {Get-OPAARCH7cInterruptedReview -Transaction $tx -State $state -Steps @($steps[0..2]) -ConfirmDevLongArchive} | Should -Throw '*unresolved or unordered claim*'
    }
    It 'reconciles an existing long pending transaction before any new archive' {
        $script:aPending=[pscustomobject]@{TransactionId='20261126-180000-abcdef12';MoveWorkerId=101}
        $r=Invoke-OPAARCH7dSequence -ReadPending {$script:aPending} -Archive {throw 'must not launch Archive'} -Record {} -ConfirmDevLongArchive -Resume {
            param($id)
            $script:aPending=$null
            [pscustomobject]@{Exited=$true;ExitCode=0;WorkerId=202;Result=[pscustomobject]@{Schema='2.6.5-ARCH4.Completed.1';Status='LiveInterruptedBatchRecovered';TransactionId=$id;PendingCleared=$true;OutlookRestartRequired=$false;VerifyWorkerId=202;MoveWorkerId=101;MoveInvocations=0;Verified=311;Reconciled=311;Indexed=311;Deferred=1;DeferredRecorded=1;Unprocessed=188;Planned=500}}
        }
        $r.ArchiveWorkers | Should -Be 0
        $r.ResumeWorkers | Should -Be 1
        $r.Verified | Should -Be 311
        $r.Unprocessed | Should -Be 188
        $r.Status | Should -BeExactly RecoveredPendingBatch
    }
}


Describe 'ARCH8a1 completed long recovery deferred proof readback' {
    BeforeEach {
        $script:aProofDir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:aProofDir)
        $script:aProofId='20261126-174835-acf7a0bb'
        $plan=@(1..500 | ForEach-Object {[pscustomobject]@{EntryId=('id'+$_);SourceFolderPath='\\fake\Inbox';Subject='synthetic';Sender='fixture';ArchiveDate='2020-01-01';Size=1}})
        $script:aProofTx=[pscustomobject]@{Path=(Join-Path $script:aProofDir ($script:aProofId+'.json'));TransactionId=$script:aProofId;State=[pscustomobject]@{SourcePst=$script:aPst;Limit=500;PlannedItems=$plan;Status='Completed';Executed=500;Verified=500;Skipped=0;SkippedEntryIds=@();SkippedItems=@()}}
        $rows=@($plan | ForEach-Object {[pscustomobject]@{SourceEntryId=$_.EntryId}})
        $script:aProofState=[pscustomobject]@{Planned=500;Returned=500;Claimed=500;Reconciled=500;OperationEventCount=1000;AwaitingRestart=$true;Rows=$rows}
        $script:aProofSteps=@([pscustomobject]@{Step='ARCH4 Batch Started'},[pscustomobject]@{Step='Candidates'})
        $script:aProofSteps+=@(foreach($item in $plan){
            [pscustomobject]@{Step='Move Started';EntryId=$item.EntryId}
            [pscustomobject]@{Step='ARCH4 Move Returned';EntryId=$item.EntryId}
        })
        $script:aProofSteps+=@([pscustomobject]@{Step='ARCH4 Awaiting Restart'},[pscustomobject]@{Step='ARCH4 Batch Verified'},[pscustomobject]@{Step='ARCH7c Recovery Verified';Message='Verified=500; Deferred=0; Unprocessed=0; MoveInvocations=0'})
        Mock Get-OPAARCH4ReturnedFromDisk {$script:aProofState}
        Mock Read-OPAARCH4StepRecords {$script:aProofSteps}
        Mock Get-OPAArchiveTransaction {$script:aProofTx}
        Mock Get-OPAARCH6HistoricalThreatIds {}
    }
    It 'revalidates the exact 500 returned and reconciled case through real Save-OPAARCH6DeferredEvidence twice' {
        (Save-OPAARCH6DeferredEvidence -Transaction $script:aProofTx -SourceStoreId 'fake' -ProfileName Outlook) | Should -Be 0
        (Save-OPAARCH6DeferredEvidence -Transaction $script:aProofTx -SourceStoreId 'fake' -ProfileName Outlook) | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:aProofDir -File).Count | Should -Be 0
    }
    It 'saves and reads back a real deferred ledger for a completed long mixed batch without widening writer consent' {
        $script:aProofState.Returned=499
        $script:aProofState.Claimed=499
        $script:aProofState.Reconciled=499
        $script:aProofState.OperationEventCount=998
        $script:aProofState.Rows=@($script:aProofState.Rows | Select-Object -First 499)
        $script:aProofTx.State.Executed=499
        $script:aProofTx.State.Verified=499
        $script:aProofTx.State.Skipped=1
        $script:aProofTx.State.SkippedEntryIds=@('id500')
        $script:aProofSteps=@($script:aProofSteps | Select-Object -First 1000)+@(
            [pscustomobject]@{Step='Skipped';EntryId='id500';SourceFolderPath='\\fake\Inbox';Message='ARCH6f3a deferred AttachmentTypeUnsupported: ARCH5 AttachmentTypeUnsupported: index=1 type=5 bytes=1';Time='2026-11-26T17:48:00'}
            [pscustomobject]@{Step='ARCH4 Awaiting Restart'}
            [pscustomobject]@{Step='ARCH4 Batch Verified'}
            [pscustomobject]@{Step='ARCH7c Recovery Verified';Message='Verified=499; Deferred=1; Unprocessed=0; MoveInvocations=0'}
        )
        (Save-OPAARCH6DeferredEvidence -Transaction $script:aProofTx -SourceStoreId 'fake' -ProfileName Outlook) | Should -Be 1
        (Save-OPAARCH6DeferredEvidence -Transaction $script:aProofTx -SourceStoreId 'fake' -ProfileName Outlook) | Should -Be 1
        @(Get-OPAARCH6DeferredIds -SourcePst $script:aPst -SourceStoreId 'fake' -ProfileName Outlook -Directory $script:aProofDir) | Should -Be 'id500'
    }
    It 'rejects a completed proof outside the hard 500-item scope' {
        $script:aProofTx.State.Limit=501
        {Save-OPAARCH6DeferredEvidence -Transaction $script:aProofTx -SourceStoreId 'fake' -ProfileName Outlook} | Should -Throw '*invalid bounded checkpoint*'
        @(Get-ChildItem -LiteralPath $script:aProofDir -File).Count | Should -Be 0
    }
    It 'rejects corrupt recovery markers and incomplete reconciliation before writing evidence' {
        $script:aProofSteps[-1].Message='Verified=499; Deferred=0; Unprocessed=0; MoveInvocations=0'
        {Save-OPAARCH6DeferredEvidence -Transaction $script:aProofTx -SourceStoreId 'fake' -ProfileName Outlook} | Should -Throw '*recovery marker mismatch*'
        $script:aProofSteps[-1].Message='Verified=500; Deferred=0; Unprocessed=0; MoveInvocations=0'
        $script:aProofState.Reconciled=499
        $script:aProofState.OperationEventCount=999
        {Save-OPAARCH6DeferredEvidence -Transaction $script:aProofTx -SourceStoreId 'fake' -ProfileName Outlook} | Should -Throw '*inconsistent completed checkpoint*'
        @(Get-ChildItem -LiteralPath $script:aProofDir -File).Count | Should -Be 0
    }
}


Describe 'ARCH8a2 failure diagnostics preserve verification gate' {
    It 'reports gate failure with missing and warning IDs without a journal/index commit' {
        Mock Write-Host {}
        $v=[pscustomobject]@{Verified=$false;EntryIdsVerified=$false;SemanticWitnessRequired=$true;AllRequiredOriginalSemanticWitnessesPresent=$true;ExpectedMoved=499;ExpectedEntryIdsChecked=499;MissingEntryIds=@('ARCHIVE_ITEM_NOT_VERIFIED:id123');WarningEntryIds=@('STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT:id456')}
        $tx=[pscustomobject]@{TransactionId='synthetic'}
        {Complete-OPAARCH4VerifiedBatch -Transaction $tx -State ([pscustomobject]@{Returned=499}) -Verification $v -SourceStoreId 'fake'} | Should -Throw '*independent full verification failed*'
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {$Object -like 'ARCH8a2 VERIFICATION_FAILURE*' -and $Object -like '*ARCHIVE_ITEM_NOT_VERIFIED:id123*' -and $Object -like '*STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT:id456*'}
    }
    It 'reports direct semantic mismatch issue codes without returning diagnostic objects' {
        Mock Test-OPA265ARCH2bWitnessSchema {$true}
        Mock Get-OPA265ARCH2bMailSemanticWitness { [pscustomobject]@{Schema='synthetic'} }
        Mock Compare-OPA265ARCH2bMailSemanticWitness { [pscustomobject]@{CriticalContentMatches=$false;IssueCodes=@('DifferentUnRead','Attachment1DifferentPayloadSha256')} }
        Mock Write-Host {}
        $item=[pscustomobject]@{Class=43;Subject='synthetic'}
        $expected=[pscustomobject]@{Subject='synthetic';Sender='';InternetMessageId='';SourceEntryId='id1';ArchiveEntryId='id2';SourceSemanticWitness=[pscustomobject]@{Schema='synthetic'}}
        $r=@(Test-OPAArchiveItemFingerprint -Item $item -Expected $expected -ReportDirectFailure)
        $r.Count | Should -Be 1
        $r[0] | Should -BeFalse
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {$Object -like '*FINGERPRINT_FAILURE*' -and $Object -like '*DifferentUnRead*' -and $Object -like '*Attachment1DifferentPayloadSha256*'}
        Test-OPAArchiveItemFingerprint -Item $item -Expected $expected | Should -BeFalse
        Should -Invoke Write-Host -Times 1 -Exactly
    }
}


Describe 'ARCH8b explicit group Auto contract' {
    It 'permits group-scoped WhatIf without a fixed source, retaining 500/unlimited and quiet defaults' {
        $r=& $script:aMain -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -RdsArchiveGroupSid 'S-1-5-21-111-222-333-2001' -Quiet -WhatIf
        $r.Status | Should -BeExactly NoOutlookOrPersistentWrites
        $r.RdsGroupScope | Should -BeTrue
        $r.BatchSize | Should -Be 500
        $r.MaxBatchesPerSource | Should -Be 0
        $r.PinnedSourcePst | Should -BeNullOrEmpty
        $r.ProductionReady | Should -BeFalse
    }
    It 'rejects group scope without long Quiet consent, or combined with a pinned PST' {
        $sid='S-1-5-21-111-222-333-2001'
        {& $script:aMain -Mode Auto -ConfirmDevAutoArchive -RdsArchiveGroupSid $sid -Quiet -WhatIf} | Should -Throw '*group scope*'
        {& $script:aMain -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -RdsArchiveGroupSid $sid -WhatIf} | Should -Throw '*group scope*'
        {& $script:aMain -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -RdsArchiveGroupSid $sid -LongArchiveSourcePst $script:aPst -Quiet -WhatIf} | Should -Throw '*group scope*'
        {& $script:aMain -Mode Analyze -RdsArchiveGroupSid $sid -WhatIf} | Should -Throw '*group scope*'
    }
    It 'exhausts two independent discovered POP3 sources in unlimited sequence without a fixed path' {
        $script:aCalls=0
        $row2=[pscustomobject]@{SourcePst='C:\Test\Second.pst';Directory='fake'}
        $r=Invoke-OPAARCH7eSourceSequence -Sources @($script:aRow,$row2) -MaxBatchesPerSource 0 -ConfirmDevLongArchive -PendingOwner {} -RunSource {
            $script:aCalls++
            if($script:aCalls -in @(1,3)){New-ARCH8aBatch -Verified 499 -Deferred 1}else{New-ARCH8aBatch -Status NoEligibleMessages -Verified 0}
        }
        $r.Status | Should -BeExactly AllSourcesExhausted
        $r.SourcesExhausted | Should -Be 2
        $r.Verified | Should -Be 998
        $r.Deferred | Should -Be 2
    }
}
