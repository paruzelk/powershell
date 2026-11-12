#requires -Version 5.1
# ARCH2d4 read-only forensic evaluation of original ARCH2d real batch 10.
# No MailItem.Move/Copy/Save/Delete, no AddStoreEx, no journal/PST writes.
# LiveAudit attaches ONLY existing Outlook; content hashes of attachments
# create ephemeral protected TEMP copies through original ARCH2b/ARCH2c2.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Evidence','LiveAudit')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ManifestSha256='',
    [string]$BatchClaimSha256=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH2d4 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot 'Core/Diagnostics/ARCH2d4LiveAudit.ps1')
Invoke-OPA265ARCH2d4Audit @PSBoundParameters
