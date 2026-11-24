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
        param([object]$Fixture)
        $tx=$Fixture.Transaction
        Save-OPAArchiveTransaction -Transaction $tx -Status Planned -Step Candidates -WriteCheckpoint
        foreach($s in $Fixture.Steps){
            $params=@{Transaction=$tx;Status='Running';Step=$s.Step;EntryId=$s.EntryId;SourceFolderPath=$s.SourceFolderPath;TargetFolderPath=$s.TargetFolderPath;ArchivePst=$s.ArchivePst;ReceivedTime=[datetime]$s.ReceivedTime}
            if($s.Step -eq 'Move Started'){$params.SemanticWitness=$s.SourceSemanticWitness}
            else{$params.ArchiveEntryId=$s.ArchiveEntryId}
            Save-OPAArchiveTransaction @params
        }
        foreach($e in $Fixture.Events){
            [void](Write-OPAOperationJournalEvent -Path (Get-OPAARCH4OperationPath -Transaction $tx) -TransactionId $tx.TransactionId -OperationId $e.OperationId -Sequence $e.Sequence -Phase Intent -SourceEntryId $e.SourceEntryId -SourceStoreId $e.SourceStoreId -SourceFolderPath $e.SourceFolderPath -TargetFolderPath $e.TargetFolderPath -ArchivePst $e.ArchivePst)
        }
        Sync-OPAStepJournalStreams
        Save-OPAArchiveTransaction -Transaction $tx -Status Running -Step 'ARCH4 Awaiting Restart' -WriteCheckpoint
    }
    function New-ARCH4Verification {
        param([int]$Count)
        return [pscustomobject]@{Verified=$true;EntryIdsVerified=$true;SemanticWitnessRequired=$true;AllRequiredOriginalSemanticWitnessesPresent=$true;ExpectedMoved=$Count;ExpectedEntryIdsChecked=$Count;MissingEntryIds=@();WarningEntryIds=@()}
    }
}
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
