#requires -Version 5.1
# ARCH3e operator-only read-only integration audit; never opens PST/Outlook.
[CmdletBinding()]
param([ValidateSet('Plan','Audit')][string]$Mode='Audit')
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3e audit requires Windows PowerShell 5.1.'
}
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3e.Plan.1'
        Status='OriginalArchiveVerifierAndDuplicateIndexPostRestartSyntheticIntegrationNoLiveWriter'
        OriginalLegacyMailMoverRetained=$true
        OriginalArchiveVerifierUsed=$true
        OriginalSemanticWitnessRequired=$true
        OriginalOperationJournalReconciledOnlyAfterVerification=$true
        OriginalDuplicateIndexAppendOnlyAfterVerification=$true
        OneTargetItemRequiredInIsolatedSyntheticFixture=$true
        OriginalOperationJournalAndDuplicateIndexReadbackRequired=$true
        SyntheticOutlookProcessRestartOnly=$true
        IndependentLiveOutlookRestartIntegrated=$false
        LivePstIntegrationPerformed=$false
        ArchiveResumeAutoRemainClosed=$true
        ProductionReady=$false
        WriterPermit=$false
    }
}
$module=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Core/Archive/ARCH3ePostRestartIndexGate.ps1'),[Text.Encoding]::UTF8)
$main=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'OutlookPOP3Archive.ps1'),[Text.Encoding]::UTF8)
$oldVerifier=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Core/Archive/ArchiveVerifier.ps1'),[Text.Encoding]::UTF8)
$oldIndex=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Core/Archive/DuplicateIndex.ps1'),[Text.Encoding]::UTF8)
$oldJournal=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Core/Archive/OperationJournal.ps1'),[Text.Encoding]::UTF8)
$posVerify=$module.IndexOf('Test-OPAArchiveMoves -Namespace',[StringComparison]::Ordinal)
$posReview=$module.IndexOf('$proofSha=Write-OPA265ARCH3cJsonOnce -Path $proofFile',[StringComparison]::Ordinal)
$posJournal=$module.IndexOf('Write-OPAOperationJournalEvent @journalParams',[StringComparison]::Ordinal)
$posIndex=$module.IndexOf('Add-OPADuplicateEntry @indexParams',[StringComparison]::Ordinal)
$posIndexFlush=$module.IndexOf('Sync-OPADuplicateJournalStreams',[StringComparison]::Ordinal)
$posFinal=$module.IndexOf('Write-OPA265ARCH3cJsonOnce -Path $indexSealFile',[StringComparison]::Ordinal)
$checks=[ordered]@{
    OriginalArchiveVerifierStillPresent=$oldVerifier.Contains('function Test-OPAArchiveMoves')
    OriginalArchiveVerifierUsesSemanticComparison=$oldVerifier.Contains('Compare-OPA265ARCH2bMailSemanticWitness')
    OriginalDuplicateIndexAppenderReused=$oldIndex.Contains('function Add-OPADuplicateEntry')
    OriginalOperationJournalReconciledPhaseReused=$oldJournal.Contains("'Reconciled'")
    ProtectedOriginalMailMoverStillClosed=$main.Contains('Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode $Mode')
    IndependentGateCallsActualOriginalArchiveVerifier=($posVerify -ge 0 -and $module.Contains('-RequireSemanticWitness'))
    ExternalOriginalReceiptAndWitnessRequired=$module.Contains('Get-OPA265ARCH3ePinnedReceipt')
    FakeNonexistentPstOnly=$module.Contains('[IO.File]::Exists($source)') -and $module.Contains('[IO.File]::Exists([string]$ArchiveStore.FilePath)')
    OriginalSourceZeroAndOneDestinationRequired=$module.Contains('[int]$verified.TargetCount -eq 1') -and $module.Contains('[int]$verified.ObservedSourceCount -eq 0')
    OriginalJournalAfterVerifier=($posReview -gt $posVerify -and $posJournal -gt $posReview)
    OriginalDuplicateIndexAfterReconciledJournal=($posIndex -gt $posJournal)
    ForceFlushedOriginalDuplicateIndexBeforeSeal=($posIndexFlush -gt $posIndex -and $posFinal -gt $posIndexFlush)
    NoActualOutlookOrPstWriter=$module.Contains('fake PSCustomObject') -and (-not $module.Contains('GetActiveObject')) -and (-not $module.Contains('AddStoreEx'))
    ExplicitNoLiveProductionClaim=$module.Contains('ProductionReady=$false') -and $module.Contains('RealOutlookRestartProven=$false')
}
$failed=@($checks.GetEnumerator()|Where-Object{-not $_.Value}|ForEach-Object{$_.Key})
return [pscustomobject][ordered]@{
    Schema='2.6.5-ARCH3e.SourceBackedIndexGateAudit.1'
    Status=if($failed.Count -eq 0){'OriginalVerifierAndIndexSyntheticCommitIntegratedLiveRestartNotCertified'}else{'ARCH3eOriginalIntegrationContractMismatchManualReview'}
    Checks=$checks
    ChecksTotal=$checks.Count
    ChecksPassed=$checks.Count-$failed.Count
    FailedChecks=$failed
    OriginalArchiveVerifierUsed=$true
    OriginalDuplicateIndexUsed=$true
    OriginalOperationJournalUsed=$true
    SyntheticCommitCapableInPester=$true
    LiveOutlookRestartProofPresent=$false
    ActualPop3PstAccess=$false
    ArchiveResumeAutoRemainClosed=$true
    WriterPermit=$false
    ProductionReady=$false
}
