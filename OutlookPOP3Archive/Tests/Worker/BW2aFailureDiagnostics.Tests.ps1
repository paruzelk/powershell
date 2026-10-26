#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerProbe265BW2.ps1')
}
Describe '2.6.5-BW2a bounded original child error diagnostics (offline)' {
    BeforeEach {
        $outcome=[pscustomobject]@{
            Status='Failed'
            FailureKind='WorkerReportedFailure'
            WorkerProcessId=2010
            ExitCode=10
            Error='BW2 read-only stage [Attach existing Outlook]: COM object unavailable'
            Response=[pscustomobject]@{Error=''}
            Operation='ProbeSyntheticPstReadOnly'
            RequiresReconciliation=$false
        }
        $proof=[pscustomobject]@{RunId=[guid]::NewGuid().ToString('D')}
    }
    It 'displays exact failing child stage and a response status' {
        $summary=Get-OPA265BW2WorkerFailureDetails -Outcome $outcome
        $summary | Should -Match 'Status=Failed'
        $summary | Should -Match 'FailureKind=WorkerReportedFailure'
        $summary | Should -Match 'Attach existing Outlook'
    }
    It 'shows actual worker process exit code and child PID' {
        $summary=Get-OPA265BW2WorkerFailureDetails -Outcome $outcome
        $summary | Should -Match 'ExitCode=10'
        $summary | Should -Match 'ChildPID=2010'
    }
    It 'preserves the COM error instead of silently dropping it' {
        $summary=Get-OPA265BW2WorkerFailureDetails -Outcome $outcome
        $summary | Should -Match 'COM object unavailable'
    }
    It 'fails closed and surfaces cause when a child reports Failed' {
        { Assert-OPA265BW2Outcome -Outcome $outcome -Proof $proof } | Should -Throw '*COM object unavailable*'
    }
    It 'retains explicit NO AUTO RETRY in thrown failure' {
        { Assert-OPA265BW2Outcome -Outcome $outcome -Proof $proof } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'surfaces timeout failure details while refusing indeterminate result' {
        $outcome.Status='Indeterminate'
        $outcome.FailureKind='Timeout'
        $outcome.ExitCode=$null
        $outcome.Error='Worker host: operation timed out after 10 seconds'
        { Assert-OPA265BW2Outcome -Outcome $outcome -Proof $proof } | Should -Throw '*timed out*'
    }
    It 'displays unknown exit code explicitly without guessing' {
        $outcome.ExitCode=$null
        (Get-OPA265BW2WorkerFailureDetails -Outcome $outcome) | Should -Match 'ExitCode=Unknown'
    }
    It 'does not trust an unrecognized failure-kind field' {
        $outcome.FailureKind='UntrustedReallyGood'
        (Get-OPA265BW2WorkerFailureDetails -Outcome $outcome) | Should -Match 'FailureKind=Unknown'
    }
    It 'falls back to response Error if outcome Error is empty' {
        $outcome.Error=''
        $outcome.Response.Error='synthetic validation refused'
        (Get-OPA265BW2WorkerFailureDetails -Outcome $outcome) | Should -Match 'synthetic validation refused'
    }
    It 'provides a safe placeholder when no child error was returned' {
        $outcome.Error=''
        $outcome.Response.Error=''
        (Get-OPA265BW2WorkerFailureDetails -Outcome $outcome) | Should -Match 'No error details from Worker'
    }
    It 'strips untrusted control characters from the printed diagnostic' {
        $outcome.Error=("line1"+[char]10+"line2"+[char]13+"message")
        $summary=Get-OPA265BW2WorkerFailureDetails -Outcome $outcome
        $summary | Should -Not -Match '[\r\n]'
        $summary | Should -Match 'line1 line2 message'
    }
    It 'bounds untrusted exception length to 400 characters' {
        $outcome.Error='a'*700
        $summary=Get-OPA265BW2WorkerFailureDetails -Outcome $outcome
        $summary.Length | Should -BeLessThan 570
        $summary | Should -Match '[.][.][.]$'
    }
    It 'labels child COM failure stages but does not add a second dispatch' {
        $child=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/SyntheticReadOnlyProbe265BW2.ps1') -Raw
        $parent=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerProbe265BW2.ps1') -Raw
        $child | Should -Match 'BW2 read-only stage'
        $child | Should -Match 'Check exact mounted stores and POP3 binding'
        ([regex]::Matches($parent,'Invoke-OPAWorkerControlledOperation -Operation')).Count | Should -Be 1
    }
    It 'passes Windows PowerShell 5.1 AST parser for both edited modules' {
        foreach($p in @('BoundedWorkerProbe265BW2.ps1','SyntheticReadOnlyProbe265BW2.ps1')) {
            $file=Join-Path $PSScriptRoot ('../../Core/Worker/'+$p)
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
