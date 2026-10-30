#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4h1PostMoveFieldDrift265.ps1')
    $script:sub='OPA265 BW4e1 FRESH TEST 98bef817-0fb5-478a-b869-33f02fda59d3'
    $script:sender='sender@example.invalid'
    $script:body="OPA265 BW4e1 disposable synthetic test. `r`n`r`nTestId: 98bef817-0fb5-478a-b869-33f02fda59d3 `r`n"
    $script:originalSize=[long]1720
    $script:ticks=[long]638600000000000000
    $script:gold='7cc35ed2da0848297959f8523285e81d1b1ff5ad9ced1cc1f22341595d2'
    $script:params=@{Subject=$script:sub;SenderEmailAddress=$script:sender;Body=$script:body;ReceivedUtcTicks=$script:ticks}
}
Describe 'BW4h1 exact historical BW4c five-field SHA256' {
    It 'matches independent fixed known original digest for padded Outlook CRLF test fixture' {
        $h=Get-OPA265BW4h1ContentHash @script:params -Size $script:originalSize
        $h | Should -BeExactly $script:gold
    }
    It 'changes SHA if only MAPI Size is +8' {
        (Get-OPA265BW4h1ContentHash @script:params -Size ($script:originalSize+8)) | Should -Not -BeExactly $script:gold
    }
    It 'changes SHA if received UTC ticks change' {
        $p=$script:params.Clone();$p.ReceivedUtcTicks=$script:ticks+1
        (Get-OPA265BW4h1ContentHash @p -Size $script:originalSize) | Should -Not -BeExactly $script:gold
    }
    It 'changes SHA if one ASCII space disappears in Body' {
        $p=$script:params.Clone();$p.Body=$script:body.Replace('. ','.')
        (Get-OPA265BW4h1ContentHash @p -Size $script:originalSize) | Should -Not -BeExactly $script:gold
    }
    It 'changes SHA if sender changes but subject and body stay the same' {
        $p=$script:params.Clone();$p.SenderEmailAddress='someone@example.invalid'
        (Get-OPA265BW4h1ContentHash @p -Size $script:originalSize) | Should -Not -BeExactly $script:gold
    }
    It 'rejects invalid zero size' {
        {Get-OPA265BW4h1ContentHash @script:params -Size 0} | Should -Throw
    }
    It 'rejects invalid zero UTC ticks' {
        $p=$script:params.Clone();$p.ReceivedUtcTicks=0
        {Get-OPA265BW4h1ContentHash @p -Size $script:originalSize} | Should -Throw
    }
}
Describe 'BW4h1 strictly bounded size-only reconstruction, never Move approval' {
    It 'recovers inferred original when destination MAPI size grows +8' {
        $r=Get-OPA265BW4h1SizeOnlyHypotheses @script:params -ObservedSize ($script:originalSize+8) -ExpectedOriginalHash $script:gold -MaxSizeDelta 64
        $r.Status | Should -BeExactly 'CompositeHashReconstructedBySizeOnlyHypothesis'
        $r.InferredOriginalSize | Should -Be $script:originalSize
        $r.DestinationMinusInferredSourceSize | Should -Be 8
        $r.SizeOnlyMatches | Should -Be 1
        $r.OriginalMailItemMoveMayBeRetried | Should -BeFalse
    }
    It 'recovers inferred original when destination MAPI size shrinks by 8' {
        $r=Get-OPA265BW4h1SizeOnlyHypotheses @script:params -ObservedSize ($script:originalSize-8) -ExpectedOriginalHash $script:gold -MaxSizeDelta 32
        $r.InferredOriginalSize | Should -Be $script:originalSize
        $r.DestinationMinusInferredSourceSize | Should -Be -8
    }
    It 'does not search outside explicit bound or guess old MAPI Size' {
        $r=Get-OPA265BW4h1SizeOnlyHypotheses @script:params -ObservedSize ($script:originalSize+8) -ExpectedOriginalHash $script:gold -MaxSizeDelta 7
        $r.Status | Should -BeExactly 'CompositeDriftNotExplainedBySizeOnlyWithinBound'
        $r.SizeOnlyMatches | Should -Be 0
    }
    It 'does not claim size-only drift when original and destination hashes already match' {
        $r=Get-OPA265BW4h1SizeOnlyHypotheses @script:params -ObservedSize $script:originalSize -ExpectedOriginalHash $script:gold -MaxSizeDelta 1
        $r.Status | Should -BeExactly 'NoCompositeFingerprintDrift'
        $r.SizeOnlyMatches | Should -Be 0
    }
    It 'does not silently infer MAPI Size if Body changed' {
        $p=$script:params.Clone();$p.Body=$script:body+'X'
        $r=Get-OPA265BW4h1SizeOnlyHypotheses @p -ObservedSize ($script:originalSize+8) -ExpectedOriginalHash $script:gold -MaxSizeDelta 16
        $r.Status | Should -BeExactly 'CompositeDriftNotExplainedBySizeOnlyWithinBound'
        $r.OtherFourFieldsProvenIndependentlyEqual | Should -BeFalse
    }
    It 'refuses malformed SHA256 original pins' {
        {Get-OPA265BW4h1SizeOnlyHypotheses @script:params -ObservedSize 1728 -ExpectedOriginalHash 'notsha' -MaxSizeDelta 1} | Should -Throw
    }
    It 'rejects excessive search budget rather than enumerating unbounded size guesses' {
        {Get-OPA265BW4h1SizeOnlyHypotheses @script:params -ObservedSize 1728 -ExpectedOriginalHash $script:gold -MaxSizeDelta 99999} | Should -Throw
    }
}
Describe 'BW4h1 read-only script has no Move and claim/journal writer' {
    BeforeAll {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW4h1FieldDriftReadOnly.ps1'
        $script:code=[IO.File]::ReadAllText($p)
    }
    It 'never dispatches MailItem.Move or original journal writing' {
        $script:code | Should -Not -Match '(?i)\$mail\.Move\('
        $script:code | Should -Not -Match 'Write-OPAOperationJournal'
        $script:code | Should -Not -Match 'Write-OPA265BW4gOneShotClaim'
    }
    It 'always runs original BW4h independent audit before computing field hypothesis' {
        $script:code | Should -Match 'Test-OPA265BW4hIndependentReconciliationReadOnly\.ps1'
        $script:code | Should -Match 'HistoricalEvidenceUnchanged'
        $script:code | Should -Match 'Get-OPA265BW4h1SizeOnlyHypotheses'
    }
}
