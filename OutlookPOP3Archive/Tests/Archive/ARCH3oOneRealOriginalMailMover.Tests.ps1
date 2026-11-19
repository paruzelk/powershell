#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3oOneRealOriginalMailMover.ps1')
    $script:run='9d276dc4-a0e6-4e74-891f-81502fafe7db'
    $script:intent='f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b'
    $script:journal='a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'
    $script:id='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    $script:folderId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
    $script:sha='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
    function New-ARCH3oFakePlan {
        param([string]$Root)
        return [pscustomobject]@{
            RunId=$script:run;SourceEntryId=$script:id
            RealSourcePst=(Join-Path $Root 'info@stios.ru.pst')
            ExistingPart1=(Join-Path $Root 'info@stios.ru.Archive-2020.pst')
            UnusedPart2=(Join-Path $Root 'info@stios.ru.Archive-2020-02.pst')
            OriginalWitnessSha256=$script:sha
            SourceStoreIdSha256=(Get-OPA265ARCH2bTextSha256 -Text 'FAKE-POP3-STORE')
            SourceFolderEntryId=$script:folderId
            OriginalContractSha256='2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
            OriginalOperationId='ARCH3b-2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
            SourceSealRunId='3773bcd7-5a07-4c31-8ce5-dfb16ddd30bf'
            SourceSealSha256='5f5a86b6c1aba8a3d2ee328a36a5632f8edf1e89fdda8e7fd728688fe881b2a4'
            OriginalSharedIndexEntryCount=500
        }
    }
}
Describe 'ARCH3o public entry and source-backed no-replay boundary' {
    It 'has explicit Plan Audit Move Status only, ConfirmOneRealMove and WhatIf' {
        $cli=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3o.ps1') -Raw -Encoding UTF8
        $cli | Should -Match "ValidateSet\('Plan','Audit','Move','Status'\)"
        $cli | Should -Match 'ConfirmOneRealMove'
        $cli | Should -Match 'WhatIf'
        $cli | Should -Not -Match 'Resume'
    }
    It 'writes all protected stages before one original MailMover Move and not shared index' {
        $core=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3oOneRealOriginalMailMover.ps1') -Raw -Encoding UTF8
        $mover=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $core | Should -Match 'ARCH3o-WriterEntry.json'
        $core | Should -Match 'ARCH3o-DestinationReady.json'
        $core | Should -Match 'ARCH3o-MoveClaimed.json'
        $core | Should -Match 'Invoke-OPA265ARCH3oOneOriginalMailMoverProviderCall'
        $core | Should -Not -Match '(?m)^\s*Add-OPADuplicateEntry\s'
        $mover | Should -Match 'ARCH3o-ProviderInvocation.json'
        $mover | Should -Match '\$moved=\$Mail\.Move\(\$Folder\)'
    }
    It 'rejects external operator Move permit during Plan' {
        Mock Get-OPA265ARCH3nPinnedRealRoute {throw 'Must not read'}
        {Invoke-OPA265ARCH3oOneRealPop3Move -Mode Plan -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove} | Should -Throw
        Should -Invoke Get-OPA265ARCH3nPinnedRealRoute -Exactly -Times 0
    }
    It 'rejects Move without explicit confirmation before contacting Outlook' {
        Mock Get-OPA265ARCH3nPinnedRealRoute {return (New-ARCH3oFakePlan -Root $TestDrive)}
        Mock Get-OPA265ARCH3jLayout {
            [pscustomobject]@{RunId=$script:run;Root=$TestDrive}
        }
        [IO.File]::WriteAllText((Join-Path $TestDrive 'original-prepare-intent.json'),'intent')
        [IO.File]::WriteAllText((Join-Path $TestDrive 'original-operation-journal.jsonl'),'journal')
        Mock Open-OPA265ARCH2dSession {throw 'Forbidden'}
        {Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal} | Should -Throw
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
    It 'public Move WhatIf does not connect Outlook and leaves evidence unchanged' {
        Mock Get-OPA265ARCH3nPinnedRealRoute {return (New-ARCH3oFakePlan -Root $TestDrive)}
        Mock Get-OPA265ARCH3jLayout {[pscustomobject]@{RunId=$script:run;Root=$TestDrive}}
        [IO.File]::WriteAllText((Join-Path $TestDrive 'original-prepare-intent.json'),'intent')
        [IO.File]::WriteAllText((Join-Path $TestDrive 'original-operation-journal.jsonl'),'journal')
        Mock Open-OPA265ARCH2dSession {throw 'Forbidden'}
        $r=Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -WhatIf
        $r.Status | Should -BeExactly 'WhatIfBeforeOutlookAndPstWrites'
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
        [IO.Directory]::GetFileSystemEntries($TestDrive).Count | Should -Be 2
    }
}
Describe 'ARCH3o real Outlook facade with only one original MailMover call' {
    BeforeEach {
        $script:p=New-ARCH3oFakePlan -Root $TestDrive
        $script:base=Join-Path $TestDrive 'evidence'
        [void][IO.Directory]::CreateDirectory($script:base)
        [IO.File]::WriteAllText((Join-Path $script:base 'original-prepare-intent.json'),'intent')
        [IO.File]::WriteAllText((Join-Path $script:base 'original-operation-journal.jsonl'),'journal')
        [IO.File]::WriteAllBytes($script:p.ExistingPart1,(New-Object byte[] 271360))
        $script:fakeParent=[pscustomobject]@{
            EntryID=$script:folderId;StoreID='FAKE-POP3-STORE'
            FolderPath='\\info@stios.ru\Входящие';Name='Входящие'
        }
        $script:fakeMail=[pscustomobject]@{EntryID=$script:id;Class=43;Parent=$script:fakeParent}
        $ns=[pscustomobject]@{}
        $ns | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {param($entry,$store)return $script:fakeMail}
        $script:session=[pscustomobject]@{
            Scope=[pscustomobject]@{Approved=$true}
            SourceStore=[pscustomobject]@{StoreID='FAKE-POP3-STORE'}
            Namespace=$ns;Inbox=$script:fakeParent;DefaultStoreId='DEFAULT-STORE'
            Accounts=@([pscustomobject]@{DeliveryStoreId='FAKE-POP3-STORE'})
            OutlookProcessId=4567;OutlookProcessStartUtcTicks=[long]1234567890
        }
        $script:archive=[pscustomobject]@{StoreID='NEW-ARCHIVE-STORE';FilePath=$script:p.UnusedPart2}
        $script:folder=[pscustomobject]@{
            StoreID='NEW-ARCHIVE-STORE';EntryID='00000000DEADBEEFDEADBEEFDEADBEEF'
            FolderPath='\\Fake Archive\2020\Входящие';Items=@()
        }
        $script:providerCalls=0;$script:sharedIndexCalls=0;$script:archiveCreateCalls=0
        Mock Get-OPA265ARCH3nPinnedRealRoute {return $script:p}
        Mock Get-OPA265ARCH3jLayout {[pscustomobject]@{RunId=$script:run;Root=$script:base}}
        Mock Get-OPA265ARCH2dLayout {[pscustomobject]@{ArchivePst=$script:p.UnusedPart2}}
        Mock Open-OPA265ARCH2dSession {return $script:session}
        Mock Close-OPA265ARCH2dSession {}
        Mock Release-OPA265ARCH2c4Com {}
        Mock Get-OPA265ARCH3jSealedSource {return [pscustomobject]@{ArchiveDateLocalTicks=([datetime]'2020-02-13T12:57:58').Ticks}}
        Mock Get-OPAArchiveItemDate {return [datetime]'2020-02-13T12:57:58'}
        Mock Get-OPA265ARCH2bMailSemanticWitness {return [pscustomobject]@{Schema='FAKE'}}
        Mock Assert-OPA265ARCH3iFullWitnessPinned {return $script:sha}
        Mock Get-OPA265ARCH3jOriginalRoutePlan {
            return [pscustomobject]@{
                ContractSha256=$script:p.OriginalContractSha256;OperationId=$script:p.OriginalOperationId
                PlannedArchivePst=$script:p.UnusedPart2
            }
        }
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$true;EntryCount=500}}
        Mock Get-OpaStoreByPathCached {$null}
        Mock New-OPAArchivePst {
            $script:archiveCreateCalls++
            [IO.File]::WriteAllText($script:p.UnusedPart2,'new PST fake allocation')
            return $script:archive
        }
        Mock Get-OPAArchiveFolder {return $script:folder}
        Mock Invoke-OPA265ARCH3oOneOriginalMailMoverProviderCall {
            $script:providerCalls++
            return [pscustomobject]@{
                OneMoveReturned=$true;DestinationEntryId='00000000CAFEBABECAFEBABECAFEBABE'
                ProviderInvocationSha256=('d'*64)
            }
        }
        Mock Add-OPADuplicateEntry {$script:sharedIndexCalls++;throw 'Index append forbidden before postrestart verifier'}
        Mock Write-OPAOperationJournalEvent {throw 'Original terminal journal event forbidden before postrestart verifier'}
    }
    It 'audits exact source and 500 shared index entries with no PST creation' {
        $r=Invoke-OPA265ARCH3oOneRealPop3Move -Mode Audit -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal
        $r.Status | Should -BeExactly 'ExactOriginalRealSourceFullWitnessAndUnusedPart2ReadOnlyNoMove'
        $r.WriterPermit | Should -BeFalse
        $script:archiveCreateCalls | Should -Be 0
        $script:providerCalls | Should -Be 0
    }
    It 'performs exactly one fake original provider call after WriteEntry, DestinationReady and MoveClaimed' {
        $r=Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -Confirm:$false
        $r.Status | Should -BeExactly 'OneRealPop3OriginalMailMoverReturnedIndependentOutlookRestartRequired'
        $r.MoveClaimed | Should -BeTrue
        $r.IndependentPostRestartVerified | Should -BeFalse
        $r.DuplicateIndexWritten | Should -BeFalse
        $script:archiveCreateCalls | Should -Be 1
        $script:providerCalls | Should -Be 1
        $script:sharedIndexCalls | Should -Be 0
        foreach($x in @('WriterEntry','DestinationReady','MoveClaimed','MoveReturned')){
            [IO.File]::Exists((Join-Path $script:base ('ARCH3o-'+$x+'.json'))) | Should -BeTrue
        }
    }
    It 'refuses any retry after first fake MoveReturned before provider' {
        [void](Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -Confirm:$false)
        {Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -Confirm:$false} | Should -Throw
        $script:providerCalls | Should -Be 1
    }
    It 'refuses stale duplicate index BEFORE any irreversible WriterEntry' {
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$false;EntryCount=500}}
        {Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -Confirm:$false} | Should -Throw
        [IO.File]::Exists((Join-Path $script:base 'ARCH3o-WriterEntry.json')) | Should -BeFalse
    }
    It 'refuses changed original full semantic witness before WriterEntry' {
        Mock Assert-OPA265ARCH3iFullWitnessPinned {throw 'content changed'}
        {Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -Confirm:$false} | Should -Throw
        $script:providerCalls | Should -Be 0
    }
    It 'refuses a reused Part2 before creating a WriterEntry' {
        [IO.File]::WriteAllText($script:p.UnusedPart2,'occupied')
        {Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -Confirm:$false} | Should -Throw
        $script:archiveCreateCalls | Should -Be 0
    }
    It 'refuses nonempty original Year2020 target after WriterEntry, preserving no-retry marker' {
        $script:folder.Items=@(1)
        {Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -Confirm:$false} | Should -Throw
        [IO.File]::Exists((Join-Path $script:base 'ARCH3o-WriterEntry.json')) | Should -BeTrue
        [IO.File]::Exists((Join-Path $script:base 'ARCH3o-MoveClaimed.json')) | Should -BeFalse
    }
    It 'refuses a wrong archive account delivery store after WriterEntry' {
        $script:session.Accounts=@([pscustomobject]@{DeliveryStoreId='NEW-ARCHIVE-STORE'})
        {Invoke-OPA265ARCH3oOneRealPop3Move -Mode Move -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ConfirmOneRealMove -Confirm:$false} | Should -Throw
        $script:providerCalls | Should -Be 0
    }
}
