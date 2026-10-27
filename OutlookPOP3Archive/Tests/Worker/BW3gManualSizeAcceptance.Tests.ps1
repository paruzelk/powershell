#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
}
Describe 'BW3g explicit one-shot historic manual size acceptance with immutable claims' {
    BeforeEach {
        $script:p=Get-OPA265BW3gPinnedAcceptance
        $script:h=[pscustomobject][ordered]@{
            Journal=$script:p.JournalSha256
            Request='a'*64
            Scope='b'*64
            MoveAttemptClaim='c'*64
            DispatchClaim='d'*64
            ControllerResult='e'*64
        }
        $script:d=[pscustomobject]@{
            Schema='2.6.5-BW3f.ManualSizeDecisionDossier.1'
            Status='EvidenceDossierReadyHumanDecisionPending'
            Decision='DeferJournalResolutionUntilSeparateExplicitAuthorization'
            RunId=$script:p.RunId
            OperationId=$script:p.OperationId
            WorkerRequestId=$script:p.WorkerRequestId
            JournalSha256=$script:p.JournalSha256
            DestinationEntryId=$script:p.DestinationEntryId
            ArchivedBodyUtf8Sha256=$script:p.BodyUtf8Sha256
            PriorBw3eStatus='SyntheticBodyTailSpaceCrLfConfirmed'
            IntentSizeBytes=1436L
            ArchivedSizeBytes=1444L
            UnapprovedSizeDifferenceBytes=8L
            SourceItemCount=0
            ArchiveItemCount=1
            AttachmentsCount=0
            HumanSizeDecisionValue='Unrecorded'
            NextAction='PreserveOriginalEvidenceAndObtainSeparateExplicitManualSizeDecision'
            WorkerMoveIdentityObserved=$true
            ClaimsCorrelated=$true
            BodySuffixConfirmed=$true
            ProviderSizeCrossCheckMatches=$true
            AdditionalExplicitOperatorConsentRequired=$true
            OnlyRunScopedSyntheticFoldersInspected=$true
            BeforeMoveActualBodyHashCaptured=$false
            TimingOfBodySuffixEstablished=$false
            CauseOfMAPIByteSizeDriftEstablished=$false
            MAPIStreamOrFullItemByteEqualityVerified=$false
            SizeDifferenceAcceptableAutomatically=$false
            SizeDifferenceApproved=$false
            HumanSizeDecisionRecorded=$false
            ManualJournalDecisionAuthorized=$false
            WriteableReconciliationPermitIssued=$false
            EvidencePacketPersisted=$false
            OutlookMoveExecuted=$false
            JournalChanged=$false
            JournalCompleted=$false
            JournalReconciled=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
            BodyTailCodeUnits=[int[]]@(32,13,10)
        }
        $script:temp=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:temp)
        $script:paths=[pscustomobject]@{
            RunId=$script:p.RunId
            SourcePst=$script:p.SourcePst
            Directory=$script:temp
        }
    }
    It 'rejects wrong RunId in dossier' {
        $script:d.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong OperationId in dossier' {
        $script:d.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong WorkerRequestId in dossier' {
        $script:d.WorkerRequestId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed journal SHA256 in dossier' {
        $script:d.JournalSha256='f'*64
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects foreign destination EntryID' {
        $script:d.DestinationEntryId='WRONG'
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong historical Body SHA256' {
        $script:d.ArchivedBodyUtf8Sha256='f'*64
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong dossier schema' {
        $script:d.Schema='Unknown'
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects fake acceptance status before consent' {
        $script:d.Status='ManualAcceptanceRecorded'
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects false reconciliation decision' {
        $script:d.Decision='Reconciled'
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed Intent size' {
        $script:d.IntentSizeBytes=1444L
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed archived size' {
        $script:d.ArchivedSizeBytes=1436L
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed +8 difference' {
        $script:d.UnapprovedSizeDifferenceBytes=0
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects additional archived mail' {
        $script:d.ArchiveItemCount=2
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects source mail reappeared' {
        $script:d.SourceItemCount=1
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects unexpected synthetic attachments' {
        $script:d.AttachmentsCount=1
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects loss of Worker evidence' {
        $script:d.WorkerMoveIdentityObserved=$false
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects loss of correlated claims' {
        $script:d.ClaimsCorrelated=$false
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects loss of Body suffix identity' {
        $script:d.BodySuffixConfirmed=$false
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects provider size mismatch' {
        $script:d.ProviderSizeCrossCheckMatches=$false
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects fake size approval' {
        $script:d.SizeDifferenceApproved=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects false journal reconciliation permission' {
        $script:d.ManualJournalDecisionAuthorized=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects false journal changed flag' {
        $script:d.JournalChanged=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects false journal completion' {
        $script:d.JournalCompleted=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects false journal Reconciled' {
        $script:d.JournalReconciled=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects unsafe automatic retry' {
        $script:d.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects false production readiness' {
        $script:d.ProductionReady=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects fabricated before-Move body fingerprint' {
        $script:d.BeforeMoveActualBodyHashCaptured=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects fabricated MAPI size cause' {
        $script:d.CauseOfMAPIByteSizeDriftEstablished=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects fabricated byte-level equality' {
        $script:d.MAPIStreamOrFullItemByteEqualityVerified=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects consent already recorded in dossier' {
        $script:d.HumanSizeDecisionRecorded=$true
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed pinned source PST' {
        $script:p.SourcePst='C:\Other.pst'
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed pinned archive EntryID' {
        $script:p.DestinationEntryId='FOREIGN'
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects changed pinned size' {
        $script:p.AcceptedDifferenceBytes=7L
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong suffix codepoints' {
        $script:d.BodyTailCodeUnits=[int[]]@(32,13,11)
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects boolean string instead of true' {
        $script:d.ClaimsCorrelated='True'
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'rejects missing explicit consent requirement' {
        $script:d.AdditionalExplicitOperatorConsentRequired=$false
        { Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p } | Should -Throw
    }
    It 'accepts exact previously unresolved BW3f evidence' {
        (Assert-OPA265BW3gReviewDossier -Dossier $script:d -Pinned $script:p) | Should -BeTrue
    }
    It 'pins exact historical approval token and location' {
        $script:p.ExactAcknowledgment | Should -BeExactly ('ACCEPT-SYNTHETIC-8-BYTES-'+$script:p.RunId+'-NO-JOURNAL-CHANGE')
        $script:p.RecordFileName | Should -BeExactly 'bw3g-manual-size-acceptance.json'
        (Get-OPA265BW3gRecordPath -Paths $script:paths) | Should -BeExactly (Join-Path $script:temp 'bw3g-manual-size-acceptance.json')
    }
    It 'refuses consent with an incomplete acknowledgement' {
        { New-OPA265BW3gManualAcceptance -Dossier $script:d -Pinned $script:p -EvidenceHashes $script:h -Acknowledgment 'ACCEPT' } | Should -Throw
    }
    It 'creates a typed, fully scoped acceptance object only with the exact token' {
        $r=New-OPA265BW3gManualAcceptance -Dossier $script:d -Pinned $script:p -EvidenceHashes $script:h -Acknowledgment $script:p.ExactAcknowledgment
        $r.Status | Should -BeExactly 'ManualSyntheticSizeDeviationAcceptedOnly'
        $r.ManualSizeAcceptanceRecorded | Should -BeTrue
        $r.AcceptedDifferenceBytes | Should -Be 8
        $r.JournalReconciliationAuthorized | Should -BeFalse
        $r.JournalChanged | Should -BeFalse
        $r.JournalReconciled | Should -BeFalse
        $r.MailMoveExecuted | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        (Assert-OPA265BW3gManualAcceptance -Record $r -Pinned $script:p -EvidenceHashes $script:h -DossierFingerprint $r.EvidenceDossierSha256) | Should -BeTrue
    }
    It 'fails closed when one original claim hash changes' {
        $changed=$script:h.PSObject.Copy()
        $changed.DispatchClaim='f'*64
        { Assert-OPA265BW3gHashesUnchanged -Previous $script:h -Current $changed } | Should -Throw
    }
    It 'fails closed when original Journal SHA256 changes' {
        $changed=$script:h.PSObject.Copy()
        $changed.Journal='f'*64
        { Assert-OPA265BW3gHashesUnchanged -Previous $script:h -Current $changed } | Should -Throw
    }
    It 'refuses destination path outside exact original fixture directory' {
        $script:paths.RunId=[guid]::NewGuid().ToString('D')
        { Get-OPA265BW3gRecordPath -Paths $script:paths } | Should -Throw
    }
    It 'creates one UTF8-without-BOM JSON record and verifies byte readback' {
        $r=New-OPA265BW3gManualAcceptance -Dossier $script:d -Pinned $script:p -EvidenceHashes $script:h -Acknowledgment $script:p.ExactAcknowledgment
        $w=Write-OPA265BW3gCreateNewRecord -Paths $script:paths -Record $r
        [IO.File]::Exists($w.Path) | Should -BeTrue
        $bytes=[IO.File]::ReadAllBytes($w.Path)
        ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) | Should -BeFalse
        $read=Read-OPA265BW3gOriginalRecord -Paths $script:paths -Pinned $script:p -EvidenceHashes $script:h -DossierFingerprint $r.EvidenceDossierSha256
        $read.Sha256 | Should -BeExactly $w.Sha256
        $read.Record.ManualSizeAcceptanceRecorded | Should -BeTrue
    }
    It 'never overwrites the original one-shot record' {
        $r=New-OPA265BW3gManualAcceptance -Dossier $script:d -Pinned $script:p -EvidenceHashes $script:h -Acknowledgment $script:p.ExactAcknowledgment
        $first=Write-OPA265BW3gCreateNewRecord -Paths $script:paths -Record $r
        { Write-OPA265BW3gCreateNewRecord -Paths $script:paths -Record $r } | Should -Throw
        (Get-FileHash -LiteralPath $first.Path -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $first.Sha256
    }
    It 'detects an altered persisted manual acceptance record' {
        $r=New-OPA265BW3gManualAcceptance -Dossier $script:d -Pinned $script:p -EvidenceHashes $script:h -Acknowledgment $script:p.ExactAcknowledgment
        $w=Write-OPA265BW3gCreateNewRecord -Paths $script:paths -Record $r
        $r.ObservedArchiveSizeBytes=1436
        [IO.File]::WriteAllText($w.Path,(ConvertTo-Json -InputObject $r -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))
        { Read-OPA265BW3gOriginalRecord -Paths $script:paths -Pinned $script:p -EvidenceHashes $script:h -DossierFingerprint $r.EvidenceDossierSha256 } | Should -Throw
    }
    It 'rejects a partial one-time record instead of retrying it' {
        $path=Get-OPA265BW3gRecordPath -Paths $script:paths
        [IO.File]::WriteAllText($path,'{"Schema":',[Text.UTF8Encoding]::new($false))
        { Read-OPA265BW3gOriginalRecord -Paths $script:paths -Pinned $script:p -EvidenceHashes $script:h -DossierFingerprint ('a'*64) } | Should -Throw
        [IO.File]::Exists($path) | Should -BeTrue
    }
    It 'rejects a BOM in the JSON data record (while requiring it in PS source)' {
        $path=Get-OPA265BW3gRecordPath -Paths $script:paths
        [IO.File]::WriteAllText($path,'{}',[Text.UTF8Encoding]::new($true))
        { Read-OPA265BW3gOriginalRecord -Paths $script:paths -Pinned $script:p -EvidenceHashes $script:h -DossierFingerprint ('a'*64) } | Should -Throw
    }
    It 'refuses a forged journal reconciliation permit inside acceptance record' {
        $r=New-OPA265BW3gManualAcceptance -Dossier $script:d -Pinned $script:p -EvidenceHashes $script:h -Acknowledgment $script:p.ExactAcknowledgment
        $r.JournalReconciliationAuthorized=$true
        { Assert-OPA265BW3gManualAcceptance -Record $r -Pinned $script:p -EvidenceHashes $script:h -DossierFingerprint $r.EvidenceDossierSha256 } | Should -Throw
    }
    It 'prevents automatic repeat mail Move or journal Reconciled from entry point' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW3gManualSizeAcceptance.ps1') -Raw
        $src | Should -Not -Match '(?i)\.Move\(|\.Save\(|\.Delete\(|AddStoreEx\(|Write-OPAOperationJournalEvent|Write-OPA264Live6ReconciledLocked|SetProperty\('
        $src | Should -Match 'Write-OPA265BW3gCreateNewRecord'
    }
    It 'validates exact consent before independent audit and any potential file creation' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW3gManualSizeAcceptance.ps1') -Raw
        $src.IndexOf('$ExactSizeAcceptance -cne [string]$pinned.ExactAcknowledgment') | Should -BeGreaterThan 0
        ($src.IndexOf('$ExactSizeAcceptance -cne [string]$pinned.ExactAcknowledgment') -lt $src.IndexOf('Write-OPA265BW3gCreateNewRecord -Paths')) | Should -BeTrue
    }
    It 'does not include production Archive Resume Auto code paths' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $src | Should -Not -Match 'BW3gManualSizeAcceptance'
    }
    It 'stores all new PowerShell scripts with UTF8 BOM EF BB BF' {
        foreach($rel in @('Core/Worker/BW3gManualSizeAcceptance265.ps1',
            'Core/Diagnostics/Invoke-OPA265BW3gManualSizeAcceptance.ps1',
            'Tests/Worker/BW3gManualSizeAcceptance.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $bytes=[IO.File]::ReadAllBytes($path)
            ($bytes[0..2] -join ',') | Should -BeExactly '239,187,191'
        }
    }
    It 'parses new BW3g code under native Windows PowerShell 5.1' {
        foreach($rel in @('Core/Worker/BW3gManualSizeAcceptance265.ps1',
            'Core/Diagnostics/Invoke-OPA265BW3gManualSizeAcceptance.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
