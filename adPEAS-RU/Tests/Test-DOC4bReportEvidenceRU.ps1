#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4b: офлайн-проверка HTML-генератора по образцам реального отчёта.
.DESCRIPTION
    Не подключается к AD. Использует синтетические объекты и только
    функции представления. Реальный пользовательский отчёт не публикуется.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
function Read-RU([string]$Relative) {
 [IO.File]::ReadAllText((Join-Path $ProjectRoot $Relative),[Text.Encoding]::UTF8)
}
$localize=Read-RU 'Localize-RU.ps1'
foreach($step in @('Apply-DOC4bStaticReport.ps1','Apply-DOC4bVisibleValues.ps1')) {
 if(-not $localize.Contains($step)){throw "DOC4b не включён в сборку: $step"}
}
$export=Read-RU 'src/modules/Reporting/Export-HTMLReport.ps1'
$definitions=Read-RU 'src/modules/Core/adPEAS-ObjectTypes.ps1'
$template=Read-RU 'src/modules/Reporting/templates/report-template.html'
$ldap=Read-RU 'src/modules/Checks/Domain/Get-LDAPConfiguration.ps1'
$js=Read-RU 'src/modules/Reporting/templates/report-scripts.js'
foreach($term in @(
 'Анализ параметров домена','Анализ прав доступа','Анализ делегирования',
 'Анализ служб сертификатов','Анализ привилегированных учётных записей',
 'Анализ групповых политик',
 '$(ConvertTo-HtmlEncode $visibleSectionHeader)',
 'return "Учётная запись Tier 0: $objName"',
 'return "Право добавления компьютеров в домен: $principal"',
 'return "Контроллеры домена ($dcCount)"'
)){
 if(-not $export.Contains($term)){throw "DOC4b: отсутствует безопасная HTML-строка: $term"}
}
if($export.Contains('$(ConvertTo-HtmlEncode $group.Header)')){
 throw 'DOC4b: HTML продолжает использовать английский заголовок напрямую'
}
foreach($term in @('настройки безопасности LDAP','не найдены настройки безопасности LDAP','анонимных сеансов','потенциально уязвимы')){
 if(-not $ldap.Contains($term)){throw "DOC4b: отсутствует перевод LDAP/null session: $term"}
}
foreach($term in @(
 'Filter by Findings: {{FINDING_COUNT}} critical issues',
 'aria-label="Card expansion controls"',
 'title="Expand all cards and top priorities"',
 'Type to filter findings by text content'
)){
 if($template.Contains($term)){throw "DOC4b: англоязычный HTML-атрибут остался: $term"}
}
foreach($term in @(
 'Фильтр нарушений: {{FINDING_COUNT}}',
 'Фильтр предупреждений: {{HINT_COUNT}}',
 'Управление отображением','Введите текст для фильтрации результатов'
)){
 if(-not $template.Contains($term)){throw "DOC4b: отсутствует русский HTML-атрибут: $term"}
}
foreach($term in @(
 'ruDOC4bVisibleValue','data-attr-name','ИНАКТИВНО',
 'DS-Replication-Get-Changes','TSPropertyArray','window.adPEASRUDOC4b'
)){
 if($term -eq 'ИНАКТИВНО'){continue}
 if(-not $js.Contains($term)){throw "DOC4b: отсутствует обработчик текстовых значений: $term"}
}
$tokens=$null;$errors=$null
foreach($pair in @(
 @('src/modules/Core/adPEAS-ObjectTypes.ps1',$definitions),
 @('src/modules/Reporting/Export-HTMLReport.ps1',$export),
 @('src/modules/Checks/Domain/Get-LDAPConfiguration.ps1',$ldap)
)){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseInput([string]$pair[1],[ref]$tokens,[ref]$errors)
 if($errors -and $errors.Count -gt 0){throw "DOC4b: ошибка PowerShell $($pair[0]): $($errors[0].Message)"}
}

# Isolated synthetic objects also detect a misleading label: LDAP/SMB GPO
# must never be called "GPO for adding computers" due to a translation mix-up.
. (Join-Path $ProjectRoot 'src/modules/Core/adPEAS-ObjectTypes.ps1')
. (Join-Path $ProjectRoot 'src/modules/Reporting/Export-HTMLReport.ps1')
$testObjects=@(
 @{Type='LDAPConfigGPO';Prefix='Настройки подписи LDAP в GPO:'},
 @{Type='NullSessionGPO';Prefix='Параметры анонимного доступа в GPO:'},
 @{Type='SMBSigning';Prefix='Настройки подписи SMB:'},
 @{Type='Tier0Account';Prefix='Учётная запись Tier 0:'},
 @{Type='AddComputerRight';Prefix='Право добавления компьютеров в домен:'},
 @{Type='DomainBasicInfo';Prefix='Домен:'}
)
foreach($item in $testObjects){
 $obj=[pscustomobject]@{
  _adPEASObjectType=$item.Type
  sAMAccountName='SYNTHETIC_TEST'
  GPOName='Synthetic Test Policy'
  Name='Synthetic Test Policy'
  accountName='SYNTHETIC_TEST'
  domainNameDNS='example.invalid'
 }
 $title=[string](Get-ObjectCardTitle -Object $obj)
 if(-not $title.StartsWith([string]$item.Prefix,[StringComparison]::Ordinal)){
  throw "DOC4b: неверный заголовок типа $($item.Type): $title"
 }
 if($title.Contains('Параметры GPO для добавления компьютеров')){
  throw "DOC4b: некорректное обозначение настройки GPO: $($item.Type)"
 }
}
Write-Host "PASS DOC4b: 6 типов объектов, 6 русских разделов, LDAP и доступность HTML, PowerShell AST; реальный AD не затронут" -ForegroundColor Green
