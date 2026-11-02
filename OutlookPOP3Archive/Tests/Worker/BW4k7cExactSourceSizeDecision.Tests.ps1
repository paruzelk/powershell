#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7cExactSourceSizeDecision265.ps1')
    function New-BW4k7cSemanticVerdict {
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7b.SemanticSourceEvidenceClassification.1'
            Status='ContentWitnessMatchedSourceSizeDriftStillUnapproved'
            SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
            TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
            OriginalSourceEvidenceSha256='0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0'
            OriginalSize=8122
            CurrentSize=8634
            DeltaSize=512
            AttachmentSha256='8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'
            AttachmentByteCount=1024
            AllCapturedContentWitnessFieldsEqual=$true
            OriginalThreeMoveClaimsUnchanged=$true
            SourceMailMoveAttempted=$false
            ContentCoverageIncludesFullRecipients=$false
            SemanticFlagMaskDefinedForProduction=$false
            CrossStoreDestinationVerified=$false
            PhysicalPstDurabilityProven=$false
            SizeDriftAccepted=$false
            NoGlobalSizeWaiver=$true
            AttemptClaimWritten=$false
            WriterPermit=$false
            OutlookMoveExecuted=$false
            CanRetryMove=$false
            ProductionReady=$false
        }
    }
}
Describe 'BW4k7c exact Attachment1K original-source +512 manual decision, no Move' {
    BeforeEach {
        $script:v=New-BW4k7cSemanticVerdict
        $script:ack='ACCEPT EXACT SOURCE 8122 TO 8634 PLUS 512 ATTACHMENT1K NO MOVE'
        $script:root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:root)
    }
    It 'accepts the pinned unapproved semantic source dossier' {
        (Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v) | Should -BeTrue
    }
    It 'refuses source size 1 byte off' {
        $script:v.CurrentSize=8635
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*exact original*'
    }
    It 'refuses +38 instead of +512 as a global size waiver' {
        $script:v.DeltaSize=38
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*exact original*'
    }
    It 'refuses a changed source evidence SHA' {
        $script:v.OriginalSourceEvidenceSha256=('a'*64)
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*exact original*'
    }
    It 'refuses changed attachment SHA' {
        $script:v.AttachmentSha256=('a'*64)
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*exact original*'
    }
    It 'refuses missing full captured-content equality' {
        $script:v.AllCapturedContentWitnessFieldsEqual=$false
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*semantic evidence*'
    }
    It 'refuses changed historical Move Claims' {
        $script:v.OriginalThreeMoveClaimsUnchanged=$false
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*semantic evidence*'
    }
    It 'refuses invented full recipient coverage' {
        $script:v.ContentCoverageIncludesFullRecipients=$true
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*cannot elevate*'
    }
    It 'refuses invented production flag mask proof' {
        $script:v.SemanticFlagMaskDefinedForProduction=$true
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*cannot elevate*'
    }
    It 'refuses another Move attempt already claimed' {
        $script:v.AttemptClaimWritten=$true
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*cannot elevate*'
    }
    It 'refuses a global size waiver' {
        $script:v.NoGlobalSizeWaiver=$false
        {Assert-OPA265BW4k7cSemanticVerdict -Verdict $script:v} | Should -Throw '*semantic evidence*'
    }
    It 'rejects missing operator phrase' {
        {New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText 'YES'} | Should -Throw '*operator acknowledgment*'
    }
    It 'rejects even the correct phrase after changed content' {
        $script:v.AllCapturedContentWitnessFieldsEqual=$false
        {New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack} | Should -Throw '*semantic evidence*'
    }
    It 'constructs an exact decision but never permits real Outlook Move' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $d.Status | Should -BeExactly 'ExactSourceSizeDriftAcknowledgedOnlyNoMovePermit'
        $d.ExactSourceSizeDriftAcknowledged | Should -BeTrue
        $d.WriterPermit | Should -BeFalse
        $d.JournalWriteAllowed | Should -BeFalse
        $d.AutomaticRetryAllowed | Should -BeFalse
        $d.ProductionReady | Should -BeFalse
    }
    It 'validates a newly constructed immutable decision' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        (Assert-OPA265BW4k7cManualDecision -Decision $d -Verdict $script:v) | Should -BeTrue
    }
    It 'rejects extra fields that could smuggle a writer permission' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $d | Add-Member -NotePropertyName AllowMove -NotePropertyValue $true
        {Assert-OPA265BW4k7cManualDecision -Decision $d -Verdict $script:v} | Should -Throw '*schema shape*'
    }
    It 'refuses to turn acknowledgment into Move permission' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $d.WriterPermit=$true
        {Assert-OPA265BW4k7cManualDecision -Decision $d -Verdict $script:v} | Should -Throw '*forbidden permission*'
    }
    It 'refuses a forged decision time' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $d.DecisionUtc='not-date'
        {Assert-OPA265BW4k7cManualDecision -Decision $d -Verdict $script:v} | Should -Throw '*timestamp*'
    }
    It 'refuses a different target fixture for decision path' {
        {Get-OPA265BW4k7cDecisionPath -SuiteId $script:v.SuiteId -TestId ([guid]::NewGuid().ToString('D')) -LocalAppData $script:root} | Should -Throw '*original SuiteId/TestId*'
    }
    It 'writes one immutable BOM evidence record with valid SHA256 in TestDrive' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $p=Get-OPA265BW4k7cDecisionPath -SuiteId $script:v.SuiteId -TestId $script:v.TestId -LocalAppData $script:root
        $saved=Write-OPA265BW4k7cManualDecisionOnce -Decision $d -Verdict $script:v -Path $p -LocalAppData $script:root
        $saved.DecisionSha256 | Should -Match '^[0-9a-f]{64}$'
        ([IO.File]::ReadAllBytes($p))[0] | Should -Be 239
    }
    It 'will not overwrite an existing decision' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $p=Get-OPA265BW4k7cDecisionPath -SuiteId $script:v.SuiteId -TestId $script:v.TestId -LocalAppData $script:root
        $null=Write-OPA265BW4k7cManualDecisionOnce -Decision $d -Verdict $script:v -Path $p -LocalAppData $script:root
        {Write-OPA265BW4k7cManualDecisionOnce -Decision $d -Verdict $script:v -Path $p -LocalAppData $script:root} | Should -Throw
    }
    It 'will not write a decision to a redirected location' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        {Write-OPA265BW4k7cManualDecisionOnce -Decision $d -Verdict $script:v -Path (Join-Path $script:root 'elsewhere.json') -LocalAppData $script:root} | Should -Throw '*cannot be redirected*'
    }
    It 'independently verifies the persisted exact record by SHA and original pins' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $p=Get-OPA265BW4k7cDecisionPath -SuiteId $script:v.SuiteId -TestId $script:v.TestId -LocalAppData $script:root
        $saved=Write-OPA265BW4k7cManualDecisionOnce -Decision $d -Verdict $script:v -Path $p -LocalAppData $script:root
        $verified=Read-OPA265BW4k7cManualDecisionVerified -Verdict $script:v -Path $p -ExpectedDecisionSha256 $saved.DecisionSha256 -LocalAppData $script:root
        $verified.Status | Should -BeExactly 'ExactSourceSizeManualDecisionIndependentlyVerifiedNoWriterPermit'
        $verified.WriterPermit | Should -BeFalse
    }
    It 'blocks decision hash mismatch instead of attempting a Move' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $p=Get-OPA265BW4k7cDecisionPath -SuiteId $script:v.SuiteId -TestId $script:v.TestId -LocalAppData $script:root
        $null=Write-OPA265BW4k7cManualDecisionOnce -Decision $d -Verdict $script:v -Path $p -LocalAppData $script:root
        {Read-OPA265BW4k7cManualDecisionVerified -Verdict $script:v -Path $p -ExpectedDecisionSha256 ('a'*64) -LocalAppData $script:root} | Should -Throw '*absent, altered*'
    }
    It 'rejects changed verdict after decision even when SHA is still correct' {
        $d=New-OPA265BW4k7cManualDecision -Verdict $script:v -ApprovalText $script:ack
        $p=Get-OPA265BW4k7cDecisionPath -SuiteId $script:v.SuiteId -TestId $script:v.TestId -LocalAppData $script:root
        $saved=Write-OPA265BW4k7cManualDecisionOnce -Decision $d -Verdict $script:v -Path $p -LocalAppData $script:root
        $script:v.CurrentSize=8635
        {Read-OPA265BW4k7cManualDecisionVerified -Verdict $script:v -Path $p -ExpectedDecisionSha256 $saved.DecisionSha256 -LocalAppData $script:root} | Should -Throw '*exact original*'
    }
    It 'enforces no in-process Outlook writer nor journal mutation in controller source' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7cExactSourceSizeDecision.ps1') -Encoding UTF8 -Raw
        $s | Should -Match 'Invoke-OPA265BW4k7bSemanticSourceReview.ps1'
        $s | Should -Not -Match '(?i)\$mail\.(Move|Save|Delete|Send)\s*\('
        $s | Should -Not -Match 'AddStoreEx\s*\('
        $s | Should -Not -Match 'Write-OPA265BW4k1ClaimOnce'
    }
    It 'enforces explicit Accept-only switches and -WhatIf' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7cExactSourceSizeDecision.ps1') -Encoding UTF8 -Raw
        $s | Should -Match 'ConfirmExactSource512'
        $s | Should -Match 'SupportsShouldProcess=\$true'
        $s | Should -Match 'WhatIfNoDecisionNoMove'
    }
}
