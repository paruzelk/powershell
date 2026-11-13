#requires -Version 5.1
# ARCH3d integrates hooks in the ORIGINAL MailMover. All moved items below
# are fake PSCustomObject test doubles; all evidence stays under OS TEMP.
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3cDurableOperationLedger.ps1')
    . (Join-Path $script:root 'Core/Archive/ARCH3dOriginalMoverBoundary.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveTransaction.ps1')
    $script:fixtures=New-Object 'System.Collections.Generic.List[object]'
    function New-ARCH3dFixture {
        $id='ARCH3D-SYNTHETIC-'+[guid]::NewGuid().ToString('N')
        $source=Join-Path (Join-Path ([IO.Path]::GetTempPath()) $id) 'info@stios.ru.pst'
        $folder=[pscustomobject]@{Name='Входящие';FolderPath='\\POP3 Store\Входящие';EntryID='FAKE'}
        $ns=[pscustomobject]@{Synthetic=$true}
        $candidate=[pscustomobject]@{
            EntryID='00000000E1878292411BC64291BD506DCEFD2A35040A3C00'
            ArchiveDate=[datetime]'2020-02-12T12:30:00'
            ReceivedTime=[datetime]'2020-02-12T12:30:00'
            FolderName='Входящие'
            SourceFolderPath='\\POP3 Store\Входящие'
            FolderPath='\\POP3 Store\Входящие'
            Subject='SYNTHETIC'
            InternetMessageId='<synthetic@invalid>'
            Sender='synthetic@invalid'
            Size=[int64]300
        }
        $transaction=[pscustomobject]@{
            TransactionId=$id
            Path=(Join-Path ([IO.Path]::GetDirectoryName($source)) 'transaction.json')
            State=[pscustomobject]@{
                SourcePst=$source
                SourceStoreId='ARCH3D-SYNTHETIC-NOT-REAL-STORE'
                ArchiveGrouping='Year'
                AccountEmail='info@stios.ru'
                PlannedItems=@()
                Planned=0;Executed=0;Verified=0;Skipped=0
                SkippedItems=@();SkippedEntryIds=@()
                ArchivePsts=@();CurrentArchivePst='';ArchivePst=''
                OlderThanMonths=12;ArchiveCutoff=''
                Limit=1;LogicalFreedBytes=[int64]0
                Updated='';Steps=@()
            }
        }
        $scope=Assert-OPA265ARCH3dSyntheticBoundary -Namespace $ns -Transaction $transaction -SourceFolders @($folder)
        $op=Get-OPA265ARCH3dOperationIdentity -Scope $scope -Candidate $candidate -ArchiveGrouping Year
        $dest=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 1
        $target='\\Synthetic Archive\2020\Входящие'
        $fixture=[pscustomobject]@{Id=$id;Root=[IO.Path]::GetDirectoryName($source);Source=$source;Folder=$folder;Namespace=$ns;Candidate=$candidate;Transaction=$transaction;Scope=$scope;Operation=$op;Destination=$dest;Target=$target}
        $script:fixtures.Add($fixture)|Out-Null
        return $fixture
    }
    function Step-ARCH3dFixture {
        param([object]$Fixture,[string]$Through='MoveReturned')
        $hash='a'*64
        foreach($phase in @('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned')){
            $s=@{Operation=$Fixture.Operation;Stage=$phase}
            if($phase -cne 'PrepareIntent'){
                $s.ArchivePst=$Fixture.Destination
                $s.TargetFolderPath=$Fixture.Target
            }
            if($phase -in @('SourceWitnessAnchored','MoveClaimed','MoveReturned')){$s.WitnessSha256=$hash}
            if($phase -eq 'MoveReturned'){$s.ArchiveEntryId='00000000FEDCBA9876543210FEDCBA987654321000000001'}
            $result=Write-OPA265ARCH3dSyntheticBoundary @s
            if($phase -ceq $Through){return $result}
        }
    }
}
AfterAll {
    foreach($f in @($script:fixtures.ToArray())){
        if([IO.Directory]::Exists([string]$f.Root)){
            Remove-Item -LiteralPath ([string]$f.Root) -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}
Describe 'ARCH3d real original MailMover integration hooks: protected scope, no actual PST' {
    It 'binds exact existing Year-folder and original POP3 source to one operation' {
        $f=New-ARCH3dFixture
        $f.Operation.OperationId | Should -Match '^ARCH3d-[a-f0-9]{64}$'
        $f.Operation.TargetFolderPath | Should -BeExactly '2020\Входящие'
        $f.Operation.SourcePst | Should -BeExactly $f.Source
    }
    It 'refuses existing source PST even inside TEMP' {
        $f=New-ARCH3dFixture
        [void][IO.Directory]::CreateDirectory($f.Root)
        [IO.File]::WriteAllText($f.Source,'FAKE')
        {Assert-OPA265ARCH3dSyntheticBoundary -Namespace $f.Namespace -Transaction $f.Transaction -SourceFolders @($f.Folder)} | Should -Throw
    }
    It 'refuses actual non-PSCustomObject namespace before any disk activity' {
        $f=New-ARCH3dFixture
        {Assert-OPA265ARCH3dSyntheticBoundary -Namespace ([IO.FileInfo]::new($f.Source)) -Transaction $f.Transaction -SourceFolders @($f.Folder)} | Should -Throw
        [IO.Directory]::Exists($f.Root) | Should -BeFalse
    }
    It 'refuses wrong StoreID and non TEMP original source' {
        $f=New-ARCH3dFixture
        $f.Transaction.State.SourceStoreId='REAL-STORE-DO-NOT-USE'
        {Assert-OPA265ARCH3dSyntheticBoundary -Namespace $f.Namespace -Transaction $f.Transaction -SourceFolders @($f.Folder)} | Should -Throw
    }
    It 'refuses non-canonical transaction marker before original legacy writer' {
        $f=New-ARCH3dFixture
        $f.Transaction.TransactionId='real-producer'
        {Assert-OPA265ARCH3dSyntheticBoundary -Namespace $f.Namespace -Transaction $f.Transaction -SourceFolders @($f.Folder)} | Should -Throw
    }
    It 'uses original Get-OPAArchiveTargetPath (nested user hierarchy retained)' {
        $f=New-ARCH3dFixture
        $f.Candidate.SourceFolderPath='\\POP3 Store\Проекты\Договоры'
        $f.Candidate.FolderName='Договоры'
        $x=Get-OPA265ARCH3dOperationIdentity -Scope $f.Scope -Candidate $f.Candidate -ArchiveGrouping Year
        $x.TargetFolderPath | Should -BeExactly '2020\Проекты\Договоры'
    }
    It 'operation ID changes with original source EntryID' {
        $f=New-ARCH3dFixture
        $f.Candidate.EntryID='00000000AAAAAAAAAAAAAAAABBBBBBBB'
        $x=Get-OPA265ARCH3dOperationIdentity -Scope $f.Scope -Candidate $f.Candidate -ArchiveGrouping Year
        $x.OperationId | Should -Not -BeExactly $f.Operation.OperationId
    }
    It 'operation ID changes with original grouping and transaction ID' {
        $f=New-ARCH3dFixture
        $x=Get-OPA265ARCH3dOperationIdentity -Scope $f.Scope -Candidate $f.Candidate -ArchiveGrouping YearQuarter
        $x.OperationId | Should -Not -BeExactly $f.Operation.OperationId
    }
    It 'immutable pre-destination intent and original OperationJournal Intent are saved before destination' {
        $f=New-ARCH3dFixture
        $s=Step-ARCH3dFixture -Fixture $f -Through PrepareIntent
        $s.Sha256 | Should -Match '^[a-f0-9]{64}$'
        $j=Read-OPAOperationJournal -Path (Join-Path $f.Operation.Root 'original-operation-journal.jsonl')
        $j.Events.Count | Should -Be 1
        $j.Events[0].Phase | Should -BeExactly 'Intent'
        $j.Events[0].OperationId | Should -BeExactly $f.Operation.OperationId
    }
    It 'duplicate pre-destination intent is NEVER written or allowed as retry' {
        $f=New-ARCH3dFixture
        $a=Step-ARCH3dFixture -Fixture $f -Through PrepareIntent
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage PrepareIntent} | Should -Throw
        (Get-FileHash -LiteralPath $a.Path -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $a.Sha256
    }
    It 'destination cannot be created or claimed without durable preparatory intent' {
        $f=New-ARCH3dFixture
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage DestinationReady -ArchivePst $f.Destination -TargetFolderPath $f.Target} | Should -Throw
    }
    It 'must use exact original archive Year part filename' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through PrepareIntent)
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage DestinationReady -ArchivePst (Join-Path $f.Root 'WRONG.pst') -TargetFolderPath $f.Target} | Should -Throw
    }
    It 'allows original existing part-two rollover naming without rewriting it' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through PrepareIntent)
        $part=Get-OPAArchivePartPath -SourcePst $f.Source -Year 2020 -Part 2
        $s=Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage DestinationReady -ArchivePst $part -TargetFolderPath $f.Target
        $s.Stage | Should -BeExactly 'DestinationReady'
    }
    It 'rejects any destination outside synthetic TEMP' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through PrepareIntent)
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage DestinationReady -ArchivePst 'C:\Public\other.pst' -TargetFolderPath $f.Target} | Should -Throw
    }
    It 'rejects wrong original target folder even for valid Year PST' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through PrepareIntent)
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage DestinationReady -ArchivePst $f.Destination -TargetFolderPath '\2020\Другая'} | Should -Throw
    }
    It 'requires exact SHA256 of source witness before Move claim' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through DestinationReady)
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage SourceWitnessAnchored -ArchivePst $f.Destination -TargetFolderPath $f.Target -WitnessSha256 ''} | Should -Throw
    }
    It 'MoveClaimed cannot bypass SourceWitnessAnchored stage' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through DestinationReady)
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage MoveClaimed -ArchivePst $f.Destination -TargetFolderPath $f.Target -WitnessSha256 ('a'*64)} | Should -Throw
    }
    It 'one immutable MoveClaimed persists; retry cannot overwrite it' {
        $f=New-ARCH3dFixture
        $s=Step-ARCH3dFixture -Fixture $f -Through MoveClaimed
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage MoveClaimed -ArchivePst $f.Destination -TargetFolderPath $f.Target -WitnessSha256 ('a'*64)} | Should -Throw
        $s.Sha256 | Should -BeExactly ((Get-FileHash -LiteralPath $s.Path -Algorithm SHA256).Hash.ToLowerInvariant())
    }
    It 'MoveReturned without original destination EntryID must fail closed' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through MoveClaimed)
        {Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage MoveReturned -ArchivePst $f.Destination -TargetFolderPath $f.Target -WitnessSha256 ('a'*64)} | Should -Throw
    }
    It 'MoveReturned evidence requires externally pinned receipt SHA' {
        $f=New-ARCH3dFixture
        $s=Step-ARCH3dFixture -Fixture $f -Through MoveReturned
        $r=Test-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -ExternallyPinnedReceiptSha256 $s.Sha256
        $r.Status | Should -BeExactly 'OriginalMailMoverSyntheticMoveReturnedReceiptPinnedIndependentReviewRequired'
        $r.ReceiptExternallyPinned | Should -BeTrue
        $r.IndependentLivePstVerified | Should -BeFalse
        $r.DuplicateIndexCommitAllowed | Should -BeFalse
    }
    It 'unpinned MoveReturned remains a pending independent verification' {
        $f=New-ARCH3dFixture
        $s=Step-ARCH3dFixture -Fixture $f -Through MoveReturned
        $r=Test-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation
        $r.ReceiptExternallyPinned | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'wrong external receipt SHA does not pass' {
        $f=New-ARCH3dFixture
        $s=Step-ARCH3dFixture -Fixture $f -Through MoveReturned
        $r=Test-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -ExternallyPinnedReceiptSha256 ('0'*64)
        $r.Issues | Should -Contain 'ExternalReceiptShaMismatch'
    }
    It 'a claimed but no-returned operation is ALWAYS unknown/never retry' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through MoveClaimed)
        $r=Test-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation
        $r.Status | Should -BeExactly 'SyntheticOneShotClaimExistsOutcomeUnknownNoRetry'
        $r.WriterPermit | Should -BeFalse
    }
    It 'indeterminate COM branch preserves original OperationJournal Indeterminate' {
        $f=New-ARCH3dFixture
        [void](Step-ARCH3dFixture -Fixture $f -Through MoveClaimed)
        [void](Write-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -Stage MoveIndeterminate -ArchivePst $f.Destination -TargetFolderPath $f.Target -WitnessSha256 ('a'*64))
        $j=Read-OPAOperationJournal -Path (Join-Path $f.Operation.Root 'original-operation-journal.jsonl')
        (Resolve-OPAOperationRecovery -Journal $j).BlockAutomaticRetry | Should -BeTrue
        (Test-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation).Status | Should -BeExactly 'SyntheticComIndeterminateManualReviewNoRetry'
    }
    It 'tampered after-claim evidence never passes integrity chain' {
        $f=New-ARCH3dFixture
        $s=Step-ARCH3dFixture -Fixture $f -Through MoveReturned
        $p=Join-Path $f.Operation.Root 'MoveClaimed.json'
        [IO.File]::AppendAllText($p,' ')
        $r=Test-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -ExternallyPinnedReceiptSha256 $s.Sha256
        $r.Issues.Count | Should -BeGreaterThan 0
    }
    It 'all synthetic boundaries preserve original writer fence and no production permit' {
        $f=New-ARCH3dFixture
        $s=Step-ARCH3dFixture -Fixture $f -Through MoveReturned
        $r=Test-OPA265ARCH3dSyntheticBoundary -Operation $f.Operation -ExternallyPinnedReceiptSha256 $s.Sha256
        $r.RealOutlookContacted | Should -BeFalse
        $r.LiveMailMoved | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
}
Describe 'ARCH3d original MailMover integration: fake single MailItem.Move, durable claim/receipt, stop before duplicate index' {
    BeforeEach {
        $script:f=New-ARCH3dFixture
        $script:fakeMail=[pscustomobject]@{
            EntryID=[string]$script:f.Candidate.EntryID
            Class=43
            Calls=0
        }
        $script:fakeMail | Add-Member -MemberType ScriptMethod -Name Move -Value {
            param($folder)
            $this.Calls++
            return [pscustomobject]@{EntryID='00000000FEDCBA9876543210FEDCBA987654321000000001'}
        }
        $script:legacyIndexCalls=0
        $script:legacyDestinationCalls=0
        Mock Get-OPAArchivePstPartsOnDiskAll { @() }
        Mock Get-OPAArchiveCandidates { @($script:f.Candidate) }
        Mock Get-OPASourceFolderByPath { $script:f.Folder }
        Mock Get-OPAItemByEntryIdFromSourceFolder { $script:fakeMail }
        Mock Get-OPAArchiveDestination {
            $script:legacyDestinationCalls++
            [pscustomobject]@{
                Path=[string]$script:f.Destination
                Folder=[pscustomobject]@{FolderPath=[string]$script:f.Target}
            }
        }
        Mock Get-OPAArchiveSafeCapacityBytes { [int64]999999999 }
        Mock Import-OPADuplicateIndex { [pscustomobject]@{ArchivePst=[string]$script:f.Destination;Entries=@()} }
        Mock Test-OPADuplicateEntry { $null }
        Mock Get-OPA265ARCH2bMailSemanticWitness { [pscustomobject]@{Original='SYNTHETIC-WITNESS';ContentSha256=('a'*64)} }
        Mock Save-OPAArchiveTransaction { }
        Mock Sync-OPAStepJournalStreams { }
        Mock Add-OPADuplicateEntry { $script:legacyIndexCalls++ }
        Mock Release-OPAComObject { }
    }
    It 'executes original GetDestination AND exactly one mock Move, then stops BEFORE legacy DuplicateIndex' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary} | Should -Throw '*ARCH3d SYNTHETIC STOP*'
        $script:fakeMail.Calls | Should -Be 1
        $script:legacyDestinationCalls | Should -Be 1
        $script:legacyIndexCalls | Should -Be 0
        $p=Join-Path $script:f.Operation.Root 'MoveReturned.json'
        [IO.File]::Exists($p) | Should -BeTrue
    }
    It 'calls the original destination only AFTER persistent PrepareIntent exists' {
        Mock Get-OPAArchiveDestination {
            $script:legacyDestinationCalls++
            if(-not [IO.File]::Exists((Join-Path $script:f.Operation.Root 'PrepareIntent.json'))){throw 'PrepareIntentMissing'}
            [pscustomobject]@{Path=[string]$script:f.Destination;Folder=[pscustomobject]@{FolderPath=[string]$script:f.Target}}
        }
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary} | Should -Throw '*ARCH3d SYNTHETIC STOP*'
        $script:legacyDestinationCalls | Should -Be 1
    }
    It 'rejects rerun BEFORE a second mock Move after original claim/receipt' {
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary} | Should -Throw
        $script:fakeMail.Calls | Should -Be 1
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary} | Should -Throw
        $script:fakeMail.Calls | Should -Be 1
    }
    It 'mock provider exception results in one claim + synthetic Indeterminate, no index, no retry' {
        $script:fakeMail.PSObject.Members.Remove('Move')
        $script:fakeMail | Add-Member -MemberType ScriptMethod -Name Move -Value {
            param($folder)
            $this.Calls++
            throw 'Simulated COM error after provider might move'
        }
        {Move-OPAItemsWithLimit -Namespace $script:f.Namespace -SourceFolders @($script:f.Folder) -Transaction $script:f.Transaction -Limit 1 -ArchiveGrouping Year -ARCH3dSyntheticBoundary} | Should -Throw
        $script:fakeMail.Calls | Should -Be 1
        $script:legacyIndexCalls | Should -Be 0
        [IO.File]::Exists((Join-Path $script:f.Operation.Root 'MoveClaimed.json')) | Should -BeTrue
        [IO.File]::Exists((Join-Path $script:f.Operation.Root 'MoveIndeterminate.json')) | Should -BeTrue
    }
    It 'without synthetic flag old MailMover remains untouched and original top-level fence remains closed' {
        $main=Get-Content -LiteralPath (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $main | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
        $m=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $m | Should -Match 'if\(\$ARCH3dSyntheticBoundary\)'
        $m | Should -Match '\$moved = \$item.Move\(\$dest.Folder\)'
    }
}
