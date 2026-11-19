#requires -Version 5.1
# ARCH3t ONLY: synthetic OS TEMP original DuplicateIndex recovery, not Outlook.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Audit','Recover')][string]$Mode='Audit',
    [Parameter(Mandatory=$true)][string]$Workspace,
    [string]$ExpectedJournalSha256='',
    [string]$ExpectedIndexSha256='',
    [switch]$ConfirmSyntheticRecovery
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3t requires Windows PowerShell 5.1; no real Outlook is contacted.'
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH3tSyntheticIndexOnlyRecovery.ps1')
$call=@{Mode=$Mode;Workspace=$Workspace;ExpectedJournalSha256=$ExpectedJournalSha256;ExpectedIndexSha256=$ExpectedIndexSha256;ConfirmSyntheticRecovery=$ConfirmSyntheticRecovery}
if($WhatIfPreference){$call.WhatIf=$true}
if($PSBoundParameters.ContainsKey('Confirm')){$call.Confirm=$PSBoundParameters['Confirm']}
Invoke-OPA265ARCH3tIndexOnlyRecovery @call
