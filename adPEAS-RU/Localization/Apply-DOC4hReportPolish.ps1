#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4h: точечный перевод видимых элементов HTML и исправление расхождения aria-label.
.DESCRIPTION
    Не изменяет данные AD, оценки риска, JSON, классы проверок,
    исходные значения атрибутов, команды исправления и логику обнаружения.
    Точность замен проверяется до записи любого файла.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
$jsPath = Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$htmlPath = Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-template.html'
$js = [IO.File]::ReadAllText($jsPath, [Text.Encoding]::UTF8)
$html = [IO.File]::ReadAllText($htmlPath, [Text.Encoding]::UTF8)
$anchor = '        // Scoring context data for context-aware risk calculation'
$riskOriginal = "badge.title = 'Risk Score (click for details)';"
$summaryOriginal = '                    el.textContent = severityCounts[severity];'
$htmlAnchor = '            <div class="info-bar">'
foreach($gate in @(
    @{Name='JS insertion anchor'; Value=$anchor; Text=$js},
    @{Name='Risk badge title'; Value=$riskOriginal; Text=$js},
    @{Name='Summary count assignment'; Value=$summaryOriginal; Text=$js},
    @{Name='HTML info bar'; Value=$htmlAnchor; Text=$html}
)) {
    $n = ([regex]::Matches($gate.Text,[regex]::Escape($gate.Value))).Count
    if($n -ne 1) { throw "DOC4h: $($gate.Name): ожидалось 1 совпадение, найдено $n" }
}
if($js.Contains('ruDOC4hObservedReportUI') -or $html.Contains('doc4hSummaryCountNote')) {
    throw 'DOC4h: повторное применение запрещено'
}
$block = @'
        // DOC4h: observed synthetic labels and DC clock note only; no AD values changed.
        document.addEventListener('DOMContentLoaded', function ruDOC4hObservedReportUI() {
            const labels=Object.freeze({
                activityStatus:'Состояние активности',
                adSubnet:'Подсеть AD',
                computerCount:'Количество компьютеров',
                operatingSystems:'Операционные системы',
                organizationalUnits:'Организационные подразделения',
                domainControllerCount:'Количество контроллеров домена',
                domainControllerTime:'Время контроллера домена'
            });
            let translatedLabels=0, translatedClockValues=0;
            const byField=Object.create(null);
            document.querySelectorAll('.attr-row[data-attr-name]').forEach(function(row) {
                const key=row.getAttribute('data-attr-name');
                if(!Object.prototype.hasOwnProperty.call(labels,key)) return;
                const label=row.querySelector('.attr-name');
                if(label && label.textContent.trim()===key && label.childNodes.length===1 &&
                   label.firstChild && label.firstChild.nodeType===Node.TEXT_NODE) {
                    label.firstChild.nodeValue=labels[key];
                    translatedLabels++;
                    byField[key]=(byField[key]||0)+1;
                }
                if(key==='domainControllerTime') {
                    const value=row.querySelector('.attr-value');
                    if(value && value.childNodes.length===1 && value.firstChild &&
                       value.firstChild.nodeType===Node.TEXT_NODE) {
                        const raw=value.firstChild.nodeValue;
                        const localized=raw.replace(/\(skew:\s*([+-]?\d+)s\)/g,
                            '(расхождение: $1 с)');
                        if(localized!==raw) {
                            value.firstChild.nodeValue=localized;
                            translatedClockValues++;
                        }
                    }
                }
            });
            window.adPEASRUDOC4h=Object.freeze({
                dictionaryEntries:Object.keys(labels).length,
                translatedLabels:translatedLabels,
                translatedClockValues:translatedClockValues,
                byField:Object.freeze(byField)
            });
        });

'@
$js = $js.Replace($anchor, $block + $anchor)
$js = $js.Replace($riskOriginal, "badge.title = 'Оценка риска (нажмите для подробностей)';")
$summaryLocalized = @'
                    el.textContent = severityCounts[severity];
                    // Accessible label must reflect the live card count, not raw
                    // result numbers from the unprocessed report template.
                    const summaryCard = el.closest('.summary-card');
                    if(summaryCard) {
                        const nameNode=summaryCard.querySelector('.label');
                        if(nameNode) summaryCard.setAttribute('aria-label',
                            'Фильтр: ' + nameNode.textContent.trim() + '; карточек проверок: ' +
                            severityCounts[severity]);
                    }
                    const summaryCountNote=document.getElementById('doc4hSummaryCountNote');
                    if(summaryCountNote) summaryCountNote.hidden=false;
'@
$js = $js.Replace($summaryOriginal, $summaryLocalized.TrimEnd())
$note = @'
            <p id="doc4hSummaryCountNote" hidden style="margin:-14px 0 16px;color:var(--text-muted);font-size:12px;line-height:1.5">
                Сводка показывает количество карточек проверок, не отдельных объектов или строк результатов. Отмеченные как выполненные карточки исключаются из этих чисел.
            </p>
'@
$html = $html.Replace($htmlAnchor, $note + [Environment]::NewLine + $htmlAnchor)
$utf8 = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($jsPath, $js, $utf8)
[IO.File]::WriteAllText($htmlPath, $html, $utf8)
Write-Host '[RU] PASS DOC4h: 7 синтетических подписей, время DC, риск и доступная сводка; AD/JSON не изменены'
