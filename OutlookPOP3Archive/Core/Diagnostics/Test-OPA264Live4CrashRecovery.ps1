#requires -Version 5.1
# LIVE4 independent test-only Outlook recovery observation. Strictly read-only.
# Never retries Worker, clears claims, removes PSTs or completes journal.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if(-not $Review){throw 'LIVE4 recovery observation requires -Review.'}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'LIVE4 read-only recovery requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live4CrashProtocol.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$req=Read-OPAWorkerJson -Path $paths.RequestPath
if(-not [string]::Equals([string]$req.SourcePst,[string]$paths.SourcePst,
    [StringComparison]::OrdinalIgnoreCase)){
    throw 'LIVE4 recovery source PST disagrees with request.'
}
$paths=Assert-OPA264Live3Request -Request $req
[void](Assert-OPA264Live3Intent -Request $req -Paths $paths)
$crashPaths=Get-OPA264Live4Paths -FixturePaths $paths
if(-not [IO.File]::Exists($crashPaths.CrashBarrier) -or
   -not [IO.File]::Exists($crashPaths.ControllerResult)){
    throw 'LIVE4 crash evidence incomplete; leave operation unresolved.'
}
$report=Read-OPAWorkerJson -Path $crashPaths.ControllerResult
$barrier=Read-OPAWorkerJson -Path $crashPaths.CrashBarrier
$window=[string]$report.ControlledCrashWindow
[void](Assert-OPA264Live4Mode -Name $window)
[void](Assert-OPA264Live4Barrier -Record $barrier -Request $req -Window $window -ExpectedWorkerPid ([int]$report.WorkerProcessId))
[void](Assert-OPA264Live4Claim -Path $crashPaths.DispatchClaim -OperationId ([string]$req.OperationId))
if([string]$report.Schema -cne '2.6.4-LIVE4.ControllerResult.1' -or
   [string]$report.Status -cne 'ControlledCrashObserved' -or
   [string]$report.RunId -cne [string]$req.RunId -or
   [string]$report.OperationId -cne [string]$req.OperationId -or
   -not [bool]$report.WorkerStarted -or
   -not [bool]$report.WorkerKilledByOwningController -or
   [bool]$report.AutomaticRetryAllowed -or
   [bool]$report.JournalCompleted -or
   -not [bool]$report.RequiresIndependentReconciliation){
    throw 'LIVE4 controller crash report is not independently trustworthy.'
}
# Fresh Outlook COM read of ONLY the exact synthetic source/target folders.
$snapshot=& (Join-Path $PSScriptRoot 'Test-OPA264Live3SyntheticMove.ps1') -RunId $paths.RunId -SourcePst $paths.SourcePst -Review
$claim=[IO.File]::Exists($paths.ClaimPath)
$response=[IO.File]::Exists($paths.ResponsePath)
$status='IndeterminateNeedsManualReview'
if($window -ceq 'WorkerStartedBeforeMove' -and -not $claim -and
   -not $response -and
   [string]$snapshot.Status -ceq 'SyntheticReadyForOneShotMove' -and
   [int]$snapshot.SourceItemCount -eq 1 -and
   [int]$snapshot.ArchiveItemCount -eq 0 -and
   [int]$snapshot.SyntheticSourceMatches -eq 1 -and
   [int]$snapshot.SyntheticArchiveMatches -eq 0){
    $status='PreMoveCrashNoMoveObserved'
}
if($window -ceq 'AfterMoveBeforeResponse' -and $claim -and
   -not $response -and
   [string]$snapshot.Status -ceq 'SyntheticMoveObserved' -and
   [int]$snapshot.SourceItemCount -eq 0 -and
   [int]$snapshot.ArchiveItemCount -eq 1 -and
   [int]$snapshot.SyntheticSourceMatches -eq 0 -and
   [int]$snapshot.SyntheticArchiveMatches -eq 1){
    [void](Assert-OPA264Live4Claim -Path $paths.ClaimPath -OperationId ([string]$req.OperationId))
    $status='PostMoveCrashMoveObserved'
}
Write-Output ([pscustomobject]@{
    Schema='2.6.4-LIVE4.RecoverySnapshot.1'
    RunId=$paths.RunId
    OperationId=[string]$req.OperationId
    CrashWindow=$window
    Status=$status
    SourceItemCount=[int]$snapshot.SourceItemCount
    ArchiveItemCount=[int]$snapshot.ArchiveItemCount
    SyntheticSourceMatches=[int]$snapshot.SyntheticSourceMatches
    SyntheticArchiveMatches=[int]$snapshot.SyntheticArchiveMatches
    ControllerDispatchClaimExists=$true
    MoveAttemptClaimExists=[bool]$claim
    WorkerResponseExists=[bool]$response
    WorkerKilledByOwningController=$true
    OutlookExaminedOnlySyntheticFolders=$true
    MoveExecutedByThisInspection=$false
    JournalCompleted=$false
    AutomaticRetryAllowed=$false
    RequiresIndependentReconciliation=$true
    ProductionReady=$false
})
