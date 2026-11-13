#requires -Version 5.1
# ARCH3h exact real POP3 Inbox original semantic witness; never Move/Save/Delete.
[CmdletBinding()]
param(
  [ValidateSet('Plan','Witness')][string]$Mode='Plan',
  [Parameter(Mandatory=$true)][string]$SourcePst,
  [Parameter(Mandatory=$true)][string]$SourceEntryId,
  [Parameter(Mandatory=$true)][ValidateRange(1900,2100)][int]$ArchiveYear,
  [Parameter(Mandatory=$true)][string]$ExpectedSourceFolderEntryId,
  [Parameter(Mandatory=$true)][string]$ExpectedStoreIdSha256,
  [Parameter(Mandatory=$true)][long]$ExpectedSourcePstLengthBytes,
  [Parameter(Mandatory=$true)][long]$ExpectedExistingArchiveLengthBytes,
  [Parameter(Mandatory=$true)][ValidateRange(0,256)][int]$ExpectedAttachmentCount,
  [Parameter(Mandatory=$true)][datetime]$ExpectedArchiveDate
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'ARCH3h requires Windows PowerShell 5.1.'}
if($Mode -ceq 'Witness' -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){throw 'ARCH3h Witness requires -STA.'}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3hRealSourceSemanticWitnessGate.ps1')
Invoke-OPA265ARCH3hPinnedSemanticWitness -Mode $Mode -SourcePst $SourcePst -SourceEntryId $SourceEntryId -ArchiveYear $ArchiveYear -ExpectedSourceFolderEntryId $ExpectedSourceFolderEntryId -ExpectedStoreIdSha256 $ExpectedStoreIdSha256 -ExpectedSourcePstLengthBytes $ExpectedSourcePstLengthBytes -ExpectedExistingArchiveLengthBytes $ExpectedExistingArchiveLengthBytes -ExpectedAttachmentCount $ExpectedAttachmentCount -ExpectedArchiveDate $ExpectedArchiveDate
