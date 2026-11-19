#Requires -Version 5.1
<#
.SYNOPSIS
    DOC6f: локализация вывода сеанса, ошибок и подсказок команд.
.DESCRIPTION
    113 проверенных строк в двух PowerShell-файлах. Меняются только
    текстовые фрагменты строковых литералов, без изменения кода, параметров,
    состояний, данных LDAP и структуры находок. Полная предварительная
    проверка всех исходных строк до записи первого файла.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'DOC6f-VisibleOutputsAndHelp.ru-RU.json'
if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'DOC6f: отсутствует реестр переводов'}
$manifest=Get-Content -LiteralPath $path -Encoding UTF8 -Raw | ConvertFrom-Json
if($manifest.schema -ne 'adPEAS-RU.DOC6f.VisibleOutputsAndHelp.1'){throw 'DOC6f: неверная схема'}
$allowed=@(
    'src/modules/Helpers/Get-adPEASSession.ps1',
    'src/modules/Core/adPEAS-Messages.ps1'
)
if(@($manifest.files).Count -ne 2){throw 'DOC6f: ожидались 2 исходных файла'}
$plans=New-Object 'System.Collections.Generic.List[object]'
$total=0
foreach($file in @($manifest.files)){
    $relative=[string]$file.path
    if($relative -cnotin $allowed -or $relative.Contains('..')){
        throw "DOC6f: недопустимый путь $($relative)"
    }
    if(@($plans | Where-Object {$_.Relative -ceq $relative}).Count -ne 0){
        throw "DOC6f: повторный файл $($relative)"
    }
    $fullPath=Join-Path $ProjectRoot ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $fullPath -PathType Leaf)){throw "DOC6f: файл не найден $($relative)"}
    $source=[IO.File]::ReadAllText($fullPath,[Text.Encoding]::UTF8)
    $updated=$source
    $groups=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    foreach($entry in @($file.entries)){
        $old=[string]$entry.original
        $new=[string]$entry.target
        if([string]::IsNullOrWhiteSpace($old) -or [string]::IsNullOrWhiteSpace($new) -or
           $old -ceq $new -or [int]$entry.line -lt 1){
            throw "DOC6f: некорректный перевод $($relative):$($entry.line)"
        }
        if($groups.ContainsKey($old)){
            $item=$groups[$old]
            if($item.Target -cne $new){throw "DOC6f: противоречивый перевод дублированной строки $($relative):$($entry.line)"}
            $item.Count++
        } else {
            $groups.Add($old,[PSCustomObject]@{Target=$new;Count=1;FirstLine=[int]$entry.line})
        }
        $total++
    }
    foreach($old in @($groups.Keys)){
        $item=$groups[$old]
        $matches=([regex]::Matches($updated,[regex]::Escape($old))).Count
        if($matches -ne $item.Count){
            throw "DOC6f: исходная строка изменилась $($relative):$($item.FirstLine); ожидалось $($item.Count), найдено $matches"
        }
        $updated=$updated.Replace($old,$item.Target)
    }
    $plans.Add([PSCustomObject]@{Relative=$relative;Path=$fullPath;Updated=$updated})
}
if($total -ne 113 -or $plans.Count -ne 2){
    throw "DOC6f: ожидались 113 строк и 2 файла, найдено $total и $($plans.Count)"
}
foreach($plan in $plans){
    [IO.File]::WriteAllText($plan.Path,$plan.Updated,(New-Object Text.UTF8Encoding($true)))
}
Write-Host '[RU] PASS DOC6f: 113 строк сеанса, ошибок и справки переведены, PowerShell UTF-8 BOM'
