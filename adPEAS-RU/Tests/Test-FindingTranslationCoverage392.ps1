#Requires -Version 5.1
<#
.SYNOPSIS
    Контроль 392 русских описаний находок на Windows PowerShell 5.1.
.DESCRIPTION
    Offline. Не открывает пользовательские HTML-отчёты и не подключается к AD.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
function Read-Catalog([string]$Name){
 $path=Join-Path $ProjectRoot ('Localization/'+$Name)
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Нет каталога $Name"}
 return ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8))
}
$titles=@{}
foreach($name in @('Findings-Titles-01.ru-RU.json','Findings-Titles-02.ru-RU.json','Findings-Titles-03.ru-RU.json','Findings-Titles-04.ru-RU.json')){
 $obj=Read-Catalog $name
 foreach($entry in $obj.PSObject.Properties){
  if($titles.ContainsKey($entry.Name)){throw "Повторяющийся заголовок: $($entry.Name)"}
  if([string]$entry.Value -notmatch '[А-Яа-яЁё]'){throw "Название не переведено: $($entry.Name)"}
  $titles[$entry.Name]=[string]$entry.Value
 }
}
$catalogNames=@('FullTechnical-01.ru-RU.json','FullTechnical-02.ru-RU.json',
 'FullTechnical-Report-03.ru-RU.json','FullTechnical-Report-04.ru-RU.json',
 'FullTechnical-Brief-05.ru-RU.json','FullTechnical-Catalog-06a.ru-RU.json',
 'FullTechnical-Catalog-06b.ru-RU.json','FullTechnical-Catalog-06c.ru-RU.json',
 'FullTechnical-Catalog-06d.ru-RU.json','FullTechnical-Catalog-06e.ru-RU.json')
$items=@{}
$translatedAttacks=0
foreach($name in $catalogNames){
 $obj=Read-Catalog $name
 foreach($entry in $obj.translations.PSObject.Properties){
  $id=$entry.Name
  if($items.ContainsKey($id)){throw "Дублируется FindingId: $id"}
  if(-not $titles.ContainsKey($id)){throw "Лишний FindingId: $id"}
  $v=$entry.Value
  if([string]::IsNullOrWhiteSpace([string]$v.description) -or [string]$v.description -notmatch '[А-Яа-яЁё]'){throw "Отсутствует русское описание: $id"}
  foreach($field in @('impact','remediation')){
   if(@($v.$field).Count -eq 0){throw "Не заполнено поле $field для $id"}
   foreach($line in $v.$field){
    if([string]::IsNullOrWhiteSpace([string]$line) -or [string]$line -notmatch '[А-Яа-яЁё]'){throw "Не переведён текст поля $field для $id"}
   }
  }
  if($null -eq $v.attack){throw "Нет массива сценариев attack для $id"}
  if(@($v.attack).Count -gt 0){$translatedAttacks++}
  $items[$id]=$name
 }
}
if($titles.Count -ne 392 -or $items.Count -ne 392){
 $missing=@($titles.Keys | Where-Object {-not $items.ContainsKey($_)})
 throw "Нарушен охват: заголовков $($titles.Count), описаний $($items.Count); нет: $($missing -join ', ')"
}
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
if(-not $js.Contains('const ruFullFindingTechnical = ')){throw 'Нет полного справочника в HTML-шаблоне'}
if($js.Contains('Исходное подробное описание EN (перевод пока не завершён)')){throw 'Устаревшая пометка EN'}
$result=[ordered]@{
 Schema='adPEAS-RU.FindingTranslationCoverage.392.1'
 CanonicalTitleCount=$titles.Count
 RussianDescriptionImpactRemediationCount=$items.Count
 RussianAttackCount=$translatedAttacks
 AttackNotTranslatedOrNotApplicable=($items.Count-$translatedAttacks)
 Ids=@($titles.Keys | Sort-Object)
 UserReportDataIncluded=$false
 Note='Непереведённые сценарии атак не обозначаются как завершённые.'
}
$out=Join-Path $ProjectRoot 'Localization/FindingTranslationCoverage392.json'
[IO.File]::WriteAllText($out,(ConvertTo-Json -InputObject $result -Depth 8),(New-Object Text.UTF8Encoding($true)))
Write-Host "PASS: 392/392 переводов описаний, последствий и рекомендаций; сценариев: $translatedAttacks; AD не затронут" -ForegroundColor Green
