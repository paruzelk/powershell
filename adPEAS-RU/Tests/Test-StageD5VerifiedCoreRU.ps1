#Requires -Version 5.1
<#
.SYNOPSIS
    D5: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D5: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D5: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D5: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'ADCS_CA_CERT_EXPIRED','ADCS_CA_SHORT_KEY','ADCS_CA_WEAK_SIGNATURE',
 'ESC13_ISSUANCE_POLICY_GROUP_LINK','ESC14_WRITABLE_MAPPING',
 'KERBEROS_HASH_CRACKABLE','KERBEROS_TICKET_LIFETIME_EXTENDED',
 'ROASTABLE_PRIVILEGED_ACCOUNT','LAPS_COVERAGE_NOT_IN_AD',
 'LAPS_GPO_ENCRYPTION_DISABLED','LAPS_GPO_NO_AD_BACKUP',
 'LAPS_GPO_NO_POST_AUTH_RESET','LAPS_NOT_DEPLOYED',
 'LAPS_PASSWORD_NOT_ROTATED','LAPS_PASSWORD_READ_ACCESS',
 'LAPS_ENCRYPTED_READ_NO_DECRYPTOR','GMSA_PASSWORD_READABLE',
 'GMSA_MEMBERSHIP_OWNER','PRIVILEGED_GROUP_MEMBERSHIP',
 'PRIVILEGED_ACCOUNT_ACL','OU_PERM_CONSTRAINED_DELEGATION',
 'OU_PERM_PASSWORD_RESET','OU_PERM_RBCD','OU_PERM_GPLINK'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D5: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D5: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D5: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-14a.ru-RU.json','SourceVerifiedCore-14b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D5: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D5: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D5: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D5: русский HTML не содержит FindingId $id"}
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
   throw "D5: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D5: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D5: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D5: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 94 -or $totals.Remediation -ne 101){
 throw "D5: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'LAPS_COVERAGE_NOT_IN_AD'='само по себе не является нарушением'
 'LAPS_ENCRYPTED_READ_NO_DECRYPTOR'='не эквивалентно чтению пароля'
 'LAPS_GPO_NO_POST_AUTH_RESET'='до следующей плановой ротации'
 'LAPS_GPO_ENCRYPTION_DISABLED'='ADPasswordEncryptionPrincipal'
 'PRIVILEGED_GROUP_MEMBERSHIP'='Не добавляйте учётные записи компьютеров и gMSA'
 'GMSA_MEMBERSHIP_OWNER'='msDS-GroupMSAMembership'
 'ESC14_WRITABLE_MAPPING'='Public-Information'
 'ESC13_ISSUANCE_POLICY_GROUP_LINK'='msDS-OIDToGroupLink'
 'KERBEROS_TICKET_LIFETIME_EXTENDED'='10 часам'
 'ROASTABLE_PRIVILEGED_ACCOUNT'='DONT_REQ_PREAUTH'
 'OU_PERM_PASSWORD_RESET'='Event ID 4724'
 'OU_PERM_GPLINK'='SetAccessRuleProtection'
 'OU_PERM_CONSTRAINED_DELEGATION'='msDS-AllowedToDelegateTo'
 'OU_PERM_RBCD'='msDS-AllowedToActOnBehalfOfOtherIdentity'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D5: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Проверяем собственные 24 записи; общие счётчики меняются в дальнейших этапах.
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D5: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D5: 24 находки; Impact 94, Remediation 101; EN/RU/HTML паритет; остатки 249/229' -ForegroundColor Green
