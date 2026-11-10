#Requires -Version 5.1
<#
.SYNOPSIS
  Русский текст блока приоритетных действий и его всплывающих подсказок.
.NOTES
  Поиск карточки и риск-баллы по-прежнему используют канонические идентификаторы.
  Английский технический оригинал рекомендаций не удаляется.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$changes=0
function Change-Exact([string]$Before,[string]$After){
 $Before=$Before.Replace("`r`n","`n")
 $After=$After.Replace("`r`n","`n")
 if(-not $script:js.Contains($Before)){throw "Не найден ожидаемый фрагмент JS: $($Before.Substring(0,[Math]::Min(85,$Before.Length)))"}
 $script:js=$script:js.Replace($Before,$After)
 $script:changes++
}
Change-Exact '                            Top Priority Actions' '                            Первоочередные меры по устранению рисков'
Change-Exact '                                No Critical Findings' '                                Критических нарушений не обнаружено'
Change-Exact 'No high-priority security issues were detected. Review the hints and notes for potential improvements.' 'Критические нарушения не выявлены. Проверьте предупреждения и информационные результаты для дальнейшего улучшения защиты.'
Change-Exact 'title="Toggle Top Priority Actions"' 'title="Свернуть или развернуть приоритетные рекомендации"'
Change-Exact 'title="More Info"' 'title="Подробности проверки"'
Change-Exact '<div class="top-action-tooltip-label">Summary</div>' '<div class="top-action-tooltip-label">Краткое описание</div>'
Change-Exact '<div class="top-action-tooltip-label">Why It Matters</div>' '<div class="top-action-tooltip-label">Почему это важно</div>'
Change-Exact '<div class="top-action-tooltip-label">What We Check</div>' '<div class="top-action-tooltip-label">Что проверяется</div>'

$before=@'
                // Impact description from checkDescriptions.whyItMatters
                const impactText = checkInfo?.whyItMatters || '';

                // Remediation from findingDefinitions (best match by findingIds/vulnerabilities/title)
                const findingDef = findBestFindingDefinition(item.meta || { title: item.title });
                const remediationText = findingDef?.remediation?.[0] || '';
'@
$after=@'
                // Prefer precise Russian security recommendations. Original definitions
                // remain intact for risk scoring and original-language reference.
                const findingDef = findBestFindingDefinition(item.meta || { title: item.title });
                const findingIdRu = findingDef
                    ? Object.keys(findingDefinitions).find(id => findingDefinitions[id] === findingDef)
                    : null;
                const explanationRu = findingIdRu ? (ruFindingExplanations[findingIdRu] || null) : null;
                const impactText = explanationRu?.impact?.[0] || checkInfo?.whyItMatters || '';
                const remediationText = explanationRu?.remediation?.[0] ||
                    'Откройте карточку нарушения, проверьте фактические права и область действия настройки; согласуйте изменение с владельцем системы.';
                const originalEnglishFix = explanationRu?.remediation?.length
                    ? '' : (findingDef?.remediation?.[0] || '');
'@
Change-Exact $before $after
$before=@'
                metaHtml += `<span class="top-action-section">${escapeHtml(item.section)}</span>`;
'@
$after=@'
                const ruModuleNames = {
                    domain:'Домен', accounts:'Учётные записи', rights:'Права доступа',
                    gpo:'Групповые политики', delegation:'Делегирование',
                    adcs:'AD CS', computer:'Компьютеры', creds:'Учётные данные',
                    application:'Приложения', shares:'Общие ресурсы',
                    bloodhound:'BloodHound'
                };
                const ruSection = ruModuleNames[String(item.section || '').toLowerCase()] || item.section;
                metaHtml += `<span class="top-action-section">${escapeHtml(ruSection)}</span>`;
'@
Change-Exact $before $after
$before=@'
                if (remediationText) {
                    detailsHtml += `<div class="top-action-fix">&rarr; ${escapeHtml(remediationText)}</div>`;
                }
'@
$after=@'
                if (remediationText) {
                    detailsHtml += `<div class="top-action-fix">&rarr; ${escapeHtml(remediationText)}</div>`;
                }
                if (originalEnglishFix) {
                    detailsHtml += `<details class="top-action-original-en" lang="en" onclick="event.stopPropagation()"><summary>Точная рекомендация разработчика (оригинал EN)</summary><div>${escapeHtml(originalEnglishFix)}</div></details>`;
                }
'@
Change-Exact $before $after
[IO.File]::WriteAllText($path,$js,(New-Object Text.UTF8Encoding($true)))
Write-Host "[RU] Приоритетные действия: $changes безопасных переводов, оригинальные рекомендации сохранены"
