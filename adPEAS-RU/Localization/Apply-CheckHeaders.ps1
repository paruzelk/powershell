#Requires -Version 5.1
<#
.SYNOPSIS
    Перевод заголовков реальных проверок AD, попадающих в HTML и текстовые отчёты.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$glossaryPath=Join-Path $ProjectRoot 'Localization/CheckHeaders.ru-RU.json'
$dictionary=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($glossaryPath,[Text.Encoding]::UTF8))
$root=Join-Path $ProjectRoot 'src/modules/Checks'
$utf8=New-Object System.Text.UTF8Encoding($true)
$total=0
$seen=@{}
foreach($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1')){
 $src=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)
 $dst=$src
 foreach($pair in $dictionary.PSObject.Properties){
  foreach($cmd in @('Show-SubHeader','Show-Header')){
   $from=$cmd+' "'+$pair.Name+'"'
   $to=$cmd+' "'+[string]$pair.Value+'"'
   if($dst.Contains($from)){
    $dst=$dst.Replace($from,$to)
    $seen[$pair.Name]=$true
    $total++
   }
  }
 }
 if($dst -ne $src){[IO.File]::WriteAllText($file.FullName,$dst,$utf8)}
}
if($seen.Count -ne @($dictionary.PSObject.Properties).Count){
 $missing=@($dictionary.PSObject.Properties.Name | Where-Object {-not $seen.ContainsKey($_)})
 throw ('Часть заголовков не найдена: '+($missing -join ', '))
}
Write-Host "[RU] PASS: $($seen.Count) заголовков реальных проверок локализованы"
