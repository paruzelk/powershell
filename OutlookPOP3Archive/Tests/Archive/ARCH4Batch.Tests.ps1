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
    . (Join-Path $script:root 'Core/Archive/ARCH6Orchestration.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH7dSupervisor.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH7eAuto.ps1')
    # ARCH7b1: the production folder adapter lives in the main entrypoint,
    # not a dot-sourceable module. Load exactly its declaration (never execute
    # the CLI, discovery, or a real COM operation) so Pester can mock it.
    $tokens=$null;$parseErrors=$null
    $mainAst=[System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $script:root 'OutlookPOP3Archive.ps1'),[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -ne 0){throw 'ARCH7b1 main entrypoint syntax invalid.'}
    $folderAdapter=@($mainAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Get-OPAPop3SourceFolders'
    },$false))
    if($folderAdapter.Count -ne 1){throw 'ARCH7b1 exact original folder adapter definition required.'}
    . ([scriptblock]::Create($folderAdapter[0].Extent.Text))
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
            }elseif($s.Step -ceq 'Skipped'){$params.Message=$s.Message}
            else{$params.ArchiveEntryId=$s.ArchiveEntryId}
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


Describe 'ARCH6f3c3 vendor-independent attachment export failure deferral' {
    BeforeEach {
        $script:localId='0011223344556677'
        $script:localMail=[pscustomobject]@{Class=43;EntryID=$script:localId}
        $script:localAttachment=[pscustomobject]@{Type=1;FileName='fake.doc';Size=100}
        $localParams=@{Mail=$script:localMail;Attachment=$script:localAttachment;EntryId=$script:localId;AttachmentName='fake.doc';Index=1;AttachmentBytes=100;Workspace=$TestDrive;Exception=[Runtime.InteropServices.COMException]::new('generic save failed',-2147467259)}
    }
    It 'classifies a generic Outlook COM export failure without any antivirus provider lookup' {
        Mock Assert-OPAARCH6ExportWorkspaceHealthy {}
        Mock Get-OPAARCH6DefenderMatches {throw 'must not query antivirus'}
        $e=New-OPAARCH6LocalExportEvidence @localParams
        $e.Reason | Should -BeExactly 'AttachmentExportFailed'
        $e.MoveAttempted | Should -BeFalse
        $e.Defender | Should -BeNullOrEmpty
        $msg=ConvertTo-OPAARCH6LocalExportMessage -Evidence $e
        Get-OPAARCH6DeferredReason -Message $msg | Should -BeExactly 'AttachmentExportFailed'
        (ConvertFrom-OPAARCH6LocalExportMessage -Message $msg -ExpectedEntryId $script:localId).ErrorDetail | Should -BeExactly 'generic save failed'
        ConvertFrom-OPAARCH6LocalExportMessage -Message $msg -ExpectedEntryId '0011223344556688' | Should -BeNullOrEmpty
        Should -Invoke Get-OPAARCH6DefenderMatches -Exactly -Times 0
    }
    It 'classifies missing output separately without claiming a virus' {
        Mock Assert-OPAARCH6ExportWorkspaceHealthy {}
        $localParams.Exception=[Exception]::new('no output')
        $e=New-OPAARCH6LocalExportEvidence @localParams -MissingOutput
        $e.Reason | Should -BeExactly 'AttachmentPayloadUnavailable'
        Get-OPAARCH6DeferredReason -Message (ConvertTo-OPAARCH6LocalExportMessage -Evidence $e) | Should -BeExactly 'AttachmentPayloadUnavailable'
    }
    It 'never treats disk full access denied or disconnected Outlook as a local skip' {
        Mock Assert-OPAARCH6ExportWorkspaceHealthy {throw 'unexpected probe'}
        foreach($code in @(-2147024784,-2147024891,-2147417848,-2147023174)){
            $localParams.Exception=[Runtime.InteropServices.COMException]::new('system fault',[int]$code)
            New-OPAARCH6LocalExportEvidence @localParams | Should -BeNullOrEmpty
        }
        Should -Invoke Assert-OPAARCH6ExportWorkspaceHealthy -Exactly -Times 0
    }
    It 'rejects changed mail identity and changed attachment metadata' {
        Mock Assert-OPAARCH6ExportWorkspaceHealthy {throw 'unexpected probe'}
        $script:localMail.EntryID='0011223344556688'
        New-OPAARCH6LocalExportEvidence @localParams | Should -BeNullOrEmpty
        $script:localMail.EntryID=$script:localId
        $script:localAttachment.Size=101
        New-OPAARCH6LocalExportEvidence @localParams | Should -BeNullOrEmpty
        Should -Invoke Assert-OPAARCH6ExportWorkspaceHealthy -Exactly -Times 0
    }
    It 'stops when workspace write or cleanup health check fails' {
        Mock Assert-OPAARCH6ExportWorkspaceHealthy {throw 'workspace probe failed'}
        {New-OPAARCH6LocalExportEvidence @localParams} | Should -Throw '*workspace probe failed*'
    }
    It 'preserves explicit Windows virus codes without querying Defender' {
        Mock Assert-OPAARCH6ExportWorkspaceHealthy {}
        Mock Get-OPAARCH6DefenderMatches {throw 'must not query antivirus'}
        $localParams.Exception=[Runtime.InteropServices.COMException]::new('deleted',-2147024670)
        $e=New-OPAARCH6LocalExportEvidence @localParams
        $e.Reason | Should -BeExactly 'AttachmentQuarantined'
        Get-OPAARCH6DeferredReason -Message (ConvertTo-OPAARCH6LocalExportMessage -Evidence $e) | Should -BeExactly 'AttachmentQuarantined'
        Should -Invoke Get-OPAARCH6DefenderMatches -Exactly -Times 0
    }
    It 'only permits the real attachment witness missing-output deferral on explicit pre-Move opt-in' {
        $a=$script:localAttachment
        $a | Add-Member ScriptMethod SaveAsFile {param($path) }
        $collection=[pscustomobject]@{Count=1;FakeAttachment=$a}
        $collection | Add-Member ScriptMethod Item {param($i) $this.FakeAttachment}
        $mail=$script:localMail
        $mail | Add-Member NoteProperty Attachments $collection
        Mock Assert-OPAARCH6ExportWorkspaceHealthy {}
        {Get-OPA265ARCH2bAttachmentWitnesses -Mail $mail -ExtendedAttachmentWitness -TemporaryDirectory $TestDrive} | Should -Throw '*SaveAsFile did not create a file*'
        $message=''
        try{Get-OPA265ARCH2bAttachmentWitnesses -Mail $mail -ExtendedAttachmentWitness -AllowLocalExportDeferral -TemporaryDirectory $TestDrive}
        catch{$message=$_.Exception.Message}
        Get-OPAARCH6DeferredReason -Message $message | Should -BeExactly 'AttachmentPayloadUnavailable'
        @(Get-ChildItem -LiteralPath $TestDrive -Directory -Filter 'OPA-ARCH2c1-*').Count | Should -Be 0
    }
    It 'stops only after the verified batch for a high proportion of generic export failures' {
        $result=[pscustomobject]@{Planned=20;SkipReasons=@([pscustomobject]@{Reason='AttachmentExportFailed';Count=10})}
        Test-OPAARCH6ExportFailureBurst -Result $result | Should -BeTrue
        $result.Planned=500
        Test-OPAARCH6ExportFailureBurst -Result $result | Should -BeFalse
        $result.Planned=10;$result.SkipReasons[0].Count=9
        Test-OPAARCH6ExportFailureBurst -Result $result | Should -BeFalse
        $result.SkipReasons[0].Count=10;$result.SkipReasons[0].Reason='AttachmentBlockedByAntivirus'
        Test-OPAARCH6ExportFailureBurst -Result $result | Should -BeFalse
    }
}


Describe 'ARCH7b independent worker live Outlook verification fences' {
    BeforeEach {
        $livePending=[pscustomobject]@{VerificationPolicy='ARCH7bFreshWorkerSameOutlook';MoveProcessId=100;MoveProcessStartUtcTicks=1000L;MoveWorkerId=200;MoveWorkerStartUtcTicks=2000L;MoveWorkerSessionId=3}
        $liveOutlook=[pscustomobject]@{Id=100;StartUtcTicks=1000L}
        $liveWorker=[pscustomobject]@{Id=201;StartUtcTicks=3000L;SessionId=3}
        Mock Test-OPAARCH7bMoveWorkerAlive {$false}
    }
    It 'accepts fresh worker only with exactly the original Outlook identity and dead Move worker' {
        {Assert-OPAARCH7bLiveFence -Pending $livePending -Outlook $liveOutlook -Worker $liveWorker} | Should -Not -Throw
        Should -Invoke Test-OPAARCH7bMoveWorkerAlive -Exactly -Times 1
    }
    It 'rejects any different Outlook PID or start time before verification' {
        $liveOutlook.Id=101
        {Assert-OPAARCH7bLiveFence -Pending $livePending -Outlook $liveOutlook -Worker $liveWorker} | Should -Throw '*Outlook process identity changed*'
        $liveOutlook.Id=100;$liveOutlook.StartUtcTicks=1001
        {Assert-OPAARCH7bLiveFence -Pending $livePending -Outlook $liveOutlook -Worker $liveWorker} | Should -Throw '*Outlook process identity changed*'
        Should -Invoke Test-OPAARCH7bMoveWorkerAlive -Exactly -Times 0
    }
    It 'rejects same old worker, earlier worker and different Windows session' {
        $liveWorker.Id=200
        {Assert-OPAARCH7bLiveFence -Pending $livePending -Outlook $liveOutlook -Worker $liveWorker} | Should -Throw '*new PowerShell worker*'
        $liveWorker.Id=201;$liveWorker.StartUtcTicks=1999
        {Assert-OPAARCH7bLiveFence -Pending $livePending -Outlook $liveOutlook -Worker $liveWorker} | Should -Throw '*new PowerShell worker*'
        $liveWorker.StartUtcTicks=3000;$liveWorker.SessionId=4
        {Assert-OPAARCH7bLiveFence -Pending $livePending -Outlook $liveOutlook -Worker $liveWorker} | Should -Throw '*new PowerShell worker*'
    }
    It 'refuses verification if original Move worker still lives' {
        Mock Test-OPAARCH7bMoveWorkerAlive {$true}
        {Assert-OPAARCH7bLiveFence -Pending $livePending -Outlook $liveOutlook -Worker $liveWorker} | Should -Throw '*still running*'
    }
    It 'does not allow switching between legacy restart policy and live verification policy' {
        {Assert-OPAARCH7bPendingPolicy -Pending $livePending} | Should -Throw '*policy mismatch*'
        {Assert-OPAARCH7bPendingPolicy -Pending ([pscustomobject]@{MoveProcessId=100}) -ConfirmLiveOutlookVerification} | Should -Throw '*policy mismatch*'
        {Assert-OPAARCH7bPendingPolicy -Pending $livePending -ConfirmLiveOutlookVerification} | Should -Not -Throw
        $livePending.VerificationPolicy='unknown'
        {Assert-OPAARCH7bPendingPolicy -Pending $livePending -ConfirmLiveOutlookVerification} | Should -Throw '*unknown pending*'
    }
    It 'legacy restart helper refuses tagged pending before inspecting or quitting Outlook' {
        Mock Get-Process {throw 'unexpected process access'}
        Mock Get-OPAARCH6RestartApplication {throw 'unexpected Outlook access'}
        {Restart-OPAARCH6OutlookForResume -Pending $livePending} | Should -Throw '*live verification pending*'
        Should -Invoke Get-Process -Exactly -Times 0
        Should -Invoke Get-OPAARCH6RestartApplication -Exactly -Times 0
    }

    It 'validates the explicit DEV CLI without COM or persistent writes and leaves Auto closed' {
        $src=Join-Path $TestDrive 'arch7b-not-created.pst'
        $main=Join-Path $script:root 'OutlookPOP3Archive.ps1'
        $params=@{ProfileName='Outlook';SourcePst=$src;ConfirmTestArchive=$true;ConfirmLiveOutlookVerification=$true;WhatIf=$true}
        (& $main -Mode Archive @params -Limit 10).Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        (& $main -Mode Resume @params -Transaction '20261125-135508-913b789a').Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        {& $main -Mode Archive @params -Limit 11} | Should -Throw '*ARCH7b*'
        {& $main -Mode Resume @params} | Should -Throw '*ARCH7b*'
        {& $main -Mode Auto @params} | Should -Throw '*ARCH7b*'
        Test-Path -LiteralPath $src | Should -BeFalse
    }
    It 'keeps original legacy no-restart gate and attach-only no activation branch in source' {
        $main=[IO.File]::ReadAllText((Join-Path $script:root 'OutlookPOP3Archive.ps1'))
        $com=[IO.File]::ReadAllText((Join-Path $script:root 'Core/Runtime/ComManager.ps1'))
        $batch=[IO.File]::ReadAllText((Join-Path $script:root 'Core/Archive/ARCH4Batch.ps1'))
        $main | Should -Match 'New-OPAComSession -ProfileName \$ProfileName -AttachOnly'
        $com.Contains("if("+'$AttachOnly'+"){throw 'ARCH7b running Outlook is not registered in ROT") | Should -BeTrue
        $batch | Should -Match 'ARCH4 fully restart Outlook before Resume'
        $batch | Should -Not -Match '\.Quit\('
    }
    It 'commits original journal/index in the same Outlook from a fresh worker and clears pending' {
        $f=New-ARCH4Fixture -Count 3
        foreach($step in @($f.Steps | Where-Object {$_.Step -eq 'Move Started'})){$step.SourceSemanticWitness | Add-Member NoteProperty Schema 'Synthetic'}
        Save-ARCH4Fixture -Fixture $f
        $tx=$f.Transaction
        $source=[string]$tx.State.SourcePst
        [IO.File]::WriteAllBytes($source,[byte[]]@(1))
        [IO.File]::WriteAllBytes($f.Archive,[byte[]]@(1))
        $store=[pscustomobject]@{StoreID='STORE';FilePath=$source}
        $dest=[pscustomobject]@{StoreID='ARCHIVE';FilePath=$f.Archive}
        $account=[pscustomobject]@{AccountType=2;DeliveryStore=$store}
        $session=[pscustomobject]@{Attached=$true;Namespace=[pscustomobject]@{CurrentProfileName='Outlook';Accounts=@($account);Stores=@($store,$dest)}}
        $discovery=[pscustomobject]@{Profile='Outlook';Pop3Sources=@([pscustomobject]@{FilePath=$source;Protocol='POP3';StoreHandle=$store})}
        $script:liveFolder=[pscustomobject]@{StoreID='STORE';FolderPath=$script:sourceFolder}
        Mock Get-OPAPop3SourceFolders {$script:liveFolder}
        Mock Get-OPAARCH4OutlookProcess {[pscustomobject]@{Id=100;StartUtcTicks=1000L}}
        Mock Get-OPAARCH7bWorkerIdentity {[pscustomobject]@{Id=201;StartUtcTicks=3000L;SessionId=3}}
        Mock Test-OPAArchiveMoves {New-ARCH4Verification -Count 3}
        Mock Move-OPAItemsWithLimit {throw 'Resume must not call Move'}
        $pending=Join-Path ([IO.Path]::GetDirectoryName($tx.Path)) 'ARCH4.pending'
        # Explicit full fixture; read back every field before Resume.
        $livePending=[pscustomobject]@{
            Schema='2.6.5-ARCH4.Pending.1';TransactionId=[string]$tx.TransactionId
            SourcePst=[IO.Path]::GetFullPath($source);SourceStoreId='STORE';Profile='Outlook'
            MoveProcessId=100;MoveProcessStartUtcTicks=1000L;DeferredPolicy=$false
            VerificationPolicy='ARCH7bFreshWorkerSameOutlook';MoveWorkerId=200
            MoveWorkerStartUtcTicks=2000L;MoveWorkerSessionId=3
        }
        Write-OPAARCH4Pending -Path $pending -Record $livePending
        $disk=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($pending,[Text.Encoding]::UTF8))
        foreach($prop in $livePending.PSObject.Properties){
            $disk.PSObject.Properties.Name | Should -Contain $prop.Name
            $disk.($prop.Name) | Should -Be $prop.Value
        }
        $disk.TransactionId | Should -Match '^\d{8}-\d{6}-[a-f0-9]{8}$'
        $disk.SourcePst | Should -BeExactly ([IO.Path]::GetFullPath($source))
        Assert-OPAARCH7bPendingPolicy -Pending $disk -ConfirmLiveOutlookVerification
        $params=@{Mode='Resume';Session=$session;Discovery=$discovery;SourcePst=$source;TransactionId=$tx.TransactionId;ARCH5Batch=$true;ConfirmLiveOutlookVerification=$true}
        $r=Invoke-OPAARCH4Batch @params
        $r.Status | Should -BeExactly 'BatchVerifiedReconciledAndIndexed'
        $r.Verified | Should -Be 3
        $r.Indexed | Should -Be 3
        $r.MoveInvocations | Should -Be 0
        $r.OutlookProcessId | Should -Be 100
        $r.MoveWorkerId | Should -Be 200
        $r.VerifyWorkerId | Should -Be 201
        $r.PendingCleared | Should -BeTrue
        Test-Path -LiteralPath $pending | Should -BeFalse
        @(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $tx) | Where-Object {$_.Step -ceq 'ARCH7b Fresh Worker Verified'}).Count | Should -Be 1
        Should -Invoke Get-OPAPop3SourceFolders -Exactly -Times 1 -ParameterFilter {$IncludeEmptyFolders -and $IncludeRootForVerification}
        Should -Invoke Test-OPAArchiveMoves -Exactly -Times 1
        Should -Invoke Move-OPAItemsWithLimit -Exactly -Times 0
    }
    It 'fails original verifier before commit and preserves pending in live worker mode' {
        $f=New-ARCH4Fixture -Count 3
        foreach($step in @($f.Steps | Where-Object {$_.Step -eq 'Move Started'})){$step.SourceSemanticWitness | Add-Member NoteProperty Schema 'Synthetic'}
        Save-ARCH4Fixture -Fixture $f
        $tx=$f.Transaction;$source=[string]$tx.State.SourcePst
        [IO.File]::WriteAllBytes($source,[byte[]]@(1));[IO.File]::WriteAllBytes($f.Archive,[byte[]]@(1))
        $store=[pscustomobject]@{StoreID='STORE';FilePath=$source}
        $dest=[pscustomobject]@{StoreID='ARCHIVE';FilePath=$f.Archive}
        $session=[pscustomobject]@{Attached=$true;Namespace=[pscustomobject]@{CurrentProfileName='Outlook';Accounts=@([pscustomobject]@{AccountType=2;DeliveryStore=$store});Stores=@($store,$dest)}}
        $discovery=[pscustomobject]@{Profile='Outlook';Pop3Sources=@([pscustomobject]@{FilePath=$source;Protocol='POP3';StoreHandle=$store})}
        $script:liveFolder=[pscustomobject]@{StoreID='STORE';FolderPath=$script:sourceFolder}
        Mock Get-OPAPop3SourceFolders {$script:liveFolder}
        Mock Get-OPAARCH4OutlookProcess {[pscustomobject]@{Id=100;StartUtcTicks=1000L}}
        Mock Get-OPAARCH7bWorkerIdentity {[pscustomobject]@{Id=201;StartUtcTicks=3000L;SessionId=3}}
        Mock Test-OPAArchiveMoves {$v=New-ARCH4Verification -Count 3;$v.Verified=$false;$v}
        Mock Move-OPAItemsWithLimit {throw 'Resume must not call Move'}
        $pending=Join-Path ([IO.Path]::GetDirectoryName($tx.Path)) 'ARCH4.pending'
        # Explicit full fixture; read back every field before Resume.
        $livePending=[pscustomobject]@{
            Schema='2.6.5-ARCH4.Pending.1';TransactionId=[string]$tx.TransactionId
            SourcePst=[IO.Path]::GetFullPath($source);SourceStoreId='STORE';Profile='Outlook'
            MoveProcessId=100;MoveProcessStartUtcTicks=1000L;DeferredPolicy=$false
            VerificationPolicy='ARCH7bFreshWorkerSameOutlook';MoveWorkerId=200
            MoveWorkerStartUtcTicks=2000L;MoveWorkerSessionId=3
        }
        Write-OPAARCH4Pending -Path $pending -Record $livePending
        $disk=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($pending,[Text.Encoding]::UTF8))
        foreach($prop in $livePending.PSObject.Properties){
            $disk.PSObject.Properties.Name | Should -Contain $prop.Name
            $disk.($prop.Name) | Should -Be $prop.Value
        }
        $disk.TransactionId | Should -Match '^\d{8}-\d{6}-[a-f0-9]{8}$'
        $disk.SourcePst | Should -BeExactly ([IO.Path]::GetFullPath($source))
        Assert-OPAARCH7bPendingPolicy -Pending $disk -ConfirmLiveOutlookVerification
        $params=@{Mode='Resume';Session=$session;Discovery=$discovery;SourcePst=$source;TransactionId=$tx.TransactionId;ARCH5Batch=$true;ConfirmLiveOutlookVerification=$true}
        {Invoke-OPAARCH4Batch @params} | Should -Throw '*independent full verification failed*'
        Test-Path -LiteralPath $pending | Should -BeTrue
        (Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE).Reconciled | Should -Be 0
        Should -Invoke Move-OPAItemsWithLimit -Exactly -Times 0
    }
}


Describe 'ARCH7c recover proven interrupted mixed live batches' {
    BeforeAll {
        function New-ARCH7cMixedFixture {
            $f=New-ARCH4Fixture -Count 4 -Returned 2
            $plan=@($f.Transaction.State.PlannedItems)
            $f.Transaction.State.PlannedItems=@($plan[0],$plan[2],$plan[1],$plan[3])
            $skip=[pscustomobject]@{Step='Skipped';EntryId='S3';SourceFolderPath=$script:sourceFolder;ReceivedTime='2020-01-01T00:00:00';Message='ARCH6f3a deferred AttachmentTypeUnsupported: ARCH5 AttachmentTypeUnsupported: index=1 type=5 bytes=100'}
            $f.Steps=@($f.Steps[0],$f.Steps[1],$skip,$f.Steps[2],$f.Steps[3])
            foreach($step in @($f.Steps | Where-Object {$_.Step -ceq 'Move Started'})){$step.SourceSemanticWitness | Add-Member -NotePropertyName Schema -NotePropertyValue Synthetic}
            Save-ARCH4Fixture -Fixture $f -Interrupted
            return $f
        }
    }
    It 'separates verified returned, deferred and never claimed planned items' {
        $f=New-ARCH7cMixedFixture
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $f.Transaction))
        $r=Get-OPAARCH7cInterruptedReview -Transaction $f.Transaction -State $state -Steps $steps
        $r.Planned | Should -Be 4
        $r.Returned | Should -Be 2
        $r.Deferred | Should -Be 1
        $r.Unprocessed | Should -Be 1
        $r.DeferredRows[0].EntryId | Should -BeExactly S3
    }
    It 'rejects unknown or unproven skip, reordered prefix and unknown journal suffix' {
        $f=New-ARCH7cMixedFixture
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $f.Transaction))
        $skip=@($steps | Where-Object {$_.Step -ceq 'Skipped'})[0]
        $original=$skip.Message;$skip.Message='unknown error'
        {Get-OPAARCH7cInterruptedReview -Transaction $f.Transaction -State $state -Steps $steps} | Should -Throw '*unsafe skipped*'
        $skip.Message=$original;$skip.EntryId='S4'
        {Get-OPAARCH7cInterruptedReview -Transaction $f.Transaction -State $state -Steps $steps} | Should -Throw '*exact planned prefix*'
        $skip.EntryId='S3'
        {Get-OPAARCH7cInterruptedReview -Transaction $f.Transaction -State $state -Steps ($steps+@([pscustomobject]@{Step='Move Indeterminate'}))} | Should -Throw
    }
    It 'does not treat an unresolved claim or a torn journal as an unprocessed item' {
        $f=New-ARCH7cMixedFixture
        $tx=$f.Transaction
        $path=Get-OPAStepJournalPath -Transaction $tx
        # Simulate the former writer exiting before independent disk replay.
        Sync-OPAStepJournalStreams
        Close-OPAStepJournalStreams
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        $state.Returned | Should -Be 2
        $state.Reconciled | Should -Be 0
        $steps=@(Read-OPAARCH4StepRecords -Path $path)
        $steps[-1].Step | Should -BeExactly 'ARCH4 Move Returned'
        # Remove exactly the last receipt while retaining its original claim.
        {Get-OPAARCH4ReturnedState -Transaction $tx -Steps @($steps | Select-Object -SkipLast 1) -Events $f.Events -SourceStoreId STORE} | Should -Throw '*unresolved claim*'
        # Append an unterminated JSON record to the actual fixture journal.
        [IO.File]::AppendAllText($path,'{"Step":"Move Started"}',[Text.UTF8Encoding]::new($false))
        $bytes=[IO.File]::ReadAllBytes($path)
        $bytes[-1] | Should -Not -Be 10
        {Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE} | Should -Throw '*incomplete tail*'
        # Also reject complete-line malformed JSON, not just a missing newline.
        [IO.File]::AppendAllText($path,([string][char]10+'{"Step":'+[char]10),[Text.UTF8Encoding]::new($false))
        $bytes=[IO.File]::ReadAllBytes($path)
        $bytes[-1] | Should -Be 10
        {Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE} | Should -Throw
        @(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($tx.Path)) -Filter 'ARCH6-deferred-*.jsonl').Count | Should -Be 0
    }
    It 'accepts a durable plan before the first Move and leaves all items unprocessed' {
        $f=New-ARCH4Fixture -Count 3 -Returned 0
        Save-ARCH4Fixture -Fixture $f -Interrupted
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $f.Transaction -SourceStoreId STORE
        $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $f.Transaction))
        $r=Get-OPAARCH7cInterruptedReview -Transaction $f.Transaction -State $state -Steps $steps
        $r.Returned | Should -Be 0
        $r.Deferred | Should -Be 0
        $r.Unprocessed | Should -Be 3
    }
    It 'commits only verified receipts and durable skipped IDs, resumes idempotently' {
        $f=New-ARCH7cMixedFixture
        $tx=$f.Transaction
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        $v=New-ARCH4Verification -Count 2
        $r=Complete-OPAARCH7cInterruptedBatch -Transaction $tx -State $state -Verification $v -SourceStoreId STORE -ProfileName Outlook
        $r.Status | Should -BeExactly 'LiveInterruptedBatchRecovered'
        $r.Verified | Should -Be 2
        $r.Indexed | Should -Be 2
        $r.DeferredRecorded | Should -Be 1
        $r.Unprocessed | Should -Be 1
        $r.MoveInvocations | Should -Be 0
        $idx=Import-OPADuplicateIndex -ArchivePst $f.Archive
        $idx.Entries.Count | Should -Be 2
        Test-OPADuplicateEntry -Index $idx -SourceEntryId S3 | Should -BeNullOrEmpty
        Test-OPADuplicateEntry -Index $idx -SourceEntryId S4 | Should -BeNullOrEmpty
        $reopened=Get-OPAArchiveTransaction -SourcePst $tx.State.SourcePst -TransactionId $tx.TransactionId
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $reopened -SourceStoreId STORE
        $r2=Complete-OPAARCH7cInterruptedBatch -Transaction $reopened -State $state -Verification $v -SourceStoreId STORE -ProfileName Outlook
        $r2.Indexed | Should -Be 2
        $r2.DeferredRecorded | Should -Be 1
        @(Get-OPAARCH6DeferredIds -SourcePst $tx.State.SourcePst -SourceStoreId STORE -ProfileName Outlook -Directory ([IO.Path]::GetDirectoryName($tx.Path))) | Should -BeExactly S3
        @((Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $tx)) | Where-Object {$_.Step -ceq 'ARCH7c Recovery Verified'}).Count | Should -Be 1
    }
    It 'fails verifier without writing Reconciled or deferred ledger' {
        $f=New-ARCH7cMixedFixture
        $tx=$f.Transaction;$state=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE
        $v=New-ARCH4Verification -Count 2;$v.Verified=$false
        {Complete-OPAARCH7cInterruptedBatch -Transaction $tx -State $state -Verification $v -SourceStoreId STORE -ProfileName Outlook} | Should -Throw '*verification failed*'
        (Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId STORE).Reconciled | Should -Be 0
        @(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($tx.Path)) -Filter 'ARCH6-deferred-*.jsonl').Count | Should -Be 0
    }
    It 'accepts a newer naturally opened Outlook only with explicit recovery and both prior processes gone' {
        $pending=[pscustomobject]@{VerificationPolicy='ARCH7bFreshWorkerSameOutlook';MoveProcessId=100;MoveProcessStartUtcTicks=1000L;MoveWorkerId=200;MoveWorkerStartUtcTicks=2000L;MoveWorkerSessionId=3}
        $outlook=[pscustomobject]@{Id=101;StartUtcTicks=2500L}
        $worker=[pscustomobject]@{Id=201;StartUtcTicks=3000L;SessionId=4}
        Mock Test-OPAARCH7bMoveWorkerAlive {$false}
        {Assert-OPAARCH7bLiveFence -Pending $pending -Outlook $outlook -Worker $worker} | Should -Throw '*Outlook process identity changed*'
        {Assert-OPAARCH7bLiveFence -Pending $pending -Outlook $outlook -Worker $worker -AllowNaturalOutlookRestart} | Should -Not -Throw
        Mock Test-OPAARCH7bMoveWorkerAlive {$true}
        {Assert-OPAARCH7bLiveFence -Pending $pending -Outlook $outlook -Worker $worker -AllowNaturalOutlookRestart} | Should -Throw '*original Outlook process still running*'
    }
    It 'exposes only explicit live recovery CLI, with no COM or files on WhatIf' {
        $src=Join-Path $TestDrive 'arch7c-no-file.pst'
        $main=Join-Path $script:root 'OutlookPOP3Archive.ps1'
        $params=@{ProfileName='Outlook';SourcePst=$src;ConfirmTestArchive=$true;ConfirmLiveOutlookVerification=$true;RecoverLiveInterrupted=$true;WhatIf=$true}
        (& $main -Mode Resume @params -Transaction '20261125-161734-1d203d2f').Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        {& $main -Mode Archive @params -Limit 1} | Should -Throw '*ARCH7c*'
        {& $main -Mode Auto @params} | Should -Throw '*ARCH7c*'
        Test-Path -LiteralPath $src | Should -BeFalse
    }
    It 'runs the actual Resume recovery branch and clears pending after original verifier and ledger' {
        $f=New-ARCH7cMixedFixture
        $tx=$f.Transaction;$source=[string]$tx.State.SourcePst
        [IO.File]::WriteAllBytes($source,[byte[]]@(1));[IO.File]::WriteAllBytes($f.Archive,[byte[]]@(1))
        $store=[pscustomobject]@{StoreID='STORE';FilePath=$source}
        $dest=[pscustomobject]@{StoreID='ARCHIVE';FilePath=$f.Archive}
        $session=[pscustomobject]@{Attached=$true;Namespace=[pscustomobject]@{CurrentProfileName='Outlook';Accounts=@([pscustomobject]@{AccountType=2;DeliveryStore=$store});Stores=@($store,$dest)}}
        $discovery=[pscustomobject]@{Profile='Outlook';Pop3Sources=@([pscustomobject]@{FilePath=$source;Protocol='POP3';StoreHandle=$store})}
        $script:liveFolder=[pscustomobject]@{StoreID='STORE';FolderPath=$script:sourceFolder}
        Mock Get-OPAPop3SourceFolders {$script:liveFolder}
        Mock Get-OPAARCH4OutlookProcess {[pscustomobject]@{Id=100;StartUtcTicks=1000L}}
        Mock Get-OPAARCH7bWorkerIdentity {[pscustomobject]@{Id=201;StartUtcTicks=3000L;SessionId=3}}
        Mock Test-OPAARCH7bMoveWorkerAlive {$false}
        Mock Test-OPAArchiveMoves {New-ARCH4Verification -Count 2}
        Mock Move-OPAItemsWithLimit {throw 'Resume must not call Move'}
        $pending=Join-Path ([IO.Path]::GetDirectoryName($tx.Path)) 'ARCH4.pending'
        $record=[pscustomobject]@{Schema='2.6.5-ARCH4.Pending.1';TransactionId=$tx.TransactionId;SourcePst=[IO.Path]::GetFullPath($source);SourceStoreId='STORE';Profile='Outlook';DeferredPolicy=$true;VerificationPolicy='ARCH7bFreshWorkerSameOutlook';MoveProcessId=100;MoveProcessStartUtcTicks=1000L;MoveWorkerId=200;MoveWorkerStartUtcTicks=2000L;MoveWorkerSessionId=3}
        Write-OPAARCH4Pending -Path $pending -Record $record
        $params=@{Mode='Resume';Session=$session;Discovery=$discovery;SourcePst=$source;TransactionId=$tx.TransactionId;ARCH5Batch=$true;ConfirmLiveOutlookVerification=$true;RecoverLiveInterrupted=$true}
        $r=Invoke-OPAARCH4Batch @params
        $r.Status | Should -BeExactly 'LiveInterruptedBatchRecovered'
        $r.Verified | Should -Be 2
        $r.DeferredRecorded | Should -Be 1
        $r.Unprocessed | Should -Be 1
        $r.PendingCleared | Should -BeTrue
        $r.NaturalOutlookRestart | Should -BeFalse
        $r.MoveInvocations | Should -Be 0
        Test-Path -LiteralPath $pending | Should -BeFalse
        Should -Invoke Test-OPAArchiveMoves -Exactly -Times 1
        Should -Invoke Move-OPAItemsWithLimit -Exactly -Times 0
    }
}


Describe 'ARCH7d supervisor recovery-only child lifecycle' {
    BeforeEach {
        $script:supervisorCase=[pscustomobject]@{Pending=$null;Archives=0;Resumes=0;ExitCode=1;Timeout=$false;ResumeFails=0;InvalidResult=$false;ClearOnFailure=$false;Unprocessed=1;SwapPending=$false;ForeignWorker=$false}
        $script:supervisorId='20261125-161734-1d203d2f'
        $script:supervisorRead={ $script:supervisorCase.Pending }
        $script:supervisorArchive={
            $script:supervisorCase.Archives++
            if($script:supervisorCase.Timeout){return [pscustomobject]@{Exited=$false;WorkerId=200;ExitCode=$null;Result=$null}}
            $script:supervisorCase.Pending=[pscustomobject]@{TransactionId=$script:supervisorId;MoveWorkerId=200}
            if($script:supervisorCase.ForeignWorker){$script:supervisorCase.Pending.MoveWorkerId=999}
            [pscustomobject]@{Exited=$true;WorkerId=200;ExitCode=$script:supervisorCase.ExitCode;Result=$(if($script:supervisorCase.ExitCode -eq 0){[pscustomobject]@{Status='BatchReturnedFreshWorkerResumeRequired';TransactionId=$script:supervisorId}})}
        }
        $script:supervisorResume={
            param($id)
            $script:supervisorCase.Resumes++
            if($script:supervisorCase.SwapPending){$script:supervisorCase.Pending.TransactionId='20261125-161735-00000000'}
            if($script:supervisorCase.Resumes -le $script:supervisorCase.ResumeFails){
                if($script:supervisorCase.ClearOnFailure){$script:supervisorCase.Pending=$null}
                return [pscustomobject]@{Exited=$true;WorkerId=201;ExitCode=1;Result=$null}
            }
            $script:supervisorCase.Pending=$null
            $r=[pscustomobject]@{Schema='2.6.5-ARCH4.Completed.1';Status='LiveInterruptedBatchRecovered';TransactionId=$id;PendingCleared=$true;OutlookRestartRequired=$false;VerifyWorkerId=201;MoveWorkerId=200;MoveInvocations=0;Planned=(3+$script:supervisorCase.Unprocessed);Verified=2;Reconciled=2;Indexed=2;Deferred=1;DeferredRecorded=1;Unprocessed=$script:supervisorCase.Unprocessed}
            if($script:supervisorCase.InvalidResult){$r.MoveInvocations=1}
            [pscustomobject]@{Exited=$true;WorkerId=201;ExitCode=0;Result=$r}
        }
        $script:supervisorOptions=@{ReadPending=$script:supervisorRead;Archive=$script:supervisorArchive;Resume=$script:supervisorResume;Record={param($phase,$data)};MaxBatches=2;MaxResumeAttempts=3;RetryDelaySeconds=0}
    }
    It 'recovers a failed Archive with exactly one new Resume worker and no repeated Archive' {
        $opts=$script:supervisorOptions
        $r=Invoke-OPAARCH7dSequence @opts
        $r.Status | Should -BeExactly 'RecoveredPendingBatch'
        $r.Verified | Should -Be 2
        $r.Unprocessed | Should -Be 1
        $r.Deferred | Should -Be 1
        $r.ArchiveWorkers | Should -Be 1
        $r.ResumeWorkers | Should -Be 1
        $r.LastArchiveExitCode | Should -Be 1
        $r.LastRecovery.MoveInvocations | Should -Be 0
    }
    It 'uses fresh verification workers for normal returned batches and respects batch limit' {
        $opts=$script:supervisorOptions
        $script:supervisorCase.ExitCode=0;$script:supervisorCase.Unprocessed=0
        $r=Invoke-OPAARCH7dSequence @opts
        $r.Status | Should -BeExactly 'BatchLimitReached'
        $r.Batches | Should -Be 2
        $r.Verified | Should -Be 4
        $r.ArchiveWorkers | Should -Be 2
        $r.ResumeWorkers | Should -Be 2
    }
    It 'recovers existing pending before any Archive and supports recovery-only with no pending' {
        $opts=$script:supervisorOptions
        $script:supervisorCase.Pending=[pscustomobject]@{TransactionId=$script:supervisorId;MoveWorkerId=200}
        $r=Invoke-OPAARCH7dSequence @opts -RecoverOnly
        $r.Status | Should -BeExactly 'RecoveredPendingBatch'
        $r.ArchiveWorkers | Should -Be 0
        $r.ResumeWorkers | Should -Be 1
        (Invoke-OPAARCH7dSequence @opts -RecoverOnly).Status | Should -BeExactly 'NoPendingBatch'
    }
    It 'retries only Resume with a bounded attempt count and preserves pending' {
        $opts=$script:supervisorOptions
        $script:supervisorCase.ResumeFails=10
        $r=Invoke-OPAARCH7dSequence @opts
        $r.Status | Should -BeExactly 'RecoveryAttemptsExhausted'
        $r.ArchiveWorkers | Should -Be 1
        $r.ResumeWorkers | Should -Be 3
        $script:supervisorCase.Pending.TransactionId | Should -BeExactly $script:supervisorId
    }
    It 'recovers after transient verification failure without invoking a second Archive' {
        $opts=$script:supervisorOptions
        $script:supervisorCase.ResumeFails=1
        $r=Invoke-OPAARCH7dSequence @opts
        $r.Status | Should -BeExactly 'RecoveredPendingBatch'
        $r.ArchiveWorkers | Should -Be 1
        $r.ResumeWorkers | Should -Be 2
    }
    It 'does not restart or launch a second worker on a still running timeout' {
        $opts=$script:supervisorOptions
        $script:supervisorCase.Timeout=$true
        $r=Invoke-OPAARCH7dSequence @opts
        $r.Status | Should -BeExactly 'WorkerStillRunning'
        $r.ArchiveWorkers | Should -Be 1
        $r.ResumeWorkers | Should -Be 0
    }
    It 'stops when failed Archive leaves no pending or recovery loses pending without evidence' {
        $opts=$script:supervisorOptions
        $opt=$script:supervisorOptions.Clone()
        $opt.Archive={[pscustomobject]@{Exited=$true;ExitCode=1;WorkerId=200;Result=$null}}
        (Invoke-OPAARCH7dSequence @opt).Status | Should -BeExactly 'ArchiveFailedWithoutPending'
        $script:supervisorCase.ResumeFails=1;$script:supervisorCase.ClearOnFailure=$true
        $r=Invoke-OPAARCH7dSequence @opts
        $r.Status | Should -BeExactly 'RecoveryExitWithoutEvidence'
        $r.ArchiveWorkers | Should -Be 1
        $r.ResumeWorkers | Should -Be 1
    }
    It 'rejects foreign Archive worker ownership, changed pending and invalid recovery evidence' {
        $opts=$script:supervisorOptions
        $script:supervisorCase.ForeignWorker=$true
        {Invoke-OPAARCH7dSequence @opts} | Should -Throw '*not owned*'
        $script:supervisorCase.Pending=$null;$script:supervisorCase.ForeignWorker=$false
        $script:supervisorCase.ResumeFails=10;$script:supervisorCase.SwapPending=$true
        {Invoke-OPAARCH7dSequence @opts} | Should -Throw '*identity changed*'
        $script:supervisorCase.Pending=$null;$script:supervisorCase.SwapPending=$false;$script:supervisorCase.ResumeFails=0;$script:supervisorCase.InvalidResult=$true
        {Invoke-OPAARCH7dSequence @opts} | Should -Throw '*invalid recovery result*'
    }
    It 'reads only exact live pending for source and profile, without modifying it' {
        $opts=$script:supervisorOptions
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        $source=Join-Path $dir 'source.pst'
        $path=Join-Path $dir 'ARCH4.pending'
        Get-OPAARCH7dPending -Directory $dir -SourcePst $source -ProfileName Outlook | Should -BeNullOrEmpty
        $record=[pscustomobject]@{Schema='2.6.5-ARCH4.Pending.1';TransactionId=$script:supervisorId;SourcePst=$source;SourceStoreId='STORE';Profile='Outlook';DeferredPolicy=$true;VerificationPolicy='ARCH7bFreshWorkerSameOutlook';MoveWorkerId=200}
        Write-OPAARCH4Pending -Path $path -Record $record
        $hash=(Get-FileHash -LiteralPath $path).Hash
        (Get-OPAARCH7dPending -Directory $dir -SourcePst $source -ProfileName Outlook).TransactionId | Should -BeExactly $script:supervisorId
        {Get-OPAARCH7dPending -Directory $dir -SourcePst $source -ProfileName Other} | Should -Throw '*invalid pending*'
        (Get-FileHash -LiteralPath $path).Hash | Should -BeExactly $hash
    }
    It 'launches a real STA PowerShell child with Unicode parameters and isolated JSON response, without Outlook' {
        $opts=$script:supervisorOptions
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        $stub=Join-Path $dir 'stub.ps1'
        $code='param([string]$SourcePst,[switch]$ConfirmTestArchive); Write-Host "diagnostic"; [pscustomobject]@{Schema="Fake.1";Status="OK";SourcePst=$SourcePst;Confirmed=[bool]$ConfirmTestArchive;Pid=$PID;Apartment=[Threading.Thread]::CurrentThread.GetApartmentState().ToString()}'
        [IO.File]::WriteAllText($stub,$code,[Text.UTF8Encoding]::new($true))
        $source=Join-Path $dir 'Файлы Outlook\почта.pst'
        $r=Invoke-OPAARCH7dWorker -Main $stub -Parameters @{SourcePst=$source;ConfirmTestArchive=$true} -Directory $dir -LogDirectory $dir -TimeoutSeconds 30
        $r.Exited | Should -BeTrue
        ($r.ExitCode -is [int]) | Should -BeTrue
        $r.ExitCode | Should -Be 0
        $r.Result.SourcePst | Should -BeExactly $source
        $r.Result.Confirmed | Should -BeTrue
        $r.Result.Pid | Should -Be $r.WorkerId
        $r.Result.Pid | Should -Not -Be $PID
        $r.Result.Apartment | Should -BeExactly STA
    }
    It 'retains numeric nonzero exit code and refuses a result from a failed real child' {
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        $stub=Join-Path $dir 'failure.ps1'
        [IO.File]::WriteAllText($stub,'throw "ARCH7d1 controlled child failure"',[Text.UTF8Encoding]::new($true))
        $r=Invoke-OPAARCH7dWorker -Main $stub -Parameters @{} -Directory $dir -LogDirectory $dir -TimeoutSeconds 30
        $r.Exited | Should -BeTrue
        ($r.ExitCode -is [int]) | Should -BeTrue
        $r.ExitCode | Should -Be 1
        $r.Result | Should -BeNullOrEmpty
        [IO.File]::ReadAllText($r.ErrorLog) | Should -Match 'ARCH7d1 controlled child failure'
        @(Get-ChildItem -LiteralPath $dir -Filter '*.result.json').Count | Should -Be 0
        $probe=[IO.FileStream]::new((Join-Path $dir 'ARCH7d.worker.lease'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $probe.Dispose()
    }
    It 'stops without launching another worker if either exit code is unknown' {
        $opt=$script:supervisorOptions.Clone()
        $opt.Archive={
            $script:supervisorCase.Archives++
            $script:supervisorCase.Pending=[pscustomobject]@{TransactionId=$script:supervisorId;MoveWorkerId=200}
            [pscustomobject]@{Exited=$true;WorkerId=200;ExitCode=$null;Result=$null}
        }
        $r=Invoke-OPAARCH7dSequence @opt
        $r.Status | Should -BeExactly 'WorkerExitCodeUnavailable'
        $r.ArchiveWorkers | Should -Be 1
        $r.ResumeWorkers | Should -Be 0
        $script:supervisorCase.Pending.TransactionId | Should -BeExactly $script:supervisorId
        $opt=$script:supervisorOptions.Clone()
        $opt.Resume={
            $script:supervisorCase.Resumes++
            [pscustomobject]@{Exited=$true;WorkerId=201;ExitCode=$null;Result=$null}
        }
        $r=Invoke-OPAARCH7dSequence @opt
        $r.Status | Should -BeExactly 'WorkerExitCodeUnavailable'
        $r.ArchiveWorkers | Should -Be 0
        $r.ResumeWorkers | Should -Be 1
        $script:supervisorCase.Pending.TransactionId | Should -BeExactly $script:supervisorId
    }
    It 'validates supervisor and controlled interruption CLI before COM or writes' {
        $opts=$script:supervisorOptions
        $src=Join-Path $TestDrive 'arch7d-not-created.pst'
        $supervisor=Join-Path $script:root 'Invoke-OPALiveArchiveBatches.ps1'
        $main=Join-Path $script:root 'OutlookPOP3Archive.ps1'
        $params=@{ProfileName='Outlook';SourcePst=$src;ConfirmTestArchive=$true;ConfirmLiveOutlookVerification=$true;WhatIf=$true}
        (& $supervisor @params -BatchSize 10 -InterruptAfterReturned 2).Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        {& $supervisor @params -BatchSize 2 -InterruptAfterReturned 2} | Should -Throw '*interruption scope*'
        {& $supervisor @params -RecoverOnly -BatchSize 10} | Should -Throw '*recovery-only*'
        (& $main @params -Mode Archive -Limit 10 -ARCH7dInterruptAfterReturned 2).Status | Should -BeExactly 'NoOutlookOrPersistentWrites'
        {& $main @params -Mode Resume -Transaction $script:supervisorId -ARCH7dInterruptAfterReturned 1} | Should -Throw '*controlled interruption*'
        Test-Path -LiteralPath $src | Should -BeFalse
    }
    It 'places the controlled interruption strictly after durable original return and before next candidate' {
        $opts=$script:supervisorOptions
        $m=[IO.File]::ReadAllText((Join-Path $script:root 'Core/Archive/MailMover.ps1'))
        $receipt=$m.IndexOf("-Step 'ARCH4 Move Returned'")
        $flush=$m.IndexOf('Sync-OPAStepJournalStreams',$receipt)
        $stop=$m.IndexOf("throw 'ARCH7d controlled interruption after durable paired receipt")
        ($receipt -ge 0 -and $flush -gt $receipt -and $stop -gt $flush) | Should -BeTrue
        $controller=[IO.File]::ReadAllText((Join-Path $script:root 'Core/Archive/ARCH7dSupervisor.ps1'))
        $controller | Should -Not -Match '\.Quit\(|\.Kill\(|Stop-Process'
    }
}


Describe 'ARCH7d2 public controller end-to-end with isolated real PowerShell children' {
    BeforeAll {
        function New-ARCH7d2PublicFixture {
            # Copy the actual public controller and actual supervisor unchanged.
            # Substitute ONLY its sibling main entrypoint inside a unique temp tree.
            # No production test injection parameter, no Outlook, no real PST.
            $fixture=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $core=Join-Path $fixture 'Core\Archive'
            [void][IO.Directory]::CreateDirectory($core)
            $controller=Join-Path $fixture 'Invoke-OPALiveArchiveBatches.ps1'
            [IO.File]::Copy((Join-Path $script:root 'Invoke-OPALiveArchiveBatches.ps1'),$controller)
            [IO.File]::Copy((Join-Path $script:root 'Core/Archive/ARCH7dSupervisor.ps1'),(Join-Path $core 'ARCH7dSupervisor.ps1'))
            $mailDir=Join-Path $fixture 'Файлы Outlook'
            [void][IO.Directory]::CreateDirectory($mailDir)
            $source=Join-Path $mailDir 'почта.pst'
            [IO.File]::WriteAllBytes($source,[byte[]]@(1,2,3))
            $stub=Join-Path $fixture 'OutlookPOP3Archive.ps1'
            $code=@'
param([string]$Mode,[string]$SourcePst,[string]$ProfileName,[switch]$ConfirmTestArchive,
      [switch]$ConfirmLiveOutlookVerification,[int]$Limit,[int]$OlderThanMonths,[string]$ArchiveGrouping,
      [string[]]$IncludeFolderPath,[switch]$IncludeRootMail,[switch]$DisableArchivePstSizeLimit,
      [int]$ARCH7dInterruptAfterReturned,[string]$Transaction,[switch]$RecoverLiveInterrupted)
$ErrorActionPreference='Stop'
$expected=Join-Path $PSScriptRoot 'Файлы Outlook\почта.pst'
if($SourcePst -cne $expected -or $ProfileName -cne 'Outlook' -or -not $ConfirmTestArchive -or
   -not $ConfirmLiveOutlookVerification -or [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH7d2 fixture common parameter mismatch'
}
$dir=Join-Path ([IO.Path]::GetDirectoryName($SourcePst)) 'OutlookPOP3Archive-Transactions'
$pending=Join-Path $dir 'ARCH4.pending'
$trace=Join-Path $dir 'fixture-trace.jsonl'
$tx='20261125-161734-1d203d2f'
if($Mode -ceq 'Archive'){
    if($Limit -ne 10 -or $OlderThanMonths -ne 60 -or $ArchiveGrouping -cne 'YearQuarter' -or
       -not $DisableArchivePstSizeLimit -or -not $IncludeRootMail -or $RecoverLiveInterrupted -or $Transaction -or
       $IncludeFolderPath.Count -ne 2 -or $IncludeFolderPath[0] -cne '\\почта\Входящие' -or $IncludeFolderPath[1] -cne '\\почта\Отправленные' -or
       $ARCH7dInterruptAfterReturned -notin @(0,2)){throw 'ARCH7d2 fixture Archive parameter mismatch'}
    $returned=if($ARCH7dInterruptAfterReturned -eq 2){2}else{10}
    $p=[ordered]@{Schema='2.6.5-ARCH4.Pending.1';VerificationPolicy='ARCH7bFreshWorkerSameOutlook';DeferredPolicy=$true;SourcePst=$SourcePst;Profile=$ProfileName;SourceStoreId='FAKE';TransactionId=$tx;MoveWorkerId=$PID;FixtureReturned=$returned}
    $json=ConvertTo-Json -InputObject $p -Compress
    $fs=[IO.FileStream]::new($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($json);$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
    $row=[ordered]@{Mode=$Mode;Pid=$PID;SourcePst=$SourcePst;Folders=$IncludeFolderPath;Interrupt=$ARCH7dInterruptAfterReturned}
    [IO.File]::AppendAllText($trace,((ConvertTo-Json -InputObject $row -Compress)+[char]10),[Text.UTF8Encoding]::new($false))
    if($ARCH7dInterruptAfterReturned -eq 2){throw 'ARCH7d2 fixture controlled interruption'}
    [pscustomobject]@{Schema='2.6.5-ARCH4.Returned.1';Status='BatchReturnedFreshWorkerResumeRequired';TransactionId=$tx}
    return
}
if($Mode -cne 'Resume' -or $Transaction -cne $tx -or -not $RecoverLiveInterrupted -or $Limit -ne 0 -or
   $OlderThanMonths -ne 0 -or $ArchiveGrouping -or $IncludeFolderPath -or $IncludeRootMail -or
   $DisableArchivePstSizeLimit -or $ARCH7dInterruptAfterReturned -ne 0){throw 'ARCH7d2 fixture Resume parameter mismatch'}
$p=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($pending,[Text.Encoding]::UTF8))
if($p.MoveWorkerId -eq $PID -or $p.TransactionId -cne $Transaction){throw 'ARCH7d2 fixture worker identity mismatch'}
$row=[ordered]@{Mode=$Mode;Pid=$PID;SourcePst=$SourcePst;TransactionId=$Transaction}
[IO.File]::AppendAllText($trace,((ConvertTo-Json -InputObject $row -Compress)+[char]10),[Text.UTF8Encoding]::new($false))
[IO.File]::Delete($pending)
[pscustomobject]@{Schema='2.6.5-ARCH4.Completed.1';Status='LiveInterruptedBatchRecovered';TransactionId=$Transaction;PendingCleared=$true;OutlookRestartRequired=$false;VerifyWorkerId=$PID;MoveWorkerId=[int]$p.MoveWorkerId;MoveInvocations=0;Planned=10;Verified=[int]$p.FixtureReturned;Reconciled=[int]$p.FixtureReturned;Indexed=[int]$p.FixtureReturned;Deferred=0;DeferredRecorded=0;Unprocessed=(10-[int]$p.FixtureReturned)}
'@
            [IO.File]::WriteAllText($stub,$code,[Text.UTF8Encoding]::new($true))
            $parameters=@{SourcePst=$source;ProfileName='Outlook';ConfirmTestArchive=$true;ConfirmLiveOutlookVerification=$true;BatchSize=10;MaxBatches=1;OlderThanMonths=60;ArchiveGrouping='YearQuarter';IncludeFolderPath=@('\\почта\Входящие','\\почта\Отправленные');IncludeRootMail=$true;MaxResumeAttempts=1;WorkerTimeoutSeconds=30}
            [pscustomobject]@{Controller=$controller;Source=$source;Directory=(Join-Path $mailDir 'OutlookPOP3Archive-Transactions');Parameters=$parameters;SourceHash=(Get-FileHash -LiteralPath $source).Hash}
        }
        function Assert-ARCH7d2PublicResult {
            param([object]$Fixture,[object]$Result,[int]$ExpectedExit,[int]$ExpectedVerified)
            $Result.ArchiveWorkers | Should -Be 1
            $Result.ResumeWorkers | Should -Be 1
            $Result.LastArchiveExitCode | Should -Be $ExpectedExit
            $Result.Verified | Should -Be $ExpectedVerified
            $Result.LastRecovery.Indexed | Should -Be $ExpectedVerified
            $Result.LastRecovery.MoveInvocations | Should -Be 0
            $Result.LastRecovery.PendingCleared | Should -BeTrue
            $Result.LastRecovery.MoveWorkerId | Should -Not -Be $Result.LastRecovery.VerifyWorkerId
            $Result.LastRecovery.MoveWorkerId | Should -Be $Result.LastArchiveWorkerId
            $Result.LastRecovery.VerifyWorkerId | Should -Not -Be $PID
            $Result.Unprocessed | Should -Be (10-$ExpectedVerified)
            [IO.File]::Exists((Join-Path $Fixture.Directory 'ARCH4.pending')) | Should -BeFalse
            (Get-FileHash -LiteralPath $Fixture.Source).Hash | Should -BeExactly $Fixture.SourceHash
            $trace=@(Get-Content -LiteralPath (Join-Path $Fixture.Directory 'fixture-trace.jsonl') -Encoding UTF8 | ForEach-Object {ConvertFrom-Json -InputObject $_})
            $trace.Count | Should -Be 2
            $trace[0].Mode | Should -BeExactly Archive
            $trace[1].Mode | Should -BeExactly Resume
            $trace[0].Pid | Should -Be $Result.LastArchiveWorkerId
            $trace[1].Pid | Should -Be $Result.LastRecovery.VerifyWorkerId
            $trace[0].SourcePst | Should -BeExactly $Fixture.Source
            $trace[0].Folders[1] | Should -BeExactly '\\почта\Отправленные'
            $journal=@(Get-Content -LiteralPath (Join-Path $Result.LogDirectory 'supervisor.jsonl') -Encoding UTF8 | ForEach-Object {ConvertFrom-Json -InputObject $_})
            $journal.Count | Should -Be 3
            $journal[0].Phase | Should -BeExactly ArchiveWorker
            $journal[1].Phase | Should -BeExactly ResumeWorker
            $journal[2].Phase | Should -BeExactly SupervisorCompleted
            @(Get-ChildItem -LiteralPath $Result.LogDirectory -Filter '*.stdout.log').Count | Should -Be 2
            @(Get-ChildItem -LiteralPath $Result.LogDirectory -Filter '*.stderr.log').Count | Should -Be 2
        }
    }
    It 'runs the unmodified public controller with real Archive and Resume child processes and Unicode options' {
        $fixture=New-ARCH7d2PublicFixture
        $parameters=$fixture.Parameters
        $r=& $fixture.Controller @parameters
        $r.Status | Should -BeExactly BatchLimitReached
        Assert-ARCH7d2PublicResult -Fixture $fixture -Result $r -ExpectedExit 0 -ExpectedVerified 10
    }
    It 'runs the public controller after a failed Archive and automatically recovers with a fresh child' {
        $fixture=New-ARCH7d2PublicFixture
        $parameters=$fixture.Parameters
        $r=& $fixture.Controller @parameters -InterruptAfterReturned 2
        $r.Status | Should -BeExactly RecoveredPendingBatch
        Assert-ARCH7d2PublicResult -Fixture $fixture -Result $r -ExpectedExit 1 -ExpectedVerified 2
        $logs=@(Get-ChildItem -LiteralPath $r.LogDirectory -Filter '*.stderr.log' | Select-String -Pattern 'ARCH7d2 fixture controlled interruption')
        $logs.Count | Should -Be 1
    }
    It 'executes public RecoverOnly with no pending and does not launch any child' {
        $fixture=New-ARCH7d2PublicFixture
        $r=& $fixture.Controller -SourcePst $fixture.Source -ProfileName Outlook -ConfirmTestArchive -ConfirmLiveOutlookVerification -RecoverOnly
        $r.Status | Should -BeExactly NoPendingBatch
        $r.ArchiveWorkers | Should -Be 0
        $r.ResumeWorkers | Should -Be 0
        @(Get-ChildItem -LiteralPath $r.LogDirectory -Filter '*.stdout.log').Count | Should -Be 0
        (Get-FileHash -LiteralPath $fixture.Source).Hash | Should -BeExactly $fixture.SourceHash
    }
}


Describe 'ARCH7e guarded all-POP3 age-only dispatcher' {
    BeforeAll {
        function New-ARCH7eFixture {
            $d=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($d)
            $other=Join-Path $d 'other'
            [void][IO.Directory]::CreateDirectory($other)
            $a=Join-Path $d 'a.pst';$b=Join-Path $d 'b.pst';$c=Join-Path $other 'c.pst'
            $imap=Join-Path $d 'imap.ost';$archive=Join-Path $d 'a.Archive-2020.pst'
            foreach($path in @($a,$b,$c,$imap,$archive)){[IO.File]::WriteAllBytes($path,[byte[]]@(1))}
            $sa=[pscustomobject]@{StoreID='A';FilePath=$a;DisplayName='A'}
            $sb=[pscustomobject]@{StoreID='B';FilePath=$b;DisplayName='B'}
            $sc=[pscustomobject]@{StoreID='C';FilePath=$c;DisplayName='C'}
            $si=[pscustomobject]@{StoreID='IMAP';FilePath=$imap;DisplayName='IMAP'}
            $sx=[pscustomobject]@{StoreID='ARCHIVE';FilePath=$archive;DisplayName='Archive'}
            $ns=[pscustomobject]@{CurrentProfileName='Outlook';Accounts=@([pscustomobject]@{AccountType=2;DeliveryStore=$sa},[pscustomobject]@{AccountType=1;DeliveryStore=$si},[pscustomobject]@{AccountType=2;DeliveryStore=$sb},[pscustomobject]@{AccountType=2;DeliveryStore=$sc});Stores=@($sa,$sb,$sc,$si,$sx)}
            $rows=@(Get-OPAARCH7eSourceRows -Namespace $ns -ProfileName Outlook)
            [pscustomobject]@{Namespace=$ns;Rows=$rows;A=$a;B=$b;C=$c;ArchiveStore=$sx;SourceStore=$sa}
        }
        function New-ARCH7eResult {
            param([string]$Status='NoEligibleMessages',[int]$Verified=0,[int]$Deferred=0,[int]$Unprocessed=0,[int]$Batches=0)
            [pscustomobject]@{Schema='2.6.5-ARCH7d.Supervisor.1';Status=$Status;Verified=$Verified;Deferred=$Deferred;Unprocessed=$Unprocessed;Batches=$Batches;ProductionReady=$false;AutomaticMoveRetryAllowed=$false;OutlookRestartRequired=$false;LastBatchResult=$null}
        }
    }
    It 'discovers only unique direct POP3 delivery stores without size gating or archive and IMAP selection' {
        $f=New-ARCH7eFixture
        $f.Rows.Count | Should -Be 3
        $f.Rows.SourcePst | Should -Contain $f.A
        $f.Rows.SourcePst | Should -Contain $f.B
        $f.Rows.SourcePst | Should -Contain $f.C
        $f.Rows.SourcePst | Should -Not -Contain $f.ArchiveStore.FilePath
        @($f.Rows | Where-Object {$_.Protocol -cne 'POP3'}).Count | Should -Be 0
        @($f.Rows | Group-Object Directory).Count | Should -Be 2
    }
    It 'rejects ambiguous shared POP3 delivery, archive as delivery, and cross-protocol store ownership' {
        $f=New-ARCH7eFixture
        $original=$f.Namespace.Accounts
        $f.Namespace.Accounts=$original+@([pscustomobject]@{AccountType=2;DeliveryStore=$f.SourceStore})
        {Get-OPAARCH7eSourceRows -Namespace $f.Namespace -ProfileName Outlook} | Should -Throw '*ambiguous POP3*'
        $f.Namespace.Accounts=$original+@([pscustomobject]@{AccountType=2;DeliveryStore=$f.ArchiveStore})
        {Get-OPAARCH7eSourceRows -Namespace $f.Namespace -ProfileName Outlook} | Should -Throw '*unsafe POP3*'
        $f.Namespace.Accounts=$original+@([pscustomobject]@{AccountType=1;DeliveryStore=$f.SourceStore})
        {Get-OPAARCH7eSourceRows -Namespace $f.Namespace -ProfileName Outlook} | Should -Throw '*non-POP3 account*'
        $f.Namespace.Accounts=$original+@([pscustomobject]@{AccountType=2;DeliveryStore=$null})
        {Get-OPAARCH7eSourceRows -Namespace $f.Namespace -ProfileName Outlook} | Should -Throw '*identity unavailable*'
    }
    It 'resolves exact shared-directory pending owner without modifying evidence and blocks foreign owners' {
        $f=New-ARCH7eFixture
        $members=@($f.Rows | Where-Object {$_.SourcePst -in @($f.A,$f.B)})
        $b=@($members | Where-Object {$_.SourcePst -eq $f.B})[0]
        [void][IO.Directory]::CreateDirectory($b.Directory)
        $path=Join-Path $b.Directory 'ARCH4.pending'
        Get-OPAARCH7ePendingOwner -Directory $b.Directory -Sources $members | Should -BeNullOrEmpty
        $record=[pscustomobject]@{Schema='2.6.5-ARCH4.Pending.1';TransactionId='20261125-173959-49d4a7fb';SourcePst=$b.SourcePst;SourceStoreId=$b.StoreId;Profile='Outlook';DeferredPolicy=$true;VerificationPolicy='ARCH7bFreshWorkerSameOutlook';MoveWorkerId=200}
        Write-OPAARCH4Pending -Path $path -Record $record
        $hash=(Get-FileHash -LiteralPath $path).Hash
        (Get-OPAARCH7ePendingOwner -Directory $b.Directory -Sources $members).SourcePst | Should -BeExactly $f.B
        {Get-OPAARCH7ePendingOwner -Directory $b.Directory -Sources @($members | Where-Object {$_.SourcePst -eq $f.A})} | Should -Throw '*not a uniquely discovered*'
        (Get-FileHash -LiteralPath $path).Hash | Should -BeExactly $hash
    }
    It 'processes pending owner first and selects fresh batches after proven partial recovery until exhaustion' {
        $f=New-ARCH7eFixture
        $script:eOwner=@($f.Rows | Where-Object {$_.SourcePst -eq $f.B})[0]
        $script:eCalls=New-Object 'System.Collections.Generic.List[string]'
        $r=Invoke-OPAARCH7eSourceSequence -Sources $f.Rows -MaxBatchesPerSource 3 -PendingOwner {
            param($directory,$members)
            if($null -ne $script:eOwner -and $script:eOwner.Directory -eq $directory){$script:eOwner}
        } -RunSource {
            param($row)
            $script:eCalls.Add($row.StoreId)
            if($row.StoreId -ceq 'B' -and $null -ne $script:eOwner){
                $script:eOwner=$null
                New-ARCH7eResult -Status RecoveredPendingBatch -Verified 2 -Deferred 1 -Unprocessed 7 -Batches 1
            }else{New-ARCH7eResult}
        }
        $r.Status | Should -BeExactly AllSourcesExhausted
        $r.SourcesExhausted | Should -Be 3
        $r.Verified | Should -Be 2
        $r.Deferred | Should -Be 1
        ($script:eCalls.ToArray() -join ',') | Should -BeExactly 'B,B,A,C'
    }
    It 'holds other PSTs sharing a failed pending but continues independent directory' {
        $f=New-ARCH7eFixture
        $script:eOwner=@($f.Rows | Where-Object {$_.SourcePst -eq $f.B})[0]
        $script:eCalls=New-Object 'System.Collections.Generic.List[string]'
        $r=Invoke-OPAARCH7eSourceSequence -Sources $f.Rows -MaxBatchesPerSource 3 -PendingOwner {
            param($directory,$members)
            if($script:eOwner.Directory -eq $directory){$script:eOwner}
        } -RunSource {
            param($row)
            $script:eCalls.Add($row.StoreId)
            if($row.StoreId -ceq 'B'){New-ARCH7eResult -Status RecoveryAttemptsExhausted}else{New-ARCH7eResult}
        }
        $r.Status | Should -BeExactly PartialOrBlocked
        ($script:eCalls.ToArray() -join ',') | Should -BeExactly 'B,C'
        @($r.Sources | Where-Object {$_.SourcePst -eq $f.A})[0].Status | Should -BeExactly NotRunBlocked
        $r.SourcesExhausted | Should -Be 1
    }
    It 'never launches another source when child is still running or exit code unknown' {
        $f=New-ARCH7eFixture
        foreach($state in @('WorkerStillRunning','WorkerExitCodeUnavailable','RecoveryExitWithoutEvidence')){
            $script:eState=$state
            $script:eCalls=0
            $r=Invoke-OPAARCH7eSourceSequence -Sources $f.Rows -MaxBatchesPerSource 3 -PendingOwner {param($directory,$members)} -RunSource {
                param($row)
                $script:eCalls++
                New-ARCH7eResult -Status $script:eState
            }
            $script:eCalls | Should -Be 1
            $r.Status | Should -BeExactly PartialOrBlocked
            @($r.Sources | Where-Object {$_.Status -ceq 'NotRunBlocked'}).Count | Should -Be 2
        }
    }
    It 'honors per-source bounded batch cap, skip-only progress and zero-progress stop' {
        $f=New-ARCH7eFixture
        $script:eCalls=0
        $r=Invoke-OPAARCH7eSourceSequence -Sources @($f.Rows[0]) -MaxBatchesPerSource 2 -PendingOwner {param($directory,$members)} -RunSource {
            param($row)
            $script:eCalls++
            New-ARCH7eResult -Status BatchLimitReached -Deferred 1 -Batches 1
        }
        $r.Status | Should -BeExactly PartialOrBlocked
        $r.Deferred | Should -Be 2
        $script:eCalls | Should -Be 2
        $r.Sources[0].Status | Should -BeExactly BatchLimitReached
        $r=Invoke-OPAARCH7eSourceSequence -Sources @($f.Rows[0]) -MaxBatchesPerSource 3 -PendingOwner {param($directory,$members)} -RunSource {
            param($row)
            New-ARCH7eResult -Status RecoveredPendingBatch -Unprocessed 10 -Batches 1
        }
        $r.Sources[0].Status | Should -BeExactly StoppedNoProgress
        $r.Sources[0].Attempts | Should -Be 1
    }
    It 'blocks a burst of attachment export failures and does not report exhaustion' {
        $f=New-ARCH7eFixture
        $r=Invoke-OPAARCH7eSourceSequence -Sources @($f.Rows[0]) -MaxBatchesPerSource 3 -PendingOwner {param($directory,$members)} -RunSource {
            param($row)
            $x=New-ARCH7eResult -Status BatchLimitReached -Deferred 10 -Batches 1
            $x.LastBatchResult=[pscustomobject]@{Planned=10;SkipReasons=@([pscustomobject]@{Reason='AttachmentExportFailed';Count=10})}
            $x
        }
        $r.Sources[0].Status | Should -BeExactly StoppedOnExportFailureBurst
        $r.Sources[0].Attempts | Should -Be 1
    }
    It 'accepts only explicit DEV Auto age-only defaults and rejects legacy policy or writer keys before COM' {
        $main=Join-Path $script:root 'OutlookPOP3Archive.ps1'
        $r=& $main -Mode Auto -ConfirmDevAutoArchive -WhatIf
        $r.Status | Should -BeExactly NoOutlookOrPersistentWrites
        $r.BatchSize | Should -Be 10
        $r.OlderThanMonths | Should -Be 12
        $r.ArchiveGrouping | Should -BeExactly YearQuarter
        $r.IncludeRootMail | Should -BeTrue
        $r.DisableStoragePolicy | Should -BeTrue
        $r.DisableArchivePstSizeLimit | Should -BeTrue
        $r.DurabilityMode | Should -BeExactly Safe
        $r.ProductionReady | Should -BeFalse
        {& $main -Mode Auto -ConfirmDevAutoArchive -WhatIf -Limit 11} | Should -Throw '*age-only*'
        {& $main -Mode Auto -ConfirmDevAutoArchive -WhatIf -SourcePst 'fake.pst'} | Should -Throw '*unsupported Auto DEV parameter*'
        {& $main -Mode Auto -ConfirmDevAutoArchive -WhatIf -DisableStoragePolicy:$false} | Should -Throw '*age-only*'
        {& $main -Mode Auto -ConfirmDevAutoArchive -WhatIf -DurabilityMode Fast} | Should -Throw '*age-only*'
        {& $main -Mode Auto -WhatIf -AutoDevMaxBatches 1} | Should -Throw '*requires ConfirmDevAutoArchive*'
        {& $main -Mode Auto -WhatIf} | Should -Throw
    }
    It 'returns NoPop3Sources without any write or Archive callback' {
        $r=Invoke-OPAARCH7eSourceSequence -Sources @() -MaxBatchesPerSource 1 -PendingOwner {throw 'unexpected pending'} -RunSource {throw 'unexpected Archive'}
        $r.Status | Should -BeExactly NoPop3Sources
        $r.SourcesDiscovered | Should -Be 0
        $r.Verified | Should -Be 0
    }
}

}
