#requires -Version 5.1
# BW4k7e: standalone immutable original recipient/user-state SHA snapshot.
# Strictly source-only: never authorizes Move, retry, source rebaseline or production.
. (Join-Path $PSScriptRoot 'BW4k7dRecipientFlagWitness265.ps1')

function Get-OPA265BW4k7eSnapshotPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SuiteId,
        [Parameter(Mandatory=$true)][string]$TestId,
        [string]$LocalAppData=$env:LOCALAPPDATA
    )
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       [string]::IsNullOrWhiteSpace($LocalAppData) -or
       -not [IO.Path]::IsPathRooted($LocalAppData) -or
       $LocalAppData.StartsWith('\',[StringComparison]::Ordinal)){
        throw 'BW4k7e exact original fixture and local AppData required.'
    }
    Join-Path (Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k7e-SemanticSnapshots') ('suite-'+$SuiteId)) ('fixture-'+$TestId+'.json')
}

function Assert-OPA265BW4k7eExactReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Review)
    $schema='2.6.5-BW4k7d.IndependentRecipientFlagsSourceReadOnly.1'
    if([string]$Review.Schema -cne $schema -or
       [string]$Review.Status -cne 'ExactAttachment1KRecipientsAndUserStateDoubleReadVerifiedNoMove' -or
       [string]$Review.SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       [string]$Review.TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       [string]$Review.OriginalSourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35A46D3C00' -or
       [string]$Review.VerifiedDecisionSha256 -cne '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6' -or
       [int]$Review.RecipientCount -ne 1 -or
       [int]$Review.ToCount -ne 1 -or [int]$Review.CcCount -ne 0 -or
       [int]$Review.BccCount -ne 0 -or
       [string]$Review.RecipientDigestSha256 -cne '11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024' -or
       [string]$Review.UserStateDigestSha256 -cne '2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f' -or
       $Review.UnRead -isnot [bool] -or $Review.UnRead -or
       [int]$Review.MapiFlags -ne 65555 -or
       [int]$Review.SemanticReadAndAttachMask -ne 17 -or
       [int]$Review.SourceAttachmentCount -ne 1 -or
       [int]$Review.IndependentReadOnlyWitnesses -ne 2){
        throw 'BW4k7e original, independently observed recipient/state evidence has changed.'
    }
    foreach($field in @('OriginalThreeMoveClaimsUnchanged')){
        if($Review.$field -isnot [bool] -or -not $Review.$field){
            throw ('BW4k7e immutable prior chain mismatch: '+$field)
        }
    }
    foreach($field in @('RawRecipientAddressesExposed','SourceSemanticSnapshotPersisted',
        'FuturePostMoveContentVerified','FullProductionSignificantFlagMaskProven',
        'OutlookMoveExecuted','AttemptClaimWritten','WriterPermit','CanRetryMove','ProductionReady')){
        if($Review.$field -isnot [bool] -or $Review.$field){
            throw ('BW4k7e forbidden prior-proof elevation: '+$field)
        }
    }
    return $true
}

function New-OPA265BW4k7eSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Review)
    [void](Assert-OPA265BW4k7eExactReview -Review $Review)
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7e.ImmutableRecipientStateSourceSnapshot.1'
        Status='ExactSourceRecipientStateSnapshotRecordedNoMove'
        SuiteId=[string]$Review.SuiteId
        TestId=[string]$Review.TestId
        OriginalSourceEntryId=[string]$Review.OriginalSourceEntryId
        OriginalBW4k7cDecisionSha256=[string]$Review.VerifiedDecisionSha256
        OriginalBW4jAttachmentEvidenceSha256='0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0'
        OriginalAttachmentByteSha256='8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'
        RecipientCount=[int]$Review.RecipientCount
        ToCount=[int]$Review.ToCount
        CcCount=[int]$Review.CcCount
        BccCount=[int]$Review.BccCount
        RecipientDigestSha256=[string]$Review.RecipientDigestSha256
        UserStateDigestSha256=[string]$Review.UserStateDigestSha256
        UnRead=[bool]$Review.UnRead
        MapiFlags=[int]$Review.MapiFlags
        SignificantReadAndAttachMask=[int]$Review.SemanticReadAndAttachMask
        SourceAttachmentCount=[int]$Review.SourceAttachmentCount
        IndependentReadOnlyWitnesses=2
        CapturedUtc=[DateTime]::UtcNow.ToString('o')
        RawRecipientAddressesPersisted=$false
        PreviousThreeClaimsUnchanged=$true
        PreMoveRecipientStateEvidenceCaptured=$true
        FullProductionSemanticFlagCoverageProven=$false
        PostMoveRecipientComparisonProven=$false
        SourceContentRebaselineAllowed=$false
        WriterPermit=$false
        OutlookMoveExecuted=$false
        AttemptClaimWritten=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}

function Assert-OPA265BW4k7eSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Snapshot,
        [Parameter(Mandatory=$true)][psobject]$Review
    )
    [void](Assert-OPA265BW4k7eExactReview -Review $Review)
    $fields=@('Schema','Status','SuiteId','TestId','OriginalSourceEntryId',
        'OriginalBW4k7cDecisionSha256','OriginalBW4jAttachmentEvidenceSha256',
        'OriginalAttachmentByteSha256','RecipientCount','ToCount','CcCount','BccCount',
        'RecipientDigestSha256','UserStateDigestSha256','UnRead','MapiFlags',
        'SignificantReadAndAttachMask','SourceAttachmentCount','IndependentReadOnlyWitnesses',
        'CapturedUtc','RawRecipientAddressesPersisted','PreviousThreeClaimsUnchanged',
        'PreMoveRecipientStateEvidenceCaptured','FullProductionSemanticFlagCoverageProven',
        'PostMoveRecipientComparisonProven','SourceContentRebaselineAllowed',
        'WriterPermit','OutlookMoveExecuted','AttemptClaimWritten',
        'AutomaticRetryAllowed','ProductionReady')
    if(@($Snapshot.PSObject.Properties.Name).Count -ne $fields.Count){
        throw 'BW4k7e immutable snapshot schema has extra/missing fields.'
    }
    foreach($field in $fields){
        if($Snapshot.PSObject.Properties.Name -cnotcontains $field){
            throw ('BW4k7e immutable snapshot missing '+$field)
        }
    }
    $checks=@{
        Schema='2.6.5-BW4k7e.ImmutableRecipientStateSourceSnapshot.1'
        Status='ExactSourceRecipientStateSnapshotRecordedNoMove'
        SuiteId=[string]$Review.SuiteId
        TestId=[string]$Review.TestId
        OriginalSourceEntryId=[string]$Review.OriginalSourceEntryId
        OriginalBW4k7cDecisionSha256=[string]$Review.VerifiedDecisionSha256
        OriginalBW4jAttachmentEvidenceSha256='0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0'
        OriginalAttachmentByteSha256='8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'
        RecipientCount=[string][int]$Review.RecipientCount
        ToCount=[string][int]$Review.ToCount
        CcCount=[string][int]$Review.CcCount
        BccCount=[string][int]$Review.BccCount
        RecipientDigestSha256=[string]$Review.RecipientDigestSha256
        UserStateDigestSha256=[string]$Review.UserStateDigestSha256
        UnRead=[string][bool]$Review.UnRead
        MapiFlags=[string][int]$Review.MapiFlags
        SignificantReadAndAttachMask=[string][int]$Review.SemanticReadAndAttachMask
        SourceAttachmentCount=[string][int]$Review.SourceAttachmentCount
        IndependentReadOnlyWitnesses='2'
    }
    foreach($p in $checks.Keys){
        if([string]$Snapshot.$p -cne [string]$checks[$p]){
            throw ('BW4k7e immutable record pin changed: '+$p)
        }
    }
    $when=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Snapshot.CapturedUtc,[ref]$when)){
        throw 'BW4k7e source snapshot timestamp invalid.'
    }
    foreach($field in @('PreviousThreeClaimsUnchanged','PreMoveRecipientStateEvidenceCaptured')){
        if($Snapshot.$field -isnot [bool] -or -not $Snapshot.$field){
            throw ('BW4k7e positive proof field invalid: '+$field)
        }
    }
    foreach($field in @('RawRecipientAddressesPersisted','FullProductionSemanticFlagCoverageProven',
        'PostMoveRecipientComparisonProven','SourceContentRebaselineAllowed',
        'WriterPermit','OutlookMoveExecuted','AttemptClaimWritten',
        'AutomaticRetryAllowed','ProductionReady')){
        if($Snapshot.$field -isnot [bool] -or $Snapshot.$field){
            throw ('BW4k7e unauthorized snapshot elevation: '+$field)
        }
    }
    return $true
}

function Write-OPA265BW4k7eSnapshotOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Snapshot,
        [Parameter(Mandatory=$true)][psobject]$Review,
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$LocalAppData=$env:LOCALAPPDATA
    )
    [void](Assert-OPA265BW4k7eSnapshot -Snapshot $Snapshot -Review $Review)
    $expected=Get-OPA265BW4k7eSnapshotPath -SuiteId $Review.SuiteId -TestId $Review.TestId -LocalAppData $LocalAppData
    if(-not [string]::Equals([IO.Path]::GetFullPath($Path),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k7e snapshot path cannot be redirected.'
    }
    $parent=[IO.Path]::GetDirectoryName($expected)
    $root=[IO.Path]::GetDirectoryName($parent)
    if(-not [IO.Directory]::Exists($root)){[void][IO.Directory]::CreateDirectory($root)}
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7e root symlink/reparse point forbidden.'
    }
    if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
    if(([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7e parent symlink/reparse point forbidden.'
    }
    $utf8=New-Object Text.UTF8Encoding($true)
    $json=ConvertTo-Json -InputObject $Snapshot -Depth 5
    $bytes=$utf8.GetBytes($json)
    if($bytes.Length -gt 16384){throw 'BW4k7e bounded snapshot JSON too large.'}
    $bom=$utf8.GetPreamble()
    $fs=$null
    try{
        $fs=New-Object IO.FileStream($expected,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $fs.Write($bom,0,$bom.Length)
        $fs.Write($bytes,0,$bytes.Length)
        $fs.Flush($true)
    }finally{if($null -ne $fs){$fs.Dispose()}}
    [pscustomobject][ordered]@{
        SnapshotPath=$expected
        SnapshotSha256=(Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Read-OPA265BW4k7eSnapshotVerified {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Review,
        [Parameter(Mandatory=$true)][string]$ExpectedSnapshotSha256,
        [string]$LocalAppData=$env:LOCALAPPDATA
    )
    [void](Assert-OPA265BW4k7eExactReview -Review $Review)
    $path=Get-OPA265BW4k7eSnapshotPath -SuiteId $Review.SuiteId -TestId $Review.TestId -LocalAppData $LocalAppData
    if($ExpectedSnapshotSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [IO.File]::Exists($path) -or
       (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $path -Force).Length -gt 16384 -or
       (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSnapshotSha256){
        throw 'BW4k7e snapshot missing or immutable SHA256 changed.'
    }
    $data=Get-Content -LiteralPath $path -Encoding UTF8 -Raw | ConvertFrom-Json
    [void](Assert-OPA265BW4k7eSnapshot -Snapshot $data -Review $Review)
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7e.IndependentSourceSnapshotVerify.1'
        Status='OriginalRecipientStateSnapshotVerifiedNoWriterPermit'
        SnapshotPath=$path;SnapshotSha256=$ExpectedSnapshotSha256
        RecipientDigestSha256=[string]$data.RecipientDigestSha256
        UserStateDigestSha256=[string]$data.UserStateDigestSha256
        WriterPermit=$false;OutlookMoveExecuted=$false;ProductionReady=$false
    }
}
