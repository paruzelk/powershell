#Requires -Version 5.1
<#
.SYNOPSIS
    D10: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D10: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D10: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D10: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'REGISTRY_FILTERADMINTOKEN',
 'REGISTRY_MACHINE_PASSWORD_STATIC',
 'REGISTRY_OFFICE_MACROS_ON',
 'REGISTRY_ONELOGON',
 'REGISTRY_PRINT_RPC_PRIVACY',
 'REGISTRY_RDP_ENCRYPTION',
 'REGISTRY_RDP_SECURITYLAYER',
 'REGISTRY_REMOTEUAC',
 'REGISTRY_SCRIPTBLOCK_LOGGING_OFF',
 'REGISTRY_SMB1_SERVER',
 'REGISTRY_SMB2_SERVER_DISABLED',
 'REGISTRY_SMB_UNENCRYPTED_ACCESS',
 'REGISTRY_WSUS_USER_PROXY',
 'SYSVOL_FRS_REPLICATION',
 'DC_PASSWORD_NOT_ROTATED',
 'GPO_POINTANDPRINT_USER_SCOPE',
 'GPO_PRINT_DRIVER_HARDENING',
 'GPO_PRINT_QUEUE_SPECIFIC_FILES',
 'GPO_PRINT_SPOOLER_RPC',
 'GPO_USERRIGHT_DEFAULT_REMOVED',
 'GPO_USERRIGHT_SECREATEGLOBAL',
 'GPO_USERRIGHT_SECREATESYMBOLICLINK',
 'GPO_USERRIGHT_SEMANAGEVOLUME',
 'GPO_USERRIGHT_SEPROFILESINGLEPROCESS'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D10: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D10: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D10: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-19a.ru-RU.json','SourceVerifiedCore-19b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D10: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D10: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D10: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D10: русский HTML не содержит FindingId $id"}
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
   throw "D10: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D10: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D10: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D10: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 54 -or $totals.Remediation -ne 43){
 throw "D10: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'REGISTRY_FILTERADMINTOKEN'='RID 500'
 'REGISTRY_MACHINE_PASSWORD_STATIC'='silver tickets'
 'REGISTRY_OFFICE_MACROS_ON'='Disable all except digitally signed macros'
 'REGISTRY_ONELOGON'='Netlogon'
 'REGISTRY_PRINT_RPC_PRIVACY'='CVE-2021-1678'
 'REGISTRY_RDP_ENCRYPTION'='SecurityLayer=2'
 'REGISTRY_RDP_SECURITYLAYER'='Negotiate'
 'REGISTRY_REMOTEUAC'='RMM'
 'REGISTRY_SCRIPTBLOCK_LOGGING_OFF'='4104'
 'REGISTRY_SMB1_SERVER'='MS17-010'
 'REGISTRY_SMB2_SERVER_DISABLED'='SMBv1'
 'REGISTRY_SMB_UNENCRYPTED_ACCESS'='SMB 1.0'
 'REGISTRY_WSUS_USER_PROXY'='http://'
 'SYSVOL_FRS_REPLICATION'='Eliminated'
 'DC_PASSWORD_NOT_ROTATED'='DCSync'
 'GPO_POINTANDPRINT_USER_SCOPE'='Computer Configuration'
 'GPO_PRINT_DRIVER_HARDENING'='RestrictDriverInstallationToAdministrators'
 'GPO_PRINT_QUEUE_SPECIFIC_FILES'='Color profiles'
 'GPO_PRINT_SPOOLER_RPC'='значение 2'
 'GPO_USERRIGHT_DEFAULT_REMOVED'='намеренное усиление'
 'GPO_USERRIGHT_SECREATEGLOBAL'='Remote Desktop Users'
 'GPO_USERRIGHT_SECREATESYMBOLICLINK'='fsutil behavior set symlinkevaluation'
 'GPO_USERRIGHT_SEMANAGEVOLUME'='ntds.dit'
 'GPO_USERRIGHT_SEPROFILESINGLEPROCESS'='Microsoft'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D10: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D10 сверяет собственные ID.
if(@($parity.ImpactStepCountDifferences).Count -ne 134 -or
   @($parity.RemediationStepCountDifferences).Count -ne 132){
 throw 'D10: контрольный остаток расхождений должен быть 134/132'
}
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D10: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D10: 24 находки; Impact 54, Remediation 43; EN/RU/HTML паритет; остатки 134/132' -ForegroundColor Green
