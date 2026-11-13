#requires -Version 5.1
# ARCH3i: original complete semantic witness sealed to protected LOCALAPPDATA.
# Seal writes ONLY immutable evidence, never PST, Journal, DuplicateIndex or Move.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Plan','Seal','Review')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$SourcePst,
    [string]$SourceEntryId,
    [ValidateRange(1900,2100)][int]$ArchiveYear=2020,
    [string]$ExpectedSourceFolderEntryId,
    [string]$ExpectedStoreIdSha256,
    [long]$ExpectedSourcePstLengthBytes,
    [long]$ExpectedExistingArchiveLengthBytes,
    [ValidateRange(0,256)][int]$ExpectedAttachmentCount,
    [datetime]$ExpectedArchiveDate,
    [string]$ExpectedOriginalWitnessSha256,
    [string]$SealSha256,
    [switch]$ConfirmEvidenceWrite
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'ARCH3i requires Windows PowerShell 5.1.'}
if($Mode -ceq 'Seal' -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){throw 'ARCH3i Seal requires -STA.'}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3iSealedFullOriginalWitness.ps1')
$pass=@{
    Mode=$Mode;RunId=$RunId;SourcePst=$SourcePst;SourceEntryId=$SourceEntryId
    ArchiveYear=$ArchiveYear;ExpectedSourceFolderEntryId=$ExpectedSourceFolderEntryId
    ExpectedStoreIdSha256=$ExpectedStoreIdSha256
    ExpectedSourcePstLengthBytes=$ExpectedSourcePstLengthBytes
    ExpectedExistingArchiveLengthBytes=$ExpectedExistingArchiveLengthBytes
    ExpectedAttachmentCount=$ExpectedAttachmentCount
    ExpectedArchiveDate=$ExpectedArchiveDate
    ExpectedOriginalWitnessSha256=$ExpectedOriginalWitnessSha256
    SealSha256=$SealSha256
    ConfirmEvidenceWrite=$ConfirmEvidenceWrite.IsPresent
    WhatIf=$WhatIfPreference
    Confirm=$false
}
Invoke-OPA265ARCH3iFullWitnessSeal @pass
