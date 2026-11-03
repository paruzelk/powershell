#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7iReopenIntegrity265.ps1')
    function New-TestAudit {
        [pscustomobject]@{
            Schema='2.6.5-BW4k7g.IndependentPostMoveSemanticAudit.1'
            Status='SourceZeroDestinationOneSemanticMismatchRequiresManualReview'
            SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
            TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
            VerifiedOneShotClaimSha256='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
            VerifiedSourceSemanticSnapshotSha256='fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
            SourceMessageIdMatches=0;DestinationMessageIdMatches=1
            DestinationEntryId='00000000D3E190022DF61241BBDE594AD46A661B24002000'
            DestinationFolderEntryId='00000000D3E190022DF61241BBDE594AD46A661B82800000'
            OriginalSourceSize=[long]8122;DestinationSize=[long]8168
            SubjectMatches=$true;SenderMatches=$true;BodyMatches=$true;HtmlBodyMatches=$true
            ReceivedUtcTicksMatches=$true;AttachmentBytesAndSha256Match=$true
            SearchKeyAndInternetMessageIdentityMatches=$true
            FullRecipientSha256Matches=$true;FullUserStateSha256Matches=$false
            SignificantReadAttachBitsMatch=$true
            IndependentDestinationContentReads=2;IndependentDestinationSemanticReads=2
            AllCapturedContentMatched=$false;PhysicalPstDurabilityProven=$false
            FullProductionSignificantFlagCoverageProven=$false
            OutlookMoveExecutedByAudit=$false;AutomaticRetryAllowed=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    function New-TestAttribution {
        [pscustomobject]@{
            Schema='2.6.5-BW4k7h.IndependentPostMoveFlagAttribution.1'
            Status='OnlyRawPrMessageFlagsChangedAllCapturedUserFieldsMatch'
            SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
            TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
            OriginalOneShotClaimSha256='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
            OriginalRecipientStateSnapshotSha256='fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
            SourceMessageIdMatches=0;DestinationMessageIdMatches=1
            DestinationEntryId='00000000D3E190022DF61241BBDE594AD46A661B24002000'
            OriginalMapiFlags=65555;DestinationMapiFlags=17
            OriginalMapiFlagsHex='0x00010013';DestinationMapiFlagsHex='0x00000011'
            ChangedMapiFlagsXor=65538;ChangedMapiFlagsXorHex='0x00010002'
            ChangedFlagBitValues=@(2,65536)
            DestinationUserStateSha256='05cceab7d9f7fd7c508d8017f023522a60e4d840a6248726faa2432008f08e25'
            ReconstructedOriginalFlagsUserStateSha256='2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'
            OriginalUserStateSha256='2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'
            IndependentDestinationSemanticReads=2
            SignificantReadAttachBitsMatch=$true
            CapturedOutlookUserFieldsMatchExcludingRawMapiFlags=$true;OnlyRawMapiFlagsChanged=$true
            ChangedRawFlagBitsSemanticallyClassified=$false
            PriorObservedMismatchMayBeReclassifiedAutomatically=$false
            RawRecipientAddressesExposed=$false;ExistingClaimRewritten=$false
            OriginalEvidenceRewritten=$false;OutlookMoveExecuted=$false
            WriterPermit=$false;AutomaticRetryAllowed=$false;ProductionReady=$false
        }
    }
    function New-TestProcess {
        param([int]$Id=2019,[long]$Ticks=638900000000000000)
        [pscustomobject]@{ProcessId=$Id;StartUtcTicks=$Ticks}
    }
    function New-TestBaseline {
        New-OPA265BW4k7iBaseline -Audit (New-TestAudit) -Attribution (New-TestAttribution) -OutlookProcess (New-TestProcess)
    }
}
Describe 'BW4k7i pin exact one-shot source-zero/target-one and original unresolved raw MAPI bits' {
    BeforeEach {$script:a=New-TestAudit;$script:h=New-TestAttribution}
    It 'accepts unchanged immutable original failure and both specific bit changes' {
        (Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h) | Should -BeTrue
    }
    It 'rejects original Claim SHA change' {
        $script:a.VerifiedOneShotClaimSha256=('0'*64)
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
    It 'rejects source message reappearing' {
        $script:a.SourceMessageIdMatches=1
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
    It 'rejects duplicate target message' {
        $script:a.DestinationMessageIdMatches=2
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
    It 'rejects changed binary attachment' {
        $script:a.AttachmentBytesAndSha256Match=$false
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
    It 'rejects changed recipient SHA' {
        $script:a.FullRecipientSha256Matches=$false
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
    It 'rejects premature user-state SHA PASS' {
        $script:a.FullUserStateSha256Matches=$true
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
    It 'rejects production enabled' {
        $script:a.ProductionReady=$true
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
    It 'rejects changed 0x00010000 unknown raw bit' {
        $script:h.ChangedFlagBitValues=@(2,131072)
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
    It 'rejects claiming unknown bit classified' {
        $script:h.ChangedRawFlagBitsSemanticallyClassified=$true
        {Assert-OPA265BW4k7iExactPriorAudit -Audit $script:a -Attribution $script:h} | Should -Throw
    }
}
Describe 'BW4k7i immutable standalone evidence capture' {
    BeforeEach {
        $script:b=New-TestBaseline
        $script:d=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:d)
    }
    It 'builds valid read-only baseline' {
        (Assert-OPA265BW4k7iBaseline -Baseline $script:b) | Should -BeTrue
    }
    It 'refuses baseline with wrong size' {
        $script:b.DestinationSize=9000
        {Assert-OPA265BW4k7iBaseline -Baseline $script:b} | Should -Throw
    }
    It 'refuses extra writer permit field' {
        $script:b | Add-Member -NotePropertyName WriterPermit -NotePropertyValue $true
        {Assert-OPA265BW4k7iBaseline -Baseline $script:b} | Should -Throw
    }
    It 'refuses changed original MAPI flag set' {
        $script:b.ChangedFlagBitValues=@(2,65536,131072)
        {Assert-OPA265BW4k7iBaseline -Baseline $script:b} | Should -Throw
    }
    It 'refuses changed original Claim' {
        $script:b.ClaimSha256=('0'*64)
        {Assert-OPA265BW4k7iBaseline -Baseline $script:b} | Should -Throw
    }
    It 'refuses automatic retry' {
        $script:b.AutomaticRetryAllowed=$true
        {Assert-OPA265BW4k7iBaseline -Baseline $script:b} | Should -Throw
    }
    It 'writes only to its separate BW4k7i path not prior BW4k1 Claim' {
        $p=Get-OPA265BW4k7iBaselinePath -SuiteId $script:b.SuiteId -TestId $script:b.TestId -LocalAppData $script:d
        $p | Should -Match 'BW4k7i-ReopenBaselines'
        $p | Should -Not -Match 'BW4k1-Claims'
    }
    It 'writes BOM + verifiable SHA256 using CreateNew' {
        $r=Write-OPA265BW4k7iBaselineOnce -Baseline $script:b -LocalAppData $script:d
        $r.BaselineSha256 | Should -Match '^[a-f0-9]{64}$'
        $data=[IO.File]::ReadAllBytes($r.BaselinePath)
        (@($data[0],$data[1],$data[2]) -join ',') | Should -BeExactly '239,187,191'
    }
    It 'refuses to overwrite an existing baseline' {
        $r=Write-OPA265BW4k7iBaselineOnce -Baseline $script:b -LocalAppData $script:d
        {Write-OPA265BW4k7iBaselineOnce -Baseline $script:b -LocalAppData $script:d} | Should -Throw
        (Get-FileHash -LiteralPath $r.BaselinePath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $r.BaselineSha256
    }
    It 'verifies original immutable evidence by pinned SHA' {
        $r=Write-OPA265BW4k7iBaselineOnce -Baseline $script:b -LocalAppData $script:d
        $v=Read-OPA265BW4k7iBaselineVerified -ExpectedBaselineSha256 $r.BaselineSha256 -LocalAppData $script:d
        $v.ClaimSha256 | Should -BeExactly $script:b.ClaimSha256
    }
    It 'fails closed on mismatched immutable baseline digest' {
        $null=Write-OPA265BW4k7iBaselineOnce -Baseline $script:b -LocalAppData $script:d
        {Read-OPA265BW4k7iBaselineVerified -ExpectedBaselineSha256 ('0'*64) -LocalAppData $script:d} | Should -Throw
    }
}
Describe 'BW4k7i true Outlook shutdown/reopen and post-restart semantic consistency' {
    BeforeEach {$script:before=New-TestBaseline;$script:after=New-TestBaseline}
    It 'rejects same Outlook process' {
        {Compare-OPA265BW4k7iAfterReopen -Baseline $script:before -Reopened $script:after -ReopenedProcess (New-TestProcess)} | Should -Throw
    }
    It 'rejects older Outlook process' {
        {Compare-OPA265BW4k7iAfterReopen -Baseline $script:before -Reopened $script:after -ReopenedProcess (New-TestProcess -Id 2020 -Ticks 638800000000000000)} | Should -Throw
    }
    It 'accepts stable archive evidence only after a new Outlook process starts' {
        $r=Compare-OPA265BW4k7iAfterReopen -Baseline $script:before -Reopened $script:after -ReopenedProcess (New-TestProcess -Id 2020 -Ticks 638901000000000000)
        $r.ActualNewOutlookProcessObserved | Should -BeTrue
        $r.ArchiveContentRecipientAttachmentShaStable | Should -BeTrue
    }
    It 'keeps raw 0x00010000 unresolved and production blocked' {
        $r=Compare-OPA265BW4k7iAfterReopen -Baseline $script:before -Reopened $script:after -ReopenedProcess (New-TestProcess -Id 2020 -Ticks 638901000000000000)
        $r.UnknownFlagWaived | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $r.PhysicalPstDurabilityFullyProven | Should -BeFalse
    }
    It 'rejects changed destination size after Outlook reopen' {
        $script:after.DestinationSize=8170
        {Compare-OPA265BW4k7iAfterReopen -Baseline $script:before -Reopened $script:after -ReopenedProcess (New-TestProcess -Id 2020 -Ticks 638901000000000000)} | Should -Throw
    }
    It 'rejects changed destination user-state SHA after Outlook reopen' {
        $script:after.DestinationUserStateSha256=('f'*64)
        {Compare-OPA265BW4k7iAfterReopen -Baseline $script:before -Reopened $script:after -ReopenedProcess (New-TestProcess -Id 2020 -Ticks 638901000000000000)} | Should -Throw
    }
}
Describe 'BW4k7i controller cannot mutate Outlook/Claim or waive unknown bits' {
    BeforeAll {
        $script:ctrl=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7iReopenIntegrityReview.ps1') -Raw -Encoding UTF8
        $script:worker=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7iReopenIntegrity265.ps1') -Raw -Encoding UTF8
    }
    It 'never invokes MailItem.Move or MailItem.Save' {
        $script:ctrl | Should -Not -Match '\$mail\.(Move|Save|Send|Delete)\s*\('
    }
    It 'only reads original Claim and runs independent postmove audits' {
        $script:ctrl | Should -Match 'Read-OPA265BW4k7gClaimVerified'
        $script:ctrl | Should -Match 'Invoke-OPA265BW4k7gPostMoveReadOnly'
        $script:ctrl | Should -Match 'Invoke-OPA265BW4k7hPostMoveFlagReview'
    }
    It 'enforces original Outlook process startup timestamp for VerifyAfterReopen' {
        $script:ctrl | Should -Match 'VerifyAfterReopen'
        $script:ctrl | Should -Match 'OriginalOutlookProcessStartUtcTicks'
    }
    It 'writes evidence only by CreateNew and Flush(true)' {
        $script:worker | Should -Match '\[IO.FileMode\]::CreateNew'
        $script:worker | Should -Match 'Flush\(\$true\)'
    }
    It 'requires explicit single immutable capture approval' {
        $script:ctrl | Should -Match 'CAPTURE EXACT BW4K7I READONLY REOPEN BASELINE'
        $script:ctrl | Should -Match 'ConfirmImmutableReopenBaseline'
    }
}
