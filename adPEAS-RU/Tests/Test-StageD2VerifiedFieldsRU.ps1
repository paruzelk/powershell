#Requires -Version 5.1
<#
.SYNOPSIS
    Offline-контроль Stage D2: 112 Attack и 10 полных Impact/Remediation.
.DESCRIPTION
    Оригинальные английские пункты, русский каталог и собранный HTML
    сравниваются один к одному. Подключения к AD отсутствуют.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$src=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'),[Text.Encoding]::UTF8)
$src=$src.Replace(([string][char]13+[string][char]10),[string][char]10)
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$marker='const ruFullFindingTechnical = '
$start=$js.IndexOf($marker,[StringComparison]::Ordinal)
if($start -lt 0){throw 'Нет итогового русского словаря находок'}
$start+=$marker.Length
$stop=$js.IndexOf([char]10,$start)
if($stop -lt 0){throw 'Неверный формат словаря'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($start,$stop-$start).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'Неверное число FindingId'}
function Get-ENItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $begin=$src.IndexOf($needle,[StringComparison]::Ordinal)
 if($begin -lt 0){throw "FindingId отсутствует в оригинале: $id"}
 $end=$src.IndexOf(([string][char]10+'    }'),$begin,[StringComparison]::Ordinal)
 if($end -lt 0){throw "Нет конца блока: $id"}
 $block=$src.Substring($begin,$end-$begin)
 $regex='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $m=[regex]::Match($block,$regex)
 if(-not $m.Success){throw "Исходное поле отсутствует: $id / $field"}
 return @([regex]::Matches($m.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') | ForEach-Object { $_.Groups['value'].Value })
}
function Test-ExactField([string]$id,[string]$field,$english,$russian,[int]$expected){
 $fromSource=@(Get-ENItems $id $field)
 $shownField=$field.ToLowerInvariant()
 $found=$ru.PSObject.Properties[$id]
 if($null -eq $found){throw "Отсутствует итоговый перевод: $id"}
 $shown=@($found.Value.$shownField)
 if($expected -ne $fromSource.Count -or $expected -ne @($english).Count -or
    $expected -ne @($russian).Count -or $expected -ne $shown.Count){
  throw "Пропущены пункты: $id / $field"
 }
 for($i=0;$i -lt $expected;$i++){
  if([string]$fromSource[$i] -cne [string]$english[$i]){throw "Оригинальный EN изменён: $id / $field, пункт $($i+1)"}
  if([string]$shown[$i] -cne [string]$russian[$i]){throw "Различается RU и HTML: $id / $field, пункт $($i+1)"}
  if([string]$russian[$i] -notmatch '[А-Яа-яЁё]'){throw "Нет русского пункта: $id / $field, пункт $($i+1)"}
 }
}
$attackCount=0;$attackSteps=0;$seen=@{}
foreach($name in @('SourceVerifiedAttack-11a.ru-RU.json','SourceVerifiedAttack-11b.ru-RU.json',
                   'SourceVerifiedAttack-11c.ru-RU.json','SourceVerifiedAttack-11d.ru-RU.json')){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($p in $cat.translations.PSObject.Properties){
  $id=[string]$p.Name
  if($seen.ContainsKey($id)){throw "Дублирование Attack: $id"}
  $seen[$id]=$true
  $v=$p.Value
  $n=[int]$v.sourceEnglishAttackStepCount
  Test-ExactField $id 'Attack' $v.sourceEnglishAttack $v.attack $n
  $attackSteps+=$n;$attackCount++
 }
}
if($attackCount -ne 112 -or $attackSteps -ne 380){throw "Неверный состав Attack D2: $attackCount / $attackSteps"}
$core=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-11.ru-RU.json'),[Text.Encoding]::UTF8))
$coreCount=0;$impactSteps=0;$remediationSteps=0
foreach($p in $core.translations.PSObject.Properties){
 $id=[string]$p.Name
 $v=$p.Value
 Test-ExactField $id 'Impact' $v.sourceEnglishImpact $v.impact ([int]$v.sourceEnglishImpactCount)
 Test-ExactField $id 'Remediation' $v.sourceEnglishRemediation $v.remediation ([int]$v.sourceEnglishRemediationCount)
 $coreCount++
 $impactSteps+=[int]$v.sourceEnglishImpactCount
 $remediationSteps+=[int]$v.sourceEnglishRemediationCount
}
if($coreCount -ne 10 -or $impactSteps -ne 38 -or $remediationSteps -ne 41){
 throw "Неполная сверка полей D2: $coreCount / $impactSteps / $remediationSteps"
}
$ruAttacks=@($ru.PSObject.Properties | Where-Object { @($_.Value.attack).Count -gt 0 }).Count
if($ruAttacks -ne 304){throw "Attack переведены не полностью: $ruAttacks / 304"}
$protect=@{
 LDAP_CHANNEL_BINDING_ALWAYS='нарушитель не может'
 LDAP_SIGNING_REQUIRED='нарушитель не может'
 SMARTCARD_REQUIRED='нарушитель не может'
 GPO_USERRIGHT_DEFAULT_REMOVED='Это не путь атаки'
 LAPS_COVERAGE_NOT_IN_AD='Из самого этого состояния'
 PKI_STRONG_KEY_LENGTH='нарушитель не может'
}
foreach($id in $protect.Keys){
 if((@($ru.PSObject.Properties[$id].Value.attack) -join ' ') -notmatch [regex]::Escape([string]$protect[$id])){
  throw "Потерян смысл защитного или информационного состояния: $id"
 }
}
Write-Host "PASS D2: 112 Attack/380 пунктов и 10 Impact/Remediation (38+41) сопоставлены с оригиналом; всего Attack 304/304" -ForegroundColor Green
