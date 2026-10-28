#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4aHistoricalIntentIsolation265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4bPerItemFence265.ps1')
}
Describe 'BW4b: per-item evidence fence before any Worker or Move' {
    BeforeEach {
        $p=Get-OPA265BW3hPinnedChain
        $script:src=[string]$p.SourcePst
        $script:fence=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4a.HistoricalWorkerIsolationFence.1';Policy='OptionBPreserveSingleIntentNeverRedispatch'
            RunId=$p.RunId;OperationId=$p.OperationId;WorkerRequestId=$p.WorkerRequestId;SourcePst=$p.SourcePst
            ArchivePst='C:\BW4b-archive.pst';JournalSha256=$p.JournalSha256
            AcceptanceRecordSha256=$p.AcceptanceFileSha256;SourceEntryId='old-historical-src'
            DestinationEntryId=$p.DestinationEntryId
            InternetMessageId=('<opa264-live3-'+$p.RunId+'@example.invalid>')
            HistoricalJournalEventCount=1;HistoricalJournalPhase='Intent';HistoricalMovePreviouslyConfirmed=$true
            JournalReconciliationAuthorized=$false;HistoricRetryBlocked=$true;WorkerDispatchAllowed=$false
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $script:a=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4b.PerItemWitness.1';CaptureId=[guid]::NewGuid().ToString('D')
            CaptureMethod='PrimaryReadOnly';SourcePst=$script:src;SourceStoreId='different-store'
            SourceEntryId='different-entry';InternetMessageId='<different@example.invalid>'
            SearchKeySha256=('a'*64);ContentSha256=('b'*64);ObservedItemCount=1
        }
        $script:b=$script:a.PSObject.Copy()
        $script:b.CaptureId=[guid]::NewGuid().ToString('D')
        $script:b.CaptureMethod='IndependentReadOnly'
    }
    It 'compares two consistent items in shared PST without dispatch' {
        $r=Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b
        $r.Status | Should -BeExactly 'PerItemEvidenceConsistentDesignOnlyNoWorkerDispatch'
        $r.PerItemEvidenceConsistent | Should -BeTrue
        $r.SharedHistoricalPst | Should -BeTrue
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'never issues worker move, journal write or production permit' {
        $r=Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b
        $r.CanInvokeMailMove | Should -BeFalse
        $r.CanWriteHistoricalJournal | Should -BeFalse
        $r.CanCreateHistoricalClaim | Should -BeFalse
        $r.IndependentOutlookReadbackVerified | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'blocks historical source EntryId from first witness' {
        $script:a.SourceEntryId=$script:fence.SourceEntryId
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
    }
    It 'blocks historical destination EntryId from second witness' {
        $script:b.SourceEntryId=$script:fence.DestinationEntryId
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
    }
    It 'blocks historical InternetMessageId even if other fields differ' {
        $script:a.InternetMessageId=$script:fence.InternetMessageId
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
    }
    It 'blocks historical Resume transaction before item comparison' {
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Resume -TransactionId $script:fence.RunId -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
    }
    It 'blocks missing first witness' {
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Independent $script:b).Status | Should -BeExactly 'BlockedMissingPerItemEvidence'
    }
    It 'blocks missing second witness' {
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a).Status | Should -BeExactly 'BlockedMissingPerItemEvidence'
    }
    It 'blocks conflicting EntryId' {
        $script:b.SourceEntryId='other'
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedConflictingPerItemEvidence'
    }
    It 'blocks conflicting content fingerprint' {
        $script:b.ContentSha256='c'*64
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedConflictingPerItemEvidence'
    }
    It 'blocks conflicting store identity' {
        $script:b.SourceStoreId='elsewhere'
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedConflictingPerItemEvidence'
    }
    It 'blocks reused witness capture Id' {
        $script:b.CaptureId=$script:a.CaptureId
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedUnverifiedPerItemEvidence'
    }
    It 'blocks invalid capture method' {
        $script:b.CaptureMethod='PrimaryReadOnly'
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedUnverifiedPerItemEvidence'
    }
    It 'blocks invalid SHA256' {
        $script:a.SearchKeySha256='wrong'
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedUnverifiedPerItemEvidence'
    }
    It 'blocks more than one observed item' {
        $script:a.ObservedItemCount=2
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedUnverifiedPerItemEvidence'
    }
    It 'blocks evidence from foreign PST' {
        $script:b.SourcePst='C:\elsewhere.pst'
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedUnverifiedPerItemEvidence'
    }
    It 'blocks forged extra permit field' {
        $script:b | Add-Member -NotePropertyName Permit -NotePropertyValue $true
        (Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b).Status | Should -BeExactly 'BlockedUnverifiedPerItemEvidence'
    }
    It 'rejects altered historic fence' {
        $script:fence.WorkerDispatchAllowed=$true
        { Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -SourcePst $script:src -Primary $script:a -Independent $script:b } | Should -Throw
    }
    It 'allows no Archive transaction reuse' {
        { Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Archive -TransactionId ([guid]::NewGuid().ToString('D')) -SourcePst $script:src -Primary $script:a -Independent $script:b } | Should -Throw
    }
    It 'keeps different Resume only in read-only mode' {
        $r=Get-OPA265BW4bPerItemDecision -Fence $script:fence -Mode Resume -TransactionId ([guid]::NewGuid().ToString('D')) -SourcePst $script:src -Primary $script:a -Independent $script:b
        $r.CanDispatchWorker | Should -BeFalse
        $r.HistoricalIntentStillUnresolved | Should -BeTrue
    }
}
