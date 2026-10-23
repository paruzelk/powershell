#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerCrashProtocol.ps1')
}

Describe '2.6.4-A deterministic crash policy (no Outlook or COM)' {
    It 'documents exactly eight distinct failure windows' {
        $matrix = @(Get-OPACrashWindowMatrix)
        $matrix.Count | Should -Be 8
        @($matrix | Select-Object -ExpandProperty Name | Select-Object -Unique).Count | Should -Be 8
    }
    It 'keeps all scenario actions disabled at this design stage' {
        foreach ($item in @(Get-OPACrashWindowMatrix)) {
            $item.FaultInjectionEnabled | Should -BeFalse
            $item.MailMoveEnabled | Should -BeFalse
            $item.AutomaticRetryAllowed | Should -BeFalse
            $item.AutomaticCompletionAllowed | Should -BeFalse
            $item.RequiresManualReview | Should -BeTrue
        }
    }
    It 'restricts future scope to a disposable PST pair and owned child only' {
        foreach ($item in @(Get-OPACrashWindowMatrix)) {
            $item.RequiredDataScope | Should -Be 'RunUniqueDisposablePstPair'
            $item.TerminationTarget | Should -Be 'OwnedChildWorkerProcessOnly'
        }
    }
    It 'does not claim deterministic interruption inside synchronous COM Move' {
        (Get-OPACrashWindowDefinition -Name 'DuringMove').DeterministicBarrier | Should -BeFalse
        (Get-OPACrashWindowDefinition -Name 'WorkerTimeoutOrMissingResponse').DeterministicBarrier | Should -BeFalse
        (Get-OPACrashWindowDefinition -Name 'OutlookUnavailable').DeterministicBarrier | Should -BeFalse
    }
    It 'marks the pre-Intent window distinct from every later case' {
        (Get-OPACrashWindowDefinition -Name 'BeforeIntentFlush').DurableIntentExpected | Should -BeFalse
        foreach ($item in @(Get-OPACrashWindowMatrix | Where-Object { $_.Name -ne 'BeforeIntentFlush' })) {
            $item.DurableIntentExpected | Should -BeTrue
        }
    }
    It 'does not assume absence of COM side effects after a timeout' {
        (Get-OPACrashWindowDefinition -Name 'WorkerTimeoutOrMissingResponse').ComMoveMayHaveExecuted | Should -BeTrue
        (Get-OPACrashWindowDefinition -Name 'OutlookUnavailable').ComMoveMayHaveExecuted | Should -BeTrue
    }
    It 'rejects unrecognized crash windows' {
        { Get-OPACrashWindowDefinition -Name 'ProductionWorkerArbitraryMove' } | Should -Throw '*Unknown*'
    }
    It 'generates correlated non-executable plans with explicit test consent requirement' {
        $id = [guid]::NewGuid().ToString('D')
        $plan = New-OPACrashTestPlan -CrashWindow 'AfterMoveBeforeResponse' -RunId $id
        $plan.RunId | Should -Be $id
        $plan.ProtocolVersion | Should -Be '2.6.4-A.1'
        $plan.RequiresExplicitTestApproval | Should -BeTrue
        $plan.OutlookComEnabled | Should -BeFalse
        $plan.WorkerLaunchEnabled | Should -BeFalse
        $plan.WorkerTerminationEnabled | Should -BeFalse
        $plan.MailMoveEnabled | Should -BeFalse
    }
    It 'rejects invalid or all-zero run identifiers' {
        { New-OPACrashTestPlan -CrashWindow 'DuringMove' -RunId 'bad-id' } | Should -Throw '*GUID*'
        { New-OPACrashTestPlan -CrashWindow 'DuringMove' -RunId ([guid]::Empty.ToString('D')) } | Should -Throw '*GUID*'
    }
    It 'generates a new RunId if omitted' {
        $a = New-OPACrashTestPlan -CrashWindow 'AfterIntentBeforeDispatch'
        $b = New-OPACrashTestPlan -CrashWindow 'AfterIntentBeforeDispatch'
        $a.RunId | Should -Not -Be $b.RunId
    }
    It 'accepts properly ordered journal/Worker/Move timeline' {
        { Assert-OPACrashTimeline -IntentFlushed -WorkerStarted -MoveStarted -MoveReturned -ResponseValidated -TerminalFlushed } | Should -Not -Throw
    }
    It 'rejects Worker start before durable Intent' {
        { Assert-OPACrashTimeline -WorkerStarted } | Should -Throw '*Intent*'
    }
    It 'rejects MailMove before Worker start' {
        { Assert-OPACrashTimeline -IntentFlushed -MoveStarted } | Should -Throw '*Worker*'
    }
    It 'rejects Move return before Move start' {
        { Assert-OPACrashTimeline -IntentFlushed -WorkerStarted -MoveReturned } | Should -Throw '*Move started*'
    }
    It 'rejects Worker response without Worker start' {
        { Assert-OPACrashTimeline -IntentFlushed -ResponseValidated } | Should -Throw '*Worker start*'
    }
    It 'rejects terminal journal event without durable Intent' {
        { Assert-OPACrashTimeline -TerminalFlushed } | Should -Throw '*Intent*'
    }
    It 'never retries on a missing, corrupt or truncated journal' {
        foreach ($trust in @('Missing','Corrupt','Truncated')) {
            $decision = Get-OPACrashReplayDirective -CrashWindow 'AfterMoveBeforeResponse' -JournalTrust $trust
            $decision.Classification | Should -Be 'UntrustedOrAbsentJournal'
            $decision.AutomaticRetryAllowed | Should -BeFalse
            $decision.JournalWriteAllowed | Should -BeFalse
        }
    }
    It 'requires independent snapshots for unresolved trusted Intent' {
        $decision = Get-OPACrashReplayDirective -CrashWindow 'DuringMove' -JournalTrust Trusted
        $decision.Classification | Should -Be 'NeedsIndependentSnapshot'
        $decision.ReadOnlyScanRequired | Should -BeTrue
        $decision.MailMoveAllowed | Should -BeFalse
    }
    It 'does not auto-complete a unique archive candidate' {
        $decision = Get-OPACrashReplayDirective -CrashWindow 'AfterResponseBeforeTerminal' -JournalTrust Trusted -MailEvidence DestinationCandidate
        $decision.Classification | Should -Be 'ReviewObservedEvidence'
        $decision.AutomaticCompletionAllowed | Should -BeFalse
        $decision.AutomaticRetryAllowed | Should -BeFalse
        $decision.RequiresManualReview | Should -BeTrue
    }
    It 'stops on ambiguous, missing, conflicting and incomplete evidence' {
        foreach ($status in @('BothPresent','Ambiguous','ScopeMismatch','IdentityConflict','IncompleteScan','MissingBoth')) {
            $decision = Get-OPACrashReplayDirective -CrashWindow 'WorkerTimeoutOrMissingResponse' -JournalTrust Trusted -MailEvidence $status
            $decision.Disposition | Should -Be 'StopAndPreserveEvidence'
            $decision.MailMoveAllowed | Should -BeFalse
            $decision.JournalWriteAllowed | Should -BeFalse
            $decision.WorkerTerminationAllowed | Should -BeFalse
        }
    }
    It 'refuses dispatch when durable Intent is absent' {
        $decision = Get-OPACrashReplayDirective -CrashWindow 'BeforeIntentFlush' -JournalTrust Trusted -MailEvidence SourceOnly
        $decision.Classification | Should -Be 'NoDurableIntent'
        $decision.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'does not automatically reconcile an existing terminal event' {
        $decision = Get-OPACrashReplayDirective -CrashWindow 'AfterResponseBeforeTerminal' -JournalTrust Trusted -MailEvidence AlreadyTerminal
        $decision.Classification | Should -Be 'TerminalNeedsAudit'
        $decision.AutomaticCompletionAllowed | Should -BeFalse
    }
    It 'contains no executable COM mutation, process kill or journal append' {
        $path = Join-Path $PSScriptRoot '../../Core/Worker/WorkerCrashProtocol.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $commands = @($ast.FindAll({
            param($node) $node -is [System.Management.Automation.Language.CommandAst]
        },$true))
        $methods = @($ast.FindAll({
            param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($commands | Where-Object { $_.GetCommandName() -in @('Stop-Process','Write-OPAOperationJournalEvent','Invoke-OPAWorkerRequest') }).Count | Should -Be 0
        @($methods | Where-Object { [string]$_.Member.Value -in @('Move','Copy','Delete','Kill','AddStore','AddStoreEx','RemoveStore') }).Count | Should -Be 0
    }
}
