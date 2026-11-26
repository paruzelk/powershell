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
 $attributeCases=@(
  @{Name='recycleBin';Text='Disabled';Expected='Отключено'},
  @{Name='LDAPSigning';Text='Optional';Expected='Необязательно'},
  @{Name='ChannelBinding';Text='Not Configured';Expected='Не настроено'},
  @{Name='maxTicketAgeTGT';Text='10 hours (default)';Expected='10 ч (по умолчанию)'},
  @{Name='minPwdLength';Text='7 characters';Expected='7 символов'},
  @{Name='domainControllers';Text='dc.fixture.invalid [PDC Emulator, RID Master]';Expected='dc.fixture.invalid [Эмулятор PDC, Мастер RID]'},
  @{Name='privilegedGroups';Text='Fixture Group (nested)';Expected='Fixture Group (через вложенную группу)'},
  @{Name='ownerKind';Text='User account';Expected='Учётная запись пользователя'},
  @{Name='ownerIsCreator';Text='Unknown - the object records no creator';Expected='Неизвестно — создатель объекта не указан'},
  @{Name='lapsProtected';Text='0 of 5 computers (0%) - the LAPS schema is not present in Active Directory';Expected='0 из 5 компьютеров (0%) — схема LAPS отсутствует в Active Directory'},
  @{Name='lapsUnprotected';Text='5 of 5 computers (100%)';Expected='5 из 5 компьютеров (100%)'},
  @{Name='name';Text='Enabled';Expected='Enabled'},
  @{Name='displayName';Text='Disabled';Expected='Disabled'},
  @{Name='description';Text='10 days';Expected='10 days'},
  @{Name='sAMAccountName';Text='Never';Expected='Never'},
  @{Name='ouName';Text='Unknown';Expected='Unknown'},
  @{Name='decidedBy';Text='Fixture GPO (LDAP signing)';Expected='Fixture GPO (подпись LDAP)'},
  @{Name='EffectiveSetting';Text='Yes - wins precedence on the Domain Controllers OU';Expected='Да — имеет приоритет в OU контроллеров домена'},
  @{Name='objectSid';Text='S-1-5-21-1-2-3-1001';Expected='S-1-5-21-1-2-3-1001'}
 )
 foreach ($case in $attributeCases) {
  if ((ConvertTo-RuDisplayAttribute19g -Name $case.Name -Text $case.Text) -cne $case.Expected) {throw "MIG19gh value mismatch: $($case.Name) $($case.Text)"}
 }
 $labelCases=@{
  'Owner (non-default)'='Нестандартный владелец'
  'ownerKind'='Тип владельца'
  'ownerIsCreator'='Владелец является создателем'
  'activeComputers'='Активные компьютеры'
  'lapsProtected'='Компьютеры под защитой LAPS'
  'lapsUnprotected'='Компьютеры без защиты LAPS'
  'ouName'='Имя OU'
  'lapsUnprotectedComputers'='Список компьютеров без защиты LAPS'
  'name'='Имя (name)'
  'eolDate'='Дата окончания поддержки'
  'daysSinceEoL'='Дней после окончания поддержки'
 }
 foreach ($key in $labelCases.Keys) {
  if ((ConvertTo-RuReportAttributeLabel7 -Text $key) -cne $labelCases[$key]) {throw "MIG19gh label mismatch: $key"}
 }
 # Real rendering, not merely helper calls. Check model is unchanged, IDs and values remain.
 $row=[pscustomobject]@{Name='lapsUnprotected';RowType='SingleValue';OverallSeverity='Hint';ForceAttributeClass=$false;Values=@([pscustomobject]@{Display='5 of 5 computers (100%)';Severity='Hint';FindingId='MIG19GH_FIXTURE';RawValue='5 of 5 computers (100%)'})}
 $before=$row|ConvertTo-Json -Depth 8 -Compress
 $html=Render-HtmlRow -Row $row
 $decoded=[System.Net.WebUtility]::HtmlDecode($html)
 if ($decoded -notmatch 'data-attr-name="lapsUnprotected"' -or $decoded -notmatch 'data-finding-id="MIG19GH_FIXTURE"' -or -not $decoded.Contains('5 из 5 компьютеров (100%)')) {throw 'MIG19gh single HTML witness'}
 $console=Render-ConsoleRow -Row $row 6>&1|Out-String
 if (-not $console.Contains('5 из 5 компьютеров (100%)')) {throw 'MIG19gh single console witness'}
 if (($row|ConvertTo-Json -Depth 8 -Compress) -cne $before) {throw 'MIG19gh renderer mutated single model'}
 $multi=[pscustomobject]@{Name='privilegedGroups';RowType='MultiValue';OverallSeverity='Hint';ForceAttributeClass=$false;Values=@([pscustomobject]@{Display='Fixture A (direct)';Severity='Hint';FindingId='MIG19GH_FIXTURE';RawValue='Fixture A (direct)'},[pscustomobject]@{Display='Fixture B (nested)';Severity='Note';FindingId='';RawValue='Fixture B (nested)'})}
 $before=$multi|ConvertTo-Json -Depth 8 -Compress
 $html=[System.Net.WebUtility]::HtmlDecode((Render-HtmlRow -Row $multi))
 $console=Render-ConsoleRow -Row $multi 6>&1|Out-String
 foreach ($str in @($html,$console)) {
  if (-not $str.Contains('Fixture A (прямое членство)') -or -not $str.Contains('Fixture B (через вложенную группу)')) {throw 'MIG19gh multi renderer witness'}
 }
 if (($multi|ConvertTo-Json -Depth 8 -Compress) -cne $before) {throw 'MIG19gh renderer mutated multi model'}
 $documented=@{
  'Invoke-adPEAS'='Domain Server UseLDAPS UseWindowsAuth Credential Username Password Certificate CertificatePassword Outputfile Module ExcludeModule OPSEC NoColor VerboseLogging InactiveDays IncludePrivileged TimeoutSeconds Format OutputAppend License Statistics'
  'Connect-adPEAS'='Domain Server UseLDAPS IgnoreSSLErrors DnsServer PatchHostsFile Quiet UseWindowsAuth Credential Username Password Certificate CertificatePassword ForcePassTheCert NTHash AES256Key AES128Key Kirbi Ccache ForceNTLM ForceSimpleBind ForceKerberos License BuildCompletionCache TimeoutSeconds'
  'Get-adPEASSession'='TestConnection Quiet'
  'Disconnect-adPEAS'='Force'
  'Convert-adPEASReport'='InputJson OutputPath Format License NoColor'
  'Compare-adPEASReport'='Baseline Current OutputPath NoColor'
  'Get-adPEASHelp'='Section Search'
 }
 $common=@('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','WhatIf','Confirm')
 foreach ($name in $documented.Keys) {
  $command=Get-Command $name -CommandType Function -ErrorAction Stop
  $actual=@($command.Parameters.Keys|Where-Object {$_ -notin $common}|Sort-Object)
  $expected=@($documented[$name].Split(' ')|Sort-Object)
  if (($actual -join '|') -cne ($expected -join '|')) {throw "MIG19gh documented parameter mismatch: $name"}
 }
 Write-Mig19bcTrace 'MIG19GH_RENDER_DOC_OK'
 $jCases=@(
  @{Text='Собрано объектов: 11; домен: fixture.invalid: 1 domains, 2 users, 3 groups, 1 computers, 1 OUs, 1 containers, 1 GPOs, 1 ADCS objects';Expected='Собрано объектов: 11; домен: fixture.invalid: доменов: 1, пользователей: 2, групп: 3, компьютеров: 1, OU: 1, контейнеров: 1, GPO: 1, объектов AD CS: 1'},
  @{Text='Собрано объектов: 2; домен: fixture.invalid: 2 users';Expected='Собрано объектов: 2; домен: fixture.invalid: пользователей: 2'},
  @{Text='Собрано объектов: 2; домен: fixture.invalid: 2 custom objects';Expected='Собрано объектов: 2; домен: fixture.invalid: 2 custom objects'},
  @{Text='Компьютеры с устаревшей версией Microsoft Windows: 3 (2 inactive accounts filtered)';Expected='Компьютеры с устаревшей версией Microsoft Windows: 3 (исключено неактивных учётных записей: 2)'}
 )
 foreach ($case in $jCases) {
  if ((ConvertTo-RuReportLine -Text $case.Text) -cne $case.Expected) {throw 'MIG19j HTML message witness'}
  if ((ConvertTo-RuConsoleText19f -Text $case.Text -Class 'Hint') -cne $case.Expected) {throw 'MIG19j console message witness'}
 }
 if ((ConvertTo-RuReportAttributeLabel7 -Text 'lapsUnprotectedComputers') -cne 'Список компьютеров без защиты LAPS') {throw 'MIG19j list label'}
 $align=Get-adPEASAttributeAlignment -Name 'Длинная подпись' -Width 4
 if ($align.PaddedName -cne 'Длинная подпись: ') {throw 'MIG19j long label separator'}
 $align=Get-adPEASAttributeAlignment -Name '' -Width 4
 if ($align.PaddedName -cne '    ') {throw 'MIG19j continuation alignment'}
 $align=Get-adPEASAttributeAlignment -Name 'X' -Width 4
 if ($align.PaddedName -cne 'X:  ') {throw 'MIG19j short label alignment'}
 $sessionKey=Show-Output -Key 'Domain:' -Value 'fixture.invalid' -Class Standard -NoCollect 6>&1|Out-String
 if (-not $sessionKey.Contains('Домен:') -or -not $sessionKey.Contains('fixture.invalid')) {throw 'MIG19j session key'}
 Write-Mig19bcTrace 'MIG19J_DISPLAY_OK'
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
