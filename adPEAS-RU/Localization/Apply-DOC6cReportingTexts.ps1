#Requires -Version 5.1
<#
.SYNOPSIS
    DOC6c: перевод пользовательских строк сравнения, конвертации и экспорта.
.DESCRIPTION
    Строгий белый список 54 замен в 4 файлах. Машинные ключи, параметры,
    GUID, SID, DN, числовая логика, структура JSON не изменяются.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$manifest=Join-Path $PSScriptRoot 'DOC6c-ReportingPhrases.ru-RU.json'
if(-not(Test-Path -LiteralPath $manifest)){throw 'DOC6c: реестр переводов не найден'}
$map=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if($map.schema -ne 'adPEAS-RU.DOC6c.ReportingDisplayTranslation.1'){throw 'DOC6c: неизвестная схема'}
$modified=0;$replacements=0
foreach($entry in $map.files){
    $relative=[string]$entry.path
    if($relative -notmatch '^src/modules/Reporting/[\w/.+-]+$' -or $relative.Contains('..')){
        throw "DOC6c: недопустимый путь $relative"
    }
    $target=Join-Path $ProjectRoot ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $target -PathType Leaf)){throw "DOC6c: отсутствует $relative"}
    $original=[IO.File]::ReadAllText($target,[Text.Encoding]::UTF8)
    $text=$original
    foreach($p in $entry.replacements){
        $old=[string]$p.from;$new=[string]$p.to
        if([string]::IsNullOrEmpty($old) -or $old -eq $new){throw "DOC6c: пустая/тождественная замена в $relative"}
        if(-not $text.Contains($old)){throw "DOC6c: исходная фраза отсутствует в $relative : $old"}
        $text=$text.Replace($old,$new)
        $replacements++
    }
    if($text -ceq $original){throw "DOC6c: не изменился $relative"}
    $utf8=New-Object Text.UTF8Encoding($relative.EndsWith('.ps1'))
    [IO.File]::WriteAllText($target,$text,$utf8)
    $modified++
}
if($modified -ne 4 -or $replacements -ne 54){throw "DOC6c: неожиданное число файлов/фраз: $modified / $replacements"}
Write-Host "[RU] PASS DOC6c: 54 текстовые замены в 4 файлах; технические данные сохранены"
