#requires -Version 5.1
# BW4k1: isolated one-shot real Outlook test-fixture guards. NEVER production Worker.
. (Join-Path $PSScriptRoot 'BW4jMultiFormatWitness265.ps1')

function Get-OPA265BW4k1ClaimPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $null=Get-OPA265BW4jPlanPath -SuiteId $SuiteId -LocalAppData $LocalAppData
    $g=[guid]::Empty
    if(-not [guid]::TryParse($TestId,[ref]$g) -or $g -eq [guid]::Empty -or
        $TestId -cne $g.ToString('D')) {
        throw 'BW4k1 invalid canonical TestId.'
    }
    Join-Path (Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k1-Claims') ('suite-'+$SuiteId)) ('fixture-'+$TestId+'.json')
}
function Assert-OPA265BW4k1PinnedSource {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Original,
          [Parameter(Mandatory=$true)][object]$Current,
          [Parameter(Mandatory=$true)][object]$Case,
          [Parameter(Mandatory=$true)][string]$SuiteId)
    [void](Assert-OPA265BW4jWitness -Witness $Original -Case $Case -SuiteId $SuiteId)
    [void](Assert-OPA265BW4jWitness -Witness $Current -Case $Case -SuiteId $SuiteId)
    $fields=@('Schema','SuiteId','CaseName','TestId','ProfileName','EntryId',
        'FolderEntryId','StoreId','InternetMessageId','SearchKeySha256',
        'SubjectUtf8Sha256','SenderUtf8Sha256','BodyUtf8Sha256',
        'HtmlBodyUtf8Sha256','SubjectLength','BodyLength','HtmlBodyLength',
        'Size','ReceivedUtcTicks','OutlookMoveExecuted','ProductionReady')
    foreach($field in $fields){
        if([string]$Original.$field -cne [string]$Current.$field){
            throw ('BW4k1 STOP: original source witness field drift: '+$field)
        }
    }
    $before=@($Original.Attachments);$after=@($Current.Attachments)
    if($before.Count -ne $after.Count){throw 'BW4k1 STOP: attachment cardinality changed.'}
    for($i=0;$i -lt $before.Count;$i++){
        foreach($field in @('Index','FileName','ByteCount','Sha256')){
            if([string]$before[$i].$field -cne [string]$after[$i].$field){
                throw ('BW4k1 STOP: original binary attachment drift: '+$field)
            }
        }
    }
    return $true
}
function Get-OPA265BW4k1EvidenceSet {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Plan,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    [void](Assert-OPA265BW4jPlan -Plan $Plan)
    if([string]$Plan.SuiteId -cne $SuiteId){
        throw 'BW4k1 five-evidence set SuiteId mismatch.'
    }
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach($case in @($Plan.Cases)){
        $path=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId ([string]$case.TestId) -LocalAppData $LocalAppData
        if(-not [IO.File]::Exists($path) -or
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
           (Get-Item -LiteralPath $path).Length -gt 16384){
            throw ('BW4k1 original source witness absent/unsafe for '+$case.Name)
        }
        $sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $w=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        [void](Assert-OPA265BW4jWitness -Witness $w -Case $case -SuiteId $SuiteId)
        $lines.Add(([string]$case.TestId)+'='+$sha)
    }
    # Order strictly matches immutable plan. ASCII syntax, UTF8 without BOM, LF terminators.
    $nl=[string][char]10
    $canonical=([string]::Join($nl,$lines.ToArray())+$nl)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k1.FiveOriginalWitnessSeal.1'
        SuiteId=$SuiteId
        Count=5
        EvidenceSetSha256=(Get-OPA265BW4jTextHash -Value $canonical)
        OriginalEvidenceSha256Lines=@($lines.ToArray())
        ProductionReady=$false
    }
}
function Write-OPA265BW4k1ClaimOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Claim,
          [Parameter(Mandatory=$true)][string]$ClaimPath,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    if([string]$Claim.Schema -cne '2.6.5-BW4k1.IrreversibleRealMailMoveClaim.1' -or
       $Claim.AutomaticRetryAllowed -isnot [bool] -or $Claim.AutomaticRetryAllowed -or
       $Claim.ProductionReady -isnot [bool] -or $Claim.ProductionReady -or
       $Claim.RealOutlookOneShot -isnot [bool] -or -not $Claim.RealOutlookOneShot -or
       [string]$Claim.SourceEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Claim.EvidenceSetSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Claim.PlanSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4k1 unsafe irreversible claim payload.'
    }
    $expected=Get-OPA265BW4k1ClaimPath -SuiteId ([string]$Claim.SuiteId) -TestId ([string]$Claim.TestId) -LocalAppData $LocalAppData
    if(-not [string]::Equals([IO.Path]::GetFullPath($ClaimPath),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k1 claim path cannot be redirected.'
    }
    $parent=[IO.Path]::GetDirectoryName($expected)
    $root=[IO.Path]::GetDirectoryName($parent)
    if(-not [IO.Directory]::Exists($root)){[void][IO.Directory]::CreateDirectory($root)}
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k1 claim root cannot be a reparse point.'
    }
    if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
    if(([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k1 claim parent cannot be a reparse point.'
    }
    $encoding=New-Object Text.UTF8Encoding($true)
    $body=$encoding.GetBytes((ConvertTo-Json -InputObject $Claim -Depth 6))
    $bom=$encoding.GetPreamble()
    $stream=$null
    try{
        $stream=[IO.FileStream]::new($expected,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bom,0,$bom.Length)
        $stream.Write($body,0,$body.Length)
        $stream.Flush($true)
    } finally {if($null -ne $stream){$stream.Dispose()}}
    return [pscustomobject]@{
        ClaimPath=$expected
        ClaimSha256=(Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
