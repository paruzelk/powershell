#Requires -Version 5.1
<#
.SYNOPSIS
    Этап C: русификация пользовательских сообщений Checks.
.DESCRIPTION
    Правила привязаны к фиксированной версии исходников adPEAS 2.9.0.
    Заменяются только литералы Show-Line/Show-Header/Show-SubHeader.
    Исполняемые команды, переменные, классы, FindingId и логика не меняются.
    Для каждого правила сравниваются PowerShell-токены и AST-подстановки.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
$catalogNames=@(
 'StageC-SessionAndCoreUX.ru-RU.json',
 'StageC-ComputerOperations.ru-RU.json',
 'StageC-UserOperations.ru-RU.json',
 'StageC-GPOGroupOperations.ru-RU.json'
)
$expectedRules=@(55,47,47,40)
$translations=@{}
$sourceFiles=@{}
$ruleCount=0
$occurrenceCount=0
$utf8=New-Object Text.UTF8Encoding($true)

function Get-DisplayCodeShape([string]$Code) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Code,[ref]$tokens,[ref]$errors)
    if(@($errors).Count -gt 0){throw "Некорректная строка PowerShell: $($errors[0].Message)"}
    $nonString=@($tokens | Where-Object {
        $_.Kind.ToString() -notin @('StringExpandable','StringLiteral','EndOfInput')
    } | ForEach-Object { "$($_.Kind):$($_.Text)" })
    $expandable=@($ast.FindAll({
        param($a) $a -is [Management.Automation.Language.ExpandableStringExpressionAst]
    },$true))
    $expanded=@()
    foreach($item in $expandable){
        $expanded+=@($item.NestedExpressions | ForEach-Object { $_.Extent.Text })
    }
    return (($nonString -join ([char]30))+'#'+($expanded -join ([char]31)))
}

for($catalogIndex=0; $catalogIndex -lt $catalogNames.Count; $catalogIndex++){
    $name=$catalogNames[$catalogIndex]
    $path=Join-Path $ProjectRoot ('Localization/'+$name)
    $catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8))
    $seenThis=0
    foreach($fileEntry in $catalog.files.PSObject.Properties){
        $relative=[string]$fileEntry.Name
        if($relative -cnotmatch '^src/modules/Core/[A-Za-z0-9_-]+\.ps1$'){
            throw "Недопустимый файл для этапа A: $relative"
        }
        if(-not $translations.ContainsKey($relative)){$translations[$relative]=@{}}
        foreach($rule in $fileEntry.Value.PSObject.Properties){
            $old=[string]$rule.Name; $new=[string]$rule.Value
            if($translations[$relative].ContainsKey($old)){throw "Повторяющееся правило: $relative / $old"}
            if($old -cnotmatch '^Show-(Line|Header|SubHeader)\s+"' -or
               $new -cnotmatch '^Show-(Line|Header|SubHeader)\s+"' ){
                throw "Разрешены только отдельные строки отображения: $relative"
            }
            if($old -ceq $new){throw "Тождественный перевод: $relative"}
            if((Get-DisplayCodeShape $old) -cne (Get-DisplayCodeShape $new)){
                throw "Изменены подстановки или PowerShell-токены: $relative / $old"
            }
            $translations[$relative][$old]=$new
            $ruleCount++
            $seenThis++
        }
    }
    if($seenThis -ne $expectedRules[$catalogIndex]){
        throw "Каталог ${name}: ожидалось $($expectedRules[$catalogIndex]) правил, найдено $seenThis"
    }
}
if($ruleCount -ne 189 -or $translations.Count -ne 14){
    throw "Нарушен состав этапа A: $ruleCount правил в $($translations.Count) файлах"
}
foreach($relative in ($translations.Keys | Sort-Object)){
    $source=Join-Path $ProjectRoot $relative
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Нет исходного файла: $relative"}
    $before=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
    $after=$before
    foreach($pair in $translations[$relative].GetEnumerator()){
        $found=[regex]::Matches($after,[regex]::Escape($pair.Key)).Count
        if($found -lt 1 -or $found -gt 2){
            throw "Ожидалось 1–2 точных совпадения в $relative, найдено ${found}: $($pair.Key)"
        }
        $after=$after.Replace($pair.Key,$pair.Value)
        $occurrenceCount+=$found
    }
    $t=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($after,[ref]$t,[ref]$errors)
    if(@($errors).Count -gt 0){throw "Ошибка PowerShell после перевода $relative : $($errors[0].Message)"}
    if($after -ceq $before){throw "Не выполнено ни одного перевода для $relative"}
    [IO.File]::WriteAllText($source,$after,$utf8)
    $sourceFiles[$relative]=$translations[$relative].Count
}
$report=[ordered]@{
 Schema='adPEAS-RU.StageC.VisibleMessages.1'
 PlannedRules=$ruleCount
 AppliedOccurrences=$occurrenceCount
 ModifiedSourceFiles=$sourceFiles.Count
 InterpolationsAndNonStringTokensPreserved=$true
 PowerShellParserPassed=$true
 ModifiedScopes=@('Core')
 ExplicitlyExcluded=@('FindingId','risk classes','commands and examples','LDAP/ACL/API identifiers','metadata definitions','dynamic/composite expressions')
 Files=$sourceFiles
 ADContacted=$false
}
$reportPath=Join-Path $ProjectRoot 'Localization/StageCValidation.json'
[IO.File]::WriteAllText($reportPath,(ConvertTo-Json -InputObject $report -Depth 6),$utf8)
Write-Host "[RU] PASS: этап C — $ruleCount правил в $($sourceFiles.Count) файлах, $occurrenceCount замен; токены и переменные сохранены" -ForegroundColor Green
