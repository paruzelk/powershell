#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4dHistoricalReplayAudit265.ps1')
}
Describe 'BW4d independent journal replay fence and complete no-Move quarantine' {
    BeforeEach {
        $script:review=[pscustomobject]@{
            Schema='2.6.5-BW4c.OutlookDualPathPerItemReadOnly.1'
            Status='OutlookReadOnlyDualPathEvidenceReviewedNoWorkerDispatch'
            CandidateStatus='PerItemEvidenceConsistentDesignOnlyNoWorkerDispatch'
            SevenHistoricalEvidenceHashesUnchanged=$true
            HistoricJournalEventCount=1
            HistoricJournalPhase='Intent'
            OutlookMoveExecuted=$false
            WorkerDispatchAllowed=$false
            CandidateEntryId='New-Entry'
            InternetMessageId='<new@example.invalid>'
            SourceStoreId='POP3-Store'
        }
        $script:history=[pscustomobject]@{
            Schema='2.6.5-BW4d.VisibleHistoryCatalog.1'
            HistoryReadOnly=$true
            CatalogComplete=$false
            JournalsScanned=1
            RunDirectoriesScanned=1
            ClaimOnlyDirectories=0
            Events=@()
        }
        $script:evt=[pscustomobject]@{
            RunDirectory='OPA264-LIVE3-11111111111111111111111111111111'
            TransactionId='11111111-1111-1111-1111-111111111111'
            OperationId='22222222-2222-2222-2222-222222222222'
            Phase='Intent'
            OperationKind='MailMove'
            SourceEntryId='old-entry'
            ArchiveEntryId=''
            InternetMessageId='<old@example.invalid>'
            SourceStoreId='POP3-Store'
        }
    }
    It 'no visible overlap never grants replay clearance or Move permission' {
        $r=Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history
        $r.Status | Should -BeExactly 'NoMatchingEventInVisibleHistoryCatalogStillNotReplayClearance'
        $r.CatalogComplete | Should -BeFalse
        $r.ReplaySafetyProven | Should -BeFalse
        $r.CanInvokeMailMove | Should -BeFalse
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'blocks a previously observed LIVE3 synthetic identity even without a file' {
        $script:review.InternetMessageId='<opa264-live3-e2399ba1-38e9-48e8-bf43-d39cc1c19edb@example.invalid>'
        $r=Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history
        $r.Status | Should -BeExactly 'BlockedSyntheticLive3OriginCannotProveNoEarlierMove'
        $r.SyntheticLive3Identity | Should -BeTrue
    }
    It 'blocks prior Intent with matching InternetMessageId' {
        $script:evt.InternetMessageId=$script:review.InternetMessageId
        $script:history.Events=@($script:evt)
        $r=Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history
        $r.Status | Should -BeExactly 'BlockedKnownPriorLive3Live4OperationEvidence'
        $r.HistoricalOperationMatches.Count | Should -Be 1
    }
    It 'blocks prior completed event with matching source EntryID' {
        $script:evt.SourceEntryId=$script:review.CandidateEntryId
        $script:evt.Phase='Completed'
        $script:history.Events=@($script:evt)
        (Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history).Status | Should -BeExactly 'BlockedKnownPriorLive3Live4OperationEvidence'
    }
    It 'blocks prior destination entry ID even without matching MessageId' {
        $script:evt.ArchiveEntryId=$script:review.CandidateEntryId
        $script:history.Events=@($script:evt)
        (Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history).Status | Should -BeExactly 'BlockedKnownPriorLive3Live4OperationEvidence'
    }
    It 'blocks a failed or crash-indeterminate prior operation' {
        $script:evt.InternetMessageId=$script:review.InternetMessageId
        $script:evt.Phase='Indeterminate'
        $script:history.Events=@($script:evt)
        (Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history).CanRetryPreviousMove | Should -BeFalse
    }
    It 'rejects a synthetic identity without a trusted history catalog' {
        $script:review.InternetMessageId='<opa264-live3-a7b51427-7494-43f4-bc96-64915f6bee7e@example.invalid>'
        $script:history.JournalsScanned=0
        (Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history).CanRetryPreviousMove | Should -BeFalse
    }
    It 'rejects a prior Outlook Move flag' {
        $script:review.OutlookMoveExecuted=$true
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects a prior Worker Dispatch flag' {
        $script:review.WorkerDispatchAllowed=$true
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects changed historic evidence hash assertion' {
        $script:review.SevenHistoricalEvidenceHashesUnchanged=$false
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects original historic journal changed to Reconciled' {
        $script:review.HistoricJournalPhase='Reconciled'
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects more than one historical journal event' {
        $script:review.HistoricJournalEventCount=2
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects an untrusted BW4c readback status' {
        $script:review.CandidateStatus='BlockedKnownHistoricalOperationNeverRetry'
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects forged complete history catalog' {
        $script:history.CatalogComplete=$true
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects forged history write permit' {
        $script:history.HistoryReadOnly=$false
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects missing observed candidate EntryID' {
        $script:review.CandidateEntryId=''
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects missing InternetMessageId' {
        $script:review.InternetMessageId=''
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'rejects missing POP3 store identity' {
        $script:review.SourceStoreId=''
        {Get-OPA265BW4dReplayDecision -Bw4cReview $script:review -History $script:history} | Should -Throw
    }
    It 'returns an empty bounded history catalog without modifying disk' {
        $dir=Join-Path $TestDrive 'empty-history'
        [void][IO.Directory]::CreateDirectory($dir)
        $r=Get-OPA265BW4dHistoryCatalog -HistoryRoot $dir
        $r.RunDirectoriesScanned | Should -Be 0
        $r.JournalsScanned | Should -Be 0
        $r.CatalogComplete | Should -BeFalse
        $r.EvidenceSnapshotSha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'rejects missing catalog root without creating it' {
        $missing=Join-Path $TestDrive 'not-existing'
        {Get-OPA265BW4dHistoryCatalog -HistoryRoot $missing} | Should -Throw
        [IO.Directory]::Exists($missing) | Should -BeFalse
    }
};
