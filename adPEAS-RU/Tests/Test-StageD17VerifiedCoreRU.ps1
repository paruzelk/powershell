#Requires -Version 5.1
<#
.SYNOPSIS
    D17: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D17: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D17: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D17: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'ASREP_ROASTABLE',
 'DANGEROUS_ACL_GENERICALL',
 'ESC9_CT_NO_SECURITY_EXTENSION',
 'EXCHANGE_SMTP_OPEN_RELAY',
 'GPO_USERRIGHT_SEAUDIT',
 'GPO_USERRIGHT_SEBACKUP',
 'GPO_USERRIGHT_SEDELEGATESESSIONUSERIMPERSONATE',
 'GPO_USERRIGHT_SEINTERACTIVELOGON',
 'GPO_USERRIGHT_SESYSTEMPROFILE',
 'KERBEROASTABLE_SPN',
 'LDAP_CHANNEL_BINDING_NOT_REQUIRED',
 'LDAP_SIGNING_NOT_REQUIRED',
 'REGISTRY_ALWAYSINSTALLELEVATED',
 'REGISTRY_CACHED_LOGONS',
 'REGISTRY_CREDSSP_DELEGATE_ANY',
 'REGISTRY_CREDSSP_ORACLE',
 'REGISTRY_DEFENDER_DISABLED',
 'REGISTRY_DSRM_ADMIN_LOGON',
 'REGISTRY_ENABLELUA',
 'REGISTRY_ESC10_KDC_BINDING',
 'REGISTRY_ESC10_KDC_BINDING_COMPAT',
 'REGISTRY_ESC10_SCHANNEL_UPN',
 'REGISTRY_KERBEROS_WEAK_ETYPES',
 'REGISTRY_LDAP_CLIENT_SIGNING_OFF'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D17: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D17: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){
  $emptyRe='(?m)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\(\)[ \t]*$'
  if([regex]::IsMatch($block,$emptyRe)){return @()}
  throw "D17: поле $field отсутствует в оригинале $id"
 }
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-26a.ru-RU.json','SourceVerifiedCore-26b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D17: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D17: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D17: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D17: русский HTML не содержит FindingId $id"}
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
   throw "D17: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D17: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D17: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D17: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 67 -or $totals.Remediation -ne 60){
 throw "D17: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'ASREP_ROASTABLE'='AS-REQ'
 'DANGEROUS_ACL_GENERICALL'='RBCD'
 'ESC9_CT_NO_SECURITY_EXTENSION'='szOID_NTDS_CA_SECURITY_EXT'
 'EXCHANGE_SMTP_OPEN_RELAY'='ms-Exch-SMTP-Accept-Any-Recipient'
 'GPO_USERRIGHT_SEAUDIT'='LOCAL SERVICE'
 'GPO_USERRIGHT_SEBACKUP'='ntds.dit'
 'GPO_USERRIGHT_SEDELEGATESESSIONUSERIMPERSONATE'='тот же сеанс'
 'GPO_USERRIGHT_SEINTERACTIVELOGON'='контроллерах домена'
 'GPO_USERRIGHT_SESYSTEMPROFILE'='WdiServiceHost'
 'KERBEROASTABLE_SPN'='gMSA'
 'LDAP_CHANNEL_BINDING_NOT_REQUIRED'='3039'
 'LDAP_SIGNING_NOT_REQUIRED'='2889'
 'REGISTRY_ALWAYSINSTALLELEVATED'='HKLM и HKCU'
 'REGISTRY_CACHED_LOGONS'='DCC2'
 'REGISTRY_CREDSSP_DELEGATE_ANY'='Remote Credential Guard'
 'REGISTRY_CREDSSP_ORACLE'='AllowEncryptionOracle=0'
 'REGISTRY_DEFENDER_DISABLED'='Tamper Protection'
 'REGISTRY_DSRM_ADMIN_LOGON'='BackupDsrmPassword'
 'REGISTRY_ENABLELUA'='EnableLUA=1'
 'REGISTRY_ESC10_KDC_BINDING'='StrongCertificateBindingEnforcement = 2'
 'REGISTRY_ESC10_KDC_BINDING_COMPAT'='CT_FLAG_NO_SECURITY_EXTENSION'
 'REGISTRY_ESC10_SCHANNEL_UPN'='0x4'
 'REGISTRY_KERBEROS_WEAK_ETYPES'='AES128_HMAC_SHA1'
 'REGISTRY_LDAP_CLIENT_SIGNING_OFF'='Require signing'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D17: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D17 сверяет собственные ID.
# В дальнейшем глобальные счётчики могут уменьшаться; проверяем только собственные 20 ID.
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D17: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D17: 24 находки; Impact 67, Remediation 60; EN/RU/HTML паритет; стабильность 24 ID' -ForegroundColor Green
