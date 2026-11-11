#Requires -Version 5.1
<#
.SYNOPSIS
    Подробные русские технические описания находок AD.
.DESCRIPTION
    Добавляет русские Description, Impact и Remediation для всех FindingId.
    Attack выводится только при наличии проверенного русского пояснения.
    Канонические определения FindingId, риск, триггеры, команды и ссылки
    остаются неизменными. Английский текст доступен отдельно для сверки.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$entries=[ordered]@{}
foreach($name in @('FullTechnical-01.ru-RU.json','FullTechnical-02.ru-RU.json','FullTechnical-Report-03.ru-RU.json','FullTechnical-Report-04.ru-RU.json','FullTechnical-Brief-05.ru-RU.json','FullTechnical-Catalog-06a.ru-RU.json','FullTechnical-Catalog-06b.ru-RU.json','FullTechnical-Catalog-06c.ru-RU.json','FullTechnical-Catalog-06d.ru-RU.json','FullTechnical-Catalog-06e.ru-RU.json')){
 $src=Join-Path $ProjectRoot ('Localization/'+$name)
 $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($src,[Text.Encoding]::UTF8))
 foreach($prop in $catalog.translations.PSObject.Properties){
  if($entries.Contains($prop.Name)){throw "Дублируется FindingId $($prop.Name)"}
  $entries[$prop.Name]=$prop.Value
 }
}
# Source-checked field overlays. No English originals, FindingId, risk or commands are changed.
$coreSource=Join-Path $ProjectRoot 'Localization/SourceVerifiedCore-07.ru-RU.json'
$coreOverlay=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($coreSource,[Text.Encoding]::UTF8))
if(@($coreOverlay.translations.PSObject.Properties).Count -ne 10){throw 'Ожидалось 10 предметных переводов Impact/Remediation'}
foreach($p in $coreOverlay.translations.PSObject.Properties){
 if(-not $entries.Contains($p.Name)){throw "Неизвестный FindingId: $($p.Name)"}
 $v=$p.Value
 if(@($v.impact).Count -ne [int]$v.sourceEnglishImpactCount){throw "Несовпадение количества Impact: $($p.Name)"}
 if(@($v.remediation).Count -ne [int]$v.sourceEnglishRemediationCount){throw "Несовпадение количества Remediation: $($p.Name)"}
 if($v.PSObject.Properties['description']){
  if([string]::IsNullOrWhiteSpace([string]$v.description)){throw "Пустое описание: $($p.Name)"}
  $entries[$p.Name].description=[string]$v.description
 }
 $entries[$p.Name].impact=@($v.impact)
 $entries[$p.Name].remediation=@($v.remediation)
}
$attackSource=Join-Path $ProjectRoot 'Localization/SourceVerifiedAttack-07.ru-RU.json'
$attackOverlay=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($attackSource,[Text.Encoding]::UTF8))
if(@($attackOverlay.translations.PSObject.Properties).Count -ne 38){throw 'Ожидалось 38 сверенных случаев Attack (36 переводов, 2 пустых оригинала)'}
$attackSteps=0
foreach($p in $attackOverlay.translations.PSObject.Properties){
 if(-not $entries.Contains($p.Name)){throw "Неизвестный FindingId: $($p.Name)"}
 $v=$p.Value
 $steps=@($v.attack)
 if($steps.Count -ne [int]$v.sourceEnglishAttackStepCount){throw "Несовпадение количества шагов оригинала Attack: $($p.Name)"}
 for($i=0;$i -lt $steps.Count;$i++){
  if([string]$steps[$i] -notmatch "^\s*$($i+1)\.\s+[А-Яа-яЁё]"){
   throw "Не переведён или неверно пронумерован шаг Attack $($i+1): $($p.Name)"
  }
 }
 $entries[$p.Name].attack=$steps
 $attackSteps+=$steps.Count
}
if($attackSteps -ne 139){throw "Ожидалось 139 переведённых шагов Attack, найдено $attackSteps"}
Write-Host "[RU] PASS: 36 цепочек Attack (139 шагов) и 10 полных полей Impact/Remediation сверены с источником; 2 недопустимых сценария очищены"

$entryCount=$entries.Count
if($entryCount -ne 392){throw "Ожидалось 392 русских технических описания, найдено $entryCount"}
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
            // Curated Russian description, impact and remediation for every FindingId.
            // Attack is shown only when an individual RU explanation exists.
            // English originals remain available separately for comparison.
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
                '<summary>Сверить с исходным текстом на английском (EN)</summary>' +
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
# Старые уведомления об отсутствии перевода не должны попадать в интерфейс.
if($js.Contains('Исходное подробное описание EN (перевод пока не завершён)')) { throw 'Найдена устаревшая пометка EN' }
$enc=New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($path,$js,$enc)
$withAttack=@($entries.Values | Where-Object { @($_.attack).Count -gt 0 }).Count
Write-Host "[RU] PASS: $entryCount типов находок имеют русское описание, последствия и рекомендации; сценарии: $withAttack"
Write-Host '[RU] PASS: исходные описания EN доступны отдельно; FindingId и команды не изменены'
