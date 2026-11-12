#Requires -Version 5.1
<#
.SYNOPSIS
    D13: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D13: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D13: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D13: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'GUEST_ACCOUNT_DISABLED',
 'INACTIVE_ACCOUNT',
 'INACTIVE_PRIVILEGED_ACCOUNT',
 'INTERDOMAIN_TRUST_ACCOUNT',
 'AGING_OS',
 'OUTDATED_OS',
 'OS_EXTENDED_SECURITY_UPDATES_ONLY',
 'SMARTCARD_REQUIRED',
 'STALE_PASSWORD',
 'STALE_PASSWORD_MEDIUM',
 'TOMBSTONE_LIFETIME_SHORT',
 'PASSWORD_COMPLEXITY_ENABLED',
 'LAPS_LEGACY',
 'NETWORK_SUBNET_DOMAIN_CONTROLLERS',
 'PRECREATED_COMPUTER_ACCOUNT',
 'PREWIN2000_DEFAULT_MEMBER',
 'PRIMARY_GROUP_IS_DC_GROUP',
 'SCRIPTPATH_HARDCODED',
 'OPERATOR_GROUP_MEMBERS',
 'OPERATOR_GROUP_MEMBERSHIP',
 'ORPHANED_ADMIN_ACCOUNT',
 'NON_DEFAULT_COMPUTER_OWNERS',
 'NON_DEFAULT_USER_OWNERS',
 'MACHINE_QUOTA_UNRESTRICTED'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D13: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D13: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D13: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-22a.ru-RU.json','SourceVerifiedCore-22b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D13: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D13: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D13: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D13: русский HTML не содержит FindingId $id"}
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
   throw "D13: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D13: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D13: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D13: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 88 -or $totals.Remediation -ne 89){
 throw "D13: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'GUEST_ACCOUNT_DISABLED'='Исправление не требуется'
 'INACTIVE_ACCOUNT'='365 дней'
 'INACTIVE_PRIVILEGED_ACCOUNT'='90 дней'
 'INTERDOMAIN_TRUST_ACCOUNT'='PASSWD_NOTREQD'
 'AGING_OS'='январе 2027'
 'OUTDATED_OS'='изолируйте'
 'OS_EXTENDED_SECURITY_UPDATES_ONLY'='ESU не фиксируется'
 'SMARTCARD_REQUIRED'='смарт-карты'
 'STALE_PASSWORD'='gMSA'
 'STALE_PASSWORD_MEDIUM'='pwdLastSet'
 'TOMBSTONE_LIFETIME_SHORT'='tombstoneLifetime'
 'PASSWORD_COMPLEXITY_ENABLED'='Это безопасная настройка'
 'LAPS_LEGACY'='Windows LAPS'
 'NETWORK_SUBNET_DOMAIN_CONTROLLERS'='Tier 0'
 'PRECREATED_COMPUTER_ACCOUNT'='STATUS_NOLOGON_WORKSTATION_TRUST_ACCOUNT'
 'PREWIN2000_DEFAULT_MEMBER'='Cisco ISE'
 'PRIMARY_GROUP_IS_DC_GROUP'='primaryGroupID'
 'SCRIPTPATH_HARDCODED'='NETLOGON'
 'OPERATOR_GROUP_MEMBERS'='NTDS.dit'
 'OPERATOR_GROUP_MEMBERSHIP'='Cert Publishers'
 'ORPHANED_ADMIN_ACCOUNT'='один запуск SDProp'
 'NON_DEFAULT_COMPUTER_OWNERS'='RBCD'
 'NON_DEFAULT_USER_OWNERS'='WriteDACL'
 'MACHINE_QUOTA_UNRESTRICTED'='ms-DS-MachineAccountQuota'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D13: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D13 сверяет собственные ID.
# В дальнейшем глобальные счётчики могут уменьшаться; проверяем только собственные 24 ID.
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D13: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D13: 24 находки; Impact 88, Remediation 89; EN/RU/HTML паритет; стабильность 24 ID' -ForegroundColor Green
