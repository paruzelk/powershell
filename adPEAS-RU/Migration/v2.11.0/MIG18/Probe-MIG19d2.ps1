param(
 [Parameter(Mandatory=$true)][string]$Candidate,
 [Parameter(Mandatory=$true)][ValidateSet('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe')][string]$Variant,
 [Parameter(Mandatory=$true)][string]$InputJson,
 [Parameter(Mandatory=$true)][string]$OutputBase
)
$ErrorActionPreference='Stop'
$trace=$OutputBase+'.trace.txt'
function Write-Mig19bcTrace([string]$Stage) {
 [IO.File]::AppendAllText($trace,([DateTime]::UtcNow.ToString('o')+' '+$Stage+[Environment]::NewLine),[Text.Encoding]::UTF8)
}
try {
 Write-Mig19bcTrace 'ENTER'
 if ($Variant -ne 'adPEAS.exe') {
  Import-Module -Name (Join-Path $Candidate $Variant) -Force -ErrorAction Stop
 }
 $ErrorActionPreference='Stop'
 Write-Mig19bcTrace 'IMPORTED'
 $null=Get-Command Convert-adPEASReport -CommandType Function -ErrorAction Stop
 $help=Get-adPEASHelp -Section Commands,Checks 6>&1 | Out-String
 [IO.File]::WriteAllText(($OutputBase+'.help.txt'),$help,[Text.Encoding]::UTF8)
 foreach ($token in @('Установить сеанс LDAP','Сравнить два экспорта JSON','Привилегированные учётные записи','Подключение','Отчёты')) {
  if (-not $help.Contains($token)) { throw "Missing Russian help: $token" }
 }
 if ($help.Contains('Establish LDAP session') -or $help.Contains('Compare two JSON exports')) {throw 'English help description remains'}
 foreach ($term in @('Establish LDAP session','Установить сеанс LDAP')) {
  $hits=Get-adPEASHelp -Search $term 6>&1 | Out-String
  if ($hits -notmatch 'Connect-adPEAS' -or $hits -notmatch 'Установить сеанс LDAP') {throw "Help search regression: $term"}
 }
 if ($Variant -in @('adPEAS.ps1','adPEAS.exe')) {
  $expected=[ordered]@{
   'Invoke-adPEAS'='Основная функция аудита adPEAS v2.'
   'Connect-adPEAS'='Основная функция аутентификации adPEAS v2.'
   'Disconnect-adPEAS'='Завершает текущий сеанс adPEAS и освобождает ресурсы.'
   'Get-adPEASSession'='Показывает сведения о текущем сеансе adPEAS или проверяет состояние соединения.'
   'Convert-adPEASReport'='Формирует отчёты из ранее экспортированного JSON-кэша результатов.'
   'Compare-adPEASReport'='Сравнивает два экспорта результатов adPEAS в JSON.'
   'Get-adPEASHelp'='Показывает справку adPEAS, включая модули проверок, команды и примеры использования.'
   'Get-adPEASOutputBasePath'='Преобразует указанный пользователем путь в базовое имя файлов отчёта.'
  }
  $witness=[ordered]@{}
  foreach ($name in $expected.Keys) {
   $h=Get-Help $name -Full
   if ([string]$h.Synopsis -notlike ('*'+$expected[$name]+'*')) {throw "Russian comment help missing: $name"}
   $witness[$name]=[string]$h.Synopsis
  }
  [IO.File]::WriteAllText(($OutputBase+'.commenthelp.json'),($witness | ConvertTo-Json),[Text.Encoding]::UTF8)
 }
 foreach ($case in @(
  @{Input='report.html';Expected='report'},
  @{Input='report.JSON';Expected='report'},
  @{Input='scan_contoso.com';Expected='scan_contoso.com'},
  @{Input='scan_v1.2';Expected='scan_v1.2'}
 )) {
  if ((Get-adPEASOutputBasePath $case.Input) -cne $case.Expected) {throw "Output path regression: $($case.Input)"}
 }
 $inputHash=(Get-FileHash -LiteralPath $InputJson -Algorithm SHA256).Hash
 Convert-adPEASReport -InputJson $InputJson -OutputPath $OutputBase -Format All -NoColor -ErrorAction Stop -WarningAction Stop
 Write-Mig19bcTrace 'CONVERT_RETURNED'
 if ((Get-FileHash -LiteralPath $InputJson -Algorithm SHA256).Hash -cne $inputHash) {throw 'Input fixture changed'}
 $files=[ordered]@{}
 foreach ($ext in @('html','txt','json')) {
  $file=$OutputBase+'.'+$ext
  $item=Get-Item -LiteralPath $file -ErrorAction Stop
  if ($item.Length -le 3) {throw "Empty output: $ext"}
  $files[$ext]=[ordered]@{Length=$item.Length;SHA256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
 }
 $data=[ordered]@{Variant=$Variant;Status='PASS';InputSha256=$inputHash;Files=$files;RealADTestPerformed=$false}
 [IO.File]::WriteAllText(($OutputBase+'.evidence.json'),($data | ConvertTo-Json -Depth 6),[Text.Encoding]::UTF8)
 Write-Mig19bcTrace 'EVIDENCE_WRITTEN'
 exit 0
} catch {
 [IO.File]::WriteAllText(($OutputBase+'.failure.txt'),($_ | Format-List * -Force | Out-String),[Text.Encoding]::UTF8)
 Write-Mig19bcTrace 'FAIL'
 [Console]::Error.WriteLine($_.Exception.Message)
 exit 1
}
