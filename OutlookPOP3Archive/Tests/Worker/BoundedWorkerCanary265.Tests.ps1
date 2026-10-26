#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerCanary265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerControl.ps1')
}
Describe '2.6.5 DEV bounded read-only Worker integration policy (offline)' {
    BeforeEach {
        $id=[guid]::NewGuid().ToString('D')
        $good=@{Mode='Archive';PilotRequested=$true;ExplicitConsent=$true;WhatIfEnabled=$true;Limit=1;ProfileName='Outlook';MaxOperations=1;TimeoutSeconds=10}
        $script:OPA265TestWorkerOutcome=[pscustomobject]@{
            Status='Succeeded';Operation='Ping';FailureKind='None';WorkerProcessId=1234
            RequiresReconciliation=$false;RequestId=$id;ArtifactDirectory=''
            Response=[pscustomobject]@{
                Status='Succeeded';Operation='Ping';RequestId=$id
                WorkerProcessId=1234;ApartmentState='STA'
                Result=[pscustomobject]@{Alive=$true}
            }
        }
    }
    It 'defaults to the unchanged FIX13b route when pilot is off' {
        $r=Assert-OPA265WorkerPilotGate -Mode Archive
        $r.Route | Should -Be 'FIX13b'
        $r.WorkerOperation | Should -Be 'None'
        $r.RealMailMoveViaWorker | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'rejects consent alone to prevent silent legacy fallback' {
        { Assert-OPA265WorkerPilotGate -Mode Archive -ExplicitConsent $true } | Should -Throw '*without -WorkerPilot*'
    }
    It 'rejects pilot options without the pilot switch' {
        { Assert-OPA265WorkerPilotGate -Mode Resume -OtherPilotOptionsSpecified $true } | Should -Throw '*without -WorkerPilot*'
    }
    It 'accepts the exact one-operation Archive WhatIf canary' {
        $r=Assert-OPA265WorkerPilotGate @good
        $r.Route | Should -Be 'ReadOnlyCanary'
        $r.WorkerOperation | Should -Be 'Ping'
        $r.MaxOperations | Should -Be 1
        $r.AutomaticRetryAllowed | Should -BeFalse
        $r.RealMailMoveViaWorker | Should -BeFalse
    }
    It 'rejects Auto even when otherwise opted in' {
        $good.Mode='Auto'
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*Auto is blocked*'
    }
    It 'rejects Analyze even when opted in' {
        $good.Mode='Analyze'
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*only*'
    }
    It 'rejects Plan even when opted in' {
        $good.Mode='Plan'
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*only*'
    }
    It 'rejects missing consent' {
        $good.ExplicitConsent=$false
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*BOTH*'
    }
    It 'rejects missing WhatIf even with consent' {
        $good.WhatIfEnabled=$false
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*BOTH*'
    }
    It 'rejects unbounded 0 Limit' {
        $good.Limit=0
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*precisely one*'
    }
    It 'rejects Limit greater than one' {
        $good.Limit=2
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*precisely one*'
    }
    It 'rejects max worker operations greater than one' {
        $good.MaxOperations=2
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*precisely one*'
    }
    It 'rejects zero max worker operations' {
        $good.MaxOperations=0
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*precisely one*'
    }
    It 'rejects zero Worker timeout' {
        $good.TimeoutSeconds=0
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*1..30*'
    }
    It 'rejects 31-second Worker timeout' {
        $good.TimeoutSeconds=31
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*1..30*'
    }
    It 'accepts a 1-second bounded timeout' {
        $good.TimeoutSeconds=1
        (Assert-OPA265WorkerPilotGate @good).TimeoutSeconds | Should -Be 1
    }
    It 'accepts a 30-second bounded timeout' {
        $good.TimeoutSeconds=30
        (Assert-OPA265WorkerPilotGate @good).TimeoutSeconds | Should -Be 30
    }
    It 'rejects implicit Outlook profile names' {
        $good.ProfileName=''
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*TEST profile*'
    }
    It 'rejects other Outlook profiles' {
        $good.ProfileName='Production'
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*TEST profile*'
    }
    It 'rejects a transaction on Archive canary' {
        $good.Transaction=[guid]::NewGuid().ToString('D')
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*cannot take -Transaction*'
    }
    It 'rejects Resume without a transaction id' {
        $good.Mode='Resume'
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*nonzero GUID*'
    }
    It 'rejects Resume with invalid transaction id' {
        $good.Mode='Resume';$good.Transaction='LATEST'
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*nonzero GUID*'
    }
    It 'rejects Resume using the empty GUID' {
        $good.Mode='Resume';$good.Transaction=[guid]::Empty.ToString('D')
        { Assert-OPA265WorkerPilotGate @good } | Should -Throw '*nonzero GUID*'
    }
    It 'accepts an explicitly scoped Resume read-only canary without executing Resume' {
        $good.Mode='Resume';$good.Transaction=[guid]::NewGuid().ToString('D')
        $r=Assert-OPA265WorkerPilotGate @good
        $r.Route | Should -Be 'ReadOnlyCanary'
        $r.Transaction | Should -Be $good.Transaction
    }
    It 'accepts only an independently verified Ping outcome' {
        (Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome) | Should -BeTrue
    }
    It 'rejects indeterminate outcome after child start' {
        $script:OPA265TestWorkerOutcome.Status='Indeterminate'
        $script:OPA265TestWorkerOutcome.RequiresReconciliation=$true
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'rejects failed Worker response without fallback' {
        $script:OPA265TestWorkerOutcome.Status='Failed'
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'rejects a different Worker operation' {
        $script:OPA265TestWorkerOutcome.Operation='ProbeOutlook'
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'rejects missing validated PID' {
        $script:OPA265TestWorkerOutcome.WorkerProcessId=0
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'rejects worker PID mismatch in response' {
        $script:OPA265TestWorkerOutcome.Response.WorkerProcessId=5678
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'rejects mismatched request GUID' {
        $script:OPA265TestWorkerOutcome.Response.RequestId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'rejects bogus request GUID' {
        $script:OPA265TestWorkerOutcome.RequestId='not-a-guid'
        $script:OPA265TestWorkerOutcome.Response.RequestId='not-a-guid'
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*GUID*'
    }
    It 'rejects an MTA Worker response' {
        $script:OPA265TestWorkerOutcome.Response.ApartmentState='MTA'
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'rejects missing Alive proof' {
        $script:OPA265TestWorkerOutcome.Response.Result.Alive=$false
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'rejects worker outcome flagged with reconciliation required' {
        $script:OPA265TestWorkerOutcome.RequiresReconciliation=$true
        { Assert-OPA265WorkerPilotOutcome -Outcome $script:OPA265TestWorkerOutcome } | Should -Throw '*fail closed*'
    }
    It 'refuses to dispatch when unsafe gate Route is supplied' {
        $gate=Assert-OPA265WorkerPilotGate @good
        $gate.Route='FIX13b'
        Mock Invoke-OPAWorkerControlledOperation { throw 'Must not be called' }
        { Invoke-OPA265BoundedWorkerCanary -Gate $gate } | Should -Throw '*unsafe*'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Times 0 -Exactly
    }
    It 'refuses to dispatch when gate permits real MailMove' {
        $gate=Assert-OPA265WorkerPilotGate @good
        $gate.RealMailMoveViaWorker=$true
        Mock Invoke-OPAWorkerControlledOperation { throw 'Must not be called' }
        { Invoke-OPA265BoundedWorkerCanary -Gate $gate } | Should -Throw '*unsafe*'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Times 0 -Exactly
    }
    It 'dispatches exactly one Ping with bounded timeout and returns non-mutating result' {
        $gate=Assert-OPA265WorkerPilotGate @good
        Mock Invoke-OPAWorkerControlledOperation { return $script:OPA265TestWorkerOutcome }
        $r=Invoke-OPA265BoundedWorkerCanary -Gate $gate
        $r.Status | Should -Be 'ReadOnlyCanaryPassed'
        $r.WorkerOperation | Should -Be 'Ping'
        $r.OperationsExecuted | Should -Be 1
        $r.OutlookMoveExecuted | Should -BeFalse
        $r.JournalChanged | Should -BeFalse
        $r.ArchiveTransactionCreated | Should -BeFalse
        $r.RealMailMoveViaWorker | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $r.NextAction | Should -Be 'StopBeforeArchiveOrResume'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Times 1 -Exactly -ParameterFilter { $Operation -eq 'Ping' -and $TimeoutSeconds -eq 10 }
    }
    It 'rejects an invalid outcome with only one dispatch and no second try' {
        $gate=Assert-OPA265WorkerPilotGate @good
        $script:OPA265TestWorkerOutcome.Status='Indeterminate'
        Mock Invoke-OPAWorkerControlledOperation { return $script:OPA265TestWorkerOutcome }
        { Invoke-OPA265BoundedWorkerCanary -Gate $gate } | Should -Throw '*fail closed*'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Times 1 -Exactly
    }
    It 'never invokes a Worker when supplied gate permits two operations' {
        $gate=Assert-OPA265WorkerPilotGate @good
        $gate.MaxOperations=2
        Mock Invoke-OPAWorkerControlledOperation { throw 'should not run' }
        { Invoke-OPA265BoundedWorkerCanary -Gate $gate } | Should -Throw '*unsafe*'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Times 0 -Exactly
    }
    It 'has no Outlook COM or PST write API in canary module' {
        $module=Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerCanary265.ps1'
        $text=Get-Content -LiteralPath $module -Raw
        $text | Should -Not -Match 'New-Object -ComObject|GetActiveObject|MailItem[.]Move|Move-OPAItemsWithLimit'
        $text | Should -Match "Invoke-OPAWorkerControlledOperation -Operation 'Ping'"
    }
    It 'wires opt-in canary gate before first COM session and MailMover in main CLI' {
        $main=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        ($main.IndexOf('Assert-OPA265WorkerPilotGate') -gt 0) | Should -BeTrue
        ($main.IndexOf('Assert-OPA265WorkerPilotGate') -lt $main.IndexOf('$session = New-OPAComSession')) | Should -BeTrue
        ($main.IndexOf('Assert-OPA265WorkerPilotGate') -lt $main.IndexOf('Move-OPAItemsWithLimit')) | Should -BeTrue
        $main | Should -Match 'if [(][$]WorkerPilot[)]'
        $main | Should -Match 'Write-Output [$]pilotResult'
    }
    It 'parses the main CLI and canary module under PS 5.1 AST' {
        foreach($path in @((Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1'),(Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerCanary265.ps1'))) {
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
