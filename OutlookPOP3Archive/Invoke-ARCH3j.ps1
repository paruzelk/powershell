#requires -Version 5.1
# ARCH3j: REAL test PST, only Plan/Audit/Prepare/Review. Absolutely NO Move.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Plan','Audit','Prepare','Review')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$SealRunId,
    [string]$SealSha256,
    [string]$IntentSha256,
    [string]$JournalSha256,
    [switch]$ConfirmPrepareIntent
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'ARCH3j requires Windows PowerShell 5.1.'}
if($Mode -cin @('Audit','Prepare') -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){throw 'ARCH3j Audit/Prepare require -STA.'}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3jRealOneShotPrepareIntent.ps1')
if($Mode -ceq 'Review'){
    Invoke-OPA265ARCH3jRealOneShotPrepare -Mode Review -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
}else{
    Invoke-OPA265ARCH3jRealOneShotPrepare -Mode $Mode -RunId $RunId -SealRunId $SealRunId -SealSha256 $SealSha256 -ConfirmPrepareIntent:$ConfirmPrepareIntent -WhatIf:$WhatIfPreference -Confirm:$false
}
