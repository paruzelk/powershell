#Requires -Version 5.1
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Построение HTML-отчёта File-Server-Audit из готового каталога CSV.
.EXAMPLE
    .\Build-AccessMapFromFolder.ps1 'C:\Reports\NTFSAudit_20261106_123441' -OpenHtml
.EXAMPLE
    .\Build-AccessMapFromFolder.ps1 'C:\Reports\NTFSAudit_20261106_123441\AccessMap_20261106_123441' -OpenHtml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Folder,
    [string]$OutputFolder,
    [switch]$Force,
    [int]$MaxEdgesPerNode = 60,
    [switch]$OpenHtml
)
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Invoke-FileServerAudit-RU.ps1'
$arguments = @{ ReportFolder = $Folder; MaxEdgesPerNode = $MaxEdgesPerNode }
if ($PSBoundParameters.ContainsKey('OutputFolder')) { $arguments.HtmlOutputFolder = $OutputFolder }
if ($Force) { $arguments.Force = $true }
if ($OpenHtml) { $arguments.OpenHtml = $true }
& $runner @arguments
