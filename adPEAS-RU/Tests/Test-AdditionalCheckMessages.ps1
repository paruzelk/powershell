#Requires -Version 5.1
<#
.SYNOPSIS
    Регрессия русификации показанных в отчёте сообщений и охват источников.
.DESCRIPTION
    Offline: AD не подключается. Проверяет каталог без замены кода проверок,
    собирает инвентаризацию прямого, косвенного и шаблонного вывода.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$cat=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $ProjectRoot 'Localization/AdditionalCheckMessages.ru-RU.json'),[Text.Encoding]::UTF8))
$checks=0
foreach($entry in $cat.files.PSObject.Properties){
    $path=Join-Path $ProjectRoot ([string]$entry.Name)
    $code=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    foreach($item in $entry.Value.PSObject.Properties){
        if(-not $code.Contains([string]$item.Value)){throw "Пропущен перевод $($entry.Name): $($item.Value)"}
        if($code.Contains([string]$item.Name)){throw "Остался исходный английский текст $($entry.Name): $($item.Name)"}
        $checks++
    }
}
if($checks -lt 97){throw "Проверено только $checks переводов; ожидается не менее 97"}
$names=@('src/modules/Checks','src/modules/Helpers','src/modules/Core','src/modules/Collector','src/modules/Reporting')
$sources=@()
foreach($relative in $names){
    $sources+=@(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot $relative) -File -Filter '*.ps1' -Recurse)
}
$sources+=@(Get-Item -LiteralPath (Join-Path $ProjectRoot 'src/adPEAS.ps1'))
$inventory=New-Object System.Collections.ArrayList
foreach($file in $sources){
    $lineNo=0
    foreach($line in [IO.File]::ReadAllLines($file.FullName,[Text.Encoding]::UTF8)){
        $lineNo++
        if($line -match '^\s*#' -or $line -match '[А-Яа-яЁё]'){continue}
        $kind=$null
        if($line -match '\bShow-(Line|Header|SubHeader)\s+'){ $kind='DirectShow' }
        elseif($line -match '^\s*\$(?:summaryText|unjudgedText|countText|cleanText|accountCleanText)\s*(?:\+?=)'){ $kind='DynamicSummary' }
        elseif($line -match '^\s*(?:SecureMessage|FilteringNote|SectionTitle|Summary)\s*='){ $kind='DefinitionText' }
        if(-not $kind -or $line -notmatch '[A-Za-z]{5}'){continue}
        $relative=$file.FullName.Substring($ProjectRoot.Length).TrimStart([char]'\',[char]'/')
        [void]$inventory.Add([pscustomobject]@{kind=$kind;source=$relative;line=$lineNo;snippet=$line.Trim()})
    }
}
$templates=@('src/modules/Reporting/templates/report-template.html',
             'src/modules/Reporting/templates/report-scripts.js',
             'src/modules/Reporting/templates/diff-template.html')
foreach($p in $templates){if(-not(Test-Path (Join-Path $ProjectRoot $p))){throw "Нет шаблона отчёта: $p"}}
$js=[IO.File]::ReadAllText((Join-Path $ProjectRoot $templates[1]),[Text.Encoding]::UTF8)
foreach($token in @('ruTranslateVisibleText','window.adPEASRUReportAudit','ruFindingTitles','ruAttributeLabels')){
    if(-not $js.Contains($token)){throw "Отсутствует HTML-обработчик: $token"}
}
$summary=[ordered]@{
    schema='adPEAS-RU.ReportTextCoverage.1'
    locale='ru-RU'
    translatedNewRules=$checks
    sources=($sources.Count)
    htmlTemplates=@($templates)
    candidateCount=$inventory.Count
    candidates=@($inventory)
    scope=@('Checks','Helpers','Core','Collector','Reporting','HTML templates','Localized finding catalogs')
    note='Эвристика: кандидаты могут быть внутренними терминами. Не переводить машинные значения и команды автоматически.'
}
$report=Join-Path $ProjectRoot 'Localization/ExtendedReportTextInventory.json'
[IO.File]::WriteAllText($report,(ConvertTo-Json -InputObject $summary -Depth 7),(New-Object Text.UTF8Encoding($true)))
Write-Host "PASS: $checks сообщений переведены; источников $($sources.Count), остаточных кандидатов $($inventory.Count)"
