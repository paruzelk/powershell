#Requires -Version 5.1
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Проверка статистики распределения прав в уже готовой папке AccessMap.
.DESCRIPTION
    Только чтение AccessMap_data\manifest.js, без обращения к NTFS/AD.
.EXAMPLE
    .\Tests\Test-RightsManifest.ps1 -AccessMapFolder 'D:\Reports\NTFSAudit_20261106_153548\AccessMap_20261106_153548'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$AccessMapFolder
)
$ErrorActionPreference = 'Stop'
$full = (Resolve-Path -LiteralPath $AccessMapFolder).ProviderPath
$manifestPath = Join-Path $full 'AccessMap_data\manifest.js'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Отсутствует manifest.js: $manifestPath"
}
$js = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8)
if ($js -notmatch '^\s*const\s+ACCESS_MAP_MANIFEST\s*=') {
    throw 'Неверный формат manifest.js: отсутствует ACCESS_MAP_MANIFEST.'
}
$json = ($js -replace '^\s*const\s+ACCESS_MAP_MANIFEST\s*=\s*', '') -replace ';\s*$', ''
$manifest = ConvertFrom-Json -InputObject $json
$expected = [int64]$manifest.totalEdgeCount
$raw = $manifest.rightsDistribution
$values = @()
if ($null -ne $raw) {
    if ($raw -is [array]) {
        $values = @($raw)
    }
    elseif ($raw -is [pscustomobject]) {
        foreach ($i in 0..5) {
            $field = $raw.PSObject.Properties[[string]$i]
            if ($null -eq $field) { break }
            $values += $field.Value
        }
    }
}
$validTypes = $values.Count -eq 6
$total = [int64]0
if ($validTypes) {
    foreach ($n in $values) {
        $v = [int64]0
        if (-not [int64]::TryParse([string]$n, [ref]$v) -or $v -lt 0) {
            $validTypes = $false
            break
        }
        $total += $v
    }
}
$status = if (-not $validTypes) { 'InvalidCounters' }
          elseif ($total -ne $expected) { 'CountMismatch' }
          else { 'Valid' }
[pscustomobject]@{
    Status = $status
    TotalEdgeCount = $expected
    SumRightsBuckets = if ($validTypes) { $total } else { $null }
    RightsDistribution = if ($validTypes) { $values -join ', ' } else { '[unavailable or malformed]' }
    ReportFolder = $full
}
