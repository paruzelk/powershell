#requires -Version 5.1
# ARCH3n strict original ARCH3j real Intent <=> ARCH3m synthetic Part2 bridge.
# Plan reads only original protected evidence/PST inventory. Audit also reads Outlook.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Audit')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$IntentSha256,
    [Parameter(Mandatory=$true)][string]$JournalSha256
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3n requires Windows PowerShell 5.1.'
}
if($Mode -ceq 'Audit' -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH3n Audit requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3nPinnedRealIntentBridge.ps1')
Invoke-OPA265ARCH3nReadOnly -Mode $Mode -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
