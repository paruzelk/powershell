#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3iSealedFullOriginalWitness.ps1')
    $script:source='C:\FAKE\info@stios.ru.pst'
    $script:entry='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    $script:folderId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
    $script:storeSha='c6f1cb064a78b6d8c676ace07d6ae8202f2477046e48d17baeade82581837ca3'
    $script:archiveDate=[datetime]'2020-02-13T12:57:58'
    function New-ARCH3iWitness {
        $digest='a'*64
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
            ItemClass=43
            InternetMessageIdSha256=$digest
            SubjectSha256=$digest
            SenderSha256=$digest
            ToSha256=$digest
            CcSha256=$digest
            BccSha256=$digest
            RecipientCount=1
            OrderedRecipientDigestSha256=$digest
            BodySha256=$digest
            BodyUtf16Length=30
            HtmlBodySha256=$digest
            HtmlBodyUtf16Length=35
            ReceivedUtcTicks=[long]637171378780000000
            SentUtcTicks=[long]637171378780000000
            UnRead=$false
            Importance=1
            Sensitivity=0
            CategoriesSha256=$digest
            AttachmentCount=0
            Attachments=@()
            MailItemSizeDiagnosticBytes=[long]2048
        }
    }
    function New-ARCH3iObserved {
        param([object]$Witness)
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3h.OriginalSemanticWitness.1'
            SourcePst=$script:source
            SourceEntryId=$script:entry
            SourceFolderEntryId=$script:folderId
            SourceStoreIdSha256=$script:storeSha
            ArchiveYear=2020
            ArchiveDate=$script:archiveDate
            ExistingArchivePart1Path='C:\FAKE\info@stios.ru.Archive-2020.pst'
            ExistingArchivePart1LengthBytes=[long]271360
            NextUnusedPartPathPreview='C:\FAKE\info@stios.ru.Archive-2020-02.pst'
            OriginalWitnessSha256=(Get-OPA265ARCH3dOriginalWitnessHash -Witness $Witness)
            FullWitnessCaptured=$true
            FullWitnessPersisted=$false
            WriterPermit=$false
            LiveMovePerformed=$false
            FullWitness=$Witness
        }
    }
    function New-ARCH3iPins {
        param([string]$Digest)
        return @{
            SourcePst=$script:source
            SourceEntryId=$script:entry
            ArchiveYear=2020
            ExpectedSourceFolderEntryId=$script:folderId
            ExpectedStoreIdSha256=$script:storeSha
            ExpectedSourcePstLengthBytes=[long]7694763008
            ExpectedExistingArchiveLengthBytes=[long]271360
            ExpectedAttachmentCount=0
            ExpectedArchiveDate=$script:archiveDate
            ExpectedOriginalWitnessSha256=$Digest
        }
    }
}
Describe 'ARCH3i original full semantic witness SHA pinning' {
    BeforeEach {
        $script:witness=New-ARCH3iWitness
        $script:digest=Get-OPA265ARCH3dOriginalWitnessHash -Witness $script:witness
    }
    It 'passes complete original ARCH2b semantic object and independently computed SHA' {
        Assert-OPA265ARCH3iFullWitnessPinned -Witness $script:witness -ExpectedOriginalWitnessSha256 $script:digest | Should -BeExactly $script:digest
    }
    It 'rejects another syntactically valid 64-hex SHA' {
        {Assert-OPA265ARCH3iFullWitnessPinned -Witness $script:witness -ExpectedOriginalWitnessSha256 ('f'*64)} | Should -Throw
    }
    It 'rejects invalid SHA format' {
        {Assert-OPA265ARCH3iFullWitnessPinned -Witness $script:witness -ExpectedOriginalWitnessSha256 'NOT_SHA'} | Should -Throw
    }
    It 'rejects incomplete original semantic object' {
        $script:witness.BodySha256='bad'
        {Assert-OPA265ARCH3iFullWitnessPinned -Witness $script:witness -ExpectedOriginalWitnessSha256 $script:digest} | Should -Throw
    }
    It 'rejects content drift that changes original Body hash but retains valid schema' {
        $script:witness.BodySha256='e'*64
        {Assert-OPA265ARCH3iFullWitnessPinned -Witness $script:witness -ExpectedOriginalWitnessSha256 $script:digest} | Should -Throw
    }
    It 'rejects a new attachment even if its count alone is forged' {
        $script:witness.AttachmentCount=1
        {Assert-OPA265ARCH3iFullWitnessPinned -Witness $script:witness -ExpectedOriginalWitnessSha256 $script:digest} | Should -Throw
    }
    It 'builds an envelope retaining the entire original semantic witness' {
        $obs=New-ARCH3iObserved -Witness $script:witness
        $r=New-OPA265ARCH3iWitnessEnvelope -Observed $obs -Witness $script:witness -RunId '01f7b98a-06a0-4bad-bf0d-13abefbd875a' -ExpectedOriginalWitnessSha256 $script:digest
        $r.FullWitnessPersisted | Should -BeTrue
        $r.OriginalWitness.BodySha256 | Should -BeExactly ('a'*64)
        $r.OriginalWitnessSha256 | Should -BeExactly $script:digest
        $r.LiveMovePerformed | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
    }
    It 'rejects an envelope whose original captured digest differs' {
        $obs=New-ARCH3iObserved -Witness $script:witness
        $obs.OriginalWitnessSha256='f'*64
        {New-OPA265ARCH3iWitnessEnvelope -Observed $obs -Witness $script:witness -RunId '01f7b98a-06a0-4bad-bf0d-13abefbd875a' -ExpectedOriginalWitnessSha256 $script:digest} | Should -Throw
    }
    It 'rejects an observed attempted Move flag even when semantic witness matches' {
        $obs=New-ARCH3iObserved -Witness $script:witness
        $obs.LiveMovePerformed=$true
        {New-OPA265ARCH3iWitnessEnvelope -Observed $obs -Witness $script:witness -RunId '01f7b98a-06a0-4bad-bf0d-13abefbd875a' -ExpectedOriginalWitnessSha256 $script:digest} | Should -Throw
    }
}
Describe 'ARCH3i protected file layout and exact one-shot claim' {
    It 'restricts evidence base to the current LOCALAPPDATA' {
        {Get-OPA265ARCH3iEvidenceLayout -RunId ([guid]::NewGuid().ToString('D')) -LocalAppData 'C:\NOT_THE_USERS_LOCALAPPDATA'} | Should -Throw
    }
    It 'rejects invalid/noncanonical run identity' {
        {Get-OPA265ARCH3iEvidenceLayout -RunId 'not-a-guid'} | Should -Throw
        {Get-OPA265ARCH3iEvidenceLayout -RunId '00000000-0000-0000-0000-000000000000'} | Should -Throw
    }
    It 'creates predictable explicit path without writing any files' {
        $id=[guid]::NewGuid().ToString('D')
        $r=Get-OPA265ARCH3iEvidenceLayout -RunId $id
        $r.RunId | Should -BeExactly $id
        $r.WitnessPath | Should -BeExactly (Join-Path (Join-Path $env:LOCALAPPDATA ('OPA265-ARCH3i-'+$id)) 'original-full-semantic-witness.json')
        Test-Path -LiteralPath $r.WitnessPath | Should -BeFalse
    }
}
Describe 'ARCH3i private immutable full witness evidence, real Windows filesystem' {
    BeforeEach {
        $script:testWitness=New-ARCH3iWitness
        $script:testDigest=Get-OPA265ARCH3dOriginalWitnessHash -Witness $script:testWitness
        $script:testRunId=[guid]::NewGuid().ToString('D')
        $script:testLayout=Get-OPA265ARCH3iEvidenceLayout -RunId $script:testRunId
        $script:params=New-ARCH3iPins -Digest $script:testDigest
        $script:params.RunId=$script:testRunId
        Mock Invoke-OPA265ARCH3hPinnedSemanticWitness {
            return (New-ARCH3iObserved -Witness $script:testWitness)
        }
    }
    AfterEach {
        $dir=[string]$script:testLayout.Root
        if([IO.Directory]::Exists($dir) -and
           [IO.Path]::GetFileName($dir) -ceq ('OPA265-ARCH3i-'+$script:testRunId) -and
           [IO.Path]::GetDirectoryName($dir) -ieq $env:LOCALAPPDATA){
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
        }
    }
    It 'Plan does not call COM or create evidence files' {
        $r=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Plan @script:params
        $r.Status | Should -BeExactly 'PinnedRealOriginalSemanticWitnessSealPlanNoOutlookOrWrites'
        $r.EvidenceWritten | Should -BeFalse
        Test-Path -LiteralPath $script:testLayout.Root | Should -BeFalse
        Should -Invoke Invoke-OPA265ARCH3hPinnedSemanticWitness -Exactly -Times 0
    }
    It 'Seal without explicit evidence-only approval never contacts Outlook or writes' {
        {Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -Confirm:$false @script:params} | Should -Throw
        Test-Path -LiteralPath $script:testLayout.Root | Should -BeFalse
        Should -Invoke Invoke-OPA265ARCH3hPinnedSemanticWitness -Exactly -Times 0
    }
    It 'WhatIf returns no writes without contacting source' {
        $r=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -WhatIf @script:params
        $r.Status | Should -BeExactly 'EvidenceSealWhatIfNoWrites'
        Test-Path -LiteralPath $script:testLayout.Root | Should -BeFalse
        Should -Invoke Invoke-OPA265ARCH3hPinnedSemanticWitness -Exactly -Times 0
    }
    It 'captures complete original witness once and seals private ACL file with readback' {
        $r=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -Confirm:$false @script:params
        $r.Status | Should -BeExactly 'OriginalFullWitnessSealedAndIndependentlyReadBackNoMove'
        $r.OriginalWitnessSha256 | Should -BeExactly $script:testDigest
        $r.FullWitnessPersisted | Should -BeTrue
        $r.IndependentReadbackPassed | Should -BeTrue
        $r.WriterPermit | Should -BeFalse
        $r.JournalOrIndexWrites | Should -BeFalse
        Test-Path -LiteralPath $r.SealPath | Should -BeTrue
        Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $script:testLayout.Root | Should -BeTrue
        Should -Invoke Invoke-OPA265ARCH3hPinnedSemanticWitness -Exactly -Times 1
    }
    It 'Review independently opens pinned full semantic evidence without Outlook' {
        $first=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -Confirm:$false @script:params
        $r=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Review -RunId $script:testRunId -SealSha256 $first.SealSha256
        $r.IndependentReadbackPassed | Should -BeTrue
        $r.OriginalWitnessSha256 | Should -BeExactly $script:testDigest
        Should -Invoke Invoke-OPA265ARCH3hPinnedSemanticWitness -Exactly -Times 1
    }
    It 'refuses reuse of the exact same RunId after sealed file exists' {
        $first=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -Confirm:$false @script:params
        {Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -Confirm:$false @script:params} | Should -Throw
        Test-Path -LiteralPath $first.SealPath | Should -BeTrue
        Should -Invoke Invoke-OPA265ARCH3hPinnedSemanticWitness -Exactly -Times 1
    }
    It 'rejects incorrect externally pinned file SHA256' {
        $null=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -Confirm:$false @script:params
        {Invoke-OPA265ARCH3iFullWitnessSeal -Mode Review -RunId $script:testRunId -SealSha256 ('f'*64)} | Should -Throw
    }
    It 'rejects sealed witness tampering after an externally pinned hash was returned' {
        $first=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -Confirm:$false @script:params
        [IO.File]::AppendAllText([string]$first.SealPath,'FORGED')
        {Invoke-OPA265ARCH3iFullWitnessSeal -Mode Review -RunId $script:testRunId -SealSha256 $first.SealSha256} | Should -Throw
    }
    It 'rejects unrecognized second file next to protected evidence' {
        $first=Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -Confirm:$false @script:params
        [IO.File]::WriteAllText((Join-Path $script:testLayout.Root 'unexpected.txt'),'x')
        {Invoke-OPA265ARCH3iFullWitnessSeal -Mode Review -RunId $script:testRunId -SealSha256 $first.SealSha256} | Should -Throw
    }
    It 'refuses mismatched operator SHA before creating private run directory' {
        $script:params.ExpectedOriginalWitnessSha256='f'*64
        {Invoke-OPA265ARCH3iFullWitnessSeal -Mode Seal -ConfirmEvidenceWrite -Confirm:$false @script:params} | Should -Throw
        Test-Path -LiteralPath $script:testLayout.Root | Should -BeFalse
    }
}
Describe 'ARCH3i original writer remains off by source-based inspection' {
    It 'new CLI exposes only Plan Seal Review and old public ARCH3h remains hash-only' {
        $entry=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3i.ps1') -Raw -Encoding UTF8
        $core=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3iSealedFullOriginalWitness.ps1') -Raw -Encoding UTF8
        $old=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3h.ps1') -Raw -Encoding UTF8
        $entry | Should -Match "ValidateSet\('Plan','Seal','Review'\)"
        $entry | Should -Not -Match '\.Move\(|\.AddStoreEx\('
        $core | Should -Not -Match '\.Move\(|\.AddStoreEx\(|Add-OPADuplicateEntry'
        $old | Should -Not -Match 'IncludeFullWitness'
        $core | Should -Match 'Write-OPA265ARCH3cJsonOnce'
    }
}
