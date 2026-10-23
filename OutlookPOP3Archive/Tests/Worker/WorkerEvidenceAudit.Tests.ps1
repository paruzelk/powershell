#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerEvidenceAudit.ps1')
}
Describe '2.6.4-F machine-readable evidence audit, synthetic only (no Outlook COM)' {
    BeforeEach {
        $runId=[guid]::NewGuid().ToString('D')
        $operationId=[guid]::NewGuid().ToString('D')
        $artifacts=[pscustomobject]@{
            ControllerDispatchClaimPresent=$true
            WorkerMoveClaimPresent=$false
            CrashBarrier='NotRecorded'
            WorkerResponsePresent=$false
            ControllerResultPresent=$false
        }
        $recovery=[pscustomobject]@{
            Schema='2.6.4-D.1'
            RunId=$runId
            OperationId=$operationId
            Status='SourceOnly'
            SourceMatches=1
            DestinationMatches=0
            SourceScanComplete=$true
            DestinationScanComplete=$true
            JournalTrailingPartial=$false
            JournalLastSequence=[long]1
            Artifacts=$artifacts
            ProvenMoved=$false
            AutomaticRetryAllowed=$false
            JournalWriteAllowed=$false
            MailMoveAllowed=$false
            RequiresManualReview=$true
            Disposition='StopAndPreserveEvidence'
        }
        $identity=[pscustomobject]@{
            Schema='2.6.4-E.1'
            RunId=$runId
            Status='Stable'
            StoreIdChanged=$false
            FolderIdentityChanged=$false
            MailEntryIdChanged=$false
            MessageLocationChanged=$false
            SourceMatchesBefore=1
            SourceMatchesAfter=1
            ArchiveMatchesBefore=0
            ArchiveMatchesAfter=0
            AutomaticRetryAllowed=$false
            MailMoveAllowed=$false
            JournalWriteAllowed=$false
            AutomaticCompletionAllowed=$false
            ProvenMoved=$false
            RequiresManualReview=$true
            Disposition='StopAndPreserveEvidence'
        }
    }
    It 'accepts a correctly correlated fail-closed D recovery record' {
        (Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId) | Should -BeTrue
    }
    It 'rejects a different run ID' {
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId ([guid]::NewGuid().ToString('D')) -OperationId $operationId } | Should -Throw '*correlation*'
    }
    It 'rejects a different operation ID' {
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId ([guid]::NewGuid().ToString('D')) } | Should -Throw '*correlation*'
    }
    It 'rejects unrecognized recovery status' {
        $recovery.Status='AutomaticallyCompleted'
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*status*'
    }
    It 'rejects a recovery that claims a successful Move proof' {
        $recovery.ProvenMoved=$true
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*ProvenMoved*'
    }
    It 'rejects a recovery enabling automatic retry' {
        $recovery.AutomaticRetryAllowed=$true
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*AutomaticRetryAllowed*'
    }
    It 'rejects a recovery enabling MailMove' {
        $recovery.MailMoveAllowed=$true
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*MailMoveAllowed*'
    }
    It 'rejects absent manual-review requirement' {
        $recovery.RequiresManualReview=$false
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*manual*'
    }
    It 'rejects contradictory SourceOnly match counts' {
        $recovery.SourceMatches=0
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*contradicts*'
    }
    It 'rejects a post-Move barrier without durable one-shot claim' {
        $artifacts.CrashBarrier='AfterMoveBeforeResponse'
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*one-shot*'
    }
    It 'rejects an unknown barrier name' {
        $artifacts.CrashBarrier='ArbitraryProcessKill'
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*unrecognized*'
    }
    It 'rejects missing crash artifact record' {
        $recovery.Artifacts=$null
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*artifacts*'
    }
    It 'rejects excessive candidate counts' {
        $recovery.Status='Ambiguous'
        $recovery.SourceMatches=1000001
        { Assert-OPA264AuditRecovery -Recovery $recovery -RunId $runId -OperationId $operationId } | Should -Throw '*unreasonable*'
    }
    It 'returns a review-only report for SourceOnly' {
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId
        $r.Classification | Should -Be 'ReviewRequired'
        $r.ProductionReady | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'reports a destination candidate without claiming success' {
        $recovery.Status='DestinationCandidate'
        $recovery.SourceMatches=0
        $recovery.DestinationMatches=1
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId
        $r.Classification | Should -Be 'CandidateObserved'
        $r.IndependentMoveProof | Should -BeFalse
    }
    It 'treats a missing match on both sides as conflicting evidence' {
        $recovery.Status='MissingBoth'
        $recovery.SourceMatches=0
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId
        $r.Classification | Should -Be 'ConflictingEvidence'
    }
    It 'treats an incomplete snapshot as incomplete evidence' {
        $recovery.Status='IncompleteScan'
        $recovery.SourceScanComplete=$false
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId
        $r.Classification | Should -Be 'IncompleteEvidence'
    }
    It 'reports a missing requested crash barrier' {
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -ExpectedCrashWindow WorkerStartedBeforeMove
        $r.ScenarioEvidence | Should -Be 'BarrierMissing'
        $r.Classification | Should -Be 'EvidenceConflict'
    }
    It 'reports a mismatch with a different crash barrier' {
        $artifacts.CrashBarrier='WorkerStartedBeforeMove'
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -ExpectedCrashWindow AfterIntentBeforeDispatch
        $r.ScenarioEvidence | Should -Be 'BarrierMismatch'
    }
    It 'recognizes a matched recorded crash barrier without granting completion' {
        $artifacts.CrashBarrier='WorkerStartedBeforeMove'
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -ExpectedCrashWindow WorkerStartedBeforeMove
        $r.ScenarioEvidence | Should -Be 'BarrierRecorded'
        $r.AutomaticCompletionAllowed | Should -BeFalse
    }
    It 'does not silently discard an unexpected crash barrier' {
        $artifacts.CrashBarrier='AfterIntentBeforeDispatch'
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId
        $r.ScenarioEvidence | Should -Be 'UnexpectedBarrier'
        $r.Classification | Should -Be 'EvidenceConflict'
    }
    It 'accepts stable identity diagnostic data as a separate observation' {
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -Identity $identity
        $r.IdentityEvidence | Should -Be 'Stable'
        $r.ProductionReady | Should -BeFalse
    }
    It 'marks a changed PST StoreID as a manual-review identity change' {
        $identity.Status='StoreIdChanged'
        $identity.StoreIdChanged=$true
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -Identity $identity
        $r.Classification | Should -Be 'IdentityChanged'
    }
    It 'rejects an identity observation from a different run' {
        $identity.RunId=[guid]::NewGuid().ToString('D')
        { New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -Identity $identity } | Should -Throw '*mismatch*'
    }
    It 'rejects a false Stable claim with changed EntryID' {
        $identity.MailEntryIdChanged=$true
        { Assert-OPA264AuditIdentity -Identity $identity -RunId $runId } | Should -Throw '*contradicts*'
    }
    It 'rejects a positive journal-write flag from identity evidence' {
        $identity.JournalWriteAllowed=$true
        { Assert-OPA264AuditIdentity -Identity $identity -RunId $runId } | Should -Throw '*JournalWriteAllowed*'
    }
    It 'reports all four crash windows missing without supplied audits' {
        $r=Get-OPA264EvidenceCoverage
        @($r.MissingCrashWindows).Count | Should -Be 4
        $r.ProductionReady | Should -BeFalse
    }
    It 'counts one verified-barrier report as only one observed scenario' {
        $artifacts.CrashBarrier='AfterIntentBeforeDispatch'
        $audit=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -ExpectedCrashWindow AfterIntentBeforeDispatch
        $coverage=Get-OPA264EvidenceCoverage -Reports @($audit)
        @($coverage.ObservedBarrierWindows).Count | Should -Be 1
        @($coverage.MissingCrashWindows).Count | Should -Be 3
    }
    It 'does not count a missing barrier as completed scenario evidence' {
        $audit=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -ExpectedCrashWindow AfterMoveBeforeResponse
        @((Get-OPA264EvidenceCoverage -Reports @($audit)).ObservedBarrierWindows).Count | Should -Be 0
    }
    It 'treats a forged optimistic production-ready report as invalid' {
        $audit=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId
        $audit.ProductionReady=$true
        $coverage=Get-OPA264EvidenceCoverage -Reports @($audit)
        $coverage.InvalidReports | Should -Be 1
        $coverage.ProductionReady | Should -BeFalse
    }
    It 'keeps even reported complete barrier coverage non-production' {
        $windows=@('AfterIntentBeforeDispatch','WorkerStartedBeforeMove','AfterMoveBeforeResponse','AfterResponseBeforeTerminal')
        $reports=@()
        foreach ($w in $windows) {
            $report=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId -ExpectedCrashWindow $w
            $report.ScenarioEvidence='BarrierRecorded'
            $reports+= $report
        }
        $coverage=Get-OPA264EvidenceCoverage -Reports $reports
        @($coverage.MissingCrashWindows).Count | Should -Be 0
        $coverage.ProductionReady | Should -BeFalse
        $coverage.Readiness | Should -Be 'BlockedPendingRealOutlookTestsAndManualReview'
    }
    It 'does not include personal mail fingerprint or EntryID in the audit schema' {
        $r=New-OPA264EvidenceAudit -Recovery $recovery -RunId $runId -OperationId $operationId
        foreach ($field in @('Sender','Subject','InternetMessageId','SourceEntryId','ArchiveEntryId','MailBody')) {
            $r.PSObject.Properties.Name | Should -Not -Contain $field
        }
    }
    It 'keeps the diagnostic audit command free from Outlook mail mutations and journal writes' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264EvidenceAudit.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({
            param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object { [string]$_.Member.Value -in @('Move','Copy','Delete','Kill','AddStore','AddStoreEx','RemoveStore','Quit') }).Count | Should -Be 0
    }
}
