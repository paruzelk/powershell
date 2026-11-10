#Requires -Version 5.1
<#
.SYNOPSIS
    Полная русификация окна «Справка» HTML-отчёта adPEAS.
.DESCRIPTION
    Меняет только человекочитаемые тексты модального окна createShortcutHelpModal.
    ID элементов, названия CSS-классов, JS-функции и клавиатурные события сохраняются.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'

$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$begin=$source.IndexOf('function createShortcutHelpModal() {')
$end=$source.IndexOf('        // Clear all adPEAS data from localStorage',$begin)
if($begin -lt 0 -or $end -lt 0 -or $end -le $begin){
    throw 'Не найдены границы окна справки. Неизвестную версию не изменяем.'
}
$help=$source.Substring($begin,$end-$begin)
$mapJson=@'
{
  ">Report Guide<": ">Руководство по отчёту<",
  "aria-label=\"Close help dialog\"": "aria-label=\"Закрыть окно справки\"",
  ">Report Structure<": ">Структура отчёта<",
  "The report is organized by security check categories (Domain, Accounts, Delegation, Rights, etc.). Each category contains multiple checks, and each check can have multiple findings.": "Отчёт сгруппирован по разделам аудита безопасности: домен, учётные записи, делегирование, права доступа и другие. В каждом разделе может быть несколько проверок, а в каждой проверке — несколько результатов.",
  ">Summary Cards<": ">Сводные карточки<",
  "Quick overview at the top showing total counts by severity level. Click a card to filter.": "В верхней части отчёта показано количество результатов по уровням критичности. Нажмите карточку, чтобы отфильтровать результаты.",
  ">Top Priority Actions<": ">Первоочередные меры<",
  "AI-scored findings ranked by risk. Start here for the most critical issues.": "Обнаруженные проблемы отсортированы по расчётной оценке риска. Начните с нарушений с наивысшим приоритетом.",
  ">Categories<": ">Разделы аудита<",
  "Expandable sections grouping related security checks together.": "Раскрываемые разделы объединяют тематически связанные проверки безопасности.",
  ">Finding Cards<": ">Карточки результатов<",
  "Individual findings with details. Click to expand and see all attributes.": "Каждая карточка содержит подробности обнаруженного результата. Нажмите её, чтобы раскрыть сведения и атрибуты.",
  ">Severity Levels<": ">Уровни критичности<",
  "Security vulnerability or misconfiguration requiring immediate attention.": "Уязвимость или опасная настройка, требующая приоритетной проверки и устранения.",
  "Potentially interesting finding that may warrant investigation.": "Потенциально значимый результат, требующий дополнительного анализа.",
  "Informational finding providing context or general information.": "Справочная информация о конфигурации и состоянии инфраструктуры.",
  "Security configuration is properly set - no action needed.": "Проверенная настройка соответствует ожидаемому безопасному состоянию; исправление не требуется.",
  ">Interactive Features<": ">Интерактивные возможности<",
  ">? Help Buttons<": ">Кнопки справки «?»<",
  "Click the blue ? buttons next to check titles or findings for detailed explanations and remediation steps.": "Нажмите кнопку «?» рядом с названием проверки или результатом, чтобы увидеть пояснения, возможные последствия и рекомендации по устранению.",
  ">Checkboxes<": ">Флажки выполнения<",
  "Mark findings as completed. Progress is saved in your browser and persists across sessions.": "Отмечайте проверенные или устранённые результаты. Отметки сохраняются в браузере и доступны при повторном открытии отчёта.",
  ">Score Badges<": ">Оценки риска<",
  "Each finding shows a calculated risk score badge. Findings are automatically sorted by score, highest first.": "У результата отображается расчётная оценка риска. Карточки автоматически сортируются по убыванию этой оценки.",
  ">Filters<": ">Фильтры<",
  "Use severity and category dropdowns to focus on specific finding types.": "Используйте фильтры по критичности и разделам, чтобы отобрать необходимые результаты проверки.",
  ">Keyboard Shortcuts<": ">Горячие клавиши<",
  ">Navigate findings<": ">Переход между результатами<",
  ">Expand / Collapse<": ">Развернуть или свернуть<",
  ">Mark completed<": ">Отметить выполненным<",
  ">Hide completed<": ">Скрыть выполненные<",
  ">Search<": ">Поиск<",
  ">Close / Clear<": ">Закрыть окно или очистить поле<",
  "<span class=\"shortcut-key\">Space</span>": "<span class=\"shortcut-key\">Пробел</span>",
  ">Tips<": ">Советы по работе с отчётом<",
  "<strong>Start with Top Priority Actions</strong> - These are automatically ranked by exploitability and impact.": "<strong>Начните с первоочередных мер.</strong> Результаты ранжируются по оценке возможности эксплуатации и потенциальным последствиям.",
  "<strong>Use the search</strong> - Quickly find specific accounts, computers, or groups by name.": "<strong>Используйте поиск.</strong> Находите учётные записи, компьютеры и группы по имени.",
  "<strong>Mark as you go</strong> - Check off findings as you remediate them to track progress.": "<strong>Отмечайте выполненное.</strong> Устанавливайте флажки после проверки или устранения проблем, чтобы отслеживать ход работы.",
  ">Data Management<": ">Хранение данных<",
  "This report stores preferences and progress in your browser's local storage:": "Настройки и отметки выполнения сохраняются в локальном хранилище браузера:",
  "Completed findings (checkboxes)": "Отметки выполненных результатов (флажки)",
  "Theme preference (Dark/Light)": "Выбранная тема оформления (тёмная или светлая)",
  "Hide completed toggle state": "Состояние переключателя «Скрыть выполненные»",
  "Data is stored only in this browser and is not sent anywhere. Each report has its own completion tracking.": "Данные хранятся только в этом браузере и никуда не отправляются. Для каждого отчёта отметки выполнения сохраняются отдельно.",
  "title=\"Remove all adPEAS data from browser storage\"": "title=\"Удалить сохранённые данные adPEAS из браузера\""
}
'@
$map=ConvertFrom-Json -InputObject $mapJson
$count=0
foreach($entry in $map.PSObject.Properties){
    $from=[string]$entry.Name
    $to=[string]$entry.Value
    $matches=[regex]::Matches($help,[regex]::Escape($from)).Count
    if($matches -ne 1){
        throw "Неоднозначная строка справки ($matches вхождений): $from"
    }
    $help=$help.Replace($from,$to)
    $count++
}
if($count -lt 38){throw "Переведено мало строк справки: $count"}
$result=$source.Substring(0,$begin)+$help+$source.Substring($end)
[IO.File]::WriteAllText($path,$result,(New-Object Text.UTF8Encoding($true)))
Write-Host "[RU] PASS: вся справка HTML переведена ($count строк), JS-идентификаторы сохранены"
