#requires -Version 5.1
# ARCH3l isolated original MailMover fake COM and Part2 preclaim tests.
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3cDurableOperationLedger.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3dOriginalMoverBoundary.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3lOriginalPart2SyntheticGate.ps1')
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
Describe 'ARCH3l original Year2020 Part2 preprovider synthetic gate' {
    BeforeEach {$script:f=New-ARCH3lFixture}
    It 'uses original Year part filename not hand-built destination' {
        $r=Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts
        $r.RequiredNewPart2 | Should -BeExactly $script:f.Part2
        $r.OriginalPart1 | Should -BeExactly $script:f.Part1
        $r.OriginalTargetFolder | Should -BeExactly '2020\Входящие'
        $r.ExistingSharedIndexSyncAllowed | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
    }
    It 'accepts exactly part2 and the ORIGINAL nested Year Inbox path' {
        $dst=[pscustomobject]@{Path=$script:f.Part2;Folder=[pscustomobject]@{FolderPath='\\Synthetic Archive\2020\Входящие'}}
        $r=Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -Stage DestinationReady -Destination $dst
        $r.Status | Should -BeExactly 'OriginalPart2AndTargetValidatedBeforeProviderClaim'
    }
    It 'rejects existing Part1 as a destination even when original normal selection fits' {
        $dst=[pscustomobject]@{Path=$script:f.Part1;Folder=[pscustomobject]@{FolderPath='\\Synthetic Archive\2020\Входящие'}}
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -Stage DestinationReady -Destination $dst} | Should -Throw
    }
    It 'rejects Part3 as destination without silent rollover' {
        $dst=[pscustomobject]@{Path=(Get-OPAArchivePartPath -SourcePst $script:f.Source -Year 2020 -Part 3);Folder=[pscustomobject]@{FolderPath='\\Synthetic Archive\2020\Входящие'}}
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -Stage DestinationReady -Destination $dst} | Should -Throw
    }
    It 'rejects wrong nested destination folder name' {
        $dst=[pscustomobject]@{Path=$script:f.Part2;Folder=[pscustomobject]@{FolderPath='\\Synthetic Archive\2020\Отправленные'}}
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -Stage DestinationReady -Destination $dst} | Should -Throw
    }
    It 'rejects absent or multiple pre-existing Part1 inputs' {
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts @()} | Should -Throw
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts @($script:f.Parts[0],$script:f.Parts[0])} | Should -Throw
    }
    It 'rejects existing part2 file even in synthetic test directory' {
        [IO.File]::WriteAllText($script:f.Part2,'occupied')
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts} | Should -Throw
    }
    It 'refuses a REAL source PST file in synthetic TEMP directory' {
        [IO.File]::WriteAllText($script:f.Source,'fake-but-existing')
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts} | Should -Throw
    }
    It 'rejects non-2020 source candidate' {
        $script:f.Candidate.ArchiveDate=[datetime]'2021-02-12'
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts} | Should -Throw
    }
    It 'rejects wrong transaction and source store evidence' {
        $script:f.Transaction.State.SourceStoreId='REAL-STORE'
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts} | Should -Throw
    }
    It 'rejects forged synthetic permission fields' {
        $script:f.Scope.RealOutlookObjectAllowed=$true
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts} | Should -Throw
    }
    It 'refuses Destination supplied before destination creation' {
        {Assert-OPA265ARCH3lSyntheticPart2 -Scope $script:f.Scope -Transaction $script:f.Transaction -Candidate $script:f.Candidate -ExistingArchiveParts $script:f.Parts -Destination ([pscustomobject]@{Path=$script:f.Part2})} | Should -Throw
    }
}
Describe 'ARCH3l integration inside original Move-OPAItemsWithLimit fake-only loop' {
    BeforeEach {
        $script:f=New-ARCH3lFixture
        $script:fakeMail=[pscustomobject]@{EntryID=[string]$script:f.Candidate.EntryID;Class=43;Calls=0}
        $script:fakeMail | Add-Member -MemberType ScriptMethod -Name Move -Value {
            param($destination)
            $this.Calls++
            return [pscustomobject]@{EntryID='00000000FEDCBA9876543210FEDCBA987654321000000001'}
        }
        $script:destPath=$script:f.Part2
        $script:destFolder='\\Synthetic Archive\2020\Входящие'
        $script:destCalls=0;$script:syncCalls=0;$script:indexWriteCalls=0
        Mock Get-OPAArchivePstPartsOnDiskAll {@($script:f.Parts)}
        Mock Get-OPADuplicateIndexPath {$script:f.IndexPath}
        Mock Get-OPADuplicateIndexJournalPath {Join-Path $script:f.Root 'nonexistent.jsonl'}
        Mock Import-OPADuplicateIndex {[pscustomobject]@{ArchivePst=$script:f.Part1;Entries=@()}}
        Mock Sync-OPADuplicateIndexFromJournal {$script:syncCalls++;throw 'Original index must NEVER be healed in ARCH3l'}
        Mock Get-OPAArchiveCandidates {@($script:f.Candidate)}
        Mock Get-OPASourceFolderByPath {$script:f.Folder}
        Mock Get-OPAItemByEntryIdFromSourceFolder {$script:fakeMail}
        Mock Get-OPAArchiveDestination {
            $script:destCalls++
            return [pscustomobject]@{Path=$script:destPath;Folder=[pscustomobject]@{FolderPath=$script:destFolder}}
        }
        Mock Get-OPAArchiveSafeCapacityBytes {[long]999999999}
        Mock Test-OPADuplicateEntry {$null}
        Mock Get-OPA265ARCH2bMailSemanticWitness {[pscustomobject]@{Original='SYNTHETIC-WITNESS';ContentSha256=('a'*64)}}
        Mock Save-OPAArchiveTransaction {}
        Mock Sync-OPAStepJournalStreams {}
        Mock Add-OPADuplicateEntry {$script:indexWriteCalls++}
        Mock Release-OPAComObject {}
    }
    It 'moves exactly one FAKE item via original loop into Part2 and seals returned receipt before index' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary} | Should -Throw '*ARCH3d SYNTHETIC STOP*'
        $script:fakeMail.Calls | Should -Be 1
        $script:destCalls | Should -Be 1
        $script:syncCalls | Should -Be 0
        $script:indexWriteCalls | Should -Be 0
        [IO.File]::Exists((Join-Path $script:f.Operation.Root 'MoveReturned.json')) | Should -BeTrue
        [IO.File]::Exists($script:f.Part2) | Should -BeFalse
    }
    It 'refuses classic Part1 selection before any fake provider Move or MoveClaimed' {
        $script:destPath=$script:f.Part1
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary} | Should -Throw
        $script:fakeMail.Calls | Should -Be 0
        $script:syncCalls | Should -Be 0
        $script:indexWriteCalls | Should -Be 0
        [IO.File]::Exists((Join-Path $script:f.Operation.Root 'MoveClaimed.json')) | Should -BeFalse
    }
    It 'refuses wrong target folder BEFORE fake provider Move' {
        $script:destFolder='\\Synthetic Archive\2020\Отправленные'
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary} | Should -Throw
        $script:fakeMail.Calls | Should -Be 0
    }
    It 'refuses after first fake provider outcome and never calls Move a second time' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary} | Should -Throw
        $script:fakeMail.Calls | Should -Be 1
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary} | Should -Throw
        $script:fakeMail.Calls | Should -Be 1
    }
    It 'rejects ARCH3l switch without ARCH3d before any Outlook/destination operation' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3lSyntheticPart2Boundary} | Should -Throw
        $script:destCalls | Should -Be 0
    }
    It 'rejects Resume and non-Year grouping before touching destination' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -Resume -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary} | Should -Throw
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping YearQuarter -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary} | Should -Throw
        $script:destCalls | Should -Be 0
    }
    It 'rejects a real COM-like namespace object through original ARCH3d boundary' {
        $obj=[IO.FileInfo]::new($script:f.Source)
        {Move-OPAItemsWithLimit -Namespace $obj -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary -ARCH3lSyntheticPart2Boundary} | Should -Throw
        $script:destCalls | Should -Be 0
    }
    It 'keeps old original Archive/Resume/Auto writer flags unchanged' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $m=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
        $m | Should -Match 'if\(\$ARCH3lSyntheticPart2Boundary\)'
        $m | Should -Match 'if\(-not \$ARCH3lSyntheticPart2Boundary\)'
        $m | Should -Match '\$moved = \$item.Move\(\$dest.Folder\)'
    }
}
