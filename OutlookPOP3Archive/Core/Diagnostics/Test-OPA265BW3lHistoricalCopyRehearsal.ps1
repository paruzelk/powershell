#requires -Version 5.1
# BW3l: independently review ACTUAL Outlook/claims via BW3j, then append
# a proposed Reconciled event to a FRESH BYTE COPY under OS TEMP ONLY.
# NO -Execute/-Record or writer for the original historical journal exists.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunId,
      [Parameter(Mandatory=$true)][string]$SourcePst,
      [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
      [switch]$RehearseVerifiedCopy)
$ErrorActionPreference='Stop'
if (-not $RehearseVerifiedCopy -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW3l requires explicit -RehearseVerifiedCopy on Windows PowerShell 5.1 STA.'
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
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3lHistoricalCopyRehearsal265.ps1')
$p=Get-OPA265BW3hPinnedChain
[void](Assert-OPA265BW3hPinnedIdentity -Pinned $p)
if ($RunId -cne [string]$p.RunId -or
    $SourcePst -cne [string]$p.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$p.JournalSha256) {
    throw 'BW3l refuses foreign RunId/SourcePst/journal SHA256.'
}
$stage='Read-only historical BW3j independent Outlook review'
try {
    $review=& (Join-Path $PSScriptRoot 'Test-OPA265BW3jResolutionDesignReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
    [void](Assert-OPA265BW3lBw3jReview -Review $review -Pinned $p)
    $stage='Check original one-Intent bytes and seven unmodified evidence files'
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $before=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $p
    $request=Read-OPAWorkerJson -Path $paths.RequestPath
    $null=Assert-OPA265BW3jOriginalIntent -Paths $paths -Request $request -Pinned $p
    if (([IO.File]::GetAttributes([string]$paths.JournalPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3l historical journal is a reparse point.'
    }
    # IMPORTANT: there is NO OPEN/WRITE handle to paths.JournalPath.
    $bytes=[IO.File]::ReadAllBytes([string]$paths.JournalPath)
    $intent=Assert-OPA265BW3lOneIntent -Bytes $bytes -Pinned $p -ExpectedSha256 ([string]$p.JournalSha256)
    if ([string]$intent.ArchivePst -cne [string]$paths.ArchivePst) {
        throw 'BW3l historical archive identity mismatch.'
    }
    $stage='Make a fresh byte-for-byte copy in a bounded OS TEMP sandbox'
    $clone=New-OPA265BW3lCopySandbox -OriginalIntentBytes $bytes -Pinned $p
    if ([string]$clone.Marker.Mode -cne 'ActualHistoricalByteCopy') {
        throw 'BW3l refuses a replica masquerading as actual history.'
    }
    $stage='Rehearse one-shot claim, SHA256-locked append and recovery on COPY ONLY'
    $copy=Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $clone.Paths.Directory -Pinned $p
    if ([string]$copy.Status -cne 'OnlySandboxCopyReconciledHistoricalJournalUntouched' -or
        [string]$copy.CopyMode -cne 'ActualHistoricalByteCopy' -or
        $copy.CopyReconciled -isnot [bool] -or -not $copy.CopyReconciled) {
        throw 'BW3l copy rehearsal did not return the expected isolated result.'
    }
    $stage='Rehash original seven files and revalidate original one-Intent journal'
    $after=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $p
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $before -After $after -Pinned $p)
    $null=Assert-OPA265BW3jOriginalIntent -Paths $paths -Request $request -Pinned $p
    [void](Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $paths -Pinned $p)
    $fresh=[IO.File]::ReadAllBytes([string]$paths.JournalPath)
    if ((Get-OPAOperationJournalSha256 -Bytes $fresh) -cne [string]$p.JournalSha256) {
        throw 'BW3l original historical Intent changed after copy rehearsal.'
    }
    Write-Output ([pscustomobject][ordered]@{
        Schema='2.6.5-BW3l.HistoricalByteCopyRehearsalReadOnlyOriginal.1'
        Status='HistoricalJournalCopyRehearsalVerifiedOriginalUntouched'
        Decision='DoNotWriteHistoricalJournalWithoutNewSeparateExplicitAuthorization'
        RunId=[string]$p.RunId
        OperationId=[string]$p.OperationId
        OriginalIntentSha256=[string]$p.JournalSha256
        AcceptanceRecordSha256=[string]$p.AcceptanceFileSha256
        DestinationEntryId=[string]$p.DestinationEntryId
        SandboxDirectory=[string]$clone.Paths.Directory
        SandboxCopyFinalSha256=[string]$copy.SandboxFinalJournalSha256
        IndependentBW3jReviewPassed=$true
        HistoricalSevenHashesUnchanged=$true
        CopyContainsOriginalExactBytes=$true
        CopyReconciled=$true
        CopyJournalEventCount=2
        CopyDurableClaimCreated=$true
        HistoricalJournalEventCount=1
        HistoricalJournalPhase='Intent'
        HistoricalResolutionClaimCreated=$false
        HistoricalJournalChanged=$false
        HistoricalJournalReconciled=$false
        HistoricalJournalWritePermitIssued=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='ReviewBW3ScopedWriterSecurityAndObtainSeparateExactRunJournalAuthorization'
    })
} catch {
    throw ('BW3l STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. NEVER edit original Intent, PST or claims. No retry of a used copy sandbox.')
}
