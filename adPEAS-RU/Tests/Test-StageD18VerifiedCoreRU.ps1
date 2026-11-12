#Requires -Version 5.1
<#
.SYNOPSIS
    D18: автономная проверка 15 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D18: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D18: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D18: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'ADCS_CLIENT_AUTH_SEVERITY',
 'AUTHN_POLICY_BROAD_CONDITION',
 'AUTHN_POLICY_NOT_EFFECTIVE',
 'CERT_FLAG_SEVERITY',
 'EXCHANGE_SMTP_CONNECTOR_AUTHENTICATED',
 'REGISTRY_LMCOMPAT',
 'REGISTRY_REMOTE_ASSISTANCE_OFFER',
 'REGISTRY_RUNASPPL',
 'REGISTRY_SMB1_CLIENT',
 'REGISTRY_UAC_NO_PROMPT',
 'REGISTRY_WINRM_BASIC',
 'REGISTRY_WINRM_UNENCRYPTED',
 'REGISTRY_WSUS_HTTP',
 'RODC_DENIED_GROUP_MISSING',
 'UNCONSTRAINED_DELEGATION'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D18: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D18: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){
  $emptyRe='(?m)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\(\)[ \t]*$'
  if([regex]::IsMatch($block,$emptyRe)){return @()}
  throw "D18: поле $field отсутствует в оригинале $id"
 }
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$expectedCatalogCounts=@{'SourceVerifiedCore-27a.ru-RU.json'=8;'SourceVerifiedCore-27b.ru-RU.json'=7}
$all=@{}
$catalogNames=@('SourceVerifiedCore-27a.ru-RU.json','SourceVerifiedCore-27b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne $expectedCatalogCounts[$catalogName]){
  throw "D18: в каталоге $catalogName неверное число записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D18: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 15 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D18: набор 15 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D18: русский HTML не содержит FindingId $id"}
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
   throw "D18: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D18: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D18: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D18: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 28 -or $totals.Remediation -ne 23){
 throw "D18: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'ADCS_CLIENT_AUTH_SEVERITY'='Client Authentication EKU'
 'AUTHN_POLICY_BROAD_CONDITION'='AuthenticationSilo'
 'AUTHN_POLICY_NOT_EFFECTIVE'='Set-ADAuthenticationPolicy'
 'CERT_FLAG_SEVERITY'='флагов шаблонов'
 'EXCHANGE_SMTP_CONNECTOR_AUTHENTICATED'='исправление не требуется'
 'REGISTRY_LMCOMPAT'='LmCompatibilityLevel'
 'REGISTRY_REMOTE_ASSISTANCE_OFFER'='Configure Offer Remote Assistance'
 'REGISTRY_RUNASPPL'='RunAsPPL=1'
 'REGISTRY_SMB1_CLIENT'='mrxsmb10'
 'REGISTRY_UAC_NO_PROMPT'='secure desktop'
 'REGISTRY_WINRM_BASIC'='WinRM client'
 'REGISTRY_WINRM_UNENCRYPTED'='Allow unencrypted traffic'
 'REGISTRY_WSUS_HTTP'='WUServer=https://'
 'RODC_DENIED_GROUP_MISSING'='Denied RODC Password Replication Group'
 'UNCONSTRAINED_DELEGATION'='Protected Users'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D18: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D18 сверяет собственные ID.
# В дальнейшем глобальные счётчики могут уменьшаться; проверяем только собственные 20 ID.
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D18: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D18: 15 находок; Impact 28, Remediation 23; EN/RU/HTML паритет; стабильность 15 ID' -ForegroundColor Green
