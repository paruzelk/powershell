#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$ConfirmDevAutoArchive,
    [string]$ExpectedUserSid,
    [ValidateRange(1,100)][int]$AutoDevMaxBatches=1,
    [ValidateRange(1,1200)][int]$OlderThanMonths=12,
    [ValidateSet('Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='YearQuarter',
    [switch]$WhatIf
)
$ErrorActionPreference='Stop'
try{
    . (Join-Path $PSScriptRoot 'Core/Runtime/ARCH7gRds.ps1')
    if(-not $ConfirmDevAutoArchive -or -not (Test-OPAARCH7gUserSid -Sid $ExpectedUserSid)){throw 'ARCH7g explicit test consent and expected user SID required.'}
    if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -ne 'STA'){throw 'ARCH7g Windows PowerShell 5.1 STA required.'}
    if($WhatIf){
        [pscustomobject]@{Schema='2.6.5-ARCH7g.WhatIf.1';Status='NoOutlookOrPersistentWrites';ExpectedUserSid=$ExpectedUserSid;MaxBatches=$AutoDevMaxBatches;OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping;ProductionReady=$false}
        exit 0
    }
    $decision=Get-OPAARCH7gRuntimeDecision -ExpectedSid $ExpectedUserSid
    if(-not $decision.MayInvokeAuto){exit $decision.ExitCode}
    # Main rechecks attach-only ROT and holds existing per-user dispatcher
    # mutex plus directory-wide supervisor/worker leases. No external retry.
    $params=@{Mode='Auto';ConfirmDevAutoArchive=$true;Quiet=$true;AutoDevMaxBatches=$AutoDevMaxBatches;OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping}
    $result=& (Join-Path $PSScriptRoot 'OutlookPOP3Archive.ps1') @params 3>$null 4>$null 5>$null 6>$null
    if($result.ExitCode -isnot [int] -or $result.ExitCode -notin @(0,10,20,30)){exit 30}
    exit $result.ExitCode
}catch{exit 30}
