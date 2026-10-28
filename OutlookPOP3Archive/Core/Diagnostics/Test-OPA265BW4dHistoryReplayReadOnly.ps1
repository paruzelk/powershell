#requires -Version 5.1
# BW4d: two independent read-only evidence channels: Outlook item and sealed journal files.
# Existing historical BW3a Intent remains immutable; no Move or replay is authorized.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
    [string]$Transaction='',
    [Parameter(Mandatory=$true)][string]$FolderEntryId,
    [Parameter(Mandatory=$true)][string]$CandidateEntryId,
    [Parameter(Mandatory=$true)][string]$ExpectedProfileName,
    [ValidateRange(1,5000)][int]$MaxFolderItems=1000,
    [string]$HistoryRoot=([IO.Path]::GetTempPath()),
    [ValidateRange(1,512)][int]$MaxHistoryRuns=256,
    [switch]$Review,
    [switch]$ConfirmExistingOutlookReadOnly
)
$ErrorActionPreference='Stop'
if (-not $Review -or -not $ConfirmExistingOutlookReadOnly -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4d requires explicit -Review and -ConfirmExistingOutlookReadOnly under native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4dHistoricalReplayAudit265.ps1')
try {
    # First independent read-only snapshot of local Live3/Live4 journal evidence.
    $before=Get-OPA265BW4dHistoryCatalog -HistoryRoot $HistoryRoot -MaxRunDirectories $MaxHistoryRuns
    # Existing BW4c independently hashes the original 7 BW3a files before AND after
    # its controlled COM read of the selected Outlook item, and never calls Move.
    $bw4c=& (Join-Path $PSScriptRoot 'Test-OPA265BW4cOutlookPerItemReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode $Mode -Transaction $Transaction -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -ExpectedProfileName $ExpectedProfileName -MaxFolderItems $MaxFolderItems -Review -ConfirmExistingOutlookReadOnly
    $after=Get-OPA265BW4dHistoryCatalog -HistoryRoot $HistoryRoot -MaxRunDirectories $MaxHistoryRuns
    if ([string]$before.EvidenceSnapshotSha256 -cne [string]$after.EvidenceSnapshotSha256 -or
        $before.RunDirectoriesScanned -ne $after.RunDirectoriesScanned -or
        $before.JournalsScanned -ne $after.JournalsScanned -or
        $before.ClaimOnlyDirectories -ne $after.ClaimOnlyDirectories) {
        throw 'BW4d historical test-run evidence changed during Outlook audit; fail closed.'
    }
    $decision=Get-OPA265BW4dReplayDecision -Bw4cReview $bw4c -History $after
    if ($decision.CanDispatchWorker -or $decision.CanRetryPreviousMove -or
        $decision.CanInvokeMailMove -or $decision.CanWriteHistoricalJournal) {
        throw 'BW4d critical no-Worker/no-Move invariant violated.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4d.IndependentJournalReplayReviewReadOnly.1'
        Status='IndependentReadOnlyJournalAndOutlookEvidenceReviewedNoMovePermit'
        CandidateStatus=$decision.Status
        HistoricalOperationMatches=$decision.HistoricalOperationMatches
        SyntheticLive3Identity=$decision.SyntheticLive3Identity
        CandidateEntryId=[string]$bw4c.CandidateEntryId
        InternetMessageId=[string]$bw4c.InternetMessageId
        SourceStoreId=[string]$bw4c.SourceStoreId
        SourceItemFingerprintSha256=[string]$bw4c.ContentFieldFingerprintSha256
        HistoryRoot=$after.HistoryRoot
        RunDirectoriesScanned=$after.RunDirectoriesScanned
        JournalsScanned=$after.JournalsScanned
        ClaimOnlyDirectories=$after.ClaimOnlyDirectories
        HistoryEvidenceSnapshotSha256=$after.EvidenceSnapshotSha256
        HistoryEvidenceFilesUnchanged=$true
        HistoryCatalogComplete=$false
        IndependentlyAuthenticatedExternalMAPIContent=$false
        ReplaySafetyProven=$false
        SevenHistoricalEvidenceHashesUnchanged=$true
        HistoricJournalEventCount=1
        HistoricJournalPhase='Intent'
        HistoricalJournalChanged=$false
        HistoricalClaimCreated=$false
        WorkerDispatchAllowed=$false
        OutlookComAccessExecuted=$true
        OutlookMoveExecuted=$false
        CanRetryPreviousMove=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='NoMove;FreshIndependentSyntheticEvidenceAndOperatorAuthorizationRequired'
    }
} catch {
    throw ('BW4d STOP (no Move, claim, journal write, automatic retry): '+[string]$_.Exception.Message)
}
