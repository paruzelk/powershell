#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
}
Describe 'BW3d pinned eight-byte historical synthetic size inspection: no consent, no Move' {
    BeforeEach {
        $script:p=Get-OPA265BW3dPinnedSizeReview
        $script:previous=[pscustomobject]@{
            Schema='2.6.5-BW3b.IndependentPostMoveAudit.1'
            Status='IndependentPostMoveAuditPassed'
            Decision='MoveConfirmedByEntryIdAndSyntheticIdentity'
            RunId=$script:p.RunId
            OperationId=$script:p.OperationId
            WorkerRequestId=$script:p.WorkerRequestId
            JournalSha256=$script:p.JournalSha256
            WorkerDestinationEntryId=$script:p.ArchiveEntryId
            ObservedArchiveEntryId=$script:p.ArchiveEntryId
            ArchiveEntryIdMatchesWorker=$true
            ClaimsCorrelated=$true
            SourceItemCount=0
            ArchiveItemCount=1
            SyntheticSourceMatches=0
            SyntheticArchiveMatches=1
            IntentSizeBytes=1436
            ObservedArchiveSizeBytes=1444
            ArchiveSizeDifferenceBytes=8
            ArchiveSizeMatchesIntent=$false
            ArchiveSizeDifferenceApproved=$false
            ContentByteEqualityVerified=$false
            RequiresManualSizeReview=$true
            OnlySyntheticFoldersInspected=$true
            OutlookMoveExecuted=$false
            JournalChanged=$false
            JournalCompleted=$false
            JournalReconciled=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
            NextAction='StopBeforeManualJournalDecision'
        }
        $script:obs=[pscustomobject]@{
            RunId=$script:p.RunId
            OperationId=$script:p.OperationId
            ArchiveEntryId=$script:p.ArchiveEntryId
            ArchiveStoreId='TESTARCHIVESTORE'
            ArchiveFolderEntryId='TESTARCHIVEFOLDER'
            ArchiveFolderPath='\\OPA264-LIVE3-Archive'
            Subject=('OPA264 LIVE3 synthetic '+$script:p.RunId)
            InternetMessageId=('<opa264-live3-'+$script:p.RunId+'@example.invalid>')
            MailClass=43
            MessageClass='IPM.Note'
            SourceItemCount=0
            ArchiveItemCount=1
            AttachmentsCount=0
            BodyText=$script:p.FixtureBody
            MailItemSizeBytes=1444L
            PrMessageSizeAvailable=$true
            PrMessageSizeBytes=1444L
            PrMessageSizeReadError=''
        }
    }
    It 'pins the exact approved historical BW3a run and 8-byte difference' {
        $script:p.RunId | Should -BeExactly 'a7b51427-7494-43f4-bc96-64915f6bee7e'
        $script:p.PinnedDifferenceBytes | Should -Be 8
        ($script:p.PinnedObservedArchiveSizeBytes-$script:p.IntentSizeBytes) | Should -Be 8
    }
    It 'pins the canonical Unicode path and exact archived EntryID' {
        $script:p.SourcePst | Should -BeExactly (Get-OPA265BW3bPinnedIdentity).SourcePst
        $script:p.ArchiveEntryId | Should -BeExactly '00000000953C628FC9EAC24E97DBE040019A969924002000'
    }
    It 'accepts the exact previous independent read-only result' {
        (Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p) | Should -BeTrue
    }
    It 'rejects an altered pinned observed size' {
        $script:p.PinnedObservedArchiveSizeBytes=1436
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects mutated fixture baseline text' {
        $script:p.FixtureBody='Different content'
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects a changed parent WorkerRequestId' {
        $script:previous.WorkerRequestId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign RunId in prior BW3b result' {
        $script:previous.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign OperationId in prior BW3b result' {
        $script:previous.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects altered original journal SHA256' {
        $script:previous.JournalSha256='f'*64
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects mismatched archive EntryID even after reported Move' {
        $script:previous.ObservedArchiveEntryId='WRONG'
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects false claim correlation' {
        $script:previous.ClaimsCorrelated=$false
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects missing or duplicate archival counts' {
        $script:previous.ArchiveItemCount=2
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects any prior automatic archive-size approval' {
        $script:previous.ArchiveSizeDifferenceApproved=$true
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects any prior claim of byte equality' {
        $script:previous.ContentByteEqualityVerified=$true
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects any prior journal completion' {
        $script:previous.JournalCompleted=$true
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects past result with automatic retry permission' {
        $script:previous.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3dPinnedBw3bAudit -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'accepts exact single archived mail structure and optional PR message size' {
        (Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p) | Should -BeTrue
    }
    It 'rejects an extra Outlook observation field' {
        $script:obs | Add-Member NoteProperty DangerousAuthorization $true
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'rejects foreign archive EntryID in size observation' {
        $script:obs.ArchiveEntryId='BAD'
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'rejects foreign InternetMessageId in size observation' {
        $script:obs.InternetMessageId='<foreign@example.invalid>'
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'rejects foreign synthetic Subject in size observation' {
        $script:obs.Subject='Ordinary user mailbox'
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'rejects a non-message archived item' {
        $script:obs.MailClass=26
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'rejects a foreign MAPI MessageClass' {
        $script:obs.MessageClass='IPM.Appointment'
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'rejects a changed observed archive size, even if another size is valid' {
        $script:obs.MailItemSizeBytes=1436
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'rejects wrong archive count after BW3b check' {
        $script:obs.ArchiveItemCount=2
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'requires an explicit availability flag for PR_MESSAGE_SIZE' {
        $script:obs.PrMessageSizeAvailable='untrusted'
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'accepts PR_MESSAGE_SIZE provider error as explicit unavailable evidence' {
        $script:obs.PrMessageSizeAvailable=$false
        $script:obs.PrMessageSizeBytes=0
        $script:obs.PrMessageSizeReadError='UnavailableOrProviderRejected'
        (Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p) | Should -BeTrue
    }
    It 'rejects claiming PR size unavailable without a reason' {
        $script:obs.PrMessageSizeAvailable=$false
        $script:obs.PrMessageSizeBytes=0
        { Assert-OPA265BW3dObservation -Evidence $script:obs -Pinned $script:p } | Should -Throw
    }
    It 'returns manual-only review even when synthetic Body and attachments match' {
        $v=Get-OPA265BW3dSizeEvidenceVerdict -Previous $script:previous -Observation $script:obs -Pinned $script:p
        $v.Status | Should -Be 'SizeDriftStructureConsistentManualReviewPending'
        $v.BodyTextMatchesFixtureExactly | Should -BeTrue
        $v.AttachmentsCountMatchesFixture | Should -BeTrue
        $v.SizeDifferenceBytes | Should -Be 8
        $v.ArchiveSizeDifferenceApproved | Should -BeFalse
        $v.EvidenceSufficientForContentByteEquality | Should -BeFalse
        $v.ManualJournalDecisionAuthorized | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
        $v.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'detects trailing CRLF as diagnostic-only text normalization' {
        $script:obs.BodyText+=[string][char]13+[char]10
        $v=Get-OPA265BW3dSizeEvidenceVerdict -Previous $script:previous -Observation $script:obs -Pinned $script:p
        $v.BodyTextMatchesFixtureExactly | Should -BeFalse
        $v.BodyTextMatchesAfterTrailingCrLfTrim | Should -BeTrue
        $v.ExpectedSyntheticBodyUtf8Sha256 | Should -Not -Be $v.ObservedBodyUtf8Sha256
        $v.ArchiveSizeDifferenceApproved | Should -BeFalse
    }
    It 'flags unexpected altered archived body without automatic approval' {
        $script:obs.BodyText='unexpected body'
        $v=Get-OPA265BW3dSizeEvidenceVerdict -Previous $script:previous -Observation $script:obs -Pinned $script:p
        $v.Status | Should -Be 'UnexpectedSyntheticContentStopAndInvestigate'
        $v.BodyTextMatchesAfterTrailingCrLfTrim | Should -BeFalse
        $v.EvidenceSufficientForAutomaticSizeApproval | Should -BeFalse
    }
    It 'flags any attachment added to historical no-attachments fixture' {
        $script:obs.AttachmentsCount=1
        $v=Get-OPA265BW3dSizeEvidenceVerdict -Previous $script:previous -Observation $script:obs -Pinned $script:p
        $v.Status | Should -Be 'UnexpectedSyntheticContentStopAndInvestigate'
        $v.AttachmentsCountMatchesFixture | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
    }
    It 'reports PR message-size mismatch without ignoring the eight-byte drift' {
        $script:obs.PrMessageSizeBytes=1445
        $v=Get-OPA265BW3dSizeEvidenceVerdict -Previous $script:previous -Observation $script:obs -Pinned $script:p
        $v.PrMessageSizeMatchesMailItemSize | Should -BeFalse
        $v.SizeDifferenceBytes | Should -Be 8
        $v.RequiresManualSizeReview | Should -BeTrue
    }
    It 'does not claim PR_MESSAGE_SIZE when provider refuses it' {
        $script:obs.PrMessageSizeAvailable=$false
        $script:obs.PrMessageSizeBytes=0
        $script:obs.PrMessageSizeReadError='UnavailableOrProviderRejected'
        $v=Get-OPA265BW3dSizeEvidenceVerdict -Previous $script:previous -Observation $script:obs -Pinned $script:p
        $v.PrMessageSizeAvailable | Should -BeFalse
        $v.PrMessageSizeBytes | Should -BeNullOrEmpty
        $v.ArchiveSizeDifferenceApproved | Should -BeFalse
    }
    It 'calculates stable UTF8 Body hash without a BOM' {
        (Get-OPA265BW3dUtf8TextSha256 -Text 'abc') | Should -BeExactly 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }
    It 'always keeps the original journal unresolved even if synthetic Body matches' {
        $v=Get-OPA265BW3dSizeEvidenceVerdict -Previous $script:previous -Observation $script:obs -Pinned $script:p
        $v.JournalChanged | Should -BeFalse
        $v.JournalCompleted | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
        $v.OutlookMoveExecuted | Should -BeFalse
    }
    It 'source script is BOM UTF8 and has no mutation/Worker calls' {
        $audit=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3dSyntheticSizeAudit.ps1'
        $bytes=[IO.File]::ReadAllBytes($audit)
        @($bytes[0..2]) | Should -Be @(239,187,191)
        $src=Get-Content -LiteralPath $audit -Raw
        $src | Should -Not -Match '(?i)\.Move\(|\.Save\(|\.Delete\(|AddStoreEx\(|Write-OPAOperationJournalEvent|Write-OPA264Live6ReconciledLocked|Invoke-OPAWorkerControlledOperation|SetProperty\('
        $src | Should -Match "'Test-OPA265BW3bIndependentMoveAudit.ps1'"
    }
    It 'rejects a wrong identity before any Outlook COM access in source' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3dSyntheticSizeAudit.ps1') -Raw
        $pin=$src.IndexOf('$SourcePst -cne [string]$pinned.SourcePst')
        $com=$src.IndexOf("GetActiveObject('Outlook.Application')")
        $pin | Should -BeGreaterThan 0
        ($pin -lt $com) | Should -BeTrue
    }
    It 'checks journal and all six durable evidence hashes before and after COM' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3dSyntheticSizeAudit.ps1') -Raw
        $src | Should -Match '[$]paths[.]JournalPath'
        $src | Should -Match '[$]extra[.]DispatchClaimPath'
        $src | Should -Match '[$]extra[.]ControllerResultPath'
        $src | Should -Match '[$]before[[][$]file[]]'
        $src | Should -Match 'foreach[(][$]file in [$]evidenceFiles[)]'
    }
    It 'does not introduce a new production Worker code path' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $src | Should -Not -Match 'BW3dSyntheticSize'
    }
    It 'both new PowerShell files parse without syntax errors in native PS5.1' {
        foreach($rel in @('Core/Worker/BW3dSyntheticSizeEvidence265.ps1','Core/Diagnostics/Test-OPA265BW3dSyntheticSizeAudit.ps1')) {
            $p=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $t=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
