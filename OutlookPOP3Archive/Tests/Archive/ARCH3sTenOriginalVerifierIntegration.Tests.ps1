#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3sTenOriginalVerifierIntegration.ps1')
}
Describe 'ARCH3s ORIGINAL Outlook ArchiveVerifier fake-ten full witness boundary' {
    It 'uses the unmodified ORIGINAL ArchiveVerifier with ten unique physical fake items' {
        $r=Invoke-OPA265ARCH3sTen -Mode VerifierOnly -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeTrue
        $r.OriginalArchiveVerifierUsed | Should -BeTrue
        $r.OriginalArchiveVerifierImplementationReplaced | Should -BeFalse
        $r.ExpectedMoved | Should -Be 10
        $r.ExpectedEntryIdsChecked | Should -Be 10
        $r.ObservedSourceCount | Should -Be 0
        $r.ObservedArchiveFolderCount | Should -Be 10
        @($r.MissingCodes).Count | Should -Be 0
        $r.OriginalJournalIndexIntegrationExecuted | Should -BeFalse
        $r.RealOutlookContacted | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'genuine ORIGINAL full ARCH2b MailItem witness hashes fake SaveAsFile payloads by value' {
        $parent=[pscustomobject]@{FolderPath='\\SYNTHETIC-ARCHIVE\2020\Входящие'}
        $mail=New-OPA265ARCH3sFakeMail -Number 4 -EntryId ('A'*32) -Parent $parent
        $actual=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
        $original=New-OPA265ARCH3rSyntheticWitness -Number 4
        $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $original -Destination $actual
        $cmp.CriticalContentMatches | Should -BeTrue
        @($cmp.IssueCodes).Count | Should -Be 0
        $actual.AttachmentCount | Should -Be 1
        $actual.Attachments[0].PayloadSha256 | Should -BeExactly $original.Attachments[0].PayloadSha256
        $actual.MailItemSizeDiagnosticBytes | Should -Be 2090
    }
    It 'accepts a single stale EntryID only when unique original full content fingerprint exists' {
        $r=Invoke-OPA265ARCH3sTen -VerifierFault StaleArchiveIdUnique -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeTrue
        @($r.WarningCodes | Where-Object {$_ -like 'STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT:*'}).Count | Should -Be 1
    }
    It 'requires original source EntryID to disappear, rejects still-present mail' {
        $r=Invoke-OPA265ARCH3sTen -VerifierFault SourceStillPresent -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        $r.ObservedSourceCount | Should -Be 1
        @($r.MissingCodes | Where-Object {$_ -like 'STILL_IN_SOURCE:*'}).Count | Should -Be 1
        $r.OriginalJournalIndexIntegrationExecuted | Should -BeFalse
    }
    It 'rejects missing archived fake mail and never appends original journal' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault DestinationMissing -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        $r.ObservedArchiveFolderCount | Should -Be 9
        $r.OriginalJournalIndexIntegrationExecuted | Should -BeFalse
        $r.OriginalSharedIndexEntryCount | Should -Be 0
    }
    It 'rejects an extra destination copy even if original verifier checks expected ten' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault ExtraDestination -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        $r.ObservedArchiveFolderCount | Should -Be 11
        $r.OriginalJournalIndexIntegrationExecuted | Should -BeFalse
    }
    It 'detects HTML-body sha drift through the ORIGINAL witness builder' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault HtmlDrift -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        @($r.MissingCodes | Where-Object {$_ -like 'ARCHIVE_ITEM_NOT_VERIFIED:*'}).Count | Should -BeGreaterThan 0
        $r.OriginalJournalIndexIntegrationExecuted | Should -BeFalse
    }
    It 'detects plaintext-body sha drift through original verifier' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault BodyDrift -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        $r.OriginalSharedIndexEntryCount | Should -Be 0
    }
    It 'detects recipient address SHA mismatch before original journal' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault RecipientDrift -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        $r.OriginalJournalReconciledCount | Should -Be 0
    }
    It 'detects attachment byte mutation with SAME byte length via real TEMP SaveAsFile SHA' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault AttachmentDrift -FaultAt 4 -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        $r.OriginalJournalIndexIntegrationExecuted | Should -BeFalse
    }
    It 'rejects missing ORIGINAL pre-Move full semantic witness' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault MissingOriginalWitness -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        @($r.MissingCodes | Where-Object {$_ -like '*SEMANTIC_WITNESS_MISSING_OR_INVALID*'}).Count | Should -BeGreaterThan 0
    }
    It 'rejects repeated source EntryID across expected ten' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault DuplicateSourceSelector -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        @($r.MissingCodes | Where-Object {$_ -like '*DUPLICATE_OR_EMPTY_SOURCE_ID*'}).Count | Should -BeGreaterThan 0
    }
    It 'rejects repeated archive EntryID across expected ten' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault DuplicateArchiveSelector -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        @($r.MissingCodes | Where-Object {$_ -like '*DUPLICATE_OR_EMPTY_ARCHIVE_ID*'}).Count | Should -BeGreaterThan 0
    }
    It 'rejects wrong target folder in original archive PST' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault WrongTargetFolder -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        @($r.MissingCodes | Where-Object {$_ -like 'ARCHIVE_FOLDER_UNREADABLE:*'}).Count | Should -BeGreaterThan 0
    }
    It 'rejects ambiguous stale archived ID fingerprint with two physical copies' {
        $r=Invoke-OPA265ARCH3sTen -VerifierFault StaleArchiveIdAmbiguous -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeFalse
        $r.ObservedArchiveFolderCount | Should -Be 11
    }
}
Describe 'ARCH3s original verifier BEFORE original journal/index ten full integration' {
    It 'successfully orders ORIGINAL ArchiveVerifier then ten original Reconciled and ten original index readbacks' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -SyntheticTempRoot $TestDrive
        $r.Status | Should -BeExactly 'OriginalArchiveVerifierTenThenOriginalJournalIndexTenFullReadbackNoLiveWriter'
        $r.OriginalArchiveVerifierPassed | Should -BeTrue
        $r.OriginalJournalIndexIntegrationExecuted | Should -BeTrue
        $r.OriginalJournalEventCount | Should -Be 20
        $r.OriginalJournalReconciledCount | Should -Be 10
        $r.OriginalJournalIndeterminateCount | Should -Be 0
        $r.OriginalSharedIndexEntryCount | Should -Be 10
        $r.OriginalJournalSha256 | Should -Match '^[a-f0-9]{64}$'
        $r.OriginalSharedIndexSha256 | Should -Match '^[a-f0-9]{64}$'
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'partial original journal Reconciled after 3 verified fake items stops before any index append' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -JournalFault AfterJournalReconciled -FaultAt 3 -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeTrue
        $r.Status | Should -BeExactly 'OriginalArchiveVerifierTenThenSyntheticPartialJournalIndexCommitStoppedNoAutoRetry'
        $r.OriginalJournalReconciledCount | Should -Be 3
        $r.OriginalJournalEventCount | Should -Be 13
        $r.OriginalSharedIndexEntryCount | Should -Be 0
        $r.AutomaticMoveRetryAllowed | Should -BeFalse
    }
    It 'partial original index after two verified fake items retains 10 Reconciled but only 2 index entries' {
        $r=Invoke-OPA265ARCH3sTen -Mode Integration -JournalFault AfterIndexAppend -FaultAt 2 -SyntheticTempRoot $TestDrive
        $r.OriginalArchiveVerifierPassed | Should -BeTrue
        $r.Status | Should -BeExactly 'OriginalArchiveVerifierTenThenSyntheticPartialJournalIndexCommitStoppedNoAutoRetry'
        $r.OriginalJournalReconciledCount | Should -Be 10
        $r.OriginalJournalEventCount | Should -Be 20
        $r.OriginalSharedIndexEntryCount | Should -Be 2
        $r.AutomaticMoveRetryAllowed | Should -BeFalse
    }
    It 'refuses journal fault under VerifierOnly mode before writing anything' {
        {Invoke-OPA265ARCH3sTen -Mode VerifierOnly -JournalFault AfterIndexAppend -SyntheticTempRoot $TestDrive} | Should -Throw
    }
    It 'refuses combined verifier corruption and journal fault' {
        {Invoke-OPA265ARCH3sTen -Mode Integration -VerifierFault HtmlDrift -JournalFault AfterIndexAppend -SyntheticTempRoot $TestDrive} | Should -Throw
    }
    It 'refuses synthetic workspace outside OS TEMP' {
        $outside=[IO.Path]::GetPathRoot($TestDrive)
        {Invoke-OPA265ARCH3sTen -SyntheticTempRoot $outside} | Should -Throw
    }
    It 'uses original verifier, not a test double, and no real Move or AddStoreEx source' {
        $scriptPath=Join-Path $script:root 'Core/Archive/ARCH3sTenOriginalVerifierIntegration.ps1'
        $c=Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
        $c | Should -Match 'Test-OPAArchiveMoves @args'
        $c | Should -Not -Match 'Mock Test-OPAArchiveMoves'
        $c | Should -Not -Match '\.Move\('
        $c | Should -Not -Match 'AddStoreEx\s*\('
    }
    It 'requires UTF-8 BOM on every new PowerShell source' {
        foreach($path in @('Invoke-ARCH3s.ps1','Core/Archive/ARCH3sFakeOutlookTenObjects.ps1',
           'Core/Archive/ARCH3sTenOriginalVerifierIntegration.ps1')){
            $bytes=[IO.File]::ReadAllBytes((Join-Path $script:root $path))
            @($bytes[0..2]) -join ',' | Should -BeExactly '239,187,191'
        }
    }
}
