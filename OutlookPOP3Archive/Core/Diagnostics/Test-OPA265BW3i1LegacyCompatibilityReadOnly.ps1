#requires -Version 5.1
# BW3i1: read-only, fail-closed explanation of old LIVE6 mismatch with BW3a.
# Never dispatches Worker, invokes LIVE6 -Execute, mutates journal or PST.
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
    throw 'BW3i1 requires explicit -Review on Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3eSyntheticBodyTailEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3gManualSizeAcceptance265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3hIndependentEvidenceChain265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3iJournalResolutionPreflight265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3i1LegacyCompatibility265.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live4CrashProtocol.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live5Reconciliation.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live6JournalResolution.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
$pinned=Get-OPA265BW3iPinnedScope
[void](Assert-OPA265BW3hPinnedIdentity -Pinned $pinned)
if ($RunId -cne [string]$pinned.RunId -or
    $SourcePst -cne [string]$pinned.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$pinned.JournalSha256) {
    throw 'BW3i1 refuses every RunId/PST/journal outside original BW3a evidence.'
}
$stage='Check original LIVE4 barrier/claim/result absence and original seven SHA256s'
try {
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $recordPath=Get-OPA265BW3gRecordPath -Paths $paths
    [void](Assert-OPA265BW3i1LegacyCrashArtifactsAbsent -Paths $paths)
    [void](Assert-OPA265BW3iResolutionClaimAbsent -Paths $paths)
    $before=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $pinned
    $request=Read-OPAWorkerJson -Path $paths.RequestPath
    $preflight=Assert-OPA265BW3iIntentAppendPreconditions -Paths $paths -Request $request -Pinned $pinned
    $stage='Re-run independent BW3h read-only actual Outlook and evidence audit'
    $bw3h=& (Join-Path $PSScriptRoot 'Test-OPA265BW3hIndependentEvidenceChain.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
    [void](Assert-OPA265BW3iBw3hVerdict -Verdict $bw3h -Pinned $pinned -RecordPath $recordPath)
    $stage='Inspect original LIVE6 Review-only result; DO NOT CALL -Execute'
    $legacyReview=& (Join-Path $PSScriptRoot 'Invoke-OPA264Live6JournalResolution.ps1') -RunId $RunId -SourcePst $SourcePst -Review
    [void](Assert-OPA265BW3i1InapplicableLive6Review -Review $legacyReview -Pinned $pinned)
    $stage='Verify seven immutable hashes, original Intent and absent LIVE4/LIVE6 claims after audit'
    $after=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $pinned
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $before -After $after -Pinned $pinned)
    [void](Assert-OPA265BW3i1LegacyCrashArtifactsAbsent -Paths $paths)
    $post=Assert-OPA265BW3iIntentAppendPreconditions -Paths $paths -Request $request -Pinned $pinned
    if ([string]$post.JournalSha256 -cne [string]$preflight.JournalSha256) {
        throw 'BW3i1 original journal bytes changed.'
    }
    $stage='Return read-only BLOCKED legacy executor compatibility classification'
    Write-Output (Get-OPA265BW3i1LegacyCompatibilityDossier -Pinned $pinned -Bw3h $bw3h -LegacyReview $legacyReview -JournalPreflight $post -SnapshotBefore $before -SnapshotAfter $after -RecordPath $recordPath)
} catch {
    throw ('BW3i1 STOP at [{0}]: {1}. Legacy LIVE6 is not approved; no Move, journal write, claim changes or retry.' -f $stage,[string]$_.Exception.Message)
}
