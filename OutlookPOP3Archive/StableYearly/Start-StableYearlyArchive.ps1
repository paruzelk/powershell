#requires -Version 5.1
# Stable 2.5.7-FIX13b operator launcher: calendar years, continuous safe batches.
# No DEV Worker, no permanent Outlook size-limit override, no blind retries.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ProfileName='Outlook',
    [ValidateRange(2000,2099)][int]$ArchiveThroughYear=2025,
    [ValidateRange(1,5000)][int]$BatchSize=1000,
    [ValidateRange(5,1000)][double]$MinimumFreeGB=20,
    [switch]$Execute
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$entry=Join-Path $projectRoot 'OutlookPOP3Archive.ps1'
if ($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'Stable yearly archive requires native Windows PowerShell 5.1 STA.'
}
if (-not [IO.Path]::IsPathRooted($SourcePst) -or $SourcePst.StartsWith('\\') -or
    [IO.Path]::GetExtension($SourcePst) -ine '.pst' -or
    -not [IO.File]::Exists($SourcePst) -or
    ([IO.File]::GetAttributes($SourcePst) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'SourcePst must be an existing local non-symlink PST.'
}
$fullSource=[IO.Path]::GetFullPath($SourcePst)
$srcInfo=Get-Item -LiteralPath $fullSource -ErrorAction Stop
$drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($fullSource))
if ($drive.DriveType -ne [IO.DriveType]::Fixed) {
    throw 'Use a local fixed NTFS/ReFS volume for source and yearly archive PSTs.'
}
$app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
if ($null -eq $app) { throw 'Outlook must already be running under the current Windows user.' }
$ns=$app.GetNamespace('MAPI')
if ([string]$ns.CurrentProfileName -cne $ProfileName) {
    throw 'The active Outlook profile is not the pinned profile.'
}
$found=0
$pop3=0
$targetStoreId=''
for($i=1;$i -le [int]$ns.Stores.Count;$i++){
    $store=$ns.Stores.Item($i)
    $path=''
    try {$path=[string]$store.FilePath} catch {}
    if ($path -and [string]::Equals([IO.Path]::GetFullPath($path),$fullSource,[StringComparison]::OrdinalIgnoreCase)){
        $found++
        $targetStoreId=[string]$store.StoreID
    }
}
for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
    $account=$ns.Accounts.Item($i)
    if ([int]$account.AccountType -ne 2) { continue }
    $pop3++
    $delivery=$account.DeliveryStore
    if ($null -eq $delivery -or
        -not [string]::Equals([string]$delivery.StoreID,$targetStoreId,[StringComparison]::OrdinalIgnoreCase)){
        throw 'Refusing bulk Archive: another POP3 account would be processed by stable FIX13b. Use an isolated profile.'
    }
}
if ($found -ne 1 -or $pop3 -ne 1 -or -not $targetStoreId){
    throw 'Expected exactly one mounted source PST and exactly one POP3 delivery account.'
}

# Registry: no script-side arbitrary 10 GB cap. Respect *effective Outlook*
# Unicode PST thresholds instead of disabling its physical allocation guard.
$version='16.0'
try {
    $v=[string]$app.Version
    if ($v -match '^(\d+)\.') { $version=$Matches[1]+'.0' }
} catch {}
$hardMb=[double]51200
$warningMb=[double]48640
$regKeys=@(
    "HKCU:\Software\Policies\Microsoft\Office\$version\Outlook\PST",
    "HKCU:\Software\Microsoft\Office\$version\Outlook\PST"
)
# Policy has precedence. Each value may be specified independently.
$seenHard=$false
$seenWarning=$false
foreach($key in $regKeys){
    if (-not (Test-Path -LiteralPath $key)) { continue }
    $reg=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
    if (-not $seenHard -and $null -ne $reg.MaxLargeFileSize) {
        $hardMb=[double]$reg.MaxLargeFileSize; $seenHard=$true
    }
    if (-not $seenWarning -and $null -ne $reg.WarnLargeFileSize) {
        $warningMb=[double]$reg.WarnLargeFileSize; $seenWarning=$true
    }
}
if ($hardMb -lt 5120 -or $warningMb -lt 5120 -or
    $warningMb -ge $hardMb -or $hardMb -gt 1048576) {
    throw 'Outlook Unicode PST size policy is missing a safe margin or has unsupported limits.'
}
# Prefer the configured Outlook warning limit, not any artificial 10 GB cap.
# Retain an additional safety margin; an oversized year can roll into -02.
$archiveMaxGB=[math]::Min(($warningMb/1024.0),($hardMb/1024.0 - 1.0))
$safetyMarginGB=0.5
if ($archiveMaxGB -le ($safetyMarginGB + 1.0)) {throw 'Outlook PST configured capacity is unsafe.'}
$freeGB=[double]$drive.AvailableFreeSpace/1GB
if ($freeGB -lt $MinimumFreeGB) {
    throw ('Not enough free local disk space: {0:N1} GB; required reserve {1:N1} GB.' -f $freeGB,$MinimumFreeGB)
}
# An existing 90 GB POP3 PST may have custom Outlook limit registry settings.
# Reject contradictory policies rather than assuming no physical size limit.
if (([double]$srcInfo.Length/1MB) -gt ($hardMb+256)) {
    throw ('Source PST is larger than Outlook configured MaxLargeFileSize ({0:N0} MB). Review Outlook registry/PST health before continuing.' -f $hardMb)
}
$transactionDir=Join-Path ([IO.Path]::GetDirectoryName($fullSource)) 'OutlookPOP3Archive-Transactions'
function Get-OPAStableCheckpointFiles {
    param([string]$Directory)
    if (-not [IO.Directory]::Exists($Directory)) {return @()}
    return @(Get-ChildItem -LiteralPath $Directory -File -Filter '*.json' -ErrorAction Stop |
        Where-Object { $_.Name -ne 'DuplicateIndex.json' -and $_.BaseName -match '^\d{8}-\d{6}-[0-9a-fA-F]{8} })
}
function Assert-OPAStableNoUnfinished {
    param([string]$Directory)
    foreach($file in @(Get-OPAStableCheckpointFiles -Directory $Directory)){
        $state=$null
        try {$state=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop}
        catch {throw ('Unreadable transaction checkpoint; manual recovery required: '+$file.FullName)}
        if ([string]$state.Status -cne 'Completed') {
            throw ('Unfinished transaction blocks any new archive run. Use manual FIX13b Resume: '+$file.FullName+' ['+[string]$state.Status+']')
        }
    }
}
$baseArgs=@{
    Mode='Plan'
    ProfileName=$ProfileName
    ArchiveGrouping='Year'
    ArchiveThroughYear=$ArchiveThroughYear
    OlderThanMonths=0
    IgnoreAge=$true
    DisableStoragePolicy=$true
    MaxArchivePstSizeGB=$archiveMaxGB
    SafetyMarginGB=$safetyMarginGB
    DurabilityMode='Safe'
}
Write-Host ('STABLE 2.5.7-FIX13b yearly operator package; source {0:N1} GB' -f ([double]$srcInfo.Length/1GB))
Write-Host ("Profile: $ProfileName; source: $fullSource; archive years <= $ArchiveThroughYear")
Write-Host ('Outlook physical cap={0:N2} GB; warning={1:N2} GB; chosen archive cap={2:N2} GB; safety margin={3:N2} GB' -f ($hardMb/1024),($warningMb/1024),$archiveMaxGB,$safetyMarginGB)
Write-Host ('Archive files: {0}.Archive-YYYY.pst; same-year part -02 ONLY when PST approaches Outlook capacity.' -f [IO.Path]::GetFileNameWithoutExtension($fullSource))
Write-Host 'Inbox, Sent Items, nested user mail folders included. Outbox excluded. Newer than the specified year excluded.'
Write-Host ('Available disk={0:N1} GB, minimum reserve={1:N1} GB' -f $freeGB,$MinimumFreeGB)
Assert-OPAStableNoUnfinished -Directory $transactionDir
if (-not $Execute) {
    Write-Host 'PREVIEW ONLY: no MailItem.Move; executing existing FIX13b Plan with first 100 candidates.'
    $baseArgs.Mode='Plan'
    $baseArgs.Limit=100
    $baseArgs.WhatIf=$true
    & $entry @baseArgs
    return
}
Write-Host 'EXECUTE: stable FIX13b controlled Archive in consecutive verified batches. This WILL Move eligible messages.'
$logDir=Join-Path $PSScriptRoot 'Logs'
if (-not [IO.Directory]::Exists($logDir)) {[void][IO.Directory]::CreateDirectory($logDir)}
$log=Join-Path $logDir ('StableYearly-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.txt')
$transcribing=$false
try {
    Start-Transcript -Path $log -ErrorAction Stop | Out-Null
    $transcribing=$true
    $batch=0
    while($true){
        $batch++
        if ($batch -gt 100000){throw 'Batch safety limit exceeded; investigate.'}
        if (($drive.AvailableFreeSpace/1GB) -lt $MinimumFreeGB){
            throw 'Free disk space reserve reached. Stop before any further archive Move.'
        }
        Assert-OPAStableNoUnfinished -Directory $transactionDir
        $before=@{}
        foreach($f in @(Get-OPAStableCheckpointFiles -Directory $transactionDir)){$before[$f.FullName]=$true}
        $baseArgs.Mode='Archive'
        $baseArgs.Limit=$BatchSize
        $baseArgs.Remove('WhatIf')
        Write-Host ("===== Stable Archive batch {0}, limit {1} =====" -f $batch,$BatchSize)
        & $entry @baseArgs
        $fresh=@(Get-OPAStableCheckpointFiles -Directory $transactionDir | Where-Object { -not $before.ContainsKey($_.FullName) })
        if ($fresh.Count -ne 1) {
            throw ('Expected exactly one new verified checkpoint for one POP3 source; observed '+$fresh.Count+'. Stop and review journals.')
        }
        $state=Get-Content -LiteralPath $fresh[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ([string]$state.Status -cne 'Completed') {
            throw ('Batch did not finish safely: '+$fresh[0].FullName+' ['+$state.Status+']')
        }
        $moved=[int64]$state.Executed
        Write-Host ("Verified completed batch {0}: {1} moved messages" -f $batch,$moved)
        if ($moved -le 0) {
            Write-Host 'No eligible older mail remains in stable selection. Stop continuous run.'
            break
        }
    }
}
finally {
    if ($transcribing) {Stop-Transcript | Out-Null}
}
 })
}
function Assert-OPAStableNoUnfinished {
    param([string]$Directory)
    foreach($file in @(Get-OPAStableCheckpointFiles -Directory $Directory)){
        $state=$null
        try {$state=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop}
        catch {throw ('Unreadable transaction checkpoint; manual recovery required: '+$file.FullName)}
        if ([string]$state.Status -cne 'Completed') {
            throw ('Unfinished transaction blocks any new archive run. Use manual FIX13b Resume: '+$file.FullName+' ['+[string]$state.Status+']')
        }
    }
}
$baseArgs=@{
    Mode='Plan'
    ProfileName=$ProfileName
    ArchiveGrouping='Year'
    ArchiveThroughYear=$ArchiveThroughYear
    OlderThanMonths=0
    IgnoreAge=$true
    DisableStoragePolicy=$true
    MaxArchivePstSizeGB=$archiveMaxGB
    SafetyMarginGB=$safetyMarginGB
    DurabilityMode='Safe'
}
Write-Host ('STABLE 2.5.7-FIX13b yearly operator package; source {0:N1} GB' -f ([double]$srcInfo.Length/1GB))
Write-Host ("Profile: $ProfileName; source: $fullSource; archive years <= $ArchiveThroughYear")
Write-Host ('Outlook physical cap={0:N2} GB; warning={1:N2} GB; chosen archive cap={2:N2} GB; safety margin={3:N2} GB' -f ($hardMb/1024),($warningMb/1024),$archiveMaxGB,$safetyMarginGB)
Write-Host ('Archive files: {0}.Archive-YYYY.pst; same-year part -02 ONLY when PST approaches Outlook capacity.' -f [IO.Path]::GetFileNameWithoutExtension($fullSource))
Write-Host 'Inbox, Sent Items, nested user mail folders included. Outbox excluded. Newer than the specified year excluded.'
Write-Host ('Available disk={0:N1} GB, minimum reserve={1:N1} GB' -f $freeGB,$MinimumFreeGB)
Assert-OPAStableNoUnfinished -Directory $transactionDir
if (-not $Execute) {
    Write-Host 'PREVIEW ONLY: no MailItem.Move; executing existing FIX13b Plan with first 100 candidates.'
    $baseArgs.Mode='Plan'
    $baseArgs.Limit=100
    $baseArgs.WhatIf=$true
    & $entry @baseArgs
    return
}
Write-Host 'EXECUTE: stable FIX13b controlled Archive in consecutive verified batches. This WILL Move eligible messages.'
$logDir=Join-Path $PSScriptRoot 'Logs'
if (-not [IO.Directory]::Exists($logDir)) {[void][IO.Directory]::CreateDirectory($logDir)}
$log=Join-Path $logDir ('StableYearly-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.txt')
$transcribing=$false
try {
    Start-Transcript -LiteralPath $log -ErrorAction Stop | Out-Null
    $transcribing=$true
    $batch=0
    while($true){
        $batch++
        if ($batch -gt 100000){throw 'Batch safety limit exceeded; investigate.'}
        if (($drive.AvailableFreeSpace/1GB) -lt $MinimumFreeGB){
            throw 'Free disk space reserve reached. Stop before any further archive Move.'
        }
        Assert-OPAStableNoUnfinished -Directory $transactionDir
        $before=@{}
        foreach($f in @(Get-OPAStableCheckpointFiles -Directory $transactionDir)){$before[$f.FullName]=$true}
        $baseArgs.Mode='Archive'
        $baseArgs.Limit=$BatchSize
        $baseArgs.Remove('WhatIf')
        Write-Host ("===== Stable Archive batch {0}, limit {1} =====" -f $batch,$BatchSize)
        & $entry @baseArgs
        $fresh=@(Get-OPAStableCheckpointFiles -Directory $transactionDir | Where-Object { -not $before.ContainsKey($_.FullName) })
        if ($fresh.Count -ne 1) {
            throw ('Expected exactly one new verified checkpoint for one POP3 source; observed '+$fresh.Count+'. Stop and review journals.')
        }
        $state=Get-Content -LiteralPath $fresh[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ([string]$state.Status -cne 'Completed') {
            throw ('Batch did not finish safely: '+$fresh[0].FullName+' ['+$state.Status+']')
        }
        $moved=[int64]$state.Executed
        Write-Host ("Verified completed batch {0}: {1} moved messages" -f $batch,$moved)
        if ($moved -le 0) {
            Write-Host 'No eligible older mail remains in stable selection. Stop continuous run.'
            break
        }
    }
}
finally {
    if ($transcribing) {Stop-Transcript | Out-Null}
}
