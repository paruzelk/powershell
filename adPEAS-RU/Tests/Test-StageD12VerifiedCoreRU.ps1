#Requires -Version 5.1
<#
.SYNOPSIS
    D12: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D12: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D12: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D12: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'ADFS_DKM_CONTAINER',
 'AZURE_AD_CONNECT_EXPOSED',
 'BITLOCKER_KEY_READABLE',
 'BITLOCKER_RECOVERY_DELEGATED',
 'CREDENTIAL_AUTOADMINLOGON',
 'CREDENTIAL_CONNECTION_STRING',
 'CREDENTIAL_GPP_PASSWORD',
 'CREDENTIAL_IN_DESCRIPTION',
 'CREDENTIAL_MENTION_REVIEW',
 'CREDENTIAL_NET_USE',
 'CREDENTIAL_ROAMING_DELEGATED',
 'CREDENTIAL_ROAMING_PRESENT',
 'CREDENTIAL_ROAMING_READABLE',
 'CREDENTIAL_SCRIPT_PASSWORD',
 'CREDENTIAL_UNATTEND_PASSWORD',
 'CREDENTIAL_VNC_PASSWORD',
 'DELETED_OBJECT_CREDENTIAL',
 'LOGON_SCRIPT_WRITABLE',
 'READABLE_UNIX_PASSWORD_ATTRIBUTES',
 'ANONYMOUS_SAM_ENUMERATION_ALLOWED',
 'ANONYMOUS_SID_NAME_TRANSLATION_ALLOWED',
 'ANON_LDAP_READABLE_ATTRS',
 'DELETED_OBJECTS_READ_BROAD',
 'DELETED_OBJECTS_READ_DELEGATED'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D12: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D12: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D12: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-21a.ru-RU.json','SourceVerifiedCore-21b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D12: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D12: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D12: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D12: русский HTML не содержит FindingId $id"}
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
   throw "D12: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D12: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D12: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D12: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 94 -or $totals.Remediation -ne 97){
 throw "D12: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'ADFS_DKM_CONTAINER'='дважды смените сертификат'
 'AZURE_AD_CONNECT_EXPOSED'='Tier 0'
 'BITLOCKER_KEY_READABLE'='msFVE-RecoveryPassword'
 'BITLOCKER_RECOVERY_DELEGATED'='confidential flag'
 'CREDENTIAL_AUTOADMINLOGON'='Registry.xml'
 'CREDENTIAL_CONNECTION_STRING'='Windows Integrated Authentication'
 'CREDENTIAL_GPP_PASSWORD'='Сначала смените пароль'
 'CREDENTIAL_IN_DESCRIPTION'='description, info, comment'
 'CREDENTIAL_MENTION_REVIEW'='ложные срабатывания'
 'CREDENTIAL_NET_USE'='без cpassword'
 'CREDENTIAL_ROAMING_DELEGATED'='READ_PROPERTY'
 'CREDENTIAL_ROAMING_PRESENT'='CVE-2022-30170'
 'CREDENTIAL_ROAMING_READABLE'='msPKIDPAPIMasterKeys'
 'CREDENTIAL_SCRIPT_PASSWORD'='gMSA'
 'CREDENTIAL_UNATTEND_PASSWORD'='Windows LAPS'
 'CREDENTIAL_VNC_PASSWORD'='UltraVNC MS-Logon'
 'DELETED_OBJECT_CREDENTIAL'='восстановление невозможным'
 'LOGON_SCRIPT_WRITABLE'='NETLOGON'
 'READABLE_UNIX_PASSWORD_ATTRIBUTES'='searchFlags bit 7'
 'ANONYMOUS_SAM_ENUMERATION_ALLOWED'='нулевых сеансов'
 'ANONYMOUS_SID_NAME_TRANSLATION_ALLOWED'='SID/Name translation'
 'ANON_LDAP_READABLE_ATTRS'='dsHeuristics'
 'DELETED_OBJECTS_READ_BROAD'='CN=Deleted Objects'
 'DELETED_OBJECTS_READ_DELEGATED'='Reanimate-Tombstones'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D12: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D12 сверяет собственные ID.
if(@($parity.ImpactStepCountDifferences).Count -ne 90 -or
   @($parity.RemediationStepCountDifferences).Count -ne 87){
 throw 'D12: контрольный остаток структурных расхождений должен быть 90/87'
}
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D12: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D12: 24 находки; Impact 94, Remediation 97; EN/RU/HTML паритет; остатки 90/87' -ForegroundColor Green
