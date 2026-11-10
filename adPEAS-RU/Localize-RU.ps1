#Requires -Version 5.1
<#
.SYNOPSIS
    Русификация отображаемых строк adPEAS 2.9.0.
.DESCRIPTION
    Не переводит ключи JSON, API, параметры, имена функций, классы опасности и LDAP-атрибуты.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$json=@'
{
  "src/modules/Reporting/templates/report-template.html": {
    "lang=\"en\"": "lang=\"ru\"",
    "adPEAS Security Report - {{DOMAIN}}": "Аудит безопасности Active Directory — {{DOMAIN}}",
    ">adPEAS Security Report<": ">Отчёт по безопасности Active Directory<",
    ">Security Report Summary<": ">Сводка результатов аудита<",
    ">Skip to Top Priority Actions<": ">К первоочередным действиям<",
    ">Skip to Findings<": ">К результатам проверок<",
    ">Skip to Search<": ">К поиску<",
    ">Print / PDF<": ">Печать / PDF<",
    ">Findings by Class<": ">Результаты по категориям<",
    "placeholder=\"Search findings... (press / to focus)\"": "placeholder=\"Поиск по результатам (нажмите /)\"",
    ">Search findings<": ">Поиск результатов<",
    ">Expand All<": ">Развернуть всё<",
    ">Collapse All<": ">Свернуть всё<",
    ">Hide completed<": ">Скрыть выполненные<",
    ">Finding</div>": ">Нарушения</div>",
    ">Hint</div>": ">Предупреждения</div>",
    ">Note</div>": ">Сведения</div>",
    ">Secure</div>": ">Безопасно</div>",
    ">Domain</div>": ">Домен</div>",
    ">Domain Controller</div>": ">Контроллер домена</div>",
    ">User</div>": ">Пользователь</div>",
    ">Generated</div>": ">Создан</div>",
    ">Version</div>": ">Версия</div>",
    "                All <span": "                Все <span",
    "                Finding <span": "                Нарушения <span",
    "                Hint <span": "                Предупреждения <span",
    "                Note <span": "                Сведения <span",
    "                Secure <span": "                Безопасно <span",
    "aria-label=\"Report navigation\"": "aria-label=\"Навигация по отчёту\"",
    "aria-label=\"Report content\"": "aria-label=\"Содержимое отчёта\"",
    "aria-label=\"Toggle theme\"": "aria-label=\"Сменить тему\"",
    "aria-label=\"Print report or save as PDF\"": "aria-label=\"Печать отчёта или сохранение в PDF\"",
    "aria-label=\"Finding counts by severity\"": "aria-label=\"Сводка результатов по категориям\"",
    "aria-label=\"Findings card view\"": "aria-label=\"Карточки результатов\"",
    "aria-label=\"total findings\"": "aria-label=\"Всего результатов\"",
    "aria-label=\"critical findings\"": "aria-label=\"Нарушения\"",
    "aria-label=\"hints\"": "aria-label=\"Предупреждения\"",
    "aria-label=\"notes\"": "aria-label=\"Сведения\"",
    "aria-label=\"secure items\"": "aria-label=\"Безопасные параметры\"",
    "title=\"Toggle Dark/Light Mode\"": "title=\"Переключить оформление\"",
    "title=\"Keyboard Shortcuts (?)\"": "title=\"Горячие клавиши\"",
    "aria-label=\"Show keyboard shortcuts and help\"": "aria-label=\"Показать справку и сочетания клавиш\"",
    "&#63; Help<": "&#63; Справка<"
  },
  "src/modules/Reporting/templates/diff-template.html": {
    "lang=\"en\"": "lang=\"ru\"",
    "adPEAS Scan Comparison": "Сравнение аудитов adPEAS",
    ">Scan Comparison<": ">Сравнение проверок<",
    ">Comparison Summary<": ">Сводка изменений<",
    ">New Findings<": ">Новые нарушения<",
    ">Remediated Findings<": ">Устранённые нарушения<",
    ">Changed Findings<": ">Изменившиеся результаты<",
    ">Unchanged Findings<": ">Без изменений<",
    ">Baseline<": ">Исходный аудит<",
    ">Current<": ">Текущий аудит<",
    ">Domain<": ">Домен<",
    ">Date<": ">Дата<",
    ">Version<": ">Версия<",
    ">New</div>": ">Новые</div>",
    ">Changed</div>": ">Изменились</div>",
    ">Unchanged</div>": ">Без изменений</div>",
    ">Remediated</div>": ">Устранены</div>",
    "Print / PDF": "Печать / PDF"
  },
  "src/modules/Reporting/templates/report-scripts.js": {
    "'Theme changed to '": "'Тема изменена: '",
    "'Copied!'": "'Скопировано!'",
    "'Copy to clipboard'": "'Копировать в буфер обмена'",
    "'No results found'": "'Ничего не найдено'",
    "'No findings found'": "'Результатов нет'",
    "'Search results'": "'Результаты поиска'",
    "'Show all'": "'Показать все'",
    "'Clear search'": "'Очистить поиск'",
    "'Reset filters'": "'Сбросить фильтры'",
    "'Keyboard shortcuts'": "'Горячие клавиши'",
    "\"Keyboard Shortcuts\"": "\"Горячие клавиши\"",
    "\"Top Priority Actions\"": "\"Первоочередные действия\"",
    "\"Print Report\"": "\"Печать отчёта\"",
    "'Finding details'": "'Подробности нарушения'",
    "'Check description'": "'Описание проверки'",
    "'Show information about this check'": "'Описание проверки'",
    "Description</span>": "Описание</span>",
    "Impact</span>": "Последствия</span>",
    "Quick Fix Commands": "Команды исправления",
    "References</span>": "Источники</span>",
    "Tools</span>": "Инструменты</span>",
    ">Copy</button>": ">Копировать</button>",
    "About this Check": "Об этой проверке",
    "Finding (Red)": "Нарушение (красный)",
    "Hint (Yellow)": "Предупреждение (жёлтый)",
    "Note (Blue)": "Сведения (синий)",
    "Secure (Green)": "Безопасно (зелёный)",
    "Clear All Stored Data": "Очистить сохранённые данные",
    "Score Breakdown": "Расчёт оценки риска",
    "No risk score (informational)": "Оценка риска не предусмотрена",
    "Base Score": "Базовая оценка",
    "<span class=\"score-tooltip-label\">Exploitability": "<span class=\"score-tooltip-label\">Возможность эксплуатации",
    " critical findings total": " критических нарушений всего",
    " affected</span>": " затронуто</span>",
    "<span>&#9660;</span> Collapse All": "<span>&#9660;</span> Свернуть всё",
    "<span>&#9654;</span> Expand All": "<span>&#9654;</span> Развернуть всё"
  },
  "src/modules/Core/Render-HtmlObject.ps1": {
    "Show $extendedCount more attribute(s)": "Показать ещё $extendedCount атрибут(ов)"
  },
  "src/modules/Reporting/Export-HTMLReport.ps1": {
    ">Categories</div>": ">Категории</div>",
    ">All Categories": ">Все категории",
    " item(s)</span>": " элементов</span>",
    "1 result</span>": "1 результат</span>"
  },
  "src/adPEAS.ps1": {
    "Show-Header \"Using existing LDAP connection\"": "Show-Header \"Используется существующее LDAP-подключение\"",
    "Show-Header \"Establishing LDAP Connection\"": "Show-Header \"Установка LDAP-подключения\"",
    "Show-Header \"Scan Summary\"": "Show-Header \"Сводка аудита\"",
    "Show-Header \"LDAP Statistics Summary\"": "Show-Header \"Сводная статистика LDAP\"",
    "Show-Line \"Duration: 0 seconds\"": "Show-Line \"Продолжительность: 0 секунд\"",
    "Show-Line \"Executing Modules:": "Show-Line \"Запуск модулей:",
    "Show-Line \"Duration:": "Show-Line \"Продолжительность:",
    "Show-Line \"Text report saved to:": "Show-Line \"Текстовый отчёт сохранён:",
    "Show-Line \"HTML report saved to:": "Show-Line \"HTML-отчёт сохранён:",
    "Show-Line \"JSON export saved to:": "Show-Line \"JSON-данные сохранены:",
    "Show-Line \"CRITICAL ERROR:": "Show-Line \"КРИТИЧЕСКАЯ ОШИБКА:",
    "Show-Error -Type HealthCheck -Message \"Domain Controller is not responding\"": "Show-Error -Type HealthCheck -Message \"Контроллер домена не отвечает\"",
    "Show-Line \"Scan was aborted due to invalid LDAP session. No reports were generated.\"": "Show-Line \"Аудит прерван: недействительная LDAP-сессия. Отчёты не созданы.\"",
    "Show-Line \"Re-authenticate with Connect-adPEAS and try again.\"": "Show-Line \"Подключитесь повторно через Connect-adPEAS и повторите проверку.\""
  }
}
'@
$maps=ConvertFrom-Json -InputObject $json
$utf8=New-Object Text.UTF8Encoding($true)
foreach($f in $maps.PSObject.Properties){
 $path=Join-Path $ProjectRoot $f.Name
 if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Нет файла: $($f.Name)"}
 $src=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
 $dst=$src
 $n=0
 foreach($item in @($f.Value.PSObject.Properties | Sort-Object {$_.Name.Length} -Descending)){
  if($dst.Contains([string]$item.Name)){
   $n+=([regex]::Matches($dst,[regex]::Escape([string]$item.Name))).Count
   $dst=$dst.Replace([string]$item.Name,[string]$item.Value)
  }
 }
 if($dst -ne $src){[IO.File]::WriteAllText($path,$dst,$utf8)}
 Write-Host "[RU] $($f.Name): $n замен"
}

# Каталоги описаний, находок и полей HTML. Раздельные этапы предотвращают
# случайную замену JS-идентификаторов и машинных атрибутов AD.
& (Join-Path $PSScriptRoot 'Localization/Apply-Catalogs.ps1') -ProjectRoot $ProjectRoot
if(-not $?){throw 'Ошибка локализации справочников HTML'}
& (Join-Path $PSScriptRoot 'Localization/Apply-TooltipUI.ps1') -ProjectRoot $ProjectRoot
if(-not $?){throw 'Ошибка локализации подсказок HTML'}

& (Join-Path $PSScriptRoot 'Localization/Apply-CheckHeaders.ps1') -ProjectRoot $ProjectRoot
if(-not $?){throw 'Ошибка локализации заголовков модулей'}

& (Join-Path $PSScriptRoot 'Localization/Apply-CheckLines.ps1') -ProjectRoot $ProjectRoot
if(-not $?){throw 'Ошибка локализации сообщений проверок'}
