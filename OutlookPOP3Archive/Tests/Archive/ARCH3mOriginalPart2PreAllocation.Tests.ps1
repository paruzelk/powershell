#requires -Version 5.1
# ARCH3l isolated original MailMover fake COM and Part2 preclaim tests.
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3cDurableOperationLedger.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3dOriginalMoverBoundary.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3lOriginalPart2SyntheticGate.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3mOriginalPart2PreAllocation.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveTransaction.ps1')
    . (Join-Path $script:root 'Core/Archive/DuplicateIndex.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH2bSemanticWitness.ps1')
    if(-not (Get-Command Release-OPAComObject -ErrorAction SilentlyContinue)){
        function Release-OPAComObject {param([object]$Object)}
    }
    $script:fixtures=New-Object 'System.Collections.Generic.List[object]'
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

Describe 'ARCH3m original selection before PST allocation is fake-only' {
    BeforeEach {
        $script:f=New-ARCH3lFixture
        $script:newPstCalls=0;$script:registerCalls=0;$script:folderCalls=0
        $script:openedParts=New-Object 'System.Collections.Generic.List[string]'
        Mock New-OPAArchivePst {
            $script:newPstCalls++
            $script:openedParts.Add([string]$ArchivePst) | Out-Null
            return [pscustomobject]@{StoreID='ARCH3M-FAKE-NEW-STORE';FilePath=[string]$ArchivePst}
        }
        Mock Register-OPAArchivePstInTransaction {$script:registerCalls++}
        Mock Get-OPAArchiveFolder {
            $script:folderCalls++
            return [pscustomobject]@{FolderPath='\\Synthetic Archive\2020\Входящие';StoreID='ARCH3M-FAKE-NEW-STORE';EntryID='00000000CAFEBABECAFEBABECAFEBABE'}
        }
        Mock Get-OPAArchivePstSizeBytes {return [long]0}
        Mock Clear-OPAArchivePartCache {}
        Mock Get-OPAArchivePstPartsOnDisk {return @($script:f.Parts)}
    }
    It 'returns exact original Part2 before any COM or PST call in the read-only gate' {
        $r=Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'
        $r.ForcedPart2 | Should -BeExactly $script:f.Part2
        $r.ExistingPart1OpenedByGate | Should -BeFalse
        $r.PSTCreatedByGate | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $script:newPstCalls | Should -Be 0
        $script:registerCalls | Should -Be 0
    }
    It 'routes original Get-OPAArchiveDestination directly to Part2, never opening Part1' {
        $r=Get-OPAArchiveDestination -Namespace $script:f.Namespace -Transaction $script:f.Transaction -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -ItemSize 300 -ArchiveGrouping Year -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru' -ARCH3mSyntheticPart2Scope $script:f.Scope -ARCH3mSyntheticCandidate $script:f.Candidate -ARCH3mSyntheticExistingParts $script:f.Parts
        $r.Path | Should -BeExactly $script:f.Part2
        $r.Part | Should -Be 2
        $r.Folder.FolderPath | Should -BeExactly '\\Synthetic Archive\2020\Входящие'
        $script:newPstCalls | Should -Be 1
        $script:registerCalls | Should -Be 1
        $script:folderCalls | Should -Be 1
        $script:openedParts.ToArray() | Should -Be @($script:f.Part2)
        [IO.File]::Exists($script:f.Part2) | Should -BeFalse
    }
    It 'refuses a second destination allocation with the same transaction without retry' {
        $q=@{Namespace=$script:f.Namespace;Transaction=$script:f.Transaction;SourcePst=$script:f.Source;ReceivedTime=$script:f.Candidate.ReceivedTime;ItemSize=300;ArchiveGrouping='Year';SourceFolderName='Входящие';SourceFolderPath=$script:f.Folder.FolderPath;AccountEmail='info@stios.ru';ARCH3mSyntheticPart2Scope=$script:f.Scope;ARCH3mSyntheticCandidate=$script:f.Candidate;ARCH3mSyntheticExistingParts=$script:f.Parts}
        [void](Get-OPAArchiveDestination @q)
        {Get-OPAArchiveDestination @q} | Should -Throw
        $script:newPstCalls | Should -Be 1
    }
    It 'rejects an existing Part2 before the original allocation function is called' {
        [IO.File]::WriteAllText($script:f.Part2,'occupied')
        {Get-OPAArchiveDestination -Namespace $script:f.Namespace -Transaction $script:f.Transaction -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -ItemSize 300 -ArchiveGrouping Year -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru' -ARCH3mSyntheticPart2Scope $script:f.Scope -ARCH3mSyntheticCandidate $script:f.Candidate -ARCH3mSyntheticExistingParts $script:f.Parts} | Should -Throw
        $script:newPstCalls | Should -Be 0
    }
    It 'rejects REAL source PST before any allocation' {
        [IO.File]::WriteAllText($script:f.Source,'real path must fail closed')
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'} | Should -Throw
        $script:newPstCalls | Should -Be 0
    }
    It 'rejects COM-like Namespace instead of the PSCustomObject-only original fake' {
        $bad=[IO.FileInfo]::new($script:f.Source)
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $bad -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'} | Should -Throw
        $script:newPstCalls | Should -Be 0
    }
    It 'rejects a forged scope which authorizes real Outlook' {
        $script:f.Scope.RealOutlookObjectAllowed=$true
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'} | Should -Throw
    }
    It 'rejects an altered source StoreID' {
        $script:f.Transaction.State.SourceStoreId='real-store'
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'} | Should -Throw
    }
    It 'rejects two initial Year parts instead of reusing the third' {
        $parts=@($script:f.Parts[0],([pscustomobject]@{Part=2;Year=2020;Path=$script:f.Part2}))
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'} | Should -Throw
    }
    It 'rejects mismatched real-like on-disk Year part topology' {
        Mock Get-OPAArchivePstPartsOnDisk {return @([pscustomobject]@{Part=3;Year=2020;Path='C:\unexpected.pst'})}
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'} | Should -Throw
    }
    It 'rejects changed original year and source folder' {
        $script:f.Candidate.ArchiveDate=[datetime]'2021-02-12'
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'} | Should -Throw
    }
    It 'rejects wrong original POP3 account before allocation' {
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'other@example.invalid'} | Should -Throw
    }
    It 'rejects already registered archive part before allocation' {
        $script:f.Transaction.State.ArchivePsts=@([pscustomobject]@{Year=2020;Part=1;Path=$script:f.Part1})
        {Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $script:f.Namespace -Transaction $script:f.Transaction -Scope $script:f.Scope -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru'} | Should -Throw
    }
    It 'stops oversize messages before any allocation' {
        {Get-OPAArchiveDestination -Namespace $script:f.Namespace -Transaction $script:f.Transaction -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -ItemSize ([long](9*1GB)) -MaxArchivePstSizeGB 1 -SafetyMarginGB 0.5 -ArchiveGrouping Year -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru' -ARCH3mSyntheticPart2Scope $script:f.Scope -ARCH3mSyntheticCandidate $script:f.Candidate -ARCH3mSyntheticExistingParts $script:f.Parts} | Should -Throw
        $script:newPstCalls | Should -Be 0
    }
    It 'rejects a wrong year folder after mocked original allocation' {
        Mock Get-OPAArchiveFolder {[pscustomobject]@{FolderPath='\\Fake Archive\2020\Отправленные';EntryID='FAKE'}}
        {Get-OPAArchiveDestination -Namespace $script:f.Namespace -Transaction $script:f.Transaction -SourcePst $script:f.Source -ReceivedTime $script:f.Candidate.ReceivedTime -ItemSize 300 -ArchiveGrouping Year -SourceFolderName 'Входящие' -SourceFolderPath $script:f.Folder.FolderPath -AccountEmail 'info@stios.ru' -ARCH3mSyntheticPart2Scope $script:f.Scope -ARCH3mSyntheticCandidate $script:f.Candidate -ARCH3mSyntheticExistingParts $script:f.Parts} | Should -Throw
    }
}
Describe 'ARCH3m entire original MailMover durable fake Move chain with preallocation forced Part2' {
    BeforeEach {
        $script:f=New-ARCH3lFixture
        $script:fakeMail=[pscustomobject]@{EntryID=[string]$script:f.Candidate.EntryID;Class=43;Calls=0}
        $script:fakeMail | Add-Member -MemberType ScriptMethod -Name Move -Value {
            param($dest)
            $this.Calls++
            return [pscustomobject]@{EntryID='00000000FEDCBA9876543210FEDCBA987654321000000001'}
        }
        $script:forcedPstCalls=0;$script:originalIndexSyncCalls=0;$script:duplicateAppendCalls=0;$script:partsOpened=@()
        Mock Get-OPAArchivePstPartsOnDiskAll {@($script:f.Parts)}
        Mock Get-OPAArchivePstPartsOnDisk {@($script:f.Parts)}
        Mock Get-OPADuplicateIndexPath {$script:f.IndexPath}
        Mock Get-OPADuplicateIndexJournalPath {Join-Path $script:f.Root 'nonexistent.jsonl'}
        Mock Import-OPADuplicateIndex {[pscustomobject]@{ArchivePst=$script:f.Part1;Entries=@()}}
        Mock Sync-OPADuplicateIndexFromJournal {$script:originalIndexSyncCalls++;throw 'DO NOT mutate original index'}
        Mock Get-OPAArchiveCandidates {@($script:f.Candidate)}
        Mock Get-OPASourceFolderByPath {$script:f.Folder}
        Mock Get-OPAItemByEntryIdFromSourceFolder {$script:fakeMail}
        Mock New-OPAArchivePst {
            $script:forcedPstCalls++
            $script:partsOpened+= [string]$ArchivePst
            return [pscustomobject]@{StoreID='FAKE-ARCH3M-PART2';FilePath=[string]$ArchivePst}
        }
        Mock Register-OPAArchivePstInTransaction {}
        Mock Get-OPAArchiveFolder {[pscustomobject]@{FolderPath='\\Synthetic Archive\2020\Входящие';EntryID='1234FAKE'}}
        Mock Get-OPAArchivePstSizeBytes {[long]0}
        Mock Clear-OPAArchivePartCache {}
        Mock Get-OPAArchiveSafeCapacityBytes {[long]999999999}
        Mock Get-OPAArchivePstGrowthRatio {return 2.0}
        Mock Test-OPADuplicateEntry {$null}
        Mock Get-OPA265ARCH2bMailSemanticWitness {[pscustomobject]@{Original='SYNTHETIC';ContentSha256=('a'*64)}}
        Mock Save-OPAArchiveTransaction {}
        Mock Sync-OPAStepJournalStreams {}
        Mock Add-OPADuplicateEntry {$script:duplicateAppendCalls++}
        Mock Release-OPAComObject {}
    }
    It 'forces original Part2 before synthetic one-time Move and leaves original DuplicateIndex unchanged' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary -ARCH3mSyntheticForcePart2} | Should -Throw '*ARCH3d SYNTHETIC STOP*'
        $script:fakeMail.Calls | Should -Be 1
        $script:forcedPstCalls | Should -Be 1
        $script:partsOpened | Should -Be @($script:f.Part2)
        $script:originalIndexSyncCalls | Should -Be 0
        $script:duplicateAppendCalls | Should -Be 0
        Test-Path -LiteralPath $script:f.Part2 | Should -BeFalse
        $journal=Join-Path $script:f.Operation.Root 'original-operation-journal.jsonl'
        $e=Read-OPAOperationJournal -Path $journal
        $e.Events[0].Phase | Should -BeExactly 'Intent'
        foreach($phase in @('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned')){
            Test-Path -LiteralPath (Join-Path $script:f.Operation.Root ($phase+'.json')) | Should -BeTrue
        }
    }
    It 'rejects replay after first fake MoveReturned with zero second provider calls' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary -ARCH3mSyntheticForcePart2} | Should -Throw
        $script:fakeMail.Calls | Should -Be 1
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary -ARCH3mSyntheticForcePart2} | Should -Throw
        $script:fakeMail.Calls | Should -Be 1
    }
    It 'rejects synthetic Part2 force without ARCH3d and ARCH3l before any PST access' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3mSyntheticForcePart2} | Should -Throw
        $script:forcedPstCalls | Should -Be 0
    }
    It 'rejects wrong target folder after original New-OPAArchivePst before fake MoveClaimed' {
        Mock Get-OPAArchiveFolder {[pscustomobject]@{FolderPath='\\Synthetic Archive\2020\Отправленные';EntryID='FAKE'}}
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary -ARCH3mSyntheticForcePart2} | Should -Throw
        $script:fakeMail.Calls | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:f.Operation.Root 'MoveClaimed.json') | Should -BeFalse
    }
    It 'does not allow actual COM-like Namespace via synthetic scope' {
        $actualLike=[IO.FileInfo]::new($script:f.Source)
        {Move-OPAItemsWithLimit -Namespace $actualLike -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary -ARCH3mSyntheticForcePart2} | Should -Throw
        $script:forcedPstCalls | Should -Be 0
    }
    It 'rejects wrong year or Resume under forced Part2 flag before original destination call' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping YearQuarter -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary -ARCH3mSyntheticForcePart2} | Should -Throw
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -Resume -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary -ARCH3mSyntheticForcePart2} | Should -Throw
        $script:forcedPstCalls | Should -Be 0
    }
    It 'forbids source-content byte drift before claimed fake Move' {
        Mock Get-OPA265ARCH2bMailSemanticWitness {throw 'synthetic full witness capture failed'}
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary -ARCH3mSyntheticForcePart2} | Should -Throw
        $script:fakeMail.Calls | Should -Be 0
    }
}
