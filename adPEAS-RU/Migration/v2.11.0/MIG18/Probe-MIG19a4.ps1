param(
 [Parameter(Mandatory=$true)][string]$Candidate,
 [Parameter(Mandatory=$true)][ValidateSet('adPEAS.ps1','adPEAS_min.ps1','adPEAS_ultra.ps1','adPEAS_obf.ps1','adPEAS.exe')][string]$Variant,
 [Parameter(Mandatory=$true)][string]$Evidence,
 [Parameter(Mandatory=$true)][string]$Trace
)
$ErrorActionPreference = 'Stop'
function Write-Mig19a4Trace([string]$Stage) {
 [IO.File]::AppendAllText($Trace, ([DateTime]::UtcNow.ToString('o')+' '+$Stage+[Environment]::NewLine), [Text.Encoding]::UTF8)
}
try {
 Write-Mig19a4Trace 'ENTER'
 if ($Variant -ne 'adPEAS.exe') {
  Write-Mig19a4Trace 'BEFORE_IMPORT'
  Import-Module -Name (Join-Path $Candidate $Variant) -Force -ErrorAction Stop
 }
 $ErrorActionPreference = 'Stop'
 Write-Mig19a4Trace 'AFTER_IMPORT'
 $commands=[ordered]@{}
 foreach ($name in @('Invoke-adPEAS','Connect-adPEAS','Disconnect-adPEAS','Get-adPEASHelp')) {
  $cmd=Get-Command $name -CommandType Function -ErrorAction Stop
  $commands[$name]=@($cmd.Parameters.Keys | Sort-Object)
 }
 Write-Mig19a4Trace 'COMMANDS_OK'
 $scopeWitness=$null
 if ($Variant -eq 'adPEAS.exe') {
  $module=(Get-Command Invoke-adPEAS -CommandType Function -ErrorAction Stop).Module
  if ($null -eq $module -or $module.Name -cne 'adPEAS') { throw 'EXE persistent module not found' }
  foreach ($name in $commands.Keys) {
   if (-not [object]::ReferenceEquals((Get-Command $name -CommandType Function).Module,$module)) { throw "EXE command has different module: $name" }
  }
  $scopeWitness=& $module {
   [ordered]@{
    Version=[string]$Script:adPEASVersion
    PrefixCount=$Script:ClassPrefixes.Count
    InfoPrefix=[string]$Script:ClassPrefixes['Info']
    AnsiCount=$Script:ANSI.Count
    ScanModuleCount=@($Script:adPEASModules).Count
   }
  }
  if ($scopeWitness.Version -cne '2.11.0' -or $scopeWitness.PrefixCount -ne 7 -or $scopeWitness.InfoPrefix -cne '[?] ' -or $scopeWitness.AnsiCount -lt 1 -or $scopeWitness.ScanModuleCount -lt 1) { throw 'EXE script scope witness mismatch' }
  if ((Get-ClassPrefix -Class Info) -cne '[?] ') { throw 'EXE prefix access from caller failed' }
  Write-Mig19a4Trace 'EXE_MODULE_STATE_OK'
 }
 $helpText=Get-adPEASHelp -Section QuickStart 6>&1 | Out-String
 [IO.File]::WriteAllText(($Evidence+'.help.txt'), $helpText, [Text.Encoding]::UTF8)
 if ($helpText -notmatch 'Быстрый старт' -or $helpText -notmatch 'Дополнительная справка' -or $helpText -match '\bQuick Start\b') {
  throw 'QuickStart runtime localization failed'
 }
 Write-Mig19a4Trace 'HELP_OK'
 $data=[ordered]@{Variant=$Variant;Commands=$commands;RussianQuickStart=$true;Status='PASS';PowerShellVersion=$PSVersionTable.PSVersion.ToString();ExeScope=$scopeWitness}
 [IO.File]::WriteAllText($Evidence,($data | ConvertTo-Json -Depth 6),[Text.Encoding]::UTF8)
 Write-Mig19a4Trace 'EVIDENCE_WRITTEN'
 exit 0
}
catch {
 $msg=($_ | Format-List * -Force | Out-String)
 [IO.File]::WriteAllText(($Evidence+'.failure.txt'),$msg,[Text.Encoding]::UTF8)
 Write-Mig19a4Trace 'FAIL'
 [Console]::Error.WriteLine($_.Exception.Message)
 exit 1
}
