#Requires -Version 5.1
<#
.SYNOPSIS
    Точечная локализация оставшихся видимых сообщений аудита.
.DESCRIPTION
    Заменяются только проверенные исходные фрагменты в известных модулях.
    Изменения применяются после прежних каталогов, при каждой сборке от
    фиксированного upstream SHA. Не меняются FindingId, LDAP, ACL, данные и команды.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$catalogFile=Join-Path $ProjectRoot 'Localization/AdditionalCheckMessages.ru-RU.json'
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($catalogFile,[Text.Encoding]::UTF8))
$utf8=New-Object Text.UTF8Encoding($true)
$changedFiles=0
$replacements=0
foreach($entry in $catalog.files.PSObject.Properties){
    $relative=[string]$entry.Name
    if($relative -notmatch '^src/modules/(?:Checks/[A-Za-z0-9_/-]+|Helpers/Format-OUContainerCount)\.ps1$'){
        throw "Неожиданный исходный файл: $relative"
    }
    $path=Join-Path $ProjectRoot $relative
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Отсутствует модуль: $relative"
    }
    $beforeText=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    $afterText=$beforeText
    foreach($translation in $entry.Value.PSObject.Properties){
        $from=[string]$translation.Name
        $to=[string]$translation.Value
        if([string]::IsNullOrWhiteSpace($from) -or [string]::IsNullOrWhiteSpace($to) -or $from -eq $to){
            throw "Пустое или тождественное правило: $relative"
        }
        if(-not $afterText.Contains($from)){
            throw "Исходный фрагмент отсутствует (обновлён upstream или нарушен порядок локализации): $relative / $from"
        }
        $afterText=$afterText.Replace($from,$to)
        $replacements++
    }
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($afterText,[ref]$tokens,[ref]$errors)
    if($errors -and $errors.Count -gt 0){
        throw "Ошибка синтаксиса после перевода $relative : $($errors[0].Message)"
    }
    if($afterText -ne $beforeText){
        [IO.File]::WriteAllText($path,$afterText,$utf8)
        $changedFiles++
    }
}
if($replacements -lt 40 -or $changedFiles -lt 17){
    throw "Недостаточно проверенных замен: $replacements правил в $changedFiles модулях"
}
Write-Host "[RU] PASS: $replacements точечных переводов в $changedFiles модулях проверок и вспомогательных функций"
