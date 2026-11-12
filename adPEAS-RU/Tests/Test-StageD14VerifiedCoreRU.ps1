#Requires -Version 5.1
<#
.SYNOPSIS
    D14: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D14: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D14: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D14: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'ADMINSDHOLDER_PROPAGATED_RIGHT',
 'COMPUTER_CONTAINER_CREATE_BROAD',
 'COMPUTER_CONTAINER_CREATE_PERMISSIONS',
 'COMPUTER_OBJECT_EXPLICIT_RIGHT',
 'COMPUTER_OWNERSHIP_REASSIGNED',
 'COMPUTER_PASSWORD_NOT_ROTATED',
 'CONSTRAINED_DELEGATION',
 'CRITICAL_OBJECT_CONTROL',
 'DANGEROUS_RIGHTS_CONTEXT',
 'DMSA_LINK_ONE_SIDED',
 'DMSA_MEMBERSHIP_OWNER',
 'DMSA_PRIVILEGED_PREDECESSOR',
 'DMSA_USABLE_BY_NONPRIVILEGED',
 'DSHEURISTICS_ADMINSDHOLDER_EXCLUSION',
 'DSHEURISTICS_ANONYMOUS_NSPI',
 'DSHEURISTICS_UNIQUENESS_DISABLED',
 'ENCRYPTION_DES_ENABLED',
 'OU_NON_DEFAULT_OWNER',
 'RBCD_CONFIGURED',
 'SID_HISTORY_FOREIGN_PRIVILEGED',
 'SID_HISTORY_ORPHANED',
 'SID_HISTORY_OWN_DOMAIN',
 'STANDALONE_MSA_LEGACY',
 'BLOODHOUND_COLLECTION_COMPLETE'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D14: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D14: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D14: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-23a.ru-RU.json','SourceVerifiedCore-23b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D14: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D14: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D14: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D14: русский HTML не содержит FindingId $id"}
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
   throw "D14: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D14: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D14: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D14: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 82 -or $totals.Remediation -ne 78){
 throw "D14: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'ADMINSDHOLDER_PROPAGATED_RIGHT'='runProtectAdminGroupsTask'
 'COMPUTER_CONTAINER_CREATE_BROAD'='SetAccessRuleProtection'
 'COMPUTER_CONTAINER_CREATE_PERMISSIONS'='pre-staging'
 'COMPUTER_OBJECT_EXPLICIT_RIGHT'='OU'
 'COMPUTER_OWNERSHIP_REASSIGNED'='OWNER RIGHTS'
 'COMPUTER_PASSWORD_NOT_ROTATED'='DisablePasswordChange'
 'CONSTRAINED_DELEGATION'='целевых SPN'
 'CRITICAL_OBJECT_CONTROL'='RID'
 'DANGEROUS_RIGHTS_CONTEXT'='4670'
 'DMSA_LINK_ONE_SIDED'='KDC игнорирует'
 'DMSA_MEMBERSHIP_OWNER'='msDS-GroupMSAMembership'
 'DMSA_PRIVILEGED_PREDECESSOR'='Tier 0'
 'DMSA_USABLE_BY_NONPRIVILEGED'='широкой группы'
 'DSHEURISTICS_ADMINSDHOLDER_EXCLUSION'='16-й символ'
 'DSHEURISTICS_ANONYMOUS_NSPI'='8-й символ'
 'DSHEURISTICS_UNIQUENESS_DISABLED'='21-й символ'
 'ENCRYPTION_DES_ENABLED'='msDS-SupportedEncryptionTypes'
 'OU_NON_DEFAULT_OWNER'='CREATOR OWNER'
 'RBCD_CONFIGURED'='сама настройка ещё не означает уязвимость'
 'SID_HISTORY_FOREIGN_PRIVILEGED'='SID filtering'
 'SID_HISTORY_ORPHANED'='ACL'
 'SID_HISTORY_OWN_DOMAIN'='текущего домена'
 'STANDALONE_MSA_LEGACY'='gMSA'
 'BLOODHOUND_COLLECTION_COMPLETE'='BloodHound CE'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D14: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D14 сверяет собственные ID.
# В дальнейшем глобальные счётчики могут уменьшаться; проверяем только собственные 24 ID.
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D14: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D14: 24 находки; Impact 82, Remediation 78; EN/RU/HTML паритет; стабильность 24 ID' -ForegroundColor Green
