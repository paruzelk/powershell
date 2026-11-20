#requires -Version 5.1
# ARCH3x1: exactly one real test POP3 batch-10 through original MailMover.
# Plan/Status offline; Audit original full content read only; Move explicitly
# authorized and permanently fenced. No Archive/Resume/Auto/Index writer.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit','Move','Status')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$SealSha256='',
    [string]$ManifestSha256='',
    [string]$JournalSha256='',
    [string]$ExpectedPreflightDigest='',
    [switch]$ConfirmTenRealMoves
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3x1 requires native Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1')
$argsHash=@{
    Mode=$Mode;RunId=$RunId
    SealSha256=$SealSha256;ManifestSha256=$ManifestSha256;JournalSha256=$JournalSha256
    ExpectedPreflightDigest=$ExpectedPreflightDigest
    ConfirmTenRealMoves=$ConfirmTenRealMoves.IsPresent
    WhatIf=[bool]$WhatIfPreference;Confirm=$false
}
Invoke-OPA265ARCH3x1RealTen @argsHash
