#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a5CountEvidence265.ps1')
    $script:controller=Get-Content -LiteralPath (
        Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2a5ReadOnlyCountReview.ps1') -Raw -Encoding UTF8
    function New-BW4k7v2a5Observation {
        param([int]$All=1,[int]$Restrict=1,[int]$Manual=1)
        $candidates=@(for($k=0;$k -lt $Manual;$k++){
            [pscustomobject]@{SubjectMatches=$true;EntryId=('ID'+$k)}
        })
        return [pscustomobject]@{
            FullItemsCount=$All;RestrictCount=$Restrict
            ManualExactSubjectCount=$Manual;MatchingCandidates=$candidates
            ReadComplete=$true;RestrictionReadComplete=$true
        }
    }
    function New-BW4k7v2a5Pair {
        return @{
            Source=(New-BW4k7v2a5Observation)
            Target=(New-BW4k7v2a5Observation -All 0 -Restrict 0 -Manual 0)
        }
    }
}
Describe 'BW4k7v2a5 original failed CreatePilot exact read-only count forensics' {
    It 'reports healthy present-time source1 destination0 but does not rewrite history' {
        $p=New-BW4k7v2a5Pair
        (Test-OPA265BW4k7v2a5CountEvidence @p).Status |
            Should -BeExactly 'NowSourceOneTargetZeroButOriginalFailureCauseUnproven'
    }
    It 'never claims original failed predicate was identified' {
        $p=New-BW4k7v2a5Pair
        (Test-OPA265BW4k7v2a5CountEvidence @p).ExactHistoricalFailedPredicateProven | Should -BeFalse
    }
    It 'detects source Restrict returns zero while direct scan sees 1' {
        $p=New-BW4k7v2a5Pair;$p.Source.RestrictCount=0
        (Test-OPA265BW4k7v2a5CountEvidence @p).Status |
            Should -BeExactly 'SourceRestrictManualCountDiscrepancyObserved'
    }
    It 'detects source Restrict returns 2 while direct scan sees 1' {
        $p=New-BW4k7v2a5Pair;$p.Source.RestrictCount=2
        (Test-OPA265BW4k7v2a5CountEvidence @p).SourceRestrictionMatchesManual | Should -BeFalse
    }
    It 'detects destination Restrict returns one while manual target zero' {
        $p=New-BW4k7v2a5Pair;$p.Target.RestrictCount=1
        (Test-OPA265BW4k7v2a5CountEvidence @p).Status |
            Should -BeExactly 'TargetRestrictManualCountDiscrepancyObserved'
    }
    It 'detects exact source subject absent with zero target' {
        $p=New-BW4k7v2a5Pair
        $p.Source=New-BW4k7v2a5Observation -All 0 -Restrict 0 -Manual 0
        (Test-OPA265BW4k7v2a5CountEvidence @p).Status |
            Should -BeExactly 'CurrentSourceTargetCardinalityNotPreMoveExpected'
    }
    It 'detects two source subjects but no target' {
        $p=New-BW4k7v2a5Pair
        $p.Source=New-BW4k7v2a5Observation -All 2 -Restrict 2 -Manual 2
        (Test-OPA265BW4k7v2a5CountEvidence @p).Status |
            Should -BeExactly 'CurrentSourceTargetCardinalityNotPreMoveExpected'
    }
    It 'detects source one and destination one' {
        $p=New-BW4k7v2a5Pair
        $p.Target=New-BW4k7v2a5Observation
        (Test-OPA265BW4k7v2a5CountEvidence @p).Status |
            Should -BeExactly 'CurrentSourceTargetCardinalityNotPreMoveExpected'
    }
    It 'detects a destination-only item' {
        $p=New-BW4k7v2a5Pair
        $p.Source=New-BW4k7v2a5Observation -All 0 -Restrict 0 -Manual 0
        $p.Target=New-BW4k7v2a5Observation
        (Test-OPA265BW4k7v2a5CountEvidence @p).Status |
            Should -BeExactly 'CurrentSourceTargetCardinalityNotPreMoveExpected'
    }
    It 'returns incomplete if source direct enumeration failed' {
        $p=New-BW4k7v2a5Pair;$p.Source.ReadComplete=$false
        (Test-OPA265BW4k7v2a5CountEvidence @p).Status |
            Should -BeExactly 'ReadOnlyIncompleteOrAmbiguousCountsNeedsManualReview'
    }
    It 'returns incomplete if destination restricted enumeration failed' {
        $p=New-BW4k7v2a5Pair;$p.Target.RestrictionReadComplete=$false
        (Test-OPA265BW4k7v2a5CountEvidence @p).CompleteRead | Should -BeFalse
    }
    It 'returns incomplete if both searches failed' {
        $p=New-BW4k7v2a5Pair;$p.Source.ReadComplete=$false
        $p.Target.RestrictionReadComplete=$false
        (Test-OPA265BW4k7v2a5CountEvidence @p).ReasonCodes |
            Should -Contain 'ProviderOrBoundedReadIncomplete'
    }
    It 'rejects malformed absent source matching candidates' {
        $p=New-BW4k7v2a5Pair
        [void]$p.Source.PSObject.Properties.Remove('MatchingCandidates')
        {Test-OPA265BW4k7v2a5CountEvidence @p} | Should -Throw
    }
    It 'rejects false candidates count contradicting manual count' {
        $p=New-BW4k7v2a5Pair;$p.Source.ManualExactSubjectCount=2
        {Test-OPA265BW4k7v2a5CountEvidence @p} | Should -Throw
    }
    It 'rejects manual count greater than Items.Count' {
        $p=New-BW4k7v2a5Pair;$p.Source.FullItemsCount=0
        {Test-OPA265BW4k7v2a5CountEvidence @p} | Should -Throw
    }
    It 'rejects count over bounded 32 maximum' {
        $p=New-BW4k7v2a5Pair;$p.Source.FullItemsCount=33
        {Test-OPA265BW4k7v2a5CountEvidence @p} | Should -Throw
    }
    It 'rejects negative RestrictCount' {
        $p=New-BW4k7v2a5Pair;$p.Source.RestrictCount=-1
        {Test-OPA265BW4k7v2a5CountEvidence @p} | Should -Throw
    }
    It 'retains identical restriction/manual count comparison when both zero' {
        $p=New-BW4k7v2a5Pair
        (Test-OPA265BW4k7v2a5CountEvidence @p).TargetRestrictionMatchesManual |
            Should -BeTrue
    }
    It 'retains manual observed source count' {
        $p=New-BW4k7v2a5Pair
        (Test-OPA265BW4k7v2a5CountEvidence @p).ObservedSourceManualSubjectCount |
            Should -Be 1
    }
    It 'never grants original failed CreatePilot retry' {
        $p=New-BW4k7v2a5Pair
        (Test-OPA265BW4k7v2a5CountEvidence @p).OriginalCreatePilotMayBeRetried |
            Should -BeFalse
    }
    It 'never grants MovePilot without original preMove manifest' {
        $p=New-BW4k7v2a5Pair
        (Test-OPA265BW4k7v2a5CountEvidence @p).OriginalMovePilotMayBeInvoked |
            Should -BeFalse
    }
    It 'never grants production writer' {
        $p=New-BW4k7v2a5Pair
        $r=Test-OPA265BW4k7v2a5CountEvidence @p
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'requires exact original creation intent and no-retry marker' {
        $script:controller | Should -Match 'CreationIntent.1'
        $script:controller | Should -Match 'NoAutomaticRetry'
        $script:controller | Should -Match 'OriginalIntentSha256'
    }
    It 'queries both the raw Items.Count and independent Restrict Count' {
        $script:controller | Should -Match '\$items\.Count'
        $script:controller | Should -Match '\$restricted\.Count'
        $script:controller | Should -Match 'RestrictEnumeratedCount'
    }
    It 'bounds full Items enumeration to sixteen source and target entries' {
        $script:controller | Should -Match '\$count -gt 16'
        $script:controller | Should -Match '>\s*16 folder items'
    }
    It 'uses exact default Drafts without ever touching original POP3 delivery PST mail' {
        $script:controller | Should -Match 'GetDefaultFolder\(16\)'
        $script:controller | Should -Match 'Pop3DeliveryStoreId'
        $script:controller | Should -Match 'TargetFolderName'
    }
    It 'inspects Body and To only for exact synthetic Subject' {
        $script:controller | Should -Match 'if\(\[string\]\$item.Subject -cne \$Subject\)\{continue\}'
        $script:controller | Should -Match 'BodyMatchesExpected'
        $script:controller | Should -Match 'ToMatchesExpected'
    }
    It 'uses GetItemFromID for matching synthetic candidates only' {
        $script:controller | Should -Match 'GetItemFromID'
        $script:controller | Should -Match 'SubjectMatches'
    }
    It 'never saves moves sends deletes or creates Outlook objects' {
        $script:controller | Should -Not -Match '\.(Save|Move|Send|Delete|AddStore|AddStoreEx|CreateItem)\s*\('
        $script:controller | Should -Not -Match 'New-Object -ComObject'
    }
    It 'never creates evidence or PST files and preserves all original suite files' {
        $script:controller | Should -Not -Match 'WriteAllText|WriteAllBytes|CreateDirectory|FileMode]::CreateNew'
        $script:controller | Should -Not -Match 'Remove-Item|Set-ItemProperty|New-Item'
    }
    It 'requires an already-running matching Outlook process' {
        $script:controller | Should -Match 'GetActiveObject'
        $script:controller | Should -Match 'Get-Process -Name OUTLOOK'
    }
    It 'does not search other stores or any other mail folder' {
        $script:controller | Should -Not -Match 'GetDefaultFolder\((6|5|4|3|10)\)'
        $script:controller | Should -Match 'OtherStoresMailSearched=\$false'
    }
}