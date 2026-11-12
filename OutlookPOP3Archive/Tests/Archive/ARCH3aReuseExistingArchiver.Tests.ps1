#requires -Version 5.1
# ARCH3a: reuse existing legacy path, do NOT reimplement COM/Year/folder
# logic. All tests read source code or invoke pure existing functions only.
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Diagnostics/ARCH3aLegacyIntegrationAudit.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveGrouping.ps1')
    . (Join-Path $script:root 'Core/Archive/ArchiveSelector.ps1')
    . (Join-Path $script:root 'Core/Archive/SystemFolders.ps1')
    . (Join-Path $script:root 'Core/Archive/MailMover.ps1')
    $script:audit=Get-OPA265ARCH3aIntegrationAudit -ProjectRoot $script:root
    $script:source='C:\ARCH3aSyntheticNoPst\info@stios.ru.pst'
    $script:route=Get-OPA265ARCH3aExistingRoutingExamples -ProjectRoot $script:root -SourcePst $script:source
    function Get-ARCH3aText {
        param([Parameter(Mandatory=$true)][string]$Relative)
        [IO.File]::ReadAllText((Join-Path $script:root $Relative),[Text.Encoding]::UTF8)
    }
}
Describe 'ARCH3a architecture decision and exact original-code capability inventory' {
    It 'reports existing pipeline REUSE, never proposes a third archive writer' {
        $script:audit.Status | Should -BeExactly 'LegacyPipelineReuseConfirmedProductionIntegrationStillBlocked'
        $script:audit.LegacyFunctionalityMustBeReused | Should -BeTrue
        $script:audit.ExistingMoverWillNotBeReplaced | Should -BeTrue
    }
    It 'all expected original capability markers exist in actual current source' {
        $script:audit.ChecksPresent | Should -Be $script:audit.RequiredChecks
        @($script:audit.MissingChecks).Count | Should -Be 0
        $script:audit.RequiredChecks | Should -BeGreaterThan 14
    }
    It 'source module inventory includes all expected present SHA256 file identities' {
        $script:audit.ModuleInventory.Count | Should -BeGreaterThan 12
        @($script:audit.ModuleInventory|Where-Object{-not $_.Exists}).Count | Should -Be 0
        @($script:audit.ModuleInventory|Where-Object{$_.CurrentSha256 -notmatch '^[a-f0-9]{64}$'}).Count | Should -Be 0
    }
    It 'labels static source evidence as NOT a runtime certification' {
        $script:audit.SourceMarkerEvidenceIsNotRuntimeCertification | Should -BeTrue
        @($script:audit.CapabilityChecks|Where-Object{$_.EvidenceKind -cne 'StaticSourceMarkersOnly'}).Count | Should -Be 0
    }
    It 'safely refuses missing original project files rather than inventing functionality' {
        $p=Join-Path $TestDrive ('ARCH3aMissing-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($p)
        {Test-OPA265ARCH3aCapabilities -ProjectRoot $p} | Should -Throw
    }
    It 'unchanged original grouping module is explicitly mapped for reuse' {
        @($script:audit.CapabilityChecks|Where-Object{$_.Code -eq 'SRC-GROUP-YEAR' -and $_.Disposition -eq 'Reuse'}).Count | Should -Be 1
    }
    It 'unchanged original archive destination is mapped for reuse' {
        @($script:audit.CapabilityChecks|Where-Object{$_.Code -eq 'SRC-ARCHIVE-DEST' -and $_.Disposition -eq 'Reuse'}).Count | Should -Be 1
    }
    It 'the original recursive POP3 folder walker is mapped for reuse' {
        @($script:audit.CapabilityChecks|Where-Object{$_.Code -eq 'SRC-FOLDER-RECURSION' -and $_.Disposition -eq 'Reuse'}).Count | Should -Be 1
    }
    It 'original Transaction / OperationJournal / DuplicateIndex map to integration rather than rewrite' {
        foreach($code in @('SRC-STEP-JOURNAL','SRC-OP-JOURNAL','SRC-DUPLICATE-INDEX')){
            @($script:audit.CapabilityChecks|Where-Object{$_.Code -ceq $code -and $_.Disposition -ceq 'Integrate'}).Count | Should -Be 1
        }
    }
    It 'the original archive verifier already contains full semantic comparison' {
        @($script:audit.CapabilityChecks|Where-Object{$_.Code -ceq 'SRC-VERIFY-ORIGINAL' -and $_.PresentInExistingSource}).Count | Should -Be 1
        (Get-ARCH3aText 'Core/Archive/ArchiveVerifier.ps1') | Should -Match 'Compare-OPA265ARCH2bMailSemanticWitness'
    }
    It 'main existing Archive and Resume call verifier with RequireSemanticWitness' {
        $script:audit.CapabilityChecks | Where-Object {$_.Code -eq 'SRC-VERIFY-CALLER'} | ForEach-Object {$_.PresentInExistingSource | Should -BeTrue}
    }
    It 'does not assume operation journal alone is independent proof of COM success' {
        @($script:audit.IntegrationGaps|Where-Object{$_.Code -ceq 'ARCH3C-RECEIPT-LINK' -and -not $_.Solved}).Count | Should -Be 1
    }
    It 'documents that legacy destination PST creation precedes Move claim' {
        $s=Get-ARCH3aText 'Core/Archive/MailMover.ps1'
        $destination=$s.IndexOf('$dest = Get-OPAArchiveDestination')
        $claim=$s.IndexOf("Save-OPAArchiveTransaction -Transaction "+'$Transaction'+ " -Status 'Running' -Step 'Move Started'")
        ($destination -ge 0 -and $claim -gt $destination) | Should -BeTrue
        @($script:audit.IntegrationGaps|Where-Object{$_.Code -ceq 'ARCH3B-CLAIM-CONTRACT'}).Count | Should -Be 1
    }
    It 'preserves original ARCH2d5 real pilot as a SEPARATE bounded writer, not production runtime' {
        @($script:audit.CapabilityChecks|Where-Object{$_.Code -ceq 'SRC-ARCH2-100'}).Count | Should -Be 1
        $script:audit.ProductionReady | Should -BeFalse
    }
    It 'never gives retry or universal Resume permit after ambiguous provider result' {
        $script:audit.AutomaticResumeOrMoveRetryAllowed | Should -BeFalse
        @($script:audit.IntegrationGaps|Where-Object{$_.Code -ceq 'ARCH3C-UNKNOWN-OUTCOME'}).Count | Should -Be 1
    }
    It 'production writer remains blocked in main runtime and original ARCH2a policy' {
        @($script:audit.CapabilityChecks|Where-Object{$_.Code -ceq 'SAFETY-WRITER-BLOCK' -and $_.PresentInExistingSource}).Count | Should -Be 1
        @($script:audit.CapabilityChecks|Where-Object{$_.Code -ceq 'SAFETY-BLOCK-CODE' -and $_.PresentInExistingSource}).Count | Should -Be 1
        $script:audit.ArchiveResumeAutoRemainClosed | Should -BeTrue
    }
    It 'reports all 6 remaining ARCH3b-f safety gaps as open, not fabricated PASS' {
        $script:audit.OpenIntegrationGaps | Should -Be 6
        @($script:audit.IntegrationGaps|Where-Object{$_.Solved}).Count | Should -Be 0
        $script:audit.WriterPermit | Should -BeFalse
    }
}
Describe 'ARCH3a execute existing pure Year, PST-naming, folder and SentOn functions without COM' {
    It 'produces distinct year PST targets using existing Get-OPAArchivePartPath' {
        $script:route.Archive2020And2021AreSeparate | Should -BeTrue
        $script:route.Archive2020Pst | Should -BeLike '*info@stios.ru.Archive-2020.pst'
        $script:route.Archive2021Pst | Should -BeLike '*info@stios.ru.Archive-2021.pst'
    }
    It 'preserves exact existing archive part naming even if operator prefers Archive-YYYY.pst' {
        $script:route.ExistingArchiveNamingUsed | Should -BeTrue
        $script:route.Archive2020Pst | Should -Match 'Archive-2020\.pst$'
    }
    It 'reuses original grouping Year, not a newly duplicated implementation' {
        $script:route.ArchiveGrouping | Should -BeExactly 'Year'
        @((Get-OPAArchiveGroupParts -Date ([datetime]'2020-02-12') -Grouping Year)).Count | Should -Be 1
    }
    It 'keeps original YearQuarter grouping available and not destroyed' {
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2020-02-12') -Grouping YearQuarter) -join '/' | Should -BeExactly '2020/Q1'
    }
    It 'reuses nested user folder hierarchy underneath original PST root' {
        $script:route.Nested2020Folder | Should -BeExactly '2020\Проекты\Договоры'
    }
    It 'reuses Inbox folder under the original yearly path' {
        $script:route.Inbox2020Folder | Should -BeExactly '2020\Входящие'
    }
    It 'reuses SentOn rather than ReceivedTime for sent messages crossing year boundary' {
        $script:route.SentUsesSentOnYear | Should -Be 2020
        $script:route.Sent2020Folder | Should -BeExactly '2020\Отправленные'
    }
    It 'original SystemFolders classifier ALWAYS excludes Outbox even if a map is available' {
        $script:route.OutboxExcluded | Should -BeTrue
        (Test-OPAExcludedSystemFolder -Name 'Исходящие' -EntryID 'CUSTOM' -WellKnownEntryIdMap @{}) | Should -BeTrue
    }
    It 'original Sent Items must be INCLUDED under the POP3 store' {
        $script:route.SystemSentExcluded | Should -BeFalse
    }
    It 'original real Drafts system folder remains excluded by default' {
        $script:route.SystemDraftsExcluded | Should -BeTrue
    }
    It 'a custom user folder named Drafts is NOT automatically discarded' {
        $script:route.UserDefinedDraftsExcluded | Should -BeFalse
    }
    It 'supports localized/English Outbox without weakening old classifier' {
        foreach($name in @('Outbox','Исходящие','Исходящие сообщения')){
            (Test-OPAExcludedSystemFolder -Name $name -WellKnownEntryIdMap @{}) | Should -BeTrue
        }
    }
    It 'leaves legacy None/YearQuarter/YearMonth modes executable' {
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2020-02-12') -Grouping None).Count | Should -Be 0
        @(Get-OPAArchiveGroupParts -Date ([datetime]'2020-02-12') -Grouping YearMonth) -join '/' | Should -BeExactly '2020/02'
    }
    It 'routing example refuses a different source PST basename' {
        {Get-OPA265ARCH3aExistingRoutingExamples -ProjectRoot $script:root -SourcePst 'C:\Mock\other-account.pst'} | Should -Throw
    }
    It 'source example route names are computed without opening any real PST' {
        $script:route.SourcePstBaseName | Should -BeExactly 'info@stios.ru.pst'
        $script:route.OutlookContacted | Should -BeFalse
        $script:route.ExistingPstOpened | Should -BeFalse
        $script:route.JsonOrPstFilesWritten | Should -BeFalse
    }
}
Describe 'ARCH3a release fences and ADR source-backed documentation' {
    It 'new audit module contains no Outlook COM acquisition or mutating MailItem operations' {
        $s=Get-ARCH3aText 'Core/Diagnostics/ARCH3aLegacyIntegrationAudit.ps1'
        $s | Should -Not -Match 'GetActiveObject\s*\('
        $s | Should -Not -Match '\.(Move|AddStoreEx|Save|Delete|Copy)\s*\('
        $s | Should -Not -Match 'Write-OPA265ARCH2c4JsonOnce'
    }
    It 'ARCH3a entrypoint has only safe Plan Audit RoutingExamples, no MoveBatch mode' {
        $s=Get-ARCH3aText 'Invoke-ARCH3a.ps1'
        $s | Should -Match "ValidateSet\('Plan','Audit','RoutingExamples'\)"
        $s | Should -Not -Match 'Invoke-OPA265ARCH2d5Pilot'
    }
    It 'the architecture decision prohibits a third archive writer' {
        $doc=Get-ARCH3aText 'docs/ADR-ARCH3-001-reuse-existing-archiver.md'
        $doc | Should -Match 'OutlookPOP3Archive.ps1'
        $doc | Should -Match 'ARCH3b'
        $doc | Should -Match 'встраиват'
    }
    It 'the architecture decision recognizes original semantic verifier rather than declaring it missing' {
        $doc=Get-ARCH3aText 'docs/ADR-ARCH3-001-reuse-existing-archiver.md'
        $doc | Should -Match 'ArchiveVerifier.ps1'
        $doc | Should -Match 'RequireSemanticWitness'
    }
    It 'ARCH3a cannot declare full production readiness or writer permit' {
        $script:audit.WriterPermit | Should -BeFalse
        $script:audit.ProductionReady | Should -BeFalse
        $script:route.ProductionReady | Should -BeFalse
    }
    It 'original main script writer fence remains in place and untouched' {
        $s=Get-ARCH3aText 'OutlookPOP3Archive.ps1'
        $s | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
    }
}
