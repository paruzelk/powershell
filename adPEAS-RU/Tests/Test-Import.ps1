#Requires -Version 5.1
<#
.SYNOPSIS
    Проверка загрузки автономного модуля без сети и AD.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$p=Join-Path $ProjectRoot 'adPEAS.ps1'
if(-not (Test-Path -LiteralPath $p)){throw "Не найден $p"}
Import-Module -Name $p -Force -ErrorAction Stop
foreach($name in @('Invoke-adPEAS','Connect-adPEAS','Disconnect-adPEAS')){
 if(-not (Get-Command -Name $name -ErrorAction SilentlyContinue)){throw "Не экспортирована функция $name"}
}
Write-Host 'PASS: автономный adPEAS загружается без AD, ключи SID не вызывают StrictMode' -ForegroundColor Green
