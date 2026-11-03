#requires -Version 5.1
# BW4k7t - prospective semantic acceptance review: PURE / NO WRITERS.
# Unknown 0x00010000 is an UNDOCUMENTED provider-state difference, not proven harmless.
# It is NOT an unconditional failure *for review eligibility*; operator acceptance is
# neither automatic nor sufficient for Move/production. BW4k7o history stays BLOCKED.
function Get-OPA265BW4k7tPolicy {
    [CmdletBinding()]
    param()
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7t.SemanticRiskPolicy.1'
        PolicyId='SEM-001-BW4k7t-Prospective-v1'
        ReplacesHistoricalBW4k7oDecision=$false
        HistoricFixtureId='d1a68868-acf5-4c70-860d-5521e1ce2836'
        OriginalEvidenceSha256='36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29'
        OriginalClaimSha256='6ba71ce58605f5c53ef0051f7f10919a388357ed3ac3c9e1feab76e71facda58'
        HistoricBeforeRawFlags=[long]65555
        HistoricAfterRawFlags=[long]17
        KnownMfUnmodifiedBit=[long]2
        ProtectedReadAndHasAttachMask=[long]17
        UndocumentedProviderBit=[long]65536
        PreviousSem001UnknownBitHardBlockPreserved=$true
        UndocumentedFlagMeaningProven=$false
        UndocumentedFlagAutomaticallySafe=$false
        UnknownFlagAloneNotProofOfCorruption=$true
        FullSemanticWitnessRequired=$true
        AttachmentPayloadSha256Required=$true
        RecipientAndSentUserStateRequired=$true
        MissingRequiredFieldIsHardStop=$true
        OperatorMaySeparatelyReviewScopedResidualRisk=$true
        OperatorResidualRiskAcceptanceRecordedHere=$false
        ManualAcceptanceAloneIsMovePermission=$false
        OriginalEvidenceOrClaimCanBeRebaselined=$false
        AutomaticRetryAllowed=$false
        JournalCompletionAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7tReadOnlyHistoricForensic {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Report)
    $policy=Get-OPA265BW4k7tPolicy
    $expected=[ordered]@{
        FixtureId=$policy.HistoricFixtureId
        OriginalPreMoveEvidenceSha256=$policy.OriginalEvidenceSha256
        OriginalIrreversibleClaimSha256=$policy.OriginalClaimSha256
        SourceMessageIdMatches=0
        DestinationMessageIdMatches=1
        SourceRawMessageFlags=65555
        DestinationRawMessageFlags=17
        SourceMailItemSize=10489
        DestinationMailItemSize=9957
        MailItemSizeDeltaBytes=-532
        PrMessageStatusBeforeMove=0
        PrMessageStatusAfterMove=0
    }
    foreach($key in @($expected.Keys)){
        if($Report.PSObject.Properties.Name -cnotcontains $key -or
            [string]$Report.$key -cne [string]$expected[$key]){
            throw ('BW4k7t original historic forensic evidence not exact: '+$key)
        }
    }
    foreach($key in @('FullSemanticContentMatch','NoThirdMoveOrWriter',
        'OriginalFullBW4k7mSemanticsVerified','Unknown0x00010000Changed')){
        if($Report.PSObject.Properties.Name -cnotcontains $key -or
           $Report.$key -isnot [bool] -or -not $Report.$key){
            throw ('BW4k7t historic forensic positive witness missing: '+$key)
        }
    }
    foreach($key in @('RawFlag0x00010000MeaningEstablished',
        'OriginalEvidenceOrClaimRewritten','AutomaticRetryAllowed','WriterPermit',
        'ProductionReady')){
        if($Report.PSObject.Properties.Name -cnotcontains $key -or
            $Report.$key -isnot [bool] -or $Report.$key){
            throw ('BW4k7t historic forensic forbidden claim: '+$key)
        }
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7t.HistoricEvidenceReview.1'
        Status='HistoricExactReadOnlyMatchButProductionSemanticCoverageUnproven'
        OriginalEvidenceSha256=$policy.OriginalEvidenceSha256
        OriginalClaimSha256=$policy.OriginalClaimSha256
        ChangedRawMaskHex='0x00010002'
        RawUnknown0x10000Meaning='UndocumentedNotProvenHarmlessOrHarmful'
        SourceZeroDestinationOneObserved=$true
        TestedContentAndAttachmentWitnessMatched=$true
        CompleteProductionRecipientAndUserStateCoverageEstablished=$false
        AnyMoveRepeated=$false
        OperatorResidualRiskAccepted=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Test-OPA265BW4k7tSemanticCase {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Case)
    $p=Get-OPA265BW4k7tPolicy
    foreach($name in @('CaseId','Kind','MessageClass','PreMoveSourceCount',
        'PreMoveDestinationCount','PostMoveSourceCount','PostMoveDestinationCount',
        'BeforeRawMessageFlags','AfterRawMessageFlags','MailItemSizeBefore',
        'MailItemSizeAfter')){
        if($Case.PSObject.Properties.Name -cnotcontains $name){
            throw ('BW4k7t synthetic semantic case missing required '+$name)
        }
    }
    $id=[string]$Case.CaseId
    $kind=[string]$Case.Kind
    if([string]::IsNullOrWhiteSpace($id) -or
       $kind -cnotin @('Mail','ReportNdr','ReportReadReceipt','MeetingRequest')){
        throw 'BW4k7t unsupported object kind or missing CaseId.'
    }
    $typeExpected=switch($kind){
        'Mail'{'IPM.Note'}
        'ReportNdr'{'Report.IPM.Note.NDR'}
        'ReportReadReceipt'{'Report.IPM.Note.IPNRN'}
        'MeetingRequest'{'IPM.Schedule.Meeting.Request'}
    }
    if([string]$Case.MessageClass -cne $typeExpected){
        throw 'BW4k7t unexpected class/message class; no generic other-class acceptance.'
    }
    foreach($name in @('PreMoveSourceCount','PreMoveDestinationCount',
        'PostMoveSourceCount','PostMoveDestinationCount')){
        if($Case.$name -isnot [int] -and $Case.$name -isnot [long]){
            throw ('BW4k7t noninteger identity count: '+$name)
        }
    }
    $identity=([long]$Case.PreMoveSourceCount -eq 1 -and
        [long]$Case.PreMoveDestinationCount -eq 0 -and
        [long]$Case.PostMoveSourceCount -eq 0 -and
        [long]$Case.PostMoveDestinationCount -eq 1)
    $required=@('ExactSourceAndDestinationStoresVerified',
        'ImmutableIntentAndClaimPinned','SingleAttemptClaimVerified',
        'UniqueMessageCorrelationVerified','OriginalAndDestinationClassMatch',
        'SubjectMatched','SenderMatched','RecipientSetMatched','TextBodyMatched',
        'HtmlBodyMatchedOrProvenAbsent','TransportHeadersMatchedOrProvenAbsent',
        'SentAndReceivedTimesMatched','AttachmentCountAndOrderMatched',
        'AttachmentPayloadSha256Matched','ReadUnreadAndProtectedFlagsMatched',
        'CategoriesAndFollowupMatched','OutlookRestartReadbackMatched',
        'IndependentReadbackSucceeded')
    $missing=New-Object 'System.Collections.Generic.List[string]'
    $failed=New-Object 'System.Collections.Generic.List[string]'
    foreach($name in $required){
        if($Case.PSObject.Properties.Name -cnotcontains $name -or
           $Case.$name -isnot [bool]){
            $missing.Add($name)
        }elseif(-not [bool]$Case.$name){
            $failed.Add($name)
        }
    }
    $rawBefore=[long]$Case.BeforeRawMessageFlags
    $rawAfter=[long]$Case.AfterRawMessageFlags
    if($rawBefore -lt 0 -or $rawBefore -gt 4294967295L -or
       $rawAfter -lt 0 -or $rawAfter -gt 4294967295L){
        throw 'BW4k7t raw MAPI message flags outside DWORD domain.'
    }
    $changed=[long]($rawBefore -bxor $rawAfter)
    $protectedChanged=(($changed -band [long]$p.ProtectedReadAndHasAttachMask) -ne 0)
    $unknownChanged=(($changed -band [long]$p.UndocumentedProviderBit) -ne 0)
    $allowedDiff=[long]($p.UndocumentedProviderBit -bor $p.KnownMfUnmodifiedBit)
    $otherChanged=(($changed -band (-bnot $allowedDiff)) -ne 0)
    if($Case.MailItemSizeBefore -isnot [int] -and
       $Case.MailItemSizeBefore -isnot [long]){throw 'BW4k7t size before not an integer.'}
    if($Case.MailItemSizeAfter -isnot [int] -and
       $Case.MailItemSizeAfter -isnot [long]){throw 'BW4k7t size after not an integer.'}
    $sizeBefore=[long]$Case.MailItemSizeBefore
    $sizeAfter=[long]$Case.MailItemSizeAfter
    if($sizeBefore -lt 0 -or $sizeAfter -lt 0){throw 'BW4k7t invalid negative size.'}
    $classification='InsufficientRequiredSemanticEvidence'
    $category='EvidenceIncomplete'
    if(-not $identity -or $failed.Count -gt 0 -or $protectedChanged){
        $classification='CriticalSemanticOrIdentityMismatchBlocked'
        $category='A'
    }elseif($missing.Count -gt 0){
        $classification='InsufficientRequiredSemanticEvidence'
        $category='EvidenceIncomplete'
    }elseif($otherChanged){
        $classification='UnexpectedOtherRawFlagChangeRequiresIndependentReview'
        $category='C'
    }elseif($kind -cne 'Mail'){
        # An Outlook report/meeting request is not an ordinary MailItem.
        # This evaluator cannot prove all class-specific properties or a safe Move.
        $classification='NonMailClassSpecificPreservationNotProven'
        $category='C'
    }elseif($unknownChanged){
        $classification='PotentialSemanticMatchUndocumentedProviderDifferenceReviewOnly'
        $category='C'
    }else{
        $classification='PotentialSemanticMatchNoUndocumentedBitChangeReviewOnly'
        $category='B'
    }
    $prospectiveCandidate=($identity -and $failed.Count -eq 0 -and
        $missing.Count -eq 0 -and -not $protectedChanged -and -not $otherChanged -and
        $kind -ceq 'Mail')
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7t.SemanticCaseReview.1'
        PolicyId=$p.PolicyId
        CaseId=$id;Kind=$kind
        MessageClass=$typeExpected
        Status=$classification
        Category=$category
        SourceZeroDestinationOneObserved=$identity
        MissingRequiredProperties=@($missing.ToArray())
        FailedRequiredProperties=@($failed.ToArray())
        ChangedRawFlagsMaskHex=('0x{0:X8}' -f $changed)
        ProtectedReadAndHasAttachBitsChanged=$protectedChanged
        Undocumented0x00010000Changed=$unknownChanged
        OtherUnknownRawFlagBitsChanged=$otherChanged
        UndocumentedBitMeaningProven=$false
        UndocumentedBitAutomaticallyWaived=$false
        MailItemSizeBefore=$sizeBefore
        MailItemSizeAfter=$sizeAfter
        MailItemSizeDeltaBytes=[long]($sizeAfter-$sizeBefore)
        SizeDeltaAloneIsFailure=$false
        MeaningfulSemanticFieldsMustRemainEqual=$true
        CandidateForSeparateScopedOperatorRiskDecision=$prospectiveCandidate
        NonMailClassSpecificPreservationProven=$false
        AllProductionPrerequisitesMet=$false
        OperatorResidualRiskDecisionRecorded=$false
        OutlookMovePerformedByThisCheck=$false
        NewJournalCompletionWritten=$false
        HistoricEvidenceOrClaimRewritten=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Test-OPA265BW4k7tNonMailWitnessSet {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object[]]$Witnesses)
    $pairs=@(
        [pscustomobject]@{Class=46;MessageClass='Report.IPM.Note.NDR';EntryId='00000000E1878292411BC64291BD506DCEFD2A35E4152A00'},
        [pscustomobject]@{Class=46;MessageClass='Report.IPM.Note.IPNRN';EntryId='00000000E1878292411BC64291BD506DCEFD2A3584922A00'},
        [pscustomobject]@{Class=53;MessageClass='IPM.Schedule.Meeting.Request';EntryId='00000000E1878292411BC64291BD506DCEFD2A35448A2C00'}
    )
    if($Witnesses.Count -ne 3){throw 'BW4k7t expected exactly three pinned prior operator nonmail witnesses.'}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($w in $Witnesses){
        if($null -eq $w -or [string]$w.FolderPath -cne '\Входящие' -or
           -not [bool]$w.RequiresManualPreservationDecision -or
           [string]$w.MessageClassObservation -cne 'Read' -or
           -not $seen.Add([string]$w.EntryId)){
            throw 'BW4k7t nonmail witness missing, duplicated or unexpected folder/decision.'
        }
        $matching=@($pairs | Where-Object {
            [string]$_.EntryId -ieq [string]$w.EntryId -and
            [int]$_.Class -eq [int]$w.Class -and
            [string]$_.MessageClass -ceq [string]$w.MessageClass
        })
        if($matching.Count -ne 1){throw 'BW4k7t operator nonmail witness differs from historic read-only evidence.'}
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7t.NonMailPreservationReview.1'
        Status='ThreeHistoricNonMailTypesCorroboratedButNoMoveAuthorization'
        ReportNdr=1;ReportReadReceipt=1;MeetingRequest=1
        CompletePerClassSemanticMoveWitnessAvailable=$false
        ThreeObjectsMustBePreserved=$true
        AutoDiscardAllowed=$false;AutoMoveAllowed=$false
        SourcePstModified=$false;ProductionReady=$false;WriterPermit=$false
    }
}
