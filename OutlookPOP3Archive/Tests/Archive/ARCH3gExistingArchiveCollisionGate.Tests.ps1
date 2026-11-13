#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3gExistingArchiveCollisionGate.ps1')
    $script:fakeSource='C:\Fake\info@stios.ru.pst'
    $script:entry='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    function New-ARCH3gPart {
        param([int]$Part=1,[int]$Year=2020,[string]$Path='')
        if(-not $Path){$Path=Get-OPAArchivePartPath -SourcePst $script:fakeSource -Year $Year -Part $Part}
        return [pscustomobject]@{Path=$Path;Part=$Part;Year=$Year}
    }
}
Describe 'ARCH3g original Year PST collision contract (pure)' {
    It 'keeps writer closed even when no annual PST exists' {
        $r=Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId $script:entry -ArchiveYear 2020 -ExistingParts @()
        $r.ExistingYearArchiveCollision | Should -BeFalse
        $r.NextUnusedPartPathPreview | Should -BeExactly (Get-OPAArchivePartPath -SourcePst $script:fakeSource -Year 2020 -Part 1)
        $r.WriterPermit | Should -BeFalse
        $r.LiveMovePerformed | Should -BeFalse
    }
    It 'flags pre-existing original Archive-2020 part 1 without touching it' {
        $r=Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId $script:entry -ArchiveYear 2020 -ExistingParts @(New-ARCH3gPart)
        $r.ExistingYearArchiveCollision | Should -BeTrue
        $r.ExistingPartCount | Should -Be 1
        $r.DoNotAppendToExistingAnnualPst | Should -BeTrue
        $r.NextUnusedPartPathPreview | Should -BeLike '*Archive-2020-02.pst'
        $r.NextUnusedPartNotReserved | Should -BeTrue
        $r.WriterPermit | Should -BeFalse
    }
    It 'reuses original Part naming for 1 and 2 and proposes only next unused part' {
        $r=Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId $script:entry -ArchiveYear 2020 -ExistingParts @((New-ARCH3gPart -Part 1),(New-ARCH3gPart -Part 2))
        $r.NextUnusedPartPathPreview | Should -BeExactly (Get-OPAArchivePartPath -SourcePst $script:fakeSource -Year 2020 -Part 3)
        $r.ExistingParts.Count | Should -Be 2
    }
    It 'rejects a part whose path disagrees with original MailMover naming' {
        {Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId $script:entry -ArchiveYear 2020 -ExistingParts @((New-ARCH3gPart -Path 'C:\Fake\strange.pst'))} | Should -Throw
    }
    It 'rejects wrong-year archive parts' {
        {Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId $script:entry -ArchiveYear 2020 -ExistingParts @((New-ARCH3gPart -Year 2021))} | Should -Throw
    }
    It 'rejects duplicated archive parts' {
        $row=New-ARCH3gPart
        {Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId $script:entry -ArchiveYear 2020 -ExistingParts @($row,$row)} | Should -Throw
    }
    It 'refuses non-test original PST names' {
        {Get-OPA265ARCH3gPartPlan -SourcePst 'C:\Fake\other.pst' -SourceEntryId $script:entry -ArchiveYear 2020} | Should -Throw
    }
    It 'refuses incomplete or malformed COM EntryID selectors' {
        {Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId 'NOT-HEX' -ArchiveYear 2020} | Should -Throw
    }
    It 'fails closed on extreme part ordinal 99' {
        {Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId $script:entry -ArchiveYear 2020 -ExistingParts @((New-ARCH3gPart -Part 99))} | Should -Throw
    }
    It 'never mistakes a dry-run path preview for a reserved target' {
        $r=Get-OPA265ARCH3gPartPlan -SourcePst $script:fakeSource -SourceEntryId $script:entry -ArchiveYear 2020
        $r.NextUnusedPartNotReserved | Should -BeTrue
        $r.NoPstOrJournalWrites | Should -BeTrue
        $r.FullSemanticWitnessCaptured | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
    }
}
Describe 'ARCH3g real Outlook read-only audit with fake COM test double' {
    BeforeEach {
        $script:source=Join-Path $TestDrive 'info@stios.ru.pst'
        [IO.File]::WriteAllBytes($script:source,[byte[]](1..32))
        $script:fakeFolder=[pscustomobject]@{
            Name='Входящие';FolderPath='\\info@stios.ru\Входящие'
            EntryID='00000000ABCDEF001234567812345678';StoreID='ARCH3G-FAKE-SOURCE'
        }
        $script:fakeMail=[pscustomobject]@{
            Class=43;EntryID=$script:entry;Parent=$script:fakeFolder
            ReceivedTime=[datetime]'2020-02-13T12:57:58'
            SentOn=[datetime]'2020-02-13T12:57:57'
            Attachments=[pscustomobject]@{Count=2}
        }
        $script:ns=[pscustomobject]@{CurrentProfileName='Outlook'}
        $script:ns | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {
            param($id,$storeId)
            if($id -cne $script:entry -or $storeId -cne 'ARCH3G-FAKE-SOURCE'){throw 'wrong fake selector'}
            return $script:fakeMail
        }
        $script:session=[pscustomobject]@{
            Scope=[pscustomobject]@{Approved=$true;SourceStoreId='ARCH3G-FAKE-SOURCE'}
            SourceStore=[pscustomobject]@{StoreID='ARCH3G-FAKE-SOURCE'}
            Namespace=$script:ns;Inbox=$script:fakeFolder
            OutlookProcessId=123;OutlookProcessStartUtcTicks=[long]456
        }
        Mock Get-OPAArchivePstPartsOnDisk {return @()}
        Mock Get-OPA265ARCH2dLayout {return [pscustomobject]@{ArchivePst='C:\none.pst'}}
        Mock Open-OPA265ARCH2dSession {return $script:session}
        Mock Release-OPA265ARCH2c4Com {}
        Mock Close-OPA265ARCH2dSession {}
    }
    It 'validates exact source MailItem inside Inbox, exposes actual attachment count, and never moves' {
        $r=Invoke-OPA265ARCH3gExistingArchiveGate -Mode Audit -SourcePst $script:source -SourceEntryId $script:entry -ArchiveYear 2020
        $r.ExactInboxItemIndependentlyLocated | Should -BeTrue
        $r.AttachmentCount | Should -Be 2
        $r.SourceArchiveDate.Year | Should -Be 2020
        $r.OriginalTargetFolderPath | Should -BeExactly '2020\Входящие'
        $r.FullWitnessPending | Should -BeTrue
        $r.WriterPermit | Should -BeFalse
        Should -Invoke Close-OPA265ARCH2dSession -Exactly -Times 1
    }
    It 'rejects a source EntryID that resolves to another folder' {
        $script:fakeMail.Parent=[pscustomobject]@{
            Name='Other';FolderPath='\\info@stios.ru\Other'
            EntryID='00000000FFFFFFFFFFFFFFFFFFFFFFFF';StoreID='ARCH3G-FAKE-SOURCE'
        }
        {Invoke-OPA265ARCH3gExistingArchiveGate -Mode Audit -SourcePst $script:source -SourceEntryId $script:entry -ArchiveYear 2020} | Should -Throw
        Should -Invoke Close-OPA265ARCH2dSession -Exactly -Times 1
    }
}
Describe 'ARCH3g no writer in source-backed operator entrypoint' {
    It 'offers only Plan and Audit; original Archive/Resume/Auto are not opened' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3g.ps1') -Raw -Encoding UTF8
        $main=Get-Content -LiteralPath (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Plan','Audit'\)"
        $main | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
    }
    It 'does not contain COM Move, create-store, journal commit, or duplicate index commit' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3gExistingArchiveCollisionGate.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '\.Move\(|\.AddStoreEx\(|\.Save\(|\.Delete\(|Add-OPADuplicateEntry|Write-OPAOperationJournalEvent'
        $s | Should -Match 'Open-OPA265ARCH2dSession'
        $s | Should -Match 'Get-OPAArchivePstPartsOnDisk'
    }
}
