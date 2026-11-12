#Requires -Version 5.1
<#
.SYNOPSIS
    Различает полное покрытие русскими описаниями и точный перевод исходных полей.
.DESCRIPTION
    Offline: проверяет структуру 392 FindingId относительно исходных списков.
    Не читает отчёты пользователей и не обращается к Active Directory.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$manifest=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/PinnedOriginalFindingFieldCounts.2.9.0.json'),[Text.Encoding]::UTF8))
$ids=@()
foreach($name in @('Findings-Titles-01.ru-RU.json','Findings-Titles-02.ru-RU.json','Findings-Titles-03.ru-RU.json','Findings-Titles-04.ru-RU.json')){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($p in $cat.PSObject.Properties){$ids+=([string]$p.Name)}
}
if($ids.Count -ne 392 -or @($ids | Sort-Object -Unique).Count -ne 392){throw 'Нет 392 уникальных заголовков'}
[Array]::Sort($ids,[StringComparer]::Ordinal)
$sha=[Security.Cryptography.SHA256]::Create()
try{
 $bytes=[Text.Encoding]::UTF8.GetBytes(($ids -join [char]10))
 $idHash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
}finally{$sha.Dispose()}
if($idHash -ne [string]$manifest.findingIdsSha256){throw 'FindingId отличаются от закреплённого оригинала'}
foreach($field in @('impact','attack','remediation')){
 if(([string]$manifest.countsHex.$field).Length -ne 392){throw "Некорректный оригинальный перечень: $field"}
}
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$mark='const ruFullFindingTechnical = '
$start=$js.IndexOf($mark,[StringComparison]::Ordinal)
if($start -lt 0){throw 'Не найден встроенный русский словарь'}
$start+=$mark.Length
$last=$js.IndexOf([char]10,$start)
if($last -lt 0){throw 'Не найдена граница встроенного русского словаря'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($start,$last-$start).Trim().TrimEnd([char]';'))
$original=@{impact=0;attack=0;remediation=0}
$russian=@{impact=0;attack=0;remediation=0}
$missing=@()
$unexpected=@()
$drift=@()
$sourceMissingImpact=0
$sourceMissingRemediation=0
$impactStepDrifts=@()
$remediationStepDrifts=@()
$rows=@()
for($i=0;$i -lt $ids.Count;$i++){
 $id=$ids[$i]
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "Русский перевод отсутствует: $id"}
 $value=$entry.Value
 $en=@{}
 $translated=@{}
 foreach($field in @('impact','attack','remediation')){
  $en[$field]=[Convert]::ToInt32(([string]$manifest.countsHex.$field).Substring($i,1),16)
  $translated[$field]=if($null -eq $value.$field){0}else{@($value.$field).Count}
  if($en[$field] -gt 0){$original[$field]++}
  if($translated[$field] -gt 0){$russian[$field]++}
 }
 if($en.attack -gt 0 -and $translated.attack -eq 0){$missing+=($id)}
 if($en.attack -eq 0 -and $translated.attack -gt 0){$unexpected+=($id)}
 if($en.attack -gt 0 -and $translated.attack -gt 0 -and $en.attack -ne $translated.attack){$drift+=($id)}
 if($en.impact -gt 0 -and $translated.impact -ne $en.impact){$impactStepDrifts+=($id)}
 if($en.remediation -gt 0 -and $translated.remediation -ne $en.remediation){$remediationStepDrifts+=($id)}
 if($en.impact -eq 0 -and $translated.impact -gt 0){$sourceMissingImpact++}
 if($en.remediation -eq 0 -and $translated.remediation -gt 0){$sourceMissingRemediation++}
 $rows+=([pscustomobject]@{
  FindingId=$id;ImpactEN=$en.impact;ImpactRU=$translated.impact
  AttackEN=$en.attack;AttackRU=$translated.attack
  RemediationEN=$en.remediation;RemediationRU=$translated.remediation
 })
}
if($original.attack -ne 304 -or $original.impact -ne 377 -or $original.remediation -ne 377){
 throw 'Исходный справочник не соответствует закреплённым количествам'
}
if($russian.attack -ne 304){throw "Ожидалось 304 русских Attack, найдено $($russian.attack)"}
if($missing.Count -ne 0){throw "Ожидалось 0 непереведённых Attack, найдено $($missing.Count)"}
if($unexpected.Count -ne 0){throw "Обнаружен вымышленный Attack: $($unexpected -join ', ')"}
if($drift.Count -ne 0){throw "Переведённые Attack имеют расхождения числа пунктов: $($drift -join ', ')"}
$result=[ordered]@{
 Schema='adPEAS-RU.SourceFieldParity392.1'
 FindingCount=392
 SourceNonempty=$original
 RussianNonempty=$russian
 MissingRussianAttackCount=$missing.Count
 MissingRussianAttackIds=@($missing)
 OriginalAttackAbsentCount=88
 AttackStepCountDifferences=@($drift)
 ImpactStepCountDifferences=@($impactStepDrifts)
 RemediationStepCountDifferences=@($remediationStepDrifts)
 RussianImpactWithNoSource=$sourceMissingImpact
 RussianRemediationWithNoSource=$sourceMissingRemediation
 Note='Все 304 Attack имеют русский текст; последние 112 снабжены буквальными EN-свидетелями с проверкой исходника. 54 приоритетных Impact/Remediation сверены построчно; совпадение количества пунктов остальных не доказывает смысловую точность.'
 UserReportDataIncluded=$false
 Fields=@($rows)
}
$out=Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'
[IO.File]::WriteAllText($out,(ConvertTo-Json -InputObject $result -Depth 8),(New-Object Text.UTF8Encoding($true)))
Write-Host "PASS: EN Impact=$($original.impact), Attack=$($original.attack), Remediation=$($original.remediation); RU Attack=$($russian.attack), осталось=$($missing.Count), вымышленных=0" -ForegroundColor Green
