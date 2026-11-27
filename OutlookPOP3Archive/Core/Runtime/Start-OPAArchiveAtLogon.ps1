#requires -Version 5.1
# Read-only group-filtered bootstrap; the shared lease protects managed runs.
$ErrorActionPreference='Stop'
$lease=$null;$identity=$null
try{
    $p=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\OutlookPOP3Archive' -ErrorAction Stop
    if([int]$p.Enabled -ne 1){exit 0}
    if([string]$p.GroupSid -cnotmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or [string]$p.DeploymentId -cnotmatch '^[a-f0-9]{64}$'){exit 30}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=[Security.Principal.WindowsPrincipal]::new($identity)
    if(-not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){exit 30}
    if(-not $principal.IsInRole([Security.Principal.SecurityIdentifier]::new([string]$p.GroupSid))){exit 41}
    $lease=[IO.FileStream]::new((Join-Path $PSScriptRoot 'deployment.lock'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $local=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'deployment.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($local.Schema -cne 'OPA.Domain.Logon.1' -or $local.DeploymentId -cne $p.DeploymentId -or $local.GroupSid -cne $p.GroupSid -or $local.Enabled -ne $true){exit 30}
    if([int]$p.BatchSize -lt 1 -or [int]$p.BatchSize -gt 500 -or [int]$p.MaxBatches -lt 0 -or [int]$p.MaxBatches -gt 100 -or [int]$p.OlderThanMonths -lt 1 -or [int]$p.OlderThanMonths -gt 1200 -or [int]$p.OutlookWaitMinutes -lt 0 -or [int]$p.OutlookWaitMinutes -gt 60 -or [string]$p.ArchiveGrouping -cnotin @('Year','YearQuarter','YearMonth')){exit 30}
    $root=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'OutlookPOP3Archive'
    & (Join-Path $root 'Invoke-OPARdsAutoDev.ps1') -ConfirmDevAutoArchive -ConfirmDevGpoArchive -ArchiveGroupSid ([string]$p.GroupSid) -BatchSize ([int]$p.BatchSize) -AutoDevMaxBatches ([int]$p.MaxBatches) -OlderThanMonths ([int]$p.OlderThanMonths) -OutlookWaitMinutes ([int]$p.OutlookWaitMinutes) -ArchiveGrouping ([string]$p.ArchiveGrouping)
    exit $LASTEXITCODE
}catch{exit 30}
finally{if($lease){$lease.Dispose()};if($identity){$identity.Dispose()}}
