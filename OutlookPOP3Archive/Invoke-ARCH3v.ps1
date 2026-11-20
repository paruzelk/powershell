#requires -Version 5.1
# ARCH3v: exactly ten REAL TEST POP3 source original full ARCH2b semantic
# fingerprints only. Plan/Audit no persistence; explicit Seal protected
# LOCALAPPDATA immutable evidence ONLY; Review independent SHA readback.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit','Seal','Review')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$SourcePst='',
    [string]$ExpectedPreviewSha256='',
    [string]$ExpectedSourceStoreIdSha256='',
    [string]$ExpectedOriginalIndexSha256='',
    [long]$ExpectedSourcePstLengthBytes=0,
    [string]$ExpectedAuditSha256='',
    [string]$SealSha256='',
    [switch]$ConfirmEvidenceWrite
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3v requires native Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3vRealTenFullWitness.ps1')
$arguments=@{
    Mode=$Mode;RunId=$RunId;SourcePst=$SourcePst
    ExpectedPreviewSha256=$ExpectedPreviewSha256
    ExpectedSourceStoreIdSha256=$ExpectedSourceStoreIdSha256
    ExpectedOriginalIndexSha256=$ExpectedOriginalIndexSha256
    ExpectedSourcePstLengthBytes=$ExpectedSourcePstLengthBytes
    ExpectedAuditSha256=$ExpectedAuditSha256
    SealSha256=$SealSha256
    ConfirmEvidenceWrite=$ConfirmEvidenceWrite.IsPresent
    Confirm=$false
}
Invoke-OPA265ARCH3vRealTenFullWitness @arguments
