#requires -Version 5.1
# BW4k7v2a1 NEW existing-profile pilot policy. Historical BW4k7v2/a is immutable.
function Assert-OPA265BW4k7v2a1SuiteId {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId)
    $parsed=[guid]::Empty
    if(-not [guid]::TryParse($SuiteId,[ref]$parsed) -or
       $parsed -eq [guid]::Empty -or $parsed.ToString('D') -cne $SuiteId -or
       $SuiteId -cin @('78a3e477-98fc-4134-b400-429b3e3b216b',
                      'd1a68868-acf5-4c70-860d-5521e1ce2836')){
        throw 'BW4k7v2a1 requires new canonical lowercase non-historical GUID.'
    }
    return $true
}
function Get-OPA265BW4k7v2a1Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    [void](Assert-OPA265BW4k7v2a1SuiteId -SuiteId $SuiteId)
    if(-not [IO.Path]::IsPathRooted($LocalAppData) -or
       $LocalAppData.StartsWith('\\',[StringComparison]::Ordinal) -or
       -not [IO.Directory]::Exists($LocalAppData)){
        throw 'BW4k7v2a1 requires existing non-UNC LOCALAPPDATA.'
    }
    $root=[IO.Path]::GetFullPath((Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k7v2a1-ExistingProfile'))
    $dir=Join-Path $root ('suite-'+$SuiteId)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a1.Layout.1'
        SuiteId=$SuiteId;ProfileName='Outlook';Pop3SmtpAddress='info@stios.ru'
        Root=$root;SuiteDirectory=$dir
        PstPath=(Join-Path $dir ('OPA265-BW4k7v2a1-'+$SuiteId+'.pst'))
        IntentPath=(Join-Path $dir 'one-pilot-intent.json')
        ManifestPath=(Join-Path $dir 'one-pilot-manifest.json')
        TestFolderName=('OPA265-BW4k7v2a1-'+$SuiteId)
        PilotSubject=('OPA265-BW4k7v2a1-PILOT-'+$SuiteId)
        WriterPermit=$false;ProductionReady=$false
    }
}
function Assert-OPA265BW4k7v2a1Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    $expected=Get-OPA265BW4k7v2a1Layout -SuiteId ([string]$Layout.SuiteId) -LocalAppData $LocalAppData
    foreach($name in @('ProfileName','Pop3SmtpAddress','Root','SuiteDirectory','PstPath',
        'IntentPath','ManifestPath','TestFolderName','PilotSubject')){
        if([string]$Layout.$name -cne [string]$expected.$name){
            throw ('BW4k7v2a1 invalid layout '+$name)
        }
    }
    foreach($path in @($expected.Root,$expected.SuiteDirectory,$expected.PstPath)){
        if(([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) -and
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'BW4k7v2a1 reparse point forbidden.'
        }
    }
    return $true
}
function Test-OPA265BW4k7v2a1ExistingProfileScope {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$ActualProfileName,
          [Parameter(Mandatory=$true)][object[]]$Accounts,
          [Parameter(Mandatory=$true)][object[]]$Stores,
          [switch]$AllowTargetAttached)
    $issues=New-Object 'System.Collections.Generic.List[string]'
    if($ActualProfileName -cne 'Outlook'){$issues.Add('WrongOutlookProfile')}
    $storeIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pop3StoreId=''
    $matchedStores=0
    foreach($store in $Stores){
        if($null -eq $store -or [string]::IsNullOrWhiteSpace([string]$store.StoreId)){
            $issues.Add('UnresolvedStore');continue
        }
        if(-not $storeIds.Add([string]$store.StoreId)){
            $issues.Add('DuplicateStoreId')
        }
        $path=[string]$store.FilePath
        if(-not [string]::IsNullOrWhiteSpace($path)){
            try{
                if([string]::Equals([IO.Path]::GetFullPath($path),[string]$Layout.PstPath,
                    [StringComparison]::OrdinalIgnoreCase)){$matchedStores++}
            }catch{$issues.Add('InvalidStorePath')}
        }
    }
    $matchedPop3=0
    foreach($account in $Accounts){
        if($null -ne $account -and [string]$account.SmtpAddress -ieq [string]$Layout.Pop3SmtpAddress -and
           [int]$account.AccountType -eq 2){
            $matchedPop3++
            $pop3StoreId=[string]$account.DeliveryStoreId
        }
    }
    if($matchedPop3 -ne 1){$issues.Add('ExpectedPop3AccountNotUnique')}
    if([string]::IsNullOrWhiteSpace($pop3StoreId) -or -not $storeIds.Contains($pop3StoreId)){
        $issues.Add('Pop3DeliveryStoreMissing')
    }
    if((-not $AllowTargetAttached -and $matchedStores -ne 0) -or
       ($AllowTargetAttached -and $matchedStores -ne 1)){
        $issues.Add('TargetTestStoreCardinalityMismatch')
    }
    if($AllowTargetAttached -and $matchedStores -eq 1){
        foreach($store in $Stores){
            if([string]::Equals([string]$store.StoreId,$pop3StoreId,
                 [StringComparison]::Ordinal)){
                try{
                    if([string]::Equals([IO.Path]::GetFullPath([string]$store.FilePath),
                         [string]$Layout.PstPath,[StringComparison]::OrdinalIgnoreCase)){
                        $issues.Add('TestStoreIsPop3DeliveryStore')
                    }
                }catch{$issues.Add('InvalidPop3DeliveryStorePath')}
            }
        }
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a1.ExistingProfileScope.1'
        Approved=($issues.Count -eq 0)
        ReasonCodes=@($issues.ToArray())
        Pop3DeliveryStoreId=$pop3StoreId
        TestStoreCount=$matchedStores
        ExistingProfileAllowed=$true
        OtherStoresAllowed=$true
        SourceMailRead=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Get-OPA265BW4k7v2a1Sha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    $h=[Security.Cryptography.SHA256]::Create()
    try{
        $b=[Text.Encoding]::UTF8.GetBytes($Text)
        return [BitConverter]::ToString($h.ComputeHash($b)).Replace('-','').ToLowerInvariant()
    }finally{$h.Dispose()}
}
function Write-OPA265BW4k7v2a1JsonOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][object]$Value)
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(
        (ConvertTo-Json -InputObject $Value -Depth 10))
    $fs=$null
    try{
        $fs=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $fs.Write($bytes,0,$bytes.Length)
        $fs.Flush($true)
    }finally{if($null -ne $fs){$fs.Dispose()}}
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-OPA265BW4k7v2a1SealedJson {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][string]$ExpectedSha256)
    if($ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [IO.File]::Exists($Path)){
        throw 'BW4k7v2a1 sealed evidence absent or expected SHA invalid.'
    }
    if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSha256){
        throw 'BW4k7v2a1 sealed evidence SHA mismatch.'
    }
    return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)))
}