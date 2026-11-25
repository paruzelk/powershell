#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Version.ps1')
    . (Join-Path $script:root 'Core/Runtime/JsonSupport.ps1')
    . (Join-Path $script:root 'Core/Runtime/ComManager.ps1')
    . (Join-Path $script:root 'Core/Archive/SystemFolders.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveSelector.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveGrouping.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveTransaction.ps1')
    . (Join-Path $script:root 'Core/Archive/DuplicateIndex.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH2bSemanticWitness.ps1')
    . (Join-Path $script:root 'Core/Archive/MailMover.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveVerifier.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH4Batch.ps1')
    $script:sourceFolder='\\Fake POP3\Inbox'
    $script:targetFolder='\\Fake Archive\2020\Inbox'
    function New-ARCH4Fixture {
        param([int]$Count=3,[int]$Returned=$Count)
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        $source=Join-Path $dir 'fake.pst';$archive=Join-Path $dir 'fake.Archive-2020.pst'
        $tx=New-OPAArchiveTransaction -SourcePst $source -ArchivePst '' -Limit $Count -ArchiveGrouping Year -AccountEmail 'fake@invalid' -DurabilityMode Safe
        $plan=New-Object 'System.Collections.Generic.List[object]'
        $steps=New-Object 'System.Collections.Generic.List[object]'
        $events=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le $Count;$i++){
            $id='S'+$i
            $p=[pscustomobject]@{EntryId=$id;Subject='Fake';Sender='';InternetMessageId='';Size=100;SourceFolderPath=$script:sourceFolder;ReceivedTime='2020-01-01T00:00:00'}
            [void]$plan.Add($p)
            if($i -gt $Returned){continue}
            [void]$steps.Add([pscustomobject]@{Step='Move Started';EntryId=$id;SourceFolderPath=$script:sourceFolder;TargetFolderPath=$script:targetFolder;ArchivePst=$archive;ReceivedTime=$p.ReceivedTime;SourceSemanticWitness=[pscustomobject]@{Synthetic=$true}})
            [void]$steps.Add([pscustomobject]@{Step='ARCH4 Move Returned';EntryId=$id;ArchiveEntryId=('A'+$i);SourceFolderPath=$script:sourceFolder;TargetFolderPath=$script:targetFolder;ArchivePst=$archive;ReceivedTime=$p.ReceivedTime})
            [void]$events.Add([pscustomobject]@{Sequence=$i;TransactionId=$tx.TransactionId;OperationKind='MailMove';OperationId=$id;Phase='Intent';SourceEntryId=$id;SourceStoreId='STORE';SourceFolderPath=$script:sourceFolder;TargetFolderPath=$script:targetFolder;ArchivePst=$archive})
        }
        $tx.State.PlannedItems=@($plan.ToArray());$tx.State.Planned=$Count
        return [pscustomobject]@{Transaction=$tx;Steps=@($steps.ToArray());Events=@($events.ToArray());Archive=$archive}
    }
    function Save-ARCH4Fixture {
        param([object]$Fixture,[switch]$Interrupted)
        $tx=$Fixture.Transaction
        if($Interrupted){Save-OPAArchiveTransaction -Transaction $tx -Status Running -Step 'ARCH4 Batch Started' -WriteCheckpoint}
        $prior=0
        Save-OPAArchiveTransaction -Transaction $tx -Status Planned -Step Candidates -WriteCheckpoint
        foreach($s in $Fixture.Steps){
            $params=@{Transaction=$tx;Status='Running';Step=$s.Step;EntryId=$s.EntryId;SourceFolderPath=$s.SourceFolderPath;TargetFolderPath=$s.TargetFolderPath;ArchivePst=$s.ArchivePst;ReceivedTime=[datetime]$s.ReceivedTime}
            if($s.Step -eq 'Move Started'){
                $params.SemanticWitness=$s.SourceSemanticWitness
                if($Interrupted){$tx.State.Executed=$prior;$params.WriteCheckpoint=$true;$prior++}
            }else{$params.ArchiveEntryId=$s.ArchiveEntryId}
            Save-OPAArchiveTransaction @params
        }
        foreach($e in $Fixture.Events){
            [void](Write-OPAOperationJournalEvent -Path (Get-OPAARCH4OperationPath -Transaction $tx) -TransactionId $tx.TransactionId -OperationId $e.OperationId -Sequence $e.Sequence -Phase Intent -SourceEntryId $e.SourceEntryId -SourceStoreId $e.SourceStoreId -SourceFolderPath $e.SourceFolderPath -TargetFolderPath $e.TargetFolderPath -ArchivePst $e.ArchivePst)
        }
        Sync-OPAStepJournalStreams
        if(-not $Interrupted){Save-OPAArchiveTransaction -Transaction $tx -Status Running -Step 'ARCH4 Awaiting Restart' -WriteCheckpoint}
    }
    function New-ARCH4Verification {
        param([int]$Count)
        return [pscustomobject]@{Verified=$true;EntryIdsVerified=$true;SemanticWitnessRequired=$true;AllRequiredOriginalSemanticWitnessesPresent=$true;ExpectedMoved=$Count;ExpectedEntryIdsChecked=$Count;MissingEntryIds=@();WarningEntryIds=@()}
    }
}
Describe 'ARCH4 controlled original batch development integration' {
BeforeEach {
    $global:OPADurabilityMode='Safe'
    Mock Test-OPA265ARCH2bWitnessSchema {$true}
}
AfterEach {
    Close-OPADuplicateJournalStreams
    Close-OPAStepJournalStreams
}
Describe 'ARCH4 general batch receipt/reconciliation contract' {
    It 'accepts 100 durable returned messages, no historical GUID or physical size' {
        $f=New-ARCH4Fixture -Count 100
        $s=Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $f.Steps -Events $f.Events -SourceStoreId STORE
        $s.Returned | Should -Be 100
        $s.Reconciled | Should -Be 0
    }
    It 'accepts 500 durable returned messages without a fixed total Inbox count' {
        $f=New-ARCH4Fixture -Count 500
        $s=Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $f.Steps -Events $f.Events -SourceStoreId STORE
        $s.Rows.Count | Should -Be 500
    }
    It 'allows safe non-attempted items and preserves the planned batch size' {
        $f=New-ARCH4Fixture -Count 100 -Returned 98
        $s=Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $f.Steps -Events $f.Events -SourceStoreId STORE
        $s.Planned | Should -Be 100
        $s.Returned | Should -Be 98
    }
    It 'rejects missing provider return after durable claim' {
        $f=New-ARCH4Fixture
        {Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps @($f.Steps | Select-Object -First 5) -Events $f.Events -SourceStoreId STORE} | Should -Throw
    }
    It 'rejects duplicate claim before any reconciliation' {
        $f=New-ARCH4Fixture
        {Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps ($f.Steps+@($f.Steps[0])) -Events $f.Events -SourceStoreId STORE} | Should -Throw
    }
    It 'rejects missing operation Intent even with three returned receipts' {
        $f=New-ARCH4Fixture
        {Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $f.Steps -Events @($f.Events | Select-Object -First 2) -SourceStoreId STORE} | Should -Throw
    }
    It 'rejects changed archive folder between claim and return' {
        $f=New-ARCH4Fixture
        $f.Steps[1].TargetFolderPath='wrong'
        {Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $f.Steps -Events $f.Events -SourceStoreId STORE} | Should -Throw
    }
    It 'rejects duplicate archive EntryID' {
        $f=New-ARCH4Fixture
        $f.Steps[3].ArchiveEntryId=$f.Steps[1].ArchiveEntryId
        {Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $f.Steps -Events $f.Events -SourceStoreId STORE} | Should -Throw
    }
    It 'rejects explicit indeterminate Move even when other receipts exist' {
        $f=New-ARCH4Fixture
        {Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps ($f.Steps+@([pscustomobject]@{Step='Move Indeterminate';EntryId='S3'})) -Events $f.Events -SourceStoreId STORE} | Should -Throw
    }
    It 'does not accept a torn step journal' {
        $p=Join-Path $TestDrive 'torn.jsonl'
        [IO.File]::WriteAllText($p,'{"Step":"Move Started"}')
        {Read-OPAARCH4StepRecords -Path $p} | Should -Throw
    }
    It 'does not overwrite an existing pending batch marker' {
        $p=Join-Path $TestDrive 'existing.pending'
        Write-OPAARCH4Pending -Path $p -Record @{TransactionId='one'}
        {Write-OPAARCH4Pending -Path $p -Record @{TransactionId='two'}} | Should -Throw
        (ConvertFrom-Json ([IO.File]::ReadAllText($p))).TransactionId | Should -BeExactly 'one'
    }
    It 'fails before any Reconciled or index append when original verifier fails' {
        $f=New-ARCH4Fixture
        $s=Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $f.Steps -Events $f.Events -SourceStoreId STORE
        $v=New-ARCH4Verification -Count 3
        $v.Verified=$false
        Mock Write-OPAOperationJournalEvent {throw 'unexpected write'}
        Mock Add-OPADuplicateEntry {throw 'unexpected write'}
        {Complete-OPAARCH4VerifiedBatch -Transaction $f.Transaction -State $s -Verification $v -SourceStoreId STORE} | Should -Throw
        Should -Invoke Write-OPAOperationJournalEvent -Exactly -Times 0
        Should -Invoke Add-OPADuplicateEntry -Exactly -Times 0
    }
    It 'rejects a stale archived EntryID warning rather than indexing the wrong ID' {
        $f=New-ARCH4Fixture
        $s=Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $f.Steps -Events $f.Events -SourceStoreId STORE
        $v=New-ARCH4Verification -Count 3
        $v.WarningEntryIds=@('STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT:S1')
        {Complete-OPAARCH4VerifiedBatch -Transaction $f.Transaction -State $s -Verification $v -SourceStoreId STORE} | Should -Throw
    }
    It 'writes and reads original Reconciled and DuplicateIndex only after full verifier success, idempotently' {
        $f=New-ARCH4Fixture
        Save-ARCH4Fixture -Fixture $f
        $s=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $s.Reconciled | Should -Be 0
        $v=New-ARCH4Verification -Count 3
        $result=Complete-OPAARCH4VerifiedBatch -Transaction $f.Transaction -State $s -Verification $v -SourceStoreId STORE
        $result.Indexed | Should -Be 3
        $result.Reconciled | Should -Be 3
        $s2=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $s2.Reconciled | Should -Be 3
        $hash=(Get-FileHash -LiteralPath (Get-OPADuplicateIndexJournalPath -ArchivePst $f.Archive)).Hash
        $r2=Complete-OPAARCH4VerifiedBatch -Transaction $f.Transaction -State $s2 -Verification $v -SourceStoreId STORE
        $r2.Indexed | Should -Be 3
        (Get-FileHash -LiteralPath (Get-OPADuplicateIndexJournalPath -ArchivePst $f.Archive)).Hash | Should -BeExactly $hash
    }
    It 'recovers a partially committed journal and index without repeating provider Move' {
        $f=New-ARCH4Fixture
        Save-ARCH4Fixture -Fixture $f
        $tx=$f.Transaction;$r=$f.Events[0]
        [void](Write-OPAOperationJournalEvent -Path (Get-OPAARCH4OperationPath -Transaction $tx) -TransactionId $tx.TransactionId -OperationId S1 -Sequence 4 -Phase Reconciled -SourceEntryId S1 -ArchiveEntryId A1 -ArchivePst $f.Archive -SourceStoreId STORE -SourceFolderPath $r.SourceFolderPath -TargetFolderPath $r.TargetFolderPath)
        $idx=Import-OPADuplicateIndex -ArchivePst $f.Archive
        Add-OPADuplicateEntry -Index $idx -SourceEntryId S1 -ArchiveEntryId A1 -ArchivePst $f.Archive -SourcePst $tx.State.SourcePst -SourceFolderPath $r.SourceFolderPath -TargetFolderPath $r.TargetFolderPath -TransactionId $tx.TransactionId
        Close-OPADuplicateJournalStreams
        $s=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        $s.Reconciled | Should -Be 1
        $result=Complete-OPAARCH4VerifiedBatch -Transaction $tx -State $s -Verification (New-ARCH4Verification -Count 3) -SourceStoreId STORE
        $result.Reconciled | Should -Be 3
        (Import-OPADuplicateIndex -ArchivePst $f.Archive).Entries.Count | Should -Be 3
    }
    It 'blocks conflicting existing shared index mapping before journal mutation' {
        $f=New-ARCH4Fixture
        Save-ARCH4Fixture -Fixture $f
        $idx=Import-OPADuplicateIndex -ArchivePst $f.Archive
        Add-OPADuplicateEntry -Index $idx -SourceEntryId S1 -ArchiveEntryId WRONG -ArchivePst $f.Archive -TransactionId other
        Close-OPADuplicateJournalStreams
        $s=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        {Complete-OPAARCH4VerifiedBatch -Transaction $f.Transaction -State $s -Verification (New-ARCH4Verification -Count 3) -SourceStoreId STORE} | Should -Throw
        (Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE).Reconciled | Should -Be 0
    }
}
Describe 'ARCH4 original MailMover integration without real Outlook' {
    It 'moves only selected batch, skips unavailable source and leaves index untouched until restart verification' {
        $f=New-ARCH4Fixture -Count 3
        $tx=$f.Transaction
        $script:fakeFolder=[pscustomobject]@{Name='Inbox';FolderPath=$script:sourceFolder;StoreID='STORE';EntryID='F1'}
        $script:fakeDest=[pscustomobject]@{Store=[pscustomobject]@{StoreID='ARCHIVE'};Folder=[pscustomobject]@{FolderPath=$script:targetFolder;StoreID='ARCHIVE'};Path=$f.Archive}
        $script:fakeCandidates=@(1..4 | ForEach-Object {
            [pscustomobject]@{EntryID=('S'+$_);ArchiveDate=[datetime]'2020-01-01';ReceivedTime=[datetime]'2020-01-01';SourceFolderPath=$script:sourceFolder;FolderName='Inbox';Subject='Fake';Sender='';InternetMessageId='';Size=100}
        })
        Mock Get-OPAArchiveCandidates {return $script:fakeCandidates}
        Mock Get-OPAArchivePstPartsOnDiskAll {return @()}
        Mock Get-OPAItemByEntryIdFromSourceFolder {
            if($EntryId -eq 'S2'){throw 'Unavailable before claim'}
            $item=[pscustomobject]@{EntryID=$EntryId;Class=43;Size=100}
            $item | Add-Member -MemberType ScriptMethod -Name Move -Value {param($Folder) return [pscustomobject]@{EntryID=('A'+$this.EntryID)}}
            return $item
        }
        Mock Assert-OPAARCH4Candidate {}
        Mock Assert-OPAARCH4Destination {}
        Mock Get-OPAArchiveDestination {return $script:fakeDest}
        Mock Get-OPA265ARCH2bMailSemanticWitness {return [pscustomobject]@{Synthetic=$true}}
        Mock Get-OPAArchivePstSizeBytes {return 1000}
        Mock Update-OPAArchivePstTelemetry {}
        Mock Add-OPADuplicateEntry {throw 'index must not be written before restart'}
        $n=Move-OPAItemsWithLimit -Namespace ([pscustomobject]@{Fake=$true}) -SourceFolders @($script:fakeFolder) -Transaction $tx -Limit 3 -ArchiveGrouping Year -ARCH4Batch
        $n | Should -Be 2
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        $state.Rows.Count | Should -Be 2
        $state.Rows.SourceEntryId | Should -Not -Contain S4
        $state.Reconciled | Should -Be 0
        Should -Invoke Add-OPADuplicateEntry -Exactly -Times 0
    }
}

Describe 'ARCH4 main command safety before discovery' {
    It 'main Archive WhatIf returns without source PST or Outlook changes' {
        $source=Join-Path $TestDrive 'not-created.pst'
        $r=& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -ProfileName Outlook -SourcePst $source -ConfirmTestArchive -Limit 100 -WhatIf
        $r.Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        Test-Path -LiteralPath $source | Should -BeFalse
    }
    It 'requires explicit test consent for the selected PST' {
        $source=Join-Path $TestDrive 'not-created.pst'
        {& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -ProfileName Outlook -SourcePst $source -Limit 100 -WhatIf} | Should -Throw
    }
    It 'does not allow an unbounded controlled test batch' {
        {& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -ProfileName Outlook -SourcePst (Join-Path $TestDrive 'test.pst') -ConfirmTestArchive -Limit 501 -WhatIf} | Should -Throw
    }
}

Describe 'ARCH5a zero-Move terminal completion' {
    It 'closes a real durable zero-claim transaction without writing a duplicate entry or operation event' {
        $f=New-ARCH4Fixture -Count 1 -Returned 0
        Save-ARCH4Fixture -Fixture $f
        $s=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $s.AwaitingRestart | Should -BeTrue
        Mock Add-OPADuplicateEntry {throw 'must never write index for zero returns'}
        Mock Write-OPAOperationJournalEvent {throw 'must never append reconciliation without Move'}
        $r=Complete-OPAARCH5aZeroMoveBatch -Transaction $f.Transaction -State $s -SourceStoreId STORE
        $r.Status | Should -BeExactly 'BatchCompletedNoMoves'
        $r.Verified | Should -Be 0
        $r.Indexed | Should -Be 0
        $r.RestartRequired | Should -BeFalse
        $f.Transaction.State.Status | Should -BeExactly 'Completed'
        Should -Invoke Add-OPADuplicateEntry -Exactly -Times 0
        Should -Invoke Write-OPAOperationJournalEvent -Exactly -Times 0
    }
    It 'refuses zero-return completion before durable selection termination' {
        $f=New-ARCH4Fixture -Count 1 -Returned 0
        $s=Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps @() -Events @() -SourceStoreId STORE
        {Complete-OPAARCH5aZeroMoveBatch -Transaction $f.Transaction -State $s -SourceStoreId STORE} | Should -Throw '*durable finished selection*'
    }
    It 'refuses zero-Move completion when a claim exists' {
        $f=New-ARCH4Fixture -Count 1 -Returned 1
        {Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps @($f.Steps[0]) -Events $f.Events -SourceStoreId STORE} | Should -Throw '*unresolved claim*'
    }
}

Describe 'ARCH6f3c1 interrupted recovery with exact skip-free journal prefix' {
    It 'accepts 311 paired receipts of 500 while checkpoint lags by one' {
        $f=New-ARCH4Fixture -Count 500 -Returned 311
        $f.Transaction.State.Status='Running';$f.Transaction.State.Executed=310
        $steps=@([pscustomobject]@{Step='ARCH4 Batch Started'},[pscustomobject]@{Step='Candidates'})+@($f.Steps)
        $state=Get-OPAARCH4ReturnedState -Transaction $f.Transaction -Steps $steps -Events $f.Events -SourceStoreId STORE
        $r=Assert-OPAARCH6InterruptedState -Transaction $f.Transaction -State $state -Steps $steps -ExpectedPlanned 500 -ExpectedReturned 311
        $r.Unprocessed | Should -Be 189
        $r.RecoveryMarkerPresent | Should -BeFalse
    }
    It 'rejects a different expected receipt count' {
        $f=New-ARCH4Fixture -Count 3 -Returned 2
        Save-ARCH4Fixture -Fixture $f -Interrupted
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $f.Transaction))
        {Assert-OPAARCH6InterruptedState -Transaction $f.Transaction -State $state -Steps $steps -ExpectedPlanned 3 -ExpectedReturned 1} | Should -Throw '*counts or termination*'
    }
    It 'rejects previous skips and unknown suffix instead of classifying the unprocessed tail as deferred' {
        $f=New-ARCH4Fixture -Count 3 -Returned 2
        Save-ARCH4Fixture -Fixture $f -Interrupted
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $f.Transaction))
        $f.Transaction.State.Skipped=1
        {Assert-OPAARCH6InterruptedState -Transaction $f.Transaction -State $state -Steps $steps -ExpectedPlanned 3 -ExpectedReturned 2} | Should -Throw '*skip-free*'
        $f.Transaction.State.Skipped=0
        {Assert-OPAARCH6InterruptedState -Transaction $f.Transaction -State $state -Steps ($steps+@([pscustomobject]@{Step='Skipped'})) -ExpectedPlanned 3 -ExpectedReturned 2} | Should -Throw '*suffix*'
    }
    It 'rejects a returned set that is not the ordered prefix of the original plan' {
        $f=New-ARCH4Fixture -Count 3 -Returned 2
        Save-ARCH4Fixture -Fixture $f -Interrupted
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $f.Transaction))
        $plan=@($f.Transaction.State.PlannedItems)
        $f.Transaction.State.PlannedItems=@($plan[1],$plan[0],$plan[2])
        {Assert-OPAARCH6InterruptedState -Transaction $f.Transaction -State $state -Steps $steps -ExpectedPlanned 3 -ExpectedReturned 2} | Should -Throw '*exact planned prefix*'
    }
    It 'rejects a normally terminated partial selection in interrupted mode' {
        $f=New-ARCH4Fixture -Count 3 -Returned 2
        Save-ARCH4Fixture -Fixture $f
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $f.Transaction))
        {Assert-OPAARCH6InterruptedState -Transaction $f.Transaction -State $state -Steps $steps -ExpectedPlanned 3 -ExpectedReturned 2} | Should -Throw '*counts or termination*'
    }
    It 'commits only the returned prefix after full verification and reads back idempotently' {
        $f=New-ARCH4Fixture -Count 3 -Returned 2
        Save-ARCH4Fixture -Fixture $f -Interrupted
        $tx=Get-OPAArchiveTransaction -SourcePst $f.Transaction.State.SourcePst -TransactionId $f.Transaction.TransactionId
        $tx.State.Executed | Should -Be 1
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        Mock Move-OPAItemsWithLimit {throw 'never move on recovery'}
        $r=Complete-OPAARCH6InterruptedBatch -Transaction $tx -State $state -Verification (New-ARCH4Verification -Count 2) -SourceStoreId STORE -ExpectedPlanned 3 -ExpectedReturned 2
        $r.Status | Should -BeExactly 'InterruptedBatchRecovered'
        $r.Verified | Should -Be 2
        $r.Indexed | Should -Be 2
        $r.Unprocessed | Should -Be 1
        $r.Deferred | Should -Be 0
        $r.MoveInvocations | Should -Be 0
        $indexPath=Get-OPADuplicateIndexJournalPath -ArchivePst $f.Archive
        $hash=(Get-FileHash -LiteralPath $indexPath).Hash
        $s2=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        $r2=Complete-OPAARCH6InterruptedBatch -Transaction $tx -State $s2 -Verification (New-ARCH4Verification -Count 2) -SourceStoreId STORE -ExpectedPlanned 3 -ExpectedReturned 2
        $r2.Reconciled | Should -Be 2
        (Get-FileHash -LiteralPath $indexPath).Hash | Should -BeExactly $hash
        $idx=Import-OPADuplicateIndex -ArchivePst $f.Archive
        $idx.Entries.Count | Should -Be 2
        Test-OPADuplicateEntry -Index $idx -SourceEntryId S3 | Should -BeNullOrEmpty
        @((Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $tx)) | Where-Object {$_.Step -ceq 'ARCH6f3c1 Interrupted Batch Verified'}).Count | Should -Be 1
        Should -Invoke Move-OPAItemsWithLimit -Exactly -Times 0
    }
    It 'keeps journal and index unchanged if independent verifier fails' {
        $f=New-ARCH4Fixture -Count 3 -Returned 2
        Save-ARCH4Fixture -Fixture $f -Interrupted
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $v=New-ARCH4Verification -Count 2
        $v.Verified=$false
        Mock Write-OPAOperationJournalEvent {throw 'unexpected append'}
        Mock Add-OPADuplicateEntry {throw 'unexpected index append'}
        {Complete-OPAARCH6InterruptedBatch -Transaction $f.Transaction -State $state -Verification $v -SourceStoreId STORE -ExpectedPlanned 3 -ExpectedReturned 2} | Should -Throw '*verification failed*'
        Should -Invoke Write-OPAOperationJournalEvent -Exactly -Times 0
        Should -Invoke Add-OPADuplicateEntry -Exactly -Times 0
    }
    It 'recovers a partially appended Reconciled prefix without reissuing Move' {
        $f=New-ARCH4Fixture -Count 3 -Returned 2
        Save-ARCH4Fixture -Fixture $f -Interrupted
        $tx=$f.Transaction;$e=$f.Events[0]
        [void](Write-OPAOperationJournalEvent -Path (Get-OPAARCH4OperationPath -Transaction $tx) -TransactionId $tx.TransactionId -OperationId S1 -Sequence 3 -Phase Reconciled -SourceEntryId S1 -ArchiveEntryId A1 -ArchivePst $f.Archive -SourceStoreId STORE -SourceFolderPath $e.SourceFolderPath -TargetFolderPath $e.TargetFolderPath)
        $s=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        $s.Reconciled | Should -Be 1
        $r=Complete-OPAARCH6InterruptedBatch -Transaction $tx -State $s -Verification (New-ARCH4Verification -Count 2) -SourceStoreId STORE -ExpectedPlanned 3 -ExpectedReturned 2
        $r.Indexed | Should -Be 2
        $r.Unprocessed | Should -Be 1
    }
    It 'requires explicit interrupted transaction and counts before Outlook or writes' {
        $src=Join-Path $TestDrive 'not-created.pst'
        $id='20261125-135508-913b789a'
        $r=& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') -SourcePst $src -ProfileName Outlook -ConfirmTestArchive -ConfirmOutlookRestart -RecoverTransaction $id -RecoverInterrupted -ExpectedInterruptedPlanned 500 -ExpectedInterruptedReturned 311 -WhatIf
        $r.Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        $r.RecoverInterrupted | Should -BeTrue
        Test-Path -LiteralPath $src | Should -BeFalse
        {& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') -SourcePst $src -ProfileName Outlook -ConfirmTestArchive -ConfirmOutlookRestart -RecoverTransaction $id -RecoverInterrupted -WhatIf} | Should -Throw '*expected planned/returned counts*'
        {& (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Mode Archive -SourcePst $src -ProfileName Outlook -ConfirmTestArchive -RecoverInterrupted -ExpectedInterruptedPlanned 500 -ExpectedInterruptedReturned 311 -WhatIf} | Should -Throw
    }
}


Describe 'ARCH6f3c2 antivirus evidence and historical hold' {
    It 'recognizes only the two explicit Windows antivirus HRESULTs through exception wrappers' {
        $a=[Runtime.InteropServices.COMException]::new('blocked',-2147024671)
        $b=[Runtime.InteropServices.COMException]::new('deleted',-2147024670)
        Get-OPAARCH6VirusHResult -Exception ([Exception]::new('wrapper',$a)) | Should -BeExactly '800700E1'
        Get-OPAARCH6VirusHResult -Exception $b | Should -BeExactly '800700E2'
        Get-OPAARCH6VirusHResult -Exception ([UnauthorizedAccessException]::new('denied')) | Should -BeNullOrEmpty
    }
    It 'defers exact antivirus HRESULT even if Defender history is unavailable' {
        Mock Get-OPAARCH6DefenderMatches {}
        $now=Get-Date
        $e=New-OPAARCH6AntivirusEvidence -EntryId '0011223344556677' -AttachmentName 'fake.doc' -Index 2 -From $now -To $now -Exception ([Runtime.InteropServices.COMException]::new('blocked',-2147024671))
        $e.Reason | Should -BeExactly 'AttachmentBlockedByAntivirus'
        $e.MoveAttempted | Should -BeFalse
        $msg=ConvertTo-OPAARCH6AntivirusMessage -Evidence $e
        Get-OPAARCH6DeferredReason -Message $msg | Should -BeExactly 'AttachmentBlockedByAntivirus'
        (ConvertFrom-OPAARCH6AntivirusMessage -Message $msg -ExpectedEntryId '0011223344556677').AttachmentIndex | Should -Be 2
        ConvertFrom-OPAARCH6AntivirusMessage -Message $msg -ExpectedEntryId '0011223344556688' | Should -BeNullOrEmpty
    }
    It 'classifies explicit virus deletion without retry' {
        Mock Get-OPAARCH6DefenderMatches {}
        $now=Get-Date
        $e=New-OPAARCH6AntivirusEvidence -EntryId '0011223344556677' -AttachmentName 'fake.doc' -Index 1 -From $now -To $now -Exception ([Runtime.InteropServices.COMException]::new('deleted',-2147024670))
        $e.Reason | Should -BeExactly 'AttachmentQuarantined'
        Get-OPAARCH6DeferredReason -Message (ConvertTo-OPAARCH6AntivirusMessage -Evidence $e) | Should -BeExactly 'AttachmentQuarantined'
    }
    It 'does not classify generic save failure or missing file without matching evidence' {
        Mock Get-OPAARCH6DefenderMatches {}
        $now=Get-Date
        New-OPAARCH6AntivirusEvidence -EntryId '0011223344556677' -AttachmentName 'fake.doc' -Index 1 -From $now -To $now -Exception ([Exception]::new('save failed')) | Should -BeNullOrEmpty
        New-OPAARCH6AntivirusEvidence -EntryId '0011223344556677' -AttachmentName 'fake.doc' -Index 1 -From $now -To $now -Exception ([IO.FileNotFoundException]::new('missing')) | Should -BeNullOrEmpty
        Get-OPAARCH6DeferredReason -Message 'ARCH5 AttachmentExportUnverified: unknown' | Should -BeNullOrEmpty
    }
    It 'accepts a unique correlated Defender event for generic save failure' {
        Mock Get-OPAARCH6DefenderMatches {[pscustomobject]@{DetectionId='9870e0c5-6cbd-4b8b-be43-3590a6c861ba';ThreatId=42;ThreatName='Synthetic';ActionSuccess=$true}}
        $now=Get-Date
        $e=New-OPAARCH6AntivirusEvidence -EntryId '0011223344556677' -AttachmentName 'fake.doc' -Index 1 -From $now -To $now -Exception ([Exception]::new('save failed'))
        $e.Defender.ThreatId | Should -Be 42
        Get-OPAARCH6DeferredReason -Message (ConvertTo-OPAARCH6AntivirusMessage -Evidence $e) | Should -BeExactly 'AttachmentBlockedByAntivirus'
    }
    It 'rejects ambiguous Defender events and forged plain marker' {
        Mock Get-OPAARCH6DefenderMatches {[pscustomobject]@{ThreatId=1};[pscustomobject]@{ThreatId=2}}
        $now=Get-Date
        New-OPAARCH6AntivirusEvidence -EntryId '0011223344556677' -AttachmentName 'fake.doc' -Index 1 -From $now -To $now -Exception ([Exception]::new('save failed')) | Should -BeNullOrEmpty
        Get-OPAARCH6DeferredReason -Message 'ARCH6f3c2 AttachmentBlockedByAntivirus: invalid' | Should -BeNullOrEmpty
    }
    It 'registers historical first unprocessed mail from metadata and reads back hold without exporting or moving' {
        $f=New-ARCH4Fixture -Count 3 -Returned 2
        $id='0011223344556677'
        $f.Transaction.State.PlannedItems[2].EntryId=$id
        Save-ARCH4Fixture -Fixture $f -Interrupted
        $tx=$f.Transaction
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        [void](Complete-OPAARCH6InterruptedBatch -Transaction $tx -State $state -Verification (New-ARCH4Verification -Count 2) -SourceStoreId STORE -ExpectedPlanned 3 -ExpectedReturned 2)
        $a=[pscustomobject]@{Type=1;FileName='fake.doc'}
        $a | Add-Member ScriptMethod SaveAsFile {throw 'must never export historical attachment'}
        $collection=[pscustomobject]@{Count=1;FakeAttachment=$a}
        $collection | Add-Member ScriptMethod Item {param($i) $this.FakeAttachment}
        $mail=[pscustomobject]@{Attachments=$collection}
        $mail | Add-Member ScriptMethod Move {throw 'must never move historical mail'}
        $ns=[pscustomobject]@{FakeMail=$mail}
        $ns | Add-Member ScriptMethod GetItemFromID {param($id,$store) $this.FakeMail}
        $folder=[pscustomobject]@{FolderPath=$script:sourceFolder}
        Mock Assert-OPAARCH4Candidate {}
        Mock Get-OPAARCH6DefenderMatches {
            [pscustomobject][ordered]@{DetectionId='9870e0c5-6cbd-4b8b-be43-3590a6c861ba';ThreatId=42;ThreatName='Synthetic';DetectionTime=$From.AddSeconds(1).ToString('o');Resource='file:_fake.doc';ProcessName='C:\OUTLOOK.EXE';ActionSuccess=$true}
        }
        $params=@{Transaction=$tx;SourceStoreId='STORE';ProfileName='Outlook';Namespace=$ns;Folders=@($folder);EntryId=$id;DetectionId='9870e0c5-6cbd-4b8b-be43-3590a6c861ba';AttachmentName='fake.doc'}
        $r=Save-OPAARCH6HistoricalThreat @params
        $r.Status | Should -BeExactly 'HistoricalThreatDeferred'
        $r.MoveInvocations | Should -Be 0
        $r.AttachmentExports | Should -Be 0
        $dir=[IO.Path]::GetDirectoryName($tx.Path)
        @(Get-OPAARCH6DeferredIds -SourcePst $tx.State.SourcePst -SourceStoreId STORE -ProfileName Outlook -Directory $dir) | Should -Contain $id
        (Save-OPAARCH6HistoricalThreat @params).Deferred | Should -Be 1
        $params.EntryId='0011223344556688'
        {Save-OPAARCH6HistoricalThreat @params} | Should -Throw '*first unprocessed identity*'
        $params.EntryId=$id;$params.AttachmentName='other.doc'
        {Save-OPAARCH6HistoricalThreat @params} | Should -Throw '*metadata not unique*'
    }
    It 'requires all historical import arguments before any Outlook access' {
        $src=Join-Path $TestDrive 'not-created.pst'
        $common=@{SourcePst=$src;ProfileName='Outlook';ConfirmTestArchive=$true;ConfirmOutlookRestart=$true;ImportDeferredTransaction='20261125-135508-913b789a';HistoricalThreatEntryId='0011223344556677';HistoricalDetectionId='9870e0c5-6cbd-4b8b-be43-3590a6c861ba';HistoricalAttachmentName='fake.doc';WhatIf=$true}
        $r=& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') @common
        $r.Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        Test-Path -LiteralPath $src | Should -BeFalse
        $common.Remove('HistoricalDetectionId')
        {& (Join-Path $script:root 'Invoke-OPAArchiveBatches.ps1') @common} | Should -Throw '*exact EntryID*'
    }
}

}
