#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/Live3SyntheticScope.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/SyntheticReadOnlyProbe265BW2.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerProbe265BW2.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BoundedWorkerCanary265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/WorkerControl.ps1')
}
Describe 'BW2c explicit one-fixture source size consent (pure and offline)' {
    BeforeEach {
        $script:BW2cRun='77854a93-ecfd-42c7-b58e-2948fe9afa88'
        $script:BW2cOp='e249f73b-8cdf-4672-92e3-5c49f8feaca0'
        $script:BW2cSha='22d2047972825f3207ef3b099f57ebe46d6088a5f4c7fd0525ab45dd19d098fc'
        $source=Join-Path $TestDrive 'synthetic-source.pst'
        [IO.File]::WriteAllBytes($source,[byte[]]@(1,2,3))
        $paths=Get-OPA264Live3Paths -RunId $script:BW2cRun -SourcePst $source
        $script:BW2cProof=[pscustomobject]@{
            RunId=$script:BW2cRun;OperationId=$script:BW2cOp
            JournalSha256=$script:BW2cSha;State='UnresolvedIntent'
            SourcePst=[string]$paths.SourcePst
            ExpectedSizeBytes=[long]1436
            Paths=[pscustomobject]@{JournalPath='X:\NeverWrite\bw2c.jsonl'}
        }
        $script:BW2cPayload=[pscustomobject]@{
            Schema='2.6.5-BW2.SyntheticProbeRequest.1'
            RunId=$script:BW2cRun
            SourcePst=[string]$paths.SourcePst
            OperationId=$script:BW2cOp
            JournalSha256=$script:BW2cSha
            State='UnresolvedIntent'
        }
        $script:BW2cEvidence=Get-OPA265BW2SourceFingerprintEvidence -ExpectedEntryId 'SAFE-SYNTHETIC-ID' -ObservedEntryId 'SAFE-SYNTHETIC-ID' -IntentSizeBytes 1436 -ObservedSourceSizeBytes 1808
        $script:BW2cConsent=[pscustomobject]@{ConfirmSourceSizeDifference=$true;ExpectedSourceSizeBytes=[long]1808}
        $script:BW2cGate=Assert-OPA265WorkerPilotGate -Mode Archive -PilotRequested $true -ExplicitConsent $true -WhatIfEnabled $true -Limit 1 -ProfileName Outlook -MaxOperations 1 -TimeoutSeconds 10
        $responseResult=[pscustomobject]@{
            Schema='2.6.5-BW2.SyntheticReadOnlyResult.1'
            RunId=$script:BW2cRun
            OperationId=$script:BW2cOp
            State='UnresolvedIntent'
            JournalSha256=$script:BW2cSha
            OutlookProfile='Outlook'
            OnlySyntheticFoldersInspected=$true
            OutlookMoveExecuted=$false
            JournalChanged=$false
            AutomaticRetryAllowed=$false
            RealMailMoveViaWorker=$false
            ProductionReady=$false
            Decision='NoMoveObserved'
            SourceItemCount=1
            ArchiveItemCount=0
            SyntheticSourceMatches=1
            SyntheticArchiveMatches=0
            ArchiveEntryId=''
            SourceSizeDifferenceExplicitlyApproved=$true
            SourceEntryIdMatchesIntent=$true
            SourceSizeMatchesIntent=$false
            IntentSizeBytes=[long]1436
            ObservedSourceSizeBytes=[long]1808
            SizeDifferenceBytes=[long]372
        }
        $script:BW2cOutcome=[pscustomobject]@{
            Status='Succeeded';FailureKind='None'
            Operation='ProbeSyntheticPstReadOnly';WorkerProcessId=7304
            RequestId=$script:BW2cOp;RequiresReconciliation=$false
            Response=[pscustomobject]@{
                Status='Succeeded';Operation='ProbeSyntheticPstReadOnly'
                WorkerProcessId=7304;RequestId=$script:BW2cOp
                ApartmentState='STA';Result=$responseResult
            }
        }
    }
    It 'accepts unconsented original six-field protocol' {
        (Assert-OPA265BW2Payload -Payload $script:BW2cPayload) | Should -BeTrue
    }
    It 'accepts exactly two explicit consent fields' {
        $script:BW2cPayload | Add-Member NoteProperty ConfirmSourceSizeDifference $true
        $script:BW2cPayload | Add-Member NoteProperty ExpectedSourceSizeBytes ([long]1808)
        (Assert-OPA265BW2Payload -Payload $script:BW2cPayload) | Should -BeTrue
    }
    It 'rejects consent flag without expected bytes' {
        $script:BW2cPayload | Add-Member NoteProperty ConfirmSourceSizeDifference $true
        { Assert-OPA265BW2Payload -Payload $script:BW2cPayload } | Should -Throw '*consent*'
    }
    It 'rejects expected bytes without consent flag' {
        $script:BW2cPayload | Add-Member NoteProperty ExpectedSourceSizeBytes ([long]1808)
        { Assert-OPA265BW2Payload -Payload $script:BW2cPayload } | Should -Throw '*consent*'
    }
    It 'rejects false approval flag' {
        $script:BW2cPayload | Add-Member NoteProperty ConfirmSourceSizeDifference $false
        $script:BW2cPayload | Add-Member NoteProperty ExpectedSourceSizeBytes ([long]1808)
        { Assert-OPA265BW2Payload -Payload $script:BW2cPayload } | Should -Throw '*consent*'
    }
    It 'rejects unapproved 1444 destination size as source consent' {
        $script:BW2cPayload | Add-Member NoteProperty ConfirmSourceSizeDifference $true
        $script:BW2cPayload | Add-Member NoteProperty ExpectedSourceSizeBytes ([long]1444)
        { Assert-OPA265BW2Payload -Payload $script:BW2cPayload } | Should -Throw '*consent*'
    }
    It 'rejects consent on Reconciled journal' {
        $script:BW2cPayload.State='Reconciled'
        $script:BW2cPayload | Add-Member NoteProperty ConfirmSourceSizeDifference $true
        $script:BW2cPayload | Add-Member NoteProperty ExpectedSourceSizeBytes ([long]1808)
        { Assert-OPA265BW2Payload -Payload $script:BW2cPayload } | Should -Throw '*consent*'
    }
    It 'rejects extra fields widening protocol scope' {
        $script:BW2cPayload | Add-Member NoteProperty ConfirmSourceSizeDifference $true
        $script:BW2cPayload | Add-Member NoteProperty ExpectedSourceSizeBytes ([long]1808)
        $script:BW2cPayload | Add-Member NoteProperty OtherFolder 'Inbox'
        { Assert-OPA265BW2Payload -Payload $script:BW2cPayload } | Should -Throw '*consent*'
    }
    It 'accepts only exact previously proven single source-size difference' {
        (Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent) | Should -BeTrue
    }
    It 'still refuses source-size mismatch without explicit consent' {
        { Assert-OPA265BW2SourceFingerprint -Evidence $script:BW2cEvidence } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects any other RunId' {
        $script:BW2cProof.RunId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects changed OperationId' {
        $script:BW2cProof.OperationId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects changed original journal SHA256' {
        $script:BW2cProof.JournalSha256=('a'*64)
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects changed durable Intent size' {
        $script:BW2cProof.ExpectedSizeBytes=1437
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects observed bytes other than 1808' {
        $script:BW2cEvidence.ObservedSourceSizeBytes=1809
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects changed source EntryID even with expected size' {
        $script:BW2cEvidence.SourceEntryIdMatchesIntent=$false
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects unsolicited consent when source size matches' {
        $script:BW2cEvidence.SourceSizeMatchesIntent=$true
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects a fake 0-byte size difference' {
        $script:BW2cEvidence.SizeDifferenceBytes=0
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects consent switch false at child verification' {
        $script:BW2cConsent.ConfirmSourceSizeDifference=$false
        { Assert-OPA265BW2SourceSizeConsent -Evidence $script:BW2cEvidence -Proof $script:BW2cProof -Consent $script:BW2cConsent } | Should -Throw '*NO AUTO RETRY*'
    }
    It 'rejects a child claim of approval without parent consent' {
        { Assert-OPA265BW2Outcome -Outcome $script:BW2cOutcome -Proof $script:BW2cProof } | Should -Throw '*unrequested*'
    }
    It 'rejects different bytes in a success-looking Worker response' {
        $script:BW2cOutcome.Response.Result.ObservedSourceSizeBytes=1809
        { Assert-OPA265BW2Outcome -Outcome $script:BW2cOutcome -Proof $script:BW2cProof -ConfirmSourceSizeDifference -ExpectedSourceSizeBytes 1808 } | Should -Throw '*source-size evidence*'
    }
    It 'rejects a success-looking child claiming changed source EntryID' {
        $script:BW2cOutcome.Response.Result.SourceEntryIdMatchesIntent=$false
        { Assert-OPA265BW2Outcome -Outcome $script:BW2cOutcome -Proof $script:BW2cProof -ConfirmSourceSizeDifference -ExpectedSourceSizeBytes 1808 } | Should -Throw '*source-size evidence*'
    }
    It 'allows only verified consent-bound read-only Worker outcome' {
        (Assert-OPA265BW2Outcome -Outcome $script:BW2cOutcome -Proof $script:BW2cProof -ConfirmSourceSizeDifference -ExpectedSourceSizeBytes 1808) | Should -BeTrue
    }
    It 'rejects orphan expected-size option before starting any Worker' {
        Mock Get-OPA265BW2FixtureProof {throw 'do not read fixture'}
        Mock Invoke-OPAWorkerControlledOperation {throw 'must not dispatch'}
        { Invoke-OPA265BW2BoundedReadOnlyCanary -Gate $script:BW2cGate -RunId $script:BW2cRun -SourcePst $script:BW2cProof.SourcePst -ExpectedSourceSizeBytes 1808 } | Should -Throw '*require explicit*'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Exactly -Times 0
    }
    It 'rejects other RunId before Worker dispatch' {
        $script:BW2cProof.RunId=[guid]::NewGuid().ToString('D')
        Mock Get-OPA265BW2FixtureProof {return $script:BW2cProof}
        Mock Invoke-OPAWorkerControlledOperation {throw 'must not dispatch'}
        { Invoke-OPA265BW2BoundedReadOnlyCanary -Gate $script:BW2cGate -RunId $script:BW2cRun -SourcePst $script:BW2cProof.SourcePst -ConfirmSourceSizeDifference -ExpectedSourceSizeBytes 1808 } | Should -Throw '*outside exact pinned*'
        Should -Invoke Invoke-OPAWorkerControlledOperation -Exactly -Times 0
    }
    It 'does not introduce any Move, mount, or persistence API' {
        $path=Join-Path $PSScriptRoot '../../Core/Worker/SyntheticReadOnlyProbe265BW2.ps1'
        $text=Get-Content -LiteralPath $path -Raw
        $text | Should -Not -Match 'New-Object -ComObject|MailItem[.]Move|AddStoreEx|RemoveStore|Outlook.exe'
        $text | Should -Match "GetActiveObject[(]'Outlook.Application'[)]"
    }
    It 'exposes explicit CLI consent parameters before COM startup' {
        $main=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $main | Should -Match 'WorkerPilotConfirmSourceSizeDifference'
        $main | Should -Match 'WorkerPilotExpectedSourceSizeBytes'
        ($main.IndexOf('WorkerPilotConfirmSourceSizeDifference') -lt $main.IndexOf('$session = New-OPAComSession')) | Should -BeTrue
    }
    It 'parses edited Windows PowerShell scripts with PS5.1 AST' {
        foreach($n in @('OutlookPOP3Archive.ps1','Core/Worker/SyntheticReadOnlyProbe265BW2.ps1','Core/Worker/BoundedWorkerProbe265BW2.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $n
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
