#Requires -Version 5.1
<#
.SYNOPSIS
  Автономные регрессионные тесты русской справки и предупреждения о лицензии.
.NOTES
  Тест не подключается к Active Directory.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$checks=0
function Assert-RU([bool]$Ok,[string]$Name) {
 if(-not $Ok){throw "FAIL: $Name"}
 $script:checks++
 Write-Host "PASS: $Name"
}
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'),[Text.Encoding]::UTF8)
$export=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/modules/Reporting/Export-HTMLReport.ps1'),[Text.Encoding]::UTF8)
$main=[IO.File]::ReadAllText((Join-Path $ProjectRoot 'src/adPEAS.ps1'),[Text.Encoding]::UTF8)
$license=Join-Path $ProjectRoot 'license/LICENSE.md'
$start=$js.IndexOf('function createShortcutHelpModal() {')
$end=$js.IndexOf('        // Clear all adPEAS data from localStorage',$start)
Assert-RU ($start -ge 0 -and $end -gt $start) 'Границы модального окна справки'
$help=$js.Substring($start,$end-$start)
$expected=@(
 'Руководство по отчёту',
 'Структура отчёта',
 'Сводные карточки',
 'Первоочередные меры',
 'Разделы аудита',
 'Карточки результатов',
 'Уровни критичности',
 'Интерактивные возможности',
 'Кнопки справки',
 'Флажки выполнения',
 'Оценки риска',
 'Фильтры',
 'Горячие клавиши',
 'Переход между результатами',
 'Развернуть или свернуть',
 'Отметить выполненным',
 'Скрыть выполненные',
 'Советы по работе с отчётом',
 'Хранение данных',
 'Данные хранятся только в этом браузере',
 'Отметки выполненных результатов',
 'Удалить сохранённые данные adPEAS из браузера'
)
foreach($ru in $expected){Assert-RU ($help.Contains($ru)) ("Текст справки: "+$ru)}
$old=@(
 'Report Guide', 'Report Structure', 'Summary Cards', 'Top Priority Actions',
 'Quick overview at the top', 'AI-scored findings', 'Severity Levels',
 'Interactive Features', 'Finding Cards', 'Keyboard Shortcuts',
 'Navigate findings', 'Data Management', 'The report is organized by',
 'Security vulnerability or misconfiguration',
 'Data is stored only in this browser'
)
foreach($en in $old){Assert-RU (-not $help.Contains($en)) ("Не осталось английского фрагмента: "+$en)}
Assert-RU ($help.Contains('onclick="hideShortcutHelp()"')) 'Функция закрытия справки не изменена'
Assert-RU ($help.Contains('onclick="clearAdPEASData()"')) 'Кнопка очистки данных продолжает вызывать исходную функцию'
Assert-RU ($help.Contains('id="helpModalTitle"')) 'ID заголовка справки сохранён'
Assert-RU ($help.Contains('class="shortcut-grid"')) 'Разметка горячих клавиш сохранена'
Assert-RU ($export.Contains('Этот отчёт сформирован инструментом, для использования которого в консалтинге или при оказании управляемых услуг требуется действующая коммерческая лицензия.')) 'Юридическое предупреждение переведено корректно'
Assert-RU ($export.Contains('This report was generated using a tool that requires a valid commercial license for consulting or managed service use.')) 'Оригинальный юридический текст сохранён в коде сопоставления'
Assert-RU ($export.Contains('$disclaimerForDisplay = [string]$disclaimer')) 'Отображаемый текст отдельно от оригинала'
Assert-RU ($export.Contains("Replace('{{DISCLAIMER}}', [string](ConvertTo-HtmlEncode "+'$disclaimerForDisplay'+" ))") -eq $false) 'Подстановка лицензии экранирует HTML и сохраняет шаблон'
Assert-RU (Test-Path -LiteralPath $license -PathType Leaf) 'Оригинальная лицензия присутствует в проекте'
Assert-RU ($main.Contains('adPEASDisclaimer')) 'Исходный механизм юридического предупреждения сохранён'
Write-Host "PASS: $checks проверок справки и уведомления о лицензии; AD не затронут" -ForegroundColor Green
