#Requires -Version 5.1
<#
.SYNOPSIS
  DOC6e: перевод сообщений DNS/SRV, привилегий и TGT.
.DESCRIPTION
  Только точные строковые литералы; все изменения проверяются до записи.
  Машинные значения, AD-атрибуты, Reason, Severity и алгоритмы не изменяются.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference='Stop'
$manifestPath=Join-Path $PSScriptRoot 'DOC6e-HelperDiagnostics.ru-RU.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($manifest.schema -ne 'adPEAS-RU.DOC6e.HelperDiagnostics.1'){throw 'DOC6e: неверная схема'}
$allowed=@('src/modules/Helpers/Resolve-adPEASName.ps1','src/modules/Helpers/Test-IsPrivileged.ps1','src/modules/Helpers/Get-adPEASSession.ps1')
$plans=New-Object 'System.Collections.Generic.List[object]'
$translations=0
foreach($entry in @($manifest.files)){
    $relative=[string]$entry.path
    if($relative -cnotin $allowed -or $relative.Contains('..')){throw "DOC6e: недопустимый файл $($relative)"}
    if(@($plans | Where-Object {$_.Relative -ceq $relative}).Count -gt 0){throw "DOC6e: повторяется файл $($relative)"}
    $file=Join-Path $ProjectRoot ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "DOC6e: файл отсутствует $($relative)"}
    $result=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
    $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($msg in @($entry.messages)){
        $from=[string]$msg.from
        $to=[string]$msg.to
        $expected=[int]$msg.occurrences
        if([string]::IsNullOrWhiteSpace($from) -or [string]::IsNullOrWhiteSpace($to) -or $from -ceq $to -or $expected -lt 1 -or -not $seen.Add($from)){
            throw "DOC6e: ошибочный элемент $($relative):$($msg.line)"
        }
        $quoted='"'+$from+'"'
        $actual=([regex]::Matches($result,[regex]::Escape($quoted))).Count
        if($actual -ne $expected){throw "DOC6e: несовпадение $($relative):$($msg.line), ожидается $expected, найдено $actual"}
        $result=$result.Replace($quoted,'"'+$to+'"')
        $translations++
    }
    $plans.Add([PSCustomObject]@{Relative=$relative;Path=$file;Text=$result})
}
if($plans.Count -ne 3 -or $translations -ne 110){throw "DOC6e: ожидалось 3 файла / 110 переводов, обнаружено $($plans.Count) / $translations"}
foreach($p in $plans){[IO.File]::WriteAllText($p.Path,$p.Text,(New-Object Text.UTF8Encoding($true)))}
Write-Host '[RU] PASS DOC6e: 110 текстовых переводов, 3 UTF-8 BOM PowerShell файла'
