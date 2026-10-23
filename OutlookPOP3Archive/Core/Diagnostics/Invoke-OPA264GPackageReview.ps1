#requires -Version 5.1
# Offline diagnostic for an externally pinned 2.6.4-G DEV ZIP and matching
# unpacked project. No PST access, Worker launch or journal mutation.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ZipPath,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceCommit,
    [Parameter(Mandatory=$true)][string]$ExpectedZipSHA256,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if (-not $Review) { throw '2.6.4-G package review requires explicit -Review.' }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5) {
    throw '2.6.4-G package review requires Windows PowerShell 5.1.'
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $PSScriptRoot '../Runtime/ReleaseReadiness264.ps1')
$releasePath=Join-Path $root 'RELEASE.json'
$release=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($releasePath)) -ErrorAction Stop
$params=@{
    SourceRoot=$root
    ZipPath=$ZipPath
    ExpectedSourceCommit=$ExpectedSourceCommit
    ExpectedZipSHA256=$ExpectedZipSHA256
    ExpectedTests=[int]$release.Verification.ExpectedPesterTests
    ExpectedContainers=[int]$release.Verification.ExpectedTestContainers
}
$package=Assert-OPA264GDevPackage @params
$decision=New-OPA264GReleaseDecision -Package $package -Release $release
Write-Output (ConvertTo-Json -InputObject $decision -Depth 6)
