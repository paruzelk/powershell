#Requires -Version 5.1
<#
.SYNOPSIS
    D6: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
.DESCRIPTION
    Проверяет исходный EN, порядок пунктов, русский каталог и встроенный
    HTML-словарь. Подключения к Active Directory и команд исправления нет.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$source=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Core/adPEAS-FindingDefinitions.ps1'),[Text.Encoding]::UTF8)
$source=$source.Replace(([string][char]13+[string][char]10),[string][char]10)
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$marker='const ruFullFindingTechnical = '
$begin=$js.IndexOf($marker,[StringComparison]::Ordinal)
if($begin -lt 0){throw 'D6: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D6: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D6: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'ADCS_CLIENT_AUTH_EKU','ADCS_HTTP_AVAILABLE','ADCS_NONPRIV_ENROLLMENT',
 'ADCS_SMARTCARD_LOGON_EKU','GMSA_MEMBERSHIP_INFO','GMSA_ROTATION_INTERVAL_LONG',
 'LAPS_ACCOUNT_INFO','LAPS_GPO_DISABLED','LAPS_GPO_EXPIRATION_PROTECTION_DISABLED',
 'LAPS_GPO_NOT_LINKED','LAPS_GPO_PASSWORD_AGE','LAPS_GPO_PASSWORD_LENGTH',
 'LAPS_GPO_WEAK_PASSWORD_COMPLEXITY','LAPS_PASSWORD_READABLE',
 'LAPS_READ_BLOCKED_BY_CONFIDENTIAL','LAPS_UNPROTECTED_COMPUTERS',
 'PRIVILEGED_ACCOUNT_AFFECTED','PRIVILEGED_GROUP_ACL',
 'RODC_PRIVILEGED_PASSWORD_ALLOWED','RODC_PRIVILEGED_PASSWORD_REVEALED',
 'OU_PERM_LAPS_READ','OU_PERM_READALL','OU_PERM_GENERICWRITE',
 'OU_PERM_USER_ACCOUNT_RESTRICTIONS'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D6: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D6: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D6: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-15a.ru-RU.json','SourceVerifiedCore-15b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D6: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D6: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D6: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D6: русский HTML не содержит FindingId $id"}
 foreach($field in @('Impact','Remediation')){
  $lower=$field.ToLowerInvariant()
  $enProp='sourceEnglish'+$field
  $countProp=$enProp+'Count'
  $original=@(Get-OriginalItems $id $field)
  $en=@($all[$id].$enProp)
  $translated=@($all[$id].$lower)
  $shown=@($entry.Value.$lower)
  $n=[int]$all[$id].$countProp
  if($n -le 0 -or $n -ne $original.Count -or $n -ne $en.Count -or
     $n -ne $translated.Count -or $n -ne $shown.Count){
   throw "D6: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D6: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D6: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D6: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 79 -or $totals.Remediation -ne 74){
 throw "D6: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'ADCS_CLIENT_AUTH_EKU'='ENROLLEE_SUPPLIES_SUBJECT'
 'ADCS_HTTP_AVAILABLE'='Extended Protection for Authentication (EPA)'
 'ADCS_NONPRIV_ENROLLMENT'='непривилегированными пользователями'
 'ADCS_SMARTCARD_LOGON_EKU'='PKINIT'
 'GMSA_ROTATION_INTERVAL_LONG'='невозможно изменить'
 'LAPS_GPO_DISABLED'='остаются в каталоге'
 'LAPS_GPO_PASSWORD_AGE'='PostAuthenticationActions'
 'LAPS_GPO_PASSWORD_LENGTH'='14 символов'
 'LAPS_READ_BLOCKED_BY_CONFIDENTIAL'='CONTROL_ACCESS'
 'LAPS_PASSWORD_READABLE'='Event ID 4662'
 'PRIVILEGED_ACCOUNT_AFFECTED'='adminCount'
 'PRIVILEGED_GROUP_ACL'='DnsAdmins'
 'RODC_PRIVILEGED_PASSWORD_ALLOWED'='Denied RODC Password Replication Group'
 'RODC_PRIVILEGED_PASSWORD_REVEALED'='уже находятся'
 'OU_PERM_READALL'='дополнительные требования'
 'OU_PERM_GENERICWRITE'='SetAccessRuleProtection'
 'OU_PERM_USER_ACCOUNT_RESTRICTIONS'='User-Account-Restrictions'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D6: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
if(@($parity.ImpactStepCountDifferences).Count -ne 225 -or
   @($parity.RemediationStepCountDifferences).Count -ne 206){
 throw 'D6: итоговый счётчик расхождений должен быть 225/206'
}
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D6: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D6: 24 находки; Impact 79, Remediation 74; EN/RU/HTML паритет; остатки 225/206' -ForegroundColor Green
