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
   'Get-DomainUser'='Получает объекты пользователей Active Directory (обёртка Get-DomainObject).'
   'Get-DomainComputer'='Основная функция запроса объектов компьютеров Active Directory.'
   'Get-DomainGroup'='Основная функция запроса объектов групп Active Directory.'
   'Get-DomainObject'='Универсальная функция запроса объектов Active Directory любого типа.'
   'Get-DomainGPO'='Основная функция запроса объектов групповых политик Active Directory.'
   'Get-CertificateTemplate'='Получает шаблоны сертификатов AD CS из Active Directory.'
   'Get-DomainDNSRecord'='Читает адресные записи DNS-зон, интегрированных в Active Directory, через LDAP.'
   'Get-DomainDNSZone'='Перечисляет зоны прямого просмотра DNS, хранящиеся в Active Directory.'
   'Get-CertificateAuthority'='Получает центры сертификации служб сертификатов Active Directory (AD CS).'
  }
  $witness=[ordered]@{}
  $failures=@()
  foreach ($name in $expected.Keys) {
   $h=Get-Help $name -Full
   $witness[$name]=[string]$h.Synopsis
   if ([string]$h.Synopsis -notlike ('*'+$expected[$name]+'*')) {$failures+= $name}
  }
  [IO.File]::WriteAllText(($OutputBase+'.commenthelp.json'),($witness | ConvertTo-Json),[Text.Encoding]::UTF8)
  [IO.File]::WriteAllText(($OutputBase+'.commenthelp-status.json'),([ordered]@{Failed=@($failures);Passed=($failures.Count -eq 0)} | ConvertTo-Json),[Text.Encoding]::UTF8)
  if ($failures.Count -gt 0) {Write-Mig19bcTrace ('COMMENT_HELP_FAILED '+($failures -join ','))}
  else {Write-Mig19bcTrace 'COMMENT_HELP_OK'}
 }
 foreach ($case in @(
  @{Input='report.html';Expected='report'},
  @{Input='report.JSON';Expected='report'},
  @{Input='scan_contoso.com';Expected='scan_contoso.com'},
  @{Input='scan_v1.2';Expected='scan_v1.2'}
 )) {
  if ((Get-adPEASOutputBasePath $case.Input) -cne $case.Expected) {throw "Output path regression: $($case.Input)"}
 }
 $displayCases=@(
  @{Text='[1/10] Analyzing Domain Configuration';Class='Info';Expected='[1/10] Анализ конфигурации домена'},
  @{Text='[10/10] Collecting BloodHound Data';Class='Info';Expected='[10/10] Сбор данных BloodHound'},
  @{Text='Establishing LDAP Connection';Class='Info';Expected='Установление соединения LDAP'},
  @{Text='Scan Summary';Class='Info';Expected='Сводка аудита'},
  @{Text='Executing Modules: Domain, Bloodhound';Class='Standard';Expected='Выполняемые модули: Domain, Bloodhound'},
  @{Text='Duration: 1.5 seconds';Class='Hint';Expected='Продолжительность: 1.5 сек.'},
  @{Text='Who can add computers to the domain:';Class='Hint';Expected='Субъекты, которым разрешено добавлять компьютеры в домен:'},
  @{Text='Found 3 computer(s) without LAPS protection, by OU:';Class='Hint';Expected='Обнаружено компьютеров без защиты LAPS: 3 (по OU):'},
  @{Text='Checking which logons Group Policy denies...';Class='SubInfo';Expected='Проверка видов входа, запрещённых групповыми политиками...'},
  @{Text='MIG19f-SYNTHETIC-UNCHANGED';Class='Note';Expected='MIG19f-SYNTHETIC-UNCHANGED'}
 )
 foreach ($case in $displayCases) {
  $actual=ConvertTo-RuConsoleText19f -Text $case.Text -Class $case.Class
  if ($actual -cne $case.Expected) {throw "MIG19f display mismatch: $($case.Text)"}
 }
 Show-Output -Value 'Scan Summary' -Class Info -NoCollect
 Show-Output -Value 'Duration: 1.5 seconds' -Class Hint -NoCollect
 Write-Mig19bcTrace 'MIG19F_DISPLAY_OK'
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
 $diffBase=$OutputBase+'.comparison'
 Compare-adPEASReport -Baseline $InputJson -Current $InputJson -OutputPath $diffBase -NoColor -ErrorAction Stop -WarningAction Stop
 $diffFiles=[ordered]@{}
 foreach ($ext in @('html','txt')) {
  $file=$diffBase+'.'+$ext
  $item=Get-Item -LiteralPath $file -ErrorAction Stop
  if ($item.Length -le 3) {throw "Empty comparison output: $ext"}
  $diffFiles[$ext]=[ordered]@{Length=$item.Length;SHA256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
 }
 if ((Get-FileHash -LiteralPath $InputJson -Algorithm SHA256).Hash -cne $inputHash) {throw 'Comparison modified fixture'}
 Write-Mig19bcTrace 'COMPARE_RETURNED'
 $data=[ordered]@{Variant=$Variant;Status='PASS';InputSha256=$inputHash;Files=$files;ComparisonFiles=$diffFiles;RealADTestPerformed=$false}
 [IO.File]::WriteAllText(($OutputBase+'.evidence.json'),($data | ConvertTo-Json -Depth 6),[Text.Encoding]::UTF8)
 Write-Mig19bcTrace 'EVIDENCE_WRITTEN'
 exit 0
} catch {
 [IO.File]::WriteAllText(($OutputBase+'.failure.txt'),($_ | Format-List * -Force | Out-String),[Text.Encoding]::UTF8)
 Write-Mig19bcTrace 'FAIL'
 [Console]::Error.WriteLine($_.Exception.Message)
 exit 1
}
