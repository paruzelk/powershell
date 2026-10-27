#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3iJournalResolutionPreflight265.ps1')
}
Describe 'BW3i read-only journal preflight, no authorization' {
    BeforeEach {
        $script:p=Get-OPA265BW3iPinnedScope
        $script:recordPath='C:\Users\bogoderov_e\AppData\Local\Temp\OPA264-LIVE3-a7b51427749443f4bc9664915f6bee7e\bw3g-manual-size-acceptance.json'
        $script:h=[pscustomobject][ordered]@{
            Schema='2.6.5-BW3h.IndependentDurableEvidenceChainReadOnly.1'
            Status='IndependentEvidenceChainVerifiedJournalDecisionPending'
            Decision='StopBeforeSeparateExplicitJournalReconciliationAuthorization'
            RunId=[string]$script:p.RunId
            OperationId=[string]$script:p.OperationId
            WorkerRequestId=[string]$script:p.WorkerRequestId
            OriginalIntentSha256=[string]$script:p.JournalSha256
            DestinationEntryId=[string]$script:p.DestinationEntryId
            ArchivedBodyUtf8Sha256=[string]$script:p.BodyUtf8Sha256
            AcceptanceRecordPath=$script:recordPath
            AcceptanceRecordSha256=[string]$script:p.AcceptanceFileSha256
            SevenDurableEvidenceHashesVerified=$true
            OriginalIntentUnchanged=$true
            WorkerDispatchClaimCorrelated=$true
            MoveAttemptClaimCorrelated=$true
            WorkerDestinationIdentityConfirmed=$true
            SourceItemCount=0
            ArchiveItemCount=1
            SyntheticAttachmentsCount=0
            BodyBaselinePlusSpaceCrLfConfirmed=$true
            IntentSizeBytes=1436L
            ArchivedSizeBytes=1444L
            ManuallyAcceptedSyntheticDifferenceBytes=8L
            ManualSizeAcceptancePersisted=$true
            SizeDiscrepancyCauseEstablished=$false
            BeforeMoveActualBodyHashAvailable=$false
            FullMAPIContentByteEqualityVerified=$false
            JournalReconciliationAuthorized=$false
            JournalWritePermitIssued=$false
            JournalChanged=$false
            JournalCompleted=$false
            JournalReconciled=$false
            OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
            NextAction='PreserveAllEvidenceAndRequireSeparateExplicitJournalDecision'
        }
        $script:l=[pscustomobject][ordered]@{
            Schema='2.6.4-LIVE6.JournalResolutionResult.1'
            RunId=[string]$script:p.RunId
            OperationId=[string]$script:p.OperationId
            Status='ReviewOnly'
            Decision='MoveConfirmed'
            CanExecute=$false
            CanExecuteWithExplicitSizeConsent=$true
            CrossPstSizeDiffers=$true
            IntentSizeBytes=1436L
            ObservedArchiveSizeBytes=1444L
            SizeDifferenceBytes=8L
            ArchiveEntryId=[string]$script:p.DestinationEntryId
            ExpectedJournalSha256=[string]$script:p.JournalSha256
            JournalEventCount=1
            JournalUnchanged=$true
            JournalReconciled=$false
            JournalChangedByThisInvocation=$false
            OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
        }
        $script:b=[pscustomobject][ordered]@{
            Journal=[string]$script:p.JournalSha256
            Request='a'*64
            Scope='b'*64
            MoveAttemptClaim='c'*64
            DispatchClaim='d'*64
            ControllerResult='e'*64
            ManualSizeAcceptance=[string]$script:p.AcceptanceFileSha256
        }
        $script:a=$script:b.PSObject.Copy()
        $script:j=[pscustomobject]@{
            JournalSha256=[string]$script:p.JournalSha256
            JournalEventCount=1
            IntentSequence=1
            IntentSizeBytes=1436L
            NextProtocolSequence=2
            ProposedNextPhase='Reconciled'
            Live6ResolutionClaimAbsent=$true
            JournalAppendEligibleByCurrentBytes=$true
            JournalAppendAuthorized=$false
        }
    }
    It 'rejects BW3h mutated historical RunId' {
        $script:h.RunId='other'
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h mutated OperationId' {
        $script:h.OperationId='other'
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h mutated request ID' {
        $script:h.WorkerRequestId='other'
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h wrong prior journal hash' {
        $script:h.OriginalIntentSha256='f'*64
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h wrong prior acceptance SHA256' {
        $script:h.AcceptanceRecordSha256='f'*64
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h wrong archive EntryID' {
        $script:h.DestinationEntryId='other'
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h wrong body SHA256' {
        $script:h.ArchivedBodyUtf8Sha256='f'*64
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h foreign acceptance path' {
        $script:h.AcceptanceRecordPath='C:\other\record.json'
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h invented journal approval field' {
        $script:h | Add-Member -NotePropertyName PermitToReconcile -NotePropertyValue $true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h missing field' {
        $script:h.PSObject.Properties.Remove('NextAction')
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h injected status' {
        $script:h.Status='AlreadyReconciled'
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h forged journal authorization' {
        $script:h.JournalReconciliationAuthorized=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h forged write permit' {
        $script:h.JournalWritePermitIssued=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h fabricated journal mutation' {
        $script:h.JournalChanged=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h fabricated journal completion' {
        $script:h.JournalCompleted=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h fabricated journal Reconciled' {
        $script:h.JournalReconciled=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h automatic retry' {
        $script:h.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h false production readiness' {
        $script:h.ProductionReady=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h changed size variance' {
        $script:h.ManuallyAcceptedSyntheticDifferenceBytes=9L
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h changed source count' {
        $script:h.SourceItemCount=1
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h changed archive count' {
        $script:h.ArchiveItemCount=2
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h attachment injected' {
        $script:h.SyntheticAttachmentsCount=1
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h lost claim correlation' {
        $script:h.WorkerDispatchClaimCorrelated=$false
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h lost acceptance confirmation' {
        $script:h.ManualSizeAcceptancePersisted=$false
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h fake full MAPI byte equality' {
        $script:h.FullMAPIContentByteEqualityVerified=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h fake original body hash' {
        $script:h.BeforeMoveActualBodyHashAvailable=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h fake size root cause' {
        $script:h.SizeDiscrepancyCauseEstablished=$true
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects BW3h string in Boolean status' {
        $script:h.SevenDurableEvidenceHashesVerified='True'
        { Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects changed LIVE6 status' {
        $script:l.Status='ReconciledJournalAppended'
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed LIVE6 review decision' {
        $script:l.Decision='InspectionFailed'
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects foreign LIVE6 RunId' {
        $script:l.RunId='other'
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects foreign LIVE6 OperationId' {
        $script:l.OperationId='other'
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects foreign archived EntryID' {
        $script:l.ArchiveEntryId='other'
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects different LIVE6 journal hash' {
        $script:l.ExpectedJournalSha256='f'*64
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects different LIVE6 archive size' {
        $script:l.ObservedArchiveSizeBytes=1445
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects different LIVE6 Intent size' {
        $script:l.IntentSizeBytes=1445
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects different LIVE6 size delta' {
        $script:l.SizeDifferenceBytes=0
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects non-single Intent event count' {
        $script:l.JournalEventCount=2
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects claim of executable without separate consent' {
        $script:l.CanExecute=$true
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects absence of technical +8 size gate' {
        $script:l.CanExecuteWithExplicitSizeConsent=$false
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects absence of size difference' {
        $script:l.CrossPstSizeDiffers=$false
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed journal' {
        $script:l.JournalUnchanged=$false
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects actual journal Reconciled' {
        $script:l.JournalReconciled=$true
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects journal mutation by LIVE6 Review' {
        $script:l.JournalChangedByThisInvocation=$true
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects Outlook Move by LIVE6 Review' {
        $script:l.OutlookMoveExecuted=$true
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects automatic retry' {
        $script:l.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects production enabled' {
        $script:l.ProductionReady=$true
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects extra untrusted approval field' {
        $script:l | Add-Member -NotePropertyName JournalWritePermit -NotePropertyValue $true
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects missing LIVE6 archive field' {
        $script:l.PSObject.Properties.Remove('ArchiveEntryId')
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects non-Boolean LIVE6 flag' {
        $script:l.CanExecuteWithExplicitSizeConsent='True'
        { Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed preflight journal hash' {
        $script:j.JournalSha256='f'*64
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects more than one Intent' {
        $script:j.JournalEventCount=2
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects different Intent sequence' {
        $script:j.IntentSequence=2
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects wrong Intent size' {
        $script:j.IntentSizeBytes=1444
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects wrong next protocol sequence' {
        $script:j.NextProtocolSequence=3
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects unknown next phase' {
        $script:j.ProposedNextPhase='Completed'
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects existing resolution claim' {
        $script:j.Live6ResolutionClaimAbsent=$false
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects append-unsafe original journal' {
        $script:j.JournalAppendEligibleByCurrentBytes=$false
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects claim of operator consent' {
        $script:j.JournalAppendAuthorized=$true
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects untyped journal authorization' {
        $script:j.JournalAppendAuthorized='False'
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'requires exact one-run historical pinned scope' {
        $script:p.RunId | Should -BeExactly 'a7b51427-7494-43f4-bc96-64915f6bee7e'
        $script:p.AcceptanceFileSha256 | Should -BeExactly 'c7b066436b03d5f9cd400ebf560c82852e46d943d15d276a2d42e3fa3fb01161'
        $script:p.JournalSha256 | Should -BeExactly '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648'
    }
    It 'accepts original complete BW3h and LIVE6 review shapes' {
        (Assert-OPA265BW3iBw3hVerdict -Verdict $script:h -Pinned $script:p -RecordPath $script:recordPath) | Should -BeTrue
        (Assert-OPA265BW3iLive6Review -Review $script:l -Pinned $script:p) | Should -BeTrue
    }
    It 'reports unambiguous pending decision, not journal permission' {
        $v=Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath
        $v.Status | Should -BeExactly 'JournalResolutionEvidenceReadySeparateAuthorizationRequired'
        $v.Decision | Should -BeExactly 'DoNotAppendReconciledWithoutNewExplicitUserAuthorization'
        $v.ProtocolNextSequence | Should -Be 2
        $v.ProposedNextPhase | Should -BeExactly 'Reconciled'
        $v.LegacyLive6CanExecuteWithExplicitSizeConsent | Should -BeTrue
        $v.LegacyLive6CanExecuteWithoutSizeConsent | Should -BeFalse
        $v.OperatorJournalAuthorizationGiven | Should -BeFalse
        $v.WriteableJournalPermitIssued | Should -BeFalse
        $v.JournalChanged | Should -BeFalse
        $v.JournalCompleted | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
        $v.OutlookMoveExecuted | Should -BeFalse
        $v.AutomaticRetryAllowed | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
    }
    It 'rejects an altered one of seven immutable evidence SHA256 values' {
        $script:a.DispatchClaim='f'*64
        { Get-OPA265BW3iDecisionDossier -Pinned $script:p -Bw3h $script:h -Live6Review $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'has no writable mode or Move call in BW3i diagnostic entrypoint' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3iJournalResolutionPreflight.ps1') -Raw
        $src | Should -Match '\[switch\]\$Review'
        $src | Should -Not -Match '\[switch\]\$Execute|\[switch\]\$Record|Write-OPA264Live6ReconciledLocked|New-OPA264Live6Claim|Write-OPAOperationJournalEvent|\.Move\(|\.Save\(|\.Delete\('
    }
    It 'always invokes old LIVE6 in Review, never Execute' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3iJournalResolutionPreflight.ps1') -Raw
        $src | Should -Match "Invoke-OPA264Live6JournalResolution.ps1'"
        $src | Should -Match '\$live6=& .*Invoke-OPA264Live6JournalResolution.ps1.*-Review'
        $src | Should -Not -Match 'Invoke-OPA264Live6JournalResolution.ps1.*-Execute'
    }
    It 'requires seven original hashes and resolution claim absence before and after Outlook audit' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3iJournalResolutionPreflight.ps1') -Raw
        $src | Should -Match '\$before=Get-OPA265BW3hEvidenceSnapshot'
        $src | Should -Match '\$after=Get-OPA265BW3hEvidenceSnapshot'
        $src | Should -Match 'Assert-OPA265BW3iSnapshotUnchanged|Assert-OPA265BW3hSnapshotUnchanged'
        $src | Should -Match 'Assert-OPA265BW3iIntentAppendPreconditions'
    }
    It 'contains no BW3i activation in production Archive Resume Auto' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $src | Should -Not -Match 'BW3iJournalResolutionPreflight'
    }
    It 'has BOM EF BB BF on every new BW3i PowerShell script' {
        foreach($rel in @('Core/Worker/BW3iJournalResolutionPreflight265.ps1',
            'Core/Diagnostics/Test-OPA265BW3iJournalResolutionPreflight.ps1',
            'Tests/Worker/BW3iJournalResolutionPreflight.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $bytes=[IO.File]::ReadAllBytes($path)
            ($bytes[0..2] -join ',') | Should -BeExactly '239,187,191'
        }
    }
    It 'parses BW3i source under native Windows PowerShell 5.1' {
        foreach($rel in @('Core/Worker/BW3iJournalResolutionPreflight265.ps1',
            'Core/Diagnostics/Test-OPA265BW3iJournalResolutionPreflight.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
