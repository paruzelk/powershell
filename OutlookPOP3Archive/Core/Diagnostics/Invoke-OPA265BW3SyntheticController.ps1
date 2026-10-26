#requires -Version 5.1
# BW3 standalone DEV synthetic-only controller; NOT production Archive/Resume.
# -Review is filesystem-only. -Execute is ONE explicitly approved Move attempt.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedJournalSha256='',
    [switch]$Review,
    [switch]$Execute,
    [switch]$ConfirmBW3SyntheticMove,
    [ValidateRange(1,30)][int]$TimeoutSeconds=15,
    [switch]$KeepArtifacts
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW3 requires native Windows PowerShell 5.1 STA.'
}
if ($Review -eq $Execute -or
    ($Review -and ($ConfirmBW3SyntheticMove -or $PSBoundParameters.ContainsKey('TimeoutSeconds') -or $KeepArtifacts)) -or
    ($Execute -and -not $ConfirmBW3SyntheticMove) -or
    ($Execute -and $ExpectedJournalSha256 -cnotmatch '^[a-f0-9]{64}$')) {
    throw 'BW3 requires exclusive -Review OR -Execute -ConfirmBW3SyntheticMove -ExpectedJournalSha256 <64 lowercase hex>.'
}
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
$pre=Get-OPA265BW3Preflight -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256
if ($Review) {
    Write-Output ([pscustomobject]@{
        Schema='2.6.5-BW3.ReadOnlyPreflight.1'
        Status='FreshFixtureIntentValidated'
        RunId=[string]$pre.RunId
        OperationId=[string]$pre.OperationId
        JournalSha256=[string]$pre.JournalSha256
        IntentSizeBytes=[long]$pre.IntentSizeBytes
        NextAction='IndependentReadOnlyFixtureReviewBeforeOneShotExecute'
        OutlookComAccessExecuted=$false
        WorkerProcessStarted=$false
        DispatchClaimCreated=$false
        MoveAttemptClaimCreated=$false
        OutlookMoveExecuted=$false
        JournalChanged=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    })
    return
}
# No further COM or PST work by controller. Durable claim MUST precede launch.
. (Join-Path $PSScriptRoot '../Worker/WorkerHost.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerControl.ps1')
$workerRequestId=[guid]::NewGuid().ToString('D')
$payload=[pscustomobject]@{
    Schema='2.6.5-BW3.SyntheticOneShot.1'
    ExecutionPurpose='OperatorApprovedSingleSyntheticMove'
    RunId=[string]$pre.RunId
    SourcePst=[string]$pre.SourcePst
    OperationId=[string]$pre.OperationId
    JournalSha256=[string]$pre.JournalSha256
    WorkerRequestId=$workerRequestId
}
[void](Assert-OPA265BW3Payload -Payload $payload)
[void](Write-OPA265BW3DurableDispatchClaim -Preflight $pre -RequestId $workerRequestId)
# Absolutely no retry: the presence of the claim blocks all subsequent calls.
$outcome=$null;$status='IndeterminateRequiresIndependentReview';$failure='';$pid=0;$destination=''
try {
    $outcome=Invoke-OPAWorkerControlledOperation -Operation 'BW3SyntheticOneShotMove' -Payload $payload -TimeoutSeconds $TimeoutSeconds -KeepArtifacts:$KeepArtifacts -RequestId $workerRequestId
    if ($null -ne $outcome) {$pid=[int]$outcome.WorkerProcessId}
    [void](Assert-OPA265BW3Outcome -Outcome $outcome -Preflight $pre -RequestId $workerRequestId)
    $status='MoveReturnedNeedsIndependentReview'
    $destination=[string]$outcome.Response.Result.DestinationEntryId
} catch {
    $failure=[string]$_.Exception.Message
}
# Claim is authoritative regardless of whether child started, failed or timed out.
# Both statuses still demand an independent fresh read-only Outlook inspection.
$report=[pscustomobject]@{
    Schema='2.6.5-BW3.ControllerResult.1'
    Status=$status
    RunId=[string]$pre.RunId
    OperationId=[string]$pre.OperationId
    WorkerRequestId=$workerRequestId
    WorkerProcessId=$pid
    WorkerStatus=$(if($null -eq $outcome){'Unknown'}else{[string]$outcome.Status})
    FailureKind=$(if($null -eq $outcome){'DispatcherException'}else{[string]$outcome.FailureKind})
    Error=$failure
    DestinationEntryId=$destination
    JournalSha256=[string]$pre.JournalSha256
    DispatchClaimExists=[IO.File]::Exists($pre.Extra.DispatchClaimPath)
    MoveAttemptClaimExists=[IO.File]::Exists($pre.Paths.ClaimPath)
    WorkerMoveMayHaveExecuted=$true
    JournalCompleted=$false
    AutomaticRetryAllowed=$false
    RequiresIndependentReconciliation=$true
    ProductionReady=$false
    NextAction='StopAndPerformIndependentReadOnlyReview'
}
$bytes=(New-Object Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $report -Depth 5))
$fs=$null
try {
    $fs=[IO.FileStream]::new($pre.Extra.ControllerResultPath,
        [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $fs.Write($bytes,0,$bytes.Length)
    $fs.Flush($true)
} finally {if($null -ne $fs){$fs.Dispose()}}
Write-Output $report
if ($status -cne 'MoveReturnedNeedsIndependentReview') {
    throw 'BW3 outcome indeterminate: preserve complete fixture, dispatch/attempt claims and journal; NEVER retry this RunId.'
}
