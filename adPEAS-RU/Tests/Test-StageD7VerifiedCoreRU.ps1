#Requires -Version 5.1
<#
.SYNOPSIS
    D7: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D7: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D7: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D7: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'AUTHN_KDC_ARMORING_NOT_SUPPORTED','AUTHN_POLICY_EXEMPT_ADMINISTRATOR',
 'AUTHN_POLICY_OBJECT_WRITABLE','AUTHN_SILO_INCOMPLETE_ENROLLMENT',
 'AUTHN_SILO_NOT_EFFECTIVE','LDAP_ANONYMOUS_BINDING_RESTRICTED',
 'LDAP_CHANNEL_BINDING_ALWAYS','LDAP_SIGNING_REQUIRED',
 'ADCS_MANAGER_APPROVAL','DOMAIN_ROOT_MAQ_WRITE',
 'OU_PERM_CREATE_CHILD','OU_PERM_CREATE_DMSA',
 'OU_PERM_DNSHOSTNAME_WRITE','OU_PERM_DNS_HOST_NAME_ATTRIBUTES',
 'OU_PERM_GPOPTIONS','OU_PERM_GROUP_MEMBERSHIP',
 'OU_PERM_SCRIPTPATH','OU_PERM_SELF_ALL_VALIDATED',
 'OU_PERM_SELF_MEMBERSHIP','OU_PERM_SPN_WRITE',
 'OU_PERM_USERACCOUNTCONTROL','OU_PERM_VALIDATED_DNS',
 'OU_PERM_VALIDATED_SPN','OU_PERM_WRITEPROPERTY_ALL'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D7: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D7: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D7: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-16a.ru-RU.json','SourceVerifiedCore-16b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D7: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D7: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D7: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D7: русский HTML не содержит FindingId $id"}
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
   throw "D7: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D7: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D7: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D7: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 85 -or $totals.Remediation -ne 93){
 throw "D7: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'AUTHN_KDC_ARMORING_NOT_SUPPORTED'='Fail unarmored authentication requests'
 'AUTHN_POLICY_EXEMPT_ADMINISTRATOR'='встроенную учётную запись Administrator'
 'AUTHN_POLICY_OBJECT_WRITABLE'='Enterprise Admins'
 'AUTHN_SILO_INCOMPLETE_ENROLLMENT'='Set-ADAccountAuthenticationPolicySilo'
 'AUTHN_SILO_NOT_EFFECTIVE'='AuthenticationPolicyFailures-DomainController'
 'LDAP_ANONYMOUS_BINDING_RESTRICTED'='исправление не требуется'
 'LDAP_CHANNEL_BINDING_ALWAYS'='TLS-канал'
 'LDAP_SIGNING_REQUIRED'='NTLM relay'
 'ADCS_MANAGER_APPROVAL'='Если одобрение не требуется'
 'DOMAIN_ROOT_MAQ_WRITE'='ms-DS-MachineAccountQuota'
 'OU_PERM_CREATE_CHILD'='Windows Server 2025'
 'OU_PERM_CREATE_DMSA'='msDS-SupersededManagedAccountLink'
 'OU_PERM_DNSHOSTNAME_WRITE'='Validated-DNS-Host-Name'
 'OU_PERM_DNS_HOST_NAME_ATTRIBUTES'='WriteProperty'
 'OU_PERM_GPOPTIONS'='Block Inheritance'
 'OU_PERM_GROUP_MEMBERSHIP'='AdminSDHolder'
 'OU_PERM_SCRIPTPATH'='scriptPath'
 'OU_PERM_SELF_ALL_VALIDATED'='Self-Membership'
 'OU_PERM_SELF_MEMBERSHIP'='самостоятельно добавить'
 'OU_PERM_SPN_WRITE'='Kerberoasting'
 'OU_PERM_USERACCOUNTCONTROL'='DONT_REQUIRE_PREAUTH'
 'OU_PERM_VALIDATED_DNS'='больше ограничений'
 'OU_PERM_VALIDATED_SPN'='менее опасно'
 'OU_PERM_WRITEPROPERTY_ALL'='SetAccessRuleProtection'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D7: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D7 сверяет собственные ID.
if(@($parity.ImpactStepCountDifferences).Count -ne 202 -or
   @($parity.RemediationStepCountDifferences).Count -ne 185){
 throw 'D7: итоговый счётчик расхождений должен быть 202/185'
}
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D7: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D7: 24 находки; Impact 85, Remediation 93; EN/RU/HTML паритет; остатки 202/185' -ForegroundColor Green
