#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4aHistoricalIntentIsolation265.ps1')
}
Describe 'BW4a: option-B single unresolved historical Intent permanent Worker isolation' {
    BeforeEach {
        $script:p=Get-OPA265BW3hPinnedChain
        $script:fakeSourceId='BW4A-TEST-SOURCE-ID'
        $script:archive='C:\BW4A-TEST-ARCHIVE.pst'
        $script:paths=[pscustomobject]@{
            RunId=[string]$script:p.RunId
            SourcePst=[string]$script:p.SourcePst
            ArchivePst=$script:archive
            Directory=('C:\Temp\OPA264-LIVE3-'+([guid]$script:p.RunId).ToString('N'))
        }
        $script:snapshot=[pscustomobject]@{
            Journal=[string]$script:p.JournalSha256
            ManualSizeAcceptance=[string]$script:p.AcceptanceFileSha256
        }
        $script:intent=[pscustomobject]@{
            SchemaVersion='1.0'
            TransactionId=[string]$script:p.RunId
            OperationId=[string]$script:p.OperationId
            Sequence=1
            Phase='Intent'
            OperationKind='MailMove'
            ArchivePst=$script:archive
            SourceEntryId=$script:fakeSourceId
            ArchiveEntryId=''
            InternetMessageId=('<opa264-live3-'+[string]$script:p.RunId+'@example.invalid>')
            Subject=('OPA264 LIVE3 synthetic '+[string]$script:p.RunId)
            Size=1436L
        }
        $script:fence=Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent
    }
    It 'produces pinned immutable Option B policy' {
        $script:fence.Schema | Should -BeExactly '2.6.5-BW4a.HistoricalWorkerIsolationFence.1'
        $script:fence.Policy | Should -BeExactly 'OptionBPreserveSingleIntentNeverRedispatch'
        $script:fence.RunId | Should -BeExactly $script:p.RunId
        $script:fence.JournalSha256 | Should -BeExactly $script:p.JournalSha256
    }
    It 'never authorizes worker dispatch, retry, or journal append' {
        $script:fence.WorkerDispatchAllowed | Should -BeFalse
        $script:fence.JournalReconciliationAuthorized | Should -BeFalse
        $script:fence.AutomaticRetryAllowed | Should -BeFalse
        $script:fence.ProductionReady | Should -BeFalse
        $script:fence.HistoricRetryBlocked | Should -BeTrue
    }
    It 'validates the exact full fence object' {
        (Assert-OPA265BW4aHistoricalFence -Fence $script:fence) | Should -BeTrue
    }
    It 'exact previous historical evidence is required to create a fence' {
        (Assert-OPA265BW4aHistoricalEvidence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent) | Should -BeTrue
    }
    It 'blocks Resume with the historical RunId before any worker' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Resume -TransactionId $script:p.RunId -SourcePst $script:p.SourcePst
        $r.Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
        $r.MatchedHistoricalIdentities | Should -Contain 'HistoricalRunId'
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'blocks a new Archive candidate sharing historical source PST while lacking per-item proof' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst $script:p.SourcePst
        $r.Status | Should -BeExactly 'BlockedSharedPstRequiresPerItemFencingInBW4b'
        $r.SharedSourcePst | Should -BeTrue
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'never authorizes an unrelated Archive candidate in BW4a' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other-Synthetic-PST.pst'
        $r.Status | Should -BeExactly 'UnrelatedCandidateDesignOnlyNotAuthorized'
        $r.CanDispatchWorker | Should -BeFalse
        $r.CanInvokeMailMove | Should -BeFalse
        $r.ArchiveResumeIntegrationActivated | Should -BeFalse
    }
    It 'does not authorize unrelated Resume either' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Resume -TransactionId ([guid]::NewGuid().ToString('D')) -SourcePst 'C:\Other-Synthetic-PST.pst'
        $r.Status | Should -BeExactly 'UnrelatedCandidateDesignOnlyNotAuthorized'
        $r.ProductionReady | Should -BeFalse
    }
    It 'blocks shared archive PST even if source differs' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other-Synthetic-PST.pst' -ArchivePst $script:archive
        $r.Status | Should -BeExactly 'BlockedSharedPstRequiresPerItemFencingInBW4b'
        $r.SharedArchivePst | Should -BeTrue
    }
    It 'blocks shared PST regardless of case' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst $script:p.SourcePst.ToUpperInvariant()
        $r.Status | Should -BeExactly 'BlockedSharedPstRequiresPerItemFencingInBW4b'
    }
    It 'marks exactly one historical Intent unresolved' {
        $script:fence.HistoricalJournalPhase | Should -BeExactly 'Intent'
        $script:fence.HistoricalJournalEventCount | Should -Be 1
    }
    It 'preserves admitted +8-size acceptance without journal permission' {
        $script:fence.AcceptanceRecordSha256 | Should -BeExactly $script:p.AcceptanceFileSha256
        $script:fence.JournalReconciliationAuthorized | Should -BeFalse
    }
    It 'blocks historic operation identity across a different PST' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other-Synthetic-PST.pst' -OperationId $script:p.OperationId
        $r.Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
        $r.MatchedHistoricalIdentities | Should -Contain 'HistoricalOperationId'
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'blocks historic worker request identity across a different PST' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other-Synthetic-PST.pst' -WorkerRequestId $script:p.WorkerRequestId
        $r.Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
        $r.MatchedHistoricalIdentities | Should -Contain 'HistoricalWorkerRequestId'
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'blocks historic journal sha identity across a different PST' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other-Synthetic-PST.pst' -JournalSha256 $script:p.JournalSha256
        $r.Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
        $r.MatchedHistoricalIdentities | Should -Contain 'HistoricalJournalSha256'
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'blocks historic source EntryId across a different PST' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other-Synthetic-PST.pst' -SourceEntryId $script:fakeSourceId
        $r.Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
        $r.MatchedHistoricalIdentities | Should -Contain 'HistoricalSourceEntryId'
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'blocks historic destination EntryId across a different PST' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other-Synthetic-PST.pst' -DestinationEntryId $script:p.DestinationEntryId
        $r.Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
        $r.MatchedHistoricalIdentities | Should -Contain 'HistoricalDestinationEntryId'
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'blocks historic InternetMessageId across a different PST' {
        $r=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other-Synthetic-PST.pst' -InternetMessageId $script:intent.InternetMessageId
        $r.Status | Should -BeExactly 'BlockedKnownHistoricalOperationNeverRetry'
        $r.MatchedHistoricalIdentities | Should -Contain 'HistoricalInternetMessageId'
        $r.CanDispatchWorker | Should -BeFalse
    }
    It 'rejects forged true flag JournalReconciliationAuthorized' {
        $script:fence.JournalReconciliationAuthorized=$true
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects untyped flag JournalReconciliationAuthorized' {
        $script:fence.JournalReconciliationAuthorized='False'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged true flag WorkerDispatchAllowed' {
        $script:fence.WorkerDispatchAllowed=$true
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects untyped flag WorkerDispatchAllowed' {
        $script:fence.WorkerDispatchAllowed='False'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged true flag AutomaticRetryAllowed' {
        $script:fence.AutomaticRetryAllowed=$true
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects untyped flag AutomaticRetryAllowed' {
        $script:fence.AutomaticRetryAllowed='False'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged true flag ProductionReady' {
        $script:fence.ProductionReady=$true
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects untyped flag ProductionReady' {
        $script:fence.ProductionReady='False'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects false required flag HistoricalMovePreviouslyConfirmed' {
        $script:fence.HistoricalMovePreviouslyConfirmed=$false
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects false required flag HistoricRetryBlocked' {
        $script:fence.HistoricRetryBlocked=$false
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence foreign run ID' {
        $script:fence.RunId='another'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence foreign operation ID' {
        $script:fence.OperationId='another'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence foreign worker request ID' {
        $script:fence.WorkerRequestId='another'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence foreign source PST' {
        $script:fence.SourcePst='C:\Other.pst'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence tampered original SHA' {
        $script:fence.JournalSha256='f'*64
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence tampered acceptance SHA' {
        $script:fence.AcceptanceRecordSha256='f'*64
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence changed archive destination' {
        $script:fence.DestinationEntryId='other'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence missing source EntryID' {
        $script:fence.SourceEntryId=''
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence empty archive PST' {
        $script:fence.ArchivePst=''
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence changed Message-ID' {
        $script:fence.InternetMessageId='<other@example.invalid>'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence wrong journal phase' {
        $script:fence.HistoricalJournalPhase='Reconciled'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence wrong journal event count' {
        $script:fence.HistoricalJournalEventCount=2
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence changed schema' {
        $script:fence.Schema='other'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence changed option B policy' {
        $script:fence.Policy='PermitRetry'
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence extra field' {
        $script:fence | Add-Member -NotePropertyName UserConsent -NotePropertyValue $true
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'rejects forged fence missing field' {
        $script:fence.PSObject.Properties.Remove('HistoricalJournalPhase')
        { Assert-OPA265BW4aHistoricalFence -Fence $script:fence } | Should -Throw
    }
    It 'refuses historical evidence with changed Intent phase' {
        $script:intent.Phase='Reconciled'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with changed Intent sequence' {
        $script:intent.Sequence=2
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with changed Intent operation type' {
        $script:intent.OperationKind='WorkerDiagnostic'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with changed Intent RunId' {
        $script:intent.TransactionId='other'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with changed Intent OperationId' {
        $script:intent.OperationId='other'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with changed original Size' {
        $script:intent.Size=1444
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with filled historical ArchiveEntryId' {
        $script:intent.ArchiveEntryId='unexpected'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with missing source identity' {
        $script:intent.SourceEntryId=''
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with changed archive path' {
        $script:intent.ArchivePst='C:\Other.pst'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with changed InternetMessageId' {
        $script:intent.InternetMessageId='<other@example.invalid>'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses historical evidence with changed Subject' {
        $script:intent.Subject='Other'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses evidence snapshot changed journal fingerprint' {
        $script:snapshot.Journal='f'*64
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses evidence snapshot changed +8 consent fingerprint' {
        $script:snapshot.ManualSizeAcceptance='f'*64
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses evidence snapshot wrong fixture directory' {
        $script:paths.Directory='C:\Temp\Wrong'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses evidence snapshot wrong source PST' {
        $script:paths.SourcePst='C:\Other.pst'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses evidence snapshot wrong archive binding' {
        $script:paths.ArchivePst='C:\Other.pst'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'refuses evidence snapshot wrong run id' {
        $script:paths.RunId='other'
        { Get-OPA265BW4aKnownHistoricalFence -Pinned $script:p -Paths $script:paths -Snapshot $script:snapshot -Intent $script:intent } | Should -Throw
    }
    It 'rejects Resume without transaction' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Resume -SourcePst 'C:\\Other.pst' } | Should -Throw '*transaction ID*'
    }
    It 'rejects Resume empty GUID' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Resume -TransactionId '00000000-0000-0000-0000-000000000000' -SourcePst 'C:\\Other.pst' } | Should -Throw '*transaction ID*'
    }
    It 'rejects Resume arbitrary text ID' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Resume -TransactionId 'LATEST' -SourcePst 'C:\\Other.pst' } | Should -Throw '*transaction ID*'
    }
    It 'rejects Archive with transaction ID' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -TransactionId $script:p.RunId -SourcePst 'C:\\Other.pst' } | Should -Throw '*cannot reuse*'
    }
    It 'rejects Archive empty source path' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst '' } | Should -Throw '*source PST*'
    }
    It 'rejects Archive relative source path' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'relative.pst' } | Should -Throw '*source PST*'
    }
    It 'rejects Archive non PST source' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\bad.txt' } | Should -Throw '*source PST*'
    }
    It 'rejects Archive UNC source' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst '\\server\share\bad.pst' } | Should -Throw '*source PST*'
    }
    It 'rejects malformed operation GUID' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other.pst' -OperationId 'invalid' } | Should -Throw '*nonempty GUID*'
    }
    It 'rejects malformed WorkerRequestId' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other.pst' -WorkerRequestId 'invalid' } | Should -Throw '*nonempty GUID*'
    }
    It 'rejects malformed hash' {
        { Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence -Mode Archive -SourcePst 'C:\Other.pst' -JournalSha256 'bad' } | Should -Throw '*journal fingerprint*'
    }
    It 'never authorizes automatic retry or moves for any candidate status' {
        $scenarios=@(
            @{Mode='Resume';TransactionId=[string]$script:p.RunId;SourcePst=[string]$script:p.SourcePst},
            @{Mode='Archive';SourcePst=[string]$script:p.SourcePst},
            @{Mode='Archive';SourcePst='C:\Other.pst'}
        )
        foreach($args in $scenarios) {
            $d=Get-OPA265BW4aWorkerBoundaryDecision -Fence $script:fence @args
            $d.HistoricalIntentQuarantined | Should -BeTrue
            $d.CanDispatchWorker | Should -BeFalse
            $d.CanInvokeMailMove | Should -BeFalse
            $d.CanAutomaticallyRetryHistoricalOperation | Should -BeFalse
            $d.HistoricJournalWritePermitIssued | Should -BeFalse
            $d.ArchiveResumeIntegrationActivated | Should -BeFalse
            $d.AutomaticRetryAllowed | Should -BeFalse
            $d.ProductionReady | Should -BeFalse
        }
    }
    It 'wires only opt-in worker pilot fence branch before first COM and MailMover in main CLI' {
        $t=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $t | Should -Match '\[switch\]\$WorkerPilotReviewHistoricalFence'
        $t | Should -Match 'if \(\$WorkerPilotReviewHistoricalFence\)'
        $t | Should -Match 'Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1'
        $t | Should -Match 'Assert-OPA265WorkerPilotGate'
        $t.IndexOf('Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1') | Should -BeLessThan $t.IndexOf('$session = New-OPAComSession')
        $t.IndexOf('Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1') | Should -BeLessThan $t.IndexOf('Move-OPAItemsWithLimit')
        $t | Should -Match 'WorkerPilotExpectedHistoricalJournalSha256'
    }
    It 'rejects pilot-only historic flag when WorkerPilot is off (structural gate)' {
        $t=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $t | Should -Match "ContainsKey\('WorkerPilotReviewHistoricalFence'\)"
        $t | Should -Match "ContainsKey\('WorkerPilotExpectedHistoricalJournalSha256'\)"
    }
    It 'does not modify production Worker entrypoint or expose a BW4a Move operation' {
        $t=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.Worker.ps1') -Raw
        $t | Should -Not -Match 'BW4aHistoricalIntentIsolation|BW4aWorkerMove'
    }
    It 'never implements file or PST writes in BW4a modules' {
        foreach($f in @('BW4aHistoricalIntentIsolation265.ps1','BW4aHistoricalFenceReadOnly265.ps1')) {
            $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot ('../../Core/Worker/'+$f)) -Raw
            $s | Should -Not -Match '\[IO.FileStream\]::new|WriteAllBytes|WriteAllText|Write-OPAOperationJournalEvent|\.Move\(|Outlook\.Application|GetActiveObject|New-Object -ComObject'
        }
    }
    It 'does not activate historical journal append or production via legacy LIVE6' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $start=$s.IndexOf('if ($WorkerPilotReviewHistoricalFence)')
        $end=$s.IndexOf('} elseif ($WorkerPilotProbeSynthetic)', $start)
        $branch=$s.Substring($start,$end-$start)
        $branch | Should -Not -Match 'Invoke-OPA264Live6|Move-OPAItems|New-OPAComSession|Invoke-OPAWorkerControlledOperation'
    }
    It 'standalone diagnostic requires explicit -Review and excludes Execute' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1') -Raw
        $s | Should -Match '\[switch\]\$Review'
        $s | Should -Not -Match '\[switch\]\$Execute|\[switch\]\$Record|\[IO.FileStream\]::new'
    }
    It 'BW4a native scripts each have exactly one UTF-8 BOM' {
        foreach($p in @('Core/Worker/BW4aHistoricalIntentIsolation265.ps1',
            'Core/Worker/BW4aHistoricalFenceReadOnly265.ps1',
            'Core/Diagnostics/Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1',
            'Tests/Worker/BW4aHistoricalIntentIsolation.Tests.ps1')) {
            $b=[IO.File]::ReadAllBytes((Join-Path (Join-Path $PSScriptRoot '../..') $p))
            ($b[0..2] -join ',') | Should -BeExactly '239,187,191'
            $b[3] | Should -Be 35
        }
    }
    It 'PowerShell 5.1 parser accepts new scripts and main CLI' {
        foreach($p in @('Core/Worker/BW4aHistoricalIntentIsolation265.ps1',
            'Core/Worker/BW4aHistoricalFenceReadOnly265.ps1',
            'Core/Diagnostics/Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1',
            'OutlookPOP3Archive.ps1')) {
            $tok=$null;$err=$null
            $null=[Management.Automation.Language.Parser]::ParseFile(
                (Join-Path (Join-Path $PSScriptRoot '../..') $p),[ref]$tok,[ref]$err)
            @($err).Count | Should -Be 0
        }
    }
}
