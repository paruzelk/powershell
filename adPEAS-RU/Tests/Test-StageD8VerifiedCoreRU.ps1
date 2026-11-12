#Requires -Version 5.1
<#
.SYNOPSIS
    D8: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D8: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D8: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D8: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'DANGEROUS_ACL_GPO_DELETE',
 'DANGEROUS_ACL_GPO_EXTENDED',
 'DANGEROUS_ACL_GPO_WRITEPROPERTY',
 'DANGEROUS_ACL_GPO_WRITEPROPERTY_SCOPED',
 'DANGEROUS_ACL_REPLICATION_INERT_HALF',
 'DANGEROUS_ACL_REPLICATION_NO_SECRETS',
 'DOMAIN_ROOT_FSMO_TRANSFER',
 'DOMAIN_ROOT_NON_DEFAULT_OWNER',
 'DOMAIN_ROOT_REANIMATE_TOMBSTONES',
 'DOMAIN_ROOT_REPLICA_INSTALL',
 'DOMAIN_ROOT_SID_HISTORY_WRITE',
 'GPO_NON_DEFAULT_OWNER',
 'GPO_LOCAL_GROUP_MEMBER',
 'GPO_REGISTRY_PASSWORD',
 'GPO_SCOPE_DOMAIN_WIDE',
 'GPO_SCRIPT_OUTSIDE_POLICY_STORE',
 'GPO_SEMACHINEACCOUNTPRIVILEGE_BROAD',
 'GPO_SYSVOL_FOLDER_ORPHANED',
 'GPO_SYSVOL_GPT_MISSING',
 'GPO_TASK_CMD_UNQUOTED_PATH',
 'GPO_TASK_UNQUOTED_PATH',
 'GPO_POINTANDPRINT_DRIVER_SOURCE',
 'GPO_POINTANDPRINT_LATENT',
 'GPO_POINTANDPRINT_NONADMIN_INSTALL'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D8: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D8: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D8: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-17a.ru-RU.json','SourceVerifiedCore-17b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D8: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D8: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D8: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D8: русский HTML не содержит FindingId $id"}
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
   throw "D8: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D8: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D8: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D8: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 79 -or $totals.Remediation -ne 75){
 throw "D8: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'DANGEROUS_ACL_GPO_DELETE'='5141'
 'DANGEROUS_ACL_GPO_EXTENDED'='ObjectType GUID'
 'DANGEROUS_ACL_GPO_WRITEPROPERTY'='gPCFileSysPath'
 'DANGEROUS_ACL_GPO_WRITEPROPERTY_SCOPED'='не сама по себе запускает код'
 'DANGEROUS_ACL_REPLICATION_INERT_HALF'='без DS-Replication-Get-Changes'
 'DANGEROUS_ACL_REPLICATION_NO_SECRETS'='несекретные атрибуты'
 'DOMAIN_ROOT_FSMO_TRANSFER'='PDC emulator'
 'DOMAIN_ROOT_NON_DEFAULT_OWNER'='Владение сохраняется после сброса DACL'
 'DOMAIN_ROOT_REANIMATE_TOMBSTONES'='AD Recycle Bin'
 'DOMAIN_ROOT_REPLICA_INSTALL'='не отменяет передачу'
 'DOMAIN_ROOT_SID_HISTORY_WRITE'='sIDHistory'
 'GPO_NON_DEFAULT_OWNER'='владелец не нуждается в отдельной ACE'
 'GPO_LOCAL_GROUP_MEMBER'='следующее обновление GPO'
 'GPO_REGISTRY_PASSWORD'='Смените пароль'
 'GPO_SCOPE_DOMAIN_WIDE'='MS16-072'
 'GPO_SCRIPT_OUTSIDE_POLICY_STORE'='SYSVOL'
 'GPO_SEMACHINEACCOUNTPRIVILEGE_BROAD'='SeMachineAccountPrivilege'
 'GPO_SYSVOL_FOLDER_ORPHANED'='Ни одна политика не применяет'
 'GPO_SYSVOL_GPT_MISSING'='репликацию SYSVOL'
 'GPO_TASK_CMD_UNQUOTED_PATH'='cmd.exe'
 'GPO_TASK_UNQUOTED_PATH'='Task Scheduler'
 'GPO_POINTANDPRINT_DRIVER_SOURCE'='PackagePointAndPrintOnly=1'
 'GPO_POINTANDPRINT_LATENT'='августа 2021'
 'GPO_POINTANDPRINT_NONADMIN_INSTALL'='RestrictDriverInstallationToAdministrators=1'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D8: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D8 сверяет собственные ID.
if(@($parity.ImpactStepCountDifferences).Count -ne 179 -or
   @($parity.RemediationStepCountDifferences).Count -ne 164){
 throw 'D8: итоговая статистика Impact/Remediation не совпадает с 179/164'
}
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D8: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D8: 24 находки; Impact 79, Remediation 75; EN/RU/HTML паритет; остатки 179/164' -ForegroundColor Green
