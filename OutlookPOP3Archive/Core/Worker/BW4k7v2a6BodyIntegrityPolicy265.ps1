#requires -Version 5.1
# BW4k7v2a6 pure synthetic text fingerprints, no Outlook, disk, or mailbox access.
# NEVER return observed Body, HTML or any substring: possible IMAP signature/data.
function Get-OPA265BW4k7v2a6BodyEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ExpectedBody,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ObservedBody
    )
    $enc=[Text.Encoding]::UTF8
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $expectedBytes=$enc.GetBytes($ExpectedBody)
        $actualBytes=$enc.GetBytes($ObservedBody)
        $expectedHash=[BitConverter]::ToString(
            $sha.ComputeHash($expectedBytes)).Replace('-','').ToLowerInvariant()
        $observedHash=[BitConverter]::ToString(
            $sha.ComputeHash($actualBytes)).Replace('-','').ToLowerInvariant()
    }finally{$sha.Dispose()}
    $exact=[string]::Equals($ExpectedBody,$ObservedBody,
        [StringComparison]::Ordinal)
    $expectedNormal=$ExpectedBody.Replace(([char]13).ToString()+([char]10).ToString(),
        ([char]10).ToString()).Replace(([char]13).ToString(),([char]10).ToString())
    $actualNormal=$ObservedBody.Replace(([char]13).ToString()+([char]10).ToString(),
        ([char]10).ToString()).Replace(([char]13).ToString(),([char]10).ToString())
    $lineEndingOnly=([string]::Equals($expectedNormal,$actualNormal,
        [StringComparison]::Ordinal) -and -not $exact)
    $trimChars=[char[]]@([char]32,[char]9,[char]13,[char]10)
    $trailingWhitespaceOnly=(-not $exact -and
        [string]::Equals($ExpectedBody.TrimEnd($trimChars),
            $ObservedBody.TrimEnd($trimChars),[StringComparison]::Ordinal))
    $observedHasExpectedPrefix=$ObservedBody.StartsWith($ExpectedBody,
        [StringComparison]::Ordinal)
    $expectedHasObservedPrefix=$ExpectedBody.StartsWith($ObservedBody,
        [StringComparison]::Ordinal)
    $class='UnexpectedBodyMismatch'
    if($exact){$class='ExactBodyMatch'}
    elseif($lineEndingOnly){$class='LineEndingOnlyDifferenceUnaccepted'}
    elseif($trailingWhitespaceOnly){$class='TrailingWhitespaceOnlyDifferenceUnaccepted'}
    elseif($observedHasExpectedPrefix){$class='NonWhitespaceSuffixAddedUnaccepted'}
    elseif($expectedHasObservedPrefix){$class='ExpectedBodyTruncatedUnaccepted'}
    $prefix=0
    $max=[Math]::Min($ExpectedBody.Length,$ObservedBody.Length)
    while($prefix -lt $max -and $ExpectedBody[$prefix] -ceq $ObservedBody[$prefix]){
        $prefix++
    }
    $expectedCrLf=[regex]::Matches($ExpectedBody,'\r\n').Count
    $actualCrLf=[regex]::Matches($ObservedBody,'\r\n').Count
    $expectedBareLf=[regex]::Matches($ExpectedBody,'(?<!\r)\n').Count
    $actualBareLf=[regex]::Matches($ObservedBody,'(?<!\r)\n').Count
    $expectedBareCr=[regex]::Matches($ExpectedBody,'\r(?!\n)').Count
    $actualBareCr=[regex]::Matches($ObservedBody,'\r(?!\n)').Count
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a6.BodyEvidence.1'
        Status=$class
        BodyMatchesExactly=$exact
        OriginalExpectedUtf8Sha256=$expectedHash
        ActualObservedUtf8Sha256=$observedHash
        ExpectedUtf16CodeUnits=$ExpectedBody.Length
        ObservedUtf16CodeUnits=$ObservedBody.Length
        ExpectedUtf8ByteCount=$expectedBytes.Length
        ObservedUtf8ByteCount=$actualBytes.Length
        ExpectedCrLfCount=$expectedCrLf
        ObservedCrLfCount=$actualCrLf
        ExpectedBareLfCount=$expectedBareLf
        ObservedBareLfCount=$actualBareLf
        ExpectedBareCrCount=$expectedBareCr
        ObservedBareCrCount=$actualBareCr
        NormalizedLineEndingsWouldMatch=$lineEndingOnly
        TrimmingTrailingWhitespaceWouldMatch=$trailingWhitespaceOnly
        ObservedStartsWithExpected=$observedHasExpectedPrefix
        ExpectedStartsWithObserved=$expectedHasObservedPrefix
        CommonPrefixUtf16CodeUnits=$prefix
        BodyNormalizationOrDifferenceAccepted=$false
        AnyRawBodyOrSuffixTextReturned=$false
        MoveAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Test-OPA265BW4k7v2a6FreshBodyRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$InitialEvidence,
        [Parameter(Mandatory=$true)][object]$IndependentEvidence,
        [bool]$OneExactSyntheticCandidate,
        [bool]$ParentStoreAndFolderSame,
        [bool]$EntryIdAndSubjectSame
    )
    foreach($e in @($InitialEvidence,$IndependentEvidence)){
        if($null -eq $e -or
           [string]$e.Schema -cne '2.6.5-BW4k7v2a6.BodyEvidence.1' -or
           [string]$e.ActualObservedUtf8Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [string]$e.OriginalExpectedUtf8Sha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'BW4k7v2a6 malformed body read evidence.'
        }
    }
    $bothReadsStable=([string]$InitialEvidence.ActualObservedUtf8Sha256 -ceq
        [string]$IndependentEvidence.ActualObservedUtf8Sha256 -and
        [int]$InitialEvidence.ObservedUtf16CodeUnits -eq
        [int]$IndependentEvidence.ObservedUtf16CodeUnits)
    $match=([bool]$InitialEvidence.BodyMatchesExactly -and
        [bool]$IndependentEvidence.BodyMatchesExactly)
    $status='BodyMismatchBlocksMoveAndRequiresManualReview'
    if(-not $OneExactSyntheticCandidate -or -not $ParentStoreAndFolderSame -or
       -not $EntryIdAndSubjectSame){
        $status='AmbiguousOrMisroutedSyntheticSourceNoMove'
    }elseif(-not $bothReadsStable){
        $status='SyntheticBodyChangedBetweenReadbacksNoMove'
    }elseif($match){
        $status='CurrentExactBodyStableButOriginalFailedSaveGateUnprovenNoMove'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a6.FreshBodyReadAssessment.1'
        Status=$status
        OneExactSyntheticCandidate=$OneExactSyntheticCandidate
        ParentStoreAndFolderSame=$ParentStoreAndFolderSame
        EntryIdAndSubjectSame=$EntryIdAndSubjectSame
        BothReadbacksSameBodyFingerprint=$bothReadsStable
        BothReadbacksExactExpectedBody=$match
        ExactOriginalPostSavePredicateHistoricallyProven=$false
        RawMapiFlagsWaived=$false
        ExistingSuiteMoveAllowed=$false
        OriginalCreatePilotMayBeRetried=$false
        OriginalMovePilotMayBeInvoked=$false
        WriterPermit=$false;ProductionReady=$false
    }
}