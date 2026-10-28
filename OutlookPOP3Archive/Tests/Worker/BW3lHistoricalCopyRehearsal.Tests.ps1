#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3gManualSizeAcceptance265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3hIndependentEvidenceChain265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3lHistoricalCopyRehearsal265.ps1')
}
Describe 'BW3l - historical-shaped journal COPY ONLY; never original' {
    BeforeEach {
        $script:p=Get-OPA265BW3hPinnedChain
        $script:seed=Join-Path $TestDrive ('seed-'+[guid]::NewGuid().ToString('N')+'.jsonl')
        $script:archive='BW3L-TEST-NO-PST'
        $evt=@{
            Path=$script:seed
            TransactionId=[string]$script:p.RunId
            OperationId=[string]$script:p.OperationId
            Sequence=1
            Phase='Intent'
            OperationKind='MailMove'
            SourceEntryId='BW3L-OFFLINE-SEED-NO-REAL-MAIL'
            ArchivePst=$script:archive
            InternetMessageId=('<opa264-live3-'+[string]$script:p.RunId+'@example.invalid>')
            Subject=('OPA264 LIVE3 synthetic '+[string]$script:p.RunId)
            Size=1436
        }
        $null=Write-OPAOperationJournalEvent @evt
        $script:seedBytes=[IO.File]::ReadAllBytes($script:seed)
        $script:seedSha=Get-OPAOperationJournalSha256 -Bytes $script:seedBytes
        $script:replica=New-OPA265BW3lCopySandbox -OriginalIntentBytes $script:seedBytes -Pinned $script:p -OfflineReplicaForTests
        $script:paths=$script:replica.Paths
        $script:m=$script:replica.Marker
    }
    AfterEach {
        if ($null -ne $script:paths -and
            [string]$script:paths.Directory -match 'OPA-BW3l-Copy-[0-9a-f]{32}$' -and
            [IO.Directory]::Exists([string]$script:paths.Directory)) {
            Remove-Item -LiteralPath $script:paths.Directory -Recurse -Force
        }
    }
    It 'real original sha differs from offline replica' {
        $script:seedSha | Should -Not -BeExactly $script:p.JournalSha256
    }
    It 'replica never has historical provenance' {
        $script:m.Mode | Should -BeExactly 'OfflineReplicaNotHistoricalProof'
    }
    It 'marker consent is false' {
        $script:m.ConsentToOriginalJournalWrite | Should -BeFalse
    }
    It 'marker production false' {
        $script:m.ProductionReady | Should -BeFalse
    }
    It 'replica stays direct child of OS TEMP' {
        [IO.Path]::GetDirectoryName([string]$script:paths.Directory) | Should -BeExactly ([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')))
    }
    It 'new copied bytes identical to source bytes' {
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:paths.JournalPath))) | Should -BeExactly $script:seedSha
    }
    It 'starts with one Intent' {
        (Read-OPAOperationJournal -Path $script:paths.JournalPath).Events.Count | Should -Be 1
    }
    It 'starts without claim' {
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'copied source is never a PST' {
        $script:archive | Should -BeExactly 'BW3L-TEST-NO-PST'
    }
    It 'enforces pinned historical sha for actual-byte-copy mode before creating a directory' {
        { New-OPA265BW3lCopySandbox -OriginalIntentBytes $script:seedBytes -Pinned $script:p } | Should -Throw
    }
    It 'rejects arbitrary historical nonmatching bytes even in replica mode' {
        $bad=[byte[]]$script:seedBytes.Clone()
        $bad[7]=[byte]($bad[7] -bxor 1)
        { New-OPA265BW3lCopySandbox -OriginalIntentBytes $bad -Pinned $script:p -OfflineReplicaForTests } | Should -Throw
    }
    It 'validates a clean original one Intent for a synthetic offline copy' {
        $r=Assert-OPA265BW3lOneIntent -Bytes $script:seedBytes -Pinned $script:p -ExpectedSha256 $script:seedSha
        $r.OperationId | Should -BeExactly $script:p.OperationId
        $r.Phase | Should -BeExactly 'Intent'
        $r.Size | Should -Be 1436
    }
    It 'returns exact current marker with historical write disallowed' {
        $m=Read-OPA265BW3lCopyMarker -Paths $script:paths -Pinned $script:p
        $m.Mode | Should -BeExactly 'OfflineReplicaNotHistoricalProof'
        $m.ConsentToOriginalJournalWrite | Should -BeFalse
    }
    It 'rehearses real envelope of Reconciled sequence 2 ONLY on the copied journal' {
        $original=Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:seed))
        $r=Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p
        $r.Status | Should -BeExactly 'OnlySandboxCopyReconciledHistoricalJournalUntouched'
        $r.CopyMode | Should -BeExactly 'OfflineReplicaNotHistoricalProof'
        $r.CopyJournalEventCount | Should -Be 2
        $r.CopyReconciled | Should -BeTrue
        $r.CopyDurableClaimCreated | Should -BeTrue
        $r.HistoricalJournalChanged | Should -BeFalse
        $r.HistoricalJournalWriteAuthorized | Should -BeFalse
        $r.OutlookMoveExecuted | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $j=Read-OPAOperationJournal -Path $script:paths.JournalPath
        $j.Events.Count | Should -Be 2
        $j.Events[0].Phase | Should -BeExactly 'Intent'
        $j.Events[1].Phase | Should -BeExactly 'Reconciled'
        $j.Events[1].Sequence | Should -Be 2
        $j.Events[1].ArchiveEntryId | Should -BeExactly $script:p.DestinationEntryId
        $j.Events[1].ArchivePst | Should -BeExactly $script:archive
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:seed))) | Should -BeExactly $original
    }
    It 'creates a durable claim in copy only and forbids second append' {
        $null=Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
        $v=Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:paths.JournalPath))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:paths.JournalPath))) | Should -BeExactly $v
    }
    It 'claim carries copy-only scope and no journal permission' {
        $null=Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p
        $claim=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $claim.Scope | Should -BeExactly 'OS-TEMP-COPY-ONLY-NOT-ORIGINAL'
        $claim.HistoricJournalWriteAuthorized | Should -BeFalse
        $claim.CopyOriginalSha256 | Should -BeExactly $script:seedSha
        $claim.ProductionReady | Should -BeFalse
    }
    It 'injected AfterClaim retains permanent claim and blocks replay' {
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p -CrashPoint 'AfterClaim' } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
        $sha=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash | Should -BeExactly $sha
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:seed))) | Should -BeExactly $script:seedSha
    }
    It 'injected PartialAppend retains permanent claim and blocks replay' {
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p -CrashPoint 'PartialAppend' } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
        $sha=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash | Should -BeExactly $sha
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:seed))) | Should -BeExactly $script:seedSha
    }
    It 'injected AfterAppend retains permanent claim and blocks replay' {
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p -CrashPoint 'AfterAppend' } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
        $sha=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash | Should -BeExactly $sha
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:seed))) | Should -BeExactly $script:seedSha
    }
    It 'AfterClaim preserves copy journal original SHA256' {
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p -CrashPoint 'AfterClaim' } | Should -Throw
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:paths.JournalPath))) | Should -BeExactly $script:seedSha
    }
    It 'PartialAppend preserves torn tail without deleting it' {
        $originalLength=([IO.File]::ReadAllBytes($script:paths.JournalPath)).Length
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p -CrashPoint 'PartialAppend' } | Should -Throw
        $new=[IO.File]::ReadAllBytes($script:paths.JournalPath)
        $new.Length | Should -Be ($originalLength+17)
        $new[$new.Length-1] | Should -Not -Be 10
    }
    It 'AfterAppend leaves valid two-line copy but rejects retry' {
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p -CrashPoint 'AfterAppend' } | Should -Throw
        (Read-OPAOperationJournal -Path $script:paths.JournalPath).Events.Count | Should -Be 2
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
    }
    It 'tampered copy bytes are rejected before creating resolution claim' {
        $b=[IO.File]::ReadAllBytes($script:paths.JournalPath)
        $b[10]=[byte]($b[10] -bxor 1)
        [IO.File]::WriteAllBytes($script:paths.JournalPath,$b)
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'truncated copy Intent is rejected before creating claim' {
        $b=[IO.File]::ReadAllBytes($script:paths.JournalPath)
        [IO.File]::WriteAllBytes($script:paths.JournalPath,$b[0..($b.Length-2)])
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'duplicate or terminal record in copy is rejected before creating claim' {
        $null=Write-OPAOperationJournalEvent -Path $script:paths.JournalPath -TransactionId $script:p.RunId -OperationId $script:p.OperationId -Sequence 2 -Phase Reconciled -ArchiveEntryId $script:p.DestinationEntryId -ArchivePst $script:archive
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'preexisting partial copy claim blocks permanently' {
        [IO.File]::WriteAllText($script:paths.ClaimPath,'partial')
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::ReadAllText($script:paths.ClaimPath) | Should -BeExactly 'partial'
    }
    It 'preexisting claim directory blocks append' {
        [void][IO.Directory]::CreateDirectory($script:paths.ClaimPath)
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
    }
    It 'exclusive external lock blocks append without touching seed' {
        $lock=[IO.FileStream]::new($script:paths.JournalPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        } finally {$lock.Dispose()}
        (Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($script:seed))) | Should -BeExactly $script:seedSha
    }
    It 'blocks any historical LIVE3 directory as writable target' {
        $historical=Join-Path ([IO.Path]::GetTempPath()) 'OPA264-LIVE3-a7b51427749443f4bc9664915f6bee7e'
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $historical -Pinned $script:p } | Should -Throw
    }
    It 'blocks source seed directory as a writable target' {
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $TestDrive -Pinned $script:p } | Should -Throw
    }
    It 'blocks synthetic copy path traversal upward' {
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory (Join-Path $script:paths.Directory '..') -Pinned $script:p } | Should -Throw
    }
    It 'tampered marker new approval rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.ConsentToOriginalJournalWrite=$true
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker nonBoolean approval rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.ConsentToOriginalJournalWrite='False'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker production enabled rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.ProductionReady=$true
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker incorrect run rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.RunId='another'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker incorrect operation rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.OperationId='another'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker changed archive entry rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.DestinationEntryId='unknown'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker changed journal sha rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.OriginalIntentSha256='f'*64
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker pretend to be historical bytes rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.Mode='ActualHistoricalByteCopy'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker unknown mode rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.Mode='Execute'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker modified source path rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.SandboxJournalPath='C:\other\journal'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker modified target directory rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.SandboxDirectory='C:\other'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker changed acceptance sha rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.AcceptanceRecordSha256='f'*64
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker changed pinned original sha rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.HistoricalPinnedSha256='f'*64
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker changed archive PST rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.ArchivePst='C:\production.pst'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker extra untrusted field rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m | Add-Member -NotePropertyName AuthorizeJournal -NotePropertyValue $true
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'tampered marker missing mandatory field rejected without claim' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.PSObject.Properties.Remove('OriginalIntentSha256')
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3lCopyOnlyRehearsal -SandboxDirectory $script:paths.Directory -Pinned $script:p } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'requires native entrypoint explicitly named RehearseVerifiedCopy and no Execute' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3lHistoricalCopyRehearsal.ps1') -Raw
        $src | Should -Match '\[switch\]\$RehearseVerifiedCopy'
        $src | Should -Not -Match '\[switch\]\$Execute|\[switch\]\$Record|MailItem\.Move|Invoke-OPA264Live6'
        $src | Should -Match "Test-OPA265BW3jResolutionDesignReadOnly.ps1"
        $src | Should -Match 'Assert-OPA265BW3hSnapshotUnchanged'
    }
    It 'only write handles in BW3l module use freshly generated sandbox file paths' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BW3lHistoricalCopyRehearsal265.ps1') -Raw
        $src | Should -Not -Match 'FileMode\]::OpenOrCreate|Write-OPA264Live6ReconciledLocked|Outlook\.Application|GetActiveObject|\.Move\(|ProductionReady=\$true'
        $src | Should -Match '\[IO.FileMode\]::CreateNew'
        $src | Should -Match '\[IO.FileShare\]::None'
        $src | Should -Match '\.Flush\(\$true\)'
    }
    It 'has no original journal write handle in public wrapper' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3lHistoricalCopyRehearsal.ps1') -Raw
        $src | Should -Not -Match '\[IO.FileStream\]::new|WriteAllText|WriteAllBytes|Write-OPAOperationJournalEvent|FileMode\]::Append'
        $src | Should -Match '\[IO.File\]::ReadAllBytes\(\[string\]\$paths.JournalPath\)'
    }
    It 'cannot enable original writer in Archive Resume Auto' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $src | Should -Not -Match 'BW3lHistoricalCopyRehearsal'
    }
    It 'new PowerShell source files have exactly one UTF8 BOM' {
        foreach($rel in @('Core/Worker/BW3lHistoricalCopyRehearsal265.ps1',
            'Core/Diagnostics/Test-OPA265BW3lHistoricalCopyRehearsal.ps1',
            'Tests/Worker/BW3lHistoricalCopyRehearsal.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $b=[IO.File]::ReadAllBytes($path)
            ($b[0..2] -join ',') | Should -BeExactly '239,187,191'
            $b[3] | Should -Be 35
        }
    }
    It 'parse BW3l PS5.1 source and diagnostic' {
        foreach($rel in @('Core/Worker/BW3lHistoricalCopyRehearsal265.ps1',
                         'Core/Diagnostics/Test-OPA265BW3lHistoricalCopyRehearsal.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
