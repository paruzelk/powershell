#requires -Version 5.1
# BW4i: exact disposable TestId ONLY. Operator acknowledges observed MAPI Size
# drift in a SEPARATE write-once evidence record; NEVER permits PST/journal edits.
function Get-OPA265BW4iPins {
    [CmdletBinding()]
    param()
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4i.ExactFixturePins.1'
        TestId='841545a1-b5fa-4c69-964a-8c0318981d52'
        RunId='a7b51427-7494-43f4-bc96-64915f6bee7e'
        OriginalJournalSha256='5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648'
        SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35E4683C00'
        DestinationFolderEntryId='000000002EC2EEA907B12B44AAB1F6C6E4953CF982800000'
        DestinationEntryId='000000002EC2EEA907B12B44AAB1F6C6E4953CF924002000'
        InternetMessageId='<000001dd6871$0723c200$156b4600$@stios.ru>'
        SourceEvidenceSha256='c0a7700de3b3d5b5e7e26dc778ce62ea2858a1be7bbf5e1145fbfd5f787a448b'
        MoveClaimSha256='809f047c235fb8dff398bd040460e2b0fa042406dcdfda093bfdd3aabfabe72b'
        OriginalCompositeSha256='3ec10c9f31412bc2a9a207b63e07c1d5dad5e99fb45e9d5870df56351bdb3709'
        SourceSize=[long]8760
        DestinationSize=[long]8798
        SizeDelta=[long]38
    }
}
function Get-OPA265BW4iDecisionPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $pin=Get-OPA265BW4iPins
    if ($TestId -cne $pin.TestId -or
        [string]::IsNullOrWhiteSpace($LocalAppData) -or
        -not [IO.Path]::IsPathRooted($LocalAppData)) {
        throw 'BW4i accepts only pinned disposable TestId and per-user AppData.'
    }
    Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4i-ManualSizeDecisions') ('fixture-'+$TestId+'.json')
}
function Assert-OPA265BW4iComparison {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Comparison)
    $pin=Get-OPA265BW4iPins
    if ($null -eq $Comparison -or
        [string]$Comparison.Schema -cne '2.6.5-BW4h2.IndependentFiveFieldPostMoveCompare.1' -or
        [string]$Comparison.Status -cne 'OnlyMAPIMessageSizeChangedManualReview' -or
        [string]$Comparison.TestId -cne $pin.TestId -or
        [string]$Comparison.OriginalSourceEntryId -cne $pin.SourceEntryId -or
        [string]$Comparison.ConfirmedDestinationEntryId -cne $pin.DestinationEntryId -or
        [int]$Comparison.SourceMessageIdMatches -ne 0 -or
        [int]$Comparison.DestinationMessageIdMatches -ne 1 -or
        $Comparison.SubjectMatches -isnot [bool] -or -not $Comparison.SubjectMatches -or
        $Comparison.SenderEmailAddressMatches -isnot [bool] -or -not $Comparison.SenderEmailAddressMatches -or
        $Comparison.BodyMatches -isnot [bool] -or -not $Comparison.BodyMatches -or
        $Comparison.ReceivedUtcTicksMatches -isnot [bool] -or -not $Comparison.ReceivedUtcTicksMatches -or
        $Comparison.FourNonSizeFieldsMatch -isnot [bool] -or -not $Comparison.FourNonSizeFieldsMatch -or
        $Comparison.SizeMatches -isnot [bool] -or $Comparison.SizeMatches -or
        [long]$Comparison.SourceSize -ne $pin.SourceSize -or
        [long]$Comparison.DestinationSize -ne $pin.DestinationSize -or
        [long]$Comparison.DestinationMinusSourceSize -ne $pin.SizeDelta -or
        $Comparison.CompositeFingerprintMatches -isnot [bool] -or $Comparison.CompositeFingerprintMatches -or
        $Comparison.IndependentPreMoveFieldEvidenceAvailable -isnot [bool] -or -not $Comparison.IndependentPreMoveFieldEvidenceAvailable -or
        [string]$Comparison.SourceFieldEvidenceSha256 -cne $pin.SourceEvidenceSha256 -or
        [string]$Comparison.ImmutableOneShotClaimSha256 -cne $pin.MoveClaimSha256 -or
        $Comparison.OriginalHistoricIntentUnchanged -isnot [bool] -or -not $Comparison.OriginalHistoricIntentUnchanged -or
        $Comparison.SevenHistoricalEvidenceHashesUnchanged -isnot [bool] -or -not $Comparison.SevenHistoricalEvidenceHashesUnchanged -or
        $Comparison.FullMAPIByteEqualityProven -isnot [bool] -or $Comparison.FullMAPIByteEqualityProven -or
        $Comparison.PhysicalPstDurabilityProven -isnot [bool] -or $Comparison.PhysicalPstDurabilityProven -or
        $Comparison.MailItemMoveExecuted -isnot [bool] -or $Comparison.MailItemMoveExecuted -or
        $Comparison.CanRetryMove -isnot [bool] -or $Comparison.CanRetryMove -or
        $Comparison.CanWriteHistoricalJournal -isnot [bool] -or $Comparison.CanWriteHistoricalJournal -or
        $Comparison.ProductionReady -isnot [bool] -or $Comparison.ProductionReady) {
        throw 'BW4i REFUSED: independent BW4h2 exact fixture +38B and four matching fields are mandatory.'
    }
    return $true
}
function New-OPA265BW4iDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Comparison)
    [void](Assert-OPA265BW4iComparison -Comparison $Comparison)
    $p=Get-OPA265BW4iPins
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4i.ExactFixtureManualSizeDecision.1'
        TestId=$p.TestId
        RunId=$p.RunId
        OriginalJournalSha256=$p.OriginalJournalSha256
        SourceEntryId=$p.SourceEntryId
        DestinationEntryId=$p.DestinationEntryId
        InternetMessageId=$p.InternetMessageId
        SourceEvidenceSha256=$p.SourceEvidenceSha256
        MoveClaimSha256=$p.MoveClaimSha256
        OriginalCompositeSha256=$p.OriginalCompositeSha256
        SourceSize=[long]$p.SourceSize
        DestinationSize=[long]$p.DestinationSize
        DestinationMinusSourceSize=[long]$p.SizeDelta
        SubjectMatches=$true
        SenderEmailAddressMatches=$true
        BodyMatches=$true
        ReceivedUtcTicksMatches=$true
        OperatorDecision='AcknowledgeExactDisposableMAPIMessageSizeDriftOnly'
        DecisionUtc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        OriginalJournalWriteAllowed=$false
        CanDispatchProductionWorker=$false
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4iDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Decision)
    $p=Get-OPA265BW4iPins
    $exact=@('Schema','TestId','RunId','OriginalJournalSha256','SourceEntryId',
        'DestinationEntryId','InternetMessageId','SourceEvidenceSha256',
        'MoveClaimSha256','OriginalCompositeSha256','SourceSize','DestinationSize',
        'DestinationMinusSourceSize','SubjectMatches','SenderEmailAddressMatches',
        'BodyMatches','ReceivedUtcTicksMatches','OperatorDecision','DecisionUtc',
        'AutomaticRetryAllowed','OriginalJournalWriteAllowed',
        'CanDispatchProductionWorker','FullMAPIByteEqualityProven',
        'PhysicalPstDurabilityProven','ProductionReady')
    if ($Decision -isnot [pscustomobject] -or
        @($Decision.PSObject.Properties.Name).Count -ne $exact.Count) {
        throw 'BW4i exact manual decision schema only.'
    }
    foreach($name in $exact) {
        if ($Decision.PSObject.Properties.Name -cnotcontains $name) {
            throw ('BW4i manual decision missing '+$name)
        }
    }
    foreach($key in @('TestId','RunId','OriginalJournalSha256','SourceEntryId',
        'DestinationEntryId','InternetMessageId','SourceEvidenceSha256',
        'MoveClaimSha256','OriginalCompositeSha256')) {
        if ([string]$Decision.$key -cne [string]$p.$key) {
            throw ('BW4i manual decision pinned '+$key+' differs.')
        }
    }
    if ([string]$Decision.Schema -cne '2.6.5-BW4i.ExactFixtureManualSizeDecision.1' -or
        [string]$Decision.OperatorDecision -cne 'AcknowledgeExactDisposableMAPIMessageSizeDriftOnly' -or
        [long]$Decision.SourceSize -ne $p.SourceSize -or
        [long]$Decision.DestinationSize -ne $p.DestinationSize -or
        [long]$Decision.DestinationMinusSourceSize -ne $p.SizeDelta) {
        throw 'BW4i manual decision not exact +38B fixture acknowledgment.'
    }
    foreach($field in @('SubjectMatches','SenderEmailAddressMatches','BodyMatches',
        'ReceivedUtcTicksMatches')) {
        if ($Decision.$field -isnot [bool] -or -not $Decision.$field) {
            throw ('BW4i manual decision requires original equal '+$field)
        }
    }
    foreach($field in @('AutomaticRetryAllowed','OriginalJournalWriteAllowed',
        'CanDispatchProductionWorker','FullMAPIByteEqualityProven',
        'PhysicalPstDurabilityProven','ProductionReady')) {
        if ($Decision.$field -isnot [bool] -or $Decision.$field) {
            throw ('BW4i manual decision cannot elevate '+$field)
        }
    }
    $dt=[datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Decision.DecisionUtc,[ref]$dt)) {
        throw 'BW4i decision UTC invalid.'
    }
    return $true
}
function Write-OPA265BW4iDecisionOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Decision,
          [Parameter(Mandatory=$true)][string]$DecisionPath)
    [void](Assert-OPA265BW4iDecision -Decision $Decision)
    $p=Get-OPA265BW4iPins
    $expected=Get-OPA265BW4iDecisionPath -TestId $p.TestId
    if (-not [string]::Equals([IO.Path]::GetFullPath($DecisionPath),
            [IO.Path]::GetFullPath($expected),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'BW4i decision path cannot be redirected.'
    }
    $dir=[IO.Path]::GetDirectoryName($expected)
    if (-not [IO.Directory]::Exists($dir)) {[void][IO.Directory]::CreateDirectory($dir)}
    if (([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW4i refuses reparse point evidence directory.'
    }
    $encoding=New-Object Text.UTF8Encoding($true)
    $bytes=$encoding.GetBytes((ConvertTo-Json -InputObject $Decision -Depth 4))
    $bom=$encoding.GetPreamble()
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($expected,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bom,0,$bom.Length)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {if ($null -ne $stream) {$stream.Dispose()}}
    return $expected
}
