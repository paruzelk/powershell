#Requires -Version 5.1
<#
.SYNOPSIS
    Регрессия предметных русских сообщений исходных проверок.
.NOTES
    Не подключается к домену и не читает пользовательские отчёты.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$translated=@{}
foreach($file in @('CheckSecureMessages-08a.ru-RU.json','CheckSecureMessages-08b.ru-RU.json',
                   'CheckSecureMessages-08c.ru-RU.json','CheckSecureMessages-08d.ru-RU.json')){
 $source=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$file)),[Text.Encoding]::UTF8))
 foreach($p in $source.translations.PSObject.Properties){
  if($translated.ContainsKey($p.Name)){throw "Повторяющийся ID проверки: $($p.Name)"}
  if([string]$p.Value -notmatch '[А-Яа-яЁё]'){throw "Не переведено: $($p.Name)"}
  $translated[$p.Name]=[string]$p.Value
 }
}
if($translated.Count -ne 94){throw "Ожидалось 94 сообщения, найдено $($translated.Count)"}
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$marker='const ruCheckContext = '
$pos=$js.IndexOf($marker,[StringComparison]::Ordinal)
if($pos -lt 0){throw 'Нет встроенных описаний проверок'}
$pos+=$marker.Length
$last=$js.IndexOf([char]10,$pos)
if($last -lt 0){throw 'Повреждена строка JSON описаний'}
$ctx=ConvertFrom-Json -InputObject ($js.Substring($pos,$last-$pos).Trim().TrimEnd([char]';'))
foreach($id in $translated.Keys){
 $entry=$ctx.PSObject.Properties[$id]
 if($null -eq $entry){throw "Не найдено описание: $id"}
 if([string]$entry.Value.secureMessage -cne [string]$translated[$id]){throw "Ошибка русификации сообщения: $id"}
}
if($ctx.PSObject.Properties['BitLockerRecoveryKey'].Value.secureMessage -notmatch 'ДРУГИХ субъектов'){throw 'Утеряна оговорка о проверяемой учётной записи'}
if($ctx.PSObject.Properties['SCOMServer'].Value.secureMessage -notmatch 'ВНУТРИ SCOM'){throw 'Не учтены полномочия SCOM вне AD'}
if($ctx.PSObject.Properties['GPORegistrySetting'].Value.secureMessage -notmatch 'НЕ получают оценку'){throw 'Не учтены неизвестные параметры GPO'}
Write-Host "PASS: 94/94 сообщений безопасного состояния и оговорки о неполноте проверки" -ForegroundColor Green
