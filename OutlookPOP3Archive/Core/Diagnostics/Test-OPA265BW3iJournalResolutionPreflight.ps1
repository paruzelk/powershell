#requires -Version 5.1
# BW3i: only a READ-ONLY preflight of hypothetical journal reconciliation.
# No -Execute, no -Record; never issues a journal write authorization.
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
    throw 'BW3i requires explicit -Review on native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3eSyntheticBodyTailEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3gManualSizeAcceptance265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3hIndependentEvidenceChain265.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live5Reconciliation.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live6JournalResolution.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3iJournalResolutionPreflight265.ps1')
$pinned=Get-OPA265BW3iPinnedScope
[void](Assert-OPA265BW3hPinnedIdentity -Pinned $pinned)
if ($RunId -cne [string]$pinned.RunId -or
    $SourcePst -cne [string]$pinned.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$pinned.JournalSha256) {
    throw 'BW3i is strictly bound to one historic RunId/PST/Intent SHA256.'
}
$stage='Validate scope and absence of existing resolution claim'
try {
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $acceptancePath=Get-OPA265BW3gRecordPath -Paths $paths
    [void](Assert-OPA265BW3iResolutionClaimAbsent -Paths $paths)
    $before=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $pinned
    $stage='Read-only validation of exact journal bytes, one Intent and LIVE6 claim absence'
    $request=Read-OPAWorkerJson -Path $paths.RequestPath
    $preflight=Assert-OPA265BW3iIntentAppendPreconditions -Paths $paths -Request $request -Pinned $pinned
    $stage='Rerun BW3h independent read-only Outlook audit'
    $bw3h=& (Join-Path $PSScriptRoot 'Test-OPA265BW3hIndependentEvidenceChain.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
    [void](Assert-OPA265BW3iBw3hVerdict -Verdict $bw3h -Pinned $pinned -RecordPath $acceptancePath)
    $stage='Rerun legacy LIVE6 -Review ONLY (NEVER -Execute)'
    # The legacy capability flag is NOT consent, does NOT grant a permit,
    # and must never be used as authority to append a journal record.
    $live6=& (Join-Path $PSScriptRoot 'Invoke-OPA264Live6JournalResolution.ps1') -RunId $RunId -SourcePst $SourcePst -Review
    [void](Assert-OPA265BW3iLive6Review -Review $live6 -Pinned $pinned)
    $stage='Recheck original journal, resolution claim absence and seven immutable hashes'
    $after=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $pinned
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $before -After $after -Pinned $pinned)
    $preflightAfter=Assert-OPA265BW3iIntentAppendPreconditions -Paths $paths -Request $request -Pinned $pinned
    if ([string]$preflightAfter.JournalSha256 -cne [string]$preflight.JournalSha256) {
        throw 'BW3i journal bytes changed after read-only protocol inspection.'
    }
    $stage='Return in-memory, nonauthorizing journal decision dossier'
    Write-Output (Get-OPA265BW3iDecisionDossier -Pinned $pinned -Bw3h $bw3h -Live6Review $live6 -JournalPreflight $preflightAfter -SnapshotBefore $before -SnapshotAfter $after -ExactRecordPath $acceptancePath)
} catch {
    throw ('BW3i STOP at [{0}]: {1}. No Reconciled append, claim write, Move or automatic retry.' -f $stage,[string]$_.Exception.Message)
}
