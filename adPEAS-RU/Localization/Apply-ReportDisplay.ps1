#Requires -Version 5.1
<#
.SYNOPSIS
    Русификация человекочитаемых строк HTML-отчёта без изменения данных аудита.
.DESCRIPTION
    Обрабатывает только видимые текстовые узлы карточек и сообщений.
    Не меняет data-атрибуты, FindingId, SID/GUID, имена объектов,
    LDAP-атрибуты, исходные команды или английский оригинал подсказок.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$catPath=Join-Path $ProjectRoot 'Localization/ReportDisplay.ru-RU.json'
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($catPath,[Text.Encoding]::UTF8))
$exact=$catalog.exact
$rules=@($catalog.regex)
if(@($exact.PSObject.Properties).Count -lt 40 -or $rules.Count -lt 25){
 throw 'Неполный каталог перевода отображаемых результатов'
}
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$mark='        // Scoring context data for context-aware risk calculation'
if(-not $source.Contains($mark)){throw 'Не найдена точка добавления перевода в HTML'}
$json=ConvertTo-Json -InputObject $catalog -Depth 10 -Compress
$inject=@'
        // Russian presentation-only text transformation: no mutation of audit data.
        const ruReportDisplay = __RU_DISPLAY_JSON__;
        const ruDisplayPatterns = ruReportDisplay.regex.map(function(entry) {
            return [new RegExp(entry[0], 'u'), entry[1]];
        });
        function ruTranslateVisibleText(original) {
            const leading = (original.match(/^\s*/) || [''])[0];
            const trailing = (original.match(/\s*$/) || [''])[0];
            const text = original.slice(leading.length, original.length - trailing.length);
            if (!text) return original;
            if (Object.prototype.hasOwnProperty.call(ruReportDisplay.exact, text)) {
                return leading + ruReportDisplay.exact[text] + trailing;
            }
            for (const entry of ruDisplayPatterns) {
                if (entry[0].test(text)) {
                    return leading + text.replace(entry[0], entry[1]) + trailing;
                }
            }
            return original;
        }
        document.addEventListener('DOMContentLoaded', function() {
            const nodes = document.querySelectorAll(
                '.finding-line, .object-body .attr-value, .object-header > span:first-child, .finding-key'
            );
            let translated = 0, reviewed = 0, englishCandidates = 0;
            const examples = [];
            nodes.forEach(function(root) {
                if (root.closest('pre,code,textarea,script,style,.tooltip-section,.tooltip-content')) return;
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                const textNodes = [];
                let node;
                while ((node = walker.nextNode())) textNodes.push(node);
                textNodes.forEach(function(textNode) {
                    const parent = textNode.parentElement;
                    if (!parent || parent.closest('pre,code,textarea,script,style,.tooltip-section,.tooltip-content')) return;
                    reviewed++;
                    const oldText = textNode.nodeValue;
                    const newText = ruTranslateVisibleText(oldText);
                    if (newText !== oldText) {
                        textNode.nodeValue = newText;
                        translated++;
                    } else {
                        const candidate = oldText.trim();
                        if (candidate.length > 24 &&
                            /(?:\b(?:Found|could not|not read|permissions|privileged|principal|account|group|default|access|Password|will|without|expected)\b)/i.test(candidate) &&
                            !/[А-Яа-яЁё]/.test(candidate)) {
                            englishCandidates++;
                            if (examples.length < 20) examples.push(candidate.slice(0, 180));
                        }
                    }
                });
            });
            // Local, read-only diagnostic for administrators. No network traffic.
            window.adPEASRUReportAudit = Object.freeze({
                reviewed: reviewed, translated: translated,
                englishCandidates: englishCandidates, examples: examples
            });
        });

'@
$inject=$inject.Replace('__RU_DISPLAY_JSON__',$json)
$source=$source.Replace($mark,$inject+$mark)
$utf8=New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($path,$source,$utf8)
# UI-only attributes; never alter data-attr-name or the sorting model.
$renderPath=Join-Path $ProjectRoot 'src/modules/Core/Render-HtmlObject.ps1'
$render=[IO.File]::ReadAllText($renderPath,[Text.Encoding]::UTF8)
$tick=[string][char]96
$oldTitle='title='+$tick+'"Drag to reorder'+$tick+'"'
$newTitle='title='+$tick+'"Перетащите для изменения порядка'+$tick+'"'
$occurrences=[regex]::Matches($render,[regex]::Escape($oldTitle)).Count
if($occurrences -ne 6){throw "Найдено неожиданное число подсказок перетаскивания: $occurrences"}
$render=$render.Replace($oldTitle,$newTitle)
[IO.File]::WriteAllText($renderPath,$render,$utf8)
$exportPath=Join-Path $ProjectRoot 'src/modules/Reporting/Export-HTMLReport.ps1'
$export=[IO.File]::ReadAllText($exportPath,[Text.Encoding]::UTF8)
$oldLabel='aria-label='+$tick+'"Mark as completed'+$tick+'"'
$newLabel='aria-label='+$tick+'"Отметить как выполненное'+$tick+'"'
if(-not $export.Contains($oldLabel)){throw 'Не найден исходный aria-label чекбокса'}
$export=$export.Replace($oldLabel,$newLabel)
[IO.File]::WriteAllText($exportPath,$export,$utf8)
Write-Host "[RU] PASS: $(@($exact.PSObject.Properties).Count) точных строк и $($rules.Count) шаблонов перевода HTML"
Write-Host '[RU] PASS: технические данные не затронуты; доступен window.adPEASRUReportAudit'
