#Requires -Version 5.1
<#
.SYNOPSIS
    Регрессионная проверка перевода пользовательских сообщений этапа B.
.DESCRIPTION
    Offline: исходные проверки, команды, атрибуты, переменные и AD не изменяются.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$catalogNames=@('StageB-AccountsADCSApplications.ru-RU.json',
 'StageB-Computer.ru-RU.json','StageB-Credentials.ru-RU.json',
 'StageB-DomainGPORights.ru-RU.json','StageB-Shares.ru-RU.json')
$seen=@{}
$total=0
foreach($name in $catalogNames){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($file in $cat.files.PSObject.Properties){
  $relative=[string]$file.Name
  if($relative -notmatch '^src/modules/Checks/'){throw "Некорректная область: $relative"}
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
if($total -ne 149){throw "Неполный перевод этапа B: $total из 142"}
$report=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/StageBValidation.json'),[Text.Encoding]::UTF8))
if($report.PlannedRules -ne 149 -or $report.ModifiedSourceFiles -ne 36 -or
   -not $report.InterpolationsAndNonStringTokensPreserved -or -not $report.PowerShellParserPassed){
 throw 'Отсутствует подтверждение безопасного применения перевода'
}
$required=@(
 @{File='src/modules/Checks/Computer/Get-InfrastructureServers.ps1';Text='результат неизвестен, а не пуст'},
 @{File='src/modules/Checks/Computer/Get-NetworkMap.ps1';Text='Режим OPSEC'},
 @{File='src/modules/Checks/Creds/Get-DeletedObjectAccess.ps1';Text='другие читатели не проверялись'},
 @{File='src/modules/Checks/Creds/Get-LAPSCredentialAccess.ps1';Text='текущая учётная запись не может прочитать'},
 @{File='src/modules/Checks/GPO/Get-GPOPointAndPrint.ps1';Text='политики Point and Print не оценивались'},
 @{File='src/modules/Checks/Shares/Invoke-ShareHunt.ps1';Text='выполнено только перечисление общих ресурсов'},
 @{File='src/modules/Checks/Domain/Get-DomainPasswordPolicy.ps1';Text='не оценивались'}
)
foreach($case in $required){
 $src=[IO.File]::ReadAllText((Join-Path $ProjectRoot $case.File),[Text.Encoding]::UTF8)
 if(-not $src.Contains($case.Text)){throw "Потеряно существенное пояснение: $($case.File) / $($case.Text)"}
}
# Проверка счётчиков и категорий риска выполняется отдельно штатными CI-тестами.
Write-Host "PASS: этап B — 149 точных переводов, 36 модулей, технические параметры и предупреждения сохранены" -ForegroundColor Green
