#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4c: автономная 1:1 сверка всех текстов помощи с исходным adPEAS.
.DESCRIPTION
    Без подключения к AD, без файлов пользователя и без изменений объектов.
    Исходный каталог проверок загружается локально для сопоставления числа
    и порядка проверяемых условий. PowerShell 5.1.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$catalog=@{}
$files=0
$bulletCount=0
$charCount=0
foreach($n in 1..9){
 $name='CheckTooltipDetails-{0:D2}.ru-RU.json' -f $n
 $file=Join-Path $ProjectRoot ('Localization/'+$name)
 if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Нет каталога DOC4c: $name"}
 $doc=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file,[Text.Encoding]::UTF8))
 if($doc.schema -ne 'adPEAS-RU.DOC4c.CheckTooltipDetails.1' -or $doc.locale -ne 'ru-RU'){
  throw "Неверный каталог DOC4c: $name"
 }
 foreach($entry in $doc.translations.PSObject.Properties){
  if($catalog.ContainsKey($entry.Name)){throw "Повторный ObjectType: $($entry.Name)"}
  $v=$entry.Value
  if([string]$v.whyItMatters -notmatch '[А-Яа-яЁё]' -or
     [string]$v.whyItMatters -match '^Параметры домена влияют на доверие'){
   throw "WhyItMatters остался шаблонным: $($entry.Name)"
  }
  $bullets=@($v.whatWeCheck)
  if($bullets.Count -lt 1){throw "Нет критериев $($entry.Name)"}
  foreach($text in $bullets){
   if([string]$text -notmatch '[А-Яа-яЁё]' -or
      [string]$text -match 'Проверенные параметры и обнаруженные объекты приведены'){
    throw "Не переведён подробный критерий: $($entry.Name)"
   }
   $charCount+=([string]$text).Length
  }
  $bulletCount+=$bullets.Count
  $catalog[$entry.Name]=$v
 }
 $files++
}
if($catalog.Count -ne 125 -or $bulletCount -ne 490 -or $files -ne 9){
 throw "Неполный DOC4c: типов $($catalog.Count)/125, критериев $bulletCount/490, файлов $files/9"
}
# Local-only dot sourcing of static metadata; does not run scan entrypoints.
. (Join-Path $ProjectRoot 'src/modules/Core/adPEAS-ObjectTypes.ps1')
if($Script:ObjectTypeDefinitions.Count -ne 125){
 throw "Источник ObjectType изменился: $($Script:ObjectTypeDefinitions.Count)"
}
$originalBullets=0
foreach($id in $Script:ObjectTypeDefinitions.Keys){
 if(-not $catalog.ContainsKey([string]$id)){throw "Русский ObjectType отсутствует: $id"}
 $original=$Script:ObjectTypeDefinitions[$id]
 $translated=$catalog[[string]$id]
 $enChecks=@($original.WhatWeCheck)
 $ruChecks=@($translated.whatWeCheck)
 if($enChecks.Count -ne $ruChecks.Count){
  throw "Различается число условий $id : оригинал=$($enChecks.Count), перевод=$($ruChecks.Count)"
 }
 if([string]$original.WhyItMatters -notmatch '[A-Za-z]' -or
    [string]$translated.whyItMatters -notmatch '[А-Яа-яЁё]'){
  throw "Потеря исходного обоснования $id"
 }
 $originalBullets+=$enChecks.Count
}
if($originalBullets -ne 490){throw "Суммарное число оригинальных критериев изменилось: $originalBullets"}
# Source semantics for the user's screenshot (RBCD, negative assessment).
$rbcd=$catalog['RBCDelegation']
if(@($rbcd.whatWeCheck).Count -ne 5 -or
   $rbcd.whatWeCheck[0] -notmatch 'msDS-AllowedToActOnBehalfOfOtherIdentity' -or
   $rbcd.whatWeCheck[4] -notmatch 'Не проверяется, кто может записывать' -or
   $rbcd.whatWeCheck[4] -notmatch 'ACL'){
 throw 'Предметные ограничения и 5 критериев RBCD потеряны'
}
$ldap=$catalog['EffectiveLDAPConfig']
if($ldap.whatWeCheck[-1] -notmatch 'Не проверяется реестр'){
 throw 'Предупреждение об ограничениях проверки GPO потеряно'
}
$share=$catalog['ReadableShare']
if($share.whatWeCheck[10] -notmatch 'открытым текстом'){
 throw 'Предупреждение об открытых паролях в JSON потеряно'
}
# Ensure the real builder does not show English when precise RU parity is present.
$js=[IO.File]::ReadAllText(
 (Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),
 [Text.Encoding]::UTF8)
foreach($marker in @(
 'const ruDetailedCheckTooltips = ',
 'check.ruDetailedCheckReady = true',
 'if (!check.ruDetailedCheckReady && check.originalEnglish && check.originalEnglish.whyItMatters) {',
 'window.adPEASRUCheckTooltipAudit'
)){
 if(-not $js.Contains($marker)){throw "DOC4c: отсутствует JS-механизм: $marker"}
}
if($js.Contains('if (check.originalEnglish && check.originalEnglish.whyItMatters) {')){
 throw 'DOC4c: английские подробные критерии по-прежнему отображаются без ограничителя'
}
$localize=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localize-RU.ps1'),[Text.Encoding]::UTF8)
if(-not $localize.Contains('Apply-DOC4cCheckTooltips.ps1')){
 throw 'DOC4c не включён в Localize-RU.ps1'
}
$apply=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/Apply-DOC4cCheckTooltips.ps1'),[Text.Encoding]::UTF8)
$scriptBytes=[IO.File]::ReadAllBytes((Join-Path $ProjectRoot 'Localization/Apply-DOC4cCheckTooltips.ps1'))
if($scriptBytes.Length -lt 3 -or $scriptBytes[0] -ne 239 -or $scriptBytes[1] -ne 187 -or $scriptBytes[2] -ne 191){
 throw 'Нет BOM у PowerShell-скрипта DOC4c'
}
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseInput($apply,[ref]$tokens,[ref]$errors)
if($errors -and $errors.Count){throw "Некорректный синтаксис Apply-DOC4cCheckTooltips.ps1: $($errors[0].Message)"}
Write-Host "PASS DOC4c: $($catalog.Count) типов, $bulletCount/$originalBullets критериев 1:1, $charCount символов русских критериев, EN скрыт после проверки; AD не затронут" -ForegroundColor Green
