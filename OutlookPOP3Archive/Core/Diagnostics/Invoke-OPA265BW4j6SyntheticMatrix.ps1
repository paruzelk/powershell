#requires -Version 5.1
# BW4j6 FINAL GATE -- GitHub Actions Windows runner SYNTHETIC ONLY.
# No customer correspondence, Outlook, PST, Send, real MailItem.Move or journal edit.
[CmdletBinding()]
param(
    [switch]$RequireGitHubActions,
    [string]$SandboxParent=$env:RUNNER_TEMP
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'BW4j6 requires native Windows PowerShell 5.1.'
}
if(-not $RequireGitHubActions -or $env:GITHUB_ACTIONS -cne 'true' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   -not [string]::Equals([IO.Path]::GetFullPath($SandboxParent),
     [IO.Path]::GetFullPath($env:RUNNER_TEMP),[StringComparison]::OrdinalIgnoreCase)){
    throw 'BW4j6 matrix restricted to GitHub Actions Windows runner temporary directory.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4j5SyntheticReconcile265.ps1')
function New-OPA265BW4j6Run {
    param([string]$Parent)
    $root=Join-Path $Parent ('OPA265-BW4j6-SYNTH-'+[guid]::NewGuid().ToString('N'))
    New-OPA265BW4j4Sandbox -SandboxRoot $root
}
function Assert-OPA265BW4j6Condition {
    param([bool]$Condition,[string]$Description)
    if(-not $Condition){throw ('BW4j6 SYNTHETIC CI GATE FAILED: '+$Description)}
}
$normal=New-OPA265BW4j6Run -Parent $SandboxParent
$m=Get-OPA265BW4j4Manifest -SandboxRoot $normal.SandboxRoot -ExpectedManifestSha256 $normal.ManifestSha256
$moveResults=New-Object 'System.Collections.Generic.List[object]'
foreach($case in @($m.Plan.Cases)){
    $result=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $normal.SandboxRoot -ExpectedManifestSha256 $normal.ManifestSha256 -TestId $case.TestId -ConfirmIsolatedSyntheticOneShot
    Assert-OPA265BW4j6Condition -Condition ($result.Status -ceq 'SyntheticFileMovedRequiresIndependentReconciliation') -Description 'synthetic per-item one-shot Move return'
    $proof=Get-OPA265BW4j5Reconciliation -SandboxRoot $normal.SandboxRoot -ExpectedManifestSha256 $normal.ManifestSha256 -TestId $case.TestId
    Assert-OPA265BW4j6Condition -Condition ($proof.Status -ceq 'SyntheticMoveConfirmedModelOnlyNoOutlookProof' -and
        $proof.SubjectMatches -and $proof.SenderMatches -and $proof.BodyMatches -and
        $proof.HtmlBodyMatches -and $proof.ReceivedTimeMatches -and $proof.AttachmentsMatch -and
        [long]$proof.SyntheticSizeDelta -eq 38) -Description 'all independent synthetic content SHA and modeled +38 delta'
    $receipt=Write-OPA265BW4j5ReceiptOnce -SandboxRoot $normal.SandboxRoot -ExpectedManifestSha256 $normal.ManifestSha256 -TestId $case.TestId
    $moveResults.Add([pscustomobject][ordered]@{
        TestId=$case.TestId
        CaseName=$case.Name
        ClaimSha256=$result.ClaimSha256
        ReceiptSha256=$receipt.ReceiptSha256
    })
}
$summary=Get-OPA265BW4j5SuiteSummary -SandboxRoot $normal.SandboxRoot -ExpectedManifestSha256 $normal.ManifestSha256
Assert-OPA265BW4j6Condition -Condition ($summary.AllFiveSyntheticItemsReconciled -and
    $summary.IndependentlyReconciled -eq 5 -and $summary.Blocked -eq 0 -and
    $summary.PendingOrUnreconciled -eq 0 -and -not $summary.OutlookUsed -and
    -not $summary.RealPstTouched -and -not $summary.OriginalHistoricalIntentTouched) -Description 'full five-item receipt reconciliation'
$blockedRetry=0
foreach($case in @($m.Plan.Cases)){
    try{
        $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $normal.SandboxRoot -ExpectedManifestSha256 $normal.ManifestSha256 -TestId $case.TestId -ConfirmIsolatedSyntheticOneShot
        throw 'BW4j6 ERROR: duplicate synthetic move somehow succeeded'
    }catch{
        if([string]$_.Exception.Message -like '*NEVER retry*'){$blockedRetry++}else{throw}
    }
}
Assert-OPA265BW4j6Condition -Condition ($blockedRetry -eq 5) -Description 'reject all five repeat attempts'
# CRASH 1: durable claim written, but no synthetic atomic move. Must NEVER retry,
# even if source is still present. Independent state only; manual quarantine.
$afterClaim=New-OPA265BW4j6Run -Parent $SandboxParent
$mClaim=Get-OPA265BW4j4Manifest -SandboxRoot $afterClaim.SandboxRoot -ExpectedManifestSha256 $afterClaim.ManifestSha256
$idClaim=[string]$mClaim.Plan.Cases[0].TestId
$injected1=$false
try {
    $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $afterClaim.SandboxRoot -ExpectedManifestSha256 $afterClaim.ManifestSha256 -TestId $idClaim -ConfirmIsolatedSyntheticOneShot -CrashPoint AfterClaim
}catch{if([string]$_.Exception.Message -like '*INJECTED CRASH after durable claim*'){$injected1=$true}else{throw}}
Assert-OPA265BW4j6Condition -Condition $injected1 -Description 'claim-only crash injected'
$state1=Get-OPA265BW4j4State -SandboxRoot $afterClaim.SandboxRoot -ExpectedManifestSha256 $afterClaim.ManifestSha256 -TestId $idClaim
Assert-OPA265BW4j6Condition -Condition ($state1.State -ceq 'ClaimedSourceStillPresentNeverRetry' -and $state1.SourceExists -and -not $state1.DestinationExists -and $state1.ClaimExists) -Description 'claim-only crash state quarantined'
$retryBlocked=$false
try{$null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $afterClaim.SandboxRoot -ExpectedManifestSha256 $afterClaim.ManifestSha256 -TestId $idClaim -ConfirmIsolatedSyntheticOneShot}
catch{if([string]$_.Exception.Message -like '*NEVER retry*'){$retryBlocked=$true}else{throw}}
Assert-OPA265BW4j6Condition -Condition $retryBlocked -Description 'claim-only crash cannot resume Move'
# CRASH 2: claim + moved file, no receipt. Independently reconcile (NEVER Move).
$afterMove=New-OPA265BW4j6Run -Parent $SandboxParent
$mMove=Get-OPA265BW4j4Manifest -SandboxRoot $afterMove.SandboxRoot -ExpectedManifestSha256 $afterMove.ManifestSha256
$idMove=[string]$mMove.Plan.Cases[1].TestId
$injected2=$false
try{
    $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $afterMove.SandboxRoot -ExpectedManifestSha256 $afterMove.ManifestSha256 -TestId $idMove -ConfirmIsolatedSyntheticOneShot -CrashPoint AfterMove
}catch{if([string]$_.Exception.Message -like '*INJECTED CRASH after atomic synthetic move*'){$injected2=$true}else{throw}}
Assert-OPA265BW4j6Condition -Condition $injected2 -Description 'after-move crash injected'
$state2=Get-OPA265BW4j4State -SandboxRoot $afterMove.SandboxRoot -ExpectedManifestSha256 $afterMove.ManifestSha256 -TestId $idMove
Assert-OPA265BW4j6Condition -Condition ($state2.State -ceq 'MoveObservedAwaitIndependentReconciliation' -and
    -not $state2.SourceExists -and $state2.DestinationExists -and $state2.ClaimExists) -Description 'after-move crash state'
$receipt2=Write-OPA265BW4j5ReceiptOnce -SandboxRoot $afterMove.SandboxRoot -ExpectedManifestSha256 $afterMove.ManifestSha256 -TestId $idMove
$state2b=Get-OPA265BW4j4State -SandboxRoot $afterMove.SandboxRoot -ExpectedManifestSha256 $afterMove.ManifestSha256 -TestId $idMove
Assert-OPA265BW4j6Condition -Condition ($state2b.State -ceq 'ReceiptExistsReadOnlyVerify' -and
    $receipt2.ReceiptSha256 -cmatch '^[a-f0-9]{64}$') -Description 'read-only resume reconciliation plus receipt'
# CORRUPTION: add source duplicate after a simulated Move; fail closed.
$dup=New-OPA265BW4j6Run -Parent $SandboxParent
$mDup=Get-OPA265BW4j4Manifest -SandboxRoot $dup.SandboxRoot -ExpectedManifestSha256 $dup.ManifestSha256
$idDup=[string]$mDup.Plan.Cases[2].TestId
$null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $dup.SandboxRoot -ExpectedManifestSha256 $dup.ManifestSha256 -TestId $idDup -ConfirmIsolatedSyntheticOneShot
$pDup=Get-OPA265BW4j4Paths -Root $dup.SandboxRoot -TestId $idDup
[IO.File]::Copy($pDup.Target,$pDup.Source)
$stateDup=Get-OPA265BW4j4State -SandboxRoot $dup.SandboxRoot -ExpectedManifestSha256 $dup.ManifestSha256 -TestId $idDup
Assert-OPA265BW4j6Condition -Condition ($stateDup.State -ceq 'BLOCKED_DuplicateSourceAndDestination') -Description 'detect duplicate after crash'
# CORRUPTION: change a moved synthetic source payload; original manifest SHA must reject.
$corrupt=New-OPA265BW4j6Run -Parent $SandboxParent
$mCorrupt=Get-OPA265BW4j4Manifest -SandboxRoot $corrupt.SandboxRoot -ExpectedManifestSha256 $corrupt.ManifestSha256
$idCorrupt=[string]$mCorrupt.Plan.Cases[3].TestId
$null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $corrupt.SandboxRoot -ExpectedManifestSha256 $corrupt.ManifestSha256 -TestId $idCorrupt -ConfirmIsolatedSyntheticOneShot
$pCorrupt=Get-OPA265BW4j4Paths -Root $corrupt.SandboxRoot -TestId $idCorrupt
[IO.File]::AppendAllText($pCorrupt.Target,'TAMPERED')
$tamperBlocked=$false
try{$null=Get-OPA265BW4j5Reconciliation -SandboxRoot $corrupt.SandboxRoot -ExpectedManifestSha256 $corrupt.ManifestSha256 -TestId $idCorrupt}
catch{if([string]$_.Exception.Message -like '*differs from independent source manifest SHA256*'){$tamperBlocked=$true}else{throw}}
Assert-OPA265BW4j6Condition -Condition $tamperBlocked -Description 'reject even one byte changed after simulated Move'
$result=[pscustomobject][ordered]@{
    Schema='2.6.5-BW4j6.GitHubActionsSyntheticMatrix.1'
    Status='SyntheticGatesPassedNoRealOutlookOrPst'
    TotalFixtureCases=5
    MoveClaimsCreated=5
    IndependentReconciliations=5
    ImmutableReceiptsCreated=5
    DuplicateMoveAttemptsBlocked=5
    CrashAfterClaimBlocked=$retryBlocked
    CrashAfterMoveReconciledWithoutRetry=($state2b.State -ceq 'ReceiptExistsReadOnlyVerify')
    DuplicateSourceAndDestinationDetected=($stateDup.State -ceq 'BLOCKED_DuplicateSourceAndDestination')
    PayloadTamperingDetected=$tamperBlocked
    AssumedSyntheticSizeDelta=38
    RealOutlookSizeDeltaForFiveMessagesProven=$false
    RealMAPIEquivalenceProven=$false
    OriginalHistoricalJournalTouched=$false
    RealPstTouched=$false
    OutlookComUsed=$false
    CanRetryMove=$false
    ProductionReady=$false
    SuiteId=$normal.SuiteId
    OriginalManifestSha256=$normal.ManifestSha256
    Cases=@($moveResults.ToArray())
}
$result|Format-List
if($result.TotalFixtureCases -ne 5 -or $result.IndependentReconciliations -ne 5 -or
   -not $result.CrashAfterClaimBlocked -or -not $result.CrashAfterMoveReconciledWithoutRetry -or
   -not $result.PayloadTamperingDetected){throw 'BW4j6 synthetic matrix FAILED.'}
Write-Host 'BW4j6 SYNTHETIC MATRIX PASSED: 5/5, zero real Outlook/PST, fail-closed crashes.'
