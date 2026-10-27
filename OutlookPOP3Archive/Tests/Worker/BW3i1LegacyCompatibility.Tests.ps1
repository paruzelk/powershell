#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3iJournalResolutionPreflight265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live4CrashProtocol.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3i1LegacyCompatibility265.ps1')
}
Describe 'BW3i1 - legacy LIVE4 crash protocol inapplicable to BW3 synthetic Worker one-shot Move' {
    BeforeEach {
        $script:p=Get-OPA265BW3iPinnedScope
        $script:recordPath='C:\Users\bogoderov_e\AppData\Local\Temp\OPA264-LIVE3-a7b51427749443f4bc9664915f6bee7e\bw3g-manual-size-acceptance.json'
        $script:l=[pscustomobject][ordered]@{
            Schema='2.6.4-LIVE6.JournalResolutionResult.1'
            RunId=[string]$script:p.RunId
            OperationId=[string]$script:p.OperationId
            Status='ReviewOnly'
            Decision='InspectionFailed'
            CanExecute=$false
            CanExecuteWithExplicitSizeConsent=$false
            CrossPstSizeDiffers=$false
            IntentSizeBytes=0L
            ObservedArchiveSizeBytes=0L
            SizeDifferenceBytes=0L
            ArchiveEntryId=''
            ExpectedJournalSha256=[string]$script:p.JournalSha256
            JournalEventCount=1
            JournalUnchanged=$true
            JournalReconciled=$false
            JournalChangedByThisInvocation=$false
            OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
        }
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
        $script:temp=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:temp)
        $script:paths=[pscustomobject]@{Directory=$script:temp}
    }
    It 'rejects legacy LIVE6 returns claimed MoveConfirmed' {
        $script:l.Decision='MoveConfirmed'
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return AlreadyReconciled' {
        $script:l.Status='AlreadyReconciled'
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return an unknown schema' {
        $script:l.Schema='AnotherSchema'
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return another RunId' {
        $script:l.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return another OperationId' {
        $script:l.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return a changed original journal hash' {
        $script:l.ExpectedJournalSha256='f'*64
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return a positive archive EntryID despite InspectionFailed' {
        $script:l.ArchiveEntryId='OTHER'
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return unintended original size' {
        $script:l.IntentSizeBytes=1436L
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return unintended archived size' {
        $script:l.ObservedArchiveSizeBytes=1444L
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return unintended delta' {
        $script:l.SizeDifferenceBytes=8L
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return two journal events' {
        $script:l.JournalEventCount=2
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 claim technical executable status' {
        $script:l.CanExecute=$true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 claim size-approved executable status' {
        $script:l.CanExecuteWithExplicitSizeConsent=$true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 claim observed size difference without evidence' {
        $script:l.CrossPstSizeDiffers=$true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return changed-journal flag' {
        $script:l.JournalUnchanged=$false
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 return existing Reconciled' {
        $script:l.JournalReconciled=$true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 claim review-time journal mutation' {
        $script:l.JournalChangedByThisInvocation=$true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 claim review-time Outlook Move' {
        $script:l.OutlookMoveExecuted=$true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 allow automatic retry' {
        $script:l.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 report production readiness' {
        $script:l.ProductionReady=$true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 report string instead of Boolean' {
        $script:l.JournalUnchanged='True'
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 omit original journal proof' {
        $script:l.PSObject.Properties.Remove('ExpectedJournalSha256')
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'rejects legacy LIVE6 add fabricated approval' {
        $script:l | Add-Member -NotePropertyName JournalWritePermit -NotePropertyValue $true
        { Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p } | Should -Throw
    }
    It 'accepts exact blocked legacy LIVE6 Review-only verdict' {
        (Assert-OPA265BW3i1InapplicableLive6Review -Review $script:l -Pinned $script:p) | Should -BeTrue
    }
    It 'read-only detects absent LIVE4 crash files in a synthetic fixture' {
        (Assert-OPA265BW3i1LegacyCrashArtifactsAbsent -Paths $script:paths) | Should -BeTrue
    }
    It 'fails closed on LIVE4 crash barrier appearing unexpectedly' {
        $path=Join-Path $script:temp 'crash-barrier.json'
        [IO.File]::WriteAllText($path,'{}')
        { Assert-OPA265BW3i1LegacyCrashArtifactsAbsent -Paths $script:paths } | Should -Throw
        [IO.File]::Exists($path) | Should -BeTrue
    }
    It 'fails closed on LIVE4 dispatch claim appearing unexpectedly' {
        $path=Join-Path $script:temp 'controller-dispatch.claim'
        [IO.File]::WriteAllText($path,'partial')
        { Assert-OPA265BW3i1LegacyCrashArtifactsAbsent -Paths $script:paths } | Should -Throw
        [IO.File]::Exists($path) | Should -BeTrue
    }
    It 'fails closed on legacy LIVE4 controller result appearing unexpectedly' {
        $path=Join-Path $script:temp 'controller-result.json'
        [IO.File]::WriteAllText($path,'{}')
        { Assert-OPA265BW3i1LegacyCrashArtifactsAbsent -Paths $script:paths } | Should -Throw
        [IO.File]::Exists($path) | Should -BeTrue
    }
    It 'does NOT claim all journal preconditions ready even when BW3 is proved' {
        $v=Get-OPA265BW3i1LegacyCompatibilityDossier -Pinned $script:p -Bw3h $script:h -LegacyReview $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -RecordPath $script:recordPath
        $v.Status | Should -BeExactly 'HistoricalBW3EvidenceVerifiedLegacyLive6ExecutorBlocked'
        $v.Decision | Should -BeExactly 'DoNotUseLegacyLIVE6ExecuteForHistoricalBW3aRun'
        $v.HistoricBw3hEvidenceChainVerified | Should -BeTrue
        $v.LegacyLive4ControlledCrashArtifactsAbsent | Should -BeTrue
        $v.LegacyLive6ApplicableToHistoricalBw3a | Should -BeFalse
        $v.LegacyLive6CanExecute | Should -BeFalse
        $v.LegacyLive6CanExecuteWithExplicitSizeConsent | Should -BeFalse
        $v.ManualSizeAcceptancePersisted | Should -BeTrue
        $v.JournalReconciliationAuthorized | Should -BeFalse
        $v.WriteableJournalPermitIssued | Should -BeFalse
        $v.JournalChanged | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
        $v.OutlookMoveExecuted | Should -BeFalse
        $v.AutomaticRetryAllowed | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
    }
    It 'rejects fabricated prior BW3h success' {
        $script:h.JournalWritePermitIssued=$true
        { Get-OPA265BW3i1LegacyCompatibilityDossier -Pinned $script:p -Bw3h $script:h -LegacyReview $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects changed original journal SHA256' {
        $script:a.Journal='f'*64
        { Get-OPA265BW3i1LegacyCompatibilityDossier -Pinned $script:p -Bw3h $script:h -LegacyReview $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects changed size acceptance JSON' {
        $script:a.ManualSizeAcceptance='f'*64
        { Get-OPA265BW3i1LegacyCompatibilityDossier -Pinned $script:p -Bw3h $script:h -LegacyReview $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects forged journal append permission' {
        $script:j.JournalAppendAuthorized=$true
        { Get-OPA265BW3i1LegacyCompatibilityDossier -Pinned $script:p -Bw3h $script:h -LegacyReview $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -RecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects forged absent resolution claim' {
        $script:j.Live6ResolutionClaimAbsent=$false
        { Get-OPA265BW3i1LegacyCompatibilityDossier -Pinned $script:p -Bw3h $script:h -LegacyReview $script:l -JournalPreflight $script:j -SnapshotBefore $script:b -SnapshotAfter $script:a -RecordPath $script:recordPath } | Should -Throw
    }
    It 'has no writable switch or LIVE6 Execute in BW3i1 entrypoint' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3i1LegacyCompatibilityReadOnly.ps1') -Raw
        $src | Should -Match '\[switch\]\$Review'
        $src | Should -Not -Match '\[switch\]\$Record|\[switch\]\$Execute|Write-OPA264Live6ReconciledLocked|New-OPA264Live6Claim|\.Move\(|\.Save\(|\.Delete\(|Write-OPAOperationJournalEvent'
        $src | Should -Match "Invoke-OPA264Live6JournalResolution.ps1'"
        $src | Should -Match '\$legacyReview=& .*Invoke-OPA264Live6JournalResolution.ps1.*-Review'
    }
    It 'has no production entrypoint integration for BW3i1' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $src | Should -Not -Match 'BW3i1LegacyCompatibilityReadOnly'
    }
    It 'requires UTF8 BOM for all new BW3i1 PowerShell code' {
        foreach($rel in @('Core/Worker/BW3i1LegacyCompatibility265.ps1',
            'Core/Diagnostics/Test-OPA265BW3i1LegacyCompatibilityReadOnly.ps1',
            'Tests/Worker/BW3i1LegacyCompatibility.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $bytes=[IO.File]::ReadAllBytes($path)
            ($bytes[0..2] -join ',') | Should -BeExactly '239,187,191'
        }
    }
    It 'parses both BW3i1 files under native PowerShell 5.1' {
        foreach($rel in @('Core/Worker/BW3i1LegacyCompatibility265.ps1',
            'Core/Diagnostics/Test-OPA265BW3i1LegacyCompatibilityReadOnly.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
