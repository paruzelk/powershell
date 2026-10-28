﻿#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3iJournalResolutionPreflight265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live4CrashProtocol.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3jResolutionDesign265.ps1')
}
Describe 'BW3j - pinned one-shot BW3 journal resolution DESIGN only, no journal writer' {
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
        $script:paths=[pscustomobject]@{Directory=$script:temp;RunId=[string]$script:p.RunId;SourcePst=[string]$script:p.SourcePst}
        $script:j=[pscustomobject][ordered]@{
            Schema='2.6.5-BW3j.OriginalIntentReadOnly.1'
            RunId=[string]$script:p.RunId
            OperationId=[string]$script:p.OperationId
            JournalSha256=[string]$script:p.JournalSha256
            JournalEventCount=1
            OriginalPhase='Intent'
            OriginalSequence=1
            OriginalSizeBytes=1436L
            ProposedNextSequence=2
            ProposedNextPhase='Reconciled'
            FutureBw3jResolutionClaimAbsent=$true
            LegacyLive6ResolutionClaimAbsent=$true
            AutomaticRetryBlocked=$true
            ReconciliationAuthorized=$false
        }
    }
    It 'rejects original Intent schema changed' {
        $script:j.Schema='Other'
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent wrong RunId' {
        $script:j.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent wrong OperationId' {
        $script:j.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent wrong Intent fingerprint' {
        $script:j.JournalSha256='f'*64
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent two events' {
        $script:j.JournalEventCount=2
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent wrong phase' {
        $script:j.OriginalPhase='Reconciled'
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent wrong sequence' {
        $script:j.OriginalSequence=2
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent wrong Intent size' {
        $script:j.OriginalSizeBytes=1444L
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent wrong proposed sequence' {
        $script:j.ProposedNextSequence=3
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent wrong proposed terminal phase' {
        $script:j.ProposedNextPhase='Completed'
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent existing future BW3j claim' {
        $script:j.FutureBw3jResolutionClaimAbsent=$false
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent existing legacy LIVE6 claim' {
        $script:j.LegacyLive6ResolutionClaimAbsent=$false
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent automatic retry unblocked' {
        $script:j.AutomaticRetryBlocked=$false
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent falsely granted journal reconciliation' {
        $script:j.ReconciliationAuthorized=$true
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent missing journal field' {
        $script:j.PSObject.Properties.Remove('JournalSha256')
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent forged approval field' {
        $script:j | Add-Member -NotePropertyName JournalWritePermit -NotePropertyValue $true
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent string instead of Boolean' {
        $script:j.FutureBw3jResolutionClaimAbsent='True'
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects original Intent numeric instead of Boolean' {
        $script:j.ReconciliationAuthorized=0
        { Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p } | Should -Throw
    }
    It 'rejects fabricated BW3h write permit' {
        $script:h.JournalWritePermitIssued=$true
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects fake BW3h reconciliation' {
        $script:h.JournalReconciled=$true
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects mismatched acceptance SHA' {
        $script:h.AcceptanceRecordSha256='f'*64
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects foreign archived EntryID' {
        $script:h.DestinationEntryId='Wrong'
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects unapproved size delta' {
        $script:h.ManuallyAcceptedSyntheticDifferenceBytes=9L
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects incorrect archived count' {
        $script:h.ArchiveItemCount=2
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects forged ByteEquality' {
        $script:h.FullMAPIContentByteEqualityVerified=$true
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects retry allowed' {
        $script:h.AutomaticRetryAllowed=$true
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects production enabled' {
        $script:h.ProductionReady=$true
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects false persisted acceptance' {
        $script:h.ManualSizeAcceptancePersisted=$false
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects mutation to original Intent durable hash' {
        $script:a.Journal='f'*64
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects mutation to fixture request durable hash' {
        $script:a.Request='f'*64
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects mutation to fixture scope durable hash' {
        $script:a.Scope='f'*64
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects mutation to Move attempt claim durable hash' {
        $script:a.MoveAttemptClaim='f'*64
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects mutation to dispatch claim durable hash' {
        $script:a.DispatchClaim='f'*64
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects mutation to controller result durable hash' {
        $script:a.ControllerResult='f'*64
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects mutation to accepted size JSON durable hash' {
        $script:a.ManualSizeAcceptance='f'*64
        { Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath } | Should -Throw
    }
    It 'pins the original historical Intent and approved 8-byte exception' {
        $script:p.RunId | Should -BeExactly 'a7b51427-7494-43f4-bc96-64915f6bee7e'
        $script:p.JournalSha256 | Should -BeExactly '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648'
        $script:p.AcceptanceFileSha256 | Should -BeExactly 'c7b066436b03d5f9cd400ebf560c82852e46d943d15d276a2d42e3fa3fb01161'
    }
    It 'accepts only exact one historical unresolved Intent evidence' {
        (Assert-OPA265BW3jOriginalIntentEvidence -Evidence $script:j -Pinned $script:p) | Should -BeTrue
    }
    It 'accepts no existing resolution claim slots in the synthetic run folder' {
        (Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $script:paths -Pinned $script:p) | Should -BeTrue
    }
    It 'rejects a newly occupied hypothetical BW3j durable claim slot' {
        $path=Join-Path $script:temp 'bw3j-resolution.claim'
        [IO.File]::WriteAllText($path,'partial')
        { Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $script:paths -Pinned $script:p } | Should -Throw
        (Test-Path -LiteralPath $path) | Should -BeTrue
    }
    It 'rejects the occupied legacy LIVE6 claim slot' {
        $path=Join-Path $script:temp 'live6-resolution.claim'
        [IO.File]::WriteAllText($path,'partial')
        { Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $script:paths -Pinned $script:p } | Should -Throw
        (Test-Path -LiteralPath $path) | Should -BeTrue
    }
    It 'rejects a pre-existing directory where future BW3j claim would be' {
        $path=Join-Path $script:temp 'bw3j-resolution.claim'
        [void][IO.Directory]::CreateDirectory($path)
        { Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $script:paths -Pinned $script:p } | Should -Throw
    }
    It 'rejects an incorrect historical RunId before returning any future claim path' {
        $script:paths.RunId='other'
        { Get-OPA265BW3jFutureClaimPath -Paths $script:paths -Pinned $script:p } | Should -Throw
    }
    It 'rejects an incorrect pinned PST before returning any future claim path' {
        $script:paths.SourcePst='C:\Other.pst'
        { Get-OPA265BW3jFutureClaimPath -Paths $script:paths -Pinned $script:p } | Should -Throw
    }
    It 'returns exact future claim filename but never creates it' {
        $claim=Get-OPA265BW3jFutureClaimPath -Paths $script:paths -Pinned $script:p
        [IO.Path]::GetFileName($claim) | Should -BeExactly 'bw3j-resolution.claim'
        [IO.File]::Exists($claim) | Should -BeFalse
    }
    It 'outputs only design evidence with blocked journal status' {
        $v=Get-OPA265BW3jResolutionDesignDossier -Pinned $script:p -Bw3h $script:h -OriginalIntent $script:j -Before $script:b -After $script:a -AcceptanceRecordPath $script:recordPath
        $v.Status | Should -BeExactly 'BW3ScopedResolutionDesignEvidenceVerifiedAuthorizationNotIssued'
        $v.VerifiedHistoricalMoveViaBW3h | Should -BeTrue
        $v.FutureExclusiveJournalLockImplemented | Should -BeFalse
        $v.FutureJournalAppendWriterImplemented | Should -BeFalse
        $v.FutureClaimCreated | Should -BeFalse
        $v.CrashGapAfterClaimBeforeAppendRequiresManualStop | Should -BeTrue
        $v.CrashGapAfterAppendBeforeVerifyRequiresManualStop | Should -BeTrue
        $v.ConcurrentAppendRequiresExclusiveLockAndFreshSHA256 | Should -BeTrue
        $v.LegacyLive6ExecuteApplicable | Should -BeFalse
        $v.JournalReconciliationAuthorized | Should -BeFalse
        $v.JournalWritePermitIssued | Should -BeFalse
        $v.JournalChanged | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
        $v.OutlookMoveExecuted | Should -BeFalse
        $v.AutomaticRetryAllowed | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
    }
    It 'never invokes legacy LIVE4 LIVE5 LIVE6 scripts in BW3j entrypoint' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3jResolutionDesignReadOnly.ps1') -Raw
        $text | Should -Not -Match 'Invoke-OPA264Live6|Test-OPA264Live5|Test-OPA264Live4|BW3i1Legacy'
        $text | Should -Match 'Test-OPA265BW3hIndependentEvidenceChain.ps1'
    }
    It 'never introduces a write switch or calls a journal writer in BW3j' {
        foreach($file in @('Core/Diagnostics/Test-OPA265BW3jResolutionDesignReadOnly.ps1',
                           'Core/Worker/BW3jResolutionDesign265.ps1')) {
            $text=Get-Content -LiteralPath (Join-Path (Join-Path $PSScriptRoot '../..') $file) -Raw
            $text | Should -Not -Match '(?i)\[switch\]\$Record|\[switch\]\$Execute|Write-OPA|Add-Content|Set-Content|\.Move\(|\.Save\(|\.Delete\(|WriteAllBytes\(|WriteAllText\(|CreateNew|ReadWrite\,|Append\)'
        }
    }
    It 'rechecks journal and seven hashes after native BW3h Outlook proof' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3jResolutionDesignReadOnly.ps1') -Raw
        $text | Should -Match '\$before=Get-OPA265BW3hEvidenceSnapshot'
        $text | Should -Match '\$after=Get-OPA265BW3hEvidenceSnapshot'
        $text | Should -Match '\$first=Assert-OPA265BW3jOriginalIntent'
        $text | Should -Match '\$last=Assert-OPA265BW3jOriginalIntent'
    }
    It 'never activates BW3j in Archive Resume Auto production' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $text | Should -Not -Match 'BW3jResolutionDesign'
    }
    It 'new BW3j PS scripts comply with TZ-ENC-001 UTF8 BOM EF BB BF' {
        foreach($rel in @('Core/Worker/BW3jResolutionDesign265.ps1',
            'Core/Diagnostics/Test-OPA265BW3jResolutionDesignReadOnly.ps1',
            'Tests/Worker/BW3jResolutionDesign.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $bytes=[IO.File]::ReadAllBytes($path)
            ($bytes[0..2] -join ',') | Should -BeExactly '239,187,191'
        }
    }
    It 'parses new BW3j scripts with native PS5.1 AST' {
        foreach($rel in @('Core/Worker/BW3jResolutionDesign265.ps1',
                          'Core/Diagnostics/Test-OPA265BW3jResolutionDesignReadOnly.ps1')) {
            $tokens=$null;$errors=$null
            $p=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $null=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
