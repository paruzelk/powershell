#requires -Version 5.1
# BW4k7t - NO Outlook, NO PST/registry, NO journal/Claim or new Move.
# Only evaluates prior operator-supplied read-only BW4k7o/BW4k7r/BW4k7s
# observations and synthetic semantic-case inputs. None is an immutable snapshot.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [psobject]$PreviousBW4k7sReadOnlyResult=$null,
    [psobject]$PreviousBW4k7rFullInventory=$null,
    [psobject]$HistoricBW4k7oForensicReport=$null,
    [psobject]$SyntheticSemanticCase=$null
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5){
    throw 'BW4k7t requires Windows PowerShell 5.1 for release-compatible checks.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7tSemanticAcceptancePolicy265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k7sInventoryRegistryPolicy265.ps1')
$policy=Get-OPA265BW4k7tPolicy
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7t.WhatIf.1'
        Status='WhatIfPolicyOnlyNoEvidenceReadOrWrites'
        PolicyId=$policy.PolicyId
        OutlookOrPstContacted=$false
        PreviousEvidenceOrClaimAltered=$false
        RegistryChanged=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
$stage='Read-only policy input validation'
try{
    $nonMail=$null;$years=$null;$historic=$null;$sample=$null
    if($null -ne $PreviousBW4k7sReadOnlyResult){
        $s=$PreviousBW4k7sReadOnlyResult
        if([string]$s.Schema -cne '2.6.5-BW4k7s.Pop3NonMailAndPstRegistryReadOnly.1' -or
           [string]$s.Status -cne 'CompleteReadOnlyNonMailWitnessesManualPreservationReview' -or
           [string]$s.SourcePst -ine
            'C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst' -or
           [long]$s.CandidateItemsExamined -ne 26605 -or
           [long]$s.MailItemsObserved -ne 26602 -or
           [long]$s.NonMailItemsObserved -ne 3 -or
           -not [bool]$s.FullNonMailInventoryCoverage -or
           -not [bool]$s.SourceFolderCountsReconciled -or
           -not [bool]$s.OutlookProcessUnchanged -or
           [bool]$s.PstOrRegistryWritten -or
           [bool]$s.WriterPermit -or [bool]$s.ProductionReady -or
           -not [bool]$s.OriginalSEM001Unknown0x00010000StillBlocked){
            throw 'BW4k7t previous BW4k7s operator read-only report is partial or mismatched.'
        }
        $nonMail=Test-OPA265BW4k7tNonMailWitnessSet -Witnesses @($s.NonMailWitnesses)
    }
    if($null -ne $PreviousBW4k7rFullInventory){
        $r=$PreviousBW4k7rFullInventory
        $yArgs=@{
            Inventory=$r
            ExpectedScopeCandidateItems=26605L
            ExpectedSourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
        }
        $years=Assert-OPA265BW4k7sPriorYearInventory @yArgs
        if([long]$years.EligibleArchiveMailItems -ne 21985 -or
           @($years.EligibleArchiveYears).Count -ne 6 -or
           [long]$years.NonMailItemsExpected -ne 3){
            throw 'BW4k7t operator-provided six-year POP3 plan differs from recorded baseline.'
        }
    }
    if($null -ne $HistoricBW4k7oForensicReport){
        $historic=Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report $HistoricBW4k7oForensicReport
    }
    if($null -ne $SyntheticSemanticCase){
        $sample=Test-OPA265BW4k7tSemanticCase -Case $SyntheticSemanticCase
        if([bool]$sample.WriterPermit -or [bool]$sample.ProductionReady -or
           [bool]$sample.OperatorResidualRiskDecisionRecorded){
            throw 'BW4k7t synthetic case must never grant writer/production.'
        }
    }
    $status=if($null -eq $nonMail -and $null -eq $years -and
        $null -eq $historic -and $null -eq $sample){
        'ProspectivePolicyOnlyNoPriorEvidenceProvidedNoWaiver'
    }else{'ReadOnlyOperatorEvidenceAndSyntheticPolicyReviewedNoWriterPermit'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7t.SemanticAcceptanceReadOnlyReport.1'
        Status=$status
        PolicyId=$policy.PolicyId
        UnknownProviderBitHex='0x00010000'
        UnknownProviderBitMeaning='NotEstablished'
        UnknownBitIsNotProofOfCorruption=$true
        UnknownBitAutomaticallySafe=$false
        OldBW4k7oHistoricHardBlockPreserved=$true
        FutureScopedRiskReviewPermittedAfterFullSemanticProof=$true
        RiskDecisionRecordedOrPermittedByThisRun=$false
        NonMailPreservationReview=$nonMail
        HistoricalSixYearPlanCrosscheck=$years
        HistoricalExactForensicReview=$historic
        SyntheticCaseReview=$sample
        PreviouslyObservedNonMailCount=if($null -ne $nonMail){3}else{$null}
        PreviousEligibleArchiveYearCount=if($null -ne $years){6}else{$null}
        PreviousEligibleMailItems=if($null -ne $years){21985L}else{$null}
        OperatorReportsAreNotImmutablePstSnapshots=$true
        SentItemsAtProductionScaleTested=$false
        NonMailClassSpecificPostMoveProofAvailable=$false
        CrashResumeAndMultiItemMoveProofAvailable=$false
        PhysicalPstDurabilityProven=$false
        YearlyArchivePstFilesCreated=$false
        OutlookContacted=$false
        PstOrRegistryReadByThisReview=$false
        PstOrRegistryWrittenByThisReview=$false
        EvidenceOrClaimRewritten=$false
        NewJournalCompleted=$false
        ExistingIrreversibleFixtureRetried=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='ReviewProspectiveSemanticCriteriaAndSeparateScopedResidualRiskApproval;NoNewMoveUntilFutureDedicatedTestPermit'
    }
}catch{
    throw ('BW4k7t READ-ONLY STOP at ['+$stage+']: '+
        [string]$_.Exception.Message+
        '. No Move, Evidence/Claim rewrite, registry change, journal completion or writer permit.')
}
