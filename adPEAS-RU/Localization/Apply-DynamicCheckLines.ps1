#Requires -Version 5.1
<#
.SYNOPSIS
  Перевод динамических строк результатов аудита, содержащих числа и имена.
.DESCRIPTION
  Только полные строковые литералы аргументов Show-Line.
  PowerShell-выражения $..., LDAP/JSON и значения атрибутов остаются неизменными.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$catalogPath=Join-Path $ProjectRoot 'Localization/DynamicCheckLines.ru-RU.json'
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($catalogPath,[Text.Encoding]::UTF8))
$root=Join-Path $ProjectRoot 'src/modules/Checks'
$enc=New-Object Text.UTF8Encoding($true)
$seen=@{}
$changes=0;$filesChanged=0
foreach($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1')){
 $src=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)
 $dst=$src
 foreach($p in $catalog.PSObject.Properties){
  $before='Show-Line "'+[string]$p.Name+'"'
  $after='Show-Line "'+[string]$p.Value+'"'
  if($dst.Contains($before)){
   $dst=$dst.Replace($before,$after)
   $seen[$p.Name]=$true
   $changes++
  }
 }
 if($dst -ne $src){
  [IO.File]::WriteAllText($file.FullName,$dst,$enc)
  $filesChanged++
 }
}
$missing=@()
foreach($p in $catalog.PSObject.Properties){if(-not $seen.ContainsKey($p.Name)){$missing += $p.Name}}
if($missing.Count -gt 0){
 Write-Warning ("Не найдены динамические строки ($($missing.Count)): "+(($missing | Select-Object -First 10) -join ' / '))
}
if($changes -lt 60){throw "Переведено лишь $changes динамических строк, ожидается не менее 60"}
Write-Host "[RU] Динамические строки результатов: $changes замен в $filesChanged файлах"
