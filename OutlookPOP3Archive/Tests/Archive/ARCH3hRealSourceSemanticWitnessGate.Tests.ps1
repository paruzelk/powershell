#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3hRealSourceSemanticWitnessGate.ps1')
    $script:id='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    $script:folderId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
    $script:store='ARCH3H-FAKE-STORE'
    $script:storeSha=Get-OPA265ARCH2bTextSha256 -Text $script:store
    $script:date=[datetime]'2020-02-13T12:57:58'
    function New-ARCH3hObserved {
        return [pscustomobject]@{
            SourceEntryId=$script:id
            SourceFolderEntryId=$script:folderId
            SourceStoreIdSha256=$script:storeSha
            SourcePstLengthBytes=[long]32
            AttachmentCount=0;SourceArchiveDate=$script:date
            ExistingYearArchiveCollision=$true
            ExistingPartCount=1
            ExistingParts=@([pscustomobject]@{Part=1;FileLengthBytes=[long]16;Path=(Join-Path $TestDrive 'info@stios.ru.Archive-2020.pst')})
            ExactInboxItemIndependentlyLocated=$true
            WriterPermit=$false;ProductionReady=$false
            OutlookProcessId=123;OutlookProcessStartUtcTicks=[long]456
            NextUnusedPartPathPreview=(Join-Path $TestDrive 'info@stios.ru.Archive-2020-02.pst')
        }
    }
    function Get-ARCH3hPins {
        return @{
            SourceEntryId=$script:id;ExpectedSourceFolderEntryId=$script:folderId
            ExpectedStoreIdSha256=$script:storeSha
            ExpectedSourcePstLengthBytes=[long]32
            ExpectedExistingArchiveLengthBytes=[long]16
            ExpectedAttachmentCount=0
            ExpectedArchiveDate=$script:date
        }
    }
}
Describe 'ARCH3h exact pinned original ARCH3g operator acceptance (pure)' {
    BeforeEach {
        $script:obs=New-ARCH3hObserved
        $script:pins=Get-ARCH3hPins
    }
    It 'accepts exactly matching live source StoreID, folder, attachment and archive bytes' {
        Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins | Should -BeTrue
    }
    It 'fails if selected EntryID is different' {
        $script:obs.SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35A4FC3B00'
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails if source folder drifted' {
        $script:obs.SourceFolderEntryId='00000000FFFFFFFFFFFFFFFFFFFFFFFF'
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails if source StoreID SHA drifted' {
        $script:obs.SourceStoreIdSha256=('f'*64)
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails if source PST length changed' {
        $script:obs.SourcePstLengthBytes=[long]33
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails if existing archive PST length changed' {
        $script:obs.ExistingParts[0].FileLengthBytes=[long]17
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails if source actual attachment count is not pinned' {
        $script:obs.AttachmentCount=1
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails if received archive date changes by one second' {
        $script:obs.SourceArchiveDate=$script:date.AddSeconds(1)
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails if more than one annual part exists' {
        $script:obs.ExistingPartCount=2
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails when preflight did not find exact inbox MailItem' {
        $script:obs.ExactInboxItemIndependentlyLocated=$false
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
    It 'fails when any writer permit appears in the input' {
        $script:obs.WriterPermit=$true
        {Assert-OPA265ARCH3hPinnedPreflight -Observed $script:obs @script:pins} | Should -Throw
    }
}
Describe 'ARCH3h fake Outlook original full semantic witness path' {
    BeforeEach {
        $script:source=Join-Path $TestDrive 'info@stios.ru.pst'
        [IO.File]::WriteAllBytes($script:source,[byte[]](1..32))
        $script:archive=Join-Path $TestDrive 'info@stios.ru.Archive-2020.pst'
        [IO.File]::WriteAllBytes($script:archive,[byte[]](1..16))
        $script:pins=Get-ARCH3hPins
        $script:folder=[pscustomobject]@{Name='Входящие';EntryID=$script:folderId;StoreID=$script:store;FolderPath='\\info@stios.ru\Входящие'}
        $script:mail=[pscustomobject]@{Class=43;EntryID=$script:id;Parent=$script:folder;Attachments=[pscustomobject]@{Count=0};ReceivedTime=$script:date;SentOn=$script:date}
        $script:ns=[pscustomobject]@{CurrentProfileName='Outlook'}
        $script:ns | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {
            param($id,$storeId)
            if($id -cne $script:id -or $storeId -cne $script:store){throw 'Incorrect fake selector'}
            return $script:mail
        }
        $script:session=[pscustomobject]@{
            Scope=[pscustomobject]@{Approved=$true;SourceStoreId=$script:store}
            SourceStore=[pscustomobject]@{StoreID=$script:store}
            Namespace=$script:ns;Inbox=$script:folder
            OutlookProcessId=123;OutlookProcessStartUtcTicks=[long]456
        }
        Mock Invoke-OPA265ARCH3gExistingArchiveGate {
            $o=New-ARCH3hObserved
            return $o
        }
        Mock Get-OPA265ARCH2dLayout {return [pscustomobject]@{ArchivePst='C:\missing.pst'}}
        Mock Open-OPA265ARCH2dSession {return $script:session}
        Mock Close-OPA265ARCH2dSession {}
        Mock Release-OPA265ARCH2c4Com {}
        Mock Get-OPA265ARCH2bMailSemanticWitness {
            return [pscustomobject]@{
                Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
                AttachmentCount=0;Attachments=@()
                BodySha256=('a'*64);HtmlBodySha256=('b'*64)
                OrderedRecipientDigestSha256=('c'*64)
            }
        }
        Mock Test-OPA265ARCH2bWitnessSchema {$true}
        Mock Get-OPA265ARCH3dOriginalWitnessHash {return ('d'*64)}
    }
    It 'returns hash-only full witness and preserves write fence on same mailbox' {
        $r=Invoke-OPA265ARCH3hPinnedSemanticWitness -Mode Witness -SourcePst $script:source -ArchiveYear 2020 @script:pins
        $r.FullWitnessCaptured | Should -BeTrue
        $r.OriginalWitnessSha256 | Should -BeExactly ('d'*64)
        $r.AttachmentCount | Should -Be 0
        $r.LiveMovePerformed | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.FullWitnessPersisted | Should -BeFalse
        Should -Invoke Get-OPA265ARCH2bMailSemanticWitness -Exactly -Times 1
        Should -Invoke Close-OPA265ARCH2dSession -Exactly -Times 1
    }
    It 'refuses source drift after connected audit and before full witness' {
        $script:mail.Parent=[pscustomobject]@{Name='Other';EntryID='00000000FFFFFFFFFFFFFFFFFFFFFFFF';StoreID=$script:store}
        {Invoke-OPA265ARCH3hPinnedSemanticWitness -Mode Witness -SourcePst $script:source -ArchiveYear 2020 @script:pins} | Should -Throw
        Should -Invoke Get-OPA265ARCH2bMailSemanticWitness -Exactly -Times 0
    }
    It 'refuses Outlook restart between preflight and source witness' {
        $script:session.OutlookProcessId=321
        {Invoke-OPA265ARCH3hPinnedSemanticWitness -Mode Witness -SourcePst $script:source -ArchiveYear 2020 @script:pins} | Should -Throw
    }
    It 'refuses incomplete original semantic witness and does not move' {
        Mock Test-OPA265ARCH2bWitnessSchema {$false}
        {Invoke-OPA265ARCH3hPinnedSemanticWitness -Mode Witness -SourcePst $script:source -ArchiveYear 2020 @script:pins} | Should -Throw
        Should -Invoke Get-OPA265ARCH3dOriginalWitnessHash -Exactly -Times 0
    }
}
Describe 'ARCH3h public API protects old writer and exact operator intent' {
    It 'Plan never contacts Outlook or obtains writer permit' {
        $p=Invoke-OPA265ARCH3hPinnedSemanticWitness -Mode Plan -SourcePst 'C:\Fake\info@stios.ru.pst' -ArchiveYear 2020 @((Get-ARCH3hPins))
        $p.OutlookContacted | Should -BeFalse
        $p.FullWitnessCaptured | Should -BeFalse
        $p.WriterPermit | Should -BeFalse
    }
    It 'entrypoint has no writer mode and original main archiver remains blocked' {
        $entry=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3h.ps1') -Raw -Encoding UTF8
        $core=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3hRealSourceSemanticWitnessGate.ps1') -Raw -Encoding UTF8
        $main=Get-Content -LiteralPath (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $entry | Should -Match "ValidateSet\('Plan','Witness'\)"
        $core | Should -Not -Match '\.Move\(|\.AddStoreEx\(|Add-OPADuplicateEntry|Write-OPAOperationJournalEvent'
        $main | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
    }
}
