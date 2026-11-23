#requires -Version 5.1
# ARCH3x2 unified: ARCH3x1b Move uses unchanged Invoke-ARCH3x1.ps1;
# new postrestart Review/Seal/Commit/Recover NEVER call MailItem.Move.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Status','Plan','Review','Seal','Commit','Recover')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$SealSha256='',
    [string]$ManifestSha256='',
    [string]$JournalSha256='',
    [string]$ReviewSha256='',
    [switch]$ConfirmReviewSeal,
    [switch]$ConfirmVerifiedCommit,
    [switch]$ConfirmRecovery
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3x2 requires native Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1')
Invoke-OPA265ARCH3x2RealTen -Mode $Mode -RunId $RunId -SealSha256 $SealSha256 -ManifestSha256 $ManifestSha256 -JournalSha256 $JournalSha256 -ReviewSha256 $ReviewSha256 -ConfirmReviewSeal:$ConfirmReviewSeal.IsPresent -ConfirmVerifiedCommit:$ConfirmVerifiedCommit.IsPresent -ConfirmRecovery:$ConfirmRecovery.IsPresent -WhatIf:$WhatIfPreference -Confirm:$false
