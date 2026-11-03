#requires -Version 5.1
# BW4k7u: deterministic synthetic-only group archive preflight, NO Outlook/PST or disk.
# No Move, never reuses old BW4k7m one-shot Claim, no actual durable journal.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$SuiteId=([guid]::NewGuid().ToString('D')),
    [ValidateRange(1990,2101)][int]$ArchiveBeforeYear=2026,
    [ValidateRange(0,1099511627776)][long]$SimulatedSegmentCapBytes=0,
    [ValidateRange(104857600,1099511627776)][long]$MaxArchivePstSizeBytes=45000000000,
    [ValidateRange(0,1099511627775)][long]$SafetyMarginBytes=3000000000,
    [ValidateSet('None','AfterIntent','AfterClaim','AfterMove')][string]$FaultPoint='None',
    [string]$FaultCaseName='',
    [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'BW4k7u native Windows PowerShell 5.1 required.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7uSyntheticBatch265.ps1')
$suite=New-OPA265BW4k7uSyntheticSuite -SuiteId $SuiteId
$cap=@{
    Suite=$suite;ArchiveBeforeYear=$ArchiveBeforeYear
    SimulatedSegmentCapBytes=$SimulatedSegmentCapBytes
    MaxArchivePstSizeBytes=$MaxArchivePstSizeBytes
    SafetyMarginBytes=$SafetyMarginBytes
}
$plan=Get-OPA265BW4k7uSyntheticCapacityPlan @cap
$ledger=New-OPA265BW4k7uSyntheticLedger -Suite $suite -CapacityPlan $plan
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
$recovery=$null
if(-not $dry -and -not $PlanOnly){
    $faultId=''
    if($FaultPoint -cne 'None'){
        $matching=@($suite.Cases | Where-Object {$_.Name -ceq $FaultCaseName})
        if($matching.Count -ne 1){throw 'BW4k7u fault requires one exact synthetic case name.'}
        $faultId=[string]$matching[0].CaseId
    }
    $recovery=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $ledger -FaultPoint $FaultPoint -FaultCaseId $faultId
}
$status=if($dry){'WhatIfSyntheticPlanOnlyNoExternalContacts'}
        elseif($PlanOnly){'SyntheticPlanOnlyNoSimulatedMoves'}
        elseif($ledger.Interrupted){'SyntheticFaultInjectedManualRecoveryNoAutomaticRetry'}
        else{'EightSyntheticMailCasesModeledAndReconciledNoRealMove'}
return [pscustomobject][ordered]@{
    Schema='2.6.5-BW4k7u.SyntheticBatchReadOnlyPreflight.1'
    Status=$status
    SuiteId=[string]$suite.SuiteId
    ManifestSha256=[string]$suite.ManifestSha256
    FixtureCount=12
    EligibleSyntheticMailCount=@($plan.Allocations).Count
    PreservedCurrentYearAndNonMailCount=@($plan.PreservedObjects).Count
    Plan=$plan
    AllocationTable=@($plan.Allocations)
    PreservedObjects=@($plan.PreservedObjects)
    BatchLedger=$ledger
    RecoveryReview=$recovery
    FaultPoint=$FaultPoint
    FaultCaseName=$FaultCaseName
    SyntheticInMemoryOnly=$true
    OldBW4k7mIrreversibleClaimUntouched=$true
    OriginalBW4k7tSEM001PolicyNotWaived=$true
    RealOutlookMAPIObserved=$false
    RealPstOrRegistryAccessed=$false
    DiskIntentClaimOrJournalWritten=$false
    CrashDurabilityOrRealResumeProven=$false
    OutlookMoveExecuted=$false
    ProductionArchiveResumeAutoEnabled=$false
    AutomaticRetryAllowed=$false
    WriterPermit=$false
    ProductionReady=$false
    NextAction='ReviewSyntheticBatchCapacityAndFaultStatesThenBuildFreshDisposablePstPreflight;NoProduction'
}
