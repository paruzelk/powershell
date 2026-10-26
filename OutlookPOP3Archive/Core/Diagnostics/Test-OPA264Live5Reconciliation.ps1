#requires -Version 5.1
# LIVE5 independent read-only replay of a previously dispatched LIVE4 RunId.
# No Outlook Move, no Worker, no PST mount/remove, no journal append.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunId,
      [Parameter(Mandatory=$true)][string]$SourcePst,
      [switch]$Review)
$ErrorActionPreference='Stop'
if (-not $Review) { throw 'LIVE5 requires explicit -Review.' }
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'LIVE5 read-only reconciliation requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live5Reconciliation.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$request=Read-OPAWorkerJson -Path $paths.RequestPath
if (-not [string]::Equals([string]$request.SourcePst,[string]$paths.SourcePst,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw 'LIVE5 selected POP3 PST differs from durable request.'
}
$paths=Assert-OPA264Live3Request -Request $request
$journalBefore=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
$journal=Read-OPAOperationJournal -Path $paths.JournalPath
$replay=Assert-OPA264Live5Journal -Request $request -Paths $paths -Journal $journal
$decision=$null
$inspectionError=''
try {
    # LIVE4 independently validates durable claims, barrier, controller,
    # then freshly inspects ONLY exact synthetic source/archive folders.
    $recovery=& (Join-Path $PSScriptRoot 'Test-OPA264Live4CrashRecovery.ps1') -RunId $paths.RunId -SourcePst $paths.SourcePst -Review
    $decision=Get-OPA264Live5Decision -Request $request -Recovery $recovery -JournalReplay $replay
} catch {
    $inspectionError=[string]$_.Exception.Message
}
$journalAfter=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($journalBefore -cne $journalAfter) {
    throw 'LIVE5 journal changed during independent inspection; manual review required.'
}
if ($null -eq $decision) {
    Write-Output ([pscustomobject]@{
        Schema='2.6.4-LIVE5.ReconciliationReview.1'
        RunId=$paths.RunId
        OperationId=[string]$request.OperationId
        Decision='InspectionFailed'
        Error=$inspectionError
        JournalSha256=$journalAfter
        JournalUnchanged=$true
        OutlookMoveExecuted=$false
        JournalCompleted=$false
        JournalReconciled=$false
        AutomaticRetryAllowed=$false
        RequiresManualJournalDecision=$true
        ProductionReady=$false
    })
    return
}
Write-Output ([pscustomobject]@{
    Schema='2.6.4-LIVE5.ReconciliationReview.1'
    RunId=$decision.RunId
    OperationId=$decision.OperationId
    CrashWindow=$decision.CrashWindow
    Decision=$decision.Decision
    SourceItemCount=$decision.SourceItemCount
    ArchiveItemCount=$decision.ArchiveItemCount
    SyntheticSourceMatches=$decision.SyntheticSourceMatches
    SyntheticArchiveMatches=$decision.SyntheticArchiveMatches
    MoveAttemptClaimExists=$decision.MoveAttemptClaimExists
    EvidenceSufficientForClassification=$decision.EvidenceSufficientForClassification
    JournalSha256=$journalAfter
    JournalUnchanged=$true
    OutlookMoveExecuted=$false
    JournalCompleted=$false
    JournalReconciled=$false
    AutomaticRetryAllowed=$false
    RequiresManualJournalDecision=$true
    ProductionReady=$false
})
