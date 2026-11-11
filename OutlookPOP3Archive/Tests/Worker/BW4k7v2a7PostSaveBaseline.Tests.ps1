#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a7PostSaveBaselinePolicy265.ps1')
    $script:c=Get-Content -LiteralPath (
        Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2a7PostSaveBaselineOneShot.ps1') -Raw -Encoding UTF8
    function New-BW4k7v2a7Baseline {
        param([string]$Expected='The exact test body',[string]$Saved='The exact test body')
        Get-OPA265BW4k7v2a7PostSaveBodyBaseline -ExpectedSyntheticBody $Expected -ActuallySavedBody $Saved
    }
}
Describe 'BW4k7v2a7 strict new disposable post-Save synthetic Body baseline and one-shot Move guards' {
    It 'accepts exact unchanged post-Save synthetic Body' {
        $r=New-BW4k7v2a7Baseline
        $r.ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeTrue
    }
    It 'classifies unchanged synthetic Body separately from changed Body' {
        (New-BW4k7v2a7Baseline).Status | Should -BeExactly 'ExactSyntheticBodyAfterSave'
    }
    It 'accepts only known CRLF then SPACE suffix of three UTF16 chars' {
        $suffix=([char]13).ToString()+([char]10).ToString()+' '
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved ('Hello'+$suffix)).Status |
            Should -BeExactly 'KnownThreeCharacterSyntheticPostSaveWhitespaceSuffix'
    }
    It 'accepts known SPACE then CRLF suffix for isolated fixture only' {
        $suffix=' '+([char]13).ToString()+([char]10).ToString()
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved ('Hello'+$suffix)).ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeTrue
    }
    It 'accepts known CRLF then TAB suffix for isolated fixture only' {
        $suffix=([char]13).ToString()+([char]10).ToString()+[char]9
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved ('Hello'+$suffix)).OnlyKnownExactWhitespaceSuffixAllowed | Should -BeTrue
    }
    It 'accepts known TAB then CRLF suffix for isolated fixture only' {
        $suffix=([char]9).ToString()+([char]13).ToString()+([char]10).ToString()
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved ('Hello'+$suffix)).ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeTrue
    }
    It 'rejects CRLF alone without a third whitespace character' {
        $s='Hello'+[char]13+[char]10
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved $s).ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'rejects LF-only suffix' {
        $s='Hello'+[char]10
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved $s).ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'rejects double CRLF suffix' {
        $s='Hello'+[char]13+[char]10+[char]13+[char]10
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved $s).ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'rejects nonwhitespace appended Outlook signature' {
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved 'Hello PRIVATESIGNATURE').ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'rejects modified character within original expected text' {
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved 'He1lo').ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'rejects deleted original character' {
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved 'Hell').ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'rejects prefixed garbage ahead of original text' {
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved 'XHello').ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'rejects three spaces, despite being only whitespace' {
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved 'Hello   ').ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'rejects CRLF and nonspace nondisposable suffix' {
        $s='Hello'+[char]13+[char]10+'X'
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved $s).ApprovedForNewDisposableSyntheticFixtureBaseline | Should -BeFalse
    }
    It 'records original bytes length and appended suffix length without returning Body' {
        $s='Hello'+[char]13+[char]10+' '
        $r=New-BW4k7v2a7Baseline -Expected 'Hello' -Saved $s
        $r.OriginalExpectedUtf8Bytes | Should -Be 5
        $r.ActualSavedUtf8Bytes | Should -Be 8
        $r.BodySuffixUtf16CodeUnits | Should -Be 3
    }
    It 'records changed SHA256 for +3 synthetic suffix' {
        $s='Hello'+[char]13+[char]10+' '
        $r=New-BW4k7v2a7Baseline -Expected 'Hello' -Saved $s
        $r.OriginalExpectedSha256 | Should -Not -BeExactly $r.ActualSavedSha256
    }
    It 'records equal SHA256 for exact unchanged Body' {
        $r=New-BW4k7v2a7Baseline
        $r.OriginalExpectedSha256 | Should -BeExactly $r.ActualSavedSha256
    }
    It 'always refuses production template normalization waiver' {
        $s='Hello'+[char]13+[char]10+' '
        (New-BW4k7v2a7Baseline -Expected 'Hello' -Saved $s).AnyProductionSemanticWaiverGranted | Should -BeFalse
    }
    It 'never approves a difference introduced by Move' {
        (New-BW4k7v2a7Baseline).AnyPostMoveBodyDifferenceAccepted | Should -BeFalse
    }
    It 'does not leak post-Save synthetic body or suffix in JSON report' {
        $r=New-BW4k7v2a7Baseline -Expected 'PRE' -Saved 'PRE Private-BODY-Text'
        ($r|ConvertTo-Json -Compress -Depth 4) | Should -Not -Match 'Private-BODY-Text'
        $r.ActualBodyReturned | Should -BeFalse
        $r.ActualSuffixReturned | Should -BeFalse
    }
    It 'rejects the old failed BW4k7v2a4 SuiteId in new layout' {
        {Get-OPA265BW4k7v2a7Layout -SuiteId '7451b8f5-6404-4496-ae7b-5b1cdfb9063a' -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'rejects old failed BW4k7v2a1 SuiteId in new layout' {
        {Get-OPA265BW4k7v2a7Layout -SuiteId '2c15cb7c-4c09-4bcf-bca1-9fec458af3a5' -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'requires a fresh lowercase new SuiteId and unique disposable PST' {
        $suite='4e472e41-6761-4c86-aa91-25d6c1cc969e'
        $l=Get-OPA265BW4k7v2a7Layout -SuiteId $suite -LocalAppData $env:LOCALAPPDATA
        $l.PstPath | Should -Match ([regex]::Escape($suite))
        $l.PstPath | Should -Match 'BW4k7v2a7'
    }
    It 'controller creates exactly one synthetic Draft Save() call' {
        ([regex]::Matches($script:c,'\$source\.Save\(')).Count | Should -Be 1
    }
    It 'controller has no immediate post-Save Restrict cardinality assertion' {
        $postSave=$script:c.IndexOf('$source.Save()')
        $seal=$script:c.IndexOf('$stage=''Seal immutable original source pre-Move manifest''')
        $chunk=$script:c.Substring($postSave,$seal-$postSave)
        $chunk | Should -Not -Match 'Get-OPA265BW4k7v2a7SubjectItems'
        $chunk | Should -Match 'GetItemFromID'
    }
    It 'controller snapshots actual saved source Body rather than pre-Save literal' {
        $script:c | Should -Match 'ActuallySavedBody \(\[string\]\$witness\.Body\)'
        $script:c | Should -Match 'SyntheticSavedActualBodySha256'
        $script:c | Should -Match 'SyntheticSavedBodyPinnedAsExactPreMoveWitness'
    }
    It 'controller verifies two by-ID readbacks before creating immutable manifest' {
        $chunk=$script:c.Substring($script:c.IndexOf('$source.Save()'))
        ([regex]::Matches($chunk,'\$ns\.GetItemFromID\(\$sourceId,\$srcStoreId\)')).Count | Should -Be 2
    }
    It 'controller explicitly stores numeric cardinality separate from singleton COM item' {
        $script:c | Should -Match 'Count=\[int\]\$count'
        $script:c | Should -Match 'Matches=@\(\$matches\.ToArray\(\)\)'
    }
    It 'controller requires independent pre-Move source one target zero' {
        $script:c | Should -Match '\$sourceMatches\.Count -ne 1'
        $script:c | Should -Match '\$targetMatches\.Count -ne 0'
    }
    It 'controller keeps exactly one explicit COM MailItem.Move' {
        ([regex]::Matches($script:c,'\$read\.Move\(')).Count | Should -Be 1
    }
    It 'controller seals durable one-shot claim before invoking Move' {
        $claim=$script:c.IndexOf('Write-OPA265BW4k7v2a1JsonOnce -Path $layout.MoveClaimPath')
        $move=$script:c.IndexOf('$moved=$read.Move(')
        $claim | Should -BeGreaterThan 0
        $move | Should -BeGreaterThan $claim
    }
    It 'controller rejects manifest/body baseline mismatch before Move' {
        $script:c | Should -Match 'bodyReview\.ActualSavedSha256'
        $script:c | Should -Match 'manifest\.SyntheticSavedActualBodySha256'
        $script:c | Should -Match 'saved Body changed relative to sealed pre-Move baseline'
    }
    It 'controller preserves separate explicit consent for default IMAP Drafts synthetic writing' {
        $script:c | Should -Match 'AllowDefaultDraftsSyntheticWrite'
        $script:c | Should -Match 'CREATE BW4K7V2A7 DRAFT'
    }
    It 'controller preserves separate explicit consent for one-shot Move' {
        $script:c | Should -Match 'ConfirmOneShotMove'
        $script:c | Should -Match 'MOVE BW4K7V2A7 ONCE'
    }
    It 'controller requires independent process restart after one Move attempt' {
        $script:c | Should -Match 'Reconcile requires complete Outlook process restart'
    }
    It 'controller does not automatically delete any old Draft or old test PST' {
        $script:c | Should -Not -Match '\.(Delete|Send|RemoveStore|RemoveStoreEx)\s*\('
    }
    It 'controller does not enable production SEM001/archive worker' {
        $script:c | Should -Match 'WriterPermit=\$false'
        $script:c | Should -Match 'ProductionReady=\$false'
    }
    It 'witness policy does not permit raw MAPI flag changes or Move retry' {
        $policy=(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a7PostSaveBaselinePolicy265.ps1') -Raw -Encoding UTF8)
        $policy | Should -Match 'OriginalMoveMayBeRetried=\$false'
        $policy | Should -Match 'SEM001RiskAcceptanceAutomaticallyGranted=\$false'
    }
}