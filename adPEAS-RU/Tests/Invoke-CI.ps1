#Requires -Version 5.1
<#
.SYNOPSIS
    Изолированные проверки adPEAS-RU без обращения к Active Directory.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$checks=0
function Assert([bool]$Condition,[string]$Message) {
 if(-not $Condition){throw "FAIL: $Message"}
 $script:checks++
 Write-Host "PASS: $Message"
}
$entry=Join-Path $ProjectRoot 'adPEAS.ps1'
Assert (Test-Path -LiteralPath $entry -PathType Leaf) 'Существует автономный adPEAS.ps1'
$src=Join-Path $ProjectRoot 'src/adPEAS.ps1'
Assert (Test-Path -LiteralPath $src) 'Сохранено модульное дерево исходников'
Assert (Test-Path (Join-Path $ProjectRoot 'license/LICENSE.md')) 'Сохранена оригинальная лицензия'
Assert (Test-Path (Join-Path $ProjectRoot 'Run-AD-Audit-RU.ps1')) 'Доступен запуск в одну команду'
$psfiles=@(Get-ChildItem -Path $ProjectRoot -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1','.psd1')})
foreach($file in $psfiles){
 $b=[IO.File]::ReadAllBytes($file.FullName)
 Assert ($b.Length -gt 2 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) ("UTF-8 BOM: "+$file.Name)
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 Assert (-not $errors -or $errors.Count -eq 0) ("PowerShell 5.1 синтаксис: "+$file.Name)
}
foreach($name in @('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1')){
 Assert (Test-Path (Join-Path $ProjectRoot $name)) ("Автономный вариант: "+$name)
}
$h=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-template.html'))
Assert ($h.Contains('lang="ru"')) 'Русская локаль HTML'
Assert ($h.Contains('Аудит безопасности Active Directory')) 'Русское название отчёта'
Assert ($h.Contains('{{FINDINGS_SECTIONS}}')) 'Сохранён контейнер результатов'
Assert ($h.Contains('data-severity="finding"')) 'Сохранён машинный классификатор результата'
$compiled=[IO.File]::ReadAllText($entry)
Assert ($compiled.Contains('Аудит безопасности Active Directory')) 'Встроен русифицированный шаблон'
$runner=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'Run-AD-Audit-RU.ps1'))
Assert ($runner.Contains('Set-StrictMode -Off')) 'Нет ошибки StrictMode на необязательных ключах'
Assert ($runner.Contains('IgnoreSSLErrors=[bool]$AllowUntrustedCertificate')) 'Проверка сертификата LDAPS включена по умолчанию'
Write-Host "PASS: $checks локальных проверок, AD не затронут" -ForegroundColor Green
