#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7tSemanticAcceptancePolicy265.ps1')
    function New-BW4k7tSyntheticCase {
        param([string]$Kind='Mail',[long]$Before=65555,[long]$After=17)
        $msg=switch($Kind) {
            'Mail'{'IPM.Note'}
            'ReportNdr'{'Report.IPM.Note.NDR'}
            'ReportReadReceipt'{'Report.IPM.Note.IPNRN'}
            'MeetingRequest'{'IPM.Schedule.Meeting.Request'}
            default{'Bad.Class'}
        }
        return [pscustomobject][ordered]@{
            CaseId='SyntheticDisposableOnly'
            Kind=$Kind;MessageClass=$msg
            PreMoveSourceCount=[int]1;PreMoveDestinationCount=[int]0
            PostMoveSourceCount=[int]0;PostMoveDestinationCount=[int]1
            BeforeRawMessageFlags=$Before;AfterRawMessageFlags=$After
            MailItemSizeBefore=[long]10489;MailItemSizeAfter=[long]9957
            ExactSourceAndDestinationStoresVerified=$true
            ImmutableIntentAndClaimPinned=$true
            SingleAttemptClaimVerified=$true
            UniqueMessageCorrelationVerified=$true
            OriginalAndDestinationClassMatch=$true
            SubjectMatched=$true;SenderMatched=$true
            RecipientSetMatched=$true
            TextBodyMatched=$true;HtmlBodyMatchedOrProvenAbsent=$true
            TransportHeadersMatchedOrProvenAbsent=$true
            SentAndReceivedTimesMatched=$true
            AttachmentCountAndOrderMatched=$true
            AttachmentPayloadSha256Matched=$true
            ReadUnreadAndProtectedFlagsMatched=$true
            CategoriesAndFollowupMatched=$true
            OutlookRestartReadbackMatched=$true
            IndependentReadbackSucceeded=$true
        }
    }
    function New-BW4k7tHistoricalNonMail {
        return @(
            [pscustomobject]@{
                Class=46;MessageClass='Report.IPM.Note.NDR'
                EntryId='00000000E1878292411BC64291BD506DCEFD2A35E4152A00'
                FolderPath='\Входящие';MessageClassObservation='Read'
                RequiresManualPreservationDecision=$true
            },
            [pscustomobject]@{
                Class=46;MessageClass='Report.IPM.Note.IPNRN'
                EntryId='00000000E1878292411BC64291BD506DCEFD2A3584922A00'
                FolderPath='\Входящие';MessageClassObservation='Read'
                RequiresManualPreservationDecision=$true
            },
            [pscustomobject]@{
                Class=53;MessageClass='IPM.Schedule.Meeting.Request'
                EntryId='00000000E1878292411BC64291BD506DCEFD2A35448A2C00'
                FolderPath='\Входящие';MessageClassObservation='Read'
                RequiresManualPreservationDecision=$true
            }
        )
    }
    function New-BW4k7tHistoricForensic {
        $p=Get-OPA265BW4k7tPolicy
        return [pscustomobject]@{
            FixtureId=[string]$p.HistoricFixtureId
            OriginalPreMoveEvidenceSha256=[string]$p.OriginalEvidenceSha256
            OriginalIrreversibleClaimSha256=[string]$p.OriginalClaimSha256
            SourceMessageIdMatches=[int]0;DestinationMessageIdMatches=[int]1
            SourceRawMessageFlags=[long]65555;DestinationRawMessageFlags=[long]17
            SourceMailItemSize=[long]10489;DestinationMailItemSize=[long]9957
            MailItemSizeDeltaBytes=[long]-532
            PrMessageStatusBeforeMove=[int]0;PrMessageStatusAfterMove=[int]0
            FullSemanticContentMatch=$true
            NoThirdMoveOrWriter=$true
            OriginalFullBW4k7mSemanticsVerified=$true
            Unknown0x00010000Changed=$true
            RawFlag0x00010000MeaningEstablished=$false
            OriginalEvidenceOrClaimRewritten=$false
            AutomaticRetryAllowed=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    function New-BW4k7tOperatorSReport {
        return [pscustomobject]@{
            Schema='2.6.5-BW4k7s.Pop3NonMailAndPstRegistryReadOnly.1'
            Status='CompleteReadOnlyNonMailWitnessesManualPreservationReview'
            SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
            CandidateItemsExamined=26605L;MailItemsObserved=26602L
            NonMailItemsObserved=3L;FullNonMailInventoryCoverage=$true
            SourceFolderCountsReconciled=$true;OutlookProcessUnchanged=$true
            PstOrRegistryWritten=$false;WriterPermit=$false;ProductionReady=$false
            OriginalSEM001Unknown0x00010000StillBlocked=$true
            NonMailWitnesses=@(New-BW4k7tHistoricalNonMail)
        }
    }
    function New-BW4k7tOperatorRReport {
        $counts=[ordered]@{'2020'=3744;'2021'=3598;'2022'=3515;'2023'=2752;'2024'=4252;'2025'=4124;'2026'=4617}
        $v=New-Object 'System.Collections.Generic.List[object]'
        foreach($k in $counts.Keys){
            $y=[int]$k
            $v.Add([pscustomobject]@{
                Year=$y;InboxMailItems=[long]$counts[$k]
                SentItemsMailItems=[long]0;UserFolderMailItems=[long]0
                TotalMailItems=[long]$counts[$k]
                ArchiveYearEligible=($y -lt 2026)
                Coverage='FullyEnumeratedObservedMetadata'
                NoArchiveFileCreated=$true
            })
        }
        return [pscustomobject]@{
            Schema='2.6.5-BW4k7r.Pop3YearDistributionCapacityReadOnly.1'
            Status='FullObservedPOP3YearDistributionReadOnlyCapacityForecastOnly'
            YearDistributionComplete=$true;AllCandidateItemsEnumerated=$true
            ScopeCandidateItemsTotal=26605L;CandidateItemsExamined=26605L
            MailItemsDated=26602L;MailItemsObserved=26602L
            MailItemsUndated=0L;NonMailItemsObserved=3L
            SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
            ArchiveBeforeYear=2026;YearDistribution=@($v.ToArray())
            MailMovedOrDeleted=$false;WriterPermit=$false;ProductionReady=$false
            OriginalSEM001Unknown0x00010000StillBlocked=$true
        }
    }
}
Describe 'BW4k7t versioned prospective SEM-001 residual risk review without historical waiver or writer' {
    It 'policy is versioned' {
        (Get-OPA265BW4k7tPolicy).PolicyId | Should -BeExactly 'SEM-001-BW4k7t-Prospective-v1'
    }
    It 'old BW4k7o decision preserved' {
        (Get-OPA265BW4k7tPolicy).ReplacesHistoricalBW4k7oDecision | Should -BeFalse
    }
    It 'unknown 0x10000 meaning never claimed' {
        (Get-OPA265BW4k7tPolicy).UndocumentedFlagMeaningProven | Should -BeFalse
    }
    It 'unknown 0x10000 not declared safe' {
        (Get-OPA265BW4k7tPolicy).UndocumentedFlagAutomaticallySafe | Should -BeFalse
    }
    It 'unknown 0x10000 alone is not corruption proof' {
        (Get-OPA265BW4k7tPolicy).UnknownFlagAloneNotProofOfCorruption | Should -BeTrue
    }
    It 'still preserve old unknown bit hard block' {
        (Get-OPA265BW4k7tPolicy).PreviousSem001UnknownBitHardBlockPreserved | Should -BeTrue
    }
    It 'original evidence SHA pinned' {
        (Get-OPA265BW4k7tPolicy).OriginalEvidenceSha256 | Should -BeExactly '36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29'
    }
    It 'irreversible claim SHA pinned' {
        (Get-OPA265BW4k7tPolicy).OriginalClaimSha256 | Should -BeExactly '6ba71ce58605f5c53ef0051f7f10919a388357ed3ac3c9e1feab76e71facda58'
    }
    It 'future risk review allowed but no acceptance recorded' {
        (Get-OPA265BW4k7tPolicy).OperatorResidualRiskAcceptanceRecordedHere | Should -BeFalse
    }
    It 'manual acceptance alone never permits Move' {
        (Get-OPA265BW4k7tPolicy).ManualAcceptanceAloneIsMovePermission | Should -BeFalse
    }
    It 'missing field hard stop policy' {
        (Get-OPA265BW4k7tPolicy).MissingRequiredFieldIsHardStop | Should -BeTrue
    }
    It 'attachment payload sha required' {
        (Get-OPA265BW4k7tPolicy).AttachmentPayloadSha256Required | Should -BeTrue
    }
    It 'recipient and sent user state required' {
        (Get-OPA265BW4k7tPolicy).RecipientAndSentUserStateRequired | Should -BeTrue
    }
    It 'no automatic retry ever' {
        (Get-OPA265BW4k7tPolicy).AutomaticRetryAllowed | Should -BeFalse
    }
    It 'no journal completion' {
        (Get-OPA265BW4k7tPolicy).JournalCompletionAllowed | Should -BeFalse
    }
    It 'no production flag' {
        (Get-OPA265BW4k7tPolicy).ProductionReady | Should -BeFalse
    }
    It 'no writer flag' {
        (Get-OPA265BW4k7tPolicy).WriterPermit | Should -BeFalse
    }
    It 'mail synthetic full semantic matched candidate C' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase)).Category | Should -BeExactly 'C'
    }
    It 'mail synthetic unknown status review only' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase)).Status | Should -BeExactly 'PotentialSemanticMatchUndocumentedProviderDifferenceReviewOnly'
    }
    It 'unknown exact changed mask 0x10002' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase)).ChangedRawFlagsMaskHex | Should -BeExactly '0x00010002'
    }
    It 'unknown bit tracked not automatically waived' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase); $r.Undocumented0x00010000Changed | Should -BeTrue; $r.UndocumentedBitAutomaticallyWaived | Should -BeFalse
    }
    It 'synthetic full semantic candidate for separate risk review' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase)).CandidateForSeparateScopedOperatorRiskDecision | Should -BeTrue
    }
    It 'candidate never writer or production' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase); $r.WriterPermit | Should -BeFalse; $r.ProductionReady | Should -BeFalse
    }
    It 'candidate never operator acceptance' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase)).OperatorResidualRiskDecisionRecorded | Should -BeFalse
    }
    It 'candidate never performs Move' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase)).OutlookMovePerformedByThisCheck | Should -BeFalse
    }
    It 'size -532 recorded without waiver' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase); $r.MailItemSizeDeltaBytes | Should -Be -532; $r.SizeDeltaAloneIsFailure | Should -BeFalse
    }
    It 'no unknown bits with 19 to 17 category B' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Before 19 -After 17); $r.Category | Should -BeExactly 'B'; $r.CandidateForSeparateScopedOperatorRiskDecision | Should -BeTrue
    }
    It 'no flag difference no unknown category B' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Before 17 -After 17)).Category | Should -BeExactly 'B'
    }
    It 'documented mfUnmodified change tracked only' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Before 19 -After 17)).ChangedRawFlagsMaskHex | Should -BeExactly '0x00000002'
    }
    It 'read bit changed is class A' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Before 65554 -After 17); $r.Category | Should -BeExactly 'A'; $r.CandidateForSeparateScopedOperatorRiskDecision | Should -BeFalse
    }
    It 'attachment presence bit changed is class A' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Before 65539 -After 17); $r.Category | Should -BeExactly 'A'
    }
    It 'unexpected raw flag bit requires C review' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Before 131091 -After 17); $r.Status | Should -BeExactly 'UnexpectedOtherRawFlagChangeRequiresIndependentReview'
    }
    It 'unexpected raw bit does not become candidate' {
        (Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Before 131091 -After 17)).CandidateForSeparateScopedOperatorRiskDecision | Should -BeFalse
    }
    It 'source zero destination one wrong blocks category A' {
        $c=New-BW4k7tSyntheticCase; $c.PostMoveDestinationCount=0; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'pre-existing destination duplicate blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.PreMoveDestinationCount=1; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'source still present blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.PostMoveSourceCount=1; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'missing source pre-move blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.PreMoveSourceCount=0; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'body mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.TextBodyMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'HTML mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.HtmlBodyMatchedOrProvenAbsent=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'subject mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.SubjectMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'sender mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.SenderMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'recipient mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.RecipientSetMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'attachment SHA mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.AttachmentPayloadSha256Matched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'attachment count order mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.AttachmentCountAndOrderMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'read unread mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.ReadUnreadAndProtectedFlagsMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'categories followup mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.CategoriesAndFollowupMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'date mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.SentAndReceivedTimesMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'headers mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.TransportHeadersMatchedOrProvenAbsent=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'original intent claim absent blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.ImmutableIntentAndClaimPinned=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'restart readback mismatch blocks A' {
        $c=New-BW4k7tSyntheticCase; $c.OutlookRestartReadbackMatched=$false; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'A'
    }
    It 'missing mandatory field cannot be accepted' {
        $c=New-BW4k7tSyntheticCase; [void]$c.PSObject.Properties.Remove('SenderMatched'); $r=Test-OPA265BW4k7tSemanticCase -Case $c; $r.Status | Should -BeExactly 'InsufficientRequiredSemanticEvidence'; $r.CandidateForSeparateScopedOperatorRiskDecision | Should -BeFalse
    }
    It 'nonBoolean mandatory witness rejected as incomplete' {
        $c=New-BW4k7tSyntheticCase; $c.SenderMatched='True'; (Test-OPA265BW4k7tSemanticCase -Case $c).Category | Should -BeExactly 'EvidenceIncomplete'
    }
    It 'mail with unexpected MessageClass rejects' {
        $c=New-BW4k7tSyntheticCase; $c.MessageClass='IPM.Note.Custom'; {Test-OPA265BW4k7tSemanticCase -Case $c} | Should -Throw
    }
    It 'empty CaseId rejects' {
        $c=New-BW4k7tSyntheticCase; $c.CaseId=''; {Test-OPA265BW4k7tSemanticCase -Case $c} | Should -Throw
    }
    It 'unknown object type rejects' {
        $c=New-BW4k7tSyntheticCase; $c.Kind='UnregisteredOther'; {Test-OPA265BW4k7tSemanticCase -Case $c} | Should -Throw
    }
    It 'negative size rejects' {
        $c=New-BW4k7tSyntheticCase; $c.MailItemSizeBefore=-1; {Test-OPA265BW4k7tSemanticCase -Case $c} | Should -Throw
    }
    It 'invalid raw DWORD rejects' {
        $c=New-BW4k7tSyntheticCase; $c.BeforeRawMessageFlags=-1; {Test-OPA265BW4k7tSemanticCase -Case $c} | Should -Throw
    }
    It 'ReportNdr requires class-specific proof not auto Move' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Kind ReportNdr); $r.Status | Should -BeExactly 'NonMailClassSpecificPreservationNotProven'; $r.CandidateForSeparateScopedOperatorRiskDecision | Should -BeFalse
    }
    It 'ReportReadReceipt requires class-specific proof not auto Move' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Kind ReportReadReceipt); $r.Status | Should -BeExactly 'NonMailClassSpecificPreservationNotProven'; $r.CandidateForSeparateScopedOperatorRiskDecision | Should -BeFalse
    }
    It 'MeetingRequest requires class-specific proof not auto Move' {
        $r=Test-OPA265BW4k7tSemanticCase -Case (New-BW4k7tSyntheticCase -Kind MeetingRequest); $r.Status | Should -BeExactly 'NonMailClassSpecificPreservationNotProven'; $r.CandidateForSeparateScopedOperatorRiskDecision | Should -BeFalse
    }
    It 'three pinned nonmail types verify without Move' {
        (Test-OPA265BW4k7tNonMailWitnessSet -Witnesses @(New-BW4k7tHistoricalNonMail)).Status | Should -BeExactly 'ThreeHistoricNonMailTypesCorroboratedButNoMoveAuthorization'
    }
    It 'three pinned nonmail never discard' {
        (Test-OPA265BW4k7tNonMailWitnessSet -Witnesses @(New-BW4k7tHistoricalNonMail)).AutoDiscardAllowed | Should -BeFalse
    }
    It 'three pinned nonmail never auto Move' {
        (Test-OPA265BW4k7tNonMailWitnessSet -Witnesses @(New-BW4k7tHistoricalNonMail)).AutoMoveAllowed | Should -BeFalse
    }
    It 'three pinned nonmail counts each one' {
        $r=Test-OPA265BW4k7tNonMailWitnessSet -Witnesses @(New-BW4k7tHistoricalNonMail); $r.ReportNdr | Should -Be 1; $r.ReportReadReceipt | Should -Be 1; $r.MeetingRequest | Should -Be 1
    }
    It 'missing third nonmail witness rejects' {
        $w=@(New-BW4k7tHistoricalNonMail); {Test-OPA265BW4k7tNonMailWitnessSet -Witnesses @($w[0],$w[1])} | Should -Throw
    }
    It 'duplicated nonmail entry rejects' {
        $w=@(New-BW4k7tHistoricalNonMail); $w[2].EntryId=$w[1].EntryId; {Test-OPA265BW4k7tNonMailWitnessSet -Witnesses $w} | Should -Throw
    }
    It 'wrong nonmail class rejects' {
        $w=@(New-BW4k7tHistoricalNonMail); $w[1].Class=43; {Test-OPA265BW4k7tNonMailWitnessSet -Witnesses $w} | Should -Throw
    }
    It 'wrong nonmail folder rejects' {
        $w=@(New-BW4k7tHistoricalNonMail); $w[0].FolderPath='\Другое'; {Test-OPA265BW4k7tNonMailWitnessSet -Witnesses $w} | Should -Throw
    }
    It 'wrong nonmail MessageClass rejects' {
        $w=@(New-BW4k7tHistoricalNonMail); $w[0].MessageClass='IPM.Note'; {Test-OPA265BW4k7tNonMailWitnessSet -Witnesses $w} | Should -Throw
    }
    It 'missing nonmail preservation decision rejects' {
        $w=@(New-BW4k7tHistoricalNonMail); $w[0].RequiresManualPreservationDecision=$false; {Test-OPA265BW4k7tNonMailWitnessSet -Witnesses $w} | Should -Throw
    }
    It 'pinned historic old forensic validates read-only' {
        (Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report (New-BW4k7tHistoricForensic)).Status | Should -BeExactly 'HistoricExactReadOnlyMatchButProductionSemanticCoverageUnproven'
    }
    It 'pinned historic source-zero destination-one' {
        (Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report (New-BW4k7tHistoricForensic)).SourceZeroDestinationOneObserved | Should -BeTrue
    }
    It 'pinned historic unknown still unproven' {
        (Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report (New-BW4k7tHistoricForensic)).CompleteProductionRecipientAndUserStateCoverageEstablished | Should -BeFalse
    }
    It 'pinned historic never writer' {
        (Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report (New-BW4k7tHistoricForensic)).WriterPermit | Should -BeFalse
    }
    It 'wrong original evidence hash rejects' {
        $h=New-BW4k7tHistoricForensic; $h.OriginalPreMoveEvidenceSha256='0'*64; {Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report $h} | Should -Throw
    }
    It 'wrong original claim hash rejects' {
        $h=New-BW4k7tHistoricForensic; $h.OriginalIrreversibleClaimSha256='0'*64; {Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report $h} | Should -Throw
    }
    It 'wrong original raw flags rejects' {
        $h=New-BW4k7tHistoricForensic; $h.SourceRawMessageFlags=0; {Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report $h} | Should -Throw
    }
    It 'false proven meaning rejects' {
        $h=New-BW4k7tHistoricForensic; $h.RawFlag0x00010000MeaningEstablished=$true; {Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report $h} | Should -Throw
    }
    It 'historical new Move assertion rejects' {
        $h=New-BW4k7tHistoricForensic; $h.NoThirdMoveOrWriter=$false; {Assert-OPA265BW4k7tReadOnlyHistoricForensic -Report $h} | Should -Throw
    }
    It 'controller WhatIf no external Outlook contact' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1') -WhatIf; $r.Status | Should -BeExactly 'WhatIfPolicyOnlyNoEvidenceReadOrWrites'
    }
    It 'controller no evidence no fake positive' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1'); $r.Status | Should -BeExactly 'ProspectivePolicyOnlyNoPriorEvidenceProvidedNoWaiver'
    }
    It 'controller no writer no evidence' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1'); $r.WriterPermit | Should -BeFalse; $r.ProductionReady | Should -BeFalse
    }
    It 'controller synthetic case review no Move' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1') -SyntheticSemanticCase (New-BW4k7tSyntheticCase); $r.SyntheticCaseReview.CandidateForSeparateScopedOperatorRiskDecision | Should -BeTrue; $r.WriterPermit | Should -BeFalse
    }
    It 'controller historical nonmail three exact' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1') -PreviousBW4k7sReadOnlyResult (New-BW4k7tOperatorSReport); $r.PreviouslyObservedNonMailCount | Should -Be 3; $r.WriterPermit | Should -BeFalse
    }
    It 'controller historical year manifest six' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1') -PreviousBW4k7rFullInventory (New-BW4k7tOperatorRReport); $r.PreviousEligibleArchiveYearCount | Should -Be 6; $r.PreviousEligibleMailItems | Should -Be 21985
    }
    It 'controller optional historic forensic never production' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1') -HistoricBW4k7oForensicReport (New-BW4k7tHistoricForensic); $r.HistoricalExactForensicReview.SourceZeroDestinationOneObserved | Should -BeTrue; $r.ProductionReady | Should -BeFalse
    }
    It 'controller rejects forged current source item count' {
        $s=New-BW4k7tOperatorSReport; $s.NonMailItemsObserved=2; {& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1') -PreviousBW4k7sReadOnlyResult $s} | Should -Throw
    }
    It 'controller rejects partial previous year report' {
        $r=New-BW4k7tOperatorRReport; $r.YearDistributionComplete=$false; {& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1') -PreviousBW4k7rFullInventory $r} | Should -Throw
    }
    It 'controller does not contact Outlook or access registry' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1'); $s | Should -Not -Match 'GetActiveObject|GetNamespace|Get-ItemProperty|Get-Item -LiteralPath'
    }
    It 'controller never writes journal Move or registry' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1'); $s | Should -Not -Match '[.](Move|Save|Delete|SetProperty)[ ]*[(]|Set-ItemProperty|New-ItemProperty|WriteAll'
    }
    It 'controller risk decision remains unrecorded' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1'); $r.RiskDecisionRecordedOrPermittedByThisRun | Should -BeFalse
    }
    It 'controller historical hardblock preserved' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1'); $r.OldBW4k7oHistoricHardBlockPreserved | Should -BeTrue
    }
    It 'controller no atomic PST snapshot false claim' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1'); $r.OperatorReportsAreNotImmutablePstSnapshots | Should -BeTrue
    }
    It 'controller old irreversible move never retried' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7tSemanticAcceptanceReview.ps1'); $r.ExistingIrreversibleFixtureRetried | Should -BeFalse
    }
}
