#Requires -Version 5.1
<#
.SYNOPSIS
    Автономная построчная проверка 20 переводов Impact/Remediation этапа D4.
.DESCRIPTION
    Сопоставляет исходный adPEAS 2.9.0, русский каталог и HTML-словарь.
    Не подключается к AD и не запускает команды исправления.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'),[Text.Encoding]::UTF8)
$source=$source.Replace(([string][char]13+[string][char]10),[string][char]10)
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-13.ru-RU.json'),[Text.Encoding]::UTF8))
$javascript=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$marker='const ruFullFindingTechnical = '
$start=$javascript.IndexOf($marker,[StringComparison]::Ordinal)
if($start -lt 0){throw 'D4: нет итогового русского HTML-словаря'}
$start+=$marker.Length
$end=$javascript.IndexOf([char]10,$start)
if($end -lt 0){throw 'D4: неверная граница HTML-словаря'}
$ru=ConvertFrom-Json -InputObject ($javascript.Substring($start,$end-$start).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D4: ожидалось 392 находки в HTML'}
if(@($catalog.translations.PSObject.Properties).Count -ne 20){throw 'D4: ожидалось 14 переводов'}
$expectedIds=@(
 'CONSTRAINED_DELEGATION_PROTOCOL_TRANSITION','CONSTRAINED_DELEGATION_TO_DC',
 'CONSTRAINED_DELEGATION_TRANSITION_NO_TARGET','RBCD_DANGEROUS_PRINCIPALS',
 'DANGEROUS_ACL_BROAD_GROUP','DANGEROUS_ACL_GENERICWRITE','DANGEROUS_ACL_WRITEDACL',
 'DANGEROUS_ACL_WRITEOWNER','ESC2_TEMPLATE','ESC3_TEMPLATE','ESC4_TEMPLATE',
 'ESC14_WEAK_EXPLICIT_MAPPING','ESC15_SCHEMA_V1_ENROLLEE_SUBJECT',
 'GPO_DANGEROUS_PERMISSIONS','GPO_LOCAL_GROUP_RISKY_MEMBER',
 'GPO_NOT_CURRENTLY_EFFECTIVE','GPO_UNLINKED_BROAD_WRITE',
 'GPO_TASK_SYSTEM_UNC_PATH','ESC_ENROLLMENT_RIGHTS_UNREAD','GPO_WIDE_IMPACT'
)
$actualIds=@($catalog.translations.PSObject.Properties | ForEach-Object {$_.Name} | Sort-Object)
$sortedExpected=@($expectedIds | Sort-Object)
if(($actualIds -join [char]10) -cne ($sortedExpected -join [char]10)){
 throw 'D4: изменён закреплённый набор из 20 FindingId'
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D4: полные переводы не отражены в сводной статистике: $id"
 }
}
function Get-OriginalItems([string]$id,[string]$field){
 $begin=$source.IndexOf(("    '"+$id+"' = @{"),[StringComparison]::Ordinal)
 if($begin -lt 0){throw "D4: отсутствует FindingId в оригинале $id"}
 $finish=$source.IndexOf(([string][char]10+'    }'),$begin,[StringComparison]::Ordinal)
 if($finish -lt 0){throw "D4: нет закрывающего блока $id"}
 $block=$source.Substring($begin,$finish-$begin)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D4: отсутствует $field для $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') | ForEach-Object { $_.Groups['value'].Value })
}
$totalImpact=0
$totalRemediation=0
$ids=@{}
foreach($row in $catalog.translations.PSObject.Properties){
 $id=[string]$row.Name
 if($ids.ContainsKey($id)){throw "D4: повторный FindingId $id"}
 $ids[$id]=$true
 $translatedEntry=$ru.PSObject.Properties[$id]
 if($null -eq $translatedEntry){throw "D4: русский HTML не содержит $id"}
 foreach($field in @('Impact','Remediation')){
  $lower=$field.ToLowerInvariant()
  $enProperty='sourceEnglish'+$field
  $countProperty=$enProperty+'Count'
  $sourceItems=@(Get-OriginalItems $id $field)
  $witness=@($row.Value.$enProperty)
  $russian=@($row.Value.$lower)
  $shown=@($translatedEntry.Value.$lower)
  $expected=[int]$row.Value.$countProperty
  if($expected -le 0 -or $expected -ne $sourceItems.Count -or
     $expected -ne $witness.Count -or $expected -ne $russian.Count -or
     $expected -ne $shown.Count){
   throw "D4: число пунктов не совпадает: $id / $field"
  }
  for($i=0;$i -lt $expected;$i++){
   if([string]$sourceItems[$i] -cne [string]$witness[$i]){
    throw "D4: изменён исходный английский пункт $id / $field / $($i+1)"
   }
   if([string]$russian[$i] -cne [string]$shown[$i]){
    throw "D4: русский пункт не совпадает с HTML $id / $field / $($i+1)"
   }
   if([string]$russian[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D4: отсутствует русская формулировка $id / $field / $($i+1)"
   }
  }
  if($field -eq 'Impact'){$totalImpact+=$expected}else{$totalRemediation+=$expected}
 }
}
if($ids.Count -ne 20 -or $totalImpact -ne 75 -or $totalRemediation -ne 77){
 throw "D4: неверные итоги $($ids.Count), $totalImpact, $totalRemediation"
}
$checks=@{
 GPO_NOT_CURRENTLY_EFFECTIVE='Сейчас непосредственного воздействия нет'
 ESC_ENROLLMENT_RIGHTS_UNREAD='нельзя, но и исключить'
 DANGEROUS_ACL_WRITEDACL='WriteDACL само по себе не разрешает изменять SACL'
 GPO_DANGEROUS_PERMISSIONS='Event ID 4663'
 GPO_WIDE_IMPACT='MS16-072'
 CONSTRAINED_DELEGATION_TO_DC='msDS-AllowedToDelegateTo'
 ESC15_SCHEMA_V1_ENROLLEE_SUBJECT='CVE-2024-49019'
 ESC14_WEAK_EXPLICIT_MAPPING='altSecurityIdentities'
}
foreach($id in $checks.Keys){
 $item=$ru.PSObject.Properties[$id]
 $shown=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($shown -notmatch [regex]::Escape([string]$checks[$id])){
  throw "D4: потерян существенный технический нюанс у $id"
 }
}
if(@($parity.ImpactStepCountDifferences).Count -ne 273 -or
   @($parity.RemediationStepCountDifferences).Count -ne 253){
 throw 'D4: итоговая статистика полей не соответствует 273/253'
}
Write-Host "PASS D4: 20 находок, 75 Impact + 77 Remediation; EN-свидетели и HTML совпадают" -ForegroundColor Green
