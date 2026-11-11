#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Runtime/ARCH1DeliveryReadinessPolicy265.ps1')
    $script:controller=Get-Content -LiteralPath (
        Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265ARCH1DeliveryReadinessAudit.ps1') -Raw -Encoding UTF8
    function New-ARCH1Fixture {
        [pscustomobject][ordered]@{
            EntryPoint="Archive -Mode 'Archive' Move-OPAItemsWithLimit"
            Mover='$item.Move($folder) ' + "Reason='MoveFailed' continue"
            Verifier='Test-OPAArchiveItemFingerprint Subject Size InternetMessageId'
            Grouping="function Get-OPAArchiveGroupParts { 'Year' }"
            Planner='function Get-OPAEligiblePop3MailFolders'
            Journal='function Write-OPAOperationJournalEvent'
            DuplicateIndex='function Test-OPADuplicateEntry'
            SystemFolders='Outbox; Исходящие'
            Release=[pscustomobject]@{
                Integration=[pscustomobject]@{
                    ArchiveWorkerEnabled=$false;ResumeWorkerEnabled=$false;AutoWorkerEnabled=$false
                }
                Verification=[pscustomobject]@{ExpectedPesterTests=3625;ExpectedTestContainers=122}
            }
        }
    }
}
Describe 'ARCH1 delivery pivot is source-code audit, never a production certification' {
    It 'returns documented source-only schema' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).Schema |
            Should -BeExactly '2.6.5-ARCH1.StaticDeliveryAudit.1'
    }
    It 'does not mark 90GB production as safe' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).SafeFor90GBProductionArchive | Should -BeFalse
    }
    It 'does not grant any writer permit' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).WriterPermit | Should -BeFalse
    }
    It 'does not conflate code markers with runtime verification' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).SourceMarkerEvidenceIsNotRuntimeCertification | Should -BeTrue
    }
    It 'recognizes direct archive CLI code as present but uncertified' {
        $r=Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)
        $r.DirectArchiveEntrypointPresent | Should -BeTrue
        @($r.AuditRows | Where-Object Area -eq 'DirectArchiveEntrypoint')[0].State | Should -BeExactly 'PresentNotCertified'
    }
    It 'does not assume disabled worker switches disable legacy Archive entrypoint' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).DirectArchiveModeNotAutomaticallyBlockedByWorkerSwitches | Should -BeTrue
    }
    It 'records legacy direct MailItem.Move and absent Copy path' {
        $r=Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)
        $r.LegacyDirectMovePresent | Should -BeTrue
        $r.CopyThenVerifyDeleteIntegrated | Should -BeFalse
    }
    It 'flags ambiguous COM Move exception continue as a critical gap' {
        $r=Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)
        $r.LegacyMoveFailureContinuePatternDetected | Should -BeTrue
        @($r.AuditRows | Where-Object Area -eq 'AmbiguousMoveFailure')[0].State | Should -BeExactly 'CriticalGap'
    }
    It 'reports critical readiness gaps' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).CriticalGapsDetected | Should -BeTrue
    }
    It 'does not claim legacy verifier checks Body HTML and attachment byte hashes' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).LegacyVerifierIncludesFullBodyHtmlAttachmentWitness | Should -BeFalse
    }
    It 'prioritizes integrating existing BW4k semantic witness' {
        $r=Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)
        @($r.AuditRows | Where-Object Area -eq 'ArchiveVerifier')[0].NextAction | Should -Match 'BW4k semantic witness'
    }
    It 'recognizes Year grouping code without claiming end-to-end coverage' {
        $r=Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)
        $r.YearGroupingPresentInSource | Should -BeTrue
        @($r.AuditRows | Where-Object Area -eq 'YearGrouping')[0].State | Should -BeExactly 'ImplementedInSourceNotIntegrated'
    }
    It 'requires explicit year archive CLI scope test' {
        $r=Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)
        @($r.AuditRows | Where-Object Area -eq 'YearGrouping')[0].NextAction | Should -Match 'ArchiveGrouping Year'
    }
    It 'recognizes POP3 recursive folder and Outbox markers' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).Pop3FolderScopeMarkersPresent | Should -BeTrue
    }
    It 'recognizes existing journal and duplicate index code' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).JournalAndDuplicateModulesPresent | Should -BeTrue
    }
    It 'does not promote journal presence to proven crash safety' {
        $r=Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)
        @($r.AuditRows | Where-Object Area -eq 'JournalAndDuplicates')[0].State | Should -BeExactly 'ImplementedInSourceNotProven'
    }
    It 'reads disabled Worker integration switches accurately' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).ArchiveWorkerIntegrationSwitchesEnabled | Should -BeFalse
    }
    It 'does not treat enabled switches as runtime execution proof' {
        $x=New-ARCH1Fixture
        $x.Release.Integration.ArchiveWorkerEnabled=$true
        $x.Release.Integration.ResumeWorkerEnabled=$true
        @((Test-OPA265ARCH1DeliveryReadiness -Evidence $x).AuditRows |
           Where-Object Area -eq 'WorkerIntegration')[0].State | Should -BeExactly 'DeclaredEnabledUnproven'
    }
    It 'does not authorize another size-only MAPI forensic branch' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).NewMapiSizeOrFlagForensicsAuthorizedByThisBuild | Should -BeFalse
    }
    It 'forbids replaying any historical one-shot Move claim' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).PreviousLiveMoveClaimsMayBeRetried | Should -BeFalse
    }
    It 'requires byte SHA256 and logical user-content witness' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).RequiredOriginalMessageContentAndAttachmentShaValidation | Should -BeTrue
    }
    It 'rejects missing source evidence' {
        $x=New-ARCH1Fixture
        [void]$x.PSObject.Properties.Remove('Mover')
        {Test-OPA265ARCH1DeliveryReadiness -Evidence $x} | Should -Throw
    }
    It 'rejects null release evidence' {
        $x=New-ARCH1Fixture;$x.Release=$null
        {Test-OPA265ARCH1DeliveryReadiness -Evidence $x} | Should -Throw
    }
    It 'rejects incomplete integration metadata' {
        $x=New-ARCH1Fixture;$x.Release.Integration=$null
        {Test-OPA265ARCH1DeliveryReadiness -Evidence $x} | Should -Throw
    }
    It 'rejects missing release verification metadata' {
        $x=New-ARCH1Fixture;$x.Release.Verification=$null
        {Test-OPA265ARCH1DeliveryReadiness -Evidence $x} | Should -Throw
    }
    It 'marks removed Year grouping as missing rather than implemented' {
        $x=New-ARCH1Fixture;$x.Grouping='removed'
        (Test-OPA265ARCH1DeliveryReadiness -Evidence $x).YearGroupingPresentInSource | Should -BeFalse
    }
    It 'marks removed Outbox exclusion as not proven' {
        $x=New-ARCH1Fixture;$x.SystemFolders='none'
        (Test-OPA265ARCH1DeliveryReadiness -Evidence $x).Pop3FolderScopeMarkersPresent | Should -BeFalse
    }
    It 'marks missing operation journal as not implemented' {
        $x=New-ARCH1Fixture;$x.Journal='none'
        (Test-OPA265ARCH1DeliveryReadiness -Evidence $x).JournalAndDuplicateModulesPresent | Should -BeFalse
    }
    It 'marks changed mover implementation for a fresh audit' {
        $x=New-ARCH1Fixture;$x.Mover='different API'
        @((Test-OPA265ARCH1DeliveryReadiness -Evidence $x).AuditRows |
            Where-Object Area -eq 'LegacyMover')[0].State | Should -BeExactly 'RequiresManualAudit'
    }
    It 'returns one row for each of eight readiness areas' {
        (Test-OPA265ARCH1DeliveryReadiness -Evidence (New-ARCH1Fixture)).AuditRows.Count | Should -Be 8
    }
    It 'controller has Plan and Audit with no Outlook COM connection' {
        $script:controller | Should -Match "ValidateSet\('Plan','Audit'\)"
        $script:controller | Should -Not -Match 'GetActiveObject|New-Object -ComObject|GetNamespace'
    }
    It 'controller only reads project files and produces source SHA hashes' {
        $script:controller | Should -Match 'Get-FileHash'
        $script:controller | Should -Not -Match 'Set-Content|Out-File|WriteAllText|WriteAllBytes|CreateDirectory'
    }
    It 'controller does not call any Outlook or PST writer' {
        $script:controller | Should -Not -Match '\.(Move|Copy|Save|Delete|Send|AddStore|AddStoreEx|RemoveStore)\s*\('
        $script:controller | Should -Not -Match 'New-Item|Remove-Item|Set-ItemProperty|SaveAsFile'
    }
    It 'controller explicitly reports zero PST and mailbox reads' {
        $script:controller | Should -Match 'AnyPstOrMailRead=\$false'
        $script:controller | Should -Match 'AnyPstOrMailWriter=\$false'
    }
    It 'controller cannot return any production write permit' {
        $script:controller | Should -Match 'ProductionReady=\$false'
        $script:controller | Should -Match 'WriterPermit=\$false'
    }
}
