#requires -Version 5.1
# ARCH3l isolated original MailMover fake COM and Part2 preclaim tests.
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3cDurableOperationLedger.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3dOriginalMoverBoundary.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3lOriginalPart2SyntheticGate.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3mOriginalPart2PreAllocation.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3nPinnedRealIntentBridge.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveTransaction.ps1')
    . (Join-Path $script:root 'Core/Archive/DuplicateIndex.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH2bSemanticWitness.ps1')
    if(-not (Get-Command Release-OPAComObject -ErrorAction SilentlyContinue)){
        function Release-OPAComObject {param([object]$Object)}
    }
    $script:fixtures=New-Object 'System.Collections.Generic.List[object]'
    $script:run='9d276dc4-a0e6-4e74-891f-81502fafe7db'
    $script:intentSha='f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b'
    $script:journalSha='a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'
    $script:realId='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    function New-ARCH3nFakePinned {
        param([string]$Root)
        $source=Join-Path $Root 'info@stios.ru.pst'
        $part1=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 1
        [IO.File]::WriteAllBytes($part1,(New-Object byte[] 271360))
        $part2=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 2
        $intent=[pscustomobject]@{
            RunId=$script:run;ExistingArchivePart1=$part1;NewArchivePst=$part2
            PlannedTargetFolderPath='2020\Входящие'
            OriginalContractSha256='2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
            FullOriginalWitnessSha256='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
            SourceEntryId=$script:realId;SourceStoreIdSha256=('c'*64)
            SourceFolderEntryId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
            SourceSealRunId='3773bcd7-5a07-4c31-8ce5-dfb16ddd30bf'
            SourceSealSha256='5f5a86b6c1aba8a3d2ee328a36a5632f8edf1e89fdda8e7fd728688fe881b2a4'
            OperationId='ARCH3b-2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
            MoveClaimed=$false;WriterPermit=$false;LiveMovePerformed=$false
        }
        $sealed=[pscustomobject]@{
            SourcePst=$source;SourceEntryId=$script:realId
            SourceStoreIdSha256=('c'*64)
            SourceFolderEntryId=$intent.SourceFolderEntryId
            OriginalWitnessSha256=$intent.FullOriginalWitnessSha256
            ArchiveDateLocalTicks=([datetime]'2020-02-13T12:57:58').Ticks
        }
        return [pscustomobject]@{Intent=$intent;Sealed=$sealed;Layout=[pscustomobject]@{RunId=$script:run}}
    }
    function New-ARCH3nFakeSynthetic {
        param([string]$Dir)
        $src=Join-Path $Dir 'info@stios.ru.pst'
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3m.OriginalSyntheticPart2PreAllocation.1'
            Status='OriginalPart2SelectedBeforeAnyArchiveStoreOpen'
            OriginalPart1=(Get-OPAArchivePartPath -SourcePst $src -Year 2020 -Part 1)
            ForcedPart2=(Get-OPAArchivePartPath -SourcePst $src -Year 2020 -Part 2)
            FolderPath='2020\Входящие';Part=2;SyntheticOnly=$true
            PSTCreatedByGate=$false;ExistingPart1OpenedByGate=$false;WriterPermit=$false
        }
    }
    function New-ARCH3lFixture {
        $id='ARCH3D-SYNTHETIC-'+[guid]::NewGuid().ToString('N')
        $dir=Join-Path ([IO.Path]::GetTempPath()) $id
        $src=Join-Path $dir 'info@stios.ru.pst'
        [void][IO.Directory]::CreateDirectory($dir)
        $indexPath=Join-Path $dir 'test-existing-index.json'
        [IO.File]::WriteAllText($indexPath,'{"SchemaVersion":"1.2","Entries":[]}')
        $folder=[pscustomobject]@{Name='Входящие';FolderPath='\\POP3 Store\Входящие';EntryID='FAKE'}
        $ns=[pscustomobject]@{Synthetic=$true}
        $candidate=[pscustomobject]@{
            EntryID='00000000E1878292411BC64291BD506DCEFD2A35040A3C00'
            ArchiveDate=[datetime]'2020-02-12T12:30:00'
            ReceivedTime=[datetime]'2020-02-12T12:30:00'
            FolderName='Входящие'
            SourceFolderPath='\\POP3 Store\Входящие'
            FolderPath='\\POP3 Store\Входящие'
            Subject='ARCH3l SYNTHETIC';InternetMessageId='<synthetic@invalid>'
            Sender='synthetic@invalid';Size=[long]300
        }
        $tx=[pscustomobject]@{
            TransactionId=$id;Path=(Join-Path $dir 'transaction.json')
            State=[pscustomobject]@{
                SourcePst=$src;SourceStoreId='ARCH3D-SYNTHETIC-NOT-REAL-STORE'
                ArchiveGrouping='Year';AccountEmail='info@stios.ru'
                PlannedItems=@();Planned=0;Executed=0;Verified=0;Skipped=0
                SkippedItems=@();SkippedEntryIds=@()
                ArchivePsts=@();CurrentArchivePst='';ArchivePst=''
                OlderThanMonths=12;ArchiveCutoff='';Limit=1;LogicalFreedBytes=[long]0
                Updated='';Steps=@()
            }
        }
        $scope=Assert-OPA265ARCH3dSyntheticBoundary -Namespace $ns -Transaction $tx -SourceFolders @($folder)
        $part1=Get-OPAArchivePartPath -SourcePst $src -Year 2020 -Part 1
        $part2=Get-OPAArchivePartPath -SourcePst $src -Year 2020 -Part 2
        $parts=@([pscustomobject]@{Path=$part1;Year=2020;Part=1})
        $op=Get-OPA265ARCH3dOperationIdentity -Scope $scope -Candidate $candidate -ArchiveGrouping Year
        $script:fixtures.Add($dir)|Out-Null
        return [pscustomobject]@{Id=$id;Root=$dir;Source=$src;Folder=$folder;Namespace=$ns;Candidate=$candidate;Transaction=$tx;Scope=$scope;Part1=$part1;Part2=$part2;Parts=$parts;Operation=$op;IndexPath=$indexPath}
    }
}
AfterAll {
    foreach($dir in @($script:fixtures.ToArray())){
        if([IO.Directory]::Exists([string]$dir)){Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    }
}


Describe 'ARCH3n real pinned original prepared Intent evidence is read-only and anti-tamper' {
    BeforeEach {
        $script:p=New-ARCH3nFakePinned -Root $TestDrive
        Mock Assert-OPA265ARCH3kPinnedPreparation {return $script:p}
        Mock Assert-OPA265ARCH3fRealTestSource {return $script:p.Sealed.SourcePst}
        Mock Get-OPAArchivePstPartsOnDisk {return @([pscustomobject]@{Path=$script:p.Intent.ExistingArchivePart1;Year=2020;Part=1})}
        Mock Clear-OPAArchivePartCache {}
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$true;EntryCount=500}}
        Mock Get-OPA265ARCH3kOriginalMoverUnsafeDefaultMarkers {return [pscustomobject]@{OriginalMailMoverSha256=('a'*64)}}
    }
    It 'binds exact immutable operator Intent, original journal, ARCH3i witness, Part1 and Part2 without any PST writes' {
        $r=Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha
        $r.Status | Should -BeExactly 'OriginalRealIntentAndForcedPart2SyntheticBridgeReadyNoLiveWriter'
        $r.UnusedPart2 | Should -BeExactly $script:p.Intent.NewArchivePst
        $r.SourceEntryId | Should -BeExactly $script:realId
        $r.OriginalSharedIndexEntryCount | Should -Be 500
        $r.RealPart2OpenedOrCreated | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'rejects a different RunId BEFORE reading original evidence' {
        {Get-OPA265ARCH3nPinnedRealRoute -RunId ([guid]::NewGuid().ToString('D')) -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
        Should -Invoke Assert-OPA265ARCH3kPinnedPreparation -Exactly -Times 0
    }
    It 'rejects rebaselined original Intent SHA before opening any PST' {
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 ('a'*64) -JournalSha256 $script:journalSha} | Should -Throw
        Should -Invoke Assert-OPA265ARCH3kPinnedPreparation -Exactly -Times 0
    }
    It 'rejects changed original OperationJournal SHA without unsafe retry' {
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 ('b'*64)} | Should -Throw
    }
    It 'rejects occupied real Part2 and never selects Part3' {
        [IO.File]::WriteAllText($script:p.Intent.NewArchivePst,'occupied')
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects changed existing Part1 size' {
        [IO.File]::AppendAllText($script:p.Intent.ExistingArchivePart1,'tamper')
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects original sealed semantic witness SHA drift' {
        $script:p.Sealed.OriginalWitnessSha256=('f'*64)
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects a tampered original routing contract SHA' {
        $script:p.Intent.OriginalContractSha256=('a'*64)
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects a duplicate source already in original index' {
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$false;EntryCount=500}}
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects altered original shared index entry count' {
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$true;EntryCount=501}}
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects already claimed or authorized real intent without trusting it' {
        $script:p.Intent.MoveClaimed=$true
        {Get-OPA265ARCH3nPinnedRealRoute -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
}
Describe 'ARCH3n pure original synthetic/real Part2 mapping has no Move permit' {
    BeforeEach {
        $script:p=New-ARCH3nFakePinned -Root $TestDrive
        $script:fakeDir=Join-Path $TestDrive 'isolated-fake'
        [void][IO.Directory]::CreateDirectory($script:fakeDir)
        $script:realPlan=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3n.PinnedRealIntentReadOnlyRoute.1'
            Status='OriginalRealIntentAndForcedPart2SyntheticBridgeReadyNoLiveWriter'
            RunId=$script:run;IntentSha256=$script:intentSha;JournalSha256=$script:journalSha
            SourceSealSha256='5f5a86b6c1aba8a3d2ee328a36a5632f8edf1e89fdda8e7fd728688fe881b2a4'
            OriginalWitnessSha256='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
            OriginalContractSha256='2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
            SourceEntryId=$script:realId;OriginalTargetFolder='2020\Входящие'
            ExistingPart1=$script:p.Intent.ExistingArchivePart1
            UnusedPart2=$script:p.Intent.NewArchivePst
            ExistingPart1LengthBytes=[long]271360
            OriginalSharedIndexEntryCount=500
            PreparedOriginalJournalIntentVerified=$true;FullOriginalWitnessVerified=$true;OriginalDuplicateIndexReadOnly=$true
            WriterPermit=$false;MoveClaimed=$false;RealPart2OpenedOrCreated=$false;ProductionReady=$false
        }
        $script:fakePlan=New-ARCH3nFakeSynthetic -Dir $script:fakeDir
        $script:candidate=[pscustomobject]@{EntryID=$script:realId;ArchiveDate=[datetime]'2020-02-13T12:57:58'}
    }
    It 'accepts exact original Part2 naming in a DIFFERENT fake directory and returns no writer permission' {
        $r=Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $script:realPlan -SyntheticPreAllocation $script:fakePlan -SyntheticCandidate $script:candidate
        $r.SyntheticOnly | Should -BeTrue
        $r.MoveClaimed | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.RealOriginalIntentSha256 | Should -BeExactly $script:intentSha
    }
    It 'rejects forged modified real witness SHA' {
        $script:realPlan.OriginalWitnessSha256=('e'*64)
        {Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $script:realPlan -SyntheticPreAllocation $script:fakePlan -SyntheticCandidate $script:candidate} | Should -Throw
    }
    It 'rejects forged modified original contract SHA' {
        $script:realPlan.OriginalContractSha256=('e'*64)
        {Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $script:realPlan -SyntheticPreAllocation $script:fakePlan -SyntheticCandidate $script:candidate} | Should -Throw
    }
    It 'rejects synthetic Part1 selected instead of new Part2' {
        $script:fakePlan.ForcedPart2=$script:fakePlan.OriginalPart1
        {Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $script:realPlan -SyntheticPreAllocation $script:fakePlan -SyntheticCandidate $script:candidate} | Should -Throw
    }
    It 'rejects fake Part2 with matching real path instead of isolated TEMP' {
        $script:fakePlan.ForcedPart2=$script:realPlan.UnusedPart2
        {Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $script:realPlan -SyntheticPreAllocation $script:fakePlan -SyntheticCandidate $script:candidate} | Should -Throw
    }
    It 'rejects different real SourceEntryId in fake original MailMover operation' {
        $script:candidate.EntryID='00000000FFFFFFFFFFFFFFFFFFFFFFFF'
        {Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $script:realPlan -SyntheticPreAllocation $script:fakePlan -SyntheticCandidate $script:candidate} | Should -Throw
    }
    It 'rejects forged real writer permission and fake scope that authorizes writes' {
        $script:realPlan.WriterPermit=$true
        {Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $script:realPlan -SyntheticPreAllocation $script:fakePlan -SyntheticCandidate $script:candidate} | Should -Throw
    }
    It 'rejects wrong original nested Year folder' {
        $script:fakePlan.FolderPath='2020\Отправленные'
        {Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $script:realPlan -SyntheticPreAllocation $script:fakePlan -SyntheticCandidate $script:candidate} | Should -Throw
    }
}
Describe 'ARCH3n standalone public modes and original destination binding gate' {
    It 'public script exposes only Plan/Audit, never real Move/Resume/Auto' {
        $source=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3n.ps1') -Raw -Encoding UTF8
        $source | Should -Match "ValidateSet\('Plan','Audit'\)"
        $source | Should -Not -Match "ValidateSet\('Plan','Audit','Move'"
    }
    It 'original destination refuses unscoped synthetic real Intent in generic live path' {
        $f=New-ARCH3lFixture
        $fake=[pscustomobject]@{Schema='2.6.5-ARCH3n.PinnedRealIntentReadOnlyRoute.1'}
        {Get-OPAArchiveDestination -Namespace $f.Namespace -Transaction $f.Transaction -SourcePst $f.Source -ReceivedTime $f.Candidate.ReceivedTime -ItemSize 200 -ArchiveGrouping Year -SourceFolderName 'Входящие' -SourceFolderPath $f.Folder.FolderPath -AccountEmail 'info@stios.ru' -ARCH3nSyntheticRealIntentBinding $fake} | Should -Throw
        [IO.File]::Exists($f.Part2) | Should -BeFalse
    }
    It 'audit fails on mismatched live source state returned by original ARCH3k before any writer call' {
        Mock Get-OPA265ARCH3nPinnedRealRoute {
            return [pscustomobject]@{
                Schema='2.6.5-ARCH3n.PinnedRealIntentReadOnlyRoute.1';RunId=$script:run
                SourceEntryId=$script:realId;OriginalWitnessSha256='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
                OriginalContractSha256='2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
                ExistingPart1='C:\fake\part1.pst';UnusedPart2='C:\fake\part2.pst';OriginalSharedIndexEntryCount=500
            }
        }
        Mock Invoke-OPA265ARCH3kLiveReadOnlyBoundary {return [pscustomobject]@{Status='Incorrect';WriterPermit=$false}}
        {Invoke-OPA265ARCH3nReadOnly -Mode Audit -RunId $script:run -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
}
