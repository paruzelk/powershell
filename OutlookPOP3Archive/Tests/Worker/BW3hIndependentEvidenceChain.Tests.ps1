#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
}
Describe 'BW3h read-only seven-artifact chain: no Reconciled permission' {
    BeforeEach {
        $script:p=Get-OPA265BW3hPinnedChain
        $script:recordPath='C:\Users\bogoderov_e\AppData\Local\Temp\OPA264-LIVE3-a7b51427749443f4bc9664915f6bee7e\bw3g-manual-size-acceptance.json'
        $script:r=[pscustomobject]@{
            Schema='2.6.5-BW3g.ManualSizeAcceptanceStatus.1'
            Status='HistoricalSyntheticSizeAcceptanceRecordVerified'
            Decision='OnlyEightByteSyntheticSizeDeviationRecorded'
            RunId=[string]$script:p.RunId
            JournalSha256=[string]$script:p.JournalSha256
            AcceptanceRecordPath=$script:recordPath
            AcceptanceRecordSha256=[string]$script:p.AcceptanceFileSha256
            AcceptedDifferenceBytes=8L
            ManualSizeAcceptancePersisted=$true
            JournalReconciliationAuthorized=$false
            JournalChanged=$false
            JournalReconciled=$false
            MailMoveExecuted=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
        }
        $script:before=[pscustomobject][ordered]@{
            Journal=[string]$script:p.JournalSha256
            Request='a'*64
            Scope='b'*64
            MoveAttemptClaim='c'*64
            DispatchClaim='d'*64
            ControllerResult='e'*64
            ManualSizeAcceptance=[string]$script:p.AcceptanceFileSha256
        }
        $script:after=$script:before.PSObject.Copy()
    }
    It 'rejects changed RunId in historical BW3g1 Review' {
        $script:r.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects wrong journal SHA256 in Review' {
        $script:r.JournalSha256='f'*64
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects wrong acceptance record SHA256 in Review' {
        $script:r.AcceptanceRecordSha256='a'*64
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects wrong acceptance record path in Review' {
        $script:r.AcceptanceRecordPath='C:\Wrong\bw3g-manual-size-acceptance.json'
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects different +8 size acceptance in Review' {
        $script:r.AcceptedDifferenceBytes=7L
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects not persisted acceptance in Review' {
        $script:r.ManualSizeAcceptancePersisted=$false
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects fabricated journal write authorization in Review' {
        $script:r.JournalReconciliationAuthorized=$true
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects false journal mutation in Review' {
        $script:r.JournalChanged=$true
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects false Reconciled in Review' {
        $script:r.JournalReconciled=$true
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects false Outlook Move executed in Review' {
        $script:r.MailMoveExecuted=$true
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects unsafe automatic retry in Review' {
        $script:r.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects production readiness in Review' {
        $script:r.ProductionReady=$true
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects false prior Review status' {
        $script:r.Status='HistoricalSyntheticSizeAcceptanceRecorded'
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects wrong previous Review schema' {
        $script:r.Schema='Wrong'
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects wrong previous Review decision' {
        $script:r.Decision='JournalReconciled'
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects missing evidence status field' {
        $script:r.PSObject.Properties.Remove('Status')
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects extra invented approval field' {
        $script:r | Add-Member -NotePropertyName JournalWriteApproved -NotePropertyValue $true
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects unsafe string Boolean acceptance' {
        $script:r.ManualSizeAcceptancePersisted='True'
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'rejects unsafe numeric Boolean journal authorization' {
        $script:r.JournalReconciliationAuthorized=0
        { Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath } | Should -Throw
    }
    It 'refuses different pinned RunId' {
        $script:p.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different pinned OperationId' {
        $script:p.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different pinned WorkerRequestId' {
        $script:p.WorkerRequestId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different pinned source PST' {
        $script:p.SourcePst='C:\Wrong.pst'
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different pinned archived EntryID' {
        $script:p.DestinationEntryId='NOT-PINNED'
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different pinned journal hash' {
        $script:p.JournalSha256='f'*64
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different pinned Body hash' {
        $script:p.BodyUtf8Sha256='f'*64
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different pinned acceptance file name' {
        $script:p.AcceptanceFileName='other.json'
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different pinned acceptance SHA256' {
        $script:p.AcceptanceFileSha256='f'*64
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different original Intent size' {
        $script:p.OriginalSizeBytes=1437L
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different archived size' {
        $script:p.ArchivedSizeBytes=1443L
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'refuses different accepted size delta' {
        $script:p.AcceptedSizeDeltaBytes=9L
        { Assert-OPA265BW3hPinnedIdentity -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on modified original Intent file hash' {
        $script:after.Journal='f'*64
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on modified fixture request hash' {
        $script:after.Request='f'*64
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on modified fixture scope hash' {
        $script:after.Scope='f'*64
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on modified Move attempt claim hash' {
        $script:after.MoveAttemptClaim='f'*64
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on modified dispatch claim hash' {
        $script:after.DispatchClaim='f'*64
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on modified controller result hash' {
        $script:after.ControllerResult='f'*64
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on modified manual +8 acceptance file hash' {
        $script:after.ManualSizeAcceptance='f'*64
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on missing acceptance file evidence' {
        $script:after.PSObject.Properties.Remove('ManualSizeAcceptance')
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on added forged eighth evidence file' {
        $script:after | Add-Member -NotePropertyName FraudulentProof -NotePropertyValue ('f'*64)
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'fails closed on bad hash instead of SHA256' {
        $script:before.Request='abc'
        { Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p } | Should -Throw
    }
    It 'pins exact historical acceptance SHA256 independently of user input' {
        $script:p.AcceptanceFileSha256 | Should -BeExactly 'c7b066436b03d5f9cd400ebf560c82852e46d943d15d276a2d42e3fa3fb01161'
        $script:p.JournalSha256 | Should -BeExactly '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648'
    }
    It 'accepts exact one-run read-only previous Review object' {
        (Assert-OPA265BW3hPreviousAcceptanceReview -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath) | Should -BeTrue
    }
    It 'accepts original 6 claims plus approval as exactly 7 unchanged file hashes' {
        (Assert-OPA265BW3hSnapshotUnchanged -Before $script:before -After $script:after -Pinned $script:p) | Should -BeTrue
    }
    It 'never grants journal reconciliation on a successful full chain' {
        $v=Get-OPA265BW3hChainVerdict -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath -Before $script:before -After $script:after
        $v.Status | Should -BeExactly 'IndependentEvidenceChainVerifiedJournalDecisionPending'
        $v.ManuallyAcceptedSyntheticDifferenceBytes | Should -Be 8
        $v.ManualSizeAcceptancePersisted | Should -BeTrue
        $v.SevenDurableEvidenceHashesVerified | Should -BeTrue
        $v.JournalReconciliationAuthorized | Should -BeFalse
        $v.JournalWritePermitIssued | Should -BeFalse
        $v.JournalCompleted | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
    }
    It 'reports unchanged archived item identity without raw email content' {
        $v=Get-OPA265BW3hChainVerdict -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath -Before $script:before -After $script:after
        $v.DestinationEntryId | Should -BeExactly $script:p.DestinationEntryId
        $v.OriginalIntentSha256 | Should -BeExactly $script:p.JournalSha256
        $v.AcceptanceRecordSha256 | Should -BeExactly $script:p.AcceptanceFileSha256
        $v.ArchivedBodyUtf8Sha256 | Should -BeExactly $script:p.BodyUtf8Sha256
        $v.SourceItemCount | Should -Be 0
        $v.ArchiveItemCount | Should -Be 1
        $v.SyntheticAttachmentsCount | Should -Be 0
        $v.PSObject.Properties.Name | Should -Not -Contain 'BodyText'
    }
    It 'retains acknowledged uncertainty of before-Move and MAPI size drift' {
        $v=Get-OPA265BW3hChainVerdict -Review $script:r -Pinned $script:p -ExactRecordPath $script:recordPath -Before $script:before -After $script:after
        $v.SizeDiscrepancyCauseEstablished | Should -BeFalse
        $v.BeforeMoveActualBodyHashAvailable | Should -BeFalse
        $v.FullMAPIContentByteEqualityVerified | Should -BeFalse
        $v.OutlookMoveExecuted | Should -BeFalse
        $v.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'requires UTF8 BOM EF BB BF in all three new BW3h source files' {
        foreach($rel in @('Core/Worker/BW3hIndependentEvidenceChain265.ps1',
            'Core/Diagnostics/Test-OPA265BW3hIndependentEvidenceChain.ps1',
            'Tests/Worker/BW3hIndependentEvidenceChain.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $bytes=[IO.File]::ReadAllBytes($path)
            ($bytes[0..2] -join ',') | Should -BeExactly '239,187,191'
        }
    }
    It 'has no direct or indirect write-enabled mode in BW3h entrypoint' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3hIndependentEvidenceChain.ps1') -Raw
        $src | Should -Not -Match '(?i)\.Move\(|\.Save\(|\.Delete\(|Write-OPA|AddStoreEx\(|SetProperty\(|CreateNew|New-OPA265BW3gManualAcceptance|WriteAllText|WriteAllBytes|Set-Content|Add-Content'
        $src | Should -Match '\[switch\]\$Review'
        $src | Should -Not -Match '\[switch\]\$Record|\[switch\]\$Execute'
    }
    It 'calls BW3g1 read-only Review exclusively before final chain verdict' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3hIndependentEvidenceChain.ps1') -Raw
        $src | Should -Match "Invoke-OPA265BW3gManualSizeAcceptance.ps1'"
        $src | Should -Match '-Review'
        ($src.IndexOf("Invoke-OPA265BW3gManualSizeAcceptance.ps1'") -lt $src.IndexOf('Get-OPA265BW3hChainVerdict -Review')) | Should -BeTrue
    }
    It 'does not invoke production Archive Resume Auto' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $src | Should -Not -Match 'BW3hIndependentEvidenceChain'
    }
    It 'parses BW3h entrypoint and pure logic with no PS5.1 AST errors' {
        foreach($rel in @('Core/Worker/BW3hIndependentEvidenceChain265.ps1',
            'Core/Diagnostics/Test-OPA265BW3hIndependentEvidenceChain.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
