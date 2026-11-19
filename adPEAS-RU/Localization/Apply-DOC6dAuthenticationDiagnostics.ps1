#Requires -Version 5.1
<#
.SYNOPSIS
    DOC6d: адресная локализация консольных сообщений запуска/аутентификации/LDAP.
.DESCRIPTION
    Только строковые литералы в 3 проверенных исходных PowerShell-файлах.
    Сохраняет параметры, кодовые обозначения, переменные и обработку ошибок.
    Повторный запуск без восстановления закреплённого оригинала запрещён.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$manifestPath=Join-Path $PSScriptRoot 'DOC6d-AuthenticationDiagnostics.ru-RU.json'
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'DOC6d: отсутствует реестр переводов'}
$manifest=Get-Content -LiteralPath $manifestPath -Encoding UTF8 -Raw | ConvertFrom-Json
if($manifest.schema -ne 'adPEAS-RU.DOC6d.AuthenticationDiagnostics.1'){throw 'DOC6d: неподдерживаемая схема'}
if(@($manifest.files).Count -ne 3){throw 'DOC6d: ожидались три исходных файла'}
$totals=0
foreach($entry in $manifest.files){
    $relative=[string]$entry.path
    if($relative -notmatch '^src/(adPEAS\.ps1|modules/Core/Connect-(adPEAS|LDAP)\.ps1)$'){
        throw "DOC6d: путь не разрешён: $relative"
    }
    $path=Join-Path $ProjectRoot ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "DOC6d: файл отсутствует: $relative"}
    $source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    foreach($item in $entry.messages){
        $from=[string]$item.from
        $to=[string]$item.to
        $expect=[int]$item.expectedOccurrences
        if([string]::IsNullOrEmpty($from) -or [string]::IsNullOrEmpty($to) -or $from -ceq $to -or $expect -lt 1){
            throw "DOC6d: некорректный элемент перевода $relative:$($item.sourceLine)"
        }
        $quotedFrom='"'+$from+'"'
        $count=([regex]::Matches($source,[regex]::Escape($quotedFrom))).Count
        if($count -ne $expect){
            throw "DOC6d: исходный текст изменился ($relative:$($item.sourceLine)); ожидалось $expect, найдено $count"
        }
        $source=$source.Replace($quotedFrom,'"'+$to+'"')
        $totals++
    }
    [IO.File]::WriteAllText($path,$source,(New-Object Text.UTF8Encoding($true)))
}
if($totals -ne 182){throw "DOC6d: переведено $totals строк, ожидалось 182"}
Write-Host '[RU] PASS DOC6d: 182 безопасно локализованные диагностические строки; исходный код и технические ключи неизменны'
