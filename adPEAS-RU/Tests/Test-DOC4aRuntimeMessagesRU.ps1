#Requires -Version 5.1
<#
.SYNOPSIS
    DOC4a: проверка реальных русских сообщений в собранных модулях аудита.
.DESCRIPTION
    Только офлайн-чтение модулей, каталога и проверка синтаксиса.
    Проверки AD/SMB не запускаются, настройки домена не изменяются.
#>
[CmdletBinding()]
param([string]$ProjectRoot=(Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Off
$ErrorActionPreference='Stop'

$catalogPath=Join-Path $ProjectRoot 'Localization/DOC4a-RuntimeMessages.ru-RU.json'
$appPath=Join-Path $ProjectRoot 'Localization/Apply-DOC4aRuntimeMessages.ps1'
$runnerPath=Join-Path $ProjectRoot 'Localize-RU.ps1'
$catalog=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($catalogPath,[Text.Encoding]::UTF8))
if($catalog.schema -cne 'adPEAS-RU.DOC4a.RuntimeMessages.1' -or $catalog.locale -cne 'ru-RU') {
    throw 'DOC4a: неверная схема каталога'
}
$loader=[IO.File]::ReadAllText($runnerPath,[Text.Encoding]::UTF8)
if(-not $loader.Contains('Apply-DOC4aRuntimeMessages.ps1')){
    throw 'DOC4a: новый этап не включён в конвейер сборки'
}
$patcher=[IO.File]::ReadAllText($appPath,[Text.Encoding]::UTF8)
foreach($term in @('VariableExpressionAst','CommandAst','ParseInput','UTF8Encoding','-ne 69','-ne 9')){
 if(-not $patcher.Contains($term)){throw "DOC4a: отсутствует защитный контроль $term"}
}
$files=@($catalog.files.PSObject.Properties)
if($files.Count -ne 9){throw "DOC4a: ожидалось 9 модулей, найдено $($files.Count)"}
$count=0
foreach($entry in $files){
 $relative=[string]$entry.Name
 $path=Join-Path $ProjectRoot $relative
 if(-not (Test-Path -LiteralPath $path)){throw "DOC4a: файл не найден: $relative"}
 $source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
 $rules=@($entry.Value.PSObject.Properties)
 if($rules.Count -lt 1){throw "DOC4a: нет правил для $relative"}
 foreach($item in $rules){
  $en=[string]$item.Name
  $ru=[string]$item.Value
  if($source.Contains($en)){
   throw "DOC4a: английское сообщение осталось в $relative : $en"
  }
  if(([regex]::Matches($source,[regex]::Escape($ru))).Count -ne 1){
   throw "DOC4a: русский текст отсутствует или дублируется в $relative : $ru"
  }
  if($ru -notmatch '[А-Яа-яЁё]'){throw "DOC4a: не русский текст в $relative"}
  $count++
 }
 $tokens=$null
 $errors=$null
 [void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
 if($errors -and $errors.Count -gt 0){
  throw "DOC4a: синтаксическая ошибка $relative — $($errors[0].Message)"
 }
}
if($count -ne 69){throw "DOC4a: отсутствуют правила (ожидалось 69, получено $count)"}
$critical=@{
 'src/modules/Checks/Creds/Get-BitLockerRecoveryKeyAccess.ps1'=@(
  'msFVE-RecoveryPassword','BITLOCKER_RECOVERY_DELEGATED','-IncludePrivileged',
  'проверенных контейнерах компьютеров')
 'src/modules/Checks/Creds/Get-CredentialRoaming.ps1'=@(
  'CREDENTIAL_ROAMING_READABLE','CREDENTIAL_ROAMING_DELEGATED',
  'Control Access','схема недоступна','Tier 0')
 'src/modules/Checks/ADCS/Get-WeakCertificateMapping.ps1'=@(
  'NTAuth','Schannel','PKINIT','certutil -viewstore -enterprise NTAuth')
 'src/modules/Checks/Accounts/Get-ManagedServiceAccountSecurity.ps1'=@(
  'КРИТИЧЕСКИЙ РИСК','без встречной ссылки','непривилегированных','dMSA')
}
foreach($entry in $critical.GetEnumerator()){
 $text=[IO.File]::ReadAllText((Join-Path $ProjectRoot $entry.Key),[Text.Encoding]::UTF8)
 foreach($term in $entry.Value){
  if($text.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -lt 0){
   throw "DOC4a: отсутствует критическое условие $($entry.Key) / $term"
  }
 }
}
Write-Host "PASS DOC4a: 69 русских сообщений, 9 модулей, синтаксис PowerShell 5.1; классификация и команды сохранены" -ForegroundColor Green
