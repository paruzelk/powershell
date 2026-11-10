#Requires -Version 5.1
<#
.SYNOPSIS
    Перевод точных пользовательских сообщений проверок Active Directory.
.NOTES
    Не заменяет подстроки и не переводит LDAP-поля, идентификаторы или имена функций.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$path=Join-Path $ProjectRoot 'Localization/CheckLines-01.ru-RU.json'
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8))
$root=Join-Path $ProjectRoot 'src/modules/Checks'
$utf8=New-Object System.Text.UTF8Encoding($true)
$filesChanged=0;$replacements=0
foreach($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1')){
 $src=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)
 $dst=$src
 foreach($pair in $catalog.PSObject.Properties){
  $english=[string]$pair.Name
  $russian=[string]$pair.Value
  # Translation only of complete literal strings passed to text-output helpers.
  # A keyword in an LDAP filter, an attribute name or a code expression is untouched.
  foreach($fn in @('Show-Line','Show-SubHeader','Show-Header')){
   $from=$fn+' "'+$english+'"'
   $to=$fn+' "'+$russian+'"'
   if($dst.Contains($from)){
    $dst=$dst.Replace($from,$to)
    $replacements++
   }
  }
 }
 if($dst -ne $src){
  [IO.File]::WriteAllText($file.FullName,$dst,$utf8)
  $filesChanged++
 }
}
Write-Host "[RU] Переведены сообщения модулей: $replacements замен в $filesChanged файлах"
