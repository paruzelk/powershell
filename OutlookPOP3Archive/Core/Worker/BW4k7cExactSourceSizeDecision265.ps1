#requires -Version 5.1
# BW4k7c: one exact source-side +512B SEM-001 operator decision only.
# Never performs Outlook Move, calls a journal writer, or enables production.
. (Join-Path $PSScriptRoot 'BW4k7bSemanticIntegrity265.ps1')

function Get-OPA265BW4k7cDecisionPath {
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
        throw 'BW4k7c decision path requires one original SuiteId/TestId and local AppData.'
    }
    Join-Path (Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k7c-ManualDecisions') ('suite-'+$SuiteId)) ('fixture-'+$TestId+'.json')
}

function Assert-OPA265BW4k7cSemanticVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Verdict)
    if([string]$Verdict.Schema -cne '2.6.5-BW4k7b.SemanticSourceEvidenceClassification.1' -or
       [string]$Verdict.Status -cne 'ContentWitnessMatchedSourceSizeDriftStillUnapproved' -or
       [string]$Verdict.SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       [string]$Verdict.TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       [string]$Verdict.OriginalSourceEvidenceSha256 -cne '0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0' -or
       [long]$Verdict.OriginalSize -ne 8122 -or [long]$Verdict.CurrentSize -ne 8634 -or
       [long]$Verdict.DeltaSize -ne 512 -or [long]$Verdict.AttachmentByteCount -ne 1024 -or
       [string]$Verdict.AttachmentSha256 -cne '8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'){
        throw 'BW4k7c exact original size-only semantic evidence changed.'
    }
    foreach($field in @('AllCapturedContentWitnessFieldsEqual','OriginalThreeMoveClaimsUnchanged','NoGlobalSizeWaiver')){
        if($Verdict.$field -isnot [bool] -or -not $Verdict.$field){
            throw ('BW4k7c mandatory semantic evidence false: '+$field)
        }
    }
    foreach($field in @('SourceMailMoveAttempted','ContentCoverageIncludesFullRecipients',
        'SemanticFlagMaskDefinedForProduction','CrossStoreDestinationVerified',
        'PhysicalPstDurabilityProven','SizeDriftAccepted','AttemptClaimWritten',
        'WriterPermit','OutlookMoveExecuted','CanRetryMove','ProductionReady')){
        if($Verdict.$field -isnot [bool] -or $Verdict.$field){
            throw ('BW4k7c cannot elevate original semantic evidence: '+$field)
        }
    }
    return $true
}

function New-OPA265BW4k7cManualDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Verdict,
        [Parameter(Mandatory=$true)][string]$ApprovalText
    )
    [void](Assert-OPA265BW4k7cSemanticVerdict -Verdict $Verdict)
    $phrase='ACCEPT EXACT SOURCE 8122 TO 8634 PLUS 512 ATTACHMENT1K NO MOVE'
    if($ApprovalText -cne $phrase){
        throw 'BW4k7c requires explicit exact operator acknowledgment phrase.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7c.OneFixtureSourceSizeDecision.1'
        Status='ExactSourceSizeDriftAcknowledgedOnlyNoMovePermit'
        SuiteId=[string]$Verdict.SuiteId
        TestId=[string]$Verdict.TestId
        OriginalSourceEvidenceSha256=[string]$Verdict.OriginalSourceEvidenceSha256
        OriginalSize=[long]$Verdict.OriginalSize
        CurrentSize=[long]$Verdict.CurrentSize
        DeltaSize=[long]$Verdict.DeltaSize
        AttachmentByteCount=[long]$Verdict.AttachmentByteCount
        AttachmentSha256=[string]$Verdict.AttachmentSha256
        SourceWitnessesIdentical=$true
        AllCapturedContentWitnessFieldsEqual=$true
        PriorThreeMoveClaimsUnchanged=$true
        DecisionScope='OnlyThisOriginalDisposableSourceSizeDelta'
        DecisionOrigin='ExplicitOperatorOnce'
        DecisionUtc=[datetime]::UtcNow.ToString('o')
        OperatorDecision=$phrase
        ExactSourceSizeDriftAcknowledged=$true
        NoGlobalSizeWaiver=$true
        CompleteRecipientCoverageProven=$false
        SignificantFlagsCoverageProven=$false
        PostMoveArchiveContentVerified=$false
        PhysicalPstDurabilityProven=$false
        AttemptClaimWritten=$false
        JournalWriteAllowed=$false
        WriterPermit=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}

function Assert-OPA265BW4k7cManualDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Decision,
        [Parameter(Mandatory=$true)][object]$Verdict
    )
    [void](Assert-OPA265BW4k7cSemanticVerdict -Verdict $Verdict)
    $fields=@('Schema','Status','SuiteId','TestId','OriginalSourceEvidenceSha256',
        'OriginalSize','CurrentSize','DeltaSize','AttachmentByteCount','AttachmentSha256',
        'SourceWitnessesIdentical','AllCapturedContentWitnessFieldsEqual',
        'PriorThreeMoveClaimsUnchanged','DecisionScope','DecisionOrigin','DecisionUtc',
        'OperatorDecision','ExactSourceSizeDriftAcknowledged','NoGlobalSizeWaiver',
        'CompleteRecipientCoverageProven','SignificantFlagsCoverageProven',
        'PostMoveArchiveContentVerified','PhysicalPstDurabilityProven',
        'AttemptClaimWritten','JournalWriteAllowed','WriterPermit','OutlookMoveExecuted',
        'AutomaticRetryAllowed','ProductionReady')
    if($Decision -isnot [pscustomobject] -or
       @($Decision.PSObject.Properties.Name).Count -ne $fields.Count){
        throw 'BW4k7c unexpected manual decision schema shape.'
    }
    foreach($field in $fields){
        if($Decision.PSObject.Properties.Name -cnotcontains $field){
            throw ('BW4k7c manual decision missing '+$field)
        }
    }
    foreach($field in @('SuiteId','TestId','OriginalSourceEvidenceSha256',
        'OriginalSize','CurrentSize','DeltaSize','AttachmentByteCount','AttachmentSha256')){
        if([string]$Decision.$field -cne [string]$Verdict.$field){
            throw ('BW4k7c manual decision altered immutable field '+$field)
        }
    }
    if([string]$Decision.Schema -cne '2.6.5-BW4k7c.OneFixtureSourceSizeDecision.1' -or
       [string]$Decision.Status -cne 'ExactSourceSizeDriftAcknowledgedOnlyNoMovePermit' -or
       [string]$Decision.DecisionScope -cne 'OnlyThisOriginalDisposableSourceSizeDelta' -or
       [string]$Decision.DecisionOrigin -cne 'ExplicitOperatorOnce' -or
       [string]$Decision.OperatorDecision -cne 'ACCEPT EXACT SOURCE 8122 TO 8634 PLUS 512 ATTACHMENT1K NO MOVE'){
        throw 'BW4k7c unexpected decision identity, scope or approval text.'
    }
    $dt=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Decision.DecisionUtc,[ref]$dt)){
        throw 'BW4k7c invalid decision timestamp.'
    }
    foreach($field in @('SourceWitnessesIdentical','AllCapturedContentWitnessFieldsEqual',
        'PriorThreeMoveClaimsUnchanged','ExactSourceSizeDriftAcknowledged','NoGlobalSizeWaiver')){
        if($Decision.$field -isnot [bool] -or -not $Decision.$field){
            throw ('BW4k7c decision missing positive proof '+$field)
        }
    }
    foreach($field in @('CompleteRecipientCoverageProven','SignificantFlagsCoverageProven',
        'PostMoveArchiveContentVerified','PhysicalPstDurabilityProven',
        'AttemptClaimWritten','JournalWriteAllowed','WriterPermit',
        'OutlookMoveExecuted','AutomaticRetryAllowed','ProductionReady')){
        if($Decision.$field -isnot [bool] -or $Decision.$field){
            throw ('BW4k7c forbidden permission/proof bit '+$field)
        }
    }
    return $true
}

function Write-OPA265BW4k7cManualDecisionOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Decision,
        [Parameter(Mandatory=$true)][object]$Verdict,
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$LocalAppData=$env:LOCALAPPDATA
    )
    [void](Assert-OPA265BW4k7cManualDecision -Decision $Decision -Verdict $Verdict)
    $expected=Get-OPA265BW4k7cDecisionPath -SuiteId ([string]$Decision.SuiteId) -TestId ([string]$Decision.TestId) -LocalAppData $LocalAppData
    if(-not [string]::Equals([IO.Path]::GetFullPath($Path),
        [IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k7c decision destination cannot be redirected.'
    }
    $dir=[IO.Path]::GetDirectoryName($expected)
    $root=[IO.Path]::GetDirectoryName($dir)
    if(-not [IO.Directory]::Exists($root)){[void][IO.Directory]::CreateDirectory($root)}
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7c decision root reparse point forbidden.'
    }
    if(-not [IO.Directory]::Exists($dir)){[void][IO.Directory]::CreateDirectory($dir)}
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7c decision directory reparse point forbidden.'
    }
    $encoding=New-Object Text.UTF8Encoding($true)
    $data=$encoding.GetBytes((ConvertTo-Json -InputObject $Decision -Depth 5))
    $bom=$encoding.GetPreamble()
    $fs=$null
    try{
        $fs=[IO.FileStream]::new($expected,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $fs.Write($bom,0,$bom.Length)
        $fs.Write($data,0,$data.Length)
        $fs.Flush($true)
    }finally{if($null -ne $fs){$fs.Dispose()}}
    return [pscustomobject][ordered]@{
        DecisionPath=$expected
        DecisionSha256=(Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Read-OPA265BW4k7cManualDecisionVerified {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Verdict,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ExpectedDecisionSha256,
        [string]$LocalAppData=$env:LOCALAPPDATA
    )
    [void](Assert-OPA265BW4k7cSemanticVerdict -Verdict $Verdict)
    $expected=Get-OPA265BW4k7cDecisionPath -SuiteId ([string]$Verdict.SuiteId) -TestId ([string]$Verdict.TestId) -LocalAppData $LocalAppData
    if($ExpectedDecisionSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [string]::Equals([IO.Path]::GetFullPath($Path),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase) -or
       -not [IO.File]::Exists($expected) -or
       (([IO.File]::GetAttributes($expected) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $expected -Force).Length -gt 16384 -or
       (Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedDecisionSha256){
        throw 'BW4k7c immutable original decision absent, altered or misdirected.'
    }
    $record=Get-Content -LiteralPath $expected -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4k7cManualDecision -Decision $record -Verdict $Verdict)
    return [pscustomobject][ordered]@{
        Status='ExactSourceSizeManualDecisionIndependentlyVerifiedNoWriterPermit'
        DecisionPath=$expected
        DecisionSha256=$ExpectedDecisionSha256
        SizeDriftAcknowledged=$true
        WriterPermit=$false
        CanRetryMove=$false
        ProductionReady=$false
    }
}
