#Requires -Version 5.1
<#
.SYNOPSIS
    Подробные русские технические описания находок AD.
.DESCRIPTION
    Переводит отображение Description, Impact, Attack и Remediation.
    Канонические определения FindingId, риск, триггеры, команды и ссылки
    остаются неизменными. Английский текст доступен отдельно для сверки.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$entries=[ordered]@{}
foreach($name in @('FullTechnical-01.ru-RU.json','FullTechnical-02.ru-RU.json')){
 $src=Join-Path $ProjectRoot ('Localization/'+$name)
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($src,[Text.Encoding]::UTF8))
 foreach($prop in $catalog.translations.PSObject.Properties){
  if($entries.Contains($prop.Name)){throw "Дублируется FindingId $($prop.Name)"}
  $entries[$prop.Name]=$prop.Value
 }
}
$entryCount=$entries.Count
if($entryCount -ne 26){throw "Ожидалось 26 полных переводов, найдено $entryCount"}
$required=@('LDAP_CHANNEL_BINDING_NOT_REQUIRED','LDAP_SIGNING_NOT_REQUIRED','UNCONSTRAINED_DELEGATION','DANGEROUS_ACL_GENERICALL')
foreach($id in $required){
 if(-not $entries.Contains($id)){throw "Нет полного перевода $id"}
 $item=$entries[$id]
 if([string]::IsNullOrWhiteSpace([string]$item.description)){throw "Не заполнено описание для $id"}
 foreach($field in @('impact','attack','remediation')){
  if($null -eq $item.$field){throw "Отсутствует раздел $field для $id"}
 }
}
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
$js=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8).Replace("`r`n","`n")
$startMarker='        const ruFindingExplanations = '
$start=$js.IndexOf($startMarker,[StringComparison]::Ordinal)
if($start -lt 0){throw 'Не найден русский справочник находок'}
$lineEnd=$js.IndexOf([char]10,$start)
if($lineEnd -lt 0){throw 'Не найдена граница строки словаря находок'}
$line=$js.Substring($start,$lineEnd-$start).TrimEnd([char]13)
if(-not $line.EndsWith(';')){throw 'Строка словаря находок не заканчивается точкой с запятой'}
$end=$start+$line.Length-1
$fullJson=ConvertTo-Json -InputObject $entries -Depth 18 -Compress
$js=$js.Insert($end+1,[Environment]::NewLine+'        const ruFullFindingTechnical = '+$fullJson+';')
$old=@'
            html += '<details class="tooltip-section" lang="en">' +
                '<summary>Полное техническое описание (оригинал EN)</summary>' +
                '<p>' + escapeHtml(finding.description) + '</p>' +
                (finding.impact ? '<p>Impact</p><ul>' + finding.impact.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.attack ? '<p>Attack</p><ul>' + finding.attack.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.remediation ? '<p>Remediation</p><ul>' + finding.remediation.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                '</details>';
'@
$replacement=@'
            // Accurate human-reviewed Russian translation is presented only when
            // all four technical sections have been translated for this FindingId.
            // Original EN remains separately available for verification.
            const ruFull = ruFullFindingTechnical[findingId] || null;
            if (ruFull) {
                const addRuList = (label, values) =>
                    values && values.length > 0
                        ? '<strong>' + label + '</strong><ul>' +
                          values.map(value => '<li>' + escapeHtml(value) + '</li>').join('') +
                          '</ul>'
                        : '';
                html += '<details class="tooltip-section" lang="ru">' +
                    '<summary>Подробное техническое описание</summary>' +
                    '<p>' + escapeHtml(ruFull.description) + '</p>' +
                    addRuList('Последствия', ruFull.impact) +
                    addRuList('Сценарий атаки', ruFull.attack) +
                    addRuList('Рекомендации по устранению', ruFull.remediation) +
                    '</details>';
            }
            html += '<details class="tooltip-section" lang="en">' +
                '<summary>' + (ruFull
                    ? 'Показать исходное описание на английском (EN)'
                    : 'Исходное подробное описание EN (перевод пока не завершён)') + '</summary>' +
                '<p>' + escapeHtml(finding.description) + '</p>' +
                (finding.impact ? '<p>Impact</p><ul>' + finding.impact.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.attack ? '<p>Attack</p><ul>' + finding.attack.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                (finding.remediation ? '<p>Remediation</p><ul>' + finding.remediation.map(i => '<li>' + escapeHtml(i) + '</li>').join('') + '</ul>' : '') +
                '</details>';
'@
$old=$old.Replace("`r`n","`n")
$replacement=$replacement.Replace("`r`n","`n")
if(-not $js.Contains($old)){throw 'Не найден точный HTML-блок исходного технического описания'}
if([regex]::Matches($js,[regex]::Escape($old)).Count -ne 1){throw 'Несколько неоднозначных HTML-блоков'}
$js=$js.Replace($old,$replacement)
$enc=New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($path,$js,$enc)
Write-Host "[RU] PASS: полные русские технические описания $entryCount находок"
Write-Host '[RU] PASS: исходные описания EN доступны отдельно; FindingId и команды не изменены'
