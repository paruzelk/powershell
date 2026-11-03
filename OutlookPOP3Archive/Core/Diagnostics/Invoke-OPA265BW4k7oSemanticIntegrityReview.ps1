#requires -Version 5.1
# BW4k7o SEM-001 READ-ONLY policy review for already-moved BW4k7m fixture.
# No Outlook Move/Save/Delete/Send, no Claim/journal, no metadata waiver.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$FixtureId='d1a68868-acf5-4c70-860d-5521e1ce2836',
    [string]$ExpectedEvidenceSha256='36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29',
    [string]$ExpectedClaimSha256='6ba71ce58605f5c53ef0051f7f10919a388357ed3ac3c9e1feab76e71facda58',
    [string]$ExpectedDestinationEntryId='00000000E88584FF275FEE45B531E472CF338A8A24002000',
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7o requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7oSemanticIntegrityPolicy265.ps1')
$pins=Get-OPA265BW4k7oPolicy
if($FixtureId -cne [string]$pins.FixtureId -or
   $ExpectedEvidenceSha256 -cne [string]$pins.OriginalEvidenceSha256 -or
   $ExpectedClaimSha256 -cne [string]$pins.OriginalClaimSha256 -or
   $ExpectedDestinationEntryId -cne [string]$pins.DestinationEntryId -or
   $ExpectedProfileName -cne 'Outlook'){
    throw 'BW4k7o only the original BW4k7l/BW4k7m sealed forensic fixture is allowed.'
}
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7o.WhatIf.1'
        Status='WhatIfPolicyOnlyNoOutlookAccessNoWrites'
        FixtureId=$FixtureId
        EvidenceOrClaimRewritten=$false
        OutlookMoveExecuted=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
$stage='BW4k7n1 fresh independent original Evidence+Claim/full content and MAPI read-only review'
try{
    $args=@{
        FixtureId=$FixtureId
        ExpectedEvidenceSha256=$ExpectedEvidenceSha256
        ExpectedClaimSha256=$ExpectedClaimSha256
        ExpectedDestinationEntryId=$ExpectedDestinationEntryId
        ExpectedProfileName=$ExpectedProfileName
    }
    $forensic=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7nReadOnlyProviderInvestigation.ps1') @args
    $stage='SEM-001-BW4k7o exact original Evidence/Claim and 11 MAPI forensic observations'
    $transition=Get-OPA265BW4k7oTransitionFromVerifiedReport -Report $forensic
    $stage='Pure SEM-001-BW4k7o semantic/flag/size classification, all waivers prohibited'
    $decision=Get-OPA265BW4k7oSemanticDecision -Transition $transition
    if([string]$decision.Status -cne 'UnclassifiedRawMapiFlagsChangedBlocked' -or
       -not [bool]$decision.Unknown0x00010000Changed -or
       [string]$decision.UnclassifiedChangedMaskHex -cne '0x00010000' -or
       [string]$decision.ChangedRawMessageFlagsMaskHex -cne '0x00010002' -or
       [bool]$decision.ProductionReady -or [bool]$decision.WriterPermit -or
       [bool]$decision.AutomaticRetryAllowed -or
       [bool]$decision.HistoricalJournalReconciliationAllowed){
        throw 'BW4k7o exact old outcome changed or policy gave unsafe permission. STOP.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7o.LiveSemanticIntegrityPolicyReview.1'
        Status='VerifiedLogicalContentButUnknownMapiFlagBlockedNoWaiver'
        PolicyId=[string]$pins.PolicyId
        FixtureId=$FixtureId
        VerifiedOriginalPreMoveEvidenceSha256=[string]$forensic.OriginalPreMoveEvidenceSha256
        VerifiedIrreversibleClaimSha256=[string]$forensic.OriginalIrreversibleClaimSha256
        VerifiedDestinationEntryId=[string]$pins.DestinationEntryId
        SourceMessageMatches=[int]$forensic.SourceMessageIdMatches
        DestinationMessageMatches=[int]$forensic.DestinationMessageIdMatches
        FullSemanticContentMatch=[bool]$forensic.FullSemanticContentMatch
        SemanticFieldMismatchCount=[int]$forensic.SemanticFieldMismatchCount
        IndependentArchivedScalarReadPaths=[int]$forensic.IndependentArchivePropertyReads
        SourceRawMessageFlags=[int]$forensic.SourceRawMessageFlags
        DestinationRawMessageFlags=[int]$forensic.DestinationRawMessageFlags
        ChangedRawMessageFlagsMaskHex=[string]$decision.ChangedRawMessageFlagsMaskHex
        DocumentedMfUnmodified0x00000002Changed=[bool]$decision.DocumentedMfUnmodified0x00000002Changed
        Unknown0x00010000Changed=[bool]$decision.Unknown0x00010000Changed
        Unknown0x00010000MeaningEstablished=$false
        SourcePrMessageStatus=[int]$forensic.PrMessageStatusBeforeMove
        DestinationPrMessageStatus=[int]$forensic.PrMessageStatusAfterMove
        SourceMailItemSizeBytes=[long]$forensic.SourceMailItemSize
        DestinationMailItemSizeBytes=[long]$forensic.DestinationMailItemSize
        MailItemSizeDeltaBytes=[long]$forensic.MailItemSizeDeltaBytes
        DestinationPrMessageSizeBytes=[int]$forensic.PrMessageSizeBytes
        DestinationPrMessageSizeMatchesMailItem=[bool]$forensic.PrMessageSizeMatchesDestinationMailItemSize
        ExtendedPrMessageSizeObservationState=[string]$forensic.PrMessageSizeExtendedObservationState
        PreMoveOriginalRawPrMessageSizeCaptured=$false
        SizeDeltaCauseProven=$false
        PolicyClassification=[string]$decision.Status
        PolicySeverity=[string]$decision.Severity
        PolicyDifferenceBlocked=[bool]$decision.ClassifiedDifferenceBlocked
        ProviderPropertyInventory=@($forensic.ProviderPropertyInventory)
        PolicyDecision=$decision
        PhysicalPstDurabilityProven=$false
        SentItemsAndCustomFoldersCoverageProven=$false
        YearlyPstCapacityRolloverProven=$false
        OutlookMoveExecutedByThisReview=$false
        EvidenceOrClaimRewritten=$false
        JournalCompletionAllowed=$false
        AutomaticRetryAllowed=$false
        MetadataWaiverAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='STOP;PreserveEvidenceAndIrreversibleClaim;InvestigateUnknown0x10000AndOriginalSizeWithoutNewMove'
    }
}catch{
    throw ('BW4k7o READ-ONLY STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Move, evidence/Claim mutation, journal completion, waiver or retry.')
}
