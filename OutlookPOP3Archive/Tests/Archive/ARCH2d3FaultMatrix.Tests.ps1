#requires -Version 5.1
# ARCH2d3 synthetic-only verification; never accesses Outlook or real PSTs.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Diagnostics/ARCH2d3FaultSimulator.ps1')
    $script:matrix=Invoke-OPA265ARCH2d3SyntheticMatrix -SandboxRoot $TestDrive
}
Describe 'ARCH2d3 isolated 57-case 1/5/10 failure injection (no Outlook)' {
    It 'covers exactly 57 models including 54 injected faults' {
        $script:matrix.Cases | Should -Be 57
        $script:matrix.InjectedFaultCases | Should -Be 54
        $script:matrix.ResultRows.Count | Should -Be 57
    }
    It 'executes each of nineteen fault types at ordinal 1,5,10' {
        $script:matrix.Scenarios.Count | Should -Be 19
        foreach($fault in $script:matrix.Scenarios){
            @($script:matrix.ResultRows|Where-Object{$_.Fault -ceq $fault}).Count | Should -Be 3
        }
    }
    It 'never connects Outlook or reads/writes physical PST for any of 57 cases' {
        @($script:matrix.ResultRows|Where-Object{$_.ActualOutlookContacted -or $_.ActualPstReadOrWritten}).Count | Should -Be 0
    }
    It 'never grants an automatic retry even after simulated zero COM operations' {
        @($script:matrix.ResultRows|Where-Object{$_.AutomaticRetryAllowed -or -not $_.ReplayBlocked}).Count | Should -Be 0
    }
    It 'models real production force-flushed immutable writer, not an in-memory-only claim' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/ARCH2d3FaultSimulator.ps1') -Raw -Encoding UTF8
        $src | Should -Match 'Write-OPA265ARCH2c4JsonOnce -Path \$globalPath'
        $src | Should -Match 'Write-OPA265ARCH2c4JsonOnce -Path \$row\.ClaimPath'
        $src | Should -Match 'Read-OPA265ARCH2c4JsonSealed -Path \$row\.ClaimPath'
    }
    It 'all non-fault simulations fully reconcile exactly 10 and retain no-retry seal' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'None'})){
            $r.Status | Should -BeExactly 'SyntheticTenAttempted'
            $r.FakeComMoveCalls | Should -Be 10
            $r.VerifiedMoved | Should -Be 10
            $r.IndividualClaims | Should -Be 10
            $r.ReturnObservations | Should -Be 10
            $r.IndependentlyVerifiedAllTen | Should -BeTrue
            $r.ReconcileStatus | Should -BeExactly 'AllTenIndependentPostRestartSemanticMatches'
        }
    }
    It 'a global collision preempts ALL fake COM work' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'GlobalClaimCollision'})){
            $r.FakeComMoveCalls | Should -Be 0
            $r.IndividualClaims | Should -Be 0
            $r.GlobalClaimValid | Should -BeFalse
            $r.ReconcileStatus | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
        }
    }
    It 'torn global claim preempts ALL fake COM work and cannot be parsed as valid' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'GlobalClaimTornWrite'})){
            $r.FakeComMoveCalls | Should -Be 0
            $r.GlobalClaimExists | Should -BeTrue
            $r.GlobalClaimValid | Should -BeFalse
            $r.IndependentlyVerifiedAllTen | Should -BeFalse
        }
    }
    It 'after global claim before item 1 no move can have happened' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'AfterGlobalClaimBeforeFirstItem'})){
            $r.GlobalClaimValid | Should -BeTrue
            $r.IndividualClaims | Should -Be 0
            $r.FakeComMoveCalls | Should -Be 0
            $r.VerifiedMoved | Should -Be 0
            $r.ReconcileStatus | Should -BeExactly 'PartialBatchVerifiedButNoResumePermit'
        }
    }
    It 'source preflight mismatch before global claim stops without even a global claim' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'ChangedOriginalBeforeGlobalClaim'})){
            $r.GlobalClaimExists | Should -BeFalse
            $r.FakeComMoveCalls | Should -Be 0
            $r.IndividualClaims | Should -Be 0
            $r.ReplayBlocked | Should -BeTrue
        }
    }
    It 'tampered or torn per-item claim is never interpreted as complete evidence' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{
            $_.Fault -in @('ItemClaimCollision','ItemClaimTornWrite')
        })){
            $r.BadEvidenceCount | Should -BeGreaterThan 0
            $r.ReconcileStatus | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
            $r.IndependentlyVerifiedAllTen | Should -BeFalse
        }
    }
    It 'silent fake COM no-apply failure never proves moved' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'ComThrowsWithoutApply'})){
            $r.VerifiedMoved | Should -Be ($r.FaultAt-1)
            $r.IndividualClaims | Should -Be $r.FaultAt
            $r.FakeComMoveCalls | Should -Be $r.FaultAt
            $r.IndependentlyVerifiedAllTen | Should -BeFalse
        }
    }
    It 'fake COM applies but throws; missing return never authorizes retry' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'ComAppliesThenThrows'})){
            $r.VerifiedMoved | Should -Be $r.FaultAt
            $r.IndividualClaims | Should -Be $r.FaultAt
            $r.ReturnObservations | Should -Be ($r.FaultAt-1)
            $r.MissingOrBadReturnCount | Should -BeGreaterThan 0
            $r.AutomaticRetryAllowed | Should -BeFalse
        }
    }
    It 'fake COM returns before durable return observation: no blind rerun' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'ComReturnsBeforeReceipt'})){
            $r.VerifiedMoved | Should -Be $r.FaultAt
            $r.ReturnObservations | Should -Be ($r.FaultAt-1)
            $r.ReplayBlocked | Should -BeTrue
        }
    }
    It 'torn/colliding return receipt is diagnostic evidence requiring manual review' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{
            $_.Fault -in @('ReturnReceiptCollision','ReturnReceiptTornWrite')
        })){
            $r.BadEvidenceCount | Should -BeGreaterThan 0
            $r.ReconcileStatus | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
            $r.ReplayBlocked | Should -BeTrue
        }
    }
    It 'fake Outlook restart absent never certifies independent reconciliation' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'NoRestart'})){
            $r.RestartConfirmed | Should -BeFalse
            $r.IndependentlyVerifiedAllTen | Should -BeFalse
        }
    }
    It 'corrupted destination Body fails semantic comparison after Move' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'ChangedDestinationBody'})){
            $r.VerifiedMoved | Should -Be 9
            $r.IndependentlyVerifiedAllTen | Should -BeFalse
            $r.ReconcileStatus | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
        }
    }
    It 'unknown MAPI source status cannot be treated as absent' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'UnknownSourceProvider'})){
            $r.VerifiedMoved | Should -Be 9
            $r.IndependentlyVerifiedAllTen | Should -BeFalse
            $r.ReconcileStatus | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
        }
    }
    It 'an unexpected duplicate in destination fails whole-batch verification' {
        foreach($r in @($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'DuplicateDestination'})){
            $r.FakeDestinationCount | Should -Be 11
            $r.ReconcileStatus | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
            $r.IndependentlyVerifiedAllTen | Should -BeFalse
        }
    }
    It 'crash just after final tenth return can be fully verified without replay' {
        $r=@($script:matrix.ResultRows|Where-Object{
            $_.Fault -eq 'AfterReturnCrash' -and $_.FaultAt -eq 10
        })[0]
        $r.IndividualClaims | Should -Be 10
        $r.ReturnObservations | Should -Be 10
        $r.VerifiedMoved | Should -Be 10
        $r.IndependentlyVerifiedAllTen | Should -BeTrue
        $r.ReplayBlocked | Should -BeTrue
    }
    It 'crash after 5th successful Move keeps 5 later originals untouched and NO resume permit' {
        $r=@($script:matrix.ResultRows|Where-Object{
            $_.Fault -eq 'AfterReturnCrash' -and $_.FaultAt -eq 5
        })[0]
        $r.VerifiedMoved | Should -Be 5
        $r.NotAttempted | Should -Be 5
        $r.ReconcileStatus | Should -BeExactly 'PartialBatchVerifiedButNoResumePermit'
    }
    It 'immutable writer refuses overwrite of existing journal/claim regardless of RunId' {
        $r=@($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'None'})[0]
        $global=Join-Path $r.SandboxCaseDirectory 'ARCH2d-BATCH-ONCE-CLAIM.json'
        $bytes=[IO.File]::ReadAllBytes($global)
        {Write-OPA265ARCH2c4JsonOnce -Path $global -Value ([pscustomobject]@{RunId='NEW'})} | Should -Throw
        ([Convert]::ToBase64String([IO.File]::ReadAllBytes($global))) | Should -BeExactly ([Convert]::ToBase64String($bytes))
    }
    It 'original returned claim has verifiable SHA256 seal and cannot be written twice' {
        $r=@($script:matrix.ResultRows|Where-Object{$_.Fault -eq 'None'})[0]
        $p=Join-Path $r.SandboxCaseDirectory 'move-05-claim.json'
        $sha=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
        $v=Read-OPA265ARCH2c4JsonSealed -Path $p -ExpectedSha256 $sha
        $v.Ordinal | Should -Be 5
        $v.ClaimedBeforeComMove | Should -BeTrue
        $v.AutomaticRetryAllowed | Should -BeFalse
        {Write-OPA265ARCH2c4JsonOnce -Path $p -Value $v} | Should -Throw
    }
    It 'tampered persisted claim fails original SHA256 seal verification' {
        $p=Join-Path $TestDrive ('ARCH2d3-tamper-'+[guid]::NewGuid().ToString('N')+'.json')
        $sha=Write-OPA265ARCH2c4JsonOnce -Path $p -Value ([pscustomobject]@{Schema='original'})
        [IO.File]::WriteAllText($p,'{"Schema":"forged"}')
        {Read-OPA265ARCH2c4JsonSealed -Path $p -ExpectedSha256 $sha} | Should -Throw
    }
    It 'torn JSON cannot be accepted as immutable original evidence' {
        $p=Join-Path $TestDrive ('ARCH2d3-torn-'+[guid]::NewGuid().ToString('N')+'.json')
        [IO.File]::WriteAllBytes($p,[byte[]]@(123,34,100))
        $sha=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
        {Read-OPA265ARCH2c4JsonSealed -Path $p -ExpectedSha256 $sha} | Should -Throw
    }
    It 'fault simulation is not shipped as a permission to move real Outlook MailItems' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/ARCH2d3FaultSimulator.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match 'GetActiveObject\s*\('
        $s | Should -Not -Match '\.Move\s*\('
        $s | Should -Not -Match '\.AddStoreEx\s*\('
        $s | Should -Not -Match '\.SaveAsFile\s*\('
        $s | Should -Not -Match 'Remove-Item'
    }
    It 'main Archive, Resume and Auto are still blocked' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
    }
    It 'refuses to use the historical ARCH2d REAL pilot folder as synthetic sandbox' {
        $real=Join-Path $TestDrive 'OutlookPOP3Archive-ARCH2d-RealBatch10'
        [void][IO.Directory]::CreateDirectory($real)
        {Invoke-OPA265ARCH2d3SyntheticFault -SandboxRoot $real -Fault None} | Should -Throw
    }
    It 'refuses to use the historical ARCH2c4 REAL pilot folder as synthetic sandbox' {
        $real=Join-Path $TestDrive 'OutlookPOP3Archive-ARCH2c4-RealPilot'
        [void][IO.Directory]::CreateDirectory($real)
        {Invoke-OPA265ARCH2d3SyntheticFault -SandboxRoot $real -Fault None} | Should -Throw
    }
    It 'reconciles each case using original ARCH2d independent decision function' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/ARCH2d3FaultSimulator.ps1') -Raw -Encoding UTF8
        $src | Should -Match 'Get-OPA265ARCH2dReconcileDecision -ItemResults'
    }
}
Describe 'ARCH2d3 every indexed failure case is durably fenced' {
    $all=@(
        'None','GlobalClaimCollision','GlobalClaimTornWrite','AfterGlobalClaimBeforeFirstItem',
        'ItemClaimCollision','ItemClaimTornWrite','AfterItemClaimBeforeCom',
        'ComThrowsWithoutApply','ComAppliesThenThrows','ComReturnsBeforeReceipt',
        'ReturnReceiptCollision','ReturnReceiptTornWrite','AfterReturnCrash',
        'ChangedOriginalBeforeGlobalClaim','ChangedOriginalBeforeItemClaim',
        'ChangedDestinationBody','UnknownSourceProvider','DuplicateDestination','NoRestart'
    )
    $cases=@(foreach($caseName in $all){
        foreach($index in @(1,5,10)){
            @{ Fault=$caseName; FaultAt=$index }
        }
    })
    It 'never grants replay after <Fault> @ <FaultAt>' -TestCases $cases {
        param([string]$Fault,[int]$FaultAt)
        $case=@($script:matrix.ResultRows|Where-Object {
            $_.Fault -ceq $Fault -and $_.FaultAt -eq $FaultAt
        })[0]
        $case | Should -Not -BeNullOrEmpty
        $case.ReplayBlocked | Should -BeTrue
        $case.AutomaticRetryAllowed | Should -BeFalse
        $case.ActualOutlookContacted | Should -BeFalse
        $case.ActualPstReadOrWritten | Should -BeFalse
        if($Fault -eq 'None'){
            $case.IndependentlyVerifiedAllTen | Should -BeTrue
        }elseif($Fault -in @('GlobalClaimCollision','GlobalClaimTornWrite',
            'ChangedOriginalBeforeGlobalClaim')){
            $case.FakeComMoveCalls | Should -Be 0
        }elseif($Fault -in @('ItemClaimCollision','ItemClaimTornWrite',
            'AfterItemClaimBeforeCom','ChangedOriginalBeforeItemClaim')){
            $case.FakeComMoveCalls | Should -Be ($FaultAt-1)
        }
    }
}
