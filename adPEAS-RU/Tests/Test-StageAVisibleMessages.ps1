#Requires -Version 5.1
<#
.SYNOPSIS
    Регрессионная проверка перевода пользовательских сообщений этапа A.
.DESCRIPTION
    Offline: исходные проверки, команды, атрибуты, переменные и AD не изменяются.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$catalogNames=@('StageA-ReportingCollector.ru-RU.json',
 'StageA-HelpersBasic.ru-RU.json','StageA-HelpersOperations1.ru-RU.json',
 'StageA-HelpersOperations2.ru-RU.json','StageA-HelpersADCS.ru-RU.json')
$seen=@{}
$total=0
foreach($name in $catalogNames){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($file in $cat.files.PSObject.Properties){
  $relative=[string]$file.Name
  if($relative -notmatch '^src/modules/(?:Reporting|Helpers|Collector)/'){throw "Некорректная область: $relative"}
  $source=[IO.File]::ReadAllText((Join-Path $ProjectRoot $relative),[Text.Encoding]::UTF8)
  foreach($translation in $file.Value.PSObject.Properties){
   $key=($relative+'|'+$translation.Name)
   if($seen.ContainsKey($key)){throw "Повтор правила: $key"}
   $seen[$key]=$true
   $to=[string]$translation.Value
   if(-not $source.Contains($to)){throw "Не применён перевод: $relative / $to"}
   if($source.Contains([string]$translation.Name)){throw "Не удалён исходный английский текст: $relative"}
   $total++
  }
 }
}
if($total -ne 142){throw "Неполный перевод этапа A: $total из 142"}
$report=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/StageAValidation.json'),[Text.Encoding]::UTF8))
if($report.PlannedRules -ne 142 -or $report.ModifiedSourceFiles -ne 14 -or
   -not $report.InterpolationsAndNonStringTokensPreserved -or -not $report.PowerShellParserPassed){
 throw 'Отсутствует подтверждение безопасного применения перевода'
}
$reporter=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/Convert-adPEASReport.ps1'),[Text.Encoding]::UTF8)
$collector=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Collector/Invoke-adPEASCollector.ps1'),[Text.Encoding]::UTF8)
$helper=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Helpers/Invoke-SMBAccess.ps1'),[Text.Encoding]::UTF8)
if(-not $reporter.Contains('Исходный аудит был прерван') -or
   -not $helper.Contains('результат ниже неполный') -or
   -not $collector.Contains('Сбор данных BloodHound CE')){
 throw 'Потеряны существенные сообщения о полноте и статусах проверок'
}
# Исполняемые примеры остаются оригинальными, чтобы не менять команды пользователя.
$cert=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Helpers/Get-CertificateInfo.ps1'),[Text.Encoding]::UTF8)
if(-not $cert.Contains('Connect-adPEAS -Domain <domain> -Certificate')){throw 'Исполняемая команда Connect-adPEAS изменена'}
Write-Host "PASS: этап A — 142 точных перевода, 14 модулей, технические параметры и предупреждения сохранены" -ForegroundColor Green
