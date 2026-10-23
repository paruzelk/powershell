#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerTestFixture.ps1')
}
Describe '2.6.4-B2 disposable fixture and parent controller contract (no Outlook COM)' {
    BeforeEach {
        $plan = New-OPA264FixturePlan
    }
    It 'creates independent run GUIDs for different fixtures' {
        $next=New-OPA264FixturePlan
        $plan.RunId | Should -Not -Be $next.RunId
    }
    It 'creates a distinct operation GUID' {
        $plan.OperationId | Should -Not -Be $plan.RunId
    }
    It 'uses the fixed run-unique OS TEMP naming convention' {
        $plan.Paths.Directory | Should -Match 'OPA264-Test-[a-f0-9]{32}$'
    }
    It 'names only the two fixed disposable PST paths' {
        [IO.Path]::GetFileName($plan.Paths.SourcePst) | Should -Be 'Source.pst'
        [IO.Path]::GetFileName($plan.Paths.ArchivePst) | Should -Be 'Archive.pst'
    }
    It 'requires explicit permission and denies production data' {
        $plan.RequiresExplicitApproval | Should -BeTrue
        $plan.AllowsProductionPst | Should -BeFalse
        $plan.AllowsExistingPst | Should -BeFalse
    }
    It 'denies any automatic Worker dispatch, repeat or completion' {
        $plan.AllowsWorkerAutoDispatch | Should -BeFalse
        $plan.AllowsWorkerAutoRetry | Should -BeFalse
        (Get-OPA264FixtureContract).AutomaticJournalCompletionAllowed | Should -BeFalse
    }
    It 'accepts a not-yet-created disposable fixture' {
        (Assert-OPA264FreshFixture -Plan $plan).RunId | Should -Be $plan.RunId
    }
    It 'refuses reusing an existing unique run directory' {
        [void][IO.Directory]::CreateDirectory($plan.Paths.Directory)
        try { { Assert-OPA264FreshFixture -Plan $plan } | Should -Throw '*already exists*' }
        finally { Remove-Item -LiteralPath $plan.Paths.Directory -Recurse -Force }
    }
    It 'refuses tampered source file path' {
        $plan.Paths.SourcePst = 'C:\Mail\MyProduction.pst'
        { Assert-OPA264FreshFixture -Plan $plan } | Should -Throw '*derived*'
    }
    It 'refuses mismatched plan and path RunId' {
        $plan.RunId = [guid]::NewGuid().ToString('D')
        { Assert-OPA264FreshFixture -Plan $plan } | Should -Throw '*mismatch*'
    }
    It 'rejects an invalid supplied GUID' {
        { New-OPA264FixturePlan -RunId 'not-a-guid' } | Should -Throw '*GUID*'
    }
    It 'does not perform COM Move, Copy, Delete or process Kill in fixture creator' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/New-OPA264DisposableFixture.ps1'
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({
            param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object { [string]$_.Member.Value -in @('Move','Copy','Delete','Kill') }).Count | Should -Be 0
    }
    It 'does not mount PSTs or call Outlook in parent controller' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264TestController.ps1'
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({
            param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
        },$true))
        @($methods | Where-Object { [string]$_.Member.Value -in @('Move','AddStore','AddStoreEx','Copy') }).Count | Should -Be 0
    }
    It 'keeps regular Worker allowlist free from MailMove' {
        $path=Join-Path $PSScriptRoot '../../Core/Worker/WorkerProtocol.ps1'
        $raw=Get-Content -LiteralPath $path -Raw
        $raw | Should -Not -Match "'MailMove'"
        $release=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../RELEASE.json') -Raw | ConvertFrom-Json
        $release.Integration.ArchiveWorkerEnabled | Should -BeFalse
        $release.Integration.ResumeWorkerEnabled | Should -BeFalse
        $release.Integration.AutoWorkerEnabled | Should -BeFalse
    }
}
