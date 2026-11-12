#requires -Version 5.1
# ARCH2d5: one real POP3 Inbox pilot with EXACTLY 100 operator-pinned
# originals and a cryptographically linked final receipt seal. New target
# PST only. Previous ARCH2c4/ARCH2d runs never modified or replayed.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Plan','Inventory','Prepare','MoveBatch','Evidence','Reconcile')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string[]]$SourceEntryIds=@(),
    [string]$ManifestSha256='',
    [string]$BatchClaimSha256='',
    [string]$FinalSealSha256='',
    [switch]$ConfirmBatchPreparation,
    [switch]$ConfirmBatchMove,
    [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH2d5 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH2d5Batch100Core.ps1')
Invoke-OPA265ARCH2d5Pilot @PSBoundParameters
