#requires -Version 5.1
# ARCH2c4 explicit, single-attempt REAL POP3 pilot entrypoint.
# Archive/Resume/Auto of OutlookPOP3Archive.ps1 stay hard blocked.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Inventory','Prepare','Move','Reconcile')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$SourceEntryId='',
    [string]$ManifestSha256='',
    [string]$ClaimSha256='',
    [switch]$ConfirmOneShotPreparation,
    [switch]$ConfirmOneShotMove,
    [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH2c4 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH2c4OneShotCore.ps1')
Invoke-OPA265ARCH2c4OneShot @PSBoundParameters
