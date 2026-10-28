#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4cOutlookReadOnlyCapture265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4eFreshSyntheticCandidate265.ps1')
    function Invoke-BW4eCandidateTest {
        Get-OPA265BW4eFreshCandidateDecision -Bw4dReview $script:bw4d -CandidateReviewId $script:reviewId -HistoricalRunId $script:historicalId -ExpectedCandidateEntryId $script:pinEntry -ExpectedInternetMessageId $script:pinMsg -ExpectedSearchKeySha256 $script:pinSearch -ExpectedContentFingerprintSha256 $script:pinContent
    }
}
Describe 'BW4e exact read-only candidate pins and permanent no-Move fence' {
    BeforeEach {
        $script:historicalId='a7b51427-7494-43f4-bc96-64915f6bee7e'
        $script:reviewId='49bf59da-6d84-4e36-8b6d-0d9857b8eed1'
        $script:pinEntry='00AABBCC'
        $script:pinMsg='<new-bw4e-manually-created@example.invalid>'
        $script:pinSearch=('a'*64)
        $script:pinContent=('b'*64)
        $script:bw4d=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4d.IndependentJournalReplayReviewReadOnly.1'
            Status='IndependentReadOnlyJournalAndOutlookEvidenceReviewedNoMovePermit'
            CandidateStatus='NoMatchingEventInVisibleHistoryCatalogStillNotReplayClearance'
            CandidateEntryId='00aabbcc'
            InternetMessageId=$script:pinMsg
            SourceStoreId='POP3-test-store'
            SourceItemFingerprintSha256=$script:pinContent
            SearchKeySha256=$script:pinSearch
            HistoricalOperationMatches=@()
            SyntheticLive3Identity=$false
            HistoryEvidenceFilesUnchanged=$true
            HistoryCatalogComplete=$false
            IndependentlyAuthenticatedExternalMAPIContent=$false
            ReplaySafetyProven=$false
            SevenHistoricalEvidenceHashesUnchanged=$true
            HistoricJournalEventCount=1
            HistoricJournalPhase='Intent'
            HistoricalJournalChanged=$false
            HistoricalClaimCreated=$false
            WorkerDispatchAllowed=$false
            OutlookMoveExecuted=$false
            CanRetryPreviousMove=$false
            ProductionReady=$false
        }
    }
    It 'recognizes exact time-separated MAPI pins without claiming fresh Move safety' {
        $r=Invoke-BW4eCandidateTest
        $r.Status | Should -BeExactly 'FreshCandidatePinsConsistentButNoProofOfNewnessOrMovePermit'
        $r.PriorReadOnlyPinsMatch | Should -BeTrue
        $r.CandidateNewnessIndependentlyProven | Should -BeFalse
        $r.ReplaySafetyProven | Should -BeFalse
    }
    It 'never permits Worker, Move, journal writer or automatic replay' {
        $r=Invoke-BW4eCandidateTest
        $r.CanDispatchWorker | Should -BeFalse
        $r.CanInvokeMailMove | Should -BeFalse
        $r.CanWriteHistoricalJournal | Should -BeFalse
        $r.CanRetryPreviousMove | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'treats prior LIVE3/4 operation match as permanent block' {
        $script:bw4d.CandidateStatus='BlockedKnownPriorLive3Live4OperationEvidence'
        $script:bw4d.HistoricalOperationMatches=@('OPA264-LIVE3-run:op:Intent')
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedPreviouslyUsedSyntheticOrKnownOperation'
    }
    It 'blocks previous synthetic Live3 even when its journal has vanished' {
        $script:bw4d.CandidateStatus='BlockedSyntheticLive3OriginCannotProveNoEarlierMove'
        $script:bw4d.SyntheticLive3Identity=$true
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedPreviouslyUsedSyntheticOrKnownOperation'
    }
    It 'rejects a different candidate EntryID' {
        $script:bw4d.CandidateEntryId='00AABBCE'
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedCandidateEvidenceNotMatchingPriorReadOnlyPins'
    }
    It 'rejects a different InternetMessageId' {
        $script:bw4d.InternetMessageId='<different@example.invalid>'
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedCandidateEvidenceNotMatchingPriorReadOnlyPins'
    }
    It 'rejects a different PR_SEARCH_KEY digest' {
        $script:bw4d.SearchKeySha256='c'*64
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedCandidateEvidenceNotMatchingPriorReadOnlyPins'
    }
    It 'rejects a different content-field digest' {
        $script:bw4d.SourceItemFingerprintSha256='c'*64
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedCandidateEvidenceNotMatchingPriorReadOnlyPins'
    }
    It 'accepts only hex-letter-case-equivalent EntryID, never arbitrary case folding' {
        (Invoke-BW4eCandidateTest).PriorReadOnlyPinsMatch | Should -BeTrue
        $script:pinEntry='AB_CD'
        $script:bw4d.CandidateEntryId='ab_cd'
        (Invoke-BW4eCandidateTest).PriorReadOnlyPinsMatch | Should -BeFalse
    }
    It 'detects known Live3 identity even if BW4d candidate status was fabricated as no-match' {
        $script:bw4d.InternetMessageId='<opa264-live3-e2399ba1-38e9-48e8-bf43-d39cc1c19edb@example.invalid>'
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedPreviouslyUsedSyntheticOrKnownOperation'
    }
    It 'blocks nonempty historical matches even with a no-match verdict field' {
        $script:bw4d.HistoricalOperationMatches=@('source:operation:Intent')
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedPreviouslyUsedSyntheticOrKnownOperation'
    }
    It 'rejects forged historical journal Reconciled' {
        $script:bw4d.HistoricJournalPhase='Reconciled'
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects historical journal event count drift' {
        $script:bw4d.HistoricJournalEventCount=2
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects tampered original seven historical evidence hashes' {
        $script:bw4d.SevenHistoricalEvidenceHashesUnchanged=$false
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects changed LIVE3/4 journal evidence files during readback' {
        $script:bw4d.HistoryEvidenceFilesUnchanged=$false
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects historical claim creation' {
        $script:bw4d.HistoricalClaimCreated=$true
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects forged Worker permission' {
        $script:bw4d.WorkerDispatchAllowed=$true
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects any Outlook Move flag' {
        $script:bw4d.OutlookMoveExecuted=$true
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects forged complete history' {
        $script:bw4d.HistoryCatalogComplete=$true
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects external MAPI proof falsely claimed by a same-session read' {
        $script:bw4d.IndependentlyAuthenticatedExternalMAPIContent=$true
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects prior move retry permission' {
        $script:bw4d.CanRetryPreviousMove=$true
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects an unrecognized BW4d history status' {
        $script:bw4d.CandidateStatus='Unknown'
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects absent PR_SEARCH_KEY evidence' {
        $script:bw4d.SearchKeySha256=''
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects using historical RunId as new candidate review ID' {
        $script:reviewId=$script:historicalId
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects invalid new candidate review GUID' {
        $script:reviewId='not-a-guid'
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects malformed operator fingerprint' {
        $script:pinContent='not-sha256'
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects malformed operator InternetMessageId' {
        $script:pinMsg='no-angle-brackets-or-at'
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'rejects malicious mismatched BW4d schema' {
        $script:bw4d.Schema='2.6.5-BW4b.PerItemFenceDecision.1'
        {Invoke-BW4eCandidateTest} | Should -Throw
    }
    It 'does not treat previous synthetic marker as a fresh candidate merely because pins match' {
        $script:pinMsg='<opa264-live3-77854a93-ecfd-42c7-b58e-2948fe9afa88@example.invalid>'
        $script:bw4d.InternetMessageId=$script:pinMsg
        (Invoke-BW4eCandidateTest).Status | Should -BeExactly 'BlockedPreviouslyUsedSyntheticOrKnownOperation'
    }
}
