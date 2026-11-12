#Requires -Version 5.1
<#
.SYNOPSIS
    Этап D1: покомпонентная проверка 77 новых переводов Attack.
.DESCRIPTION
    Проверяет точные английские пункты закреплённого источника и русский
    текст итогового HTML-словаря. Не подключается к Active Directory.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$src=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'),[Text.Encoding]::UTF8)
$src=$src.Replace(([string][char]13+[string][char]10),[string][char]10)
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$marker='const ruFullFindingTechnical = '
$start=$js.IndexOf($marker,[StringComparison]::Ordinal)
if($start -lt 0){throw 'Не найден встроенный русский словарь'}
$start+=$marker.Length
$stop=$js.IndexOf([char]10,$start)
if($stop -lt 0){throw 'Повреждена строка русского словаря'}
$compiled=ConvertFrom-Json -InputObject ($js.Substring($start,$stop-$start).Trim().TrimEnd([char]';'))
$count=0
$steps=0
$seen=@{}
foreach($name in @('SourceVerifiedAttack-10a.ru-RU.json','SourceVerifiedAttack-10b.ru-RU.json')){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 foreach($p in $catalog.translations.PSObject.Properties){
  $id=[string]$p.Name
  if($seen.ContainsKey($id)){throw "Дублируется $id"}
  $seen[$id]=$true
  $v=$p.Value
  $needle="    '$id' = @{"
  $begin=$src.IndexOf($needle,[StringComparison]::Ordinal)
  if($begin -lt 0){throw "Нет исходной находки $id"}
  $end=$src.IndexOf(([string][char]10+'    }'),$begin,[StringComparison]::Ordinal)
  if($end -lt 0){throw "Нет окончания исходной находки $id"}
  $block=$src.Substring($begin,$end-$begin)
  $match=[regex]::Match($block,'(?ms)^[ \t]{8}Attack[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)')
  if(-not $match.Success){throw "Отсутствует Attack оригинала $id"}
  $original=@([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') | ForEach-Object { $_.Groups['value'].Value })
  $english=@($v.sourceEnglishAttack)
  $russian=@($v.attack)
  $embedded=$compiled.PSObject.Properties[$id]
  if($null -eq $embedded){throw "Нет перевода в итоговом HTML: $id"}
  $rendered=@($embedded.Value.attack)
  $n=[int]$v.sourceEnglishAttackStepCount
  if($original.Count -ne $n -or $english.Count -ne $n -or $russian.Count -ne $n -or $rendered.Count -ne $n){
   throw "Пропущены пункты: $id, исходных=$($original.Count), EN=$($english.Count), RU=$($russian.Count), HTML=$($rendered.Count)"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$english[$i]){throw "Оригинальный пункт изменён: $id №$($i+1)"}
   if([string]$russian[$i] -cne [string]$rendered[$i]){throw "Пункт изменён в HTML: $id №$($i+1)"}
   if([string]$russian[$i] -notmatch '[А-Яа-яЁё]'){throw "Пункт не переведён: $id №$($i+1)"}
  }
  $count++
  $steps+=$n
 }
}
if($count -ne 77 -or $steps -ne 272){throw "Ожидалось 77 разделов и 272 пункта, получено $count/$steps"}
# У ESC_ENROLLMENT_RIGHTS_UNREAD исходное диагностическое пояснение
# пронумеровано как три шага — нумерацию оригинала нельзя удалять.
$meaningChecks=@{
 ACCOUNT_NOT_DELEGATED='нарушитель не может'
 BLOODHOUND_COLLECTION_COMPLETE='защитный инструмент'
 ESC_ENROLLMENT_RIGHTS_UNREAD='Само по себе это не атака'
 ENROLLMENT_REQUIRES_APPROVAL='нарушители не могут'
}
foreach($id in $meaningChecks.Keys){
 $x=($compiled.PSObject.Properties[$id].Value.attack -join ' ')
 if($x -notmatch [regex]::Escape([string]$meaningChecks[$id])){
  throw "Утерян смысл защитного или диагностического пояснения: $id"
 }
}
Write-Host 'PASS Stage D1: 77 новых разделов Attack и 272 пункта точно связаны с EN-оригиналом' -ForegroundColor Green
