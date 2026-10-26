#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live3SyntheticScope.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/SyntheticReadOnlyProbe265BW2.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerProbe265BW2.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerCanary265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerControl.ps1')
}
Describe '2.6.5-BW2 synthetic-only Outlook Worker probe and parent validation (offline)' {
    BeforeEach {
        $id=[guid]::NewGuid().ToString('D')
        $op=[guid]::NewGuid().ToString('D')
        $pst=Join-Path $TestDrive ($id+'.pst')
        [IO.File]::WriteAllBytes($pst,[byte[]]@(1,2,3))
        $paths=Get-OPA264Live3Paths -RunId $id -SourcePst $pst
        $payload=[pscustomobject]@{
            Schema='2.6.5-BW2.SyntheticProbeRequest.1'
            RunId=$id
            SourcePst=[string]$paths.SourcePst
            OperationId=$op
            JournalSha256=('a'*64)
            State='Reconciled'
        }
        $gate=Assert-OPA265WorkerPilotGate -Mode Archive -PilotRequested $true -ExplicitConsent $true -WhatIfEnabled $true -Limit 1 -ProfileName 'Outlook' -MaxOperations 1 -TimeoutSeconds 10
        $proof=[pscustomobject]@{
            RunId=$id
            OperationId=$op
            State='Reconciled'
            JournalSha256=('a'*64)
            ExpectedArchiveEntryId='SYNTHETIC-ARCHIVE-ENTRY'
        }
        $r=[pscustomobject]@{
            Schema='2.6.5-BW2.SyntheticReadOnlyResult.1'
            RunId=$id;OperationId=$op;State='Reconciled';Decision='MoveConfirmed'
            JournalSha256=('a'*64);OutlookProfile='Outlook'
            SourceItemCount=0;ArchiveItemCount=1;SyntheticSourceMatches=0;SyntheticArchiveMatches=1
            ArchiveEntryId='SYNTHETIC-ARCHIVE-ENTRY'
            OnlySyntheticFoldersInspected=$true;OutlookMoveExecuted=$false;JournalChanged=$false
            AutomaticRetryAllowed=$false;RealMailMoveViaWorker=$false;ProductionReady=$false
        }
        $script:BW2Outcome=[pscustomobject]@{
            Status='Succeeded';Operation='ProbeSyntheticPstReadOnly';FailureKind='None'
            WorkerProcessId=1234;RequiresReconciliation=$false;RequestId=$id
            Response=[pscustomobject]@{
                Status='Succeeded';Operation='ProbeSyntheticPstReadOnly'
                WorkerProcessId=1234;RequestId=$id;ApartmentState='STA';Result=$r
            }
        }
    }
    It 'allows exactly one unresolved synthetic mail remaining in source' {
        (Assert-OPA265BW2ObservedCounts -State UnresolvedIntent -SourceCount 1 -ArchiveCount 0 -SourceMatches 1 -ArchiveMatches 0) | Should -Be 'NoMoveObserved'
    }
    It 'allows exactly one reconciled archive mail with empty source' {
        (Assert-OPA265BW2ObservedCounts -State Reconciled -SourceCount 0 -ArchiveCount 1 -SourceMatches 0 -ArchiveMatches 1) | Should -Be 'MoveConfirmed'
    }
    It 'rejects previously moved but unresolved Intent' {
        { Assert-OPA265BW2ObservedCounts -State UnresolvedIntent -SourceCount 0 -ArchiveCount 1 -SourceMatches 0 -ArchiveMatches 1 } | Should -Throw '*disagree*'
    }
    It 'rejects a reconciled journal with source still containing mail' {
        { Assert-OPA265BW2ObservedCounts -State Reconciled -SourceCount 1 -ArchiveCount 0 -SourceMatches 1 -ArchiveMatches 0 } | Should -Throw '*disagree*'
    }
    It 'rejects duplicate source and archive synthetic items' {
        { Assert-OPA265BW2ObservedCounts -State Reconciled -SourceCount 1 -ArchiveCount 1 -SourceMatches 1 -ArchiveMatches 1 } | Should -Throw '*disagree*'
    }
    It 'rejects missing synthetic item from both folders' {
        { Assert-OPA265BW2ObservedCounts -State Reconciled -SourceCount 0 -ArchiveCount 0 -SourceMatches 0 -ArchiveMatches 0 } | Should -Throw '*disagree*'
    }
    It 'rejects extra source items' {
        { Assert-OPA265BW2ObservedCounts -State UnresolvedIntent -SourceCount 2 -ArchiveCount 0 -SourceMatches 1 -ArchiveMatches 0 } | Should -Throw '*disagree*'
    }
    It 'rejects extra archive items' {
        { Assert-OPA265BW2ObservedCounts -State Reconciled -SourceCount 0 -ArchiveCount 2 -SourceMatches 0 -ArchiveMatches 1 } | Should -Throw '*disagree*'
    }
    It 'rejects an unknown state' {
        { Assert-OPA265BW2ObservedCounts -State Unknown -SourceCount 0 -ArchiveCount 1 -SourceMatches 0 -ArchiveMatches 1 } | Should -Throw '*impossible*'
    }
    It 'rejects negative source counts' {
        { Assert-OPA265BW2ObservedCounts -State Reconciled -SourceCount -1 -ArchiveCount 1 } | Should -Throw '*impossible*'
    }
    It 'rejects matches exceeding folder items' {
        { Assert-OPA265BW2ObservedCounts -State Reconciled -SourceCount 0 -ArchiveCount 1 -SourceMatches 1 -ArchiveMatches 1 } | Should -Throw '*impossible*'
    }
    It 'requires exactly the six permitted request payload fields' {
        (Assert-OPA265BW2Payload -Payload $payload) | Should -BeTrue
    }
    It 'rejects extra payload fields that could expand inspection scope' {
        $payload | Add-Member NoteProperty AnyFolderEntryId 'INBOX'
        { Assert-OPA265BW2Payload -Payload $payload } | Should -Throw '*extra*'
    }
    It 'rejects a stale payload schema' {
        $payload.Schema='2.6.5-BW1'
        { Assert-OPA265BW2Payload -Payload $payload } | Should -Throw '*invalid*'
    }
    It 'rejects noncanonical SHA256 strings' {
        $payload.JournalSha256=('A'*64)
        { Assert-OPA265BW2Payload -Payload $payload } | Should -Throw '*invalid*'
    }
    It 'rejects missing payload OperationId' {
        $payload.OperationId='not-a-guid'
        { Assert-OPA265BW2Payload -Payload $payload } | Should -Throw '*GUID*'
    }
    It 'rejects source path outside an existing local PST' {
        $payload.SourcePst='C:\missing\source.pst'
        { Assert-OPA265BW2Payload -Payload $payload } | Should -Throw
    }
    It 'rejects an unknown payload State' {
        $payload.State='Arbitrary'
        { Assert-OPA265BW2Payload -Payload $payload } | Should -Throw '*invalid*'
    }
    It 'accepts an exact enabled Archive canary for the probe' {
        (Assert-OPA265BW2CanaryGate -Gate $gate -RunId $id -SourcePst $pst) | Should -BeTrue
    }
    It 'rejects disabled legacy route as probe gate' {
        $gate.Route='FIX13b'
        { Assert-OPA265BW2CanaryGate -Gate $gate -RunId $id -SourcePst $pst } | Should -Throw '*invalid*'
    }
    It 'rejects scope expansion beyond one operation' {
        $gate.MaxOperations=2
        { Assert-OPA265BW2CanaryGate -Gate $gate -RunId $id -SourcePst $pst } | Should -Throw '*invalid*'
    }
    It 'rejects a probe when a real Move is enabled' {
        $gate.RealMailMoveViaWorker=$true
        { Assert-OPA265BW2CanaryGate -Gate $gate -RunId $id -SourcePst $pst } | Should -Throw '*invalid*'
    }
    It 'rejects probe when automatic retry allowed' {
        $gate.AutomaticRetryAllowed=$true
        { Assert-OPA265BW2CanaryGate -Gate $gate -RunId $id -SourcePst $pst } | Should -Throw '*invalid*'
    }
    It 'rejects probe with unapproved Outlook profile' {
        $gate.ProfileName='Production'
        { Assert-OPA265BW2CanaryGate -Gate $gate -RunId $id -SourcePst $pst } | Should -Throw '*invalid*'
    }
    It 'rejects invalid timeout' {
        $gate.TimeoutSeconds=31
        { Assert-OPA265BW2CanaryGate -Gate $gate -RunId $id -SourcePst $pst } | Should -Throw '*invalid*'
    }
    It 'requires explicit RunId and SourcePst' {
        { Assert-OPA265BW2CanaryGate -Gate $gate -RunId '' -SourcePst $pst } | Should -Throw
    }
    It 'validates the exact bound successful read-only Worker outcome' {
        (Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof) | Should -BeTrue
    }
    It 'rejects a Worker timeout or indeterminate result' {
        $script:BW2Outcome.Status='Indeterminate'
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*fail closed*'
    }
    It 'rejects a failed Worker result' {
        $script:BW2Outcome.Status='Failed'
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*fail closed*'
    }
    It 'rejects response from a different PID' {
        $script:BW2Outcome.Response.WorkerProcessId=5678
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*fail closed*'
    }
    It 'rejects child result with changed original journal SHA256' {
        $script:BW2Outcome.Response.Result.JournalSha256=('b'*64)
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*differs*'
    }
    It 'rejects child result with foreign synthetic RunId' {
        $script:BW2Outcome.Response.Result.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*differs*'
    }
    It 'rejects child result for a foreign OperationId' {
        $script:BW2Outcome.Response.Result.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*differs*'
    }
    It 'rejects changed archived EntryID' {
        $script:BW2Outcome.Response.Result.ArchiveEntryId='other'
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*EntryID*'
    }
    It 'rejects child probe with a Move flag' {
        $script:BW2Outcome.Response.Result.OutlookMoveExecuted=$true
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*differs*'
    }
    It 'rejects child probe without synthetic-only inspection attestation' {
        $script:BW2Outcome.Response.Result.OnlySyntheticFoldersInspected=$false
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*differs*'
    }
    It 'rejects a child result claiming production readiness' {
        $script:BW2Outcome.Response.Result.ProductionReady=$true
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*differs*'
    }
    It 'rejects child count ambiguity even if child decision claims success' {
        $script:BW2Outcome.Response.Result.SourceItemCount=1
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*disagree*'
    }
    It 'rejects an MTA worker result' {
        $script:BW2Outcome.Response.ApartmentState='MTA'
        { Assert-OPA265BW2Outcome -Outcome $script:BW2Outcome -Proof $proof } | Should -Throw '*fail closed*'
    }
    It 'preserves BW1 one-shot Ping allowlist alongside typed BW2 probe' {
        $protocol=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/WorkerProtocol.ps1') -Raw
        $protocol | Should -Match 'ProbeSyntheticPstReadOnly'
        $protocol | Should -Match "'Ping'"
    }
    It 'has no mail-mutating COM calls in the BW2 probe module' {
        $path=Join-Path $PSScriptRoot '../../Core/Worker/SyntheticReadOnlyProbe265BW2.ps1'
        $text=Get-Content -LiteralPath $path -Raw
        $text | Should -Match "GetActiveObject[(]'Outlook.Application'[)]"
        $text | Should -Not -Match 'New-Object -ComObject|AddStoreEx|RemoveStore|MailItem[.]Move|Move-OPAItemsWithLimit'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $mutators=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
            [string]$node.Member.Value -in @('Move','Save','Delete','AddStoreEx','AddStore','RemoveStore','Quit','Kill')
        },$true))
        @($mutators).Count | Should -Be 0
    }
    It 'parses parent bounded probe module and child Worker under Windows PowerShell 5.1' {
        foreach($path in @((Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerProbe265BW2.ps1'),(Join-Path $PSScriptRoot '../../OutlookPOP3Archive.Worker.ps1'))) {
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
    It 'wires BW2 route into main CLI before COM session creation and legacy Move' {
        $main=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $main | Should -Match 'WorkerPilotProbeSynthetic'
        $main | Should -Match 'Invoke-OPA265BW2BoundedReadOnlyCanary'
        ($main.IndexOf('Invoke-OPA265BW2BoundedReadOnlyCanary') -lt $main.IndexOf('$session = New-OPAComSession')) | Should -BeTrue
        ($main.IndexOf('Invoke-OPA265BW2BoundedReadOnlyCanary') -lt $main.IndexOf('Move-OPAItemsWithLimit')) | Should -BeTrue
    }
    It 'only exposes BW2 operation to the isolated Worker explicit switch' {
        $worker=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.Worker.ps1') -Raw
        $worker | Should -Match "'ProbeSyntheticPstReadOnly' [{]"
        $worker | Should -Match 'Invoke-OPA265BW2ReadOnlySyntheticProbe -Payload'
    }
}
