#Requires -Version 5.1
<#
.SYNOPSIS
    Аудит всех источников текста отчёта и регрессионные проверки RU.
.DESCRIPTION
    Складывает в JSON потенциально не переведённые выводимые Show-Line/Show-Header
    из всех модулей adPEAS. Остаток отмечается, но не скрывается.
    Не подключается к AD и не меняет объекты домена.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
function Read-Text([string]$Relative) {
 [IO.File]::ReadAllText((Join-Path $ProjectRoot $Relative),[Text.Encoding]::UTF8)
}
$src=Join-Path $ProjectRoot 'src/modules'
$files=@(Get-ChildItem -LiteralPath $src -File -Recurse -Filter '*.ps1')
$checkFiles=@($files | Where-Object { $_.FullName -match '[\\/]Checks[\\/]' })
if($files.Count -lt 190 -or $checkFiles.Count -lt 50) {
 throw "Часть источников отчёта отсутствует: всего $($files.Count), проверок $($checkFiles.Count)"
}
$gpo=Read-Text 'src/modules/Checks/GPO/Get-GPOPermissions.ps1'
$group=Read-Text 'src/modules/Checks/Accounts/Get-PrivilegedGroupMembers.ps1'
$render=Read-Text 'src/modules/Core/Render-HtmlObject.ps1'
$export=Read-Text 'src/modules/Reporting/Export-HTMLReport.ps1'
$javascript=Read-Text 'src/modules/Reporting/templates/report-scripts.js'
$labels=ConvertFrom-Json -InputObject (Read-Text 'Localization/AttributeLabels.ru-RU.json')
foreach($needle in @(
 'Обнаружено GPO с опасными разрешениями',
 'только из-за владельца:',
 'папки политики доступны для записи'
)){
 if(-not $gpo.Contains($needle)){throw "Не переведён результат проверки GPO: $needle"}
}
foreach($needle in @(
 'Привилегированные группы вне защиты AdminSDHolder:',
 'Группа Account Operators$aoMembers по умолчанию',
 'нет участников',
 'из $($examinedGroups.Count)',
 'из $examinedAccounts'
)){
 if(-not $group.Contains($needle)){throw "Не переведён результат привилегированных групп: $needle"}
}
if(-not $group.Contains("WriteProperty on member - may add a member to every protected group")){
 throw 'Изменены исходные технические значения ACL: запрещено'
}
foreach($needle in @('ruTranslateVisibleText','ruReportDisplay','window.adPEASRUReportAudit')){
 if(-not $javascript.Contains($needle)){throw "Не реализован перевод отображения HTML: $needle"}
}
foreach($name in @('GPOName','GPOGUID','GPOPath','DangerousPermissions','LinkedOUs','dangerousRights','distinguishedName')){
 if(-not $labels.PSObject.Properties[$name]){throw "Не переведено имя поля: $name"}
}
if($render.Contains('Drag to reorder') -or $export.Contains('Mark as completed')){
 throw 'В HTML остались непереведённые подсказки управления карточками'
}
if(-not $render.Contains('Перетащите для изменения порядка')){throw 'Не найдена русская подсказка изменения порядка'}
if(-not $javascript.Contains('WriteProperty на member')){throw 'Не переведены пояснения к правам WriteProperty в отображении'}
if(-not (Test-Path (Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-template.html'))){
 throw 'Шаблон отчёта отсутствует'
}
if(-not (Test-Path (Join-Path $ProjectRoot 'src/modules/Reporting/templates/diff-template.html'))){
 throw 'Шаблон сравнения отчётов отсутствует'
}
# Выявляем потенциальные остатки — предупреждаем, не выдаём их за переведённые.
$items=@()
foreach($file in $files){
 $lineNum=0
 foreach($line in [IO.File]::ReadAllLines($file.FullName,[Text.Encoding]::UTF8)){
  $lineNum++
  if($line -notmatch '\bShow-(Line|SubHeader|Header)\b'){continue}
  if($line -match '[А-Яа-яЁё]'){continue}
  $candidateMatch=[regex]::Match($line,'Show-(Line|SubHeader|Header)\s+(?:\(\s*)?"([^"]*[A-Za-z]{4,}[^"]*)"')
  if(-not $candidateMatch.Success){continue}
  $value=[string]$candidateMatch.Groups[2].Value
  if($value -match '^\s*\$'){continue}
  $shortPath=$file.FullName.Substring($ProjectRoot.Length).TrimStart([char]'\',[char]'/')
  $items += [pscustomobject]@{File=$shortPath;Line=$lineNum;Text=$value}
 }
}
$result=[ordered]@{
 Schema='adPEAS-RU-2.9.0.ReportSourceInventory.1'
 TotalModuleFiles=$files.Count
 CheckFiles=$checkFiles.Count
 ReportingTemplates=@('report-template.html','diff-template.html','report-scripts.js','report-styles.css')
 UntranslatedCandidateCount=$items.Count
 UntranslatedCandidates=@($items)
 Note='Эвристический список: технические имена, команды и переменные могут давать ложные совпадения. Неизвестные строки не переводятся автоматически.'
}
$json=ConvertTo-Json -InputObject $result -Depth 7
$out=Join-Path $ProjectRoot 'Localization/ReportLocalizationAudit.json'
[IO.File]::WriteAllText($out,$json,(New-Object Text.UTF8Encoding($true)))
Write-Host "PASS: проверены $($files.Count) PowerShell-модулей, $($checkFiles.Count) файлов проверок и шаблоны HTML"
Write-Host "PASS: строки GPO, AdminSDHolder, подписи таблиц, ACL и управление карточками локализованы"
Write-Host "AUDIT: найдено $($items.Count) потенциально непереведённых строк; список: $out"
