#requires -Version 5.1
# ARCH3q: ONLY original real postrestart verified OperationJournal Reconciled
# and append-only original shared DuplicateIndex. No MailItem.Move.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Plan','Seal','Commit','Recover','Status','Review')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$IntentSha256,
    [Parameter(Mandatory=$true)][string]$JournalSha256,
    [string]$ReviewSha256='',
    [string]$CommitClaimSha256='',
    [string]$CommitSealSha256='',
    [switch]$ConfirmSeal,
    [switch]$ConfirmVerifiedCommit,
    [switch]$ConfirmRecovery
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3q requires native Windows PowerShell 5.1.'
}
if($Mode -cin @('Seal','Commit','Recover') -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH3q Seal/Commit/Recover require Windows PowerShell 5.1 -STA.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3qVerifiedJournalIndexCommit.ps1')
$params=@{Mode=$Mode;RunId=$RunId;IntentSha256=$IntentSha256;JournalSha256=$JournalSha256
    ReviewSha256=$ReviewSha256;CommitClaimSha256=$CommitClaimSha256;CommitSealSha256=$CommitSealSha256
    ConfirmSeal=$ConfirmSeal;ConfirmVerifiedCommit=$ConfirmVerifiedCommit;ConfirmRecovery=$ConfirmRecovery
    WhatIf=[bool]$WhatIfPreference;Confirm=$false}
Invoke-OPA265ARCH3qCommit @params
