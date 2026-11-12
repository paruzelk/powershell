#Requires -Version 5.1
<#
.SYNOPSIS
    D15: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D15: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D15: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D15: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'TRUST_BIDIRECTIONAL',
 'TRUST_PASSWORD_STALE',
 'TRUST_SELECTIVE_AUTH',
 'TRUST_TRANSITIVE',
 'TRUST_TREAT_AS_EXTERNAL',
 'PKI_CERTIFICATE_EXPIRED',
 'PKI_SHORT_KEY_LENGTH',
 'PKI_STRONG_KEY_LENGTH',
 'PKI_STRONG_SIGNATURE_ALGORITHM',
 'PKI_WEAK_SIGNATURE_ALGORITHM',
 'NTAUTH_FOREIGN_ISSUER',
 'ENROLLMENT_REQUIRES_APPROVAL',
 'WEB_ENDPOINT_EPA_ENABLED',
 'SCCM_GROUP_BROAD_MEMBER',
 'SCCM_PXE_EXPOSURE',
 'SCCM_SERVICE_ACCOUNT',
 'SCCM_SITE_HIERARCHY',
 'SCOM_PRIVILEGED_SERVICE_ACCOUNT',
 'ESX_ADMINS_MEMBER',
 'MSSQL_SERVICE_ACCOUNT_PRIVILEGED',
 'EXCHANGE_AD_SPLIT_PERMISSIONS',
 'EXCHANGE_GROUP_LOW_PRIV_MEMBER',
 'EXCHANGE_GROUP_PERMISSIONS',
 'EXCHANGE_PERMISSIONS_MODEL_CLEAN'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D15: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D15: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D15: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-24a.ru-RU.json','SourceVerifiedCore-24b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D15: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D15: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D15: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D15: русский HTML не содержит FindingId $id"}
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
   throw "D15: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D15: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D15: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D15: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 86 -or $totals.Remediation -ne 85){
 throw "D15: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'TRUST_BIDIRECTIONAL'='SID Filtering'
 'TRUST_PASSWORD_STALE'='resetOneSide'
 'TRUST_SELECTIVE_AUTH'='Исправление не требуется'
 'TRUST_TRANSITIVE'='нетранзитивные'
 'TRUST_TREAT_AS_EXTERNAL'='quarantine'
 'PKI_CERTIFICATE_EXPIRED'='PKINIT'
 'PKI_SHORT_KEY_LENGTH'='NIST SP 800-57'
 'PKI_STRONG_KEY_LENGTH'='Это безопасная конфигурация'
 'PKI_STRONG_SIGNATURE_ALGORITHM'='SHA-384'
 'PKI_WEAK_SIGNATURE_ALGORITHM'='SHA-1'
 'NTAUTH_FOREIGN_ISSUER'='NTAuthCertificates'
 'ENROLLMENT_REQUIRES_APPROVAL'='Исправление не требуется'
 'WEB_ENDPOINT_EPA_ENABLED'='EPA'
 'SCCM_GROUP_BROAD_MEMBER'='административная роль SCCM'
 'SCCM_PXE_EXPOSURE'='NAA'
 'SCCM_SERVICE_ACCOUNT'='не добавляйте в группу gMSA'
 'SCCM_SITE_HIERARCHY'='Central Administration Site'
 'SCOM_PRIVILEGED_SERVICE_ACCOUNT'='Action Account'
 'ESX_ADMINS_MEMBER'='CVE-2024-37085'
 'MSSQL_SERVICE_ACCOUNT_PRIVILEGED'='xp_cmdshell'
 'EXCHANGE_AD_SPLIT_PERMISSIONS'='Exchange Trusted Subsystem'
 'EXCHANGE_GROUP_LOW_PRIV_MEMBER'='НЕМЕДЛЕННО'
 'EXCHANGE_GROUP_PERMISSIONS'='нельзя и не следует удалять'
 'EXCHANGE_PERMISSIONS_MODEL_CLEAN'='LDAP channel binding'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D15: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D15 сверяет собственные ID.
# В дальнейшем глобальные счётчики могут уменьшаться; проверяем только собственные 24 ID.
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D15: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D15: 24 находки; Impact 86, Remediation 85; EN/RU/HTML паритет; стабильность 24 ID' -ForegroundColor Green
