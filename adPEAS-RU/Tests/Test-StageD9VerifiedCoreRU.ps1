#Requires -Version 5.1
<#
.SYNOPSIS
    D9: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D9: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D9: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D9: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'REGISTRY_AUTOLOGON',
 'REGISTRY_CREDGUARD',
 'REGISTRY_FIREWALL_DISABLED',
 'REGISTRY_INSECURE_GUEST_AUTH',
 'REGISTRY_LEGACY_TLS',
 'REGISTRY_LLMNR_ON',
 'REGISTRY_MACHINE_PASSWORD_AGE',
 'REGISTRY_NOLMHASH',
 'REGISTRY_NULL_SESSION',
 'REGISTRY_RDP_NLA',
 'REGISTRY_RESTRICTEDADMIN',
 'REGISTRY_WDIGEST',
 'GPO_USERRIGHT_SEDEBUG',
 'GPO_USERRIGHT_SEIMPERSONATE',
 'GPO_USERRIGHT_SEENABLEDELEGATION',
 'GPO_USERRIGHT_SELOADDRIVER',
 'GPO_USERRIGHT_SERESTORE',
 'GPO_USERRIGHT_SETAKEOWNERSHIP',
 'GPO_USERRIGHT_SESECURITY',
 'GPO_USERRIGHT_SESERVICELOGON',
 'GPO_USERRIGHT_SEREMOTEINTERACTIVELOGON',
 'GPO_USERRIGHT_SEBATCHLOGON',
 'GPO_USERRIGHT_SEASSIGNPRIMARYTOKEN',
 'GPO_USERRIGHT_SECREATETOKEN'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D9: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D9: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D9: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-18a.ru-RU.json','SourceVerifiedCore-18b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D9: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D9: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D9: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D9: русский HTML не содержит FindingId $id"}
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
   throw "D9: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D9: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D9: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D9: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 61 -or $totals.Remediation -ne 45){
 throw "D9: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'REGISTRY_AUTOLOGON'='AutoAdminLogon'
 'REGISTRY_CREDGUARD'='UEFI lock'
 'REGISTRY_FIREWALL_DISABLED'='EnableFirewall=1'
 'REGISTRY_INSECURE_GUEST_AUTH'='AllowInsecureGuestAuth=0'
 'REGISTRY_LEGACY_TLS'='Schannel'
 'REGISTRY_LLMNR_ON'='Turn off multicast name resolution'
 'REGISTRY_MACHINE_PASSWORD_AGE'='krbtgt'
 'REGISTRY_NOLMHASH'='следующей смены пароля'
 'REGISTRY_NULL_SESSION'='RestrictNullSessAccess=1'
 'REGISTRY_RDP_NLA'='CredSSP'
 'REGISTRY_RESTRICTEDADMIN'='Remote Credential Guard'
 'REGISTRY_WDIGEST'='UseLogonCredential=0'
 'GPO_USERRIGHT_SEDEBUG'='LSASS'
 'GPO_USERRIGHT_SEIMPERSONATE'='служебная учётная запись'
 'GPO_USERRIGHT_SEENABLEDELEGATION'='CVE-2020-17049'
 'GPO_USERRIGHT_SELOADDRIVER'='HVCI/WDAC'
 'GPO_USERRIGHT_SERESTORE'='SAM/SYSTEM'
 'GPO_USERRIGHT_SETAKEOWNERSHIP'='ACL'
 'GPO_USERRIGHT_SESECURITY'='SIEM'
 'GPO_USERRIGHT_SESERVICELOGON'='действующей службой'
 'GPO_USERRIGHT_SEREMOTEINTERACTIVELOGON'='NLA'
 'GPO_USERRIGHT_SEBATCHLOGON'='Task Scheduler'
 'GPO_USERRIGHT_SEASSIGNPRIMARYTOKEN'='SeImpersonatePrivilege'
 'GPO_USERRIGHT_SECREATETOKEN'='не назначает это право никому'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D9: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D9 сверяет собственные ID.
if(@($parity.ImpactStepCountDifferences).Count -ne 157 -or
   @($parity.RemediationStepCountDifferences).Count -ne 149){
 throw 'D9: итоговая статистика Impact/Remediation не совпадает с 157/149'
}
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D9: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D9: 24 находки; Impact 61, Remediation 45; EN/RU/HTML паритет; остатки 157/149' -ForegroundColor Green
