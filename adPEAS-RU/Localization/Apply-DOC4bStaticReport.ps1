#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4b: генерация русских заголовков HTML по фактическому отчёту.
.DESCRIPTION
    Только выводимые заголовки и подсказки; риск, проверки, FindingId,
    технические свойства и исходные объекты AD остаются неизменными.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($true)
function Read-Text([string]$Relative) {
 [IO.File]::ReadAllText((Join-Path $ProjectRoot $Relative),[Text.Encoding]::UTF8)
}
function Save-PS([string]$Relative,[string]$Text) {
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
 if($errors -and $errors.Count -gt 0){throw "DOC4b: синтаксис $Relative : $($errors[0].Message)"}
 [IO.File]::WriteAllText((Join-Path $ProjectRoot $Relative),$Text,$utf8)
}
function Change-Exact([string]$Before,[string]$After,[int]$Expected=1) {
 $n=([regex]::Matches($script:src,[regex]::Escape($Before))).Count
 if($n -ne $Expected){throw "DOC4b: $script:relative ожидается $Expected, найдено $n : $Before"}
 $script:src=$script:src.Replace($Before,$After)
}

$relative='src/modules/Reporting/Export-HTMLReport.ps1'
$src=Read-Text $relative
$marker='            $categoryEncoded = ConvertTo-HtmlEncode $categorySlug'
$inject=@'
            # DOC4b: only the emitted HTML label is localized. Group keys remain original.
            $visibleSectionHeader = [string]$group.Header
            $ruSectionNames = @{
                'Analyzing Domain Configuration' = 'Анализ параметров домена'
                'Analyzing Access Permissions' = 'Анализ прав доступа'
                'Analyzing Delegation Settings' = 'Анализ делегирования'
                'Analyzing Certificate Services' = 'Анализ служб сертификатов'
                'Analyzing Privileged Accounts' = 'Анализ привилегированных учётных записей'
                'Analyzing Group Policy Objects' = 'Анализ групповых политик'
                'Analyzing Credential Exposure' = 'Анализ раскрытия учётных данных'
                'Analyzing Computer Security' = 'Анализ безопасности компьютеров'
                'Analyzing Application Infrastructure' = 'Анализ инфраструктуры приложений'
            }
            foreach($pair in $ruSectionNames.GetEnumerator()){
                if($visibleSectionHeader.EndsWith([string]$pair.Key,[StringComparison]::Ordinal)){
                    $visibleSectionHeader=$visibleSectionHeader.Substring(0,$visibleSectionHeader.Length - $pair.Key.Length)+$pair.Value
                    break
                }
            }
'@
Change-Exact $marker ($inject+[string][char]10+$marker)
Change-Exact '$(ConvertTo-HtmlEncode $group.Header)' '$(ConvertTo-HtmlEncode $visibleSectionHeader)'
$titlePairs=@(
 @('return "Tier-0 Account: $objName ($context)"','return "Учётная запись Tier 0: $objName ($context)"'),
 @('return "Tier-0 Account: $objName"','return "Учётная запись Tier 0: $objName"'),
 @('return "Operator Group: $grpName"','return "Операторская группа: $grpName"'),
 @('return "SID History: $objName$ctxInfo"','return "История SID: $objName$ctxInfo"'),
 @('return "Credential ($credType)"','return "Учётные данные ($credType)"'),
 @('return "LAPS Config: $ouName"','return "Конфигурация LAPS: $ouName"'),
 @('return "Domain: $domainName"','return "Домен: $domainName"'),
 @('return "Domain Controllers ($dcCount)"','return "Контроллеры домена ($dcCount)"'),
 @('return "Fine-Grained Policy: $psoName"','return "Тонкая политика паролей: $psoName"'),
 @('return "Trust: $trustTarget"','return "Доверительное отношение: $trustTarget"'),
 @('return "GPO Local Group: $localGrp$gpoName"','return "Локальная группа через GPO: $localGrp$gpoName"'),
 @('return "Scheduled Task: $taskName"','return "Запланированная задача: $taskName"'),
 @('return "Add Computer Right: $principal"','return "Право добавления компьютеров в домен: $principal"')
)
foreach($p in $titlePairs){Change-Exact ([string]$p[0]) ([string]$p[1])}
Save-PS $relative $src

$relative='src/modules/Checks/Domain/Get-LDAPConfiguration.ps1'
$src=Read-Text $relative
$checks=@(
 @("FoundText         = 'LDAP security configuration'","FoundText         = 'безопасности LDAP'"),
 @("FoundText         = 'null session configuration'","FoundText         = 'анонимных сеансов'"),
 @('NoneActiveText    = "No LDAP security configuration is deployed by a policy that is linked and enabled - all $dcCount DC(s) potentially vulnerable"','NoneActiveText    = "Ни одна привязанная и включённая GPO не применяет настройки безопасности LDAP — все $dcCount контроллеров домена потенциально уязвимы"'),
 @('NoneFoundText     = "No LDAP Security configuration found in any GPO - all $dcCount DC(s) potentially vulnerable"','NoneFoundText     = "Ни в одной GPO не найдены настройки безопасности LDAP — все $dcCount контроллеров домена потенциально уязвимы"'),
 @("NoneActiveText    = 'No null session setting is deployed by a policy that is linked and enabled - the domain controllers keep the OS defaults'","NoneActiveText    = 'Ни одна привязанная и включённая GPO не задаёт параметры анонимных сеансов — контроллеры домена используют настройки ОС по умолчанию'"),
 @("NoneFoundText     = 'No null session setting found in any GPO - the domain controllers keep the OS defaults'","NoneFoundText     = 'Ни в одной GPO не найдены параметры анонимных сеансов — контроллеры домена используют настройки ОС по умолчанию'")
)
foreach($p in $checks){Change-Exact ([string]$p[0]) ([string]$p[1])}
Save-PS $relative $src

$relative='src/modules/Reporting/templates/report-template.html'
$src=Read-Text $relative
$labels=@(
 @('Filter by Findings: {{FINDING_COUNT}} critical issues','Фильтр нарушений: {{FINDING_COUNT}}'),
 @('Filter by Hints: {{HINT_COUNT}} items','Фильтр предупреждений: {{HINT_COUNT}}'),
 @('Filter by Notes: {{NOTE_COUNT}} items','Фильтр сведений: {{NOTE_COUNT}}'),
 @('Filter by Secure: {{SECURE_COUNT}} items','Фильтр безопасных результатов: {{SECURE_COUNT}}'),
 @('aria-label="View controls"','aria-label="Управление отображением"'),
 @('aria-label="Card expansion controls"','aria-label="Разворачивание карточек"'),
 @('title="Expand all cards and top priorities"','title="Развернуть все карточки и приоритетные рекомендации"'),
 @('title="Collapse all cards and top priorities"','title="Свернуть все карточки и приоритетные рекомендации"'),
 @('aria-label="Expand all finding cards"','aria-label="Развернуть карточки результатов"'),
 @('aria-label="Collapse all finding cards"','aria-label="Свернуть карточки результатов"'),
 @('Type to filter findings by text content','Введите текст для фильтрации результатов'),
 @('Toggle to show or hide findings marked as completed','Показать или скрыть отмеченные как выполненные результаты')
)
foreach($p in $labels){Change-Exact ([string]$p[0]) ([string]$p[1])}
[IO.File]::WriteAllText((Join-Path $ProjectRoot $relative),$src,$utf8)
Write-Host "[RU] PASS DOC4b/DOC4d: 9 заголовков разделов, $($titlePairs.Count) названий объектов, 6 сообщений LDAP и $($labels.Count) доступных подписей"
