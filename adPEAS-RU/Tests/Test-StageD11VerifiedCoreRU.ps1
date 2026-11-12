#Requires -Version 5.1
<#
.SYNOPSIS
    D11: автономная проверка 24 полных Impact/Remediation по оригиналу adPEAS 2.9.0.
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
if($begin -lt 0){throw 'D11: русский словарь находок не найден'}
$begin+=$marker.Length
$end=$js.IndexOf([char]10,$begin)
if($end -lt 0){throw 'D11: словарь находок не завершён'}
$ru=ConvertFrom-Json -InputObject ($js.Substring($begin,$end-$begin).Trim().TrimEnd([char]';'))
if(@($ru.PSObject.Properties).Count -ne 392){throw 'D11: ожидается ровно 392 FindingId'}
$expectedIds=@(
 'GPO_USERRIGHT_SERELABEL',
 'GPO_USERRIGHT_SEREMOTESHUTDOWN',
 'GPO_USERRIGHT_SESHUTDOWN',
 'GPO_USERRIGHT_SESYNCAGENT',
 'GPO_USERRIGHT_SESYSTEMENVIRONMENT',
 'GPO_USERRIGHT_SESYSTEMTIME',
 'GPO_USERRIGHT_SETRUSTEDCREDMANACCESS',
 'NO_ACCOUNT_LOCKOUT',
 'NO_MIN_PASSWORD_AGE',
 'PASSWORD_NEVER_EXPIRES',
 'PASSWORD_NOT_REQUIRED',
 'WEAK_PASSWORD_POLICY',
 'SMB_SIGNING_DISABLED',
 'SMB_SIGNING_REQUIRED',
 'PREWIN2000_ANONYMOUS_MEMBER',
 'PREWIN2000_BROAD_MEMBER',
 'REVERSIBLE_ENCRYPTION',
 'KERBEROAST_WITHOUT_PREAUTH',
 'UNCONSTRAINED_DELEGATION_DC',
 'UNCONSTRAINED_DELEGATION_EXPOSED_ACCOUNTS',
 'TRUST_SID_FILTERING_DISABLED',
 'WEAK_LOCKOUT_DURATION',
 'WEAK_FGPP',
 'OLD_FUNCTIONAL_LEVEL'
)
function Get-OriginalItems([string]$id,[string]$field){
 $needle="    '$id' = @{"
 $start=$source.IndexOf($needle,[StringComparison]::Ordinal)
 if($start -lt 0){throw "D11: в оригинале отсутствует FindingId $id"}
 $stop=$source.IndexOf(([string][char]10+'    }'),$start,[StringComparison]::Ordinal)
 if($stop -lt 0){throw "D11: не закрыт оригинальный блок $id"}
 $block=$source.Substring($start,$stop-$start)
 $expression='(?ms)^[ \t]{8}'+$field+'[ \t]*=[ \t]*@\([ \t]*\n(?<items>.*?)^[ \t]{8}\)'
 $match=[regex]::Match($block,$expression)
 if(-not $match.Success){throw "D11: поле $field отсутствует в оригинале $id"}
 return @([regex]::Matches($match.Groups['items'].Value,'(?m)^[ \t]{12}"(?<value>(?:\x60.|[^"])*)"') |
   ForEach-Object {$_.Groups['value'].Value})
}
$all=@{}
$catalogNames=@('SourceVerifiedCore-20a.ru-RU.json','SourceVerifiedCore-20b.ru-RU.json')
foreach($catalogName in $catalogNames){
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot ('Localization/'+$catalogName)),[Text.Encoding]::UTF8))
 if(@($catalog.translations.PSObject.Properties).Count -ne 12){
  throw "D11: в каталоге $catalogName ожидается 12 записей"
 }
 foreach($item in $catalog.translations.PSObject.Properties){
  $id=[string]$item.Name
  if($all.ContainsKey($id)){throw "D11: повтор FindingId $id"}
  $all[$id]=$item.Value
 }
}
$ids=@($all.Keys | Sort-Object)
$expected=@($expectedIds | Sort-Object)
if($all.Count -ne 24 -or ($ids -join [char]10) -cne ($expected -join [char]10)){
 throw 'D11: набор 24 закреплённых FindingId изменён'
}
$totals=@{Impact=0;Remediation=0}
foreach($id in $expectedIds){
 $entry=$ru.PSObject.Properties[$id]
 if($null -eq $entry){throw "D11: русский HTML не содержит FindingId $id"}
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
   throw "D11: пропущен пункт $id / $field"
  }
  for($i=0;$i -lt $n;$i++){
   if([string]$original[$i] -cne [string]$en[$i]){
    throw "D11: изменён EN-источник $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -cne [string]$shown[$i]){
    throw "D11: русский каталог и HTML различаются $id / $field / $($i+1)"
   }
   if([string]$translated[$i] -notmatch '[А-Яа-яЁё]'){
    throw "D11: непереведённая строка $id / $field / $($i+1)"
   }
  }
  $totals[$field]+=$n
 }
}
if($totals.Impact -ne 77 -or $totals.Remediation -ne 77){
 throw "D11: неверные итоги Impact=$($totals.Impact) Remediation=$($totals.Remediation)"
}
# Контроль смысловых границ и технических идентификаторов в русском HTML.
$semanticGuards=@{
 'GPO_USERRIGHT_SERELABEL'='Mandatory Integrity Control'
 'GPO_USERRIGHT_SEREMOTESHUTDOWN'='из любой точки сети'
 'GPO_USERRIGHT_SESHUTDOWN'='из локального сеанса'
 'GPO_USERRIGHT_SESYNCAGENT'='DCSync'
 'GPO_USERRIGHT_SESYSTEMENVIRONMENT'='BitLocker'
 'GPO_USERRIGHT_SESYSTEMTIME'='Kerberos'
 'GPO_USERRIGHT_SETRUSTEDCREDMANACCESS'='не назначает это право'
 'NO_ACCOUNT_LOCKOUT'='10–15'
 'NO_MIN_PASSWORD_AGE'='24 предыдущих'
 'PASSWORD_NEVER_EXPIRES'='gMSA'
 'PASSWORD_NOT_REQUIRED'='PASSWD_NOTREQD'
 'WEAK_PASSWORD_POLICY'='Fine-Grained Password Policies'
 'SMB_SIGNING_DISABLED'='МФУ'
 'SMB_SIGNING_REQUIRED'='исправление не требуется'
 'PREWIN2000_ANONYMOUS_MEMBER'='Anonymous Logon'
 'PREWIN2000_BROAD_MEMBER'='само по себе не доказывает ошибку'
 'REVERSIBLE_ENCRYPTION'='NTDS.dit'
 'KERBEROAST_WITHOUT_PREAUTH'='AS-REQ'
 'UNCONSTRAINED_DELEGATION_DC'='Не снимайте флаг'
 'UNCONSTRAINED_DELEGATION_EXPOSED_ACCOUNTS'='не служебные и не компьютерные'
 'TRUST_SID_FILTERING_DISABLED'='TRUST_TREAT_AS_EXTERNAL'
 'WEAK_LOCKOUT_DURATION'='MFA'
 'WEAK_FGPP'='msDS-PasswordSettingsPrecedence'
 'OLD_FUNCTIONAL_LEVEL'='2012 R2'
}
foreach($id in $semanticGuards.Keys){
 $item=$ru.PSObject.Properties[$id]
 $visible=(@($item.Value.impact)+@($item.Value.remediation)) -join ' '
 if($visible -notmatch [regex]::Escape([string]$semanticGuards[$id])){
  throw "D11: утрачена важная оговорка у $id"
 }
}
$parity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceFieldParity392.json'),[Text.Encoding]::UTF8))
# Глобальные показатели могут изменяться в следующих этапах; D11 сверяет собственные ID.
foreach($id in $expectedIds){
 if(@($parity.ImpactStepCountDifferences) -ccontains $id -or
    @($parity.RemediationStepCountDifferences) -ccontains $id){
  throw "D11: структурное расхождение у переведённой находки $id"
 }
}
Write-Host 'PASS D11: 24 находки; Impact 77, Remediation 77; EN/RU/HTML паритет и стабильность 24 ID' -ForegroundColor Green
