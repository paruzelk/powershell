#requires -Version 5.1
# ARCH3w1 exact sealed ARCH3v 10 real test POP3 original journal Intent ONLY.
# Plan/Audit read only; Prepare requires externally pinned digest and permits
# protected LOCALAPPDATA evidence-only original OperationJournal writes after original Part2 archive full semantic proof, without raw Part2 PST binary SHA as a permit.
# Review independent: no Outlook, PST, Move, claim or shared index writer.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit','Prepare','Review')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$SealSha256='',
    [string]$ExpectedAuditSha256='',
    [string]$ExpectedPreviewSha256='',
    [string]$ExpectedOriginalIndexSha256='',
    [string]$ExpectedPrepareDigest='',
    [string]$ManifestSha256='',
    [string]$JournalSha256='',
    [switch]$ConfirmPrepareIntent
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3w1 requires Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3w1SemanticPart2Intents.ps1')
$parameters=@{
    Mode=$Mode;RunId=$RunId;SealSha256=$SealSha256
    ExpectedAuditSha256=$ExpectedAuditSha256
    ExpectedPreviewSha256=$ExpectedPreviewSha256
    ExpectedOriginalIndexSha256=$ExpectedOriginalIndexSha256
    ExpectedPrepareDigest=$ExpectedPrepareDigest
    ManifestSha256=$ManifestSha256
    JournalSha256=$JournalSha256
    ConfirmPrepareIntent=$ConfirmPrepareIntent.IsPresent
    Confirm=$false
}
Invoke-OPA265ARCH3w1TenOriginalIntent @parameters
