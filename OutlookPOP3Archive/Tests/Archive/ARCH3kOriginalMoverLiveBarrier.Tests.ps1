#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3kOriginalMoverLiveBarrier.ps1')
    $script:runId='9d276dc4-a0e6-4e74-891f-81502fafe7db'
    $script:intentSha='f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b'
    $script:journalSha='a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'
    $script:sourceId='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    $script:folderId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
    $script:sha='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
    function New-ARCH3kFakePrepared {
        $sealed=[pscustomobject]@{
            RunId='3773bcd7-5a07-4c31-8ce5-dfb16ddd30bf'
            SourcePst='C:\Fake\info@stios.ru.pst'
            SourceEntryId=$script:sourceId
            SourceFolderEntryId=$script:folderId
            SourceStoreIdSha256=(Get-OPA265ARCH2bTextSha256 -Text 'ARCH3K-FAKE-STORE')
            ArchiveDateLocalTicks=([datetime]'2020-02-13T12:57:58').Ticks
            OriginalWitnessSha256=$script:sha
        }
        return [pscustomobject]@{
            Layout=[pscustomobject]@{RunId=$script:runId}
            Intent=[pscustomobject]@{
                SourceEntryId=$script:sourceId
                ExistingArchivePart1='C:\Fake\info@stios.ru.Archive-2020.pst'
                NewArchivePst='C:\Fake\info@stios.ru.Archive-2020-02.pst'
                OriginalContractSha256=('b'*64)
                OperationId=('ARCH3b-'+('b'*64))
            }
            Sealed=$sealed
            Review=[pscustomobject]@{OriginalOperationJournalIntentWritten=$true}
        }
    }
    function New-ARCH3kFakeSession {
        $folder=[pscustomobject]@{
            EntryID=$script:folderId
            StoreID='ARCH3K-FAKE-STORE'
            FolderPath='\\info@stios.ru\Входящие'
        }
        $item=[pscustomobject]@{
            EntryID=$script:sourceId
            Class=43
            Parent=$folder
            ReceivedTime=[datetime]'2020-02-13T12:57:58'
            SentOn=[datetime]'2020-02-13T12:57:58'
        }
        $ns=[pscustomobject]@{}
        $ns | Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {
            param($entry,$store)
            return $script:fakeMail
        }
        $script:fakeMail=$item
        $script:fakeFolder=$folder
        return [pscustomobject]@{
            SourceStore=[pscustomobject]@{StoreID='ARCH3K-FAKE-STORE'}
            Scope=[pscustomobject]@{Approved=$true}
            Namespace=$ns;Inbox=$folder
            OutlookProcessId=11168
            OutlookProcessStartUtcTicks=[long]639300867186071455
        }
    }
}
Describe 'ARCH3k original MailMover source backed risk model' {
    It 'detects existing-part selection, preverification DuplicateIndex and real Move in original code' {
        $r=Get-OPA265ARCH3kOriginalMoverUnsafeDefaultMarkers
        $r.GenericMoverMayAppendToExistingYearPart1 | Should -BeTrue
        $r.GenericMoverHealsSharedDuplicateIndexBeforeMove | Should -BeTrue
        $r.GenericMoverAppendsSharedDuplicateIndexBeforeIndependentRestart | Should -BeTrue
        $r.ProtectedARCH3dBoundaryIsSyntheticOnly | Should -BeTrue
        $r.DirectGenericMoverSafeForPinnedPart2 | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.OriginalMailMoverSha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'does not modify original MailMover to add any new unverified live writer' {
        $text=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $text | Should -Not -Match 'Invoke-OPA265ARCH3kOneOriginalMailMoverCall'
        $text | Should -Match 'function Move-OPAItemsWithLimit'
    }
    It 'rejects another operator RunId without touching files' {
        {Assert-OPA265ARCH3kPinnedPreparation -RunId ([guid]::NewGuid().ToString('D')) -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects changed persisted PrepareIntent SHA' {
        {Assert-OPA265ARCH3kPinnedPreparation -RunId $script:runId -IntentSha256 ('f'*64) -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects changed original OperationJournal SHA' {
        {Assert-OPA265ARCH3kPinnedPreparation -RunId $script:runId -IntentSha256 $script:intentSha -JournalSha256 ('f'*64)} | Should -Throw
    }
}
Describe 'ARCH3k operator Plan never connects to Outlook or creates any PST' {
    BeforeEach {
        Mock Assert-OPA265ARCH3kPinnedPreparation {return (New-ARCH3kFakePrepared)}
        Mock Open-OPA265ARCH2dSession {throw 'Plan may not open Outlook'}
    }
    It 'returns deterministic original unsafe mass writer warnings with WriterPermit False' {
        $r=Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode Plan -RunId $script:runId -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha
        $r.Status | Should -BeExactly 'PreparedOriginalRealMoverRiskGateNoOutlookOrWrites'
        $r.OutlookContacted | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $r.GenericMoverPart1AndIndexRiskDetected | Should -BeTrue
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
}
Describe 'ARCH3k fake Outlook pure read-only verification cannot call Move' {
    BeforeEach {
        $script:mockPrepared=New-ARCH3kFakePrepared
        $script:mockSession=New-ARCH3kFakeSession
        Mock Assert-OPA265ARCH3kPinnedPreparation {return $script:mockPrepared}
        Mock Get-OPA265ARCH2dLayout {return [pscustomobject]@{ArchivePst='C:\Fake\missing.pst'}}
        Mock Open-OPA265ARCH2dSession {return $script:mockSession}
        Mock Close-OPA265ARCH2dSession {}
        Mock Release-OPA265ARCH2c4Com {}
        Mock Get-OPA265ARCH2bMailSemanticWitness {return [pscustomobject]@{Schema='2.6.5-ARCH2b.MailSemanticWitness.1'}}
        Mock Assert-OPA265ARCH3iFullWitnessPinned {return $script:sha}
        Mock Get-OPA265ARCH3jOriginalRoutePlan {
            return [pscustomobject]@{
                OperationId=('ARCH3b-'+('b'*64))
                ContractSha256=('b'*64)
                PlannedArchivePst='C:\Fake\info@stios.ru.Archive-2020-02.pst'
                PlannedTargetFolderPath='2020\Входящие'
                SourceFolderPath='\\info@stios.ru\Входящие'
            }
        }
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$true;EntryCount=500;IndexReadOnly=$true}}
    }
    It 'audits the exact original 2020 POP3 source and 500 shared index entries without writes' {
        $r=Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode Audit -RunId $script:runId -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha
        $r.Status | Should -BeExactly 'ExactOriginalPOP3SemanticAndPart2RevalidatedMassWriterStillBlocked'
        $r.OriginalIndexEntryCount | Should -Be 500
        $r.FullWitnessSha256 | Should -BeExactly $script:sha
        $r.MoveClaimed | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 1
        Should -Invoke Get-OPA265ARCH2bMailSemanticWitness -Exactly -Times 1
    }
    It 'rejects changed original MailItem EntryID' {
        $script:fakeMail.EntryID='00000000FFFFFFFFFFFFFFFFFFFFFFFF'
        {Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode Audit -RunId $script:runId -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
        Should -Invoke Get-OPA265ARCH2bMailSemanticWitness -Exactly -Times 0
    }
    It 'rejects changed POP3 source StoreID' {
        $script:mockSession.SourceStore.StoreID='BAD-STORE'
        {Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode Audit -RunId $script:runId -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
    It 'rejects source folder escape from approved Inbox' {
        $script:fakeFolder.EntryID='00000000FFFFFFFFFFFFFFFFFFFFFFFF'
        {Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode Audit -RunId $script:runId -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
        Should -Invoke Get-OPA265ARCH2bMailSemanticWitness -Exactly -Times 0
    }
    It 'rejects source full semantic SHA drift before any destination selection' {
        Mock Assert-OPA265ARCH3iFullWitnessPinned {throw 'hash drift'}
        {Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode Audit -RunId $script:runId -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
        Should -Invoke Get-OPA265ARCH3jOriginalRoutePlan -Exactly -Times 0
    }
    It 'rejects a late duplicate index collision instead of moving mail' {
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$false;Reason='SourceAlreadyInOriginalSharedDuplicateIndex'}}
        {Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode Audit -RunId $script:runId -IntentSha256 $script:intentSha -JournalSha256 $script:journalSha} | Should -Throw
    }
}
Describe 'ARCH3k public CLI contains no writer route' {
    It 'exposes only Plan and Audit and preserves original production Archive/Resume/Auto gates' {
        $entry=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3k.ps1') -Raw -Encoding UTF8
        $core=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3kOriginalMoverLiveBarrier.ps1') -Raw -Encoding UTF8
        $entry | Should -Match "ValidateSet\('Plan','Audit'\)"
        $entry | Should -Not -Match "ValidateSet\('Plan','Audit','Move'"
        $core | Should -Not -Match '\.Move\(|\.AddStoreEx\(|Write-OPA265ARCH3cJsonOnce|Write-OPAOperationJournalEvent|Add-OPADuplicateEntry'
        $core | Should -Match 'Get-OPA265ARCH3kOriginalMoverUnsafeDefaultMarkers'
    }
}
