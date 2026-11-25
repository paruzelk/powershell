param(
 [Parameter(Mandatory=$true)][string]$Candidate,
 [Parameter(Mandatory=$true)][string]$Report
)
$ErrorActionPreference='Stop'
$source=Join-Path $Candidate 'src/modules/Helpers/Get-adPEASOutputBasePath.ps1'
. $source
$expected='Преобразует указанный пользователем путь в базовое имя файлов отчёта.'
$help=Get-Help Get-adPEASOutputBasePath -Full
if ([string]$help.Synopsis -notlike ('*'+$expected+'*')) {throw 'Isolated helper synopsis missing'}
$desc=($help.Description | Out-String)
if ($desc -notmatch '\.com' -or $desc -notmatch '\.local' -or $desc -notmatch '\.de') {throw 'Domain suffix documentation missing'}
$parameter=Get-Help Get-adPEASOutputBasePath -Parameter Path
if (($parameter | Out-String) -notmatch 'Путь пользователя') {throw 'Russian Path description missing'}
foreach ($case in @(
 @{Input='report.html';Expected='report'},
 @{Input='report.JSON';Expected='report'},
 @{Input='report.txt';Expected='report'},
 @{Input='scan_contoso.com';Expected='scan_contoso.com'},
 @{Input='scan_contoso.local';Expected='scan_contoso.local'},
 @{Input='scan_contoso.de';Expected='scan_contoso.de'},
 @{Input='scan_v1.2';Expected='scan_v1.2'},
 @{Input='.html';Expected='.html'}
)) {
 if ((Get-adPEASOutputBasePath $case.Input) -cne $case.Expected) {throw "Output path regression: $($case.Input)"}
}
$data=[ordered]@{Schema='adPEAS-RU.MIG19d2b.IsolatedHelp.1';Status='PASS';PowerShellVersion=$PSVersionTable.PSVersion.ToString();Synopsis=[string]$help.Synopsis;Description=$desc;PathDescription=($parameter | Out-String);PathCases=8;RealADTestPerformed=$false}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Report),($data | ConvertTo-Json -Depth 5),[Text.Encoding]::UTF8)
Write-Host 'PASS MIG19d2b isolated Get-Help and eight output path cases'
