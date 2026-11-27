#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$ConfirmDevAutoArchive,
    [string]$ExpectedUserSid,
    [switch]$ConfirmDevGpoArchive,
    [string]$ArchiveGroupSid,
    [ValidateRange(0,60)][int]$OutlookWaitMinutes=20,
    [ValidateRange(1,500)][int]$BatchSize=500,
    [ValidateRange(0,100)][int]$AutoDevMaxBatches=1,
    [ValidateRange(1,1200)][int]$OlderThanMonths=12,
    [ValidateSet('Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='YearQuarter',
    [switch]$WhatIf
)
$ErrorActionPreference='Stop'
try{
    . (Join-Path $PSScriptRoot 'Core/Runtime/ARCH7gRds.ps1')
    if(-not $ConfirmDevAutoArchive){throw 'ARCH7g explicit test consent required.'}
    if($ConfirmDevGpoArchive){
        if(-not (Test-OPAARCH7gUserSid -Sid $ArchiveGroupSid) -or $PSBoundParameters.ContainsKey('ExpectedUserSid')){throw 'ARCH8b explicit group SID, no fixed user SID required.'}
        if(-not $PSBoundParameters.ContainsKey('AutoDevMaxBatches')){$AutoDevMaxBatches=0}
    }elseif(-not (Test-OPAARCH7gUserSid -Sid $ExpectedUserSid) -or $AutoDevMaxBatches -eq 0 -or $PSBoundParameters.ContainsKey('ArchiveGroupSid') -or $PSBoundParameters.ContainsKey('OutlookWaitMinutes') -or $PSBoundParameters.ContainsKey('BatchSize')){throw 'ARCH7g explicit expected user SID and bounded scope required.'}
    if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -ne 'STA'){throw 'ARCH7g Windows PowerShell 5.1 STA required.'}
    if($WhatIf){
        if($ConfirmDevGpoArchive){[pscustomobject]@{Schema='2.6.5-ARCH8b.WhatIf.1';Status='NoOutlookOrPersistentWrites';GroupSid=$ArchiveGroupSid;BatchSize=$BatchSize;MaxBatches=$AutoDevMaxBatches;OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping;OutlookWaitMinutes=$OutlookWaitMinutes;Quiet=$true;AllDiscoveredPop3=$true;ProductionReady=$false};exit 0}
        [pscustomobject]@{Schema='2.6.5-ARCH7g.WhatIf.1';Status='NoOutlookOrPersistentWrites';ExpectedUserSid=$ExpectedUserSid;MaxBatches=$AutoDevMaxBatches;OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping;ProductionReady=$false}
        exit 0
    }
    if($ConfirmDevGpoArchive){
        $decision=Wait-OPAARCH8bOutlook -MaxWaitIntervals ($OutlookWaitMinutes*4) -Probe {Get-OPAARCH8bReadyDecision -GroupSid $ArchiveGroupSid} -Delay {Start-Sleep -Seconds 15}
    }else{$decision=Get-OPAARCH7gRuntimeDecision -ExpectedSid $ExpectedUserSid}
    if(-not $decision.MayInvokeAuto){exit $decision.ExitCode}
    # Main rechecks attach-only ROT and holds existing per-user dispatcher
    # mutex plus directory-wide supervisor/worker leases. No external retry.
    $params=@{Mode='Auto';ConfirmDevAutoArchive=$true;Quiet=$true;AutoDevMaxBatches=$AutoDevMaxBatches;OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping}
    if($ConfirmDevGpoArchive){$params.ConfirmDevLongArchive=$true;$params.RdsArchiveGroupSid=$ArchiveGroupSid;$params.Limit=$BatchSize}
    $result=& (Join-Path $PSScriptRoot 'OutlookPOP3Archive.ps1') @params 3>$null 4>$null 5>$null 6>$null
    if($result.ExitCode -isnot [int] -or $result.ExitCode -notin @(0,10,20,30)){exit 30}
    exit $result.ExitCode
}catch{exit 30}
