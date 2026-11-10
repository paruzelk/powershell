#Requires -Version 5.1
<#
.SYNOPSIS
    Регрессионные тесты русификации содержимого HTML-карточек, без AD.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$n=0
function Check([bool]$Ok,[string]$Title) {
 if(-not $Ok){throw "FAIL: $Title"}
 $script:n++
 Write-Host "PASS: $Title"
}
function Read-RU([string]$Relative){
 [IO.File]::ReadAllText((Join-Path $ProjectRoot $Relative),[Text.Encoding]::UTF8)
}
$obj=Read-RU 'src/modules/Core/adPEAS-ObjectTypes.ps1'
$rights=Read-RU 'src/modules/Core/adPEAS-UserRights.ps1'
$gpo=Read-RU 'src/modules/Checks/Rights/Get-GPOUserRightsAssignment.ps1'
$acl=Read-RU 'src/modules/Checks/Rights/Get-DangerousACLs.ps1'
$js=Read-RU 'src/modules/Reporting/templates/report-scripts.js'
$release=Read-RU 'adPEAS.ps1'
Check ($obj.Contains('TitleFormat = "Опасные разрешения ACL: {Name}"')) 'Русское название карточки опасных ACL'
Check ($obj.Contains('TitleFormat = "Право пользователя в GPO: {UserRightName}"')) 'Русское название карточки права пользователя GPO'
Check (-not $obj.Contains('TitleFormat = "GPO User Right:')) 'Английский шаблон GPO отсутствует'
Check (-not $obj.Contains('TitleFormat = "Dangerous ACL:')) 'Английский шаблон опасных ACL отсутствует'
Check ($rights.Contains("Name = 'Отладка программ'")) 'Терминология Windows: отладка программ'
Check ($rights.Contains("Name = 'Замена токена уровня процесса'")) 'Терминология Windows: замена токена'
Check ($rights.Contains("Name = 'Формирование аудита безопасности'")) 'Терминология Windows: формирование аудита'
Check ($rights.Contains("Name = 'Архивирование файлов и каталогов'")) 'Терминология Windows: архивирование'
Check (-not $rights.Contains("Name = 'Debug programs'")) 'Нет старой английской подписи права'
Check ($rights.Contains("'SeDebugPrivilege' = @{")) 'Сохранён канонический ключ SeDebugPrivilege'
Check ($gpo.Contains('Назначений, удаляющих только стандартных субъектов:')) 'Русская сводка исключений прав GPO'
Check ($gpo.Contains('Обнаружено назначений прав пользователя с отклонением')) 'Русская сводка отклонений GPO'
Check ($acl.Contains('Обнаружены субъекты с правами DCSync')) 'Русская сводка DCSync'
Check ($acl.Contains('Обнаружены субъекты с опасными правами на корневой объект')) 'Русская сводка ACL'
Check ($js.Contains('Первоочередные меры по устранению рисков')) 'Русский блок приоритетных рекомендаций'
Check ($js.Contains('ruFindingExplanations[findingIdRu]')) 'Используются конкретные русские рекомендации по FindingId'
Check ($js.Contains('Точная рекомендация разработчика (оригинал EN)')) 'Оригинальное исправление доступно для проверки'
Check ($js.Contains('Права доступа') -and $js.Contains('Групповые политики')) 'Перевод категорий в приоритетных действиях'
Check ($release.Contains('Право пользователя в GPO: {UserRightName}')) 'Перевод GPO вошёл в готовый автономный модуль'
Check ($release.Contains('Обнаружены субъекты с правами DCSync')) 'Перевод результатов DCSync вошёл в сборку'
$exporter=Read-RU 'src/modules/Reporting/Export-HTMLReport.ps1'
Check ($exporter.Contains('Все категории')) 'Русский пункт Все категории'
Check ($exporter.Contains("Accounts='Учётные записи'")) 'Переведено название Accounts без изменения ID'
Check ($exporter.Contains("Rights='Права доступа'")) 'Переведено название Rights без изменения ID'
Check ($exporter.Contains('> Развернуть всё</button>')) 'Кнопка раскрытия объектов на русском'
Check ($js.Contains('Первоочередные меры по устранению рисков')) 'Заголовок приоритетных мер на русском'
Write-Host "PASS: $n проверок русского текста карточек" -ForegroundColor Green
