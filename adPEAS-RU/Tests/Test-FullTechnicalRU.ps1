#Requires -Version 5.1
<#
.SYNOPSIS
    Автономные проверки полных русских технических описаний находок.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$n=0
function Check([bool]$Ok,[string]$Message){
 if(-not $Ok){throw "FAIL: $Message"}
 $script:n++
 Write-Host "PASS: $Message"
}
$entries=@{}
foreach($name in @('FullTechnical-01.ru-RU.json','FullTechnical-02.ru-RU.json','FullTechnical-Report-03.ru-RU.json','FullTechnical-Report-04.ru-RU.json','FullTechnical-Brief-05.ru-RU.json','FullTechnical-Catalog-06a.ru-RU.json','FullTechnical-Catalog-06b.ru-RU.json','FullTechnical-Catalog-06c.ru-RU.json','FullTechnical-Catalog-06d.ru-RU.json','FullTechnical-Catalog-06e.ru-RU.json')){
 $path=Join-Path $ProjectRoot ('Localization/'+$name)
 Check (Test-Path -LiteralPath $path) ("Словарь $name")
 $json=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8))
 foreach($prop in $json.translations.PSObject.Properties){
  Check (-not $entries.ContainsKey($prop.Name)) ("Уникальный FindingId: "+$prop.Name)
  $entries[$prop.Name]=$prop.Value
 }
}
Check ($entries.Count -eq 392) '392 русских технических описания находок'
foreach($id in @('LDAP_CHANNEL_BINDING_NOT_REQUIRED','LDAP_SIGNING_NOT_REQUIRED','KERBEROASTABLE_SPN','REGISTRY_ESC10_KDC_BINDING','REGISTRY_WSUS_HTTP')){
 Check ($entries.ContainsKey($id)) ("Есть полный перевод для "+$id)
}
foreach($entry in $entries.GetEnumerator()){
 $d=$entry.Value
 Check (-not [string]::IsNullOrWhiteSpace([string]$d.description)) ("Непустое описание: "+$entry.Key)
 Check ($null -ne $d.impact -and $null -ne $d.remediation -and $null -ne $d.attack) ("Структурные поля присутствуют: "+$entry.Key)
 Check (@($d.impact).Count -gt 0 -and @($d.remediation).Count -gt 0) ("Заполнены последствия и рекомендации: "+$entry.Key)
 Check ([string]$d.description -match '[А-Яа-яЁё]') ("Русский текст: "+$entry.Key)
}
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$mergeMarker='const ruFullFindingTechnical = '
$mergeStart=$js.IndexOf($mergeMarker,[StringComparison]::Ordinal)
if($mergeStart -lt 0){throw 'Не найден итоговый встроенный русский словарь'}
$mergeStart+=$mergeMarker.Length
$mergeEnd=$js.IndexOf([char]10,$mergeStart)
if($mergeEnd -lt 0){throw 'Нет границы JSON русского словаря'}
$mergeJson=$js.Substring($mergeStart,$mergeEnd-$mergeStart).Trim().TrimEnd([char]';')
$merged=ConvertFrom-Json -InputObject $mergeJson
$compiled=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'adPEAS.ps1'),[Text.Encoding]::UTF8)
Check ($js.Contains('const ruFullFindingTechnical = ')) 'Полные переводы внедрены в JavaScript'
Check ($js.Contains('Подробное техническое описание')) 'Русский заголовок полного описания'
Check ($js.Contains('Сверить с исходным текстом на английском (EN)')) 'Оригинал английского текста доступен для сверки'
Check (-not $js.Contains('Исходное подробное описание EN (перевод пока не завершён)')) 'Не выводится устаревшая пометка о незавершённом переводе'
Check ($compiled.Contains('В GPO не задано требование LDAP Channel Binding')) 'Технический перевод LDAP Channel Binding включён в сборку'
Check ($compiled.Contains('событие 3039')) 'Указаны события аудита LDAP Channel Binding'
Check ($compiled.Contains('LDAP Simple Bind через LDAPS')) 'Сохранено уточнение о Simple Bind и CBT'
Check ($compiled.Contains('StrongCertificateBindingEnforcement = 2')) 'Сохранён параметр строгой привязки сертификата'
Check ($compiled.Contains('HKEY_LOCAL_MACHINE')) 'Сохранены пути реестра'
Check ($compiled.Contains('Get-ADGroupMember -Identity')) 'Исполняемые команды не удалены'
Check (-not $compiled.Contains('Исходное подробное описание EN (перевод пока не завершён)')) 'В автономной сборке нет устаревшей пометки EN'
# Находки без сценария атаки в оригинале не должны получать искусственные сценарии.
$attackChecked=(ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceVerifiedAttack-07.ru-RU.json'),[Text.Encoding]::UTF8))).translations
$coreChecked=(ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-07.ru-RU.json'),[Text.Encoding]::UTF8))).translations
Check (@($attackChecked.PSObject.Properties).Count -eq 38) '38 сверенных идентификаторов Attack'
Check (@($coreChecked.PSObject.Properties).Count -eq 10) '10 приоритетных сверок Impact и Remediation'
foreach($e in $attackChecked.PSObject.Properties){
 $id=$e.Name
 $a=@($merged.PSObject.Properties[$id].Value.attack)
 Check ($a.Count -eq [int]$e.Value.sourceEnglishAttackStepCount) ("Сохранено число шагов Attack: "+$id)
}
foreach($id in @('GPO_WIDE_IMPACT','GPO_UNLINKED_BROAD_WRITE')){
 Check (@($merged.PSObject.Properties[$id].Value.attack).Count -eq 0) ("Нет вымышленного Attack там, где он отсутствует в оригинале: "+$id)
}
Check ($merged.PSObject.Properties['ESC8_WEB_ENROLLMENT'].Value.description -match 'tokenChecking') 'Сохранена оговорка о неопределённом состоянии EPA'
Check (($merged.PSObject.Properties['ESC1_TEMPLATE'].Value.remediation -join ' ') -match '0x10000') 'Сохранён второй флаг SAN и предупреждение о совместимости'
Check (($merged.PSObject.Properties['GPO_SYSVOL_WRITABLE'].Value.remediation -join ' ') -match 'dcgpofix') 'Сохранено предупреждение против неосторожного dcgpofix'
Check (($merged.PSObject.Properties['OU_PERM_KEYCREDENTIALLINK_WRITE'].Value.remediation -join ' ') -match 'SetAccessRuleProtection') 'Указаны последствия разрыва наследования ACL'

Check (@($merged.PSObject.Properties | Where-Object { @($_.Value.attack).Count -gt 0 }).Count -eq 115) '115 русских сценариев Attack (только там, где они есть в оригинале)'
Check (@($merged.PSObject.Properties['GPO_WIDE_IMPACT'].Value.attack).Count -eq 0) 'Пустой Attack у GPO_WIDE_IMPACT согласован с оригиналом'
Check (@($merged.PSObject.Properties['GPO_UNLINKED_BROAD_WRITE'].Value.attack).Count -eq 0) 'Пустой Attack у GPO_UNLINKED_BROAD_WRITE согласован с оригиналом'
Write-Host "PASS: $n проверок технического перевода; AD не затронут" -ForegroundColor Green
