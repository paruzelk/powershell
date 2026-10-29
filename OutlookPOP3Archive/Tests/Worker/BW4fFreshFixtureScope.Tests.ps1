#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4fFreshFixtureScope265.ps1')
    $script:testGuid='98bef817-0fb5-478a-b869-33f02fda59d3'
    $script:subject='OPA265 BW4e1 FRESH TEST '+$script:testGuid
    $script:body=('OPA265 BW4e1 disposable synthetic test.'+[char]13+[char]10+
        'TestId: '+$script:testGuid+[char]13+[char]10+'This message contains no customer data.')
}
Describe 'BW4f exact disposable Outlook fixture tag' {
    It 'recognizes exactly matching subject, body, GUID and zero attachments' {
        $r=Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:body -AttachmentCount 0
        $r.IsExactOperatorFixture | Should -BeTrue
        $r.SubjectBodyExactTagMatched | Should -BeTrue
        $r.AttachmentsAbsentProven | Should -BeTrue
        $r.TestId | Should -BeExactly $script:testGuid
    }
    It 'rejects ordinary client mail even if copied body header' {
        (Get-OPA265BW4fFixtureTag -Subject 'Customer' -Body $script:body -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects invalid subject GUID' {
        (Get-OPA265BW4fFixtureTag -Subject 'OPA265 BW4e1 FRESH TEST invalid' -Body $script:body -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects subject GUID mismatching body GUID' {
        $sub=$script:subject.Replace($script:testGuid,'49bf59da-6d84-4e36-8b6d-0d9857b8eed1')
        (Get-OPA265BW4fFixtureTag -Subject $sub -Body $script:body -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects missing body header' {
        $b=$script:body.Replace('OPA265 BW4e1 disposable synthetic test.','not-fixture')
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $b -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects missing body TestId' {
        $b=$script:body.Replace('TestId: ','Other: ')
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $b -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects duplicate body TestId tags' {
        $b=$script:body+[char]10+'TestId: '+$script:testGuid
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $b -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects even one attachment' {
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:body -AttachmentCount 1).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects unverifiable attachments count' {
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:body).IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects malformed attachments count' {
        (Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:body -AttachmentCount 'bad').IsExactOperatorFixture | Should -BeFalse
    }
    It 'rejects zero GUID fixture' {
        $z=[guid]::Empty.ToString('D')
        (Get-OPA265BW4fFixtureTag -Subject ($script:subject.Replace($script:testGuid,$z)) -Body ($script:body.Replace($script:testGuid,$z)) -AttachmentCount 0).IsExactOperatorFixture | Should -BeFalse
    }
}
Describe 'BW4f real BW4c witness must not fake attachment absence' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../../Core/Worker/BW4cOutlookReadOnlyCapture265.ps1')
    }
    BeforeEach {
        $script:folder=[pscustomobject]@{EntryID='00112244';StoreID='00CCCCFF'}
        $script:accessor=[pscustomobject]@{MessageId='<new-test@example.invalid>';Key=[byte[]](1,2,3)}
        $script:accessor | Add-Member ScriptMethod GetProperty {
            param($name)
            if ($name -eq 'http://schemas.microsoft.com/mapi/proptag/0x1035001F'){return $this.MessageId}
            if ($name -eq 'http://schemas.microsoft.com/mapi/proptag/0x300B0102'){return $this.Key}
            throw 'Unknown MAPI property'
        }
        $script:mail=[pscustomobject]@{
            Class=43;EntryID='00AABBCC';Parent=$script:folder
            PropertyAccessor=$script:accessor
            Size=[long]512;ReceivedTime=[datetime]'2026-10-28T11:00:00'
            Subject=$script:subject;SenderEmailAddress='self@example.invalid'
            Body=$script:body
        }
    }
    It 'does not interpret absent Attachments COM collection as 0 attachments' {
        $w=Get-OPA265BW4cItemWitness -Mail $script:mail -SourcePst 'C:\fixture.pst' -StoreId '00CCCCFF' -FolderEntryId '00112244' -CandidateEntryId '00AABBCC' -Method PrimaryReadOnly
        $w.IsExactOperatorFixture | Should -BeFalse
    }
    It 'recognizes exact fixture when Outlook proves actual Attachments.Count equals zero' {
        $script:mail | Add-Member NoteProperty Attachments ([pscustomobject]@{Count=0})
        $w=Get-OPA265BW4cItemWitness -Mail $script:mail -SourcePst 'C:\fixture.pst' -StoreId '00CCCCFF' -FolderEntryId '00112244' -CandidateEntryId '00AABBCC' -Method PrimaryReadOnly
        $w.IsExactOperatorFixture | Should -BeTrue
        $w.ObservedOperatorTestId | Should -BeExactly $script:testGuid
    }
}
Describe 'BW4f historical no-Move gate after BW4e2 targeted read-only' {
    BeforeEach {
        $script:review=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4e.FreshSyntheticCandidatePreMoveReadOnly.1'
            Status='FreshCandidatePinsConsistentButNoProofOfNewnessOrMovePermit'
            IsExactOperatorFixture=$true
            ObservedOperatorTestId=$script:testGuid
            CandidateEntryId='00AABB'
            InternetMessageId='<new@example.invalid>'
            TargetedMessageIdReadOnlyUsed=$true
            FolderItemsObserved=26485
            HistoryEvidenceFilesUnchanged=$true
            SevenHistoricalEvidenceHashesUnchanged=$true
            HistoricJournalEventCount=1
            HistoricJournalPhase='Intent'
            HistoricalJournalChanged=$false
            HistoricalClaimCreated=$false
            WorkerDispatchAllowed=$false
            OutlookMoveExecuted=$false
            CanRetryPreviousMove=$false
            CanInvokeMailMove=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
            HistoryCatalogComplete=$false
            IndependentlyAuthenticatedExternalMAPIContent=$false
        }
    }
    It 'recognizes scoped fixture without permitting Move Worker or retry' {
        $r=Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid
        $r.Status | Should -BeExactly 'DisposableFixtureScopeConsistentButNoMovePermit'
        $r.IsExactOperatorFixture | Should -BeTrue
        $r.CanInvokeMailMove | Should -BeFalse
        $r.CanDispatchWorker | Should -BeFalse
        $r.CanRetryPreviousMove | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'blocks a different explicit operator GUID' {
        (Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId '49bf59da-6d84-4e36-8b6d-0d9857b8eed1').Status | Should -BeExactly 'BlockedNotExactDisposableFixture'
    }
    It 'blocks non-fixture mail' {
        $script:review.IsExactOperatorFixture=$false
        (Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid).Status | Should -BeExactly 'BlockedNotExactDisposableFixture'
    }
    It 'blocks any known prior Live3 historical operation' {
        $script:review.Status='BlockedPreviouslyUsedSyntheticOrKnownOperation'
        (Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid).Status | Should -BeExactly 'BlockedByHistoricalOrPinnedEvidence'
    }
    It 'blocks differing exact operator pins' {
        $script:review.Status='BlockedCandidateEvidenceNotMatchingPriorReadOnlyPins'
        (Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid).Status | Should -BeExactly 'BlockedByHistoricalOrPinnedEvidence'
    }
    It 'blocks absent BW4e2 targeted MAPI readback' {
        $script:review.TargetedMessageIdReadOnlyUsed=$false
        (Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid).Status | Should -BeExactly 'BlockedNeedsExplicitTargetedOutlookReadOnly'
    }
    It 'rejects invalid GUID' {
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId 'bad'} | Should -Throw
    }
    It 'rejects noncanonical uppercase GUID' {
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid.ToUpperInvariant()} | Should -Throw
    }
    It 'rejects original BW3a Intent changed' {
        $script:review.HistoricJournalPhase='Reconciled'
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid} | Should -Throw
    }
    It 'rejects seven pinned historical hashes changed' {
        $script:review.SevenHistoricalEvidenceHashesUnchanged=$false
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid} | Should -Throw
    }
    It 'rejects historical file snapshot drift' {
        $script:review.HistoryEvidenceFilesUnchanged=$false
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid} | Should -Throw
    }
    It 'rejects any forged Worker dispatch flag' {
        $script:review.WorkerDispatchAllowed=$true
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid} | Should -Throw
    }
    It 'rejects any forged MailItem.Move flag' {
        $script:review.CanInvokeMailMove=$true
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid} | Should -Throw
    }
    It 'rejects any automatic retry flag' {
        $script:review.AutomaticRetryAllowed=$true
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid} | Should -Throw
    }
    It 'rejects forged history completeness or external proof' {
        $script:review.HistoryCatalogComplete=$true
        {Get-OPA265BW4fScopeDecision -Bw4eReview $script:review -ExpectedTestId $script:testGuid} | Should -Throw
    }
}
