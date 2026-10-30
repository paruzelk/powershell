#requires -Version 5.1
# BW4h1 pure read-only field-level diagnostic of historical BW4c fingerprint.
# NEVER accept altered fields as data equality or authorize another MailItem.Move.
function Get-OPA265BW4h1ContentHash {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Subject,
        [AllowEmptyString()][string]$SenderEmailAddress,
        [AllowEmptyString()][string]$Body,
        [Parameter(Mandatory=$true)][long]$Size,
        [Parameter(Mandatory=$true)][long]$ReceivedUtcTicks
    )
    if ($Size -lt 1 -or $ReceivedUtcTicks -lt 1 -or
        $Subject.Length -gt 32768 -or $SenderEmailAddress.Length -gt 4096 -or
        $Body.Length -gt 4194304) {
        throw 'BW4h1 invalid or unbounded original BW4c fingerprint fields.'
    }
    $buffer=New-Object Text.StringBuilder
    foreach($value in @(
        $Subject,$SenderEmailAddress,$Body,
        $Size.ToString([Globalization.CultureInfo]::InvariantCulture),
        $ReceivedUtcTicks.ToString([Globalization.CultureInfo]::InvariantCulture)
    )) {
        [void]$buffer.Append(([string]$value).Length.ToString([Globalization.CultureInfo]::InvariantCulture))
        [void]$buffer.Append(':')
        [void]$buffer.Append([string]$value)
    }
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($buffer.ToString()))
        ).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function Get-OPA265BW4h1FieldDigest {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
        ).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function Get-OPA265BW4h1SizeOnlyHypotheses {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Subject,
        [AllowEmptyString()][string]$SenderEmailAddress,
        [AllowEmptyString()][string]$Body,
        [Parameter(Mandatory=$true)][long]$ObservedSize,
        [Parameter(Mandatory=$true)][long]$ReceivedUtcTicks,
        [Parameter(Mandatory=$true)][string]$ExpectedOriginalHash,
        [ValidateRange(1,4096)][int]$MaxSizeDelta=256
    )
    if ($ExpectedOriginalHash -cnotmatch '^[a-f0-9]{64}$' -or
        $ObservedSize -lt 1 -or $ReceivedUtcTicks -lt 1) {
        throw 'BW4h1 size-only diagnostic requires exact original SHA256 and valid size.'
    }
    $current=Get-OPA265BW4h1ContentHash -Subject $Subject -SenderEmailAddress $SenderEmailAddress -Body $Body -Size $ObservedSize -ReceivedUtcTicks $ReceivedUtcTicks
    $matches=New-Object 'System.Collections.Generic.List[long]'
    if ($current -cne $ExpectedOriginalHash) {
        for($delta=1;$delta -le $MaxSizeDelta;$delta++){
            foreach($candidateSize in @(([long]$ObservedSize-$delta),([long]$ObservedSize+$delta))) {
                if ($candidateSize -lt 1) { continue }
                $probe=Get-OPA265BW4h1ContentHash -Subject $Subject -SenderEmailAddress $SenderEmailAddress -Body $Body -Size $candidateSize -ReceivedUtcTicks $ReceivedUtcTicks
                if ($probe -ceq $ExpectedOriginalHash) { $matches.Add([long]$candidateSize) }
            }
        }
    }
    $state=if($current -ceq $ExpectedOriginalHash) {
        'NoCompositeFingerprintDrift'
    } elseif($matches.Count -eq 1) {
        'CompositeHashReconstructedBySizeOnlyHypothesis'
    } elseif($matches.Count -gt 1) {
        'AmbiguousSizeOnlyMatches'
    } else {
        'CompositeDriftNotExplainedBySizeOnlyWithinBound'
    }
    $inferred=$null;$sizeDelta=$null
    if ($matches.Count -eq 1){
        $inferred=[long]$matches[0]
        $sizeDelta=[long]$ObservedSize-[long]$matches[0]
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4h1.SizeOnlyHypothesisReadOnly.1'
        Status=$state
        OriginalContentFingerprintSha256=$ExpectedOriginalHash
        RecomputedDestinationContentFingerprintSha256=$current
        ObservedDestinationSize=$ObservedSize
        InferredOriginalSize=$inferred
        DestinationMinusInferredSourceSize=$sizeDelta
        SizeSearchDeltaBound=$MaxSizeDelta
        SizeOnlyMatches=$matches.Count
        OtherFourFieldsProvenIndependentlyEqual=$false
        FullMAPIByteEqualityProven=$false
        OriginalMailItemMoveMayBeRetried=$false
        HistoricalJournalWriteAuthorized=$false
        ProductionReady=$false
    }
}
