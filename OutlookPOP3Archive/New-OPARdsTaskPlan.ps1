#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$ConfirmDevAutoArchive,
    [string]$InstallDirectory=$PSScriptRoot,
    [ValidateRange(0,30)][int]$LogonDelayMinutes=2,
    [ValidateRange(1,100)][int]$AutoDevMaxBatches=1,
    [ValidateRange(1,1200)][int]$OlderThanMonths=12,
    [ValidateSet('Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='YearQuarter',
    [string]$DailyAt=''
)
$ErrorActionPreference='Stop'
if(-not $ConfirmDevAutoArchive){throw 'ARCH7g explicit all-POP3 test consent required.'}
. (Join-Path $PSScriptRoot 'Core/Runtime/ARCH7gRds.ps1')
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
try{
    New-OPAARCH7gTaskDefinition -UserSid $identity.User.Value -InstallDirectory $InstallDirectory -WindowsDirectory $env:WINDIR -LogonDelayMinutes $LogonDelayMinutes -MaxBatches $AutoDevMaxBatches -OlderThanMonths $OlderThanMonths -ArchiveGrouping $ArchiveGrouping -DailyAt $DailyAt
}finally{$identity.Dispose()}
