#requires -Version 5.1
# ARCH3x: ten synthetic fake-only original MailMover fences or read-only original Intent review.
# No real Move / PST / index write enabled.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','ReviewPrepared','Synthetic','Inspect')][string]$Mode,
    [string]$RunId='',
    [string]$SealSha256='',
    [string]$ManifestSha256='',
    [string]$JournalSha256='',
    [string]$Workspace='',
    [ValidateSet('None','AfterClaim','AfterInvocation','ProviderThrows','AfterMoveReturned')][string]$Fault='None',
    [ValidateRange(1,10)][int]$FaultAt=4
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3x requires Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3xOriginalBatchTenFence.ps1')
$params=@{
    Mode=$Mode;RunId=$RunId;SealSha256=$SealSha256
    ManifestSha256=$ManifestSha256;JournalSha256=$JournalSha256
    Workspace=$Workspace;Fault=$Fault;FaultAt=$FaultAt
    WhatIf=[bool]$WhatIfPreference;Confirm=$false
}
Invoke-OPA265ARCH3xOriginalBatchFence @params
