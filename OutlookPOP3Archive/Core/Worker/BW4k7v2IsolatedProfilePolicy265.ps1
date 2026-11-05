#requires -Version 5.1
# BW4k7v2 fail-closed separate-profile pilot policy. The old BW4k7v
# partial PST and accidental default Draft are deliberately quarantined.
function Assert-OPA265BW4k7v2SuiteId {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId)
    $guid=[guid]::Empty
    $blocked=@(
        '78a3e477-98fc-4134-b400-429b3e3b216b',
        'd1a68868-acf5-4c70-860d-5521e1ce2836'
    )
    if(-not [guid]::TryParse($SuiteId,[ref]$guid) -or
       $guid -eq [guid]::Empty -or
       $guid.ToString('D') -cne $SuiteId -or
       $SuiteId -cin $blocked){
        throw 'BW4k7v2 requires a brand new canonical lowercase GUID; historic SuiteIds are forbidden.'
    }
    return $true
}
function Get-OPA265BW4k7v2Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    [void](Assert-OPA265BW4k7v2SuiteId -SuiteId $SuiteId)
    if(-not [IO.Path]::IsPathRooted($LocalAppData) -or
       $LocalAppData.StartsWith('\\',[StringComparison]::Ordinal) -or
       -not [IO.Directory]::Exists($LocalAppData)){
        throw 'BW4k7v2 requires existing local, non-UNC LOCALAPPDATA.'
    }
    $root=[IO.Path]::GetFullPath((Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k7v2-Isolated'))
    $directory=Join-Path $root ('suite-'+$SuiteId)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2.Layout.1'
        SuiteId=$SuiteId
        ProfileName='OPA265-BW4k7v2'
        Root=$root
        SuiteDirectory=$directory
        PstPath=(Join-Path $directory ('OPA265-BW4k7v2-'+$SuiteId+'.pst'))
        TemplatePath=(Join-Path $directory ('pilot-'+$SuiteId+'.oft'))
        ManifestPath=(Join-Path $directory 'pilot-premovereadonly.json')
        RootFolderName=('OPA265-BW4k7v2-'+$SuiteId)
        PilotFolderName='Pilot-Inbox'
        PilotSubject=('OPA265-BW4k7v2-PILOT-'+$SuiteId)
        SyntheticYear=2020
        NoOldOutlookProfileAccess=$true
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7v2Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    $actual=Get-OPA265BW4k7v2Layout -SuiteId ([string]$Layout.SuiteId) -LocalAppData $LocalAppData
    foreach($name in @('ProfileName','Root','SuiteDirectory','PstPath',
        'TemplatePath','ManifestPath','RootFolderName','PilotFolderName','PilotSubject')){
        if([string]$Layout.$name -cne [string]$actual.$name){
            throw ('BW4k7v2 forged layout '+$name)
        }
    }
    foreach($p in @($actual.Root,$actual.SuiteDirectory,$actual.PstPath)){
        if(([IO.Directory]::Exists($p) -or [IO.File]::Exists($p)) -and
           (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'BW4k7v2 does not allow symlink/reparse point directories or PST.'
        }
    }
    return $true
}
function Test-OPA265BW4k7v2StoreIsolation {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$ActualProfileName,
          [ValidateRange(0,999)][int]$AccountsCount,
          [ValidateRange(0,999)][int]$StoresCount,
          [Parameter(Mandatory=$true)][string]$DefaultStoreId,
          [Parameter(Mandatory=$true)][string]$OnlyStoreId,
          [Parameter(Mandatory=$true)][string]$OnlyStoreFilePath,
          [ValidateRange(0,1000000000000)][long]$PstSizeBytes,
          [switch]$RequirePristine)
    $issues=New-Object 'System.Collections.Generic.List[string]'
    if($ActualProfileName -cne [string]$Layout.ProfileName){
        $issues.Add('NotDedicatedProfile')
    }
    if($AccountsCount -ne 0){$issues.Add('MailAccountsPresent')}
    if($StoresCount -ne 1){$issues.Add('MultipleOrMissingStores')}
    if($DefaultStoreId -cne $OnlyStoreId -or
       [string]::IsNullOrWhiteSpace($OnlyStoreId)){
        $issues.Add('DefaultStoreNotOnlyStore')
    }
    $pathMatch=$false
    try{
        $full=[IO.Path]::GetFullPath($OnlyStoreFilePath)
        $pathMatch=[string]::Equals($full,[string]$Layout.PstPath,
            [StringComparison]::OrdinalIgnoreCase)
    }catch{}
    if(-not $pathMatch){$issues.Add('OnlyStorePathMismatch')}
    if($PstSizeBytes -le 0 -or $PstSizeBytes -gt 16777216){
        if($RequirePristine){$issues.Add('PilotPstTooLargeOrMissing')}
        elseif($PstSizeBytes -le 0){$issues.Add('PstMissing')}
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2.StoreIsolation.1'
        Isolated=($issues.Count -eq 0)
        ReasonCodes=@($issues.ToArray())
        ProfileName=$ActualProfileName
        AccountsCount=$AccountsCount
        StoresCount=$StoresCount
        OnlyPstIsDefault=$DefaultStoreId -ceq $OnlyStoreId
        ExactPstPathMatch=$pathMatch
        MustStopBeforeAnyMailCreation=($issues.Count -ne 0)
        AutomaticRecoveryOrFallbackAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Get-OPA265BW4k7v2Sha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    $h=[Security.Cryptography.SHA256]::Create()
    try{
        $bytes=[Text.Encoding]::UTF8.GetBytes($Text)
        return [BitConverter]::ToString($h.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
    }finally{$h.Dispose()}
}
function Assert-OPA265BW4k7v2PilotManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Manifest,
          [Parameter(Mandatory=$true)][object]$Layout)
    if([string]$Manifest.Schema -cne '2.6.5-BW4k7v2.PilotPreMoveManifest.1' -or
       [string]$Manifest.SuiteId -cne [string]$Layout.SuiteId -or
       [string]$Manifest.PstPath -cne [string]$Layout.PstPath -or
       [string]$Manifest.ProfileName -cne [string]$Layout.ProfileName -or
       [string]$Manifest.Subject -cne [string]$Layout.PilotSubject -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.StoreId) -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.EntryId) -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.FolderId) -or
       [long]$Manifest.CreatingProcessStartUtcTicks -le 0 -or
       [string]$Manifest.WitnessSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [bool]$Manifest.DedicatedSinglePstNoAccounts -or
       [int]$Manifest.SyntheticArchiveYear -ne 2020 -or
       [bool]$Manifest.MoveExecuted -or
       [bool]$Manifest.SendExecuted -or
       [bool]$Manifest.OldProfileTouched -or
       [bool]$Manifest.ProductionReady -or
       [bool]$Manifest.WriterPermit){
        throw 'BW4k7v2 manifest is invalid or unsafe.'
    }
    return $true
}
function Write-OPA265BW4k7v2ManifestOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][object]$Manifest)
    [void](Assert-OPA265BW4k7v2PilotManifest -Manifest $Manifest -Layout $Layout)
    $utf8=New-Object Text.UTF8Encoding($false)
    $data=$utf8.GetBytes((ConvertTo-Json -InputObject $Manifest -Depth 12))
    $fs=$null
    try{
        $fs=[IO.File]::Open([string]$Layout.ManifestPath,
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $fs.Write($data,0,$data.Length)
        $fs.Flush($true)
    }finally{if($null -ne $fs){$fs.Dispose()}}
    return (Get-FileHash -LiteralPath $Layout.ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-OPA265BW4k7v2Manifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256)
    if($ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4k7v2 original lowercase SHA256 is required.'
    }
    if(-not [IO.File]::Exists([string]$Layout.ManifestPath)){
        throw 'BW4k7v2 no original manifest; never reconstruct or retry.'
    }
    $actual=(Get-FileHash -LiteralPath $Layout.ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -cne $ExpectedManifestSha256){
        throw 'BW4k7v2 sealed manifest tampered; STOP.'
    }
    $record=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText(
        [string]$Layout.ManifestPath,[Text.Encoding]::UTF8))
    [void](Assert-OPA265BW4k7v2PilotManifest -Manifest $record -Layout $Layout)
    return $record
}
