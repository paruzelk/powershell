#requires -Version 5.1
BeforeAll {
    $script:BW3aControllerPath=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW3SyntheticController.ps1'
}
Describe 'BW3a: no assignment to read-only automatic PID after durable dispatch' {
    BeforeEach {
        $script:BW3aController=Get-Content -LiteralPath $script:BW3aControllerPath -Raw
    }
    It 'demonstrates that native automatic PID is read-only' {
        { $PID=0 } | Should -Throw
    }
    It 'permits assigning a separate ordinary workerProcessId variable' {
        $workerProcessId=0
        $workerProcessId=123456
        $workerProcessId | Should -Be 123456
    }
    It 'finds zero AST assignments to read-only PID (case-insensitive)' {
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($script:BW3aControllerPath,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $bad=@($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
            [string]::Equals([string]$node.Left.VariablePath.UserPath,'PID',[StringComparison]::OrdinalIgnoreCase)
        },$true))
        $bad.Count | Should -Be 0
    }
    It 'rejects raw legacy lowercase PID assignments in controller source' {
        $script:BW3aController | Should -Not -Match '(?i)[$]pid\s*='
    }
    It 'initializes the separate Worker PID local to zero' {
        $script:BW3aController | Should -Match '[$]workerProcessId=0'
    }
    It 'reads actual Worker ProcessId from outcome into separate local' {
        $script:BW3aController | Should -Match '[$]workerProcessId=\[int\][$]outcome[.]WorkerProcessId'
    }
    It 'uses workerProcessId rather than automatic PID in durable controller report' {
        $script:BW3aController | Should -Match 'WorkerProcessId=[$]workerProcessId'
    }
    It 'creates durable dispatch claim BEFORE initializing Worker variables' {
        $claim=$script:BW3aController.IndexOf('Write-OPA265BW3DurableDispatchClaim -Preflight')
        $init=$script:BW3aController.IndexOf('$workerProcessId=0')
        $claim | Should -BeGreaterThan 0
        ($claim -lt $init) | Should -BeTrue
    }
    It 'initializes Worker variables BEFORE the only call dispatching child' {
        $init=$script:BW3aController.IndexOf('$workerProcessId=0')
        $dispatch=$script:BW3aController.IndexOf('Invoke-OPAWorkerControlledOperation -Operation')
        ($init -lt $dispatch) | Should -BeTrue
    }
    It 'launches at most one child Worker operation and does not retry' {
        ([regex]::Matches($script:BW3aController,'Invoke-OPAWorkerControlledOperation -Operation')).Count | Should -Be 1
        $script:BW3aController | Should -Match 'NO AUTO RETRY|NEVER retry'
    }
    It 'does not remove a claim after an exception' {
        $script:BW3aController | Should -Not -Match 'Remove-Item|[.]Delete[(]|[IO.FileMode]::Truncate'
    }
    It 'never calls MailItem.Move or mounts PSTs from the controller' {
        $script:BW3aController | Should -Not -Match '[$]mail[.]Move|AddStoreEx|RemoveStore|New-Object -ComObject'
    }
    It 'retains result classification requiring independent read-only review' {
        $script:BW3aController | Should -Match 'RequiresIndependentReconciliation=[$]true'
        $script:BW3aController | Should -Match 'StopAndPerformIndependentReadOnlyReview'
    }
    It 'preserves separate source Journal SHA and RequestId binding' {
        $script:BW3aController | Should -Match 'ExpectedJournalSha256'
        $script:BW3aController | Should -Match 'RequestId [$]workerRequestId'
    }
    It 'has zero PowerShell AST parse errors for controller and BW3 Worker' {
        foreach($name in @('Core/Diagnostics/Invoke-OPA265BW3SyntheticController.ps1',
            'Core/Worker/BW3SyntheticMoveWorker265.ps1',
            'Core/Worker/BW3OneShotProtocol265.ps1')) {
            $file=Join-Path (Join-Path $PSScriptRoot '../..') $name
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
