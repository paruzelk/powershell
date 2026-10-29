#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4aHistoricalIntentIsolation265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4bPerItemFence265.ps1')
}
Describe 'BW4f1: BW4b witness compatibility (no Move or Worker)' {
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
