#requires -Version 5.1
# BW3m security review: EXACT historical read-only Outlook audit + TEMP COPY append
# via already tested BW3l. NO original write handle / original claim creation.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunId,
      [Parameter(Mandatory=$true)][string]$SourcePst,
      [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
      [switch]$Review)
$ErrorActionPreference='Stop'
if (-not $Review -or $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW3m requires -Review in native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3eSyntheticBodyTailEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3gManualSizeAcceptance265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3hIndependentEvidenceChain265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3iJournalResolutionPreflight265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3jResolutionDesign265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3lHistoricalCopyRehearsal265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3mHistoricalWriterSafetyReview265.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
$p=Get-OPA265BW3hPinnedChain
[void](Assert-OPA265BW3hPinnedIdentity -Pinned $p)
if ($RunId -cne [string]$p.RunId -or $SourcePst -cne [string]$p.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$p.JournalSha256) {
    throw 'BW3m refuses any foreign RunId, original PST or journal SHA256.'
}
$stage='Snapshot exact seven historical hashes and original one-Intent journal'
try {
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    [void](Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $paths -Pinned $p)
    $before=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $p
    $request=Read-OPAWorkerJson -Path $paths.RequestPath
    $null=Assert-OPA265BW3jOriginalIntent -Paths $paths -Request $request -Pinned $p
    if (([IO.File]::GetAttributes([string]$paths.JournalPath) -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3m refuses original journal reparse point.'
    }
    $original=[IO.File]::ReadAllBytes([string]$paths.JournalPath)
    $intent=Assert-OPA265BW3lOneIntent -Bytes $original -Pinned $p -ExpectedSha256 $p.JournalSha256
    if ([string]$intent.ArchivePst -cne [string]$paths.ArchivePst) {
        throw 'BW3m original archive PST mismatch.'
    }
    $stage='Perform BW3l independent actual Outlook review and one-shot append into NEW TEMP COPY'
    $bw3l=& (Join-Path $PSScriptRoot 'Test-OPA265BW3lHistoricalCopyRehearsal.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -RehearseVerifiedCopy
    [void](Assert-OPA265BW3mBw3lReview -Review $bw3l -Pinned $p)
    $stage='Independently inspect BW3l TEMP copy bytes, claim, terminal envelope, replay'
    $readback=Assert-OPA265BW3mCopyReadback -Review $bw3l -Pinned $p -OriginalBytes $original
    $stage='Rehash original seven historical artifacts and verify original Intent still unresolved'
    $after=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $p
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $before -After $after -Pinned $p)
    $null=Assert-OPA265BW3jOriginalIntent -Paths $paths -Request $request -Pinned $p
    [void](Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $paths -Pinned $p)
    if ((Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes([string]$paths.JournalPath))) -cne
        [string]$p.JournalSha256) {
        throw 'BW3m original Intent hash changed after independent copy audit.'
    }
    $stage='Publish NON-AUTHORIZING historical writer threat review verdict'
    Write-Output (Get-OPA265BW3mSecurityDecision -Pinned $p -Bw3l $bw3l -CopyAudit $readback -EvidenceBefore $before -EvidenceAfter $after)
} catch {
    throw ('BW3m STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No original journal append, original claim, PST write, MailItem.Move or retry.')
}
