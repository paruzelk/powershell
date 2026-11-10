#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a6BodyIntegrityPolicy265.ps1')
    $script:controller=Get-Content -LiteralPath (
        Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2a6ReadOnlyBodyReview.ps1') -Raw -Encoding UTF8
    function New-BW4k7v2a6ReadPair {
        param([string]$Expected='A simple synthetic Body',[string]$Observed='A simple synthetic Body')
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody $Expected -ObservedBody $Observed
        $b=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody $Expected -ObservedBody $Observed
        return @{InitialEvidence=$a;IndependentEvidence=$b;OneExactSyntheticCandidate=$true;ParentStoreAndFolderSame=$true;EntryIdAndSubjectSame=$true}
    }
}
Describe 'BW4k7v2a6 exact synthetic Body read-only fingerprint and SEM001 no-move gate' {
    It 'classifies an exact synthetic body as exact, without enabling Move' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'alpha' -ObservedBody 'alpha'
        $a.Status | Should -BeExactly 'ExactBodyMatch'
        $a.BodyMatchesExactly | Should -BeTrue
        $a.MoveAllowed | Should -BeFalse
    }
    It 'SHA256 fingerprints are stable and 64 lowercase hex characters' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'ab' -ObservedBody 'ab'
        $a.OriginalExpectedUtf8Sha256 | Should -Match '^[a-f0-9]{64}$'
        $a.OriginalExpectedUtf8Sha256 | Should -BeExactly $a.ActualObservedUtf8Sha256
    }
    It 'classifies CRLF versus LF as unaccepted line-ending change' {
        $s="A"+[char]13+[char]10+"B"
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody $s -ObservedBody ("A"+[char]10+"B")
        $a.Status | Should -BeExactly 'LineEndingOnlyDifferenceUnaccepted'
        $a.NormalizedLineEndingsWouldMatch | Should -BeTrue
    }
    It 'classifies CR versus LF as unaccepted line-ending change' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody ("A"+[char]13+"B") -ObservedBody ("A"+[char]10+"B")
        $a.Status | Should -BeExactly 'LineEndingOnlyDifferenceUnaccepted'
    }
    It 'detects one appended newline as unaccepted trailing whitespace' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'A' -ObservedBody ("A"+[char]13+[char]10)
        $a.Status | Should -BeExactly 'TrailingWhitespaceOnlyDifferenceUnaccepted'
    }
    It 'detects trailing spaces as unaccepted whitespace' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'A' -ObservedBody 'A  '
        $a.TrimmingTrailingWhitespaceWouldMatch | Should -BeTrue
    }
    It 'never silently allows whitespace normalization' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'A' -ObservedBody 'A '
        $a.BodyNormalizationOrDifferenceAccepted | Should -BeFalse
    }
    It 'detects added non-whitespace suffix without exposing it' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'A' -ObservedBody 'A PRIVATE-SIGNATURE'
        $a.Status | Should -BeExactly 'NonWhitespaceSuffixAddedUnaccepted'
        $a.AnyRawBodyOrSuffixTextReturned | Should -BeFalse
    }
    It 'does not include added signature text in object serialization' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'A' -ObservedBody 'A SENSITIVE-TEXT-NEVER-RETURN'
        ($a | ConvertTo-Json -Compress -Depth 3) | Should -Not -Match 'SENSITIVE-TEXT-NEVER-RETURN'
    }
    It 'reports common prefix length but not character content' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'Hello' -ObservedBody 'HelXo'
        $a.CommonPrefixUtf16CodeUnits | Should -Be 3
    }
    It 'detects truncation of expected content' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'Hello' -ObservedBody 'Hel'
        $a.Status | Should -BeExactly 'ExpectedBodyTruncatedUnaccepted'
    }
    It 'detects changes in the middle of the Body' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'Hello' -ObservedBody 'Hella'
        $a.Status | Should -BeExactly 'UnexpectedBodyMismatch'
    }
    It 'detects case-sensitive differences' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'Test' -ObservedBody 'test'
        $a.BodyMatchesExactly | Should -BeFalse
    }
    It 'allows the expected body to be empty only for pure policy unit tests' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody '' -ObservedBody ''
        $a.Status | Should -BeExactly 'ExactBodyMatch'
    }
    It 'records UTF8 bytes distinctly from UTF16 code units' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'Ё' -ObservedBody 'Ё'
        $a.ExpectedUtf16CodeUnits | Should -Be 1
        $a.ExpectedUtf8ByteCount | Should -Be 2
    }
    It 'counts actual CRLF pairs separately from lone LF' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'A' -ObservedBody ("X"+[char]13+[char]10+[char]10)
        $a.ObservedCrLfCount | Should -Be 1
        $a.ObservedBareLfCount | Should -Be 1
    }
    It 'counts standalone CR separately' {
        $a=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'A' -ObservedBody ("X"+[char]13+"B")
        $a.ObservedBareCrCount | Should -Be 1
    }
    It 'flags both readbacks body-exact but still refuses to retry or move' {
        $p=New-BW4k7v2a6ReadPair
        $r=Test-OPA265BW4k7v2a6FreshBodyRead @p
        $r.Status | Should -BeExactly 'CurrentExactBodyStableButOriginalFailedSaveGateUnprovenNoMove'
        $r.ExistingSuiteMoveAllowed | Should -BeFalse
    }
    It 'flags stable but non-matching Body as an explicit move blocker' {
        $p=New-BW4k7v2a6ReadPair -Expected 'Hello' -Observed 'Hello EXTRA'
        (Test-OPA265BW4k7v2a6FreshBodyRead @p).Status | Should -BeExactly 'BodyMismatchBlocksMoveAndRequiresManualReview'
    }
    It 'flags first and independently opened read with different Body hashes' {
        $p=New-BW4k7v2a6ReadPair
        $p.IndependentEvidence=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody 'A simple synthetic Body' -ObservedBody 'DIFFERENT'
        (Test-OPA265BW4k7v2a6FreshBodyRead @p).Status | Should -BeExactly 'SyntheticBodyChangedBetweenReadbacksNoMove'
    }
    It 'flags ambiguous synthetic identity instead of allowing Move' {
        $p=New-BW4k7v2a6ReadPair;$p.EntryIdAndSubjectSame=$false
        (Test-OPA265BW4k7v2a6FreshBodyRead @p).Status | Should -BeExactly 'AmbiguousOrMisroutedSyntheticSourceNoMove'
    }
    It 'flags unexpected parent store as unsafe' {
        $p=New-BW4k7v2a6ReadPair;$p.ParentStoreAndFolderSame=$false
        (Test-OPA265BW4k7v2a6FreshBodyRead @p).Status | Should -BeExactly 'AmbiguousOrMisroutedSyntheticSourceNoMove'
    }
    It 'flags source cardinality two even with exact Body' {
        $p=New-BW4k7v2a6ReadPair;$p.OneExactSyntheticCandidate=$false
        (Test-OPA265BW4k7v2a6FreshBodyRead @p).Status | Should -BeExactly 'AmbiguousOrMisroutedSyntheticSourceNoMove'
    }
    It 'rejects forged missing SHA256 in readback evidence' {
        $p=New-BW4k7v2a6ReadPair
        $p.IndependentEvidence.ActualObservedUtf8Sha256='bad'
        {Test-OPA265BW4k7v2a6FreshBodyRead @p} | Should -Throw
    }
    It 'never claims original transient Save count failure was proven' {
        $p=New-BW4k7v2a6ReadPair
        (Test-OPA265BW4k7v2a6FreshBodyRead @p).ExactOriginalPostSavePredicateHistoricallyProven | Should -BeFalse
    }
    It 'never waives unknown raw MAPI flag changes' {
        $p=New-BW4k7v2a6ReadPair
        (Test-OPA265BW4k7v2a6FreshBodyRead @p).RawMapiFlagsWaived | Should -BeFalse
    }
    It 'never permits old failed creation retry' {
        $p=New-BW4k7v2a6ReadPair
        (Test-OPA265BW4k7v2a6FreshBodyRead @p).OriginalCreatePilotMayBeRetried | Should -BeFalse
    }
    It 'never permits old failed Move or production worker' {
        $p=New-BW4k7v2a6ReadPair
        $r=Test-OPA265BW4k7v2a6FreshBodyRead @p
        $r.OriginalMovePilotMayBeInvoked | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'controller pins exact original failed SuiteId and immutable intent SHA' {
        $script:controller | Should -Match '7451b8f5-6404-4496-ae7b-5b1cdfb9063a'
        $script:controller | Should -Match 'd31a549a4b9baca30a9bcce661230d2f545b1e538d7da4bbccf1a33f6b16e1f8'
    }
    It 'controller bounds scan to only default Drafts exact synthetic subject' {
        $script:controller | Should -Match 'GetDefaultFolder\(16\)'
        $script:controller | Should -Match '\$sourceCount -gt 16'
        $script:controller | Should -Match '\$item.Subject -cne'
    }
    It 'controller scans no content of unrelated mailbox messages' {
        $script:controller | Should -Match 'if\(\[string\]\$item.Subject -cne \[string\]\$layout.Subject\)\{continue\}'
        $script:controller | Should -Not -Match '\$item\.Body'
    }
    It 'controller uses GetItemFromID and performs a second Body fingerprint read' {
        $script:controller | Should -Match 'GetItemFromID'
        $script:controller | Should -Match 'ReopenedByIdBodyEvidence'
    }
    It 'controller forbids writing, moving, deleting or attaching any PST' {
        $script:controller | Should -Not -Match '\.(Save|Move|Send|Delete|AddStore|AddStoreEx|CreateItem|RemoveStore)\s*\('
        $script:controller | Should -Not -Match 'CreateDirectory|WriteAllText|FileMode]::CreateNew'
    }
    It 'controller never returns raw synthetic Body or signature' {
        $script:controller | Should -Match 'RawBodyOrSignatureReturned=\$false'
        $script:controller | Should -Not -Match 'ActualBody\s*='
    }
}