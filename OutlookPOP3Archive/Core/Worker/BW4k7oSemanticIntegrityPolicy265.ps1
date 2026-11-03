#requires -Version 5.1
# BW4k7o - SEM-001 semantic-integrity policy evaluator, PURE / READ ONLY.
# Never grants Archive, Resume, journal completion, Claim rewrite or Move permission.
# 0x00010000 has NO known meaning in this message-flags observation.
# STORE_HTML_OK (same numeric bit) belongs to a DIFFERENT MAPI property.
function Get-OPA265BW4k7oPolicy {
    [CmdletBinding()]
    param()
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7o.SemanticIntegrityPolicy.1'
        PolicyId='SEM-001-BW4k7o-v1'
        FixtureId='d1a68868-acf5-4c70-860d-5521e1ce2836'
        OriginalEvidenceSha256='36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29'
        OriginalClaimSha256='6ba71ce58605f5c53ef0051f7f10919a388357ed3ac3c9e1feab76e71facda58'
        SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A3504B03C00'
        DestinationEntryId='00000000E88584FF275FEE45B531E472CF338A8A24002000'
        ExpectedOriginalRawFlags=65555
        ExpectedDestinationRawFlags=17
        DocumentedMfUnmodifiedMask=2
        ProtectedReadAndHasAttachMask=17
        Unclassified0x00010000Mask=65536
        UnknownRawFlagWaiverPermitted=$false
        ProviderSizeOffsetWaiverPermitted=$false
        NoBlindMoveRetry=$true
        JournalCompletionAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7oExactLiveForensicReport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Report)
    $p=Get-OPA265BW4k7oPolicy
    $fixed=@{
        Schema='2.6.5-BW4k7n.ReadOnlyProviderSizeFlagAttribution.1'
        Status='TwoFixtureFlagsReproducedSizeDeltaObservedCauseStillUnclassified'
        FixtureId=[string]$p.FixtureId
        OriginalPreMoveEvidenceSha256=[string]$p.OriginalEvidenceSha256
        OriginalIrreversibleClaimSha256=[string]$p.OriginalClaimSha256
        SourceMessageIdMatches=0
        DestinationMessageIdMatches=1
        SourceRawMessageFlags=65555
        DestinationRawMessageFlags=17
        PrMessageStatusBeforeMove=0
        PrMessageStatusAfterMove=0
        HistoricalBW4k7gChangedMaskHex='0x00010002'
        NewBW4k7mChangedMaskHex='0x00010002'
        SourceMailItemSize=10489
        DestinationMailItemSize=9957
        MailItemSizeDeltaBytes=-532
        PrMessageSizeBytes=9957
        PrMessageSizeExtendedObservationState='NotProbedPowerShellComPtI8Interop'
        SampledScalarPropertyCount=11
        IndependentArchivePropertyReads=2
    }
    foreach($name in @($fixed.Keys)){
        if($Report.PSObject.Properties.Name -cnotcontains $name -or
           [string]$Report.$name -cne [string]$fixed[$name]){
            throw ('BW4k7o live forensic baseline changed/missing: '+$name+'. STOP.')
        }
    }
    $truth=@('FullSemanticContentMatch','ExactFlagDeltaReproducedAcrossTwoFixtures',
             'KnownMfUnmodified0x00000002Changed','Unknown0x00010000Changed',
             'PrMessageStatusUnchanged','SizeDifferenceReproducedAfterOutlookRestart',
             'PrMessageSizePresent','PrMessageSizeMatchesDestinationMailItemSize',
             'PrMessageSizeExtendedNotProbedByDesign','NoLargeBinaryMapiPropertiesLoaded',
             'NoThirdMoveOrWriter','OriginalFullBW4k7mSemanticsVerified')
    foreach($name in $truth){
        if($Report.PSObject.Properties.Name -cnotcontains $name -or
           $Report.$name -isnot [bool] -or -not $Report.$name){
            throw ('BW4k7o missing required real read-only proof: '+$name+'. STOP.')
        }
    }
    $falses=@('RawFlag0x00010000MeaningEstablished','CrossPropertyStoreHtmlOkEquivalenceAssumed',
              'OriginalPrMessageSizeCapturedBeforeMove','OriginalPrMessageSizeExtendedCapturedBeforeMove',
              'PropertySpecificSizeDeltaCauseProven','PrMessageSizeExtendedPresent',
              'PrMessageSizeExtendedProviderSupportEstablished','OriginalEvidenceOrClaimRewritten',
              'AutomaticRetryAllowed','ProviderFlagWaiver','WriterPermit','ProductionReady',
              'OutlookMoveExecutedByThisReview','IndependentProcessRestartComparisonAvailable')
    foreach($name in $falses){
        if($Report.PSObject.Properties.Name -cnotcontains $name -or
           $Report.$name -isnot [bool] -or $Report.$name){
            throw ('BW4k7o false safety guard violated/missing: '+$name+'. STOP.')
        }
    }
    if($Report.PSObject.Properties.Name -cnotcontains 'SemanticFieldMismatchCount' -or
       [int]$Report.SemanticFieldMismatchCount -ne 0 -or
       [string]$Report.OldBW4k7gClaimExpectedSha256 -cne
           '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c' -or
       $Report.PSObject.Properties.Name -cnotcontains 'PrMessageSizeExtendedBytes' -or
       $null -ne $Report.PrMessageSizeExtendedBytes -or
       $Report.PSObject.Properties.Name -cnotcontains 'PrMessageSizeExtendedMatchesDestinationMailItemSize' -or
       $null -ne $Report.PrMessageSizeExtendedMatchesDestinationMailItemSize){
        throw 'BW4k7o original/Claim/full semantic/Extended-PT_I8 evidence untrusted. STOP.'
    }
    # Validate every property observation, not merely a count. No implicit interpretation of absent as zero.
    $expected=@(
        @('PrMessageFlags','0x0E070003','Read',17),
        @('PrMessageStatus','0x0E170003','Read',0),
        @('PrHasAttachments','0x0E1B000B','Read',$true),
        @('PrMessageSize','0x0E080003','Read',9957),
        @('PrMessageSizeExtended','0x0E080014','NotProbedPowerShellComPtI8Interop',$null),
        @('PrNativeBody','0x10160003','Read',0),
        @('PrRtfInSync','0x0E1F000B','Read',$false),
        @('PrInternetCodepage','0x3FDE0003','Read',65001),
        @('PrMessageCodepage','0x3FFD0003','MapiNotFound',$null),
        @('PrLastModificationTime','0x30080040','Read',$null),
        @('PrCreationTime','0x30070040','Read',$null)
    )
    $items=@($Report.ProviderPropertyInventory)
    if($items.Count -ne 11){throw 'BW4k7o exactly 11 property observations required.'}
    for($i=0;$i -lt 11;$i++){
        $entry=$items[$i];$pin=$expected[$i]
        if([string]$entry.Name -cne [string]$pin[0] -or
           [string]$entry.Tag -cne [string]$pin[1] -or
           [string]$entry.ObservationState -cne [string]$pin[2] -or
           $entry.PSObject.Properties.Name -cnotcontains 'Available' -or
           $entry.Available -isnot [bool] -or
           $entry.PSObject.Properties.Name -cnotcontains 'Value' -or
           $entry.PSObject.Properties.Name -cnotcontains 'OriginalPreMoveValueCaptured' -or
           $entry.OriginalPreMoveValueCaptured -isnot [bool] -or $entry.OriginalPreMoveValueCaptured){
            throw ('BW4k7o archived property baseline changed or forged: index '+$i)
        }
        $isNull=($i -eq 4 -or $i -eq 8)
        if($isNull){
            if($entry.Available -or $null -ne $entry.Value){
                throw ('BW4k7o absent/not-probed property improperly filled: '+$entry.Name)
            }
        }else{
            if(-not $entry.Available){throw ('BW4k7o required observed property unavailable: '+$entry.Name)}
            if($i -ge 9){
                if($entry.Value -isnot [long] -and $entry.Value -isnot [int]){
                    throw ('BW4k7o invalid provider timestamp type: '+$entry.Name)
                }
                if([long]$entry.Value -le 0){throw ('BW4k7o invalid provider UTC ticks: '+$entry.Name)}
            }elseif([string]$entry.Value -cne [string]$pin[3]){
                throw ('BW4k7o property value changed from operator observation: '+$entry.Name)
            }
        }
    }
    return $true
}
function Get-OPA265BW4k7oSemanticDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Transition)
    $required=@(
        'SourceMatches','DestinationMatches','FullSemanticContentMatch',
        'SemanticFieldMismatchCount','EvidenceVerified','ClaimVerified',
        'IndependentDestinationReadPaths','SourceRawFlags','DestinationRawFlags',
        'SourceMessageStatus','DestinationMessageStatus','SourceMailItemSize',
        'DestinationMailItemSize','DestinationPrMessageSizeAvailable',
        'DestinationPrMessageSize','DestinationPrMessageSizeObservationState',
        'ProductionCoverageProven','PhysicalPstDurabilityProven'
    )
    foreach($name in $required){
        if($Transition.PSObject.Properties.Name -cnotcontains $name){
            throw ('BW4k7o missing required transition field: '+$name+'.')
        }
    }
    foreach($name in @('FullSemanticContentMatch','EvidenceVerified','ClaimVerified',
                        'DestinationPrMessageSizeAvailable','ProductionCoverageProven','PhysicalPstDurabilityProven')){
        if($Transition.$name -isnot [bool]){throw ('BW4k7o invalid Boolean field '+$name)}
    }
    $a=[long]$Transition.SourceRawFlags;$b=[long]$Transition.DestinationRawFlags
    if($a -lt 0 -or $a -gt 2147483647 -or
       $b -lt 0 -or $b -gt 2147483647 -or
       [long]$Transition.SemanticFieldMismatchCount -lt 0 -or
       [long]$Transition.SourceMailItemSize -le 0 -or
       [long]$Transition.DestinationMailItemSize -le 0){
        throw 'BW4k7o invalid negative/oversized flags or size or mismatch count.'
    }
    if($Transition.ProductionCoverageProven -or $Transition.PhysicalPstDurabilityProven){
        throw 'BW4k7o cannot infer production coverage or physical durability from the disposable fixture.'
    }
    $mask=[int]$a -bxor [int]$b
    $critical=$mask -band 17
    $knownProviderChange=$mask -band 2
    $unclassified=$mask -band (-bnot 19)
    $mailSizeDelta=[long]$Transition.DestinationMailItemSize-[long]$Transition.SourceMailItemSize
    $sizeState=[string]$Transition.DestinationPrMessageSizeObservationState
    if($sizeState -cnotin @('Read','MapiNotFound','NotProbedPowerShellComPtI8Interop')){
        throw 'BW4k7o invalid provider message-size observation state.'
    }
    if($Transition.DestinationPrMessageSizeAvailable -and
       ($sizeState -cne 'Read' -or
        $Transition.DestinationPrMessageSize -isnot [int] -or
        [int]$Transition.DestinationPrMessageSize -lt 0)){
        throw 'BW4k7o required typed provider size evidence inconsistent.'
    }
    if(-not $Transition.DestinationPrMessageSizeAvailable -and
       ($sizeState -ceq 'Read' -or $null -ne $Transition.DestinationPrMessageSize)){
        throw 'BW4k7o unknown provider size cannot be represented as a measured value.'
    }
    $providerSizeEqual=$null
    if($Transition.DestinationPrMessageSizeAvailable){
        $providerSizeEqual=([long]$Transition.DestinationPrMessageSize -eq
                            [long]$Transition.DestinationMailItemSize)
    }
    $classification='ExactObservedLogicalAndMetadataMatchReadOnly'
    $priority='None'
    $isBlocked=$false
    if(-not $Transition.EvidenceVerified -or -not $Transition.ClaimVerified -or
       [int]$Transition.IndependentDestinationReadPaths -lt 2){
        $classification='EvidenceNotAuthenticatedBlocked';$priority='Critical';$isBlocked=$true
    }elseif([int]$Transition.SourceMatches -ne 0 -or
           [int]$Transition.DestinationMatches -ne 1){
        $classification='SourceDestinationIdentityMismatchBlocked';$priority='Critical';$isBlocked=$true
    }elseif(-not $Transition.FullSemanticContentMatch -or
           [int]$Transition.SemanticFieldMismatchCount -ne 0){
        $classification='SemanticContentOrAttachmentMismatchBlocked';$priority='Critical';$isBlocked=$true
    }elseif([int]$Transition.SourceMessageStatus -ne [int]$Transition.DestinationMessageStatus){
        $classification='PrMessageStatusChangedBlocked';$priority='Critical';$isBlocked=$true
    }elseif($critical -ne 0){
        $classification='ReadOrHasAttachFlagChangedBlocked';$priority='Critical';$isBlocked=$true
    }elseif($unclassified -ne 0){
        $classification='UnclassifiedRawMapiFlagsChangedBlocked';$priority='Critical';$isBlocked=$true
    }elseif(-not $Transition.DestinationPrMessageSizeAvailable){
        $classification='ProviderMessageSizeNotObservedNeedsReview';$priority='Review';$isBlocked=$true
    }elseif(-not $providerSizeEqual){
        $classification='ProviderMessageSizeDisagreesWithMailItemNeedsReview';$priority='Review';$isBlocked=$true
    }elseif($knownProviderChange -ne 0){
        $classification='DocumentedMfUnmodifiedChangeNeedsReview';$priority='Review';$isBlocked=$true
    }elseif($mailSizeDelta -ne 0){
        $classification='SizeOnlyDifferenceNeedsReview';$priority='Review';$isBlocked=$true
    }
    $isUnknownBitChanged=(($mask -band 65536) -ne 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7o.SemanticIntegrityDecision.1'
        PolicyId='SEM-001-BW4k7o-v1'
        Status=$classification
        Severity=$priority
        ClassifiedDifferenceBlocked=$isBlocked
        FullSemanticContentMatch=[bool]$Transition.FullSemanticContentMatch
        SourceMessageMatches=[int]$Transition.SourceMatches
        DestinationMessageMatches=[int]$Transition.DestinationMatches
        ChangedRawMessageFlagsMaskHex=('0x{0:X8}' -f $mask)
        ProtectedReadOrHasAttachChanged=(($critical) -ne 0)
        DocumentedMfUnmodified0x00000002Changed=($knownProviderChange -ne 0)
        UnclassifiedChangedMaskHex=('0x{0:X8}' -f $unclassified)
        Unknown0x00010000Changed=$isUnknownBitChanged
        Unknown0x00010000MeaningEstablished=$false
        PrMessageStatusEqual=([int]$Transition.SourceMessageStatus -eq [int]$Transition.DestinationMessageStatus)
        SourceMailItemSizeBytes=[long]$Transition.SourceMailItemSize
        DestinationMailItemSizeBytes=[long]$Transition.DestinationMailItemSize
        MailItemSizeDeltaBytes=$mailSizeDelta
        DestinationPrMessageSizeAvailable=[bool]$Transition.DestinationPrMessageSizeAvailable
        DestinationPrMessageSizeBytes=$Transition.DestinationPrMessageSize
        DestinationPrMessageSizeObservationState=$sizeState
        DestinationPrMessageSizeMatchesMailItem=$providerSizeEqual
        OriginalRawPrMessageSizeCapturedBeforeMove=$false
        SizeDeltaCauseProven=$false
        SizeOnlyGlobalWaiverAllowed=$false
        FullProductionSemanticCoverageProven=$false
        PhysicalPstDurabilityProven=$false
        SentItemsAndCustomFoldersCoverageProven=$false
        YearlyArchiveCapacityRolloverProven=$false
        PriorClaimOrEvidenceRewritten=$false
        HistoricalJournalReconciliationAllowed=$false
        ManualReviewDoesNotPermitMove=$true
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='PreserveOriginalWitnessAndClaim;NoRetry;NoMetadataWaiver;DoNotEnableArchiveResumeOrAuto'
    }
}
function Get-OPA265BW4k7oTransitionFromVerifiedReport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Report)
    [void](Assert-OPA265BW4k7oExactLiveForensicReport -Report $Report)
    return [pscustomobject][ordered]@{
        SourceMatches=[int]$Report.SourceMessageIdMatches
        DestinationMatches=[int]$Report.DestinationMessageIdMatches
        FullSemanticContentMatch=[bool]$Report.FullSemanticContentMatch
        SemanticFieldMismatchCount=[int]$Report.SemanticFieldMismatchCount
        EvidenceVerified=$true
        ClaimVerified=$true
        IndependentDestinationReadPaths=[int]$Report.IndependentArchivePropertyReads
        SourceRawFlags=[int]$Report.SourceRawMessageFlags
        DestinationRawFlags=[int]$Report.DestinationRawMessageFlags
        SourceMessageStatus=[int]$Report.PrMessageStatusBeforeMove
        DestinationMessageStatus=[int]$Report.PrMessageStatusAfterMove
        SourceMailItemSize=[long]$Report.SourceMailItemSize
        DestinationMailItemSize=[long]$Report.DestinationMailItemSize
        DestinationPrMessageSizeAvailable=[bool]$Report.PrMessageSizePresent
        DestinationPrMessageSize=[int]$Report.PrMessageSizeBytes
        DestinationPrMessageSizeObservationState='Read'
        ProductionCoverageProven=$false
        PhysicalPstDurabilityProven=$false
    }
}
