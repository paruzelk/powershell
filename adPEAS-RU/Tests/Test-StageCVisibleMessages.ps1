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
$catalogNames=@('StageC-SessionAndCoreUX.ru-RU.json',
 'StageC-ComputerOperations.ru-RU.json','StageC-UserOperations.ru-RU.json',
 'StageC-GPOGroupOperations.ru-RU.json')
$seen=@{}
$total=0
foreach($name in $catalogNames){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($file in $cat.files.PSObject.Properties){
  $relative=[string]$file.Name
  if($relative -notmatch '^src/modules/Core/'){throw "Некорректная область: $relative"}
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
if($total -ne 189){throw "Неполный перевод этапа B: $total из 142"}
$report=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/StageCValidation.json'),[Text.Encoding]::UTF8))
if($report.PlannedRules -ne 189 -or $report.ModifiedSourceFiles -ne 14 -or
   -not $report.InterpolationsAndNonStringTokensPreserved -or -not $report.PowerShellParserPassed){
 throw 'Отсутствует подтверждение безопасного применения перевода'
}
$required=@(
 @{File='src/modules/Core/Connect-adPEAS.ps1';Text='Междоменная аутентификация'},
 @{File='src/modules/Core/Disconnect-adPEAS.ps1';Text='Принудительный режим включён'},
 @{File='src/modules/Core/Move-DomainObject.ps1';Text='наследуемые ACL теперь определяются новым расположением'},
 @{File='src/modules/Core/Set-DomainComputer.ps1';Text='Теперь компьютер может выдавать себя за ЛЮБОГО пользователя'},
 @{File='src/modules/Core/Set-DomainUser.ps1';Text='Теперь пользовательская учётная запись уязвима к AS-REP Roasting!'},
 @{File='src/modules/Core/Set-DomainGPO.ps1';Text='последствия уже применённых на клиентах настроек НЕ отменяются'},
 @{File='src/modules/Core/Set-DomainGroup.ps1';Text='Группу больше нельзя использовать для назначения разрешений'},
 @{File='src/modules/Core/adPEAS-Messages.ps1';Text='Модули проверок безопасности'}
)
foreach($case in $required){
 $src=[IO.File]::ReadAllText((Join-Path $ProjectRoot $case.File),[Text.Encoding]::UTF8)
 if(-not $src.Contains($case.Text)){throw "Потеряно предупреждение или сообщение Core: $($case.File)"}
}
$help=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Core/adPEAS-Messages.ps1'),[Text.Encoding]::UTF8)
if(-not $help.Contains("Connect-adPEAS -Domain 'contoso.com' -Credential (Get-Credential)")){
 throw 'Повреждён исполняемый пример Connect-adPEAS'
}
$definitions=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Core/adPEAS-ObjectTypes.ps1'),[Text.Encoding]::UTF8)
if(-not $definitions.Contains('SecureMessage = "Kerberos policy settings are properly configured.')){
 throw 'Изменён исходный справочник определений — этап C не должен его переписывать'
}
Write-Host "PASS: этап C — 189 точных переводов, 14 модулей, технические параметры и предупреждения сохранены" -ForegroundColor Green
