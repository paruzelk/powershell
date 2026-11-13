#requires -Version 5.1
# ARCH3f real test PST preflight; all CI cases are fake-only and read-only.
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3fRealTestPstPreflight.ps1')
    $script:source='C:\Users\ARCH3F-FAKE\Documents\Файлы Outlook\info@stios.ru.pst'
    function New-ARCH3fCandidate {
        param([string]$EntryID='00000000E1878292411BC64291BD506DCEFD2A35040A3C00',
              [datetime]$ArchiveDate=([datetime]'2020-02-12T12:30:00'),
              [string]$FolderName='Входящие',
              [string]$FolderPath='\\POP3 Store\Входящие')
        return [pscustomobject]@{
            EntryID=$EntryID
            ArchiveDate=$ArchiveDate
            ReceivedTime=$ArchiveDate
            FolderName=$FolderName
            SourceFolderPath=$FolderPath
            Size=[long]4100
            AttachmentCount=2
        }
    }
    function New-ARCH3fFolder {
        param([string]$FolderName='Входящие',
              [string]$FolderPath='\\POP3 Store\Входящие',
              [int]$Count=26000,
              [bool]$SentLike=$false)
        return [pscustomobject]@{
            FolderName=$FolderName
            FolderPath=$FolderPath
            FolderEntryId='00000000ABCDEF000000000000000000'
            ItemsCount=$Count
            SentLike=$SentLike
        }
    }
}
Describe 'ARCH3f operator designated existing test PST policy and safe Plan' {
    It 'accepts exact local info@stios.ru.pst name as an operator-declared TEST source' {
        (Assert-OPA265ARCH3fRealTestSource -SourcePst $script:source) | Should -BeExactly $script:source
    }
    It 'rejects a different mailbox PST name' {
        {Assert-OPA265ARCH3fRealTestSource -SourcePst 'C:\Fake\other@stios.ru.pst'} | Should -Throw
    }
    It 'rejects an archive PST for source' {
        {Assert-OPA265ARCH3fRealTestSource -SourcePst 'C:\Fake\info@stios.ru.Archive-2020.pst'} | Should -Throw
    }
    It 'rejects a UNC source' {
        {Assert-OPA265ARCH3fRealTestSource -SourcePst '\\server\test\info@stios.ru.pst'} | Should -Throw
    }
    It 'fails closed if real inventory requested but test PST does not exist' {
        {Assert-OPA265ARCH3fRealTestSource -SourcePst $script:source -RequireExisting} | Should -Throw
    }
    It 'Plan can work with the real test PST path as text without Outlook' {
        $p=Invoke-OPA265ARCH3fRealTestPreflight -Mode Plan -SourcePst $script:source
        $p.Status | Should -BeExactly 'OperatorDesignatedRealTestPstAcceptedReadOnlyIntegrationPlan'
        $p.SourceDesignation | Should -BeExactly 'OperatorDesignatedTestPstWithRealMailboxContent'
        $p.OutlookContacted | Should -BeFalse
        $p.LiveMoveIntegrated | Should -BeFalse
    }
    It 'Plan always keeps legacy Archive/Resume/Auto blocked' {
        $p=Invoke-OPA265ARCH3fRealTestPreflight -Mode Plan -SourcePst $script:source
        $p.OriginalArchiveResumeAutoStillBlocked | Should -BeTrue
        $p.WriterPermit | Should -BeFalse
        $p.ProductionReady | Should -BeFalse
    }
    It 'Plan has zero implicit real COM or PST reads' {
        $p=Invoke-OPA265ARCH3fRealTestPreflight -Mode Plan -SourcePst $script:source
        $p.SourcePstOpened | Should -BeFalse
        $p.ArchivePstOpenedOrCreated | Should -BeFalse
        $p.NoPstOrJournalWrites | Should -BeTrue
    }
}
Describe 'ARCH3f reuse the ORIGINAL Year routing on real-mail-shaped fake candidates' {
    BeforeEach {
        $script:folders=@(New-ARCH3fFolder)
        $script:rows=@(New-ARCH3fCandidate)
    }
    It 'maps 2020 original Inbox candidate to original Year archive part and relative folder' {
        $p=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates $script:rows
        $p.SampleCandidateCount | Should -Be 1
        $p.Candidates[0].PlannedArchivePart1Pst | Should -BeLike '*info@stios.ru.Archive-2020.pst'
        $p.Candidates[0].PlannedTargetFolderPath | Should -BeExactly '2020\Входящие'
    }
    It 'uses exactly the source original Get-OPAArchivePartPath and Get-OPAArchiveTargetPath functions' {
        $p=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates $script:rows
        $c=$script:rows[0]
        $p.Candidates[0].PlannedArchivePart1Pst | Should -BeExactly (Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 1)
        $p.Candidates[0].PlannedTargetFolderPath | Should -BeExactly (Get-OPAArchiveTargetPath -ReceivedTime $c.ArchiveDate -SourceFolderName $c.FolderName -SourceFolderPath $c.SourceFolderPath -Grouping Year)
    }
    It 'preserves original SentOn year when selector already selected ARCHIVE date' {
        $f=New-ARCH3fFolder -FolderName 'Отправленные' -FolderPath '\\POP3 Store\Отправленные' -Count 77 -SentLike $true
        $c=New-ARCH3fCandidate -FolderName 'Отправленные' -FolderPath $f.FolderPath -ArchiveDate ([datetime]'2020-12-31T23:50:00')
        $p=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders @($f) -Candidates @($c)
        $p.Candidates[0].ArchiveYear | Should -Be 2020
        $p.Candidates[0].PlannedTargetFolderPath | Should -BeExactly '2020\Отправленные'
    }
    It 'preserves nested user folder hierarchy in original Year destination' {
        $f=New-ARCH3fFolder -FolderName 'Договоры' -FolderPath '\\POP3 Store\Проекты\Договоры' -Count 1
        $c=New-ARCH3fCandidate -FolderName 'Договоры' -FolderPath $f.FolderPath
        $p=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders @($f) -Candidates @($c)
        $p.Candidates[0].PlannedTargetFolderPath | Should -BeExactly '2020\Проекты\Договоры'
    }
    It 'separates 2020 and 2021 into different existing original archive names' {
        $r1=New-ARCH3fCandidate
        $r2=New-ARCH3fCandidate -EntryID '00000000E1878292411BC64291BD506DCEFD2A3520093C00' -ArchiveDate ([datetime]'2021-05-03')
        $p=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates @($r1,$r2)
        $p.YearSampleCounts.Count | Should -Be 2
        $p.Candidates[0].PlannedArchivePart1Pst | Should -Not -BeExactly $p.Candidates[1].PlannedArchivePart1Pst
    }
    It 'folder item total is original folder-count sum, not mislabeled sampled Year total' {
        $p=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates $script:rows
        $p.FolderItemsCountSum | Should -Be 26000
        $p.SampleCandidateCount | Should -Be 1
        $p.YearCountsAreFullInventory | Should -BeFalse
    }
    It 'rejects Outbox even if it contains hundreds of mail items' {
        $f=New-ARCH3fFolder -FolderName 'Исходящие' -FolderPath '\\POP3 Store\Исходящие' -Count 100
        {ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders @($f) -Candidates @()} | Should -Throw
    }
    It 'rejects default excluded Drafts/Junk/Deleted Items by original SystemFolders fallback' {
        foreach($name in @('Черновики','Спам','Удалённые')){
            $f=New-ARCH3fFolder -FolderName $name -FolderPath ('\\POP3 Store\'+$name) -Count 4
            {ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders @($f) -Candidates @()} | Should -Throw
        }
    }
    It 'keeps a user-created folder named Drafts when original well-known map identifies a different system Drafts ID' {
        $f=New-ARCH3fFolder -FolderName 'Черновики' -FolderPath '\\POP3 Store\Проекты\Черновики' -Count 4
        $c=New-ARCH3fCandidate -FolderName 'Черновики' -FolderPath $f.FolderPath
        $map=@{'00000000FFFFFFFFFFFFFFFFFFFFFFFF'='Drafts'}
        $p=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders @($f) -Candidates @($c) -WellKnownEntryIdMap $map
        $p.Candidates[0].PlannedTargetFolderPath | Should -BeExactly '2020\Проекты\Черновики'
    }
    It 'rejects a candidate in any folder absent from approved folder plan' {
        $c=New-ARCH3fCandidate -FolderPath '\\POP3 Store\Other'
        {ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates @($c)} | Should -Throw
    }
    It 'rejects duplicate source EntryID' {
        {ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates @($script:rows[0],$script:rows[0])} | Should -Throw
    }
    It 'rejects duplicate source folder paths' {
        {ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders @($script:folders[0],$script:folders[0]) -Candidates $script:rows} | Should -Throw
    }
    It 'rejects malformed source EntryID and date before any live Move' {
        $c=New-ARCH3fCandidate -EntryID 'X'
        {ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates @($c)} | Should -Throw
        $c=New-ARCH3fCandidate -ArchiveDate ([datetime]'1800-01-01')
        {ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates @($c)} | Should -Throw
    }
    It 'rejects oversized planned candidate/folder counts without writing PST' {
        $f=@(New-ARCH3fFolder)
        $rows=@()
        for($i=1;$i -le 2;$i++){$rows+=New-ARCH3fCandidate -EntryID ('{0:X32}' -f $i)}
        {ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $f -Candidates $rows -MaximumCandidates 1} | Should -Throw
    }
    It 'read-only preview never permits production writer or retry' {
        $p=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $script:source -Folders $script:folders -Candidates $script:rows
        $p.NoRealMoveMade | Should -BeTrue
        $p.AutomaticRetryAllowed | Should -BeFalse
        $p.ArchiveResumeAutoRemainClosed | Should -BeTrue
        $p.ProductionReady | Should -BeFalse
    }
}
Describe 'ARCH3f real Inventory code path with only fake Outlook COM wrappers in CI' {
    It 'reuses original Session/EligibleWalker/Selector and returns actual folder counts with sampled Year routes' {
        $fakeFolder=[pscustomobject]@{
            Name='Входящие'
            EntryID='00000000ABCDEF001234567812345678'
            FolderPath='\\POP3 Store\Входящие'
            Items=[pscustomobject]@{Count=25}
        }
        $store=[pscustomobject]@{
            StoreID='ARCH3F-FAKE-STORE'
            Root=[pscustomobject]@{FolderPath='\\POP3 Store'}
        }
        $store | Add-Member -MemberType ScriptMethod -Name GetRootFolder -Value {return $this.Root}
        $fakeSession=[pscustomobject]@{
            SourceStore=$store
            Namespace=[pscustomobject]@{CurrentProfileName='Outlook'}
            Scope=[pscustomobject]@{Approved=$true}
            OutlookProcessId=789
            OutlookProcessStartUtcTicks=[long]1234567
        }
        $fakeCandidate=New-ARCH3fCandidate
        Mock Assert-OPA265ARCH3fRealTestSource {return $script:source}
        Mock Get-OPA265ARCH2dLayout {return [pscustomobject]@{ArchivePst='C:\none.pst'}}
        Mock Open-OPA265ARCH2dSession {return $fakeSession}
        Mock Get-OPAWellKnownFolderEntryIds {@{}}
        Mock Get-OPAEligiblePop3MailFolders {return @($fakeFolder)}
        Mock Get-OPAArchiveCandidates {
            [pscustomobject]@{
                SelectionErrors=0;UsedSort=$true;UsedRestrict=$false
                Candidates=@($fakeCandidate);SelectionErrorDetails=@()
            }
        }
        Mock Release-OPA265ARCH2c4Com {}
        Mock Close-OPA265ARCH2dSession {}
        $r=Invoke-OPA265ARCH3fRealTestPreflight -Mode Inventory -SourcePst $script:source
        $r.Status | Should -BeExactly 'ExistingTestPstRealMailRoutePreviewNoPstOrComWrites'
        $r.Pop3ScopeApproved | Should -BeTrue
        $r.FolderItemsCountSum | Should -Be 25
        $r.SampleCandidateCount | Should -Be 1
        $r.Candidates[0].PlannedTargetFolderPath | Should -BeExactly '2020\Входящие'
        $r.YearCountsAreFullInventory | Should -BeFalse
        $r.ArchivePstOpenedOrCreated | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        Should -Invoke Open-OPA265ARCH2dSession -Times 1 -Exactly
        Should -Invoke Get-OPAEligiblePop3MailFolders -Times 1 -Exactly
        Should -Invoke Get-OPAArchiveCandidates -Times 1 -Exactly
        Should -Invoke Close-OPA265ARCH2dSession -Times 1 -Exactly
    }
}
Describe 'ARCH3f source-backed read-only integration safety gates' {
    It 'operators only get Plan and Inventory, never Move/Prepare/Resume/Archive' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3f.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Plan','Inventory'\)"
        $s | Should -Not -Match 'MoveBatch|ConfirmBatchMove|ConfirmOneShotMove'
    }
    It 'actual inventory calls old ARCH2d session, original FolderWalker/Selector, closes session' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3fRealTestPstPreflight.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Open-OPA265ARCH2dSession -Layout'
        $s | Should -Match 'Get-OPAEligiblePop3MailFolders -RootFolder'
        $s | Should -Match 'Get-OPAArchiveCandidates -SourceFolder'
        $s | Should -Match 'Close-OPA265ARCH2dSession -Session'
    }
    It 'original top-level legacy production fence is unchanged' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
    }
    It 'real inventory has no PST modifying COM calls and no original Move retries' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3fRealTestPstPreflight.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '\.Move\(|\.AddStoreEx\(|\.Save\(|\.Delete\(|\.RemoveStore\('
        $s | Should -Not -Match 'Save-OPAArchiveTransaction|Add-OPADuplicateEntry|Write-OPA265ARCH2c4JsonOnce'
    }
    It 'README and ARCH3f authority classify the real mailbox data as test without falsely guaranteeing IMAP restore' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'docs/2.6.5-arch3f-test-pst-authorization.md') -Raw -Encoding UTF8
        $s | Should -Match 'OperatorDesignatedTestPstWithRealMailboxContent'
        $s | Should -Match 'IMAP'
        $s | Should -Match 'не должны автоматически'
    }
}
