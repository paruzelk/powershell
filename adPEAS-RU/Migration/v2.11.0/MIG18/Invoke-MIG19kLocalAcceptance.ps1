[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$OpsecJson,
 [Parameter(Mandatory=$true)][string]$FullJson,
 [string]$Candidate = (Join-Path $PSScriptRoot 'candidate\adPEAS.ps1'),
 [string]$OutputDirectory = (Join-Path (Get-Location).Path ('MIG19k-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)))
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {throw 'Требуется Windows PowerShell 5.1'}
$source=(Resolve-Path -LiteralPath $Candidate).Path
$op=(Resolve-Path -LiteralPath $OpsecJson).Path
$full=(Resolve-Path -LiteralPath $FullJson).Path
if ($op -eq $full) {throw 'Нужны два разных исходных JSON'}
$folder=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath $folder) {throw 'Каталог результатов уже существует; выберите новый'}
$null=New-Item -ItemType Directory -Path $folder
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
  $m=[regex]::Matches($Html,('class="summary-card '+$class+'">[\s\S]*?<div class="value">\s*(\d+)\s*</div>'))
  if ($m.Count -ne 1) {throw "Нет однозначного счётчика HTML: $class"}
  $summary[$class]=[int]$m[0].Groups[1].Value
 }
 [ordered]@{Cards=[regex]::Matches($Html,'class="finding-card(?:\s|")').Count;Attributes=[regex]::Matches($Html,'\bdata-attr-name="').Count;Summary=$summary}
}
$records=New-Object 'System.Collections.Generic.List[object]'
$inputs=@(@{Mode='OPSEC';Path=$op;Count=231;Modules=9;Cards=78;Summary=@(22,22,26,35)},@{Mode='Full';Path=$full;Count=244;Modules=10;Cards=80;Summary=@(27,19,27,37)})
Import-Module $source -Force -ErrorAction Stop
foreach ($entry in $inputs) {
 $mode=$entry.Mode
 $inputPath=$entry.Path
 $inputHash=(Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash
 $output=Join-Path $folder ('AD-Audit-MIG19k-'+$mode)
 $failures=New-Object 'System.Collections.Generic.List[string]'
 $changed=New-Object 'System.Collections.Generic.List[int]'
 $metrics=$null
 try {
  $before=Read-Cache $inputPath
  if ($before.CacheVersion -ne 1 -or $before.Complete -ne $true -or $before.FindingCount -ne $entry.Count -or @($before.Findings).Count -ne $entry.Count -or @($before.CompletedModules).Count -ne $entry.Modules) {throw 'Исходный JSON не соответствует контрольному MIG19i'}
  Convert-adPEASReport -InputJson $inputPath -OutputPath $output -Format All -NoColor -ErrorAction Stop -WarningAction Stop
  foreach ($ext in @('html','txt','json')) {
   if ((Get-Item -LiteralPath ($output+'.'+$ext) -ErrorAction Stop).Length -le 3) {throw "Пустой файл $ext"}
  }
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
  $metrics=Get-HTMLMetrics $html
  if ($metrics.Cards -ne $entry.Cards) {$failures.Add('HTML card count')}
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
 } catch {$failures.Add('Conversion or verification exception: '+$_.Exception.GetType().FullName)}
 if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash -cne $inputHash) {$failures.Add('INPUT MODIFIED')}
 $records.Add([pscustomobject]@{Mode=$mode;Status=$(if ($failures.Count -eq 0) {'PASS'} else {'REVIEW'});FindingsExpected=$entry.Count;Metrics=$metrics;ChangedFindingIndices=@($changed.ToArray());Failures=@($failures.ToArray())})
}
$passed=@($records|Where-Object {$_.Status -ne 'PASS'}).Count -eq 0
$report=[ordered]@{Schema='adPEAS-RU.MIG19k.LocalAcceptance.1';Status=$(if ($passed) {'PASS'} else {'REVIEW'});CandidateSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;RealADScanPerformed=$false;Results=$records.ToArray()}
$path=Join-Path $folder 'MIG19k-acceptance.json'
[IO.File]::WriteAllText($path,($report|ConvertTo-Json -Depth 12),[Text.Encoding]::UTF8)
$records|Select-Object Mode,Status,FindingsExpected,@{Name='Differences';Expression={$_.Failures.Count}}|Format-Table -AutoSize
Write-Host "Результаты: $folder"
if (-not $passed) {throw 'MIG19k: имеются расхождения; см. MIG19k-acceptance.json'}
