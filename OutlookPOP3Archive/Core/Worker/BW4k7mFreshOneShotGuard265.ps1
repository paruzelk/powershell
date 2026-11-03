#requires -Version 5.1
# BW4k7m: ONLY the new BW4k7l disposable Attachment1K witness.
# Claim-before-one-Move, absolute no-retry, no production archive integration.
. (Join-Path $PSScriptRoot 'BW4k7lFreshPreMoveMapiWitness265.ps1')

function Get-OPA265BW4k7mPins {
    [CmdletBinding()]
    param()
    return [pscustomobject][ordered]@{
        FixtureId='d1a68868-acf5-4c70-860d-5521e1ce2836'
        EvidenceSha256='36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29'
        SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A3504B03C00'
        DestinationFolderEntryId='00000000E88584FF275FEE45B531E472CF338A8A82800000'
        AttachmentBytesSha256='2bce1ba628720664be4b9fdd77aae0678e5f0f3f02fc6ff641ec879094f6a404'
        RecipientDigestSha256='11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024'
        InternetMessageIdSha256='77762cb8a7eb97f398920f228e30061e9a8bb35c4047a201d79ff0ec773df3de'
        OldBW4k7gClaimSha256='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        OldBW4k7iBaselineSha256='f75594047529cca19bbeb8d2a52db5412187325a39db4d659dc85b4b41d44399'
    }
}
function Get-OPA265BW4k7mClaimPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$FixtureId)
    $pins=Get-OPA265BW4k7mPins
    if($FixtureId -cne [string]$pins.FixtureId){throw 'BW4k7m only the exact sealed new fixture is eligible.'}
    if([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)){
        throw 'BW4k7m LOCALAPPDATA unavailable.'
    }
    return (Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4k7m-OneShotClaims') ('fixture-'+$FixtureId+'.json'))
}
function Assert-OPA265BW4k7mNeverAttempted {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$FixtureId)
    $pins=Get-OPA265BW4k7mPins
    if($FixtureId -cne [string]$pins.FixtureId){throw 'BW4k7m fixture identity mismatch.'}
    $paths=@(
        (Get-OPA265BW4k7mClaimPath -FixtureId $FixtureId),
        (Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$FixtureId+'.json')),
        (Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4k1-Claims') ('fixture-'+$FixtureId+'.json'))
    )
    foreach($p in $paths){
        if([IO.File]::Exists($p)){throw 'BW4k7m irreversible attempt Claim already exists. NEVER RETRY. Independent audit only.'}
    }
    return $true
}
function Read-OPA265BW4k7mSealedEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$FixtureId,
          [Parameter(Mandatory=$true)][string]$ExpectedEvidenceSha256)
    $pins=Get-OPA265BW4k7mPins
    if($FixtureId -cne [string]$pins.FixtureId -or
       $ExpectedEvidenceSha256 -cne [string]$pins.EvidenceSha256){
        throw 'BW4k7m exact sealed fixture/immutable SHA256 operator pins mismatch.'
    }
    $path=Get-OPA265BW4k7lEvidencePath -FixtureId $FixtureId
    if(-not [IO.File]::Exists($path) -or
       (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'BW4k7m original BW4k7l evidence missing or reparse point.'
    }
    if((Get-Item -LiteralPath $path).Length -gt 32768){
        throw 'BW4k7m evidence file exceeds fixed size bound.'
    }
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($hash -cne [string]$pins.EvidenceSha256){throw 'BW4k7m immutable evidence SHA256 differs. STOP.'}
    $record=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4k7mEvidence -Evidence $record)
    return [pscustomobject][ordered]@{Path=$path;Sha256=$hash;Record=$record}
}
function Assert-OPA265BW4k7mEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Evidence)
    $pins=Get-OPA265BW4k7mPins
    $w=$Evidence.SourceWitness
    if($null -eq $w -or
       [string]$Evidence.Schema -cne '2.6.5-BW4k7l.ImmutablePreMoveEvidence.1' -or
       [string]$Evidence.FixtureId -cne [string]$pins.FixtureId -or
       [string]$Evidence.OutlookProfile -cne 'Outlook' -or
       [string]$Evidence.DestinationFolderEntryId -cne [string]$pins.DestinationFolderEntryId -or
       [int]$Evidence.DestinationFolderItems -ne 0 -or
       [int]$Evidence.IndependentSourceReads -ne 2 -or
       [bool]$Evidence.Original0x00010000MeaningEstablished -or
       [bool]$Evidence.OriginalBW4k7gFlagMismatchWaived -or
       [bool]$Evidence.OutlookMoveExecuted -or
       [bool]$Evidence.AutomaticRetryAllowed -or
       [bool]$Evidence.WriterPermit -or
       [bool]$Evidence.ProductionReady -or
       [string]$Evidence.PriorBW4k7gClaimMustRemainUntouched -cne [string]$pins.OldBW4k7gClaimSha256 -or
       [string]$w.Schema -cne '2.6.5-BW4k7l.FreshPreMoveMapiWitness.1' -or
       [string]$w.FixtureId -cne [string]$pins.FixtureId -or
       [string]$w.SourceEntryId -cne [string]$pins.SourceEntryId -or
       [string]$w.InternetMessageIdSha256 -cne [string]$pins.InternetMessageIdSha256 -or
       [string]$w.RecipientDigestSha256 -cne [string]$pins.RecipientDigestSha256 -or
       [string]$w.AttachmentBytesSha256 -cne [string]$pins.AttachmentBytesSha256 -or
       [int]$w.AttachmentByteLength -ne 1024 -or
       [int]$w.AttachmentCount -ne 1 -or
       [int]$w.RawPrMessageFlags -ne 65555 -or
       [string]$w.RawPrMessageFlagsHex -cne '0x00010013' -or
       -not [bool]$w.RawFlag0x00010000BeforeMove -or
       -not [bool]$w.PrMessageStatusAvailable -or
       [int]$w.PrMessageStatus -ne 0 -or
       -not [bool]$w.PrHasAttach -or
       [bool]$w.UnRead -or
       -not [bool]$w.BeforeMove -or
       [bool]$w.OutlookMoveExecuted -or
       [bool]$w.WriterPermit -or
       [bool]$w.ProductionReady){
        throw 'BW4k7m sealed evidence violates exact fixture, original MAPI or no-legacy-waiver pins.'
    }
    if([string]::IsNullOrWhiteSpace([string]$Evidence.SourcePst) -or
       [string]::IsNullOrWhiteSpace([string]$Evidence.DestinationPst) -or
       [string]::IsNullOrWhiteSpace([string]$w.SourceFolderEntryId) -or
       [string]::IsNullOrWhiteSpace([string]$w.SearchKeySha256) -or
       [string]::IsNullOrWhiteSpace([string]$w.InternetMessageId) -or
       [string]::IsNullOrWhiteSpace([string]$w.SourceStoreIdSha256) -or
       [string]::IsNullOrWhiteSpace([string]$Evidence.DestinationStoreIdSha256)){
        throw 'BW4k7m sealed evidence missing mandatory identity fields.'
    }
    if([string]$w.InternetMessageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$' -or
       [string]$w.InternetMessageId -match '[\x00-\x1f]' -or
       [string]$w.InternetMessageIdSha256 -cne (Get-OPA265BW4k7lStringSha -Value ([string]$w.InternetMessageId))){
        throw 'BW4k7m unsafe or mismatching original InternetMessageId for exact DASL Restrict.'
    }
    return $true
}
function Assert-OPA265BW4k7mSourceEqualsSealed {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Original,
          [Parameter(Mandatory=$true)][psobject]$Live)
    if([string]$Original.Schema -cne '2.6.5-BW4k7l.FreshPreMoveMapiWitness.1' -or
       [string]$Live.Schema -cne [string]$Original.Schema){
        throw 'BW4k7m pre-Move witness schema mismatch.'
    }
    $names=@($Original.PSObject.Properties.Name)
    if($names.Count -ne @($Live.PSObject.Properties.Name).Count){
        throw 'BW4k7m pre-Move original vs live property count mismatch.'
    }
    foreach($name in $names){
        if($Live.PSObject.Properties.Name -cnotcontains $name -or
           [string]$Original.$name -cne [string]$Live.$name){
            throw ('BW4k7m sealed vs live source drift: '+$name+'. STOP: no Move.')
        }
    }
    return $true
}
function New-OPA265BW4k7mAttemptClaim {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Evidence,
          [Parameter(Mandatory=$true)][string]$EvidenceSha256)
    [void](Assert-OPA265BW4k7mEvidence -Evidence $Evidence)
    $pins=Get-OPA265BW4k7mPins
    if($EvidenceSha256 -cne [string]$pins.EvidenceSha256){throw 'BW4k7m cannot claim unsealed evidence.'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7m.OneIrreversibleFreshAttachment1KClaim.1'
        FixtureId=[string]$pins.FixtureId
        EvidenceSha256=$EvidenceSha256
        SourceEntryId=[string]$pins.SourceEntryId
        SourceFolderEntryId=[string]$Evidence.SourceWitness.SourceFolderEntryId
        SourceStoreIdSha256=[string]$Evidence.SourceWitness.SourceStoreIdSha256
        DestinationFolderEntryId=[string]$pins.DestinationFolderEntryId
        DestinationStoreIdSha256=[string]$Evidence.DestinationStoreIdSha256
        SourcePst=[string]$Evidence.SourcePst
        DestinationPst=[string]$Evidence.DestinationPst
        InternetMessageId=[string]$Evidence.SourceWitness.InternetMessageId
        OriginalRawPrMessageFlags=65555
        OriginalRawPrMessageStatus=0
        OriginalAttachmentBytesSha256=[string]$pins.AttachmentBytesSha256
        OriginalRecipientDigestSha256=[string]$pins.RecipientDigestSha256
        PriorHistoricBW4k7gClaimUnmodifiedSha256=[string]$pins.OldBW4k7gClaimSha256
        AttemptUtc=[datetime]::UtcNow.ToString('o')
        OneIrreversibleMoveAttemptClaimed=$true
        AllowAutomaticRetry=$false
        AllowJournalWrite=$false
        HistoricalFlagMismatchWaived=$false
        ProductionReady=$false
    }
}
function Write-OPA265BW4k7mClaimOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Claim)
    $pins=Get-OPA265BW4k7mPins
    if([string]$Claim.Schema -cne '2.6.5-BW4k7m.OneIrreversibleFreshAttachment1KClaim.1' -or
       [string]$Claim.FixtureId -cne [string]$pins.FixtureId -or
       [string]$Claim.EvidenceSha256 -cne [string]$pins.EvidenceSha256 -or
       [string]$Claim.SourceEntryId -cne [string]$pins.SourceEntryId -or
       [string]$Claim.DestinationFolderEntryId -cne [string]$pins.DestinationFolderEntryId -or
       -not [bool]$Claim.OneIrreversibleMoveAttemptClaimed -or
       [bool]$Claim.AllowAutomaticRetry -or
       [bool]$Claim.AllowJournalWrite -or
       [bool]$Claim.HistoricalFlagMismatchWaived -or
       [bool]$Claim.ProductionReady){
        throw 'BW4k7m forged or incomplete irreversible claim.'
    }
    $path=Get-OPA265BW4k7mClaimPath -FixtureId $Claim.FixtureId
    [void](Assert-OPA265BW4k7mNeverAttempted -FixtureId $Claim.FixtureId)
    $dir=[IO.Path]::GetDirectoryName($path)
    if(-not [IO.Directory]::Exists($dir)){[void][IO.Directory]::CreateDirectory($dir)}
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7m claim folder is redirected; STOP.'
    }
    $json=ConvertTo-Json -InputObject $Claim -Depth 8 -Compress
    if($json.Length -gt 32768){throw 'BW4k7m claim exceeds fixed byte budget.'}
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($json+[char]10)
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    }finally{$stream.Dispose()}
    return [pscustomobject][ordered]@{
        ClaimPath=$path
        ClaimSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        IrreversibleClaimCreated=$true
    }
}
function Get-OPA265BW4k7mContentComparison {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Original,
          [Parameter(Mandatory=$true)][psobject]$Destination)
    if([string]$Original.Schema -cne '2.6.5-BW4k7l.FreshPreMoveMapiWitness.1' -or
       [string]$Destination.Schema -cne [string]$Original.Schema){
        throw 'BW4k7m post-Move witness schema mismatch.'
    }
    # Raw flags, PR_MESSAGE_STATUS and provider-computed Size are NOT silently waived.
    # They are reported individually; content evidence must match independently.
    $required=@(
        'FixtureId','InternetMessageId','InternetMessageIdSha256','SearchKeySha256',
        'SubjectSha256','BodySha256','HtmlBodySha256','SenderSha256',
        'ReceivedUtcTicks','SentUtcTicks','RecipientCount','RecipientDigestSha256',
        'PrHasAttach','UnRead','AttachmentCount','AttachmentNameSha256',
        'AttachmentByteLength','AttachmentBytesSha256'
    )
    $drifts=New-Object 'System.Collections.Generic.List[string]'
    foreach($field in $required){
        if($Original.PSObject.Properties.Name -cnotcontains $field -or
           $Destination.PSObject.Properties.Name -cnotcontains $field -or
           [string]$Original.$field -cne [string]$Destination.$field){
            $drifts.Add($field)
        }
    }
    $originalFlags=[int]$Original.RawPrMessageFlags
    $destFlags=[int]$Destination.RawPrMessageFlags
    $mask=($originalFlags -bxor $destFlags)
    $sourceStatus=$Original.PrMessageStatus
    $destStatus=$Destination.PrMessageStatus
    $statusComparable=([bool]$Original.PrMessageStatusAvailable -and [bool]$Destination.PrMessageStatusAvailable)
    $statusEqual=([bool]$Original.PrMessageStatusAvailable -eq [bool]$Destination.PrMessageStatusAvailable)
    if($statusEqual -and $statusComparable){
        $statusEqual=([int]$sourceStatus -eq [int]$destStatus)
    }
    $status=if($drifts.Count -ne 0){
        'ContentOrIdentityDriftNeedsManualReview'
    }elseif(-not $statusEqual){
        'SeparatePrMessageStatusDriftNeedsManualReview'
    }elseif($mask -ne 0){
        'ContentMatchRawPrMessageFlagsDriftUnclassifiedManualReview'
    }elseif([long]$Original.MessageSizeDiagnostic -ne [long]$Destination.MessageSizeDiagnostic){
        'ContentMatchProviderMessageSizeDriftNeedsManualReview'
    }else{
        'ContentAndObservedMapiPropertiesMatchReadOnlyNoProductionPermit'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7m.IndependentPostMoveContentComparison.1'
        Status=$status
        RequiredSemanticFieldCount=$required.Count
        SemanticFieldMismatchCount=$drifts.Count
        SemanticFieldMismatches=@($drifts.ToArray())
        FullSemanticContentMatch=($drifts.Count -eq 0)
        OriginalRawPrMessageFlags=$originalFlags
        DestinationRawPrMessageFlags=$destFlags
        ChangedMaskHex=('0x{0:X8}' -f $mask)
        Unresolved0x00010000Changed=(($mask -band 65536) -ne 0)
        OriginalPrMessageStatusAvailable=[bool]$Original.PrMessageStatusAvailable
        DestinationPrMessageStatusAvailable=[bool]$Destination.PrMessageStatusAvailable
        OriginalPrMessageStatus=$sourceStatus
        DestinationPrMessageStatus=$destStatus
        SeparatePrMessageStatusEqual=$statusEqual
        OriginalDiagnosticMessageSize=[long]$Original.MessageSizeDiagnostic
        DestinationDiagnosticMessageSize=[long]$Destination.MessageSizeDiagnostic
        ProviderMessageSizeDrift=([long]$Original.MessageSizeDiagnostic -ne [long]$Destination.MessageSizeDiagnostic)
        Historic0x00010000MeaningEstablished=$false
        HistoricalRawStateMismatchWaived=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
