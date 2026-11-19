#requires -Version 5.1
BeforeAll {
    $script:project=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:project 'Core/Archive/ARCH3uRealBatchTenPreflight.ps1')
    function New-ARCH3uFixture {
        param([int]$Count=13,[int]$Year=2020)
        $src=Join-Path $TestDrive 'info@stios.ru.pst'
        $path='\\info@stios.ru\Входящие'
        $mail=@(for($n=1;$n -le $Count;$n++){
            [pscustomobject]@{
                EntryID=('{0:X16}' -f $n)
                ArchiveDate=[datetime]::new($Year,2,1).AddMinutes($n)
                SourceFolderPath=$path
                FolderName='Входящие'
                Subject=('synthetic '+$n)
            }
        })
        $parts=@(
            [pscustomobject]@{Year=$Year;Part=1;Path=(Get-OPAArchivePartPath -SourcePst $src -Year $Year -Part 1)}
            [pscustomobject]@{Year=$Year;Part=2;Path=(Get-OPAArchivePartPath -SourcePst $src -Year $Year -Part 2)}
        )
        return @{
            RunId='12345678-1234-4234-8234-123456789abc'
            SourcePst=$src
            SourceStoreId='SYNTH-POP3-STORE-READONLY'
            InboxEntryId=('A'*32)
            InboxPath=$path
            InboxName='Входящие'
            Candidates=$mail
            IndexedSourceEntryIds=@(('{0:X16}' -f 1),('{0:X16}' -f 2))
            ExistingParts=$parts
            OriginalIndexSha256=('b'*64)
        }
    }
}
Describe 'ARCH3u exact ten original MailMover route READ ONLY' {
    BeforeEach {$script:fixture=New-ARCH3uFixture}
    It 'selects ten unindexed oldest from original Inbox, year and unused part3' {
        $x=New-OPA265ARCH3uTenPreview @script:fixture
        $x.Status | Should -BeExactly 'TenOriginalInboxCandidatesAndNextUnusedYearPartReadOnlyNoMove'
        $x.BatchSize | Should -Be 10
        $x.Rows.Count | Should -Be 10
        $x.SampleAlreadyIndexedCount | Should -Be 2
        $x.SelectedYear | Should -Be 2020
        $x.SelectedArchivePart | Should -Be 3
        $x.OriginalMailMoverContractsUsed | Should -BeTrue
        $x.OriginalDuplicateIndexConsulted | Should -BeTrue
        $x.RealMailMovePerformed | Should -BeFalse
        $x.WriterPermit | Should -BeFalse
    }
    It 'preserves each canonical original per-item contract and target folder' {
        $x=New-OPA265ARCH3uTenPreview @script:fixture
        foreach($r in $x.Rows){
            $r.OriginalOperationId | Should -Match '^ARCH3b-[a-f0-9]{64}$'
            $r.OriginalContractSha256 | Should -Match '^[a-f0-9]{64}$'
            $r.TargetPstPreview | Should -BeExactly $x.TargetPstPreview
            $r.SourceFolderPath | Should -BeExactly $script:fixture.InboxPath
        }
    }
    It 'has deterministic SHA across repeated pure previews' {
        $a=New-OPA265ARCH3uTenPreview @script:fixture
        $b=New-OPA265ARCH3uTenPreview @script:fixture
        $a.PreviewSha256 | Should -BeExactly $b.PreviewSha256
    }
    It 'changes sealed preview digest when original index SHA differs' {
        $a=New-OPA265ARCH3uTenPreview @script:fixture
        $script:fixture.OriginalIndexSha256='c'*64
        $b=New-OPA265ARCH3uTenPreview @script:fixture
        $a.PreviewSha256 | Should -Not -BeExactly $b.PreviewSha256
    }
    It 'does not reselect already indexed source selectors' {
        $script:fixture.IndexedSourceEntryIds=@(for($n=1;$n -le 3;$n++){'{0:X16}' -f $n})
        $a=New-OPA265ARCH3uTenPreview @script:fixture
        $a.Rows[0].SourceEntryId | Should -BeExactly ('{0:X16}' -f 4)
        $a.Rows.Count | Should -Be 10
    }
    It 'denies partial nine-message batch' {
        $script:fixture.Candidates=@($script:fixture.Candidates | Select-Object -First 9)
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'denies ten candidates if more than one is already indexed' {
        $script:fixture.Candidates=@($script:fixture.Candidates | Select-Object -First 10)
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'rejects duplicated original Inbox EntryID' {
        $script:fixture.Candidates[4].EntryID=$script:fixture.Candidates[3].EntryID
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'rejects candidate from different folder or account' {
        $script:fixture.Candidates[0].SourceFolderPath='\\IMAP\Inbox'
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'rejects invalid original indexed selector' {
        $script:fixture.IndexedSourceEntryIds=@('unknown-index-selector')
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'rejects conflicting annual part path' {
        $script:fixture.ExistingParts[1].Path=Join-Path $TestDrive 'Wrong.PST'
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'rejects duplicate annual part number' {
        $script:fixture.ExistingParts[1].Part=1
        $script:fixture.ExistingParts[1].Path=$script:fixture.ExistingParts[0].Path
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'rejects non-canonical RunId' {
        $script:fixture.RunId='NOT-A-GUID'
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'rejects SHA that cannot pin original shared index' {
        $script:fixture.OriginalIndexSha256='BAD'
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'blocks Year split when no single year has ten eligible messages' {
        $script:fixture.Candidates=@(New-ARCH3uFixture -Count 10 -Year 2020).Candidates
        $script:fixture.Candidates[9].ArchiveDate=[datetime]::new(2021,2,1)
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'Plan never needs an Outlook process or an existing PST' {
        $x=Invoke-OPA265ARCH3uRealBatchTenPreflight -Mode Plan -RunId $script:fixture.RunId -SourcePst $script:fixture.SourcePst
        $x.Status | Should -BeExactly 'RealTestPstOriginalTenReadOnlyPreflightPlannedNoOutlook'
        $x.OutlookContacted | Should -BeFalse
        $x.NoPstOrJournalWrites | Should -BeTrue
        $x.WriterPermit | Should -BeFalse
    }
    It 'rejects invalid year part 100 and never grants a writer' {
        $script:fixture.ExistingParts[1].Part=100
        {New-OPA265ARCH3uTenPreview @script:fixture} | Should -Throw
    }
    It 'requires BOM and forbids Move/AddStoreEx/PST writer calls in new code' {
        foreach($p in @('Invoke-ARCH3u.ps1','Core/Archive/ARCH3uRealBatchTenPreflight.ps1')){
            $f=Join-Path $script:project $p
            $bytes=[IO.File]::ReadAllBytes($f)
            @($bytes[0],$bytes[1],$bytes[2]) -join ',' | Should -BeExactly '239,187,191'
            $body=[IO.File]::ReadAllText($f)
            $body | Should -Not -Match '\.Move\s*\('
            $body | Should -Not -Match '\.AddStoreEx\s*\('
            $body | Should -Not -Match '\.Delete\s*\('
        }
    }
}
