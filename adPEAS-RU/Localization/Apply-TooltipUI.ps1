#Requires -Version 5.1
<#
.SYNOPSIS
    Перевод карточек находок и помощи по проверкам в HTML-отчёте.
.NOTES
    Значения FindingId и поля оценки риска сохраняются без изменений.
    Для непереведённых длинных технических объяснений сохраняется скрытый оригинал EN.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$jsPath=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($jsPath,[Text.Encoding]::UTF8)
function Replace-RU([string]$Before,[string]$After){
 if(-not $script:js.Contains($Before)){throw "Не найден фрагмент JS: $Before"}
 $script:js=$script:js.Replace($Before,$After)
}
$before='class="tooltip-title">' + '$' + '{escapeHtml(finding.title)}'
$after='class="tooltip-title">' + '$' + '{escapeHtml(ruFindingTitles[findingId] || finding.title)}'
Replace-RU $before $after
Replace-RU "label: 'FINDING'" "label: 'НАРУШЕНИЕ'"
Replace-RU "label: 'HINT'" "label: 'ПРЕДУПРЕЖДЕНИЕ'"
Replace-RU "label: 'NOTE'" "label: 'СВЕДЕНИЯ'"
Replace-RU "label: 'SECURE'" "label: 'БЕЗОПАСНО'"
$map=@{
 '<span class="toggle-icon">&#9660;</span> Description'='<span class="toggle-icon">&#9660;</span> Описание'
 '<span class="toggle-icon">&#9660;</span> Impact'='<span class="toggle-icon">&#9660;</span> Последствия'
 '<span class="toggle-icon">&#9660;</span> References'='<span class="toggle-icon">&#9660;</span> Источники'
 '<span class="toggle-icon">&#9660;</span> Tools'='<span class="toggle-icon">&#9660;</span> Инструменты'
 "isSecure ? 'Blocked Attack Vectors' : 'Attack Steps'"="isSecure ? 'Предотвращаемые угрозы' : 'Этапы атаки'"
 "isSecureConfig ? 'Best Practices' : 'Remediation'"="isSecureConfig ? 'Поддержание защиты' : 'Меры по устранению'"
 'class="check-tooltip-section-title">Secure Configuration'='class="check-tooltip-section-title">Безопасная конфигурация'
 'class="check-tooltip-section-title">Why It Matters'='class="check-tooltip-section-title">Почему это важно'
 'class="check-tooltip-section-title">What We Check'='class="check-tooltip-section-title">Что проверяется'
 'class="check-tooltip-section-title">Output Filtering'='class="check-tooltip-section-title">Фильтрация результатов'
 'Example commands for reference only. Always test in a non-production environment first and adapt to your specific situation.'='Команды приведены как примеры. Перед применением проверьте их в тестовой среде и адаптируйте к вашей инфраструктуре.'
}
foreach($item in $map.GetEnumerator()){
 if($js.Contains($item.Key)){$js=$js.Replace($item.Key,$item.Value)}
}
# Переводимые поля показываются в основном представлении.
# Оригинальный английский текст сохраняется в раскрываемой технической секции.
$functionStart=$js.IndexOf('function buildTooltipHtml(finding, findingId, actualSeverity) {')
if($functionStart -lt 0){throw 'Не найдена функция buildTooltipHtml'}
$severityMark='            // Map card severity to display label and CSS class'
$insertAt=$js.IndexOf($severityMark,$functionStart)
if($insertAt -lt 0){throw 'Не найдена точка внедрения tooltip'}
$vars=@'
            const ruExtra = ruFindingExplanations[findingId] || {};
            const titleRu = ruFindingTitles[findingId] || finding.title;
            const isSecureRu = actualSeverity === 'secure' ||
                (finding.risk && finding.risk.toLowerCase() === 'secure');
            const descriptionRu = ruExtra.description ||
                ('Краткое русское пояснение: ' + titleRu + '. Для оценки конкретных условий используйте данные карточки и полный технический оригинал EN.');
            const impactRu = ruExtra.impact || (isSecureRu ?
                ['Обнаруженный параметр соответствует ожидаемому безопасному состоянию.'] :
                ['Последствия зависят от полномочий затронутого субъекта и области действия настройки.']);
            const remediationRu = ruExtra.remediation || (isSecureRu ?
                ['Сохраните действующие защитные настройки и проверяйте их после изменений инфраструктуры.'] :
                ['Проверьте необходимость настройки и соответствие принципу минимальных привилегий. Для исправления опирайтесь на документацию Microsoft и действующие политики организации.']);
            const attackRu = ruExtra.attack || [];

'@
$js=$js.Insert($insertAt,$vars)
$descFrom='$' + '{escapeHtml(finding.description)}'
$descTo='$' + '{escapeHtml(descriptionRu)}'
Replace-RU $descFrom $descTo
Replace-RU 'if (finding.impact && finding.impact.length > 0)' 'if (impactRu && impactRu.length > 0)'
Replace-RU 'finding.impact.map(i =>' 'impactRu.map(i =>'
Replace-RU 'if (finding.attack && finding.attack.length > 0)' 'if (attackRu && attackRu.length > 0)'
Replace-RU 'finding.attack.map(a =>' 'attackRu.map(a =>'
Replace-RU 'if (finding.remediation && finding.remediation.length > 0)' 'if (remediationRu && remediationRu.length > 0)'
Replace-RU 'finding.remediation.map(r =>' 'remediationRu.map(r =>'
# Не заменяем техническое содержание рекомендаций на общие утверждения без возможности проверить оригинал.
$original=@'
            html += '<details class="tooltip-section" lang="en">' +
                '<summary>Полное техническое описание (оригинал EN)</summary>' +
                '<p>' + escapeHtml(finding.description) + '</p>' +
                (finding.impact ? '<p>Impact</p><ul>' + finding.impact.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.attack ? '<p>Attack</p><ul>' + finding.attack.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.remediation ? '<p>Remediation</p><ul>' + finding.remediation.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                '</details>';

'@
$mark='            // MITRE ATT&CK'
if(-not $js.Contains($mark)){throw 'Отсутствует маркер MITRE'}
$js=$js.Replace($mark,$original+$mark)
# Точные оригинальные критерии проверки оставляем доступными в закрытой детали.
$originalCheck=@'
            if (check.originalEnglish && check.originalEnglish.whyItMatters) {
                html += '<details class="check-tooltip-section" lang="en">' +
                    '<summary>Подробные критерии проверки (оригинал EN)</summary>' +
                    '<p>' + escapeHtml(check.originalEnglish.whyItMatters) + '</p>' +
                    (check.originalEnglish.whatWeCheck ?
                        '<ul>' + check.originalEnglish.whatWeCheck.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                    '</details>';
            }

'@
$checkMarker='            // Filtering Note (documents privilege filtering behavior)'
if(-not $js.Contains($checkMarker)){throw 'Отсутствует маркер Filtering Note'}
$js=$js.Replace($checkMarker,$originalCheck+$checkMarker)
[IO.File]::WriteAllText($jsPath,$js,(New-Object System.Text.UTF8Encoding($true)))
Write-Host '[RU] PASS: заголовки, аннотации и меры устранения в подсказках переведены'
