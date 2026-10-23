#requires -Version 5.1
# Standalone, project-only ZIP packaging. Does not delete user data or source.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ExpectedBuild,
    [string]$OutputDirectory = '',
    [string]$SourceCommit = '',
    [string]$ExpectedSourceInventorySha256 = ''
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'dist'
}
if ($ExpectedBuild -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9]+)*$') {
    throw 'Invalid ExpectedBuild. Use the exact RELEASE.json Build value.'
}
if ($SourceCommit -and $SourceCommit -notmatch '^[a-fA-F0-9]{40}$') {
    throw 'SourceCommit must be a full 40-character Git SHA.'
}
if ($SourceCommit -and [string]::IsNullOrWhiteSpace($ExpectedSourceInventorySha256)) {
    throw 'SourceCommit alone is only a label. Supply -ExpectedSourceInventorySha256 from the pinned Git commit.'
}
if (-not $SourceCommit -and -not [string]::IsNullOrWhiteSpace($ExpectedSourceInventorySha256)) {
    throw 'ExpectedSourceInventorySha256 requires SourceCommit.'
}
. (Join-Path $root 'Core/Runtime/ReleasePackage.ps1')
[void](Assert-OPAReleaseSourceHygiene -ProjectRoot $root)

Write-Host '== Mandatory CI before packaging =='
& (Join-Path $root 'Invoke-CI.ps1') -ExpectedBuild $ExpectedBuild
# This file is intentionally NOT distributed until its full version and tests
# have been validated. A failed/absent Pester or analyzer aborts above.
$release = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $root 'RELEASE.json') -Raw)
if ([string]$release.Build -cne $ExpectedBuild) {
    throw 'Release metadata changed after CI; refusing to package.'
}
$items = @(Get-OPAReleasePackageFiles -ProjectRoot $root -ExpectedBuild $ExpectedBuild)
if ($items.Count -lt 10) { throw 'No source files selected for packaging.' }
$actualInventorySha256 = Get-OPAReleaseSourceInventorySha256 -Files $items
if ($SourceCommit) {
    [void](Assert-OPAReleaseSourceInventorySha256 -Files $items -ExpectedSha256 $ExpectedSourceInventorySha256)
}
Write-Host ("Source inventory SHA-256: {0} ({1} files)" -f $actualInventorySha256,$items.Count)

$version = $ExpectedBuild.ToLowerInvariant()
$artifactName = 'OutlookPOP3Archive-v' + $version
if ($SourceCommit) { $artifactName += '-dev-g' + $SourceCommit.Substring(0,[Math]::Min(8,$SourceCommit.Length)).ToLowerInvariant() }
$dist = [IO.Path]::GetFullPath($OutputDirectory)
if (-not [IO.Directory]::Exists($dist)) { [void][IO.Directory]::CreateDirectory($dist) }
$archiveFile = Join-Path $dist ($artifactName + '.zip')
$checksumFile = Join-Path $dist ($artifactName + '.sha256')
if ((Test-Path -LiteralPath $archiveFile) -or (Test-Path -LiteralPath $checksumFile)) {
    throw 'The output ZIP/checksum already exists; refusing to overwrite an earlier build.'
}
$stagingParent = Join-Path ([IO.Path]::GetTempPath()) ('OPA-Package-' + [guid]::NewGuid().ToString('N'))
$stagingRoot = Join-Path $stagingParent $artifactName

try {
    [void][IO.Directory]::CreateDirectory($stagingRoot)
    foreach ($item in $items) {
        $relative = [string]$item.RelativePath
        $target = Join-Path $stagingRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        $folder = [IO.Path]::GetDirectoryName($target)
        if (-not [IO.Directory]::Exists($folder)) { [void][IO.Directory]::CreateDirectory($folder) }
        [IO.File]::Copy([string]$item.FullName,$target,$false)
    }
    $buildInfo = [ordered]@{
        Artifact = $artifactName + '.zip'
        Build = $ExpectedBuild
        ApplicationVersion = [string]$release.ApplicationVersion
        SourceCommit = $SourceCommit
        SourceInventorySha256 = $actualInventorySha256
        CreatedUtc = [datetime]::UtcNow.ToString('o')
        Files = $items.Count
        TestsRequired = $true
        Status = 'Packaged after mandatory local Windows CI'
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $infoJson = ConvertTo-Json -InputObject $buildInfo -Depth 5
    [IO.File]::WriteAllText((Join-Path $stagingRoot 'BUILD-INFO.json'),$infoJson,$utf8)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [IO.Compression.ZipFile]::CreateFromDirectory($stagingParent,$archiveFile,[IO.Compression.CompressionLevel]::Optimal,$false)
    $hash = (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($checksumFile,($hash + '  ' + [IO.Path]::GetFileName($archiveFile) + "`n"),$utf8)
    Write-Host ("PASS: {0} ({1} source files); SHA-256: {2}" -f $archiveFile,$items.Count,$hash)
    [pscustomobject]@{
        Archive = $archiveFile
        SHA256File = $checksumFile
        SHA256 = $hash
        Build = $ExpectedBuild
        SourceCommit = $SourceCommit
        SourceInventorySha256 = $actualInventorySha256
        IncludedSourceFiles = $items.Count
    }
}
finally {
    # Only our own fresh temporary staging directory is removed; never
    # remove any Outlook PST, transaction journal or source-side file.
    if (Test-Path -LiteralPath $stagingParent -PathType Container) {
        Remove-Item -LiteralPath $stagingParent -Force -Recurse -ErrorAction Stop
    }
}
) {
    throw 'SourceCommit must be a full 40-character Git SHA.'
}
if ($SourceCommit -and [string]::IsNullOrWhiteSpace($ExpectedSourceInventorySha256)) {
    throw 'A SourceCommit alone is only a label, not provenance verification. Supply -ExpectedSourceInventorySha256 from the pinned Git commit.'
}
if (-not $SourceCommit -and -not [string]::IsNullOrWhiteSpace($ExpectedSourceInventorySha256)) {
    throw 'ExpectedSourceInventorySha256 requires a SourceCommit.'
}
. (Join-Path $root 'Core/Runtime/ReleasePackage.ps1')
[void](Assert-OPAReleaseSourceHygiene -ProjectRoot $root)

Write-Host '== Mandatory CI before packaging =='
& (Join-Path $root 'Invoke-CI.ps1') -ExpectedBuild $ExpectedBuild
# This file is intentionally NOT distributed until its full version and tests
# have been validated. A failed/absent Pester or analyzer aborts above.
$release = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $root 'RELEASE.json') -Raw)
if ([string]$release.Build -cne $ExpectedBuild) {
    throw 'Release metadata changed after CI; refusing to package.'
}
$items = @(Get-OPAReleasePackageFiles -ProjectRoot $root -ExpectedBuild $ExpectedBuild)
if ($items.Count -lt 10) { throw 'No source files selected for packaging.' }

$version = $ExpectedBuild.ToLowerInvariant()
$artifactName = 'OutlookPOP3Archive-v' + $version
if ($SourceCommit) { $artifactName += '-dev-g' + $SourceCommit.Substring(0,[Math]::Min(8,$SourceCommit.Length)).ToLowerInvariant() }
$dist = [IO.Path]::GetFullPath($OutputDirectory)
if (-not [IO.Directory]::Exists($dist)) { [void][IO.Directory]::CreateDirectory($dist) }
$archiveFile = Join-Path $dist ($artifactName + '.zip')
$checksumFile = Join-Path $dist ($artifactName + '.sha256')
if ((Test-Path -LiteralPath $archiveFile) -or (Test-Path -LiteralPath $checksumFile)) {
    throw 'The output ZIP/checksum already exists; refusing to overwrite an earlier build.'
}
$stagingParent = Join-Path ([IO.Path]::GetTempPath()) ('OPA-Package-' + [guid]::NewGuid().ToString('N'))
$stagingRoot = Join-Path $stagingParent $artifactName

try {
    [void][IO.Directory]::CreateDirectory($stagingRoot)
    foreach ($item in $items) {
        $relative = [string]$item.RelativePath
        $target = Join-Path $stagingRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        $folder = [IO.Path]::GetDirectoryName($target)
        if (-not [IO.Directory]::Exists($folder)) { [void][IO.Directory]::CreateDirectory($folder) }
        [IO.File]::Copy([string]$item.FullName,$target,$false)
    }
    $buildInfo = [ordered]@{
        Artifact = $artifactName + '.zip'
        Build = $ExpectedBuild
        ApplicationVersion = [string]$release.ApplicationVersion
        SourceCommit = $SourceCommit
        CreatedUtc = [datetime]::UtcNow.ToString('o')
        Files = $items.Count
        TestsRequired = $true
        Status = 'Packaged after mandatory local Windows CI'
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $infoJson = ConvertTo-Json -InputObject $buildInfo -Depth 5
    [IO.File]::WriteAllText((Join-Path $stagingRoot 'BUILD-INFO.json'),$infoJson,$utf8)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    [IO.Compression.ZipFile]::CreateFromDirectory($stagingParent,$archiveFile,[IO.Compression.CompressionLevel]::Optimal,$false)
    $hash = (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($checksumFile,($hash + '  ' + [IO.Path]::GetFileName($archiveFile) + "`n"),$utf8)
    Write-Host ("PASS: {0} ({1} source files); SHA-256: {2}" -f $archiveFile,$items.Count,$hash)
    [pscustomobject]@{
        Archive = $archiveFile
        SHA256File = $checksumFile
        SHA256 = $hash
        Build = $ExpectedBuild
        SourceCommit = $SourceCommit
        IncludedSourceFiles = $items.Count
    }
}
finally {
    # Only our own fresh temporary staging directory is removed; never
    # remove any Outlook PST, transaction journal or source-side file.
    if (Test-Path -LiteralPath $stagingParent -PathType Container) {
        Remove-Item -LiteralPath $stagingParent -Force -Recurse -ErrorAction Stop
    }
}
