#requires -Version 5.1
# ARCH3p: independent REAL Outlook postrestart ORIGINAL ArchiveVerifier.
# No Move, PST changes, original OperationJournal reconciliation or Index writes.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Review','Status')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$IntentSha256,
    [Parameter(Mandatory=$true)][string]$JournalSha256,
    [string]$ExpectedMoveClaimSha256=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'ARCH3p requires Windows PowerShell 5.1.'}
if($Mode -ceq 'Review' -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){throw 'ARCH3p real Outlook Review requires Windows PowerShell 5.1 -STA.'}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3pIndependentPostRestartOriginalVerifier.ps1')
Invoke-OPA265ARCH3pPostRestart -Mode $Mode -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256 -ExpectedMoveClaimSha256 $ExpectedMoveClaimSha256
