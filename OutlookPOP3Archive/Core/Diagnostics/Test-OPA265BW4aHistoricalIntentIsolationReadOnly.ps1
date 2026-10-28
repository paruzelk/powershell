#requires -Version 5.1
# BW4a stand-alone OPTIONAL read-only Option B quarantine audit, NO Outlook COM.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunId,
      [Parameter(Mandatory=$true)][string]$SourcePst,
      [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
      [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
      [string]$Transaction='',
      [switch]$Review)
$ErrorActionPreference='Stop'
if (-not $Review -or $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4a requires explicit -Review in native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3eSyntheticBodyTailEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3gManualSizeAcceptance265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3hIndependentEvidenceChain265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3iJournalResolutionPreflight265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3jResolutionDesign265.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4aHistoricalIntentIsolation265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4aHistoricalFenceReadOnly265.ps1')
try {
    Write-Output (Invoke-OPA265BW4aHistoricalFenceReview -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode $Mode -Transaction $Transaction)
} catch {
    throw ('BW4a STOP: '+[string]$_.Exception.Message+'. No Worker dispatch, Move, claim, original journal write or automatic retry.')
}
