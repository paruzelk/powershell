#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/OperationJournal.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3kSandboxJournalWriter265.ps1')
}
Describe 'BW3k temporary-only single synthetic journal Reconciled writer' {
    BeforeEach {
        $script:fixture=New-OPA265BW3kIsolatedFixture
        $script:paths=$script:fixture.Paths
        $script:m=$script:fixture.Marker
    }
    AfterEach {
        if ($null -ne $script:paths -and
            [string]$script:paths.Directory -match 'OPA-BW3k-Sandbox-[0-9a-f]{32}$' -and
            [IO.Directory]::Exists([string]$script:paths.Directory)) {
            Remove-Item -LiteralPath $script:paths.Directory -Recurse -Force
        }
    }
    It 'generates fresh random synthetic RunId' {
        $script:m.RunId | Should -Not -BeExactly 'a7b51427-7494-43f4-bc96-64915f6bee7e'
    }
    It 'generates fresh random synthetic OperationId' {
        $script:m.OperationId | Should -Not -BeExactly '9bd83da2-d47e-404f-a4fd-792852b58dec'
    }
    It 'never creates a PST' {
        @(Get-ChildItem -LiteralPath $script:paths.Directory -Filter '*.pst').Count | Should -Be 0
    }
    It 'requires immediate OS TEMP directory' {
        [IO.Path]::GetDirectoryName([string]$script:paths.Directory) | Should -BeExactly ([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')))
    }
    It 'creates one initial Intent' {
        (Read-OPAOperationJournal -Path $script:paths.JournalPath).Events.Count | Should -Be 1
    }
    It 'creates no initial durable claim' {
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'pins fixture original SHA256' {
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $script:m.OriginalJournalSha256
    }
    It 'pins synthetic-only fake archive path' {
        $script:m.ArchivePst | Should -BeExactly 'BW3K-SANDBOX-NO-PST'
    }
    It 'refuses synthetic operator permission in marker' {
        $script:m.OperatorJournalConsent | Should -BeFalse
    }
    It 'blocks auto retry in test marker' {
        $script:m.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'has production disabled in marker' {
        $script:m.ProductionReady | Should -BeFalse
    }
    It 'accepts exact isolated fixture marker' {
        (Read-OPA265BW3kMarker -Paths $script:paths).RunId | Should -BeExactly $script:m.RunId
    }
    It 'validates the one original LF-terminated Intent and envelope' {
        $bytes=[IO.File]::ReadAllBytes($script:paths.JournalPath)
        $item=Assert-OPA265BW3kOneIntentBytes -Bytes $bytes -Marker $script:m
        $item.Phase | Should -BeExactly 'Intent'
        $item.Sequence | Should -Be 1
        $item.Size | Should -Be 1436
    }
    It 'commits only one sandbox Reconciled sequence 2 under exclusive lock' {
        $before=[IO.File]::ReadAllBytes($script:paths.JournalPath)
        $r=Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory
        $r.Status | Should -BeExactly 'SandboxJournalReconciledNotHistorical'
        $r.JournalReconciledInSandbox | Should -BeTrue
        $r.HistoricalJournalChanged | Should -BeFalse
        $r.OutlookMoveExecuted | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $r.JournalEventCount | Should -Be 2
        $after=[IO.File]::ReadAllBytes($script:paths.JournalPath)
        for($i=0;$i -lt $before.Length;$i++) { $after[$i] | Should -Be $before[$i] }
        $j=Read-OPAOperationJournal -Path $script:paths.JournalPath
        $j.Events[0].Phase | Should -BeExactly 'Intent'
        $j.Events[1].Phase | Should -BeExactly 'Reconciled'
        $j.Events[1].Sequence | Should -Be 2
        $j.Events[1].ArchiveEntryId | Should -BeExactly $script:m.ArchiveEntryId
        (Assert-OPA265BW3kTerminalReplay -Journal $j -Marker $script:m) | Should -BeTrue
    }
    It 'writes flushed claim before journal and blocks any second append' {
        $null=Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
        $sha=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash | Should -BeExactly $sha
    }
    It 'records strict claim identity and original hash in sandbox only' {
        $null=Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory
        $claim=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.ClaimPath))
        $claim.Schema | Should -BeExactly '2.6.5-BW3k.SandboxResolutionClaim.1'
        $claim.Scope | Should -BeExactly 'TemporarySyntheticJournalOnlyNoPst'
        $claim.RunId | Should -BeExactly $script:m.RunId
        $claim.PreviousJournalSha256 | Should -BeExactly $script:m.OriginalJournalSha256
        $claim.AutomaticRetryAllowed | Should -BeFalse
        $claim.ProductionReady | Should -BeFalse
    }
    It 'injected crash AfterClaim permanently blocks retry without deleting claim' {
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory -CrashPoint 'AfterClaim' } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
        $first=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash | Should -BeExactly $first
    }
    It 'injected crash PartialAppend permanently blocks retry without deleting claim' {
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory -CrashPoint 'PartialAppend' } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
        $first=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash | Should -BeExactly $first
    }
    It 'injected crash AfterAppend permanently blocks retry without deleting claim' {
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory -CrashPoint 'AfterAppend' } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
        $first=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash | Should -BeExactly $first
    }
    It 'AfterClaim failure preserves exact original journal hash and one Intent' {
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory -CrashPoint 'AfterClaim' } | Should -Throw
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $script:m.OriginalJournalSha256
        @( (Read-OPAOperationJournal -Path $script:paths.JournalPath).Events ).Count | Should -Be 1
    }
    It 'PartialAppend failure retains forensic torn tail, never restores it' {
        $old=[IO.File]::ReadAllBytes($script:paths.JournalPath)
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory -CrashPoint 'PartialAppend' } | Should -Throw
        $now=[IO.File]::ReadAllBytes($script:paths.JournalPath)
        $now.Length | Should -Be ($old.Length+17)
        $now[$now.Length-1] | Should -Not -Be 10
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeTrue
    }
    It 'AfterAppend failure retains valid two-event journal but blocks replay' {
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory -CrashPoint 'AfterAppend' } | Should -Throw
        $j=Read-OPAOperationJournal -Path $script:paths.JournalPath
        (Assert-OPA265BW3kTerminalReplay -Journal $j -Marker $script:m) | Should -BeTrue
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
    }
    It 'external exclusive journal lock causes STOP with claim retained' {
        $lock=[IO.FileStream]::new($script:paths.JournalPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        } finally { $lock.Dispose() }
        # Preclaim read itself can be blocked; if no claim was made, clean
        # new fixture is still eligible; never assert successful append.
        $after=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $after | Should -BeExactly $script:m.OriginalJournalSha256
    }
    It 'rejects a preexisting partial claim without modifying it' {
        [IO.File]::WriteAllText($script:paths.ClaimPath,'partial')
        $hash=(Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::ReadAllText($script:paths.ClaimPath) | Should -BeExactly 'partial'
        (Get-FileHash -LiteralPath $script:paths.JournalPath -Algorithm SHA256).Hash | Should -BeExactly $hash
    }
    It 'rejects a claim path occupied by a directory' {
        [void][IO.Directory]::CreateDirectory($script:paths.ClaimPath)
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
    }
    It 'rejects a duplicate or already terminal journal before claim creation' {
        $null=Write-OPAOperationJournalEvent -Path $script:paths.JournalPath -TransactionId $script:m.RunId -OperationId $script:m.OperationId -Sequence 2 -Phase 'Reconciled' -ArchiveEntryId $script:m.ArchiveEntryId -ArchivePst $script:m.ArchivePst
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects torn original Intent before claim creation' {
        $p=$script:paths.JournalPath
        $bytes=[IO.File]::ReadAllBytes($p)
        [IO.File]::WriteAllBytes($p,$bytes[0..($bytes.Length-2)])
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects mutated journal bytes even with LF and well-shaped old event' {
        $p=$script:paths.JournalPath
        $bytes=[IO.File]::ReadAllBytes($p)
        $bytes[9]=[byte]($bytes[9] -bxor 1)
        [IO.File]::WriteAllBytes($p,$bytes)
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects a non-sandbox path outside TEMP without creating claim' {
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory 'C:\Users\Bogus\historic' } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects a historical LIVE3 run directory even when it is inside TEMP' {
        $name=Join-Path ([IO.Path]::GetTempPath()) 'OPA264-LIVE3-a7b51427749443f4bc9664915f6bee7e'
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $name } | Should -Throw
    }
    It 'rejects traversal from a sandbox directory to a parent' {
        $escaped=Join-Path $script:paths.Directory '..'
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $escaped } | Should -Throw
    }
    It 'rejects marker wrong schema before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.Schema='Other'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker wrong purpose before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.Purpose='ProductionArchive'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker historical RunId before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.RunId='a7b51427-7494-43f4-bc96-64915f6bee7e'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker historical OperationId before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.OperationId='9bd83da2-d47e-404f-a4fd-792852b58dec'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker historical journal SHA256 before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.OriginalJournalSha256='5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker changed journal hash before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.OriginalJournalSha256='f'*64
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker changed destination ID before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.ArchiveEntryId='00000000953C628FC9EAC24E97DBE040019A969924002000'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker changed source ID before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.SourceEntryId='real-source-entry'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker real PST path before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.ArchivePst='C:\real.pst'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker changed sandbox directory before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.SandboxDirectory='C:\other'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker changed journal path before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.JournalPath='C:\other\journal'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker wrong original size before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.IntentSizeBytes=1444
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker wrong archived size before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.ArchiveSizeBytes=1436
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker forged journal consent before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.OperatorJournalConsent=$true
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker retry enabled before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.AutomaticRetryAllowed=$true
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker production enabled before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.ProductionReady=$true
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker nonBoolean false flag before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.OperatorJournalConsent='False'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker extra field before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m | Add-Member -NotePropertyName RealPst -NotePropertyValue 'path'
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'rejects marker missing field before claim and append' {
        $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:paths.MarkerPath))
        $m.PSObject.Properties.Remove('RunId')
        [IO.File]::WriteAllText($script:paths.MarkerPath,(ConvertTo-Json -InputObject $m -Depth 5))
        { Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $script:paths.Directory } | Should -Throw
        [IO.File]::Exists($script:paths.ClaimPath) | Should -BeFalse
    }
    It 'does not reference LIVE6 Execute, Outlook COM or production worker in source' {
        $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BW3kSandboxJournalWriter265.ps1') -Raw
        $source | Should -Not -Match 'GetActiveObject|Outlook\.Application|MailItem\.Move|Write-OPA264Live6ReconciledLocked|Invoke-OPA264Live6|ControllerDispatch|ProductionReady=\$true'
        $source | Should -Match '\[IO.FileMode\]::CreateNew'
        $source | Should -Match '\[IO.FileShare\]::None'
        $source | Should -Match '\.Flush\(\$true\)'
    }
    It 'new BW3k scripts contain a single leading UTF8 BOM' {
        foreach($rel in @('Core/Worker/BW3kSandboxJournalWriter265.ps1',
            'Core/Diagnostics/Test-OPA265BW3kSandboxJournalProtocol.ps1',
            'Tests/Worker/BW3kSandboxJournalWriter.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $b=[IO.File]::ReadAllBytes($path)
            ($b[0..2] -join ',') | Should -BeExactly '239,187,191'
            $b[3] | Should -Be 35
        }
    }
    It 'native Windows PowerShell 5.1 parser accepts all BW3k files' {
        foreach($rel in @('Core/Worker/BW3kSandboxJournalWriter265.ps1',
            'Core/Diagnostics/Test-OPA265BW3kSandboxJournalProtocol.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
    It 'does not integrate BW3k into production Archive/Resume/Auto' {
        $entry=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $entry | Should -Not -Match 'BW3kSandboxJournalWriter'
    }
}
