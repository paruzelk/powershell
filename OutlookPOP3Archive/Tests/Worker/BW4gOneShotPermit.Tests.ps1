#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4aHistoricalIntentIsolation265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4bPerItemFence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4cOutlookReadOnlyCapture265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4gOneShotPermit265.ps1')
}
Describe 'BW4g: exact BW4f review must precede any separately approved disposable Move' {
    BeforeEach {
        $script:guid='98bef817-0fb5-478a-b869-33f02fda59d3'
        $script:review=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4f.DisposableFixtureScopeReadOnly.1'
            Status='DisposableFixtureScopeConsistentButNoMovePermit'
            TestId=$script:guid
            CandidateEntryId='00AABBCC'
            InternetMessageId='<unique-disposable@example.invalid>'
            IsExactOperatorFixture=$true
            TargetedMessageIdReadOnlyUsed=$true
            SevenHistoricalEvidenceHashesUnchanged=$true
            HistoricalEvidenceFilesUnchanged=$true
            HistoricJournalPhase='Intent'
            HistoricJournalEventCount=1
            WorkerDispatchAllowed=$false
            OutlookMoveExecuted=$false
            CanRetryPreviousMove=$false
            CanInvokeMailMove=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
        }
    }
    It 'validates exact historical and disposable review while leaving no Move permission in the review object' {
        (Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00aabbcc' -InternetMessageId '<unique-disposable@example.invalid>') | Should -BeTrue
        $script:review.CanInvokeMailMove | Should -BeFalse
    }
    It 'rejects a previous Live3 or other blocked review' {
        $script:review.Status='BlockedByHistoricalOrPinnedEvidence'
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
    It 'rejects an arbitrary real customer email' {
        $script:review.IsExactOperatorFixture=$false
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
    It 'rejects mismatched operator TestId' {
        $script:review.TestId='49bf59da-6d84-4e36-8b6d-0d9857b8eed1'
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
    It 'rejects changed candidate EntryID' {
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBDE' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
    It 'rejects changed InternetMessageId' {
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<wrong@example.invalid>'} | Should -Throw
    }
    It 'rejects original immutable seven evidence files changed' {
        $script:review.SevenHistoricalEvidenceHashesUnchanged=$false
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
    It 'rejects original Intent journal changed to Reconciled' {
        $script:review.HistoricJournalPhase='Reconciled'
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
    It 'rejects forged Worker approval' {
        $script:review.WorkerDispatchAllowed=$true
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
    It 'rejects forged previous retry approval' {
        $script:review.CanRetryPreviousMove=$true
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
    It 'rejects old unbounded scan in place of BW4e2 exact MAPI restriction' {
        $script:review.TargetedMessageIdReadOnlyUsed=$false
        {Assert-OPA265BW4gReady -Review $script:review -TestId $script:guid -CandidateEntryId '00AABBCC' -InternetMessageId '<unique-disposable@example.invalid>'} | Should -Throw
    }
}
Describe 'BW4g: durable attempt filename is per-fixture GUID and fail closed' {
    It 'derives stable one-attempt claim name from TestId, never from arbitrary RunId' {
        $g='98bef817-0fb5-478a-b869-33f02fda59d3'
        $path=Get-OPA265BW4gClaimPath -TestId $g -LocalAppData 'C:\test-local-appdata'
        $path | Should -BeExactly 'C:\test-local-appdata\OutlookPOP3Archive-BW4g-Claims\fixture-98bef817-0fb5-478a-b869-33f02fda59d3.json'
    }
    It 'refuses invalid or zero GUID claim filename' {
        {Get-OPA265BW4gClaimPath -TestId 'invalid'} | Should -Throw
        {Get-OPA265BW4gClaimPath -TestId ([guid]::Empty.ToString('D'))} | Should -Throw
    }
    It 'refuses redirecting durable claim to an unrelated path' {
        $obj=[pscustomobject]@{Schema='2.6.5-BW4g.ImmutableOneShotClaim.1';TestId='98bef817-0fb5-478a-b869-33f02fda59d3';AutomaticRetryAllowed=$false;ProductionReady=$false}
        {Write-OPA265BW4gOneShotClaim -ClaimPath (Join-Path $TestDrive 'fake.claim') -Claim $obj} | Should -Throw '*cannot be redirected*'
    }
    It 'durably creates exactly one claim under isolated temporary per-user AppData' {
        $original=$env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA=Join-Path $TestDrive 'test-appdata'
            $g='98bef817-0fb5-478a-b869-33f02fda59d3'
            $path=Get-OPA265BW4gClaimPath -TestId $g
            $obj=[pscustomobject]@{Schema='2.6.5-BW4g.ImmutableOneShotClaim.1';TestId=$g;AutomaticRetryAllowed=$false;ProductionReady=$false}
            $saved=Write-OPA265BW4gOneShotClaim -ClaimPath $path -Claim $obj
            $saved | Should -BeExactly $path
            (Test-Path -LiteralPath $path) | Should -BeTrue
            (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).TestId | Should -BeExactly $g
        } finally { $env:LOCALAPPDATA=$original }
    }
    It 'never permits reusing an already claimed disposable fixture GUID' {
        $original=$env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA=Join-Path $TestDrive 'test-appdata'
            $g='98bef817-0fb5-478a-b869-33f02fda59d3'
            $path=Get-OPA265BW4gClaimPath -TestId $g
            $obj=[pscustomobject]@{Schema='2.6.5-BW4g.ImmutableOneShotClaim.1';TestId=$g;AutomaticRetryAllowed=$false;ProductionReady=$false}
            [void](Write-OPA265BW4gOneShotClaim -ClaimPath $path -Claim $obj)
            $before=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            {Write-OPA265BW4gOneShotClaim -ClaimPath $path -Claim $obj} | Should -Throw
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -BeExactly $before
        } finally { $env:LOCALAPPDATA=$original }
    }
    It 'refuses a payload with any automatic retry permission' {
        $obj=[pscustomobject]@{Schema='2.6.5-BW4g.ImmutableOneShotClaim.1';TestId='98bef817-0fb5-478a-b869-33f02fda59d3';AutomaticRetryAllowed=$true;ProductionReady=$false}
        {Write-OPA265BW4gOneShotClaim -ClaimPath (Join-Path $TestDrive 'fake.claim') -Claim $obj} | Should -Throw '*claim payload invalid*'
    }
}
Describe 'BW4g: BW4b backward compatible exact 10-field and 12-field witness acceptance' {
    BeforeEach {
        $p=Get-OPA265BW3hPinnedChain
        $script:source=[string]$p.SourcePst
        $script:fence=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4a.HistoricalWorkerIsolationFence.1';Policy='OptionBPreserveSingleIntentNeverRedispatch'
            RunId=$p.RunId;OperationId=$p.OperationId;WorkerRequestId=$p.WorkerRequestId;SourcePst=$p.SourcePst
            ArchivePst='C:\BW4g-fixture.pst';JournalSha256=$p.JournalSha256
            AcceptanceRecordSha256=$p.AcceptanceFileSha256;SourceEntryId='old-historical-src'
            DestinationEntryId=$p.DestinationEntryId;InternetMessageId=('<opa264-live3-'+$p.RunId+'@example.invalid>')
            HistoricalJournalEventCount=1;HistoricalJournalPhase='Intent';HistoricalMovePreviouslyConfirmed=$true
            JournalReconciliationAuthorized=$false;HistoricRetryBlocked=$true;WorkerDispatchAllowed=$false
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $script:a=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4b.PerItemWitness.1';CaptureId=[guid]::NewGuid().ToString('D')
            CaptureMethod='PrimaryReadOnly';SourcePst=$script:source;SourceStoreId='test-store'
            SourceEntryId='test-entry';InternetMessageId='<fresh@example.invalid>'
            SearchKeySha256=('a'*64);ContentSha256=('b'*64);ObservedItemCount=1
        }
        $script:b=$script:a.PSObject.Copy()
        $script:b.CaptureId=[guid]::NewGuid().ToString('D')
        $script:b.CaptureMethod='IndependentReadOnly'
    }
    It 'retains legacy exact ten-field witness acceptance' {
        $r=Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:source -Primary $script:a -Independent $script:b
        $r.Status | Should -BeExactly 'PerItemEvidenceConsistentDesignOnlyNoWorkerDispatch'
    }
    It 'accepts exact twelve fields with matching real BW4f TestId' {
        $id='98bef817-0fb5-478a-b869-33f02fda59d3'
        foreach($w in @($script:a,$script:b)){
            $w | Add-Member NoteProperty IsExactOperatorFixture $true
            $w | Add-Member NoteProperty ObservedOperatorTestId $id
        }
        $r=Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:source -Primary $script:a -Independent $script:b
        $r.Status | Should -BeExactly 'PerItemEvidenceConsistentDesignOnlyNoWorkerDispatch'
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'rejects forged extra thirteenth permit field' {
        foreach($w in @($script:a,$script:b)){
            $w | Add-Member NoteProperty IsExactOperatorFixture $false
            $w | Add-Member NoteProperty ObservedOperatorTestId ''
        }
        $script:a | Add-Member NoteProperty Permit $true
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:source -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedUnverifiedPerItemEvidence'
    }
    It 'rejects mismatched TestId in separate Outlook read paths' {
        $script:a | Add-Member NoteProperty IsExactOperatorFixture $true
        $script:a | Add-Member NoteProperty ObservedOperatorTestId '98bef817-0fb5-478a-b869-33f02fda59d3'
        $script:b | Add-Member NoteProperty IsExactOperatorFixture $true
        $script:b | Add-Member NoteProperty ObservedOperatorTestId '49bf59da-6d84-4e36-8b6d-0d9857b8eed1'
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:source -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedConflictingPerItemEvidence'
    }
    It 'rejects noncanonical synthetic marker GUID' {
        foreach($w in @($script:a,$script:b)){
            $w | Add-Member NoteProperty IsExactOperatorFixture $true
            $w | Add-Member NoteProperty ObservedOperatorTestId 'bad'
        }
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:source -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedUnverifiedPerItemEvidence'
    }
}
