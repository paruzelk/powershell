#Requires -Version 5.1
<#
.SYNOPSIS
    Перевод текстов результатов проверок adPEAS, которые собираются динамически.
.DESCRIPTION
    Использует каталог точных замен с привязкой к файлу.
    Изменяет только ранее проверенные текстовые фрагменты исходников;
    машинные FindingId, LDAP-атрибуты и значения ACL не переводятся.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$catalogPath=Join-Path $ProjectRoot 'Localization/ReportSourceMessages.ru-RU.json'
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($catalogPath,[Text.Encoding]::UTF8))
$encoding=New-Object Text.UTF8Encoding($true)
$files=0;$changes=0
foreach($part in $catalog.files.PSObject.Properties){
  $relative=[string]$part.Name
  if($relative -notmatch '^src/modules/Checks/[A-Za-z0-9_/-]+\.ps1$'){
     throw "Недопустимый путь в каталоге: $relative"
  }
  $path=Join-Path $ProjectRoot $relative
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Нет исходного файла: $relative"}
  $source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
  $result=$source
  foreach($rule in $part.Value.PSObject.Properties){
    $before=[string]$rule.Name
    $after=[string]$rule.Value
    if([string]::IsNullOrWhiteSpace($before) -or [string]::IsNullOrWhiteSpace($after)){throw "Пустая замена в $relative"}
    if(-not $result.Contains($before)){
      throw "Исходный текст отсутствует в $relative : $before"
    }
    $result=$result.Replace($before,$after)
    $changes++
  }
  if($result -ne $source){
    $t=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($result,[ref]$t,[ref]$errors)
    if($errors -and $errors.Count -gt 0){
      throw "Нарушен синтаксис $relative : $($errors[0].Message)"
    }
    [IO.File]::WriteAllText($path,$result,$encoding)
    $files++
  }
}
if($files -ne 12 -or $changes -ne 65){throw "Неполный перевод динамических текстов: $changes замен в $files файлах"}
Write-Host "[RU] PASS: $changes проверенных замен текстов проверок в $files исходных файлах"
