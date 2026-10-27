#requires -Version 5.1
# BW3h: strictly read-only independent chain audit. No -Execute/-Record.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if (-not $Review -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW3h requires explicit -Review on native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3eSyntheticBodyTailEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3gManualSizeAcceptance265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3hIndependentEvidenceChain265.ps1')
$pinned=Get-OPA265BW3hPinnedChain
[void](Assert-OPA265BW3hPinnedIdentity -Pinned $pinned)
if ($RunId -cne [string]$pinned.RunId -or
    $SourcePst -cne [string]$pinned.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$pinned.JournalSha256) {
    throw 'BW3h refuses every RunId/PST/journal outside the pinned synthetic evidence set.'
}
$stage='Verify original evidence and 7 pinned file hashes before COM'
try {
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $acceptancePath=Get-OPA265BW3gRecordPath -Paths $paths
    $before=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $pinned
    $stage='Rerun BW3g1 read-only Review (which reruns BW3f/BW3e/BW3d/BW3b)'
    $previous=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW3gManualSizeAcceptance.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
    $stage='Validate exact historical verified BW3g1 Review result'
    [void](Assert-OPA265BW3hPreviousAcceptanceReview -Review $previous -Pinned $pinned -ExactRecordPath $acceptancePath)
    $stage='Recheck seven original durable hashes after read-only Outlook inspection'
    $after=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $pinned
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $before -After $after -Pinned $pinned)
    $stage='Produce non-authorizing independent read-only evidence chain verdict'
    Write-Output (Get-OPA265BW3hChainVerdict -Review $previous -Pinned $pinned -ExactRecordPath $acceptancePath -Before $before -After $after)
} catch {
    throw ('BW3h STOP at [{0}]: {1}. No journal write, consent rewrite, Move, retry or production use.' -f $stage,[string]$_.Exception.Message)
}
