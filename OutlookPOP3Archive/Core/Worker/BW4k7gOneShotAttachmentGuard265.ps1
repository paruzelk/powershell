#requires -Version 5.1
# BW4k7g: one exact disposable Attachment1K, claim-before-Move.
# Recognized BW4k1 claim path makes ALL legacy single-attempt paths fail closed.
. (Join-Path $PSScriptRoot 'BW4k7fEmptyTargetPreflight265.ps1')
. (Join-Path $PSScriptRoot 'BW4k1RealOneShotGuards265.ps1')

function Assert-OPA265BW4k7gPinnedSourceContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Original,
        [Parameter(Mandatory=$true)][psobject]$Current,
        [Parameter(Mandatory=$true)][psobject]$Case,
        [Parameter(Mandatory=$true)][string]$SuiteId
    )
    [void](Assert-OPA265BW4jWitness -Witness $Original -Case $Case -SuiteId $SuiteId)
    [void](Assert-OPA265BW4jWitness -Witness $Current -Case $Case -SuiteId $SuiteId)
    $fields=@('Schema','SuiteId','CaseName','TestId','ProfileName','EntryId','FolderEntryId',
        'StoreId','InternetMessageId','SearchKeySha256','SubjectUtf8Sha256',
        'SenderUtf8Sha256','BodyUtf8Sha256','HtmlBodyUtf8Sha256','SubjectLength',
        'BodyLength','HtmlBodyLength','ReceivedUtcTicks','OutlookMoveExecuted',
        'ProductionReady')
    foreach($name in $fields){
        if([string]$Original.$name -cne [string]$Current.$name){
            throw ('BW4k7g original source semantic field changed: '+$name)
        }
    }
    # Only the already-accepted exact +512 byte source provider Size drift is allowed.
    if([long]$Original.Size -ne 8122 -or [long]$Current.Size -ne 8634 -or
       ([long]$Current.Size - [long]$Original.Size) -ne 512){
        throw 'BW4k7g source Size differs from exact +512-only manual decision.'
    }
    $before=@($Original.Attachments);$after=@($Current.Attachments)
    if($before.Count -ne 1 -or $after.Count -ne 1){
        throw 'BW4k7g expected exactly one original by-value attachment.'
    }
    foreach($name in @('Index','FileName','ByteCount','Sha256')){
        if([string]$before[0].$name -cne [string]$after[0].$name){
            throw ('BW4k7g attachment payload/metadata differs: '+$name)
        }
    }
    if([long]$after[0].ByteCount -ne 1024 -or
       [string]$after[0].Sha256 -cne '8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'){
        throw 'BW4k7g original attachment SHA-256 or byte count not pinned.'
    }
    return $true
}

function Assert-OPA265BW4k7gLiveSemanticSource {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Witness)
    if([string]$Witness.Schema -cne '2.6.5-BW4k7d.RecipientsFlagsReadOnly.1' -or
       [string]$Witness.SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       [string]$Witness.TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       [string]$Witness.SourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35A46D3C00' -or
       [string]$Witness.RecipientDigestSha256 -cne '11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024' -or
       [string]$Witness.UserStateDigestSha256 -cne '2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f' -or
       [int]$Witness.RecipientCount -ne 1 -or [int]$Witness.ToCount -ne 1 -or
       [int]$Witness.CcCount -ne 0 -or [int]$Witness.BccCount -ne 0 -or
       [int]$Witness.MapiFlags -ne 65555 -or [int]$Witness.AttachmentCount -ne 1 -or
       $Witness.UnRead -isnot [bool] -or $Witness.UnRead){
        throw 'BW4k7g live source recipient or user-state witness no longer equals immutable original.'
    }
    foreach($flag in @('WriterPermit','OutlookMoveExecuted','ProductionReady')){
        if($Witness.$flag -isnot [bool] -or $Witness.$flag){
            throw 'BW4k7g source witness cannot claim Move/production.'
        }
    }
    return $true
}

function New-OPA265BW4k7gAttemptClaim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$DestinationPst,
        [Parameter(Mandatory=$true)][string]$SourceStoreId,
        [Parameter(Mandatory=$true)][string]$DestinationStoreId,
        [Parameter(Mandatory=$true)][string]$InternetMessageId
    )
    if([string]::IsNullOrWhiteSpace($SourceStoreId) -or
       [string]::IsNullOrWhiteSpace($DestinationStoreId) -or
       $SourceStoreId -ceq $DestinationStoreId -or
       -not [IO.Path]::IsPathRooted($SourcePst) -or
       -not [IO.Path]::IsPathRooted($DestinationPst) -or
       [string]::IsNullOrWhiteSpace($InternetMessageId)){
        throw 'BW4k7g invalid source/destination identity for immutable claim.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7g.OneIrreversibleAttachment1KMoveClaim.1'
        SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
        TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        CaseName='Attachment1K'
        SourcePst=[IO.Path]::GetFullPath($SourcePst)
        DestinationPst=[IO.Path]::GetFullPath($DestinationPst)
        SourceStoreIdSha256=(Get-OPA265BW4jTextHash -Value $SourceStoreId)
        DestinationStoreIdSha256=(Get-OPA265BW4jTextHash -Value $DestinationStoreId)
        SourceFolderEntryId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
        SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
        DestinationFolderEntryId='00000000D3E190022DF61241BBDE594AD46A661B82800000'
        InternetMessageId=$InternetMessageId
        OriginalSourceWitnessSha256='0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0'
        FiveEvidenceSetSha256='ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3'
        PlanSha256='6464f562eec08082d1db7781281e3cb0a4efd5264f1c2197ab9f14aedfb74f63'
        ManualSourceSizeDecisionSha256='29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6'
        ImmutableRecipientStateSnapshotSha256='fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
        AttachmentByteSha256='8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'
        ObservedSourceSize=8634
        OriginalSourceSize=8122
        AttemptUtc=[datetime]::UtcNow.ToString('o')
        RealOutlookOneShot=$true
        AutomaticRetryAllowed=$false
        HistoricalJournalWriteAllowed=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7gClaim {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Claim)
    $schema='2.6.5-BW4k7g.OneIrreversibleAttachment1KMoveClaim.1'
    $fixed=@{
        Schema=$schema
        SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
        TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        CaseName='Attachment1K'
        SourceFolderEntryId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
        SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
        DestinationFolderEntryId='00000000D3E190022DF61241BBDE594AD46A661B82800000'
        OriginalSourceWitnessSha256='0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0'
        FiveEvidenceSetSha256='ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3'
        PlanSha256='6464f562eec08082d1db7781281e3cb0a4efd5264f1c2197ab9f14aedfb74f63'
        ManualSourceSizeDecisionSha256='29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6'
        ImmutableRecipientStateSnapshotSha256='fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
        AttachmentByteSha256='8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'
        ObservedSourceSize='8634';OriginalSourceSize='8122'
    }
    $fields=@('Schema','SuiteId','TestId','CaseName','SourcePst','DestinationPst',
        'SourceStoreIdSha256','DestinationStoreIdSha256','SourceFolderEntryId',
        'SourceEntryId','DestinationFolderEntryId','InternetMessageId',
        'OriginalSourceWitnessSha256','FiveEvidenceSetSha256','PlanSha256',
        'ManualSourceSizeDecisionSha256','ImmutableRecipientStateSnapshotSha256',
        'AttachmentByteSha256','ObservedSourceSize','OriginalSourceSize','AttemptUtc',
        'RealOutlookOneShot','AutomaticRetryAllowed','HistoricalJournalWriteAllowed','ProductionReady')
    if(@($Claim.PSObject.Properties.Name).Count -ne $fields.Count){throw 'BW4k7g claim schema mismatch.'}
    foreach($name in $fields){
        if($Claim.PSObject.Properties.Name -cnotcontains $name){throw ('BW4k7g missing claim '+$name)}
    }
    foreach($name in $fixed.Keys){
        if([string]$Claim.$name -cne [string]$fixed[$name]){
            throw ('BW4k7g immutable claim altered '+$name)
        }
    }
    foreach($name in @('SourcePst','DestinationPst')){
        if([string]::IsNullOrWhiteSpace([string]$Claim.$name) -or
           -not [IO.Path]::IsPathRooted([string]$Claim.$name)){
            throw ('BW4k7g claim invalid path '+$name)
        }
    }
    foreach($name in @('SourceStoreIdSha256','DestinationStoreIdSha256')){
        if([string]$Claim.$name -cnotmatch '^[a-f0-9]{64}$'){throw 'BW4k7g claim store digest invalid.'}
    }
    if([string]$Claim.SourceStoreIdSha256 -ceq [string]$Claim.DestinationStoreIdSha256 -or
       [string]$Claim.InternetMessageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$'){
        throw 'BW4k7g claim source/target store or message identity invalid.'
    }
    $when=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Claim.AttemptUtc,[ref]$when)){
        throw 'BW4k7g claim attempt time invalid.'
    }
    if($Claim.RealOutlookOneShot -isnot [bool] -or -not $Claim.RealOutlookOneShot){
        throw 'BW4k7g claim must be a single real disposable attempt.'
    }
    foreach($flag in @('AutomaticRetryAllowed','HistoricalJournalWriteAllowed','ProductionReady')){
        if($Claim.$flag -isnot [bool] -or $Claim.$flag){throw ('BW4k7g forbidden claim capability '+$flag)}
    }
    return $true
}
function Write-OPA265BW4k7gClaimOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Claim,
        [string]$LocalAppData=$env:LOCALAPPDATA
    )
    [void](Assert-OPA265BW4k7gClaim -Claim $Claim)
    # Reuse universally fenced BW4k1 claim filename. Existing BW4k1/BW4k7f
    # controllers already STOP when any file occupies this exact path.
    $path=Get-OPA265BW4k1ClaimPath -SuiteId $Claim.SuiteId -TestId $Claim.TestId -LocalAppData $LocalAppData
    $parent=[IO.Path]::GetDirectoryName($path)
    $root=[IO.Path]::GetDirectoryName($parent)
    if(-not [IO.Directory]::Exists($root)){[void][IO.Directory]::CreateDirectory($root)}
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7g claim root reparse point forbidden.'
    }
    if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
    if(([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7g claim parent reparse point forbidden.'
    }
    $u=New-Object Text.UTF8Encoding($true)
    $json=ConvertTo-Json -InputObject $Claim -Depth 6
    $bytes=$u.GetBytes($json)
    if($bytes.Length -gt 16384){throw 'BW4k7g claim JSON too large.'}
    $bom=$u.GetPreamble()
    $fs=$null
    try{
        $fs=New-Object IO.FileStream($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $fs.Write($bom,0,$bom.Length)
        $fs.Write($bytes,0,$bytes.Length)
        $fs.Flush($true)
    }finally{if($null -ne $fs){$fs.Dispose()}}
    [pscustomobject][ordered]@{
        ClaimPath=$path
        ClaimSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
function Read-OPA265BW4k7gClaimVerified {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ExpectedClaimSha256,
        [string]$LocalAppData=$env:LOCALAPPDATA
    )
    $path=Get-OPA265BW4k1ClaimPath -SuiteId '74912f94-d523-4856-9efd-d5528a92426f' -TestId '87e72fd0-9e77-4098-a403-cbe99870b9e7' -LocalAppData $LocalAppData
    if($ExpectedClaimSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [IO.File]::Exists($path) -or
       (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $path -Force).Length -gt 16384 -or
       (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedClaimSha256){
        throw 'BW4k7g irreversible attempt Claim missing or SHA-256 differs. NEVER RETRY.'
    }
    $claim=Get-Content -LiteralPath $path -Encoding UTF8 -Raw | ConvertFrom-Json
    [void](Assert-OPA265BW4k7gClaim -Claim $claim)
    return $claim
}
