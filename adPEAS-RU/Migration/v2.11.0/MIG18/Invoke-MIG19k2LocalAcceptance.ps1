[CmdletBinding(DefaultParameterSetName='Acceptance')]
param(
 [Parameter(Mandatory=$true,ParameterSetName='Acceptance')][string]$OpsecJson,
 [Parameter(Mandatory=$true,ParameterSetName='Acceptance')][string]$FullJson,
 [Parameter(Mandatory=$true,ParameterSetName='SelfTest')][switch]$SelfTest,
 [Parameter(ParameterSetName='Acceptance')][string]$Candidate = (Join-Path $PSScriptRoot 'candidate\adPEAS.ps1'),
 [Parameter(ParameterSetName='Acceptance')][string]$OutputDirectory = (Join-Path (Get-Location).Path ('MIG19k2-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)))
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {throw 'Требуется Windows PowerShell 5.1'}
function Read-Cache([string]$Path) {
 Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
# Normalize property ordering, not data. Timestamp strings use the same local time zone
# when conversion runs on the original workstation. Compare exact scalar values.
function Normalize-Value($Value) {
 if ($null -eq $Value) {return $null}
 if ($Value -is [System.Management.Automation.PSCustomObject]) {
  $map=[ordered]@{}
  foreach ($prop in @($Value.PSObject.Properties|Sort-Object Name)) {
   $map[$prop.Name]=Normalize-Value $prop.Value
  }
  return $map
 }
 if ($Value -is [array]) {
  $items=New-Object 'System.Collections.Generic.List[object]'
  foreach ($item in $Value) {$items.Add((Normalize-Value $item))}
  return ,$items.ToArray()
 }
 return $Value
}
function Get-NormalJson($Value) {
 ConvertTo-Json -InputObject (Normalize-Value $Value) -Depth 70 -Compress
}
function Get-HTMLMetrics([string]$Html) {
 $summary=[ordered]@{}
 foreach ($class in @('finding','hint','note','secure')) {
  # Limit matching to one button; a missing value must never borrow the next card.
  $pattern='<button\b[^>]*\sclass="summary-card '+$class+'"[^>]*>((?:(?!<button\b|</button\s*>)[\s\S])*)</button\s*>'
  $m=[regex]::Matches($Html,$pattern)
  if ($m.Count -ne 1) {throw "Нет однозначной кнопки счётчика HTML: $class (найдено: $($m.Count))"}
  $v=[regex]::Matches($m[0].Groups[1].Value,'<div\b[^>]*\sclass="value"[^>]*>\s*(\d+)\s*</div\s*>')
  if ($v.Count -ne 1) {throw "Нет однозначного значения счётчика HTML: $class (найдено: $($v.Count))"}
  $summary[$class]=[int]$v[0].Groups[1].Value
 }
 [ordered]@{Cards=[regex]::Matches($Html,'class="finding-card(?:\s|")').Count;Attributes=[regex]::Matches($Html,'\bdata-attr-name="').Count;Summary=$summary}
}
function Get-LocalException([System.Management.Automation.ErrorRecord]$Record,[string]$Stage) {
 [ordered]@{
  Stage=$Stage
  Type=$Record.Exception.GetType().FullName
  Message=$Record.Exception.Message
  FullyQualifiedErrorId=$Record.FullyQualifiedErrorId
  ScriptName=$Record.InvocationInfo.ScriptName
  ScriptLineNumber=$Record.InvocationInfo.ScriptLineNumber
  OffsetInLine=$Record.InvocationInfo.OffsetInLine
  ScriptStackTrace=$Record.ScriptStackTrace
 }
}
function Test-LocalAcceptanceHelpers {
 $fixture=@'
<button class="summary-card finding" onclick="filterBySeverity('finding')" aria-label="Synthetic: 2"><div class="value">2</div></button>
<button aria-label="Synthetic: 1" class="summary-card hint"><div class="value">1</div></button>
<button class="summary-card note"><div class="value">0</div></button>
<button class="summary-card secure" aria-label="Synthetic: 3"><div class="value">3</div></button>
<div class="finding-card test"><span data-attr-name="fixture"></span></div>
'@
 $m=Get-HTMLMetrics $fixture
 if (($m.Summary.Values -join '|') -cne '2|1|0|3' -or $m.Cards -ne 1 -or $m.Attributes -ne 1) {throw 'MIG19k2 selftest: valid metrics'}
 $bad=@(
  $fixture.Replace('class="summary-card finding"','class="other-card finding"')
  ($fixture + '<button class="summary-card finding"><div class="value">2</div></button>')
  $fixture.Replace('<div class="value">2</div>','<div class="other">2</div>')
  $fixture.Replace('<div class="value">2</div>','<div class="value">2</div><div class="value">9</div>')
  $fixture.Replace('<div class="value">2</div>','<div class="value">invalid</div>')
 )
 foreach ($case in $bad) {
  $rejected=$false
  try {$null=Get-HTMLMetrics $case}
  catch {
   $rejected=$true
   $d=Get-LocalException $_ 'HTMLMetrics'
   if ($d.Stage -ne 'HTMLMetrics' -or -not $d.Message -or -not $d.FullyQualifiedErrorId -or $d.ScriptLineNumber -le 0 -or -not $d.ScriptStackTrace) {throw 'MIG19k2 selftest: exception details'}
  }
  if (-not $rejected) {throw 'MIG19k2 selftest: invalid HTML accepted'}
 }
 Write-Host 'PASS MIG19k2: 1 valid metrics fixture; 5 rejected invalid fixtures; exception evidence'
}
if ($SelfTest) {
 Test-LocalAcceptanceHelpers
 return
}
$source=(Resolve-Path -LiteralPath $Candidate).Path
$op=(Resolve-Path -LiteralPath $OpsecJson).Path
$full=(Resolve-Path -LiteralPath $FullJson).Path
if ($op -eq $full) {throw 'Нужны два разных исходных JSON'}
$folder=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath $folder) {throw 'Каталог результатов уже существует; выберите новый'}
$null=New-Item -ItemType Directory -Path $folder
$records=New-Object 'System.Collections.Generic.List[object]'
$inputs=@(@{Mode='OPSEC';Path=$op;Count=231;Modules=9;Cards=78;Attributes=631;Summary=@(22,22,26,35)},@{Mode='Full';Path=$full;Count=244;Modules=10;Cards=80;Attributes=701;Summary=@(27,19,27,37)})
Import-Module $source -Force -ErrorAction Stop
foreach ($entry in $inputs) {
 $mode=$entry.Mode
 $inputPath=$entry.Path
 $inputHash=(Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash
 $output=Join-Path $folder ('AD-Audit-MIG19k2-'+$mode)
 $failures=New-Object 'System.Collections.Generic.List[string]'
 $changed=New-Object 'System.Collections.Generic.List[int]'
 $metrics=$null
 $exception=$null
 $stage='ReadInput'
 try {
  $before=Read-Cache $inputPath
  if ($before.CacheVersion -ne 1 -or $before.Complete -ne $true -or $before.FindingCount -ne $entry.Count -or @($before.Findings).Count -ne $entry.Count -or @($before.CompletedModules).Count -ne $entry.Modules) {throw 'Исходный JSON не соответствует контрольному MIG19i'}
  $stage='ConvertReport'
  Convert-adPEASReport -InputJson $inputPath -OutputPath $output -Format All -NoColor -ErrorAction Stop -WarningAction Stop
  $stage='VerifyOutputFiles'
  foreach ($ext in @('html','txt','json')) {
   if ((Get-Item -LiteralPath ($output+'.'+$ext) -ErrorAction Stop).Length -le 3) {throw "Пустой файл $ext"}
  }
  $stage='CompareJson'
  $after=Read-Cache ($output+'.json')
  foreach ($key in @('CacheVersion','Domain','Server','adPEASVersion','Complete','CompletedModules','FindingCount')) {
   if ((Get-NormalJson $before.$key) -cne (Get-NormalJson $after.$key)) {$failures.Add("Metadata: $key")}
  }
  if (@($before.Findings).Count -ne @($after.Findings).Count) {$failures.Add('Finding count')}
  else {
   for ($i=0;$i -lt @($before.Findings).Count;$i++) {
    if ((Get-NormalJson $before.Findings[$i]) -cne (Get-NormalJson $after.Findings[$i])) {$changed.Add($i)}
   }
   if ($changed.Count -gt 0) {$failures.Add('Finding contents differ; review indices locally')}
  }
  $html=[IO.File]::ReadAllText($output+'.html',[Text.Encoding]::UTF8)
  $txt=[IO.File]::ReadAllText($output+'.txt',[Text.Encoding]::UTF8)
  $stage='HTMLMetrics'
  $metrics=Get-HTMLMetrics $html
  $stage='VerifyPresentation'
  if ($metrics.Cards -ne $entry.Cards) {$failures.Add('HTML card count')}
  if ($metrics.Attributes -ne $entry.Attributes) {$failures.Add('HTML attribute count')}
  $metrics['SidSessionDiagnostics']=[regex]::Matches($txt,'(?im)(?:Нет активного сеанса для|No active session for|No active LDAP (?:session|connection) for)\s+Convert(?:To|From)-SID').Count
  if ($metrics.SidSessionDiagnostics -ne 0) {$failures.Add('Offline SID session diagnostics in TXT')}
  $actual=@($metrics.Summary.finding,$metrics.Summary.hint,$metrics.Summary.note,$metrics.Summary.secure)
  if (($actual -join '|') -ne ($entry.Summary -join '|')) {$failures.Add('HTML severity summary')}
  if ($txt.Contains([string][char]27)) {$failures.Add('TXT ANSI')}
  if (-not $txt.Contains('Срок хранения удалённых объектов (tombstoneLifetime): ')) {$failures.Add('TXT long label spacing')}
  if ($mode -eq 'Full') {
   foreach ($text in @([System.Net.WebUtility]::HtmlDecode($html),$txt)) {
    if (-not $text.Contains('Список компьютеров без защиты LAPS')) {$failures.Add('LAPS label')}
    if (-not $text.Contains('исключено неактивных учётных записей: 1')) {$failures.Add('Inactive account message')}
    if (-not $text.Contains('доменов: 1, пользователей: 12, групп: 48, компьютеров: 20')) {$failures.Add('BloodHound summary')}
   }
  }
 } catch {
  $exception=Get-LocalException $_ $stage
  $failures.Add('Conversion or verification exception ['+$stage+']: '+$exception.Type+': '+$exception.Message)
 }
 if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash -cne $inputHash) {$failures.Add('INPUT MODIFIED')}
 $records.Add([pscustomobject]@{Mode=$mode;Status=$(if ($failures.Count -eq 0) {'PASS'} else {'REVIEW'});FindingsExpected=$entry.Count;Metrics=$metrics;Exception=$exception;ChangedFindingIndices=@($changed.ToArray());Failures=@($failures.ToArray())})
}
$passed=@($records|Where-Object {$_.Status -ne 'PASS'}).Count -eq 0
$report=[ordered]@{Schema='adPEAS-RU.MIG19k2.LocalAcceptance.1';Status=$(if ($passed) {'PASS'} else {'REVIEW'});CandidateSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;RealADScanPerformed=$false;ProductionReady=$false;Scope='CacheAndPresentationAcceptance';OfflineSidRenderingVerified=$passed;Results=$records.ToArray()}
$path=Join-Path $folder 'MIG19k2-acceptance.json'
[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 12),[Text.Encoding]::UTF8)
$records|Select-Object Mode,Status,FindingsExpected,@{Name='Differences';Expression={$_.Failures.Count}}|Format-Table -AutoSize
Write-Host "Результаты: $folder"
if (-not $passed) {throw 'MIG19k2: имеются расхождения; см. MIG19k2-acceptance.json'}
