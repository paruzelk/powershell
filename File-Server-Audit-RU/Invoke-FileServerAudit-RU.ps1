#Requires -Version 5.1
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Аудит NTFS/AD с автоматическим построением HTML на базе File-Server-Audit 0.7.4.
.DESCRIPTION
    Готовый запуск без установщиков. Сохраняет параметры исходного
    Invoke-NTFSPermissionAudit.ps1 и вызывает Build-AccessMapHtml.ps1.
    -ReportFolder формирует HTML из ранее полученных CSV либо открывает
    готовый AccessMap.html. Не изменяет ACL и объекты AD.
.EXAMPLE
    .\Invoke-FileServerAudit-RU.ps1 -Path '\\SHARE\Network' -ExpandGroups -MaxDepth 2 -OpenHtml
.EXAMPLE
    .\Invoke-FileServerAudit-RU.ps1 -ReportFolder '.\NTFSAudit_20261106_123441' -OpenHtml
.EXAMPLE
    .\Invoke-FileServerAudit-RU.ps1 -ReportFolder '.\NTFSAudit_20261106_123441\AccessMap_20261106_123441' -OpenHtml
#>
[CmdletBinding(DefaultParameterSetName = 'Scan')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Scan')]
    [string[]]$Path,

    [Parameter(Mandatory = $true, ParameterSetName = 'Report', Position = 0)]
    [Alias('InputFolder')]
    [string]$ReportFolder,

    # Параметры исходного NTFS-сканера (имена и типы сохранены).
    [switch]$IncludeFiles,
    [switch]$IncludeInheritedFileAces,
    [int]$MaxDepth = -1,
    [switch]$NoRecursion,
    [switch]$BreadthFirst,
    [ValidateRange(1,128)]
    [int]$ThrottleLimit = 1,
    [switch]$ExpandGroups,
    [string[]]$ExpandGroupsExclude = @('Domain Users','Everyone','Authenticated Users','Users','BUILTIN\Users'),
    [Alias('SkipInheritedAcesInFolderReport')]
    [switch]$SkipInheritedAces,
    [string]$OutputFolder,
    [switch]$NoAdLookup,
    [switch]$Force,
    [switch]$Resume,

    # Только построение/открытие HTML.
    [string]$HtmlOutputFolder,
    [int]$MaxEdgesPerNode = 60,
    [switch]$OpenHtml
)

$ErrorActionPreference = 'Stop'
# Важно: НЕ включать Set-StrictMode здесь. Исходные сканер и сборщик
# исполняются в собственных областях; сборщик 0.7.4 не рассчитан на
# унаследованный StrictMode Latest.
$base = $PSScriptRoot
$scanner = Join-Path $base 'Invoke-NTFSPermissionAudit.ps1'
$builder = Join-Path $base 'Build-AccessMapHtml.ps1'
foreach ($f in @($scanner,$builder,(Join-Path $base 'AccessMapTemplate.html'))) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
        throw "Отсутствует обязательный файл проекта: $f"
    }
}

function Get-IdentityCsvFiles {
    param([Parameter(Mandatory)][string]$Directory)
    return @(Get-ChildItem -LiteralPath $Directory -Filter 'IdentityPermissions*.csv' -File -ErrorAction Stop)
}

function Get-AuditTimestamp {
    param([Parameter(Mandatory)][string]$Directory)
    $candidates = @(Get-IdentityCsvFiles -Directory $Directory)
    if ($candidates.Count -lt 1) { throw "Нет IdentityPermissions*.csv в $Directory" }
    $sorted = @($candidates | Sort-Object -Descending -Property @{
        Expression = {
            if ($_.Name -match '_(\d{8}_\d{6})\.csv$') { $Matches[1] }
            else { $_.LastWriteTime.ToString('yyyyMMdd_HHmmss') }
        }
    })
    if ($sorted[0].Name -match '_(\d{8}_\d{6})\.csv$') { return $Matches[1] }
    return (Get-Date -Format 'yyyyMMdd_HHmmss')
}

$sourceDir = $null
$htmlPath = $null
$targetDir = $null

if ($PSCmdlet.ParameterSetName -eq 'Scan') {
    if ($Resume -and -not $PSBoundParameters.ContainsKey('OutputFolder')) {
        throw 'Для -Resume укажите исходный каталог -OutputFolder.'
    }
    if (-not $PSBoundParameters.ContainsKey('OutputFolder')) {
        $OutputFolder = Join-Path (Get-Location).Path ("NTFSAudit_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }
    $scanArgs = @{ Path = $Path; OutputFolder = $OutputFolder }
    foreach ($name in @(
        'IncludeFiles','IncludeInheritedFileAces','MaxDepth','NoRecursion',
        'BreadthFirst','ThrottleLimit','ExpandGroups','ExpandGroupsExclude',
        'SkipInheritedAces','NoAdLookup','Force','Resume'
    )) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $scanArgs[$name] = $PSBoundParameters[$name]
        }
    }
    if ($NoAdLookup -and $ExpandGroups) {
        Write-Warning 'Указаны одновременно -NoAdLookup и -ExpandGroups: участники групп не будут определены.'
    } elseif (-not $ExpandGroups) {
        Write-Warning 'Для отображения участников AD-групп требуется параметр -ExpandGroups.'
    }
    Write-Host "Аудит NTFS: $OutputFolder" -ForegroundColor Cyan
    & $scanner @scanArgs
    $sourceDir = (Resolve-Path -LiteralPath $OutputFolder).ProviderPath
    if (@(Get-IdentityCsvFiles -Directory $sourceDir).Count -lt 1) {
        throw 'Аудит не создал IdentityPermissions.csv; построение HTML отменено.'
    }
    $done = @(Get-ChildItem -LiteralPath $sourceDir -Filter 'Completed_*.marker' -File)
    if ($done.Count -lt 1) {
        throw 'Отсутствует маркер завершения сканирования. Сначала завершите аудит.'
    }
}
else {
    $requested = (Resolve-Path -LiteralPath $ReportFolder).ProviderPath
    if (-not (Test-Path -LiteralPath $requested -PathType Container)) {
        throw "Путь не является каталогом: $requested"
    }
    $csvHere = @(Get-IdentityCsvFiles -Directory $requested)
    if ($csvHere.Count -gt 0) {
        $sourceDir = $requested
    }
    else {
        $existingHtml = Join-Path $requested 'AccessMap.html'
        $dataFile = Join-Path $requested 'AccessMap_data\manifest.js'
        if ((Test-Path -LiteralPath $existingHtml -PathType Leaf) -and
            (Test-Path -LiteralPath $dataFile -PathType Leaf) -and
            -not $Force -and -not $HtmlOutputFolder) {
            $htmlPath = $existingHtml
        }
        else {
            $parent = Split-Path -Path $requested -Parent
            if (@(Get-IdentityCsvFiles -Directory $parent).Count -lt 1) {
                throw 'В указанном каталоге и его родителе нет IdentityPermissions*.csv.'
            }
            $sourceDir = $parent
            if (-not $HtmlOutputFolder) { $targetDir = $requested }
        }
    }
}

if (-not $htmlPath) {
    $buildArgs = @{ InputFolder = $sourceDir; MaxEdgesPerNode = $MaxEdgesPerNode }
    if ($HtmlOutputFolder) {
        $targetDir = $HtmlOutputFolder
    }
    if ($targetDir) {
        $buildArgs.OutputFolder = $targetDir
    }
    if ($Force) {
        $buildArgs.Force = $true
    }
    $stamp = Get-AuditTimestamp -Directory $sourceDir
    Write-Host "Создание HTML: $sourceDir" -ForegroundColor Cyan
    & $builder @buildArgs
    if (-not $targetDir) {
        $targetDir = Join-Path $sourceDir "AccessMap_$stamp"
    }
    $htmlPath = Join-Path $targetDir 'AccessMap.html'
    $manifestPath = Join-Path $targetDir 'AccessMap_data\manifest.js'
    if (-not (Test-Path -LiteralPath $htmlPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "HTML-отчёт не создан полностью: $targetDir"
    }
}

Write-Host "HTML-отчёт: $htmlPath" -ForegroundColor Green
if ($OpenHtml) { Invoke-Item -LiteralPath $htmlPath }
[PSCustomObject]@{
    Status = 'Succeeded'
    HtmlPath = $htmlPath
    SourceFolder = $sourceDir
}
