#requires -Version 5.1
# BW3j exact BW3a synthetic read-only journal reconciliation DESIGN preflight.
# It NEVER invokes LIVE4/LIVE5/LIVE6, any writer, Move or Record.
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
    throw 'BW3j requires explicit -Review in native Windows PowerShell 5.1 STA.'
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
$pinned=Get-OPA265BW3hPinnedChain
[void](Assert-OPA265BW3hPinnedIdentity -Pinned $pinned)
if ($RunId -cne [string]$pinned.RunId -or
    $SourcePst -cne [string]$pinned.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$pinned.JournalSha256) {
    throw 'BW3j refuses unpinned RunId, PST or historical journal SHA256.'
}
$stage='Check original exact-run evidence and empty historical resolution claim slots'
try {
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $acceptancePath=Get-OPA265BW3gRecordPath -Paths $paths
    [void](Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $paths -Pinned $pinned)
    $before=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $pinned
    $stage='Read one original Intent envelope, replay it and verify request/claim-slot preconditions'
    $request=Read-OPAWorkerJson -Path $paths.RequestPath
    $first=Assert-OPA265BW3jOriginalIntent -Paths $paths -Request $request -Pinned $pinned
    $stage='Rerun independent actual Outlook BW3h proof chain without any new Move'
    $historical=& (Join-Path $PSScriptRoot 'Test-OPA265BW3hIndependentEvidenceChain.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
    [void](Assert-OPA265BW3iBw3hVerdict -Verdict $historical -Pinned $pinned -RecordPath $acceptancePath)
    $stage='Verify seven evidence hashes and re-read original Intent after Outlook audit'
    $after=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $pinned
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $before -After $after -Pinned $pinned)
    $last=Assert-OPA265BW3jOriginalIntent -Paths $paths -Request $request -Pinned $pinned
    if ([string]$first.JournalSha256 -cne [string]$last.JournalSha256) {
        throw 'BW3j original journal changed during read-only review.'
    }
    $stage='Return in-memory design-only dossier with no journal-write authority'
    Write-Output (Get-OPA265BW3jResolutionDesignDossier -Pinned $pinned -Bw3h $historical -OriginalIntent $last -Before $before -After $after -AcceptanceRecordPath $acceptancePath)
} catch {
    throw ('BW3j STOP at [{0}]: {1}. No journal append, claim creation, Move, PST mutation, or automatic retry.' -f $stage,[string]$_.Exception.Message)
}
