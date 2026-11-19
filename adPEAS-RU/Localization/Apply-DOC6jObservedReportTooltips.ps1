#Requires -Version 5.1
<#
.SYNOPSIS
    DOC6j: предметные русские подсказки вместо общих шаблонов.
.DESCRIPTION
    Только HTML-представление; технические каталоги, EN-оригиналы, ID,
    правила аудита, PowerShell-команды и оценки риска сохраняются.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/templates/report-scripts.js'
if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'DOC6j: шаблон отчёта отсутствует'}
$script:source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
if(-not $script:source.Contains('const ruFullFindingTechnical = ') -or
   -not $script:source.Contains('const ruFindingExplanations = ')){
    throw 'DOC6j: проверенные каталоги ещё не внедрены в шаблон'
}
$script:changes=0
function Replace-Once {
    param([string]$Old,[string]$New,[string]$Purpose)
    $n=([regex]::Matches($script:source,[regex]::Escape($Old))).Count
    if($n -ne 1){throw "DOC6j: изменён исходный фрагмент $Purpose; совпадений $n"}
    $script:source=$script:source.Replace($Old,$New)
    $script:changes++
}
$nl=[string][char]10
Replace-Once '            const descriptionRu = ruExtra.description ||' (
    '            const ruFull = ruFullFindingTechnical[findingId] || null;' + $nl +
    '            const descriptionRu = ruExtra.description || (ruFull && ruFull.description) ||'
) 'description'
$oldGeneric = @'
                ('Краткое русское пояснение: ' + titleRu + '. Для оценки конкретных условий используйте данные карточки и полный технический оригинал EN.');
'@
$newGeneric = @'
                ('Для проверки «' + titleRu + '» отсутствует локализованное описание. Смотрите данные карточки и документацию проверяемой настройки.');
'@
Replace-Once $oldGeneric $newGeneric 'generic RU description'
Replace-Once '            const impactRu = ruExtra.impact || (isSecureRu ?' (
    '            const impactRu = (ruExtra.impact && ruExtra.impact.length ? ruExtra.impact : null) ||' + $nl +
    '                (ruFull && ruFull.impact && ruFull.impact.length ? ruFull.impact : null) || (isSecureRu ?'
) 'impact'
Replace-Once '            const remediationRu = ruExtra.remediation || (isSecureRu ?' (
    '            const remediationRu = (ruExtra.remediation && ruExtra.remediation.length ? ruExtra.remediation : null) ||' + $nl +
    '                (ruFull && ruFull.remediation && ruFull.remediation.length ? ruFull.remediation : null) || (isSecureRu ?'
) 'remediation'
Replace-Once '            const attackRu = ruExtra.attack || [];' (
    '            const attackRu = (ruExtra.attack && ruExtra.attack.length ? ruExtra.attack : null) ||' + $nl +
    '                (ruFull && ruFull.attack && ruFull.attack.length ? ruFull.attack : null) || [];'
) 'attack'

$declaration='            const ruFull = ruFullFindingTechnical[findingId] || null;'
if(([regex]::Matches($script:source,[regex]::Escape($declaration))).Count -ne 2){
    throw 'DOC6j: ожидались старое и новое объявления ruFull'
}
$last=$script:source.LastIndexOf($declaration,[StringComparison]::Ordinal)
if($last -lt 0 -or -not $script:source.Substring($last).Contains('            if (ruFull) {')){
    throw 'DOC6j: не найдено позднее объявление каталога'
}
$script:source=$script:source.Remove($last,$declaration.Length)

# English comparison stays available to developers, but is hidden by default.
$englishStart='            html += ''<details class="tooltip-section" lang="en">'' +'
$i=$script:source.IndexOf($englishStart,[StringComparison]::Ordinal)
if($i -lt 0 -or $script:source.IndexOf($englishStart,$i+1,[StringComparison]::Ordinal) -ge 0){
    throw 'DOC6j: начало EN-блока не совпадает с закреплённым исходником'
}
$j=$script:source.IndexOf('            // MITRE ATT&CK',$i,[StringComparison]::Ordinal)
if($j -lt 0){throw 'DOC6j: конец EN-блока не найден'}
$englishBlock=$script:source.Substring($i,$j-$i)
if(-not $englishBlock.Contains('Сверить с исходным текстом на английском (EN)') -or
   -not $englishBlock.Contains('finding.remediation')){
    throw 'DOC6j: неожиданный EN-блок'
}
$script:source=$script:source.Substring(0,$i) +
    '            if (window.adPEASShowOriginalEnglish === true) {' + $nl +
    $englishBlock + '            }' + $nl + $script:source.Substring($j)
Replace-Once '            if (!check.ruDetailedCheckReady && check.originalEnglish && check.originalEnglish.whyItMatters) {' (
    '            if (window.adPEASShowOriginalEnglish === true && !check.ruDetailedCheckReady && check.originalEnglish && check.originalEnglish.whyItMatters) {'
) 'check EN comparison'

if($script:changes -ne 6 -or
   ([regex]::Matches($script:source,[regex]::Escape($declaration))).Count -ne 1){
    throw 'DOC6j: финальная проверка отображения не пройдена'
}
[IO.File]::WriteAllText($path,$script:source,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS DOC6j: полные русские описания вместо шаблонов; EN только по запросу разработчика'
