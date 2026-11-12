#requires -Version 5.1
# ARCH2d: separate real POP3 Inbox batch pilot, exactly TEN letters, no
# production Archive/Resume/Auto. No reuse of old ARCH2c4a irreversible claim.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Inventory','Prepare','MoveBatch','Reconcile')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string[]]$SourceEntryIds=@(),
    [string]$ManifestSha256='',
    [string]$BatchClaimSha256='',
    [switch]$ConfirmBatchPreparation,
    [switch]$ConfirmBatchMove,
    [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH2d requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH2dBatchCore.ps1')
Invoke-OPA265ARCH2dBatch @PSBoundParameters
