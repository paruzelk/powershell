#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3fManualSizeDossier265.ps1')
}
Describe 'BW3f immutable one-run synthetic manual decision packet (NO consent)' {
    BeforeEach {
        $script:p=Get-OPA265BW3ePinnedTailEvidence
        $script:a=[pscustomobject]@{
            Schema='2.6.5-BW3e.SyntheticBodyTailReadOnlyEvidence.1'
            Status='SyntheticBodyTailSpaceCrLfConfirmed'
            Decision='BodyTailEvidenceOnlySizeDifferenceStillUnapproved'
            RunId=$script:p.RunId
            OperationId=$script:p.OperationId
            WorkerRequestId=$script:p.WorkerRequestId
            JournalSha256=$script:p.JournalSha256
            ArchivedMailEntryId=$script:p.ArchiveEntryId
            ExpectedBaselineBodyLength=50
            ObservedBodyLength=53
            ExpectedBodyLength=53
            ObservedTailUnicodeCodeUnits=[int[]]@(32,13,10)
            ExpectedTailUnicodeCodeUnits=[int[]]@(32,13,10)
            ExpectedTailUtf8Bytes=[int[]]@(32,13,10)
            ObservedBodyUtf8Sha256=$script:p.ExpectedBodySha256
            ExpectedObservedBodyUtf8Sha256=$script:p.ExpectedBodySha256
            BodyTextMatchesExactBaselinePlusSpaceCrLf=$true
            TailSpaceCrLfConfirmed=$true
            NormalizedByRemovingExactlyThreeSuffixCharsMatchesBaseline=$true
            TrailingSpaceBeforeCrLfObserved=$true
            IntentSizeBytes=1436L
            ArchivedSizeBytes=1444L
            UnapprovedSizeDifferenceBytes=8L
            PrMessageSizeMatchedMailItemSize=$true
            SourceItemCount=0
            ArchiveItemCount=1
            AttachmentsCount=0
            ArchiveEntryIdMatchesWorker=$true
            ClaimsCorrelated=$true
            BeforeMoveActualBodyHashAvailable=$false
            WhenTailWasIntroducedEstablished=$false
            SizeDifferenceCauseEstablished=$false
            ContentByteEqualityVerified=$false
            ArchiveSizeDifferenceApproved=$false
            ManualJournalDecisionAuthorized=$false
            RequiresManualSizeReview=$true
            OutlookMoveExecuted=$false
            JournalChanged=$false
            JournalCompleted=$false
            JournalReconciled=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
            NextAction='PreserveIntentClaimsAndAwaitExplicitIndependentSizeDecision'
        }
    }
    It 'accepts exactly matching historical BW3e evidence' {
        (Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p) | Should -BeTrue
    }
    It 'rejects a foreign RunId' {
        $script:a.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign OperationId' {
        $script:a.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign WorkerRequestId' {
        $script:a.WorkerRequestId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a changed durable Intent SHA256' {
        $script:a.JournalSha256='1'*64
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign archive EntryID' {
        $script:a.ArchivedMailEntryId='WRONG-ENTRY'
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a fake BW3e status' {
        $script:a.Status='ArchiveApproved'
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a fake BW3e schema' {
        $script:a.Schema='Wrong'
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a fake BW3e decision' {
        $script:a.Decision='AutomaticallyAccepted'
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects different observed archival size' {
        $script:a.ArchivedSizeBytes=1436
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects different original Intent size' {
        $script:a.IntentSizeBytes=1444
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects unexpected 8-byte drift value' {
        $script:a.UnapprovedSizeDifferenceBytes=0
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a different observed body SHA256' {
        $script:a.ObservedBodyUtf8Sha256='a'*64
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a different baseline body length' {
        $script:a.ExpectedBaselineBodyLength=49
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a different observed body length' {
        $script:a.ObservedBodyLength=52
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects duplicated synthetic mail' {
        $script:a.ArchiveItemCount=2
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects remaining synthetic source mail' {
        $script:a.SourceItemCount=1
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a changed attachment count' {
        $script:a.AttachmentsCount=1
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects uncorrelated durable claims' {
        $script:a.ClaimsCorrelated=$false
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects lack of matching EntryID' {
        $script:a.ArchiveEntryIdMatchesWorker=$false
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects fabricated previous before-Move body hash' {
        $script:a.BeforeMoveActualBodyHashAvailable=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects fabricated established suffix timing' {
        $script:a.WhenTailWasIntroducedEstablished=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects fabricated 8-byte cause explanation' {
        $script:a.SizeDifferenceCauseEstablished=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects previous claimed content byte equality' {
        $script:a.ContentByteEqualityVerified=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects preapproved size difference' {
        $script:a.ArchiveSizeDifferenceApproved=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects previous manual journal consent' {
        $script:a.ManualJournalDecisionAuthorized=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects completed original journal' {
        $script:a.JournalCompleted=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects reconciled original journal' {
        $script:a.JournalReconciled=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects automatic retry enabled' {
        $script:a.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects production readiness' {
        $script:a.ProductionReady=$true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects size review silently disabled' {
        $script:a.RequiresManualSizeReview=$false
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects unexpected suffix integer' {
        $script:a.ObservedTailUnicodeCodeUnits=[int[]]@(32,13,11)
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects suffix as string instead of int array' {
        $script:a.ObservedTailUnicodeCodeUnits='32,13,10'
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a shortened suffix array' {
        $script:a.ObservedTailUnicodeCodeUnits=[int[]]@(13,10)
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects an unexpected additional field' {
        $script:a | Add-Member -NotePropertyName AutoApprove -NotePropertyValue $true
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a removed mandatory evidence field' {
        $script:a.PSObject.Properties.Remove('ClaimsCorrelated')
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects a Boolean encoded as string' {
        $script:a.ClaimsCorrelated='True'
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed pinned journal hash' {
        $script:p.JournalSha256='b'*64
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed pinned source PST path' {
        $script:p.SourcePst='C:\Other.pst'
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed pinned archive size' {
        $script:p.ArchiveSizeBytes=1436
        { Assert-OPA265BW3fHistoricalAudit -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'outputs no size approval or journal authorization even if all evidence matches' {
        $v=Get-OPA265BW3fDecisionDossier -Audit $script:a -Pinned $script:p
        $v.Status | Should -BeExactly 'EvidenceDossierReadyHumanDecisionPending'
        $v.SizeDifferenceApproved | Should -BeFalse
        $v.HumanSizeDecisionRecorded | Should -BeFalse
        $v.HumanSizeDecisionValue | Should -BeExactly 'Unrecorded'
        $v.ManualJournalDecisionAuthorized | Should -BeFalse
        $v.WriteableReconciliationPermitIssued | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
        $v.AdditionalExplicitOperatorConsentRequired | Should -BeTrue
    }
    It 'explains absent baseline byte hash and unidentified MAPI size cause' {
        $v=Get-OPA265BW3fDecisionDossier -Audit $script:a -Pinned $script:p
        $v.BeforeMoveActualBodyHashCaptured | Should -BeFalse
        $v.TimingOfBodySuffixEstablished | Should -BeFalse
        $v.CauseOfMAPIByteSizeDriftEstablished | Should -BeFalse
        $v.MAPIStreamOrFullItemByteEqualityVerified | Should -BeFalse
        $v.UnapprovedSizeDifferenceBytes | Should -Be 8
    }
    It 'keeps all original run identifiers intact' {
        $v=Get-OPA265BW3fDecisionDossier -Audit $script:a -Pinned $script:p
        $v.RunId | Should -BeExactly $script:p.RunId
        $v.OperationId | Should -BeExactly $script:p.OperationId
        $v.WorkerRequestId | Should -BeExactly $script:p.WorkerRequestId
        $v.JournalSha256 | Should -BeExactly $script:p.JournalSha256
        $v.DestinationEntryId | Should -BeExactly $script:p.ArchiveEntryId
    }
    It 'does not accept a mismatched prior observation to create any dossier' {
        $script:a.BodyTextMatchesExactBaselinePlusSpaceCrLf=$false
        { Get-OPA265BW3fDecisionDossier -Audit $script:a -Pinned $script:p } | Should -Throw
    }
    It 'has UTF-8 BOM for every new PowerShell source and test' {
        foreach($rel in @('Core/Worker/BW3fManualSizeDossier265.ps1',
            'Core/Diagnostics/Test-OPA265BW3fManualSizeDecisionDossier.ps1',
            'Tests/Worker/BW3fManualSizeDecisionDossier.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $bytes=[IO.File]::ReadAllBytes($path)
            ($bytes[0..2] -join ',') | Should -BeExactly '239,187,191'
        }
    }
    It 'contains no synthetic Move, file output or manual resolution path' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3fManualSizeDecisionDossier.ps1'
        $src=Get-Content -LiteralPath $path -Raw
        $src | Should -Not -Match '(?i)\.Move\(|\.Save\(|\.Delete\(|AddStoreEx\(|Write-OPAOperationJournalEvent|Write-OPA264Live6ReconciledLocked|SetProperty\(|WriteAllText\(|WriteAllBytes\(|Add-Content|Set-Content|Out-File'
    }
    It 'only evaluates prior BW3e read-only audit before creating a dossier' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3fManualSizeDecisionDossier.ps1'
        $src=Get-Content -LiteralPath $path -Raw
        $src | Should -Match "'Test-OPA265BW3eSyntheticBodyTailAudit.ps1'"
        ($src.IndexOf("'Test-OPA265BW3eSyntheticBodyTailAudit.ps1'") -lt $src.IndexOf('Get-OPA265BW3fDecisionDossier -Audit')) | Should -BeTrue
    }
    It 'compares six evidence hashes before and after chained read-only inspection' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3fManualSizeDecisionDossier.ps1') -Raw
        $src | Should -Match '[$]extra[.]DispatchClaimPath'
        $src | Should -Match '[$]extra[.]ControllerResultPath'
        $src | Should -Match '[$]paths[.]JournalPath'
        $src | Should -Match '[$]before[[][$]file[]]'
    }
    It 'does not alter production Archive Resume or Auto integration' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $src | Should -Not -Match 'BW3fManualSize'
    }
    It 'parses two new BW3f PowerShell files without errors in Windows PS5.1' {
        foreach($rel in @('Core/Worker/BW3fManualSizeDossier265.ps1',
            'Core/Diagnostics/Test-OPA265BW3fManualSizeDecisionDossier.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
