#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3jRealOneShotPrepareIntent.ps1')
    $script:sourceId='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    $script:folderId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
    $script:sealRun='3773bcd7-5a07-4c31-8ce5-dfb16ddd30bf'
    $script:sealSha='5f5a86b6c1aba8a3d2ee328a36a5632f8edf1e89fdda8e7fd728688fe881b2a4'
    $script:originalSha='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
    function New-ARCH3jSealed {
        param([string]$SourcePst)
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3i.OriginalFullWitnessEnvelope.1'
            RunId=$script:sealRun
            SourcePst=$SourcePst
            SourceEntryId=$script:sourceId
            SourceFolderEntryId=$script:folderId
            SourceStoreIdSha256=(Get-OPA265ARCH2bTextSha256 -Text 'FAKE-ARCH3J-STORE')
            ExistingArchivePart1LengthBytes=[long]271360
            ArchiveDateLocalTicks=([datetime]'2020-02-13T12:57:58').Ticks
            SourceArchiveYear=2020
            OriginalWitnessSha256=$script:originalSha
            OriginalWitness=[pscustomobject]@{Schema='2.6.5-ARCH2b.MailSemanticWitness.1'}
        }
    }
    function Initialize-ARCH3jTestPst {
        $script:source=Join-Path $TestDrive 'info@stios.ru.pst'
        $script:part1=Join-Path $TestDrive 'info@stios.ru.Archive-2020.pst'
        $script:part2=Join-Path $TestDrive 'info@stios.ru.Archive-2020-02.pst'
        [IO.File]::WriteAllBytes($script:source,[byte[]](1..32))
        [IO.File]::WriteAllBytes($script:part1,(New-Object byte[] 271360))
        Clear-OPAArchivePartCache -SourcePst $script:source
        $script:sealed=New-ARCH3jSealed -SourcePst $script:source
    }
    function New-ARCH3jEmptySharedIndex {
        $dir=Join-Path $TestDrive 'OutlookPOP3Archive-Transactions'
        [void][IO.Directory]::CreateDirectory($dir)
        [IO.File]::WriteAllText((Join-Path $dir 'DuplicateIndex.json'),'{"SchemaVersion":"1.2","Entries":[]}')
    }
}
Describe 'ARCH3j original MailMover exact Year part isolation' {
    BeforeEach { Initialize-ARCH3jTestPst }
    It 'selects original Part2 route without opening Part1' {
        $o=Get-OPA265ARCH3jOriginalRoutePlan -Sealed $script:sealed -RunId ([guid]::NewGuid().ToString('D')) -SourceStoreId 'FAKE-ARCH3J-STORE'
        $o.PlannedArchivePst | Should -BeExactly $script:part2
        $o.PlannedTargetFolderPath | Should -BeExactly '2020\Входящие'
        $o.ArchivePart | Should -Be 2
        $o.WriterPermit | Should -BeFalse
        Test-Path -LiteralPath $script:part2 | Should -BeFalse
    }
    It 'rejects forged source StoreID' {
        {Get-OPA265ARCH3jOriginalRoutePlan -Sealed $script:sealed -RunId ([guid]::NewGuid().ToString('D')) -SourceStoreId 'other'} | Should -Throw
    }
    It 'rejects changed operator original full witness' {
        $script:sealed.OriginalWitnessSha256='f'*64
        {Get-OPA265ARCH3jOriginalRoutePlan -Sealed $script:sealed -RunId ([guid]::NewGuid().ToString('D')) -SourceStoreId 'FAKE-ARCH3J-STORE'} | Should -Throw
    }
    It 'rejects a changed existing Part1 length' {
        [IO.File]::AppendAllText($script:part1,'X')
        {Get-OPA265ARCH3jOriginalRoutePlan -Sealed $script:sealed -RunId ([guid]::NewGuid().ToString('D')) -SourceStoreId 'FAKE-ARCH3J-STORE'} | Should -Throw
    }
    It 'refuses an already existing original archive Part2' {
        [IO.File]::WriteAllText($script:part2,'not our target')
        Clear-OPAArchivePartCache -SourcePst $script:source
        {Get-OPA265ARCH3jOriginalRoutePlan -Sealed $script:sealed -RunId ([guid]::NewGuid().ToString('D')) -SourceStoreId 'FAKE-ARCH3J-STORE'} | Should -Throw
    }
    It 'refuses unknown existing Part3 rather than assuming Part2 still safe' {
        [IO.File]::WriteAllText((Join-Path $TestDrive 'info@stios.ru.Archive-2020-03.pst'),'unknown')
        Clear-OPAArchivePartCache -SourcePst $script:source
        {Get-OPA265ARCH3jOriginalRoutePlan -Sealed $script:sealed -RunId ([guid]::NewGuid().ToString('D')) -SourceStoreId 'FAKE-ARCH3J-STORE'} | Should -Throw
    }
}
Describe 'ARCH3j original shared DuplicateIndex read-only strict gate' {
    BeforeEach { Initialize-ARCH3jTestPst }
    It 'reports missing index directory as blocked without creating it' {
        $r=Get-OPA265ARCH3jIndexSafety -Part1 $script:part1 -SourceEntryId $script:sourceId
        $r.Approved | Should -BeFalse
        $r.Reason | Should -BeExactly 'OriginalSharedDuplicateIndexDirectoryMissing'
        Test-Path (Join-Path $TestDrive 'OutlookPOP3Archive-Transactions') | Should -BeFalse
    }
    It 'reports missing shared index files as blocked without creating files' {
        [void][IO.Directory]::CreateDirectory((Join-Path $TestDrive 'OutlookPOP3Archive-Transactions'))
        $r=Get-OPA265ARCH3jIndexSafety -Part1 $script:part1 -SourceEntryId $script:sourceId
        $r.Approved | Should -BeFalse
        $r.Reason | Should -BeExactly 'OriginalSharedDuplicateIndexFilesMissing'
    }
    It 'reads empty original legacy index and allows evidence-only preparation' {
        New-ARCH3jEmptySharedIndex
        $r=Get-OPA265ARCH3jIndexSafety -Part1 $script:part1 -SourceEntryId $script:sourceId
        $r.Approved | Should -BeTrue
        $r.IndexReadOnly | Should -BeTrue
        $r.EntryCount | Should -Be 0
    }
    It 'blocks index entry matching exact original source EntryID' {
        New-ARCH3jEmptySharedIndex
        $legacy=Join-Path (Join-Path $TestDrive 'OutlookPOP3Archive-Transactions') 'DuplicateIndex.json'
        $o=[pscustomobject]@{SchemaVersion='1.2';Entries=@([pscustomobject]@{SourceEntryId=$script:sourceId})}
        [IO.File]::WriteAllText($legacy,(ConvertTo-Json -InputObject $o -Depth 5))
        $r=Get-OPA265ARCH3jIndexSafety -Part1 $script:part1 -SourceEntryId $script:sourceId
        $r.Approved | Should -BeFalse
        $r.Reason | Should -BeExactly 'SourceAlreadyInOriginalSharedDuplicateIndex'
    }
    It 'rejects malformed final shared JSONL line even when newline is present' {
        New-ARCH3jEmptySharedIndex
        $journal=Join-Path (Join-Path $TestDrive 'OutlookPOP3Archive-Transactions') 'DuplicateIndex.jsonl'
        [IO.File]::WriteAllText($journal,('NOT_VALID_JSON'+[Environment]::NewLine))
        {Get-OPA265ARCH3jIndexSafety -Part1 $script:part1 -SourceEntryId $script:sourceId} | Should -Throw
    }
    It 'refuses unterminated shared index JSONL before original importer' {
        New-ARCH3jEmptySharedIndex
        [IO.File]::WriteAllText((Join-Path (Join-Path $TestDrive 'OutlookPOP3Archive-Transactions') 'DuplicateIndex.jsonl'),'{"SourceEntryId":"bad"}')
        {Get-OPA265ARCH3jIndexSafety -Part1 $script:part1 -SourceEntryId $script:sourceId} | Should -Throw
    }
}
Describe 'ARCH3j existing operator seal and original operation journal preparation' {
    BeforeEach {
        Initialize-ARCH3jTestPst
        $script:run=[guid]::NewGuid().ToString('D')
        $script:layout=Get-OPA265ARCH3jLayout -RunId $script:run
        Mock Get-OPA265ARCH3jSealedSource {return $script:sealed}
        $script:folder=[pscustomobject]@{Name='Входящие';FolderPath='\\info@stios.ru\Входящие';EntryID=$script:folderId;StoreID='FAKE-ARCH3J-STORE'}
        $script:mail=[pscustomobject]@{Class=43;EntryID=$script:sourceId;Parent=$script:folder;ReceivedTime=[datetime]'2020-02-13T12:57:58';SentOn=[datetime]'2020-02-13T12:57:58';Attachments=[pscustomobject]@{Count=0}}
        $script:ns=[pscustomobject]@{}
        $script:ns | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {
            param($id,$storeId)
            if($id -cne $script:sourceId -or $storeId -cne 'FAKE-ARCH3J-STORE'){throw 'wrong mock selector'}
            return $script:mail
        }
        $script:session=[pscustomobject]@{
            Scope=[pscustomobject]@{Approved=$true}
            SourceStore=[pscustomobject]@{StoreID='FAKE-ARCH3J-STORE'}
            Inbox=$script:folder;Namespace=$script:ns
            OutlookProcessId=123;OutlookProcessStartUtcTicks=[long]456
        }
        Mock Get-OPA265ARCH2dLayout {return [pscustomobject]@{ArchivePst='C:\never-create.pst'}}
        Mock Open-OPA265ARCH2dSession {return $script:session}
        Mock Close-OPA265ARCH2dSession {}
        Mock Release-OPA265ARCH2c4Com {}
        Mock Get-OPA265ARCH2bMailSemanticWitness {return [pscustomobject]@{Schema='2.6.5-ARCH2b.MailSemanticWitness.1';AttachmentCount=0}}
        Mock Assert-OPA265ARCH3iFullWitnessPinned {return $script:originalSha}
    }
    AfterEach {
        if([IO.Directory]::Exists([string]$script:layout.Root) -and
           [IO.Path]::GetFileName([string]$script:layout.Root) -ceq ('OPA265-ARCH3j-'+$script:run) -and
           [IO.Path]::GetDirectoryName([string]$script:layout.Root) -ieq $env:LOCALAPPDATA){
            Remove-Item -LiteralPath ([string]$script:layout.Root) -Recurse -Force -ErrorAction Stop
        }
    }
    It 'Plan with sealed operator source does not contact Outlook, journal or PST' {
        $r=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Plan -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha
        $r.Status | Should -BeExactly 'SealedRealOneShotOriginalYearRoutePlanNoOutlookNoWrites'
        $r.OriginalOperationJournalIntentWritten | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        Test-Path -LiteralPath $script:layout.Root | Should -BeFalse
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
    It 'Audit blocks missing shared index with no durable writes' {
        $r=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Audit -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha
        $r.Status | Should -BeExactly 'ExistingOriginalDuplicateIndexBlocksNewRealOneShotPreparation'
        $r.WriterPermit | Should -BeFalse
        Test-Path -LiteralPath $script:layout.Root | Should -BeFalse
    }
    It 'Audit with readable original index is still no-write' {
        New-ARCH3jEmptySharedIndex
        $r=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Audit -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha
        $r.Status | Should -BeExactly 'OriginalArchiveIndexAndSealedSourcePermitEvidenceOnlyPrepareIntent'
        $r.NewArchivePart2 | Should -BeExactly $script:part2
        $r.OriginalOperationJournalIntentWritten | Should -BeFalse
        $r.LiveMovePerformed | Should -BeFalse
        Test-Path -LiteralPath $script:layout.Root | Should -BeFalse
    }
    It 'Prepare without explicit ConfirmPrepareIntent stops before Outlook COM' {
        New-ARCH3jEmptySharedIndex
        {Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Prepare -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha -Confirm:$false} | Should -Throw
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
        Test-Path -LiteralPath $script:layout.Root | Should -BeFalse
    }
    It 'WhatIf Prepare does not open Outlook or write intent' {
        New-ARCH3jEmptySharedIndex
        $r=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Prepare -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha -ConfirmPrepareIntent -WhatIf
        $r.Status | Should -BeExactly 'PrepareIntentWhatIfNoOutlookNoWrites'
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
        Test-Path -LiteralPath $script:layout.Root | Should -BeFalse
    }
    It 'Prepare writes protected original journal Intent and immutable record before any PST creation' {
        New-ARCH3jEmptySharedIndex
        $r=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Prepare -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha -ConfirmPrepareIntent -Confirm:$false
        $r.Status | Should -BeExactly 'OriginalOperationJournalRealTestPstPrepareIntentIndependentlyVerifiedNoMove'
        $r.OriginalOperationJournalIntentWritten | Should -BeTrue
        $r.LiveMovePerformed | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        Test-Path -LiteralPath $script:part2 | Should -BeFalse
        $events=Read-OPAOperationJournal -Path $script:layout.JournalPath
        @($events.Events).Count | Should -Be 1
        $events.Events[0].Phase | Should -BeExactly 'Intent'
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 1
    }
    It 'Review proves original journal and immutable record without Outlook' {
        New-ARCH3jEmptySharedIndex
        $first=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Prepare -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha -ConfirmPrepareIntent -Confirm:$false
        $r=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Review -RunId $script:run -IntentSha256 $first.IntentSha256 -JournalSha256 $first.JournalSha256
        $r.OriginalOperationJournalIntentWritten | Should -BeTrue
        $r.MoveClaimed | Should -BeFalse
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 1
    }
    It 'never retries Prepare for the same RunId even without Move' {
        New-ARCH3jEmptySharedIndex
        $first=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Prepare -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha -ConfirmPrepareIntent -Confirm:$false
        {Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Prepare -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha -ConfirmPrepareIntent -Confirm:$false} | Should -Throw
        Test-Path -LiteralPath $script:layout.IntentPath | Should -BeTrue
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 1
    }
    It 'Review refuses a wrong journal SHA and never contacts Outlook' {
        New-ARCH3jEmptySharedIndex
        $first=Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Prepare -RunId $script:run -SealRunId $script:sealRun -SealSha256 $script:sealSha -ConfirmPrepareIntent -Confirm:$false
        {Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Review -RunId $script:run -IntentSha256 $first.IntentSha256 -JournalSha256 ('f'*64)} | Should -Throw
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 1
    }
    It 'original public entrypoint has Plan Audit Prepare Review but no real Move' {
        $entry=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3j.ps1') -Raw -Encoding UTF8
        $core=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3jRealOneShotPrepareIntent.ps1') -Raw -Encoding UTF8
        $entry | Should -Match "ValidateSet\('Plan','Audit','Prepare','Review'\)"
        $core | Should -Not -Match '\.Move\(|\.AddStoreEx\(|Add-OPADuplicateEntry'
        $core | Should -Match 'Write-OPAOperationJournalEvent'
        $core | Should -Match 'New-OPA265ARCH3bOperationContract'
    }
}
