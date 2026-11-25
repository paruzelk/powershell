param(
 [Parameter(Mandatory=$true)][string]$Candidate,
 [Parameter(Mandatory=$true)][ValidateSet('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe')][string]$Variant,
 [Parameter(Mandatory=$true)][string]$Evidence,
 [Parameter(Mandatory=$true)][string]$Trace
)
$ErrorActionPreference = 'Stop'
function Write-Mig19a3Trace([string]$Stage) {
 [IO.File]::AppendAllText($Trace, ([DateTime]::UtcNow.ToString('o')+' '+$Stage+[Environment]::NewLine), [Text.Encoding]::UTF8)
}
try {
 Write-Mig19a3Trace 'ENTER'
 if ($Variant -ne 'adPEAS.exe') {
  Write-Mig19a3Trace 'BEFORE_IMPORT'
  Import-Module -Name (Join-Path $Candidate $Variant) -Force -ErrorAction Stop
 }
 $ErrorActionPreference = 'Stop'
 Write-Mig19a3Trace 'AFTER_IMPORT'
 $commands=[ordered]@{}
 foreach ($name in @('Invoke-adPEAS','Connect-adPEAS','Disconnect-adPEAS','Get-adPEASHelp')) {
  $cmd=Get-Command $name -CommandType Function -ErrorAction Stop
  $commands[$name]=@($cmd.Parameters.Keys | Sort-Object)
 }
 Write-Mig19a3Trace 'COMMANDS_OK'
 $helpText=Get-adPEASHelp -Section QuickStart 6>&1 | Out-String
 [IO.File]::WriteAllText(($Evidence+'.help.txt'), $helpText, [Text.Encoding]::UTF8)
 if ($helpText -notmatch 'Быстрый старт' -or $helpText -notmatch 'Дополнительная справка' -or $helpText -match '\bQuick Start\b') {
  throw 'QuickStart runtime localization failed'
 }
 Write-Mig19a3Trace 'HELP_OK'
 $data=[ordered]@{Variant=$Variant;Commands=$commands;RussianQuickStart=$true;Status='PASS';PowerShellVersion=$PSVersionTable.PSVersion.ToString()}
 [IO.File]::WriteAllText($Evidence,($data | ConvertTo-Json -Depth 6),[Text.Encoding]::UTF8)
 Write-Mig19a3Trace 'EVIDENCE_WRITTEN'
 exit 0
}
catch {
 $msg=($_ | Format-List * -Force | Out-String)
 [IO.File]::WriteAllText(($Evidence+'.failure.txt'),$msg,[Text.Encoding]::UTF8)
 Write-Mig19a3Trace 'FAIL'
 [Console]::Error.WriteLine($_.Exception.Message)
 exit 1
}
