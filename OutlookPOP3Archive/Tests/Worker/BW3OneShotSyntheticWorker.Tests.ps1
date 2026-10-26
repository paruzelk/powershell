#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live3SyntheticScope.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerProtocol.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3OneShotProtocol265.ps1')
}
Describe 'BW3 single new synthetic Move: durable dispatch and fail-closed offline contract' {
    BeforeEach {
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        $id=[guid]::NewGuid().ToString('D')
        $op=[guid]::NewGuid().ToString('D')
        $req=[guid]::NewGuid().ToString('D')
        $sha='a'*64
        $script:BW3Pre=[pscustomobject]@{
            RunId=$id
            OperationId=$op
            JournalSha256=$sha
            SourcePst='C:\Synthetic\Source.pst'
            IntentSizeBytes=1436
            Extra=[pscustomobject]@{
                DispatchClaimPath=(Join-Path $dir 'bw3-dispatch.claim')
                ControllerResultPath=(Join-Path $dir 'bw3-controller-result.json')
            }
        }
        $script:BW3RequestId=$req
        $script:BW3Payload=[pscustomobject]@{
            Schema='2.6.5-BW3.SyntheticOneShot.1'
            ExecutionPurpose='OperatorApprovedSingleSyntheticMove'
            RunId=$id
            SourcePst=$script:BW3Pre.SourcePst
            OperationId=$op
            JournalSha256=$sha
            WorkerRequestId=$req
        }
        $script:BW3Result=[pscustomobject]@{
            Schema='2.6.5-BW3.MoveReturned.1'
            RunId=$id
            OperationId=$op
            JournalSha256=$sha
            DestinationEntryId='SYNTHETIC-DESTINATION'
            MoveReturned=$true
            MovesAttempted=1
            JournalCompleted=$false
            AutomaticRetryAllowed=$false
            RequiresIndependentReconciliation=$true
            ProductionReady=$false
        }
        $script:BW3Outcome=[pscustomobject]@{
            Status='Succeeded'
            FailureKind='None'
            Operation='BW3SyntheticOneShotMove'
            RequestId=$req
            WorkerProcessId=12345
            RequiresReconciliation=$false
            Response=[pscustomobject]@{
                Status='Succeeded'
                Operation='BW3SyntheticOneShotMove'
                RequestId=$req
                WorkerProcessId=12345
                ApartmentState='STA'
                Result=$script:BW3Result
            }
        }
    }
    It 'accepts exactly typed seven-field synthetic payload' {
        (Assert-OPA265BW3Payload -Payload $script:BW3Payload) | Should -BeTrue
    }
    It 'rejects arbitrary eighth payload field used to expand scope' {
        $script:BW3Payload | Add-Member NoteProperty SourceFolder 'Inbox'
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*invalid*'
    }
    It 'rejects extra code fields in Worker payload' {
        $script:BW3Payload | Add-Member NoteProperty Script 'Remove-Item C:\'
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*invalid*'
    }
    It 'rejects missing worker request correlation GUID' {
        $script:BW3Payload.WorkerRequestId=''
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*GUID*'
    }
    It 'rejects missing durable operation GUID' {
        $script:BW3Payload.OperationId=''
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*GUID*'
    }
    It 'rejects an empty RunId' {
        $script:BW3Payload.RunId=''
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*GUID*'
    }
    It 'rejects noncanonical GUID spelling' {
        $script:BW3Payload.RunId=$script:BW3Pre.RunId.ToUpperInvariant()
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*GUID*'
    }
    It 'rejects a read-only probe pretending to be a Move' {
        $script:BW3Payload.ExecutionPurpose='ProbeSyntheticPstReadOnly'
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*invalid*'
    }
    It 'rejects incorrectly typed schema' {
        $script:BW3Payload.Schema='2.6.5-BW2.SyntheticProbeRequest.1'
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*invalid*'
    }
    It 'rejects uppercase or partial SHA256' {
        $script:BW3Payload.JournalSha256='A'*64
        { Assert-OPA265BW3Payload -Payload $script:BW3Payload } | Should -Throw '*invalid*'
    }
    It 'writes exact parent dispatch claim durably before Worker creation' {
        $c=Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId
        [IO.File]::Exists($script:BW3Pre.Extra.DispatchClaimPath) | Should -BeTrue
        $c.WorkerRequestId | Should -Be $script:BW3RequestId
        $c.JournalCompleted | Should -BeFalse
        $c.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'never permits a second claim for the same operation' {
        [void](Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId)
        { Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw
    }
    It 'rejects an existing empty claim without overwriting it' {
        [IO.File]::WriteAllText($script:BW3Pre.Extra.DispatchClaimPath,'')
        { Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw
    }
    It 'writes exact request and operation identity to durable claim' {
        [void](Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId)
        $c=Read-OPAWorkerJson -Path $script:BW3Pre.Extra.DispatchClaimPath
        $c.OperationId | Should -Be $script:BW3Pre.OperationId
        $c.WorkerRequestId | Should -Be $script:BW3RequestId
    }
    It 'rejects a mismatched requested PID-free dispatch GUID' {
        $c=Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId
        { Assert-OPA265BW3DispatchClaim -Claim $c -Preflight $script:BW3Pre -RequestId ([guid]::NewGuid().ToString('D')) } | Should -Throw '*correlation*'
    }
    It 'rejects dispatch claim for another RunId' {
        $c=Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId
        $c.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3DispatchClaim -Claim $c -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*correlation*'
    }
    It 'rejects dispatch claim for another OperationId' {
        $c=Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId
        $c.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3DispatchClaim -Claim $c -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*correlation*'
    }
    It 'rejects dispatch claim on a changed journal SHA256' {
        $c=Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId
        $c.JournalSha256='b'*64
        { Assert-OPA265BW3DispatchClaim -Claim $c -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*correlation*'
    }
    It 'rejects dispatch claim enabling production' {
        $c=Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId
        $c.ProductionReady=$true
        { Assert-OPA265BW3DispatchClaim -Claim $c -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*correlation*'
    }
    It 'rejects claim that permits automatic retry' {
        $c=Write-OPA265BW3DurableDispatchClaim -Preflight $script:BW3Pre -RequestId $script:BW3RequestId
        $c.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3DispatchClaim -Claim $c -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*correlation*'
    }
    It 'independently validates an exact one-shot child response' {
        (Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId) | Should -BeTrue
    }
    It 'rejects missing response on timeout' {
        $script:BW3Outcome.Status='Indeterminate'
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects a Worker failure and does not retry' {
        $script:BW3Outcome.Status='Failed'
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects changed child response PID' {
        $script:BW3Outcome.Response.WorkerProcessId=54321
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects an MTA child process' {
        $script:BW3Outcome.Response.ApartmentState='MTA'
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects forged success with two attempted Moves' {
        $script:BW3Result.MovesAttempted=2
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects success when destination EntryID absent' {
        $script:BW3Result.DestinationEntryId=''
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects forged terminal journal completion' {
        $script:BW3Result.JournalCompleted=$true
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'requires independent reconciliation even when COM returned' {
        $script:BW3Result.RequiresIndependentReconciliation=$false
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects foreign child operation correlation' {
        $script:BW3Outcome.Response.Result.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects changed durable journal evidence in response' {
        $script:BW3Result.JournalSha256='b'*64
        { Assert-OPA265BW3Outcome -Outcome $script:BW3Outcome -Preflight $script:BW3Pre -RequestId $script:BW3RequestId } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'has exactly one COM Move call in isolated synthetic Worker' {
        $path=Join-Path $PSScriptRoot '../../Core/Worker/BW3SyntheticMoveWorker265.ps1'
        $text=Get-Content -LiteralPath $path -Raw
        ([regex]::Matches($text,'[$]mail[.]Move[(]')).Count | Should -Be 1
        $text | Should -Not -Match 'AddStoreEx|RemoveStore|New-Object -ComObject|Quit[(]'
    }
    It 'writes durable attempt claim before one Move according to source order' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BW3SyntheticMoveWorker265.ps1') -Raw
        ($text.IndexOf('[IO.FileMode]::CreateNew') -lt $text.IndexOf('$mail.Move($to)')) | Should -BeTrue
        ($text.IndexOf('$fs.Flush($true)') -lt $text.IndexOf('$mail.Move($to)')) | Should -BeTrue
    }
    It 'durably claims dispatch before the only host Worker invocation' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW3SyntheticController.ps1') -Raw
        ($text.IndexOf('Write-OPA265BW3DurableDispatchClaim -Preflight') -lt $text.IndexOf('Invoke-OPAWorkerControlledOperation -Operation')) | Should -BeTrue
        ([regex]::Matches($text,'Invoke-OPAWorkerControlledOperation -Operation')).Count | Should -Be 1
    }
    It 'never appends Reconciled automatically from the BW3 controller' {
        $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW3SyntheticController.ps1') -Raw
        $text | Should -Not -Match 'Write-OPA264Live6ReconciledLocked|Write-OPAOperationJournalEvent'
        $text | Should -Match 'RequiresIndependentReconciliation'
    }
    It 'ensures both legacy LIVE3 and LIVE4 refuse BW3 dispatch evidence' {
        foreach($file in @('Invoke-OPA264Live3SyntheticWorker.ps1','Invoke-OPA264Live4CrashController.ps1')) {
            $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot ('../../Core/Diagnostics/'+$file)) -Raw
            $text | Should -Match 'bw3-dispatch.claim'
        }
    }
    It 'keeps production Archive/Resume main entry independent of BW3 Move' {
        $main=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $main | Should -Not -Match 'BW3SyntheticOneShotMove|Invoke-OPA265BW3SyntheticController'
    }
    It 'parses BW3 Worker, controller, protocol and app under Windows PowerShell AST' {
        foreach($file in @('Core/Worker/BW3OneShotProtocol265.ps1','Core/Worker/BW3SyntheticMoveWorker265.ps1','Core/Diagnostics/Invoke-OPA265BW3SyntheticController.ps1','OutlookPOP3Archive.Worker.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $file
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
