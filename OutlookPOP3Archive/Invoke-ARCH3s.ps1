#requires -Version 5.1
# ARCH3s: ORIGINAL ArchiveVerifier for ten synthetic Outlook MailItems;
# full ORIGINAL ARCH2b attachment SaveAsFile/SHA, TEMP-only journal/index.
# REAL MailItem.Move, PST modification and production writer are CLOSED.
[CmdletBinding()]
param(
    [ValidateSet('VerifierOnly','Integration')][string]$Mode='VerifierOnly',
    [ValidateSet('None','SourceStillPresent','DestinationMissing','ExtraDestination',
      'HtmlDrift','BodyDrift','RecipientDrift','AttachmentDrift','MissingOriginalWitness',
      'DuplicateSourceSelector','DuplicateArchiveSelector','WrongTargetFolder',
      'StaleArchiveIdUnique','StaleArchiveIdAmbiguous')][string]$VerifierFault='None',
    [ValidateSet('None','AfterJournalReconciled','AfterIndexAppend')][string]$JournalFault='None',
    [ValidateRange(1,10)][int]$FaultAt=4,
    [string]$SyntheticTempRoot=[IO.Path]::GetTempPath()
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3s requires Windows PowerShell 5.1. No real Outlook COM used.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3sTenOriginalVerifierIntegration.ps1')
$params=@{Mode=$Mode;VerifierFault=$VerifierFault;JournalFault=$JournalFault;FaultAt=$FaultAt;SyntheticTempRoot=$SyntheticTempRoot}
Invoke-OPA265ARCH3sTen @params
