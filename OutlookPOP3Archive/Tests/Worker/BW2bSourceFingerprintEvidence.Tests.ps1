#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/SyntheticReadOnlyProbe265BW2.ps1')
}
Describe '2.6.5-BW2b source EntryID/size evidence: strict read-only diagnostics' {
    BeforeEach {
        $expected='synthetic-test-source-EntryID'
        $observed='synthetic-test-source-EntryID'
        $size=1436
        $actual=1436
    }
    It 'preserves exact EntryID and size match when both equal' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.ExactMatch | Should -BeTrue
        $e.SourceEntryIdMatchesIntent | Should -BeTrue
        $e.SourceSizeMatchesIntent | Should -BeTrue
    }
    It 'reports an exact 8-byte positive size difference without approval' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes 1436 -ObservedSourceSizeBytes 1444
        $e.SourceEntryIdMatchesIntent | Should -BeTrue
        $e.SourceSizeMatchesIntent | Should -BeFalse
        $e.SizeDifferenceBytes | Should -Be 8
        $e.ExactMatch | Should -BeFalse
    }
    It 'reports an exact negative size difference' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes 1444 -ObservedSourceSizeBytes 1436
        $e.SizeDifferenceBytes | Should -Be -8
        $e.ExactMatch | Should -BeFalse
    }
    It 'does not confuse a changed EntryID for size drift' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId 'OTHER-ID' -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.SourceEntryIdMatchesIntent | Should -BeFalse
        $e.SourceSizeMatchesIntent | Should -BeTrue
        $e.ExactMatch | Should -BeFalse
    }
    It 'reports both mismatches simultaneously, without silent override' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId 'OTHER-ID' -IntentSizeBytes $size -ObservedSourceSizeBytes 1444
        $e.SourceEntryIdMatchesIntent | Should -BeFalse
        $e.SourceSizeMatchesIntent | Should -BeFalse
        $e.ExactMatch | Should -BeFalse
        $e.SizeDifferenceBytes | Should -Be 8
    }
    It 'uses ordinal case-sensitive EntryID comparison' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'SOURCE' -ObservedEntryId 'source' -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.SourceEntryIdMatchesIntent | Should -BeFalse
    }
    It 'rejects an empty durable EntryID' {
        { Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId '' -ObservedEntryId 'A' -IntentSizeBytes $size -ObservedSourceSizeBytes $actual } | Should -Throw '*nonempty*'
    }
    It 'rejects an empty observed EntryID' {
        { Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'A' -ObservedEntryId '' -IntentSizeBytes $size -ObservedSourceSizeBytes $actual } | Should -Throw '*nonempty*'
    }
    It 'rejects a negative Intent size' {
        { Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'A' -ObservedEntryId 'A' -IntentSizeBytes -1 -ObservedSourceSizeBytes $actual } | Should -Throw '*nonnegative*'
    }
    It 'rejects a negative observed size' {
        { Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'A' -ObservedEntryId 'A' -IntentSizeBytes $size -ObservedSourceSizeBytes -1 } | Should -Throw '*nonnegative*'
    }
    It 'hashes exact EntryID using SHA256 UTF8 rather than printing raw COM identifiers' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'abc' -ObservedEntryId 'abc' -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.ExpectedSourceEntryIdSha256 | Should -Be 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        $e.ObservedSourceEntryIdSha256 | Should -Be $e.ExpectedSourceEntryIdSha256
    }
    It 'produces distinct hashes if IDs differ' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'abc' -ObservedEntryId 'abd' -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.ExpectedSourceEntryIdSha256 | Should -Not -Be $e.ObservedSourceEntryIdSha256
    }
    It 'does not authorize automatic retry in returned evidence' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'does not claim to have executed an Outlook Move' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.OutlookMoveExecuted | Should -BeFalse
    }
    It 'rejects an invalid evidence schema before authorizing match' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.Schema='INVALID'
        { Assert-OPA265BW2SourceFingerprint -Evidence $e } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'allows only exactly matched evidence' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        (Assert-OPA265BW2SourceFingerprint -Evidence $e) | Should -BeTrue
    }
    It 'rejects size mismatch with separate numerical values and signed difference' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes 1436 -ObservedSourceSizeBytes 1444
        { Assert-OPA265BW2SourceFingerprint -Evidence $e } | Should -Throw '*SizeDifferenceBytes=8*'
    }
    It 'rejects EntryID mismatch even when sizes are identical' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'a' -ObservedEntryId 'b' -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        { Assert-OPA265BW2SourceFingerprint -Evidence $e } | Should -Throw '*SourceEntryIdMatchesIntent=False*'
    }
    It 'rejects mismatched size and EntryID together' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'a' -ObservedEntryId 'b' -IntentSizeBytes 1436 -ObservedSourceSizeBytes 1444
        { Assert-OPA265BW2SourceFingerprint -Evidence $e } | Should -Throw '*SourceSizeMatchesIntent=False*'
    }
    It 'does not echo raw EntryID in diagnostic error text' {
        $secret='SYNTHETIC-PRIVATE-ID-DO-NOT-EMIT'
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $secret -ObservedEntryId 'OTHER' -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $message=''
        try { [void](Assert-OPA265BW2SourceFingerprint -Evidence $e) } catch {$message=$_.Exception.Message}
        $message | Should -Not -Match $secret
        $message | Should -Match 'ExpectedSourceEntryIdSha256='
    }
    It 'does not trust evidence permitting an automatic retry' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.AutomaticRetryAllowed=$true
        { Assert-OPA265BW2SourceFingerprint -Evidence $e } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'does not trust evidence claiming a Move occurred' {
        $e=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId $expected -ObservedEntryId $observed -IntentSizeBytes $size -ObservedSourceSizeBytes $actual
        $e.OutlookMoveExecuted=$true
        { Assert-OPA265BW2SourceFingerprint -Evidence $e } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'keeps strict checks as the sole route before incrementing synthetic match count' {
        $path=Join-Path $PSScriptRoot '../../Core/Worker/SyntheticReadOnlyProbe265BW2.ps1'
        $text=Get-Content -LiteralPath $path -Raw
        $text | Should -Match 'Assert-OPA265BW2SourceFingerprint -Evidence'
        $text | Should -Match 'Assert-OPA265BW2MatchingMail -Mail [$]mail'
        $text | Should -Match 'Assert-OPA265BW2SourceFingerprint -Evidence'
        $text | Should -Match 'Assert-OPA265BW2SourceSizeConsent -Evidence'
        $text | Should -Not -Match 'SkipSourceSizeCheck'
    }
    It 'parses changed module under native Windows PowerShell 5.1' {
        $path=Join-Path $PSScriptRoot '../../Core/Worker/SyntheticReadOnlyProbe265BW2.ps1'
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
