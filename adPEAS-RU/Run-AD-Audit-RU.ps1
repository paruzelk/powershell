#Requires -Version 5.1
<#
.SYNOPSIS
    Безопасный аудит Active Directory и создание HTML/TXT/JSON.
.EXAMPLE
    .\Run-AD-Audit-RU.ps1 -Domain 'stios.local' -OPSEC
.EXAMPLE
    .\Run-AD-Audit-RU.ps1 -Domain 'stios.local' -Module Domain,Accounts,GPO -OPSEC
.NOTES
    Режим OPSEC не гарантирует полную пассивность проверки.
#>
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Domain,
 [string]$Server,
 [string]$OutputDirectory=(Join-Path $PSScriptRoot 'Reports'),
 [ValidateSet('Text','HTML','JSON','All')][string]$Format='All',
 [ValidateSet('Domain','Creds','Rights','Delegation','ADCS','Accounts','GPO','Computer','Application','Shares','Bloodhound')][string[]]$Module,
 [ValidateSet('Domain','Creds','Rights','Delegation','ADCS','Accounts','GPO','Computer','Application','Shares','Bloodhound')][string[]]$ExcludeModule,
 [switch]$OPSEC=$true,
 [switch]$IncludePrivileged,
 [switch]$UseLDAPS=$true,
 [switch]$AllowUntrustedCertificate,
 [System.Management.Automation.PSCredential]$Credential
)
# В adPEAS хеш-таблицы имеют необязательные ключи, например Short.
# StrictMode 2+ ошибочно превращает такие обращения в исключения.
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$entry=Join-Path $PSScriptRoot 'adPEAS.ps1'
if(-not (Test-Path -LiteralPath $entry -PathType Leaf)){
 throw 'Не найден собранный adPEAS.ps1. Требуется сборка из полного исходного проекта.'
}
if(-not (Test-Path -LiteralPath $OutputDirectory)){
 New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$resolved=(Resolve-Path -LiteralPath $OutputDirectory).ProviderPath
$basename=Join-Path $resolved ('AD-Audit-'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
Import-Module -Name $entry -Force -ErrorAction Stop
$conn=@{
 Domain=$Domain
 UseWindowsAuth=$true
 UseLDAPS=[bool]$UseLDAPS
 IgnoreSSLErrors=[bool]$AllowUntrustedCertificate
}
if($Server){$conn.Server=$Server}
if($Credential){[void]$conn.Remove('UseWindowsAuth');$conn.Credential=$Credential}
$connected=$false
try{
 $session=Connect-adPEAS @conn
 if(-not $session){throw 'Соединение с Active Directory не установлено.'}
 $connected=$true
 $scan=@{Outputfile=$basename;Format=$Format;OPSEC=[bool]$OPSEC}
 if($Module){$scan.Module=$Module}
 if($ExcludeModule){$scan.ExcludeModule=$ExcludeModule}
 if($IncludePrivileged){$scan.IncludePrivileged=$true}
 Invoke-adPEAS @scan
 Write-Host ("Отчёты: "+$basename+".*") -ForegroundColor Green
} finally {
 if($connected){Disconnect-adPEAS}
}
