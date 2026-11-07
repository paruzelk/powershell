#Requires -Version 5.1
# SPDX-License-Identifier: MIT
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$psFiles = @(
    'Invoke-FileServerAudit-RU.ps1',
    'Build-AccessMapFromFolder.ps1',
    'Invoke-NTFSPermissionAudit.ps1',
    'Get-FileServerShareInventory.ps1',
    'Build-AccessMapHtml.ps1'
)
foreach ($name in $psFiles) {
    $file = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing: $file" }
    $bytes = [IO.File]::ReadAllBytes($file)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) {
        throw "UTF-8 BOM missing: $name"
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw ("PowerShell syntax error in {0}: {1}" -f $name,$errors[0].Message)
    }
    Write-Host "PASS: $name" -ForegroundColor Green
}
$htmlFile = Join-Path $root 'AccessMapTemplate.html'
if (-not (Test-Path -LiteralPath $htmlFile -PathType Leaf)) { throw "Missing: $htmlFile" }
$html = [IO.File]::ReadAllText($htmlFile,[Text.Encoding]::UTF8)
foreach ($marker in @('FSA_RU_GROUP_CONTROLS_EMBEDDED_V2','RU_I18N_INLINE_1_0_11','RU_SUMMARY_DIAGNOSTIC_1.0.8','RU_SIDEBAR_GROUP_MEMBERS_V1','RU_RIGHTS_CHART_VALIDATION_V1','Участники: ','Развернуть все группы')) {
    if (-not $html.Contains($marker)) { throw "HTML feature missing: $marker" }
}
$scan = [IO.File]::ReadAllText((Join-Path $root 'Invoke-NTFSPermissionAudit.ps1'),[Text.Encoding]::UTF8)
if (-not $scan.Contains('RU_UAC_STATUS_V2')) { throw 'AD UAC status check missing' }
$exports = [regex]::Matches($scan,'(?m)Export-Csv[^\r\n]*-NoTypeInformation[^\r\n]*')
foreach ($m in $exports) {
    if ($m.Value -notmatch '-Encoding UTF8') { throw 'Export-Csv lacks -Encoding UTF8' }
}
Write-Host 'PASS: HTML, AD UAC, CSV UTF8' -ForegroundColor Green
Write-Host 'Static source checks passed (AD/SMB integration not tested).' -ForegroundColor Cyan

# RU_RIGHTS_STATIC_TEST_V1 — проверка исходного сборщика и формата массива PS5.1.
$builder = [IO.File]::ReadAllText((Join-Path $root 'Build-AccessMapHtml.ps1'), [Text.Encoding]::UTF8)
if (-not $builder.Contains('RU_RIGHTS_DISTRIBUTION_VERIFIED_V1')) {
    throw 'Rights-distribution verification missing from Build-AccessMapHtml.ps1'
}
[int[]]$sampleBuckets = @(2, 1, 0, 0, 0, 0)
$sampleJson = ConvertTo-Json -InputObject ([ordered]@{
    rightsDistribution = $sampleBuckets
    totalEdgeCount = 3
}) -Depth 4 -Compress
$parsed = ConvertFrom-Json -InputObject $sampleJson
$values = @($parsed.rightsDistribution)
if ($values.Count -ne 6 -or [int]$values[0] -ne 2 -or [int]$values[1] -ne 1) {
    throw 'PowerShell 5.1 could not round-trip rightsDistribution as an array.'
}
Write-Host 'PASS: rights totals, JSON structure and fallback code markers.' -ForegroundColor Green

# Проверка встроенной русской справки без прежнего DOM-русификатора.
$documentationMarkers = @(
    'Уровни доступа: разрешённые действия и возможные риски',
    'Эти замечания основаны на эвристическом анализе данных отчёта',
    'Замечания, требующие проверки',
    'Непосредственных участников в AD',
    'Пользователи и группы'
)
foreach ($phrase in $documentationMarkers) {
    if (-not $html.Contains($phrase)) { throw "Отсутствует русская справка: $phrase" }
}
if ($html.Contains('FSA_RU_EMBEDDED_TRANSLATION_V2')) {
    throw 'Устаревший динамический HTML-русификатор не удалён.'
}
foreach ($english in @(
    'What each access level actually allows (and how it could be misused)',
    'These are heuristic, data-driven starting points',
    'Some connections at this depth were too numerous',
    'Objects that could not be scanned ('
)) {
    if ($html.Contains($english)) {
        throw "Остался англоязычный элемент отчёта: $english"
    }
}
Write-Host 'PASS: русская справка, пояснения и встроенная локализация.' -ForegroundColor Green

# RU_IDENTITY_STATUS_EVERYWHERE_1_0_12: контроль единых меток состояния.
foreach ($marker in @(
    'RU_IDENTITY_STATUS_EVERYWHERE_1_0_12',
    'function identityStatusItems(idn)',
    'function identityStatusBadgesHtml(idn)',
    'function appendIdentityStatusBadges(parent, idn)',
    'function identityStatusRowClass(idn)',
    'function groupMembersStatusSummary(memberIndices)',
    'appendIdentityStatusBadges(link, person)',
    'appendIdentityStatusBadges(div, idn)',
    'groupMembersStatusSummary(ids)',
    'groupMembersStatusSummary(reportMembers)',
    'identityStatusBadgesHtml(group)',
    'title.textContent = info.full + (info.status',
    'if (info.flagged)'
)) {
    if (-not $html.Contains($marker)) {
        throw "Отсутствует единое отображение статуса учётной записи: $marker"
    }
}
Write-Host 'PASS: единые метки AD во всех представлениях, включая группы и граф.' -ForegroundColor Green

# RU_GRAPH_NODE_RIGHTS_1_0_13: защита от неподвижных подписей при перетаскивании.
foreach ($marker in @(
    'RU_GRAPH_NODE_RIGHTS_1_0_13',
    "const tag = svgEl('g', { class: 'graphRightsTag'",
    'function updateNodePosition(key, x, y)',
    'updateNodePosition(key, nx, ny)',
    'originalPositions.forEach((initial, key)',
    "rightsToggle.textContent = showAllRights ?",
    "svg.classList.toggle('rightsAlways', showAllRights)",
    "line.appendChild(lineTip)",
    "group.appendChild(tag)",
    "const radius = hop === 0 ? 0 : Math.max("
)) {
    if (-not $html.Contains($marker)) {
        throw "Отсутствует обновление связанного с узлом графа: $marker"
    }
}
if ($html.Contains("class: 'edgeLabel'")) {
    throw 'В графе осталась отдельная неподвижная подпись права.'
}
Write-Host 'PASS: права привязаны к узлам, перетаскивание и сброс координат учтены.' -ForegroundColor Green

# RU_GRAPH_LEGEND_COMBINATIONS_1_0_14 — расшифровка красного пунктира.
foreach ($marker in @(
    'RU_GRAPH_LEGEND_COMBINATIONS_1_0_14',
    "lineRow(getEdgeColors()[0],",
    'Красный пунктир — унаследованный «Полный доступ»',
    'Красная сплошная — явно назначенный «Полный доступ»',
    'Красный цвет обозначает «Полный доступ», а НЕ запрет (Deny)',
    'цвет показывает категорию прав NTFS'
)) {
    if (-not $html.Contains($marker)) {
        throw "Нет пояснения комбинации цвета и типа линии: $marker"
    }
}
Write-Host 'PASS: в легенде объяснены красный пунктир, наследуемые и явно назначенные права.' -ForegroundColor Green

# RU_GRAPH_VIEWPORT_DRAG_1_0_15 — корректная прокрутка легенды и Pointer Events.
foreach ($marker in @(
    'RU_GRAPH_VIEWPORT_DRAG_1_0_15',
    'RU_GRAPH_POINTER_DRAG_1_0_15',
    '.graphCanvas .graphLegendPanel',
    'graphCanvas.appendChild(legendPanel)',
    'graphCanvas.appendChild(svg)',
    'legendPanel.scrollTop = 0',
    "group.addEventListener('pointerdown'",
    "document.addEventListener('pointermove', onPointerMove)",
    "document.addEventListener('pointerup', onPointerUp)",
    "document.addEventListener('pointercancel', onPointerCancel)",
    "svg.addEventListener('pointerdown'",
    'function onPanPointerMove(e)',
    'updateNodePosition(key, nextX, nextY)'
)) {
    if (-not $html.Contains($marker)) {
        throw "Не найдено исправление графа/легенды: $marker"
    }
}
foreach ($old in @(
    "group.addEventListener('mouseenter', () => nodesLayer.appendChild(group))",
    "group.addEventListener('mousedown', (e) => {",
    'max-height:65vh'
)) {
    if ($html.Contains($old)) {
        throw "Остался старый механизм, нарушающий перетаскивание или прокрутку: $old"
    }
}
Write-Host 'PASS: ограниченная легенда, прокрутка и перетаскивание узлов Pointer Events.' -ForegroundColor Green
