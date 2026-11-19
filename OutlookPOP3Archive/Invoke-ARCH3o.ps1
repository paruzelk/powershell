#requires -Version 5.1
# ARCH3o exact ONE user-approved TEST-PST Move via ORIGINAL MailMover.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Plan','Audit','Move','Status')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$IntentSha256,
    [Parameter(Mandatory=$true)][string]$JournalSha256,
    [switch]$ConfirmOneRealMove
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'ARCH3o requires native Windows PowerShell 5.1.'}
if($Mode -cin @('Audit','Move') -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){throw 'ARCH3o Audit/Move require native Windows PowerShell 5.1 STA.'}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3oOneRealOriginalMailMover.ps1')
Invoke-OPA265ARCH3oOneRealPop3Move -Mode $Mode -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256 -ConfirmOneRealMove:$ConfirmOneRealMove -WhatIf:$WhatIfPreference -Confirm:$false
