#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7oSemanticIntegrityPolicy265.ps1')
    function New-OPA265BW4k7oSyntheticTransition {
        return [pscustomobject][ordered]@{
            SourceMatches=0;DestinationMatches=1
            FullSemanticContentMatch=$true;SemanticFieldMismatchCount=0
            EvidenceVerified=$true;ClaimVerified=$true
            IndependentDestinationReadPaths=2
            SourceRawFlags=65555;DestinationRawFlags=17
            SourceMessageStatus=0;DestinationMessageStatus=0
            SourceMailItemSize=[long]10489;DestinationMailItemSize=[long]9957
            DestinationPrMessageSizeAvailable=$true
            DestinationPrMessageSize=[int]9957
            DestinationPrMessageSizeObservationState='Read'
            ProductionCoverageProven=$false
            PhysicalPstDurabilityProven=$false
        }
    }
    function New-OPA265BW4k7oSyntheticReport {
        $p=Get-OPA265BW4k7oPolicy
        $spec=@(
            @('PrMessageFlags','0x0E070003','Read',[int]17),
            @('PrMessageStatus','0x0E170003','Read',[int]0),
            @('PrHasAttachments','0x0E1B000B','Read',$true),
            @('PrMessageSize','0x0E080003','Read',[int]9957),
            @('PrMessageSizeExtended','0x0E080014','NotProbedPowerShellComPtI8Interop',$null),
            @('PrNativeBody','0x10160003','Read',[int]0),
            @('PrRtfInSync','0x0E1F000B','Read',$false),
            @('PrInternetCodepage','0x3FDE0003','Read',[int]65001),
            @('PrMessageCodepage','0x3FFD0003','MapiNotFound',$null),
            @('PrLastModificationTime','0x30080040','Read',[long]639292855196420000),
            @('PrCreationTime','0x30070040','Read',[long]639292855196420000)
        )
        $inventory=New-Object 'System.Collections.Generic.List[object]'
        foreach($specLine in $spec){
            $state=[string]$specLine[2]
            $inventory.Add([pscustomobject][ordered]@{
                Name=[string]$specLine[0]
                Tag=[string]$specLine[1]
                ObservationState=$state
                Available=($state -ceq 'Read')
                Value=$specLine[3]
                OriginalPreMoveValueCaptured=$false
            })
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7n.ReadOnlyProviderSizeFlagAttribution.1'
            Status='TwoFixtureFlagsReproducedSizeDeltaObservedCauseStillUnclassified'
            FixtureId=[string]$p.FixtureId
            OriginalPreMoveEvidenceSha256=[string]$p.OriginalEvidenceSha256
            OriginalIrreversibleClaimSha256=[string]$p.OriginalClaimSha256
            OldBW4k7gClaimExpectedSha256='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
            SourceMessageIdMatches=0;DestinationMessageIdMatches=1
            FullSemanticContentMatch=$true;SemanticFieldMismatchCount=0
            ExactFlagDeltaReproducedAcrossTwoFixtures=$true
            SourceRawMessageFlags=65555;DestinationRawMessageFlags=17
            KnownMfUnmodified0x00000002Changed=$true
            Unknown0x00010000Changed=$true
            HistoricalBW4k7gChangedMaskHex='0x00010002'
            NewBW4k7mChangedMaskHex='0x00010002'
            RawFlag0x00010000MeaningEstablished=$false
            CrossPropertyStoreHtmlOkEquivalenceAssumed=$false
            PrMessageStatusBeforeMove=0;PrMessageStatusAfterMove=0
            PrMessageStatusUnchanged=$true
            SourceMailItemSize=[long]10489;DestinationMailItemSize=[long]9957
            MailItemSizeDeltaBytes=[long]-532
            SizeDifferenceReproducedAfterOutlookRestart=$true
            PrMessageSizePresent=$true
            PrMessageSizeBytes=[int]9957
            PrMessageSizeMatchesDestinationMailItemSize=$true
            PrMessageSizeExtendedPresent=$false
            PrMessageSizeExtendedBytes=$null
            PrMessageSizeExtendedMatchesDestinationMailItemSize=$null
            PrMessageSizeExtendedObservationState='NotProbedPowerShellComPtI8Interop'
            PrMessageSizeExtendedNotProbedByDesign=$true
            PrMessageSizeExtendedProviderSupportEstablished=$false
            OriginalPrMessageSizeCapturedBeforeMove=$false
            OriginalPrMessageSizeExtendedCapturedBeforeMove=$false
            PropertySpecificSizeDeltaCauseProven=$false
            SampledScalarPropertyCount=11
            ProviderPropertyInventory=@($inventory.ToArray())
            NoLargeBinaryMapiPropertiesLoaded=$true
            NoThirdMoveOrWriter=$true
            OriginalEvidenceOrClaimRewritten=$false
            AutomaticRetryAllowed=$false
            ProviderFlagWaiver=$false
            WriterPermit=$false
            ProductionReady=$false
            OriginalFullBW4k7mSemanticsVerified=$true
            IndependentArchivePropertyReads=2
            OutlookMoveExecutedByThisReview=$false
            IndependentProcessRestartComparisonAvailable=$false
        }
    }
    function Get-OPA265BW4k7oSyntheticDecision {
        param($Transition)
        if($null -eq $Transition){$Transition=New-OPA265BW4k7oSyntheticTransition}
        Get-OPA265BW4k7oSemanticDecision -Transition $Transition
    }
}
Describe 'BW4k7o SEM-001 read-only semantic integrity policy and full evidence gates' {
  It 'policy id explicitly versioned' {
    (Get-OPA265BW4k7oPolicy).PolicyId | Should -BeExactly 'SEM-001-BW4k7o-v1'
  }
  It 'original SHA pinned' {
    (Get-OPA265BW4k7oPolicy).OriginalEvidenceSha256 | Should -BeExactly '36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29'
  }
  It 'irreversible claim SHA pinned' {
    (Get-OPA265BW4k7oPolicy).OriginalClaimSha256 | Should -BeExactly '6ba71ce58605f5c53ef0051f7f10919a388357ed3ac3c9e1feab76e71facda58'
  }
  It 'exact archived EntryID pinned' {
    (Get-OPA265BW4k7oPolicy).DestinationEntryId | Should -BeExactly '00000000E88584FF275FEE45B531E472CF338A8A24002000'
  }
  It 'initial flags pinned' {
    (Get-OPA265BW4k7oPolicy).ExpectedOriginalRawFlags | Should -Be 65555
  }
  It 'destination flags pinned' {
    (Get-OPA265BW4k7oPolicy).ExpectedDestinationRawFlags | Should -Be 17
  }
  It 'mfUnmodified documented mask 2' {
    (Get-OPA265BW4k7oPolicy).DocumentedMfUnmodifiedMask | Should -Be 2
  }
  It 'critical read and attachment mask 17' {
    (Get-OPA265BW4k7oPolicy).ProtectedReadAndHasAttachMask | Should -Be 17
  }
  It 'unknown high-bit mask 65536' {
    (Get-OPA265BW4k7oPolicy).Unclassified0x00010000Mask | Should -Be 65536
  }
  It 'policy never grants writer' {
    (Get-OPA265BW4k7oPolicy).WriterPermit | Should -BeFalse
  }
  It 'policy never grants production' {
    (Get-OPA265BW4k7oPolicy).ProductionReady | Should -BeFalse
  }
  It 'policy never grants journal completion' {
    (Get-OPA265BW4k7oPolicy).JournalCompletionAllowed | Should -BeFalse
  }
  It 'live real report complete accepted as independently verified' {
    (Assert-OPA265BW4k7oExactLiveForensicReport -Report (New-OPA265BW4k7oSyntheticReport)) | Should -BeTrue
  }
  It 'new real report converter returns original flags' {
    $v=Get-OPA265BW4k7oTransitionFromVerifiedReport -Report (New-OPA265BW4k7oSyntheticReport); $v.SourceRawFlags | Should -Be 65555; $v.DestinationRawFlags | Should -Be 17
  }
  It 'new real report converter requires no production proof' {
    $v=Get-OPA265BW4k7oTransitionFromVerifiedReport -Report (New-OPA265BW4k7oSyntheticReport); $v.ProductionCoverageProven | Should -BeFalse; $v.PhysicalPstDurabilityProven | Should -BeFalse
  }
  It 'synthetic unknown high bit is blocker' {
    $r=Get-OPA265BW4k7oSyntheticDecision; $r.Status | Should -BeExactly 'UnclassifiedRawMapiFlagsChangedBlocked'; $r.ClassifiedDifferenceBlocked | Should -BeTrue
  }
  It 'synthetic XOR 0x00010002 matches real two cases' {
    (Get-OPA265BW4k7oSyntheticDecision).ChangedRawMessageFlagsMaskHex | Should -BeExactly '0x00010002'
  }
  It 'unclassified mask is precisely 0x00010000' {
    (Get-OPA265BW4k7oSyntheticDecision).UnclassifiedChangedMaskHex | Should -BeExactly '0x00010000'
  }
  It 'mfUnmodified separately tracked' {
    (Get-OPA265BW4k7oSyntheticDecision).DocumentedMfUnmodified0x00000002Changed | Should -BeTrue
  }
  It 'unknown bit never given semantic meaning' {
    (Get-OPA265BW4k7oSyntheticDecision).Unknown0x00010000MeaningEstablished | Should -BeFalse
  }
  It 'raw source destination MessageStatus equal' {
    (Get-OPA265BW4k7oSyntheticDecision).PrMessageStatusEqual | Should -BeTrue
  }
  It 'real delta negative 532 bytes' {
    (Get-OPA265BW4k7oSyntheticDecision).MailItemSizeDeltaBytes | Should -Be -532
  }
  It 'provider destination size matches MailItem' {
    (Get-OPA265BW4k7oSyntheticDecision).DestinationPrMessageSizeMatchesMailItem | Should -BeTrue
  }
  It 'original raw message size is not retroactively fabricated' {
    (Get-OPA265BW4k7oSyntheticDecision).OriginalRawPrMessageSizeCapturedBeforeMove | Should -BeFalse
  }
  It 'no causal size claim' {
    (Get-OPA265BW4k7oSyntheticDecision).SizeDeltaCauseProven | Should -BeFalse
  }
  It 'no blanket size waiver' {
    (Get-OPA265BW4k7oSyntheticDecision).SizeOnlyGlobalWaiverAllowed | Should -BeFalse
  }
  It 'no physical PST durability claim' {
    (Get-OPA265BW4k7oSyntheticDecision).PhysicalPstDurabilityProven | Should -BeFalse
  }
  It 'no Sent Items coverage claim' {
    (Get-OPA265BW4k7oSyntheticDecision).SentItemsAndCustomFoldersCoverageProven | Should -BeFalse
  }
  It 'no annual capacity rollover claim' {
    (Get-OPA265BW4k7oSyntheticDecision).YearlyArchiveCapacityRolloverProven | Should -BeFalse
  }
  It 'no new move in manual review' {
    (Get-OPA265BW4k7oSyntheticDecision).ManualReviewDoesNotPermitMove | Should -BeTrue
  }
  It 'no automatic retry ever' {
    (Get-OPA265BW4k7oSyntheticDecision).AutomaticRetryAllowed | Should -BeFalse
  }
  It 'historical journal remains blocked' {
    (Get-OPA265BW4k7oSyntheticDecision).HistoricalJournalReconciliationAllowed | Should -BeFalse
  }
  It 'writer stays false even if all tested fields match' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=17;$a.SourceMailItemSize=9957; $r=Get-OPA265BW4k7oSyntheticDecision $a; $r.WriterPermit | Should -BeFalse; $r.ProductionReady | Should -BeFalse
  }
  It 'missing original witness SHA returns untrusted blocked' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.EvidenceVerified=$false; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'EvidenceNotAuthenticatedBlocked'
  }
  It 'missing original claim returns untrusted blocked' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.ClaimVerified=$false; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'EvidenceNotAuthenticatedBlocked'
  }
  It 'one independent read is insufficient' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.IndependentDestinationReadPaths=1; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'EvidenceNotAuthenticatedBlocked'
  }
  It 'source still contains matching mail blocked' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceMatches=1; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'SourceDestinationIdentityMismatchBlocked'
  }
  It 'destination zero blocked' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationMatches=0; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'SourceDestinationIdentityMismatchBlocked'
  }
  It 'destination duplicates blocked' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationMatches=2; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'SourceDestinationIdentityMismatchBlocked'
  }
  It 'content mismatch blocked ahead of provider flags' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.FullSemanticContentMatch=$false; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'SemanticContentOrAttachmentMismatchBlocked'
  }
  It 'attachment hash mismatch count blocked' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SemanticFieldMismatchCount=1; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'SemanticContentOrAttachmentMismatchBlocked'
  }
  It 'changed status blocks before unknown flag classification' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationMessageStatus=1; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'PrMessageStatusChangedBlocked'
  }
  It 'read bit drift blocks' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=1; $a.DestinationRawFlags=0; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'ReadOrHasAttachFlagChangedBlocked'
  }
  It 'has attach bit drift blocks' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=16; $a.DestinationRawFlags=0; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'ReadOrHasAttachFlagChangedBlocked'
  }
  It 'unknown other MAPI flag blocks' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=32;$a.DestinationRawFlags=0; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'UnclassifiedRawMapiFlagsChangedBlocked'
  }
  It 'documented mfUnmodified change still needs review' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=19; $a.DestinationRawFlags=17; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'DocumentedMfUnmodifiedChangeNeedsReview'
  }
  It 'provider size missing needs review' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=17; $a.DestinationPrMessageSizeAvailable=$false; $a.DestinationPrMessageSize=$null; $a.DestinationPrMessageSizeObservationState='MapiNotFound'; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'ProviderMessageSizeNotObservedNeedsReview'
  }
  It 'provider size differs needs review' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=17; $a.DestinationPrMessageSize=9958; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'ProviderMessageSizeDisagreesWithMailItemNeedsReview'
  }
  It 'size only needs review without global waiver' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=17; (Get-OPA265BW4k7oSyntheticDecision $a).Status | Should -BeExactly 'SizeOnlyDifferenceNeedsReview'
  }
  It 'all observed properties matching still not production' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=17;$a.SourceMailItemSize=9957; $r=Get-OPA265BW4k7oSyntheticDecision $a; $r.Status | Should -BeExactly 'ExactObservedLogicalAndMetadataMatchReadOnly'; $r.ProductionReady | Should -BeFalse
  }
  It 'invalid negative source flags rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceRawFlags=-1; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'invalid negative destination flags rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationRawFlags=-1; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'source negative size rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.SourceMailItemSize=-5; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'destination zero size rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationMailItemSize=0; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'untrusted claim of production proof rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.ProductionCoverageProven=$true; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'untrusted claim of physical durability rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.PhysicalPstDurabilityProven=$true; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'missing required transition property rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; [void]$a.PSObject.Properties.Remove('ClaimVerified'); {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'non Boolean property rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.EvidenceVerified='true'; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'size read state and available inconsistent rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationPrMessageSizeObservationState='MapiNotFound'; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'provider size unavailable but value fabricated rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationPrMessageSizeAvailable=$false; $a.DestinationPrMessageSizeObservationState='MapiNotFound'; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'unrecognized provider observation state rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationPrMessageSizeObservationState='Imaginary'; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'provider size string type rejected' {
    $a=New-OPA265BW4k7oSyntheticTransition; $a.DestinationPrMessageSize='9957'; {Get-OPA265BW4k7oSyntheticDecision $a} | Should -Throw
  }
  It 'live report changed original Evidence SHA rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.OriginalPreMoveEvidenceSha256=('0'*64); {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report changed irreversible Claim SHA rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.OriginalIrreversibleClaimSha256=('0'*64); {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report unexpected fixture id rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.FixtureId='0'; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report missing source-one target-zero rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.SourceMessageIdMatches=1; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report invalid semantic digest rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.FullSemanticContentMatch=$false; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report user flags changed again rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.DestinationRawMessageFlags=16; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report original unknown bit waiver rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.RawFlag0x00010000MeaningEstablished=$true; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report cross-property HTML confusion rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.CrossPropertyStoreHtmlOkEquivalenceAssumed=$true; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report destination size drift change rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.DestinationMailItemSize=9956; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report provider size not observed rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.PrMessageSizePresent=$false; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report extended size falsely read rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.PrMessageSizeExtendedPresent=$true; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report extended size falsely populated rejected' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.PrMessageSizeExtendedBytes=[long]9957; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report 11 property count enforced' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.ProviderPropertyInventory=@($r.ProviderPropertyInventory | Select-Object -Skip 1); {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report required properties cannot be fabricated' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.ProviderPropertyInventory[0].Value=19; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report optional property absence not equal to zero' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.ProviderPropertyInventory[8].Value=[int]0; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report 64-bit notprobed not substituted' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.ProviderPropertyInventory[4].ObservationState='MapiNotFound'; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report timestamp type enforced' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.ProviderPropertyInventory[9].Value='2026-11-03'; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report original pre-Move raw MAPI size not invented' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.OriginalPrMessageSizeCapturedBeforeMove=$true; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report no new writer proof required' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.NoThirdMoveOrWriter=$false; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report no automatic retry gate required' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.AutomaticRetryAllowed=$true; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'live report forbids forged production-ready' {
    $r=New-OPA265BW4k7oSyntheticReport; $r.ProductionReady=$true; {Assert-OPA265BW4k7oExactLiveForensicReport $r} | Should -Throw
  }
  It 'controller uses n1 independent real forensic review' {
    $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7oSemanticIntegrityReview.ps1'); $s | Should -Match 'Invoke-OPA265BW4k7nReadOnlyProviderInvestigation'
  }
  It 'controller enforces exact unknown raw bit block' {
    $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7oSemanticIntegrityReview.ps1'); $s | Should -Match 'UnclassifiedRawMapiFlagsChangedBlocked'
  }
  It 'controller contains no Outlook move/save or claim writer' {
    $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7oSemanticIntegrityReview.ps1'); $s | Should -Not -Match '(?i)\.(Move|Save|Delete|Send|SetProperty)\s*\('; $s | Should -Not -Match 'Write-OPA265BW4k7mClaimOnce'
  }
  It 'controller no Pester-only pretend real Move' {
    $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7oSemanticIntegrityReview.ps1'); $s | Should -Match 'OutlookMoveExecutedByThisReview=\$false'
  }
  It 'controller has -WhatIf no Outlook access' {
    $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7oSemanticIntegrityReview.ps1'); $s | Should -Match 'WhatIfPolicyOnlyNoOutlookAccessNoWrites'
  }
}
