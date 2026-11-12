#Requires -Version 5.1
<#
.SYNOPSIS
    D16: автономная проверка 20 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D16: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D16: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D16: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'EXCHANGE_HYBRID_DEPLOYMENT',
 'EXCHANGE_RBAC_AD_PERMISSIONS',
 'EXCHANGE_RBAC_APPLICATION_IMPERSONATION',
 'EXCHANGE_RBAC_DEFAULT_ASSIGNMENT',
 'EXCHANGE_RBAC_MAILBOX_IMPORT_EXPORT',
 'EXCHANGE_RBAC_MAILBOX_SEARCH',
 'EXCHANGE_RBAC_ROLE_MANAGEMENT',
 'EXCHANGE_RBAC_UNSCOPED_ROLE_MANAGEMENT',
 'EXCHANGE_SMTP_ANONYMOUS_AUTHENTICATED',
 'EXCHANGE_SMTP_ANONYMOUS_BYPASS_ANTISPAM',
 'EXCHANGE_SMTP_ANONYMOUS_SPOOFING',
 'EXCHANGE_SMTP_BROAD_RELAY',
 'EXCHANGE_SMTP_BROAD_SPOOFING',
 'EXCHANGE_VULNERABLE_VERSION',
 'EXCHANGE_WEB_ENDPOINTS',
 'EXCHANGE_SMTP_CONNECTOR_UNREADABLE',
 'DANGEROUS_RIGHTS_AFFECTED_OUS',
 'DANGEROUS_RIGHTS_SEVERITY',
 'LAPS_INSTALLED',
 'GPO_LINK_REACHES_DC'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D16: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D16: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){
  $emptyRe='(?m)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\(\)[ \t]*$'
  if([regex]::IsMatch($block,$emptyRe)){return @()}
  throw "D16: поле $field отсутствует в оригинале $id"
 }
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-25a.ru-RU.json','SourceVerifiedCore-25b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 10){
  throw "D16: в каталоге $catalogName ожидается 10 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D16: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 20 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D16: набор 20 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D16: русский HTML не содержит FindingId $id"}
 foreach($field in @('Impact','Remediation')){
  $lower=$field.ToLowerInvariant()
  $enProp='sourceEnglish'+$field
  $countProp=$enProp+'Count'
  $original=@(Get-OriginalItems $id $field)
  $en=@($all[$id].$enProp)
  $translated=@($all[$id].$lower)
  $shown=@($entry.Value.$lower)
  $n=[int]$all[$id].$countProp
  if($n -eq 0 -and ($id -cne 'LAPS_INSTALLED' -or $field -cne 'Remediation')){throw "D16: неожиданный пустой раздел $id / $field"}
  if($n -lt 0 -or $n -ne $original.Count -or $n -ne $en.Count -or
     $n -ne $translated.Count -or $n -ne $shown.Count){
   throw "D16: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D16: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D16: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D16: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 59 -or $totals.Remediation -ne 56){
 throw "D16: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'EXCHANGE_HYBRID_DEPLOYMENT'='Exchange Server Health Checker'
 'EXCHANGE_RBAC_AD_PERMISSIONS'='Add-ADPermission'
 'EXCHANGE_RBAC_APPLICATION_IMPERSONATION'='management scope'
 'EXCHANGE_RBAC_DEFAULT_ASSIGNMENT'='Discovery Management'
 'EXCHANGE_RBAC_MAILBOX_IMPORT_EXPORT'='New-MailboxExportRequest'
 'EXCHANGE_RBAC_MAILBOX_SEARCH'='New-MailboxSearch'
 'EXCHANGE_RBAC_ROLE_MANAGEMENT'='New-ManagementRoleAssignment'
 'EXCHANGE_RBAC_UNSCOPED_ROLE_MANAGEMENT'='New-ManagementRole'
 'EXCHANGE_SMTP_ANONYMOUS_AUTHENTICATED'='ms-Exch-SMTP-Accept-Authentication-Flag'
 'EXCHANGE_SMTP_ANONYMOUS_BYPASS_ANTISPAM'='ms-Exch-Bypass-Anti-Spam'
 'EXCHANGE_SMTP_ANONYMOUS_SPOOFING'='SPF, DKIM и DMARC'
 'EXCHANGE_SMTP_BROAD_RELAY'='RemoteIPRanges'
 'EXCHANGE_SMTP_BROAD_SPOOFING'='второе необходимо проверить и снять отдельно'
 'EXCHANGE_VULNERABLE_VERSION'='Exchange Subscription Edition'
 'EXCHANGE_WEB_ENDPOINTS'='MRSProxy'
 'EXCHANGE_SMTP_CONNECTOR_UNREADABLE'='неизвестно'
 'DANGEROUS_RIGHTS_AFFECTED_OUS'='масштаб последствий'
 'DANGEROUS_RIGHTS_SEVERITY'='Expected/Attention'
 'LAPS_INSTALLED'='автоматической ротацией'
 'GPO_LINK_REACHES_DC'='контроллеру домена'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D16: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D16 сверяет собственные ID.
# В дальнейшем глобальные счётчики могут уменьшаться; проверяем только собственные 20 ID.
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D16: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D16: 20 находок; Impact 59, Remediation 56; EN/RU/HTML паритет; стабильность 20 ID' -ForegroundColor Green
