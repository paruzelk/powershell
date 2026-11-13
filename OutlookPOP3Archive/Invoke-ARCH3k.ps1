#requires -Version 5.1
# ARCH3k: Plan/Audit original MailMover risk assessment only; no real writer.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Audit')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$IntentSha256,
    [Parameter(Mandatory=$true)][string]$JournalSha256
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'ARCH3k requires Windows PowerShell 5.1.'}
if($Mode -ceq 'Audit' -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){throw 'ARCH3k Audit requires -STA.'}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3kOriginalMoverLiveBarrier.ps1')
Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode $Mode -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
