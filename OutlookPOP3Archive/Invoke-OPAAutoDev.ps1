#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$ConfirmDevAutoArchive,
    [string]$ProfileName,
    [ValidateRange(1,10)][int]$Limit=10,
    [ValidateRange(1,100)][int]$AutoDevMaxBatches=100,
    [ValidateRange(1,1200)][int]$OlderThanMonths=12,
    [ValidateSet('Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='YearQuarter',
    [ValidateRange(0,300)][int]$AutoBatchDelaySeconds=2,
    [ValidateRange(5,300)][int]$AutoRecoveryDelaySeconds=5,
    [ValidateRange(1,10)][int]$AutoMaxResumeAttempts=3,
    [ValidateRange(1,3650)][int]$AutoLogRetentionDays=30,
    [switch]$WhatIf
)
$ErrorActionPreference='Stop'
try{
    if(-not $ConfirmDevAutoArchive){throw 'ARCH7f explicit all-POP3 test consent required.'}
    $params=@{Mode='Auto';ConfirmDevAutoArchive=$true;Quiet=$true;ProfileName=$ProfileName;Limit=$Limit;AutoDevMaxBatches=$AutoDevMaxBatches;OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping;AutoBatchDelaySeconds=$AutoBatchDelaySeconds;AutoRecoveryDelaySeconds=$AutoRecoveryDelaySeconds;AutoMaxResumeAttempts=$AutoMaxResumeAttempts;AutoLogRetentionDays=$AutoLogRetentionDays;WhatIf=[bool]$WhatIf}
    $result=& (Join-Path $PSScriptRoot 'OutlookPOP3Archive.ps1') @params 3>$null 4>$null 5>$null 6>$null
    if($WhatIf){
        if($result.Status -cne 'NoOutlookOrPersistentWrites'){exit 30}
        $result
        exit 0
    }
    if($result.ExitCode -isnot [int] -or $result.ExitCode -notin @(0,10,20,30)){exit 30}
    exit $result.ExitCode
}catch{exit 30}
