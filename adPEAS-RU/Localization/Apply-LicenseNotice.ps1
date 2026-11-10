#Requires -Version 5.1
<#
.SYNOPSIS
    Перевод юридического предупреждения в HTML без изменения лицензии adPEAS.
.DESCRIPTION
    Встроенный источник $Script:adPEASDisclaimer, исходный текст, лицензия и
    механизм проверки коммерческой лицензии остаются без изменений.
    Подстановка выполняется только при точном совпадении исходной фразы.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'src/modules/Reporting/Export-HTMLReport.ps1'
$source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$before=@'
        $html = $html.Replace('{{DISCLAIMER}}', [string](ConvertTo-HtmlEncode $disclaimer))
'@
$after=@'
        # Localize only the HTML display of the original license notice.
        # Keep $Script:adPEASDisclaimer and the complete original license intact.
        $disclaimerForDisplay = [string]$disclaimer
        $originalCommercialNotice = 'This report was generated using a tool that requires a valid commercial license for consulting or managed service use.'
        $russianCommercialNotice = 'Этот отчёт сформирован инструментом, для использования которого в консалтинге или при оказании управляемых услуг требуется действующая коммерческая лицензия.'
        if ($disclaimerForDisplay.Contains($originalCommercialNotice)) {
            $disclaimerForDisplay = $disclaimerForDisplay.Replace($originalCommercialNotice, $russianCommercialNotice)
        }
        $html = $html.Replace('{{DISCLAIMER}}', [string](ConvertTo-HtmlEncode $disclaimerForDisplay))
'@
if($source.Contains($after)){
    Write-Host '[RU] PASS: перевод лицензионного предупреждения уже включён'
    return
}
$from=$before.TrimEnd([char]13,[char]10)
$to=$after.TrimEnd([char]13,[char]10)
if(-not $source.Contains($from)){throw 'Не найдена точка подстановки лицензии в Export-HTMLReport.ps1'}
if([regex]::Matches($source,[regex]::Escape($from)).Count -ne 1){
    throw 'Найдено неоднозначное количество точек подстановки лицензионного предупреждения'
}
$source=$source.Replace($from,$to)
[IO.File]::WriteAllText($path,$source,(New-Object Text.UTF8Encoding($true)))
Write-Host '[RU] PASS: юридическое предупреждение показано по-русски; оригинал не изменён'
