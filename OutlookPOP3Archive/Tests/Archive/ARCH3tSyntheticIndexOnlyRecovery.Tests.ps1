#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3tSyntheticIndexOnlyRecovery.ps1')
}
Describe 'ARCH3t independently recover missing ORIGINAL index rows in fake OS TEMP only' {
    BeforeEach {
        $script:partial=Invoke-OPA265ARCH3sTen -Mode Integration -JournalFault AfterIndexAppend -FaultAt 2 -SyntheticTempRoot $TestDrive
        $script:pin=@{
            Workspace=[string]$script:partial.OriginalJournalWorkspace
            ExpectedJournalSha256=[string]$script:partial.OriginalJournalSha256
            ExpectedIndexSha256=[string]$script:partial.OriginalSharedIndexSha256
        }
    }
    It 'audits 10 Reconciled and 2 original indexed entries without writing journal or index' {
        $p=Join-Path $script:pin.Workspace 'OutlookPOP3Archive-Transactions/DuplicateIndex.jsonl'
        $before=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
        $r=Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Audit -Workspace $script:pin.Workspace
        $r.Status | Should -BeExactly 'ReadyForSyntheticMissingIndexOnly'
        $r.JournalEventCount | Should -Be 20
        $r.JournalReconciledCount | Should -Be 10
        $r.IndexedCount | Should -Be 2
        @($r.MissingNumbers).Count | Should -Be 8
        $r.OriginalArchiveVerifierPassed | Should -BeTrue
        $r.RealMailMovePerformed | Should -BeFalse
        (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash | Should -BeExactly $before
    }
    It 'recovers precisely eight original missing index rows without Move or second Reconciled' {
        $r=Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Recover @script:pin -ConfirmSyntheticRecovery -Confirm:$false
        $r.Status | Should -BeExactly 'RecoveredMissingSyntheticIndexOnlyNoMove'
        $r.IndexedCount | Should -Be 10
        $r.JournalEventCount | Should -Be 20
        $r.OriginalJournalSha256 | Should -BeExactly $script:pin.ExpectedJournalSha256
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $r.AutomaticMoveRetryAllowed | Should -BeFalse
    }
    It 'is idempotent on a second audit and Recover with freshly pinned completed index SHA' {
        $first=Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Recover @script:pin -ConfirmSyntheticRecovery -Confirm:$false
        $again=Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Recover -Workspace $script:pin.Workspace -ExpectedJournalSha256 $first.OriginalJournalSha256 -ExpectedIndexSha256 $first.OriginalIndexSha256 -ConfirmSyntheticRecovery -Confirm:$false
        $again.Status | Should -BeExactly 'AlreadyFullyIndexedNoWrites'
        $again.OriginalIndexSha256 | Should -BeExactly $first.OriginalIndexSha256
    }
    It 'WhatIf does not append records or alter pinned SHA' {
        $r=Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Recover @script:pin -ConfirmSyntheticRecovery -WhatIf
        $r.Status | Should -BeExactly 'WhatIfSyntheticRecoveryNoWrites'
        $after=Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Audit -Workspace $script:pin.Workspace
        $after.IndexedCount | Should -Be 2
        $after.OriginalIndexSha256 | Should -BeExactly $script:pin.ExpectedIndexSha256
    }
    It 'requires explicit operator confirmation before any index append' {
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Recover @script:pin -Confirm:$false} | Should -Throw
    }
    It 'rejects wrong journal SHA pin' {
        $script:pin.ExpectedJournalSha256='0'*64
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Recover @script:pin -ConfirmSyntheticRecovery -Confirm:$false} | Should -Throw
    }
    It 'rejects wrong index SHA pin' {
        $script:pin.ExpectedIndexSha256='f'*64
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Recover @script:pin -ConfirmSyntheticRecovery -Confirm:$false} | Should -Throw
    }
    It 'rejects 3 Reconciled and 0 indexed; cannot infer unverified items' {
        $p=Invoke-OPA265ARCH3sTen -Mode Integration -JournalFault AfterJournalReconciled -FaultAt 3 -SyntheticTempRoot $TestDrive
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Audit -Workspace $p.OriginalJournalWorkspace} | Should -Throw
    }
    It 'rejects conflicting destination even if original last-wins importer could load it' {
        $p=Join-Path $script:pin.Workspace 'OutlookPOP3Archive-Transactions/DuplicateIndex.jsonl'
        $lines=[IO.File]::ReadAllLines($p)
        $first=ConvertFrom-Json -InputObject $lines[0]
        $first.ArchiveEntryId='CONFLICT'
        $lines[0]=ConvertTo-Json -InputObject $first -Compress -Depth 8
        [IO.File]::WriteAllText($p,(($lines -join [Environment]::NewLine)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Audit -Workspace $script:pin.Workspace} | Should -Throw
    }
    It 'rejects duplicate raw JSONL source even when last-wins de-duplicates the imported view' {
        $p=Join-Path $script:pin.Workspace 'OutlookPOP3Archive-Transactions/DuplicateIndex.jsonl'
        $first=[IO.File]::ReadAllLines($p)[0]
        [IO.File]::AppendAllText($p,($first+[Environment]::NewLine))
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Audit -Workspace $script:pin.Workspace} | Should -Throw
    }
    It 'rejects missing original synthetic provider claim before index recovery' {
        Remove-Item -LiteralPath (Join-Path $script:pin.Workspace 'SYNTH-ProviderInvocation-7.json') -Force
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Audit -Workspace $script:pin.Workspace} | Should -Throw
    }
    It 'rejects truncated append-only index tail without repairing it' {
        $p=Join-Path $script:pin.Workspace 'OutlookPOP3Archive-Transactions/DuplicateIndex.jsonl'
        [IO.File]::AppendAllText($p,'{')
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Audit -Workspace $script:pin.Workspace} | Should -Throw
    }
    It 'rejects any directory not nested below exact ARCH3s ARCH3r fake TEMP workspace' {
        {Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Audit -Workspace $TestDrive} | Should -Throw
    }
    It 'never contains real Outlook Move, COM attach, or PST mount and uses UTF-8 BOM' {
        foreach($path in @('Invoke-ARCH3t.ps1','Core/Archive/ARCH3tSyntheticIndexOnlyRecovery.ps1')){
            $full=Join-Path $script:root $path
            $bytes=[IO.File]::ReadAllBytes($full)
            (@($bytes[0..2]) -join ',') | Should -BeExactly '239,187,191'
            $c=Get-Content -LiteralPath $full -Raw -Encoding UTF8
            $c | Should -Not -Match '\\.Move\\s*\\('
            $c | Should -Not -Match 'GetActiveObject\\s*\\('
            $c | Should -Not -Match 'AddStoreEx\\s*\\('
        }
    }
    It 'recovers after exactly one original index append at the first failpoint' {
        $p=Invoke-OPA265ARCH3sTen -Mode Integration -JournalFault AfterIndexAppend -FaultAt 1 -SyntheticTempRoot $TestDrive
        $r=Invoke-OPA265ARCH3tIndexOnlyRecovery -Mode Recover -Workspace $p.OriginalJournalWorkspace -ExpectedJournalSha256 $p.OriginalJournalSha256 -ExpectedIndexSha256 $p.OriginalSharedIndexSha256 -ConfirmSyntheticRecovery -Confirm:$false
        $r.IndexedCount | Should -Be 10
        $r.JournalReconciledCount | Should -Be 10
    }
}
