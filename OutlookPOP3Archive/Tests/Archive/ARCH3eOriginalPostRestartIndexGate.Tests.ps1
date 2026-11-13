#requires -Version 5.1
# ARCH3e uses ORIGINAL ArchiveVerifier and DuplicateIndex in pure synthetic
# Outlook test doubles with immutable original ARCH3d receipt and temp JSONL.
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Runtime/JsonSupport.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3cDurableOperationLedger.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3dOriginalMoverBoundary.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH2bSemanticWitness.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveVerifier.ps1')
    . (Join-Path $script:root 'Core/Archive/DuplicateIndex.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3ePostRestartIndexGate.ps1')
    if(-not (Get-Command Release-OPAComObject -ErrorAction SilentlyContinue)){
        function Release-OPAComObject {param([object]$Object)}
    }
    $global:OPADurabilityMode='Safe'
    $script:fixtures=New-Object 'System.Collections.Generic.List[object]'
    function New-ARCH3eWitness {
        $names=@('InternetMessageIdSha256','SubjectSha256','SenderSha256','ToSha256',
                 'CcSha256','BccSha256','OrderedRecipientDigestSha256',
                 'BodySha256','HtmlBodySha256','CategoriesSha256')
        $w=[ordered]@{Schema='2.6.5-ARCH2b.MailSemanticWitness.1';ItemClass=43}
        foreach($n in $names){$w[$n]=('a'*64)}
        foreach($n in @('BodyUtf16Length','HtmlBodyUtf16Length','RecipientCount','AttachmentCount',
                        'ReceivedUtcTicks','SentUtcTicks','MailItemSizeDiagnosticBytes')){$w[$n]=[long]0}
        $w.UnRead=$false;$w.Importance=1;$w.Sensitivity=0;$w.Attachments=@()
        return [pscustomobject]$w
    }
    function New-ARCH3eFixture {
        $id='ARCH3D-SYNTHETIC-'+[guid]::NewGuid().ToString('N')
        $src=Join-Path (Join-Path ([IO.Path]::GetTempPath()) $id) 'info@stios.ru.pst'
        $subject='ARCH3e fake original mail'
        $originalFolderPath='\\POP3 Store\Входящие'
        $originalFolder=[pscustomobject]@{
            FolderPath=$originalFolderPath
            Name='Входящие'
            Items=[pscustomobject]@{Count=0}
        }
        $candidate=[pscustomobject]@{EntryID='00000000E1878292411BC64291BD506DCEFD2A35040A3C00';
            ArchiveDate=[datetime]'2020-02-12T12:30:00';ReceivedTime=[datetime]'2020-02-12T12:30:00';
            FolderName='Входящие';SourceFolderPath=$originalFolderPath;Subject=$subject}
        $t=[pscustomobject]@{TransactionId=$id;State=[pscustomobject]@{
            SourcePst=$src;SourceStoreId='ARCH3D-SYNTHETIC-NOT-REAL-STORE'}}
        $scope=Assert-OPA265ARCH3dSyntheticBoundary -Namespace ([pscustomobject]@{Fake=$true}) -Transaction $t -SourceFolders @($originalFolder)
        $op=Get-OPA265ARCH3dOperationIdentity -Scope $scope -Candidate $candidate -ArchiveGrouping Year
        $archive=Get-OPAArchivePartPath -SourcePst $src -Year 2020 -Part 1
        $archiveFolderPath='\\Synthetic Archive\2020\Входящие'
        $destId='00000000FEDCBA9876543210FEDCBA987654321000000001'
        $attachmentWitness=New-ARCH3eWitness
        $archiveFolder=[pscustomobject]@{Name='Входящие';FolderPath=$archiveFolderPath;Items=[pscustomobject]@{Count=1}}
        $yearFolder=[pscustomobject]@{Name='2020';Folders=@($archiveFolder)}
        $fakeRoot=[pscustomobject]@{Name='Synthetic Archive';Folders=@($yearFolder)}
        $store=[pscustomobject]@{FilePath=$archive;StoreID='ARCH3E-FAKE-ARCHIVE-STORE';Root=$fakeRoot}
        $store | Add-Member -MemberType ScriptMethod -Name GetRootFolder -Value {return $this.Root}
        $item=[pscustomobject]@{Class=43;EntryID=$destId;Subject=$subject;SenderEmailAddress='';Size=[long]100;Parent=$archiveFolder}
        $ns=[pscustomobject]@{ItemValue=$item}
        $ns | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {param($entryId,$storeId) return $this.ItemValue}
        $witnessSha=Get-OPA265ARCH3dOriginalWitnessHash -Witness $attachmentWitness
        $seq=@('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned')
        $returned=$null
        foreach($phase in $seq){
            $params=@{Operation=$op;Stage=$phase}
            if($phase -cne 'PrepareIntent'){$params.ArchivePst=$archive;$params.TargetFolderPath=$archiveFolderPath}
            if($phase -in @('SourceWitnessAnchored','MoveClaimed','MoveReturned')){$params.WitnessSha256=$witnessSha}
            if($phase -ceq 'MoveReturned'){$params.ArchiveEntryId=$destId}
            $returned=Write-OPA265ARCH3dSyntheticBoundary @params
        }
        $fixture=[pscustomobject]@{
            Id=$id;Source=$src;OriginalFolder=$originalFolder;Operation=$op;Witness=$attachmentWitness;
            ArchiveStore=$store;Namespace=$ns;ArchiveItem=$item;ArchiveFolder=$archiveFolder;
            Root=[IO.Path]::GetDirectoryName($src);ExpectedSubject=$subject;ReceiptSha256=$returned.Sha256
            IndexPath=(Get-OPADuplicateIndexJournalPath -ArchivePst $archive)
        }
        $script:fixtures.Add($fixture)|Out-Null
        return $fixture
    }
    function Get-ARCH3eParams {
        param([object]$Fixture)
        return @{
            Operation=$Fixture.Operation
            ReceiptSha256=$Fixture.ReceiptSha256
            SourceSemanticWitness=$Fixture.Witness
            Namespace=$Fixture.Namespace
            SourceFolder=$Fixture.OriginalFolder
            ArchiveStore=$Fixture.ArchiveStore
            OriginalProcessId=101
            ReopenedProcessId=202
            ExpectedSubject=$Fixture.ExpectedSubject
        }
    }
}
AfterAll {
    if(Get-Command Close-OPADuplicateJournalStreams -ErrorAction SilentlyContinue){Close-OPADuplicateJournalStreams}
    foreach($f in @($script:fixtures.ToArray())){
        if([IO.Directory]::Exists([string]$f.Root)){
            Remove-Item -LiteralPath ([string]$f.Root) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
Describe 'ARCH3e original ArchiveVerifier post-restart model gate' {
    BeforeEach {
        $script:f=New-ARCH3eFixture
        Mock Get-OPA265ARCH2bMailSemanticWitness { return $script:f.Witness }
        Mock Release-OPAComObject {}
    }
    It 'keeps original full source witness schema authoritative (not Subject+Size)' {
        (Test-OPA265ARCH2bWitnessSchema -Witness $script:f.Witness) | Should -BeTrue
        $script:f.Witness.BodySha256 | Should -Match '^[a-f0-9]{64}$'
        $script:f.Witness.HtmlBodySha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'actual ORIGINAL ArchiveVerifier verifies one fake item and zero source after fake restart' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $r=Test-OPA265ARCH3eOriginalVerifierGate @x
        $r.Status | Should -BeExactly 'SyntheticOriginalVerifierSemanticMatchNotLiveCertified'
        $r.OriginalArchiveVerifierUsed | Should -BeTrue
        $r.AllOriginalSemanticsMatched | Should -BeTrue
        $r.RealOutlookRestartProven | Should -BeFalse
    }
    It 'wrong external receipt SHA prevents verification' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $x.ReceiptSha256='0'*64
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'same fake Outlook process ID blocks restart claim' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $x.ReopenedProcessId=$x.OriginalProcessId
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'original archive verifier refuses source mail still present' {
        $script:f.OriginalFolder.Items.Count=1
        $script:f.OriginalFolder.Items | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param($i)
            [pscustomobject]@{EntryID='00000000E1878292411BC64291BD506DCEFD2A35040A3C00'}
        }
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects unknown extra destination item even when direct EntryID matches' {
        $script:f.ArchiveFolder.Items.Count=2
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects missing target archive item count' {
        $script:f.ArchiveFolder.Items.Count=0
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects changed original email Subject' {
        $script:f.ArchiveItem.Subject='TAMPERED'
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects changed original Body SHA even with unchanged Subject' {
        $destination=$script:f.Witness.PSObject.Copy()
        $destination.BodySha256='b'*64
        Mock Get-OPA265ARCH2bMailSemanticWitness {return $destination}
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects changed HtmlBody SHA even when Body SHA matches' {
        $destination=$script:f.Witness.PSObject.Copy()
        $destination.HtmlBodySha256='b'*64
        Mock Get-OPA265ARCH2bMailSemanticWitness {return $destination}
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects original source witness substituted after pinned MoveReturned' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $x.SourceSemanticWitness=$script:f.Witness.PSObject.Copy()
        $x.SourceSemanticWitness.ToSha256='b'*64
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects fake archive location not matching original year PST part' {
        $script:f.ArchiveStore.FilePath=Join-Path $script:f.Root 'other-mailbox.pst'
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects an EXISTING source PST, even inside synthetic TEMP' {
        [IO.File]::WriteAllText($script:f.Source,'DONOTOPEN')
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects an EXISTING archive PST, even inside synthetic TEMP' {
        [IO.File]::WriteAllText($script:f.ArchiveStore.FilePath,'DONOTOPEN')
        $x=Get-ARCH3eParams -Fixture $script:f
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects real non-PSCustomObject provider wrapper' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $x.Namespace=[IO.FileInfo]::new($script:f.Source)
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
    }
    It 'rejects incomplete or malformed original ARCH2b witness before any index write' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $x.SourceSemanticWitness=[pscustomobject]@{Schema='fake';ItemClass=43}
        {Test-OPA265ARCH3eOriginalVerifierGate @x} | Should -Throw
        [IO.File]::Exists($script:f.IndexPath) | Should -BeFalse
    }
    It 'never authorizes production or live PST verification from synthetic gate' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $r=Test-OPA265ARCH3eOriginalVerifierGate @x
        $r.ReadyForSyntheticIndexCommit | Should -BeTrue
        $r.ProductionReady | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
    }
}
Describe 'ARCH3e original OperationJournal and DuplicateIndex commit ONLY AFTER original verification' {
    BeforeEach {
        $script:f=New-ARCH3eFixture
        Mock Get-OPA265ARCH2bMailSemanticWitness {return $script:f.Witness}
        Mock Release-OPAComObject {}
    }
    It 'explicit synthetic index-write approval is mandatory' {
        $x=Get-ARCH3eParams -Fixture $script:f
        {Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x} | Should -Throw
        [IO.File]::Exists($script:f.IndexPath) | Should -BeFalse
    }
    It 'original post-restart fake verifier PASS allows original OperationJournal Reconciled then DuplicateIndex' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $c=Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite
        $c.Status | Should -BeExactly 'OriginalVerifierThenOriginalOperationJournalAndDuplicateIndexSyntheticLinkedNoLiveCertification'
        $c.DuplicateIndexCommitAfterVerification | Should -BeTrue
        $c.OriginalOperationJournalSha256 | Should -Match '^[a-f0-9]{64}$'
        $j=Read-OPAOperationJournal -Path (Join-Path $script:f.Operation.Root 'original-operation-journal.jsonl')
        $j.Events.Count | Should -Be 2
        $j.Events[0].Phase | Should -BeExactly 'Intent'
        $j.Events[1].Phase | Should -BeExactly 'Reconciled'
        $index=Import-OPADuplicateIndex -ArchivePst $script:f.ArchiveStore.FilePath
        (Test-OPADuplicateEntry -Index $index -SourceEntryId $script:f.Operation.EntryId).ArchiveEntryId | Should -BeExactly $script:f.ArchiveItem.EntryID
    }
    It 'synthetic commit cannot be retried after persisted independent review and index append' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $c=Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite
        $before=(Get-FileHash -LiteralPath $script:f.IndexPath -Algorithm SHA256).Hash
        {Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite} | Should -Throw
        (Get-FileHash -LiteralPath $script:f.IndexPath -Algorithm SHA256).Hash | Should -BeExactly $before
    }
    It 'source present blocks index and original Reconciled journal' {
        $script:f.OriginalFolder.Items.Count=1
        $script:f.OriginalFolder.Items | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param($i)
            [pscustomobject]@{EntryID='00000000E1878292411BC64291BD506DCEFD2A35040A3C00'}
        }
        $x=Get-ARCH3eParams -Fixture $script:f
        {Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite} | Should -Throw
        [IO.File]::Exists($script:f.IndexPath) | Should -BeFalse
        (Read-OPAOperationJournal -Path (Join-Path $script:f.Operation.Root 'original-operation-journal.jsonl')).Events.Count | Should -Be 1
    }
    It 'tampered Body witness blocks index and original Reconciled journal' {
        $destination=$script:f.Witness.PSObject.Copy()
        $destination.BodySha256='c'*64
        Mock Get-OPA265ARCH2bMailSemanticWitness {return $destination}
        $x=Get-ARCH3eParams -Fixture $script:f
        {Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite} | Should -Throw
        [IO.File]::Exists($script:f.IndexPath) | Should -BeFalse
    }
    It 'extra unknown destination item prevents original index append' {
        $script:f.ArchiveFolder.Items.Count=2
        $x=Get-ARCH3eParams -Fixture $script:f
        {Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite} | Should -Throw
        [IO.File]::Exists($script:f.IndexPath) | Should -BeFalse
    }
    It 'fake unchanged Outlook process ID cannot be promoted to Reconciled or indexed' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $x.ReopenedProcessId=$x.OriginalProcessId
        {Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite} | Should -Throw
        [IO.File]::Exists($script:f.IndexPath) | Should -BeFalse
    }
    It 'original journal corrupted before independent review cannot commit index' {
        [IO.File]::AppendAllText((Join-Path $script:f.Operation.Root 'original-operation-journal.jsonl'),'{"torn":')
        $x=Get-ARCH3eParams -Fixture $script:f
        {Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite} | Should -Throw
        [IO.File]::Exists($script:f.IndexPath) | Should -BeFalse
    }
    It 'pinned synthetic final seal links original journal and index disk bytes' {
        $x=Get-ARCH3eParams -Fixture $script:f
        $c=Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite
        $file=Join-Path $script:f.Operation.Root 'ARCH3e-IndexCommitted.json'
        $record=Read-OPA265ARCH3cPinnedJson -Path $file -ExpectedSha256 $c.FinalIndexSealSha256
        $record.OriginalOperationJournalSha256 | Should -BeExactly $c.OriginalOperationJournalSha256
        $record.OriginalDuplicateIndexJournalSha256 | Should -BeExactly $c.OriginalDuplicateIndexJournalSha256
        $record.FakeRestartOnly | Should -BeTrue
        $record.ProductionReady | Should -BeFalse
    }
    It 'original receipt is pinned and no index created for COM-indeterminate branch' {
        $x=Get-ARCH3eParams -Fixture $script:f
        [IO.File]::WriteAllText((Join-Path $script:f.Operation.Root 'MoveIndeterminate.json'),'FAKE')
        {Invoke-OPA265ARCH3eSyntheticVerifiedIndexCommit @x -ConfirmSyntheticIndexWrite} | Should -Throw
        [IO.File]::Exists($script:f.IndexPath) | Should -BeFalse
    }
}
Describe 'ARCH3e code and production safety fences' {
    It 'new adapter calls original full semantic ArchiveVerifier rather than copying or bypassing it' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3ePostRestartIndexGate.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Test-OPAArchiveMoves -Namespace'
        $s | Should -Match '-RequireSemanticWitness'
        $s | Should -Match 'Get-OPA265ARCH3ePinnedReceipt'
    }
    It 'new adapter uses ORIGINAL OperationJournal and DuplicateIndex append/readback' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3ePostRestartIndexGate.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Write-OPAOperationJournalEvent'
        $s | Should -Match 'Add-OPADuplicateEntry'
        $s | Should -Match 'Sync-OPADuplicateJournalStreams'
    }
    It 'does not touch existing real Outlook or PST writers' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3ePostRestartIndexGate.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match 'GetActiveObject|New-Object -ComObject|AddStoreEx|\.Move\('
        $s | Should -Not -Match 'Save-OPAArchiveTransaction'
        $m=Get-Content -LiteralPath (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $m | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
    }
}
