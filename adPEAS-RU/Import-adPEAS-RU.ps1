#Requires -Version 5.1
<#
.SYNOPSIS
    Импорт полной версии adPEAS v2.9.0 и русификация в Windows PowerShell 5.1.
#>
[CmdletBinding()]
param([switch]$SkipBuild)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$commit='ee0c9c47cddcaddae74ef3b8a43f9fef1bf2d082'
$root=$PSScriptRoot
$tmp=Join-Path $env:TEMP ('adpeas-ru-'+[guid]::NewGuid().ToString('N'))
$checks=@{
 'src/adPEAS.ps1'='940c80aabe22a4274e7a31d0ab5a53c7ea30d5eb'
 'src/modules/Reporting/templates/report-template.html'='8114fca0ad5b14b6770021785ec5227e6ea58c93'
 'src/modules/Reporting/templates/report-scripts.js'='bb141072fdb061b741a4e0ed5d9aefaf0c335454'
 'src/modules/Reporting/Export-HTMLReport.ps1'='67c8029f0ddfcc156c1706cce51430943c329840'
 'Build-Release.ps1'='7e8e3a59ab3cc62f693787b39f9d5165bfea4227'
 'Build-Config.psd1'='d262f503feb5fdf174cf7ac80686089cac3c174c'
}
function Get-GitBlobHash([string]$Path) {
 [byte[]]$data=[IO.File]::ReadAllBytes($Path)
 [byte[]]$head=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length+[char]0))
 [byte[]]$all=New-Object byte[] ($head.Length+$data.Length)
 [Buffer]::BlockCopy($head,0,$all,0,$head.Length)
 [Buffer]::BlockCopy($data,0,$all,$head.Length,$data.Length)
 $sha=[Security.Cryptography.SHA1]::Create()
 try {([BitConverter]::ToString($sha.ComputeHash($all))).Replace('-','').ToLowerInvariant()}
 finally {$sha.Dispose()}
}
try {
 New-Item -ItemType Directory -Path $tmp -Force | Out-Null
 $zip=Join-Path $tmp 'source.zip'
 $srcRoot=Join-Path $tmp 'unpacked'
 [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
 Invoke-WebRequest -Uri ("https://codeload.github.com/61106960/adPEAS/zip/"+$commit) -OutFile $zip -UseBasicParsing -TimeoutSec 180
 Expand-Archive -LiteralPath $zip -DestinationPath $srcRoot -Force
 $dirs=@(Get-ChildItem -LiteralPath $srcRoot -Directory)
 if($dirs.Count -ne 1){throw 'Неверная структура upstream ZIP'}
 $source=$dirs[0].FullName
 foreach($x in $checks.GetEnumerator()){
  $p=Join-Path $source $x.Key
  if(-not (Test-Path -LiteralPath $p)){throw "Отсутствует $($x.Key)"}
  if((Get-GitBlobHash $p) -ne $x.Value){throw "Хеш upstream не совпал: $($x.Key)"}
 }
 if(-not (Test-Path (Join-Path $source 'license/LICENSE.md'))){throw 'Исходная лицензия отсутствует'}
 Write-Host '[RU] PASS: зафиксированная версия и SHA-1 исходников'
 foreach($x in @(Get-ChildItem -LiteralPath $source -Force)){
  Copy-Item -LiteralPath $x.FullName -Destination (Join-Path $root $x.Name) -Recurse -Force
 }
} finally {
 if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue}
}
& (Join-Path $root 'Localize-RU.ps1') -ProjectRoot $root
if(-not $?){throw 'Ошибка локализации'}
$buildFile=Join-Path $root 'Build-Release.ps1'
$s=[IO.File]::ReadAllText($buildFile,[Text.Encoding]::UTF8)
$from='$ModuleProblems = Test-BuildModuleList -ModuleList $ModuleList -SourceRoot $SourcePath -ModuleDirectory $Config.ModuleDirectory'
$to='$ModuleProblems = @(Test-BuildModuleList -ModuleList $ModuleList -SourceRoot $SourcePath -ModuleDirectory $Config.ModuleDirectory)'
if($s.Contains($from)){$s=$s.Replace($from,$to)}
elseif(-not $s.Contains($to)){throw 'Неожиданный код Build-Release.ps1'}
$utf8=New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($buildFile,$s,$utf8)
$psfiles=@(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Extension -in @('.ps1','.psm1','.psd1')})
foreach($f in $psfiles){
 $t=[IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8)
 [IO.File]::WriteAllText($f.FullName,$t,$utf8)
 $tokens=$null; $errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
 if($errors -and $errors.Count -gt 0){throw "Синтаксис $($f.FullName): $($errors[0].Message)"}
}
Write-Host "[RU] PASS: $($psfiles.Count) файлов PowerShell"
if(-not $SkipBuild){
 Push-Location $root
 try {
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $buildFile
  if($LASTEXITCODE -ne 0){throw "Build-Release завершился с кодом $LASTEXITCODE"}
 } finally {Pop-Location}
 foreach($name in @('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1')){
  $p=Join-Path $root $name
  if(-not (Test-Path $p)){throw "Не создан $name"}
  $txt=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)
  [IO.File]::WriteAllText($p,$txt,$utf8)
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  if($errors -and $errors.Count -gt 0){throw "Ошибка $name : $($errors[0].Message)"}
 }
 Write-Host '[RU] PASS: четыре автономных варианта'
}
@{Source='61106960/adPEAS';Commit=$commit;Version='2.9.0';Utc=[DateTime]::UtcNow.ToString('o');ActiveDirectoryTested=$false;Localization='Display labels and reports'} | ConvertTo-Json | Out-File (Join-Path $root 'RU-BUILD-MANIFEST.json') -Encoding UTF8
Write-Host '[RU] Полная исходная копия готова'
