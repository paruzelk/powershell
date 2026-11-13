#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4a: перевод подтверждённых английских сообщений работающих проверок.
.DESCRIPTION
    Применяется после предыдущих этапов локализации к зафиксированному
    upstream adPEAS 2.9.0. Только замены точных строк в известных файлах.
    Сохраняет команды, переменные, FindingId и внутренние значения риска.
    До записи проверяет синтаксис и семантическую структуру PowerShell AST.
    Active Directory не подключается и не модифицируется.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'

$root=(Resolve-Path -LiteralPath $ProjectRoot).Path
$catalogPath=Join-Path $root 'Localization/DOC4a-RuntimeMessages.ru-RU.json'
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($catalogPath,[Text.Encoding]::UTF8))
if($catalog.schema -cne 'adPEAS-RU.DOC4a.RuntimeMessages.1' -or $catalog.locale -cne 'ru-RU') {
    throw 'DOC4a: несовместимый каталог локализации'
}
$files=@($catalog.files.PSObject.Properties)
if($files.Count -ne 9){throw "DOC4a: ожидалось 9 файлов, получено $($files.Count)"}
$writer=New-Object Text.UTF8Encoding($true)
$changed=0
$total=0
foreach($entry in $files){
    $relative=[string]$entry.Name
    if($relative -notmatch '^src/modules/(?:Checks/(?:Accounts|ADCS|Creds|Domain)/[A-Za-z0-9-]+|Helpers/Get-GCConnection)\.ps1$') {
        throw "DOC4a: неожиданный путь: $relative"
    }
    $file=Join-Path $root $relative
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "DOC4a: нет файла $relative"}
    $source=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
    $result=$source
    foreach($rule in @($entry.Value.PSObject.Properties)){
        $from=[string]$rule.Name
        $to=[string]$rule.Value
        if([string]::IsNullOrWhiteSpace($from) -or [string]::IsNullOrWhiteSpace($to) -or $from -ceq $to){
            throw "DOC4a: недопустимое правило в $relative"
        }
        if($to -notmatch '[А-Яа-яЁё]'){throw "DOC4a: целевой текст не содержит русского языка в $relative"}
        $found=([regex]::Matches($result,[regex]::Escape($from))).Count
        if($found -ne 1){throw "DOC4a: не найден уникальный исходный фрагмент ($found): $relative / $from"}
        $result=$result.Replace($from,$to)
        $total++
    }
    $tokens=$null;$errors=$null
    $afterAst=[Management.Automation.Language.Parser]::ParseInput($result,[ref]$tokens,[ref]$errors)
    if($errors -and $errors.Count -gt 0){throw "DOC4a: синтаксис $relative : $($errors[0].Message)"}
    $tokens=$null;$errors=$null
    $beforeAst=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    if($errors -and $errors.Count -gt 0){throw "DOC4a: ошибка исходного синтаксиса $relative"}
    $variableType=[Management.Automation.Language.VariableExpressionAst]
    $commandType=[Management.Automation.Language.CommandAst]
    $varsBefore=@($beforeAst.FindAll({param($node) $node -is [Management.Automation.Language.VariableExpressionAst]},$true) |
        ForEach-Object { $_.VariablePath.UserPath })
    $varsAfter=@($afterAst.FindAll({param($node) $node -is [Management.Automation.Language.VariableExpressionAst]},$true) |
        ForEach-Object { $_.VariablePath.UserPath })
    if(($varsBefore -join [char]31) -cne ($varsAfter -join [char]31)){
        throw "DOC4a: изменён перечень переменных (включая интерполяции) в $relative"
    }
    $cmdsBefore=@($beforeAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true) |
        ForEach-Object { $_.GetCommandName() })
    $cmdsAfter=@($afterAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true) |
        ForEach-Object { $_.GetCommandName() })
    if(($cmdsBefore -join [char]31) -cne ($cmdsAfter -join [char]31)){
        throw "DOC4a: изменены команды PowerShell в $relative"
    }
    if($result -cne $source){
        [IO.File]::WriteAllText($file,$result,$writer)
        $changed++
    }
}
if($total -ne 69 -or $changed -ne 9) {
    throw "DOC4a: неверный охват: $total замен в $changed файлах (ожидалось 69/9)"
}
Write-Host "[RU] PASS DOC4a: $total строк переведено в $changed модулях, переменные и команды AST не изменены" -ForegroundColor Green
