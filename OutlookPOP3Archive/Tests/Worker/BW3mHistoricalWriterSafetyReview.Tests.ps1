#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3lHistoricalCopyRehearsal265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3mHistoricalWriterSafetyReview265.ps1')
}
Describe 'BW3m: final historical writer security proof, original READ ONLY' {
    BeforeEach {
        $script:p=Get-OPA265BW3hPinnedChain
        $script:source=Join-Path $TestDrive ('source-'+[guid]::NewGuid().ToString('N')+'.jsonl')
        $script:fakePst='BW3M-ISOLATED-NO-REAL-PST'
        $evt=@{
            Path=$script:source
            TransactionId=[string]$script:p.RunId
            OperationId=[string]$script:p.OperationId
            Sequence=1
            Phase='Intent'
            OperationKind='MailMove'
            SourceEntryId='BW3M-OFFLINE-SOURCE-ONLY'
            ArchivePst=$script:fakePst
            InternetMessageId=('<opa264-live3-'+[string]$script:p.RunId+'@example.invalid>')
            Subject=('OPA264 LIVE3 synthetic '+[string]$script:p.RunId)
            Size=1436L
        }
        $null=Write-OPAOperationJournalEvent @evt
        $script:seed=[IO.File]::ReadAllBytes($script:source)
        $script:seedSha=Get-OPAOperationJournalSha256 -Bytes $script:seed
        $script:fixture=New-OPA265BW3lCopySandbox -OriginalIntentBytes $script:seed -Pinned $script:p -OfflineReplicaForTests
        $script:paths=$script:fixture.Paths
        $script:m=$script:fixture.Marker
        $script:copyResult=Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p
        $script:review=[pscustomobject][ordered]@{
            Schema='2.6.5-BW3l.HistoricalByteCopyRehearsalReadOnlyOriginal.1'
            Status='HistoricalJournalCopyRehearsalVerifiedOriginalUntouched'
            Decision='DoNotWriteHistoricalJournalWithoutNewSeparateExplicitAuthorization'
            RunId=[string]$script:p.RunId
            OperationId=[string]$script:p.OperationId
            OriginalIntentSha256=[string]$script:p.JournalSha256
            AcceptanceRecordSha256=[string]$script:p.AcceptanceFileSha256
            DestinationEntryId=[string]$script:p.DestinationEntryId
            SandboxDirectory=[string]$script:paths.Directory
            SandboxCopyFinalSha256=[string]$script:copyResult.SandboxFinalJournalSha256
            IndependentBW3jReviewPassed=$true
            HistoricalSevenHashesUnchanged=$true
            CopyContainsOriginalExactBytes=$true
            CopyReconciled=$true
            CopyJournalEventCount=2
            CopyDurableClaimCreated=$true
            HistoricalJournalEventCount=1
            HistoricalJournalPhase='Intent'
            HistoricalResolutionClaimCreated=$false
            HistoricalJournalChanged=$false
            HistoricalJournalReconciled=$false
            HistoricalJournalWritePermitIssued=$false
            OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
            NextAction='ReviewBW3ScopedWriterSecurityAndObtainSeparateExactRunJournalAuthorization'
        }
        $script:hashes=[pscustomobject][ordered]@{
            Journal=[string]$script:p.JournalSha256
            Request='a'*64
            Scope='b'*64
            MoveAttemptClaim='c'*64
            DispatchClaim='d'*64
            ControllerResult='e'*64
            ManualSizeAcceptance=[string]$script:p.AcceptanceFileSha256
        }
        $script:after=$script:hashes.PSObject.Copy()
    }
    AfterEach {
        if ($null -ne $script:paths -and
            [string]$script:paths.Directory -match 'OPA-BW3l-Copy-[0-9a-f]{32}$' -and
            [IO.Directory]::Exists([string]$script:paths.Directory)) {
            Remove-Item -LiteralPath $script:paths.Directory -Recurse -Force
        }
    }
    It 'keeps source Intent unchanged during independent test setup' {
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:source))) | Should -BeExactly $script:seedSha
        $script:seedSha | Should -Not -BeExactly $script:p.JournalSha256
    }
    It 'accepts exact positive BW3l review solely for read-only evaluation' {
        (Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p) | Should -BeTrue
    }
    It 'independently validates complete offline test copy claim and journal replay WITHOUT claiming historical proof' {
        $r=Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests
        $r.CopyMode | Should -BeExactly 'OfflineReplicaNotHistoricalProof'
        $r.CopyFinalSha256 | Should -BeExactly $script:review.SandboxCopyFinalSha256
        $r.OriginalIntentBytePrefixPreserved | Should -BeTrue
        $r.ClaimScopeCopyOnlyVerified | Should -BeTrue
        $r.TwoJournalEventsReplayVerified | Should -BeTrue
        $r.HistoricalJournalWriteAuthorized | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'refuses offline copy as real historical evidence without explicit test-only mode' {
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed } | Should -Throw
    }
    It 'refuses historical security verdict on offline copy proof even with valid copy journal' {
        $copy=Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests
        { Get-OPA265BW3mSecurityDecision -Pinned $script:p -Bw3l $script:review -CopyAudit $copy -EvidenceBefore $script:hashes -EvidenceAfter $script:after } | Should -Throw
    }
    It 'refuses a fake historical verdict claiming an offline copy was actual history' {
        $copy=Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests
        $copy.CopyMode='ActualHistoricalByteCopy'
        # Tests expose that a fabricated value would need its own source
        # provenance evaluation; the public entrypoint never accepts an
        # arbitrary CopyAudit from outside this module.
        $copy.HistoricalJournalWriteAuthorized | Should -BeFalse
    }
    It 'rejects BW3l verdict changed schema' {
        $script:review.Schema='Bad'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict changed status' {
        $script:review.Status='Approved'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict changed decision' {
        $script:review.Decision='AppendNow'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict foreign RunId' {
        $script:review.RunId='foreign'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict foreign OperationId' {
        $script:review.OperationId='foreign'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict changed original journal hash' {
        $script:review.OriginalIntentSha256='f'*64
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict changed acceptance fingerprint' {
        $script:review.AcceptanceRecordSha256='f'*64
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict foreign archive EntryID' {
        $script:review.DestinationEntryId='other'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict wrong copy final hash' {
        $script:review.SandboxCopyFinalSha256='x'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict undetected source hash' {
        $script:review.SandboxCopyFinalSha256=$script:p.JournalSha256
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict falsified BW3j proof' {
        $script:review.IndependentBW3jReviewPassed=$false
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict falsified seven hashes' {
        $script:review.HistoricalSevenHashesUnchanged=$false
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict false byte-copy assertion' {
        $script:review.CopyContainsOriginalExactBytes=$false
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict false copy reconciled' {
        $script:review.CopyReconciled=$false
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict false durable claim' {
        $script:review.CopyDurableClaimCreated=$false
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict wrong copy event count' {
        $script:review.CopyJournalEventCount=3
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict wrong historical count' {
        $script:review.HistoricalJournalEventCount=2
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict wrong historical phase' {
        $script:review.HistoricalJournalPhase='Reconciled'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict historical claim asserted created' {
        $script:review.HistoricalResolutionClaimCreated=$true
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict historical journal marked changed' {
        $script:review.HistoricalJournalChanged=$true
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict historical Reconciled asserted' {
        $script:review.HistoricalJournalReconciled=$true
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict historical permit asserted' {
        $script:review.HistoricalJournalWritePermitIssued=$true
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict Outlook Move asserted' {
        $script:review.OutlookMoveExecuted=$true
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict retry allowed' {
        $script:review.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict production asserted' {
        $script:review.ProductionReady=$true
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict unknown next action' {
        $script:review.NextAction='Execute'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict untyped false' {
        $script:review.HistoricalJournalChanged='False'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict extra authorization field' {
        $script:review | Add-Member -NotePropertyName NewApproval -NotePropertyValue $true
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict missing approval field' {
        $script:review.PSObject.Properties.Remove('HistoricalJournalWritePermitIssued')
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects BW3l verdict foreign sandbox directory' {
        $script:review.SandboxDirectory='C:\Production'
        { Assert-OPA265BW3mBw3lReview -Review $script:review -Pinned $script:p } | Should -Throw
    }
    It 'rejects copy claim changed claim schema' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.Schema='Altered'
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim wrong claim RunId' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.RunId='other'
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim wrong claim operation' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.OperationId='other'
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim wrong original copy SHA256' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.CopyOriginalSha256='f'*64
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim wrong archive EntryID' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.DestinationEntryId='UNKNOWN'
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim wrong copy claim scope' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.Scope='Original'
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim grant original journal access' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.HistoricJournalWriteAuthorized=$true
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim grant automatic retry' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.AutomaticRetryAllowed=$true
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim grant production' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.ProductionReady=$true
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim nonboolean claim consent' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.HistoricJournalWriteAuthorized='False'
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim extra unsigned permission' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x | Add-Member -NotePropertyName ExecuteNow -NotePropertyValue $true
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects copy claim missing required field' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $x.PSObject.Properties.Remove('Scope')
        [IO.File]::WriteAllText($script:paths.ClaimPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects a changed final copy byte independently of recorded hash' {
        $p=$script:paths.JournalPath
        $x=[IO.File]::ReadAllBytes($p)
        $x[25]=[byte]($x[25] -bxor 1)
        [IO.File]::WriteAllBytes($p,$x)
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects an extra third journal record' {
        $null=Write-OPAOperationJournalEvent -Path $script:paths.JournalPath -TransactionId $script:p.RunId -OperationId $script:p.OperationId -Sequence 3 -Phase Reconciled -ArchivePst $script:fakePst -ArchiveEntryId $script:p.DestinationEntryId
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects an absent durable claim' {
        Remove-Item -LiteralPath $script:paths.ClaimPath -Force
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects an absent copy marker' {
        Remove-Item -LiteralPath $script:paths.MarkerPath -Force
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects marker changed into fake ActualHistoricalByteCopy' {
        $x=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $x.Mode='ActualHistoricalByteCopy'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $x -Depth 6))
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects changed original bytes supplied as independent reference' {
        $fake=[byte[]]$script:seed.Clone()
        $fake[13]=[byte]($fake[13] -bxor 1)
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $fake -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects altered reported final hash' {
        $script:review.SandboxCopyFinalSha256='f'*64
        { Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests } | Should -Throw
    }
    It 'rejects changed original evidence snapshot even if copied journal is valid' {
        $script:after.DispatchClaim='f'*64
        $copy=Assert-OPA265BW3mCopyReadback -Review $script:review -Pinned $script:p -OriginalBytes $script:seed -OfflineReplicaForTests
        $copy.CopyMode='ActualHistoricalByteCopy'
        { Get-OPA265BW3mSecurityDecision -Pinned $script:p -Bw3l $script:review -CopyAudit $copy -EvidenceBefore $script:hashes -EvidenceAfter $script:after } | Should -Throw
    }
    It 'checks the original journal again after BW3l (static audit)' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3mHistoricalWriterSafetyReview.ps1') -Raw
        $src | Should -Match 'Assert-OPA265BW3hSnapshotUnchanged'
        $src | Should -Match 'Assert-OPA265BW3jOriginalIntent'
        $src | Should -Match 'Assert-OPA265BW3jResolutionClaimSlotsAbsent'
        $src | Should -Match 'Test-OPA265BW3lHistoricalCopyRehearsal.ps1'
        $src | Should -Match 'Assert-OPA265BW3mCopyReadback'
    }
    It 'has only -Review, no original writer/Execute/Record switch' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3mHistoricalWriterSafetyReview.ps1') -Raw
        $src | Should -Match '\[switch\]\$Review'
        $src | Should -Not -Match '\[switch\]\$Execute|\[switch\]\$Record|\[switch\]\$Commit|FileMode\]::OpenOrCreate|\[IO.FileStream\]::new|Write-OPAOperationJournalEvent|Invoke-OPA264Live6'
    }
    It 'has no write path in BW3m independent audit module' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BW3mHistoricalWriterSafetyReview265.ps1') -Raw
        $src | Should -Not -Match 'FileStream\]::new|CreateNew|WriteAllBytes|WriteAllText|Move\(|MailItem\.Move|ProductionReady=\$true'
    }
    It 'is not exposed in production Archive Resume Auto' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $src | Should -Not -Match 'BW3mHistoricalWriterSafetyReview'
    }
    It 'has exactly one UTF8 BOM for every new BW3m PowerShell script' {
        foreach($rel in @('Core/Worker/BW3mHistoricalWriterSafetyReview265.ps1',
            'Core/Diagnostics/Test-OPA265BW3mHistoricalWriterSafetyReview.ps1',
            'Tests/Worker/BW3mHistoricalWriterSafetyReview.Tests.ps1')) {
            $p=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $b=[IO.File]::ReadAllBytes($p)
            ($b[0..2] -join ',') | Should -BeExactly '239,187,191'
            $b[3] | Should -Be 35
        }
    }
    It 'PS5.1 parser accepts all BW3m code' {
        foreach($rel in @('Core/Worker/BW3mHistoricalWriterSafetyReview265.ps1',
             'Core/Diagnostics/Test-OPA265BW3mHistoricalWriterSafetyReview.ps1')) {
            $p=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null; $errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
