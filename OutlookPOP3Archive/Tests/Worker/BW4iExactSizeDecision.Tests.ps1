#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4iExactSizeDecision265.ps1')
    $script:p=Get-OPA265BW4iPins
    $script:comparison=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4h2.IndependentFiveFieldPostMoveCompare.1'
        Status='OnlyMAPIMessageSizeChangedManualReview'
        TestId=$script:p.TestId
        OriginalSourceEntryId=$script:p.SourceEntryId
        ConfirmedDestinationEntryId=$script:p.DestinationEntryId
        SourceMessageIdMatches=0
        DestinationMessageIdMatches=1
        SubjectMatches=$true
        SenderEmailAddressMatches=$true
        BodyMatches=$true
        SizeMatches=$false
        ReceivedUtcTicksMatches=$true
        FourNonSizeFieldsMatch=$true
        SourceSize=[long]8760
        DestinationSize=[long]8798
        DestinationMinusSourceSize=[long]38
        CompositeFingerprintMatches=$false
        IndependentPreMoveFieldEvidenceAvailable=$true
        SourceFieldEvidenceSha256=$script:p.SourceEvidenceSha256
        ImmutableOneShotClaimSha256=$script:p.MoveClaimSha256
        OriginalHistoricIntentUnchanged=$true
        SevenHistoricalEvidenceHashesUnchanged=$true
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        MailItemMoveExecuted=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
    }
}
Describe 'BW4i exact pinned only synthetic one-shot MAPI size decision preflight' {
    BeforeEach {$script:x=$script:comparison.PSObject.Copy()}
    It 'accepts exact independent BW4h2 +38B four-field-match observation' {
        (Assert-OPA265BW4iComparison -Comparison $script:x) | Should -BeTrue
    }
    It 'pins exact previously observed TestId' {
        $script:p.TestId | Should -BeExactly '841545a1-b5fa-4c69-964a-8c0318981d52'
    }
    It 'pins original 8760 and destination 8798 as exact values' {
        $script:p.SourceSize | Should -Be 8760
        $script:p.DestinationSize | Should -Be 8798
        $script:p.SizeDelta | Should -Be 38
    }
    It 'rejects different TestId' {
        $script:x.TestId='98bef817-0fb5-478a-b869-33f02fda59d3'
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects different schema or outcome' {
        $script:x.Status='IndependentOutlookReadOnlyMoveReconciled'
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects source still holding one duplicate' {
        $script:x.SourceMessageIdMatches=1
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects duplicate destination item' {
        $script:x.DestinationMessageIdMatches=2
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects different original EntryID' {
        $script:x.OriginalSourceEntryId='00000000DEADBEEF'
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects different destination EntryID' {
        $script:x.ConfirmedDestinationEntryId='00000000DEADBEEF'
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed Subject' {
        $script:x.SubjectMatches=$false
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed sender' {
        $script:x.SenderEmailAddressMatches=$false
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed body' {
        $script:x.BodyMatches=$false
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed received timestamp' {
        $script:x.ReceivedUtcTicksMatches=$false
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects false non-size field comparison flag' {
        $script:x.FourNonSizeFieldsMatch=$false
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed source Size' {
        $script:x.SourceSize=8759
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed destination Size' {
        $script:x.DestinationSize=8800
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects wrong delta' {
        $script:x.DestinationMinusSourceSize=40
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed source BW4h2 SHA256' {
        $script:x.SourceFieldEvidenceSha256=('0'*64)
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed permanent BW4g claim SHA256' {
        $script:x.ImmutableOneShotClaimSha256=('0'*64)
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed historic Intent' {
        $script:x.OriginalHistoricIntentUnchanged=$false
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects changed seven historical files' {
        $script:x.SevenHistoricalEvidenceHashesUnchanged=$false
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
    It 'rejects any production-ready or replay permission' {
        $script:x.CanRetryMove=$true
        {Assert-OPA265BW4iComparison -Comparison $script:x} | Should -Throw
    }
}
Describe 'BW4i exact one-time operator decision schema' {
    BeforeEach {$script:d=(New-OPA265BW4iDecision -Comparison $script:comparison)}
    It 'creates only a zero-privilege exact manual acknowledgment' {
        $script:d.OperatorDecision | Should -BeExactly 'AcknowledgeExactDisposableMAPIMessageSizeDriftOnly'
        (Assert-OPA265BW4iDecision -Decision $script:d) | Should -BeTrue
        $script:d.CanDispatchProductionWorker | Should -BeFalse
        $script:d.OriginalJournalWriteAllowed | Should -BeFalse
        $script:d.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'denies additional property opening fake privileged action' {
        $script:d | Add-Member NoteProperty CanMoveAgain $true
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
    It 'denies missing one SHA256 field' {
        $script:d.PSObject.Properties.Remove('SourceEvidenceSha256')
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
    It 'denies decision with new archive EntryID' {
        $script:d.DestinationEntryId='not-original'
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
    It 'denies another signed size delta' {
        $script:d.DestinationMinusSourceSize=40
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
    It 'denies false or forged BodyMatches' {
        $script:d.BodyMatches='True'
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
    It 'denies hidden historical writer permission' {
        $script:d.OriginalJournalWriteAllowed=$true
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
    It 'denies change to observed original composite hash' {
        $script:d.OriginalCompositeSha256=('f'*64)
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
    It 'denies forged production-readiness' {
        $script:d.ProductionReady=$true
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
    It 'denies malformed UTC in acceptance receipt' {
        $script:d.DecisionUtc='bad'
        {Assert-OPA265BW4iDecision -Decision $script:d} | Should -Throw
    }
}
Describe 'BW4i write-once manual decision evidence' {
    BeforeAll {$script:oldAppData=$env:LOCALAPPDATA}
    AfterAll {$env:LOCALAPPDATA=$script:oldAppData}
    It 'uses exact per-user local AppData path only' {
        $p=Get-OPA265BW4iDecisionPath -TestId $script:p.TestId -LocalAppData 'C:\Temp'
        $p | Should -BeExactly ('C:\Temp\OutlookPOP3Archive-BW4i-ManualSizeDecisions\fixture-'+$script:p.TestId+'.json')
    }
    It 'rejects any other fixture even when GUID valid' {
        {Get-OPA265BW4iDecisionPath -TestId '98bef817-0fb5-478a-b869-33f02fda59d3' -LocalAppData 'C:\Temp'} | Should -Throw
    }
    It 'rejects redirected operator decision path' {
        $env:LOCALAPPDATA=$TestDrive
        $d=New-OPA265BW4iDecision -Comparison $script:comparison
        {Write-OPA265BW4iDecisionOnce -Decision $d -DecisionPath 'C:\Temp\hijack.json'} | Should -Throw
    }
    It 'durably writes original exact decision with UTF8 BOM and denies overwrite on second call' {
        $env:LOCALAPPDATA=$TestDrive
        $d=New-OPA265BW4iDecision -Comparison $script:comparison
        $path=Get-OPA265BW4iDecisionPath -TestId $script:p.TestId
        $result=Write-OPA265BW4iDecisionOnce -Decision $d -DecisionPath $path
        [IO.File]::Exists($result) | Should -BeTrue
        ([IO.File]::ReadAllBytes($result)[0]) | Should -Be 239
        $r=Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json
        (Assert-OPA265BW4iDecision -Decision $r) | Should -BeTrue
        {Write-OPA265BW4iDecisionOnce -Decision $d -DecisionPath $path} | Should -Throw
    }
}
Describe 'BW4i controller contains no Move or journal write privileges' {
    BeforeAll {
        $script:code=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4iExactSizeDriftDecision.ps1'))
    }
    It 'does not call Outlook MailItem.Move' {
        $script:code | Should -Not -Match '(?i)\$mail\.Move\('
    }
    It 'does not invoke production Worker or an original operation journal writer' {
        $script:code | Should -Not -Match 'Write-OPAOperationJournal'
        $script:code | Should -Not -Match 'Write-OPA265BW4gOneShotClaim'
    }
    It 'replays complete BW4h2 read-only check on every mode' {
        $script:code | Should -Match 'Invoke-OPA265BW4h2DurableFieldEvidence\.ps1'
        $script:code | Should -Match 'Assert-OPA265BW4iComparison'
    }
    It 'requires explicit opt-in confirmation only for Accept' {
        $script:code | Should -Match 'ConfirmExactSizeDrift'
        $script:code | Should -Match 'Decision already exists'
    }
    It 'requires externally pinned acceptance SHA256 to verify' {
        $script:code | Should -Match 'ExpectedDecisionSha256'
    }
}
