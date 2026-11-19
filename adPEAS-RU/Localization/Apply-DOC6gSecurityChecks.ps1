#Requires -Version 5.1
<#
.SYNOPSIS
    DOC6g: русификация сообщений трёх модулей аудита безопасности AD.
.DESCRIPTION
    158 точных замен строк пользовательского вывода и журналирования.
    Сначала проверяется весь исходный код, затем выполняется запись.
    Не изменяются алгоритмы, ключи находок, Severity, идентификаторы и AD-данные.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$manifestPath=Join-Path $PSScriptRoot 'DOC6g-SecurityChecks.ru-RU.json'
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'DOC6g: реестр отсутствует'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($manifest.schema -ne 'adPEAS-RU.DOC6g.SecurityChecks.1'){throw 'DOC6g: неверная схема'}
$allowed=@(
    'src/modules/Checks/Accounts/Get-PrivilegedGroupMembers.ps1',
    'src/modules/Checks/Domain/Get-DomainInformation.ps1',
    'src/modules/Checks/ADCS/Get-ADCSVulnerabilities.ps1'
)
if(@($manifest.files).Count -ne 3){throw 'DOC6g: ожидались три исходных файла'}
$plans=New-Object 'System.Collections.Generic.List[object]'
$count=0
foreach($entry in @($manifest.files)){
    $relative=[string]$entry.path
    if($relative -cnotin $allowed -or $relative.Contains('..')){
        throw "DOC6g: недопустимый путь $($relative)"
    }
    if(@($plans | Where-Object {$_.Relative -ceq $relative}).Count -ne 0){
        throw "DOC6g: повторный путь $($relative)"
    }
    $filePath=Join-Path $ProjectRoot ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $filePath -PathType Leaf)){
        throw "DOC6g: исходный файл не найден $($relative)"
    }
    $original=[IO.File]::ReadAllText($filePath,[Text.Encoding]::UTF8)
    $groups=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    foreach($line in @($entry.entries)){
        $before=[string]$line.original
        $after=[string]$line.target
        if([string]::IsNullOrWhiteSpace($before) -or [string]::IsNullOrWhiteSpace($after) -or $before -ceq $after -or [int]$line.line -lt 1){
            throw "DOC6g: некорректная запись $($relative):$($line.line)"
        }
        if($groups.ContainsKey($before)){
            if($groups[$before].Target -cne $after){throw "DOC6g: разные переводы повторной строки $($relative):$($line.line)"}
            $groups[$before].Count++
        } else {
            $groups.Add($before,[PSCustomObject]@{Target=$after;Count=1;Line=[int]$line.line})
        }
        $count++
    }
    $updated=$original
    foreach($before in @($groups.Keys)){
        $g=$groups[$before]
        $actual=([regex]::Matches($updated,[regex]::Escape($before))).Count
        if($actual -ne $g.Count){
            throw "DOC6g: изменена строка $($relative):$($g.Line); ожидалось $($g.Count), найдено $actual"
        }
        $updated=$updated.Replace($before,$g.Target)
    }
    $plans.Add([PSCustomObject]@{Relative=$relative;Path=$filePath;Content=$updated})
}
if($count -ne 158 -or $plans.Count -ne 3){
    throw "DOC6g: ожидались 158 строк в 3 файлах; получено $count в $($plans.Count)"
}
foreach($plan in $plans){
    [IO.File]::WriteAllText($plan.Path,$plan.Content,(New-Object Text.UTF8Encoding($true)))
}
Write-Host '[RU] PASS DOC6g: 158 текстовых переводов, 3 файла UTF-8 BOM, логика аудита сохранена'
