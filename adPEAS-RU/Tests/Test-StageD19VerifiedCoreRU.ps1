#Requires -Version 5.1
<#
.SYNOPSIS
    D19: завершающая независимая сверка 15 FindingId, включая 29 отсутствующих полей.
.DESCRIPTION
    Проверяет именно отсутствие Impact/Remediation в закреплённом EN,
    не выдумывает строки и подтверждает единственную рекомендацию AES.
    Сверяет 392 элемента русской HTML-модели без контакта с AD.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'),[Text.Encoding]::UTF8)
$source=$source.Replace(([string][char]13+[string][char]10),[string][char]10)
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$marker='const ruFullFindingTechnical = '
$begin=$js.IndexOf($marker,[StringComparison]::Ordinal)
if($begin -lt 0){throw 'D19: полный русский словарь не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D19: не найдена граница JSON словаря'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D19: требуется ровно 392 FindingId в русском HTML'}
$expectedIds=@(
 'ADCS_CA_CROSS_DOMAIN',
 'CREDENTIAL_MATCHED_LINE',
 'CREDENTIAL_PASSWORD_EXPOSED',
 'CREDENTIAL_TYPE_INFO',
 'CREDENTIAL_USERNAME_EXPOSED',
 'GPO_LINKED_OUS_SEVERITY',
 'GPO_SCOPE_SEVERITY',
 'GPO_TASK_FIELD_SEVERITY',
 'KERBEROASTABLE_USER_SPN',
 'META_SEVERITY_PASSTHROUGH',
 'META_STATUS_INDICATOR',
 'NON_DEFAULT_OWNER',
 'UAC_SEVERITY_OVERRIDE',
 'WEB_ENDPOINT_SECURITY',
 'ENCRYPTION_AES_ONLY'
)
$catalogCounts=@{'SourceVerifiedCore-28a.ru-RU.json'=8;'SourceVerifiedCore-28b.ru-RU.json'=7}
$all=@{}
foreach($name in @('SourceVerifiedCore-28a.ru-RU.json','SourceVerifiedCore-28b.ru-RU.json')){
 $cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$name)),[Text.Encoding]::UTF8))
 if(@($cat.translations.PSObject.Properties).Count -ne $catalogCounts[$name]){
  throw "D19: неверное число записей в $name"
 }
 foreach($row in $cat.translations.PSObject.Properties){
  $id=[string]$row.Name
  if($all.ContainsKey($id)){throw "D19: повтор FindingId $id"}
  $all[$id]=$row.Value
 }
}
$actualIds=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 15 -or ($actualIds -join [char]10) -cne ($expected -join [char]10)){
 throw 'D19: набор 15 FindingId не соответствует ожидаемому'
}
function Get-OriginalFieldWitness([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D19: отсутствует оригинал $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D19: нет конца блока оригинала $id"}
 $block=$source.Substring($start,$stop-$start)
 $declared=[regex]::IsMatch($block,'(?m)^[ \t]{8}'+$field+'[ \t]*=')
 $values=@()
 if($declared){
  $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
  $match=[regex]::Match($block,$expression)
  if($match.Success){
   $values=@([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
     ForEach-Object {$_.Groups['value'].Value})
  }else{
   $emptyRe='(?m)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\(\)[ \t]*$'
   if(-not [regex]::IsMatch($block,$emptyRe)){throw "D19: не удалось разобрать исходное $field у $id"}
  }
 }
 return [pscustomobject]@{Declared=$declared;Items=@($values)}
}
$absent=0
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D19: русский HTML не содержит $id"}
 if([string]$entry.Value.description -notmatch '[А-Яа-яЁё]'){
  throw "D19: нет русского описания $id"
 }
 foreach($field in @('Impact','Remediation')){
  $lower=$field.ToLowerInvariant()
  $enField='sourceEnglish'+$field
  $countField=$enField+'Count'
  $declaredField=$enField+'Declared'
  if($null -eq $all[$id].PSObject.Properties[$declaredField]){
   throw "D19: нет свидетельства наличия оригинального поля $id / $field"
  }
  $witness=Get-OriginalFieldWitness $id $field
  $expectedDeclared=[bool]$all[$id].$declaredField
  if($witness.Declared -ne $expectedDeclared){
   throw "D19: изменён факт наличия Impact/Remediation в оригинале $id / $field"
  }
  $original=@($witness.Items)
  $english=@($all[$id].$enField)
  $translated=@($all[$id].$lower)
  $shown=@($entry.Value.$lower)
  $n=[int]$all[$id].$countField
  if($n -ne $original.Count -or $n -ne $english.Count -or $n -ne $translated.Count -or $n -ne $shown.Count){
   throw "D19: нарушено соответствие EN/RU/HTML у $id / $field"
  }
  if(-not $witness.Declared){
   if($n -ne 0){throw "D19: выдумано содержимое отсутствующего поля $id / $field"}
   $absent++
  }elseif($id -cne 'ENCRYPTION_AES_ONLY' -or $field -cne 'Remediation' -or $n -ne 1){
   throw "D19: неожиданное исходное содержимое $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$english[$i]){throw "D19: изменён EN $id / $field / $($i+1)"}
   if([string]$translated[$i] -cne [string]$shown[$i]){throw "D19: каталог не совпадает с HTML $id / $field / $($i+1)"}
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){throw "D19: отсутствует русский пункт $id / $field / $($i+1)"}
  }
  $totals[$field]+=$n
 }
}
if($absent -ne 29 -or $totals.Impact -ne 0 -or $totals.Remediation -ne 1){
 throw "D19: итог должен быть 29 отсутствующих полей, Impact=0, Remediation=1; сейчас $absent, $($totals.Impact), $($totals.Remediation)"
}
$aes=$ru.PSObject.Properties['ENCRYPTION_AES_ONLY'].Value
if([string]$aes.remediation[0] -notmatch 'Исправление не требуется' -or [string]$aes.remediation[0] -notmatch 'AES'){
 throw 'D19: потеряна безопасная семантика AES-only'
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
if([int]$parity.FindingCount -ne 392 -or @($parity.AttackStepCountDifferences).Count -ne 0 -or
   @($parity.ImpactStepCountDifferences).Count -ne 0 -or
   @($parity.RemediationStepCountDifferences).Count -ne 0 -or
   [int]$parity.MissingRussianAttackCount -ne 0){
 throw 'D19: общий структурный паритет 392 находок нарушен'
}
Write-Host 'PASS D19: 15 находок, 29 исходно отсутствующих полей и 1 AES Remediation; 392 FindingId; EN/RU/HTML паритет' -ForegroundColor Green
