#Requires -Version 5.1
<#
.SYNOPSIS
    Автономная построчная проверка 14 переводов Impact/Remediation этапа D3.
.DESCRIPTION
    Сопоставляет исходный adPEAS 2.9.0, русский каталог и HTML-словарь.
    Не подключается к AD и не запускает команды исправления.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'),[Text.Encoding]::UTF8)
$source=$source.Replace(([string][char]13+[string][char]10),[string][char]10)
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-12.ru-RU.json'),[Text.Encoding]::UTF8))
$javascript=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$marker='const ruFullFindingTechnical = '
$start=$javascript.IndexOf($marker,[StringComparison]::Ordinal)
if($start -lt 0){throw 'D3: нет итогового русского HTML-словаря'}
$start+=$marker.Length
$end=$javascript.IndexOf([char]10,$start)
if($end -lt 0){throw 'D3: неверная граница HTML-словаря'}
$ru=ConvertFrom-Json -InputObject ($javascript.Substring($start,$end-$start).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D3: ожидалось 392 находки в HTML'}
if(@($catalog.translations.PSObject.Properties).Count -ne 14){throw 'D3: ожидалось 14 переводов'}
$expectedIds=@(
 'ACCOUNT_DISABLED','ACCOUNT_NOT_DELEGATED','ACL_INHERITED_FROM',
 'ADMIN_COUNT_INDICATOR','AD_RECYCLE_BIN_DISABLED','DOMAIN_ROOT_GPLINK_WRITE',
 'DSRM_PASSWORD_UNMANAGED','ENCRYPTION_NOT_CONFIGURED','ENCRYPTION_RC4_ONLY',
 'GUEST_ACCOUNT_ENABLED','LDAP_ANONYMOUS_BINDING_ALLOWED',
 'LOCKOUT_DURATION_FOREVER','NO_MAX_PASSWORD_AGE','PASSWORD_HISTORY_DISABLED'
)
$actualIds=@($catalog.translations.PSObject.Properties | ForEach-Object {$_.Name} | Sort-Object)
$sortedExpected=@($expectedIds | Sort-Object)
if(($actualIds -join [char]10) -cne ($sortedExpected -join [char]10)){
 throw 'D3: изменён закреплённый набор из 14 FindingId'
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D3: полные переводы не отражены в сводной статистике: $id"
 }
}
function Get-OriginalItems([string]$id,[string]$field){
 $begin=$source.IndexOf(("    '"+$id+"' = @{"),[StringComparison]::Ordinal)
 if($begin -lt 0){throw "D3: отсутствует FindingId в оригинале $id"}
 $finish=$source.IndexOf(([string][char]10+'    }'),$begin,[StringComparison]::Ordinal)
 if($finish -lt 0){throw "D3: нет закрывающего блока $id"}
 $block=$source.Substring($begin,$finish-$begin)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D3: отсутствует $field для $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') | ForEach-Object { $_.Groups['value'].Value })
}
$totalImpact=0
$totalRemediation=0
$ids=@{}
foreach($row in $catalog.translations.PSObject.Properties){
 $id=[string]$row.Name
 if($ids.ContainsKey($id)){throw "D3: повторный FindingId $id"}
 $ids[$id]=$true
 $translatedEntry=$ru.PSObject.Properties[$id]
 if($null -eq $translatedEntry){throw "D3: русский HTML не содержит $id"}
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
   throw "D3: число пунктов не совпадает: $id / $field"
  }
  for($i=0;$i -lt $expected;$i++){
   if([string]$sourceItems[$i] -cne [string]$witness[$i]){
    throw "D3: изменён исходный английский пункт $id / $field / $($i+1)"
   }
   if([string]$russian[$i] -cne [string]$shown[$i]){
    throw "D3: русский пункт не совпадает с HTML $id / $field / $($i+1)"
   }
   if([string]$russian[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D3: отсутствует русская формулировка $id / $field / $($i+1)"
   }
  }
  if($field -eq 'Impact'){$totalImpact+=$expected}else{$totalRemediation+=$expected}
 }
}
if($ids.Count -ne 14 -or $totalImpact -ne 46 -or $totalRemediation -ne 43){
 throw "D3: неверные итоги $($ids.Count), $totalImpact, $totalRemediation"
}
$checks=@{
 ACCOUNT_NOT_DELEGATED='CVE-2020-17049'
 AD_RECYCLE_BIN_DISABLED='отключить её нельзя'
 ADMIN_COUNT_INDICATOR='наследование разрешений'
 ENCRYPTION_NOT_CONFIGURED='Hint'
 LOCKOUT_DURATION_FOREVER='исправление не требуется'
 DSRM_PASSWORD_UNMANAGED='BackupDsrmPassword'
 LDAP_ANONYMOUS_BINDING_ALLOWED='седьмой символ'
}
foreach($id in $checks.Keys){
 $item=$ru.PSObject.Properties[$id]
 $text=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($text -notmatch [regex]::Escape([string]$checks[$id])){
  throw "D3: утрачен существенный технический нюанс у $id"
 }
}
Write-Host "PASS D3: 14 находок, 46 Impact + 43 Remediation; все EN-свидетели и HTML совпадают" -ForegroundColor Green
