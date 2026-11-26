#requires -Version 5.1
BeforeAll {
    $script:fRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:fRoot 'Core/Archive/ARCH7eAuto.ps1')
    . (Join-Path $script:fRoot 'Core/Archive/ARCH7dSupervisor.ps1')
}
Describe 'ARCH7f DEV diagnostics and safe pacing' {
    It 'returns zero only for known exhaustion or no sources' {
        foreach($state in @('AllSourcesExhausted','NoPop3Sources')){
            Get-OPAARCH7fExitCode -Result ([pscustomobject]@{Schema='2.6.5-ARCH7e.Auto.1';Status=$state;ProductionReady=$false}) | Should -Be 0
        }
    }
    It 'distinguishes bounded completion from blocked status' {
        $r=[pscustomobject]@{Schema='2.6.5-ARCH7e.Auto.1';Status='PartialOrBlocked';ProductionReady=$false;Sources=@([pscustomobject]@{Status='BatchLimitReached'})}
        Get-OPAARCH7fExitCode -Result $r | Should -Be 10
        $r.Sources[0].Status='WorkerStillRunning'
        Get-OPAARCH7fExitCode -Result $r | Should -Be 20
    }
    It 'rejects unknown and production-ready responses' {
        Get-OPAARCH7fExitCode -Result $null | Should -Be 30
        Get-OPAARCH7fExitCode -Result ([pscustomobject]@{Schema='2.6.5-ARCH7e.Auto.1';Status='AllSourcesExhausted';ProductionReady=$true}) | Should -Be 30
    }
    It 'uses capped exponential recovery backoff' {
        Get-OPAARCH7fRecoveryDelay -BaseSeconds 5 -Attempt 1 | Should -Be 5
        Get-OPAARCH7fRecoveryDelay -BaseSeconds 5 -Attempt 3 | Should -Be 20
        Get-OPAARCH7fRecoveryDelay -BaseSeconds 100 -Attempt 10 | Should -Be 300
        Get-OPAARCH7fRecoveryDelay -BaseSeconds 0 -Attempt 2 | Should -Be 0
    }
    It 'writes structured UTF8 diagnostic rows without pipeline noise' {
        $p=Join-Path $TestDrive 'diagnostic.jsonl'
        $fs=[IO.FileStream]::new($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
        try{Write-OPAARCH7fDiagnostic -Stream $fs -Phase Batch -Data @{SourcePst='Почта.pst';Verified=10} | Should -BeNullOrEmpty}finally{$fs.Dispose()}
        $r=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8))
        $r.Phase | Should -BeExactly Batch
        $r.Data.SourcePst | Should -BeExactly 'Почта.pst'
        $r.Data.Verified | Should -Be 10
    }
    It 'creates a private diagnostic root and reopens it without changing ACL' {
        $base=Join-Path $TestDrive 'private'
        [void][IO.Directory]::CreateDirectory($base)
        $p=New-OPAARCH7fLogRoot -BaseDirectory $base
        ([IO.Directory]::GetAccessControl($p)).AreAccessRulesProtected | Should -BeTrue
        (New-OPAARCH7fLogRoot -BaseDirectory $base) | Should -BeExactly $p
    }
    It 'rotates only exact old finalized diagnostic names and preserves evidence' {
        $d=Join-Path $TestDrive 'retention'
        [void][IO.Directory]::CreateDirectory($d)
        $names=@('ARCH7f-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.complete.jsonl','ARCH7f-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jsonl','ARCH4.pending','ARCH7f-invalid.complete.jsonl','ARCH7f-cccccccccccccccccccccccccccccccc.complete.jsonl')
        foreach($name in $names){[IO.File]::WriteAllText((Join-Path $d $name),'test')}
        foreach($name in $names[0..3]){[IO.File]::SetLastWriteTimeUtc((Join-Path $d $name),[DateTime]::UtcNow.AddDays(-40))}
        Remove-OPAARCH7fExpiredDiagnostics -Directory $d -RetentionDays 30
        [IO.File]::Exists((Join-Path $d $names[0])) | Should -BeFalse
        foreach($name in $names[1..4]){[IO.File]::Exists((Join-Path $d $name)) | Should -BeTrue}
    }
    It 'records and delays only between proven batches' {
        Mock Start-Sleep {}
        $row=[pscustomobject]@{SourcePst='fake.pst';Directory='fake'}
        $script:fRecords=0
        $r=Invoke-OPAARCH7eSourceSequence -Sources @($row) -MaxBatchesPerSource 2 -BatchDelaySeconds 2 -PendingOwner {} -RunSource {
            [pscustomobject]@{Schema='2.6.5-ARCH7d.Supervisor.1';Status='BatchLimitReached';Verified=1;Deferred=0;Unprocessed=0;Batches=1;ProductionReady=$false;AutomaticMoveRetryAllowed=$false;OutlookRestartRequired=$false;LastBatchResult=$null}
        } -Record {$script:fRecords++}
        $r.Verified | Should -Be 2
        $script:fRecords | Should -Be 2
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {$Seconds -eq 2}
    }
    It 'does not delay or dispatch another worker on unknown outcome' {
        Mock Start-Sleep {}
        $row=[pscustomobject]@{SourcePst='fake.pst';Directory='fake'}
        $r=Invoke-OPAARCH7eSourceSequence -Sources @($row) -MaxBatchesPerSource 3 -BatchDelaySeconds 2 -PendingOwner {} -RunSource {
            [pscustomobject]@{Schema='2.6.5-ARCH7d.Supervisor.1';Status='WorkerStillRunning';Verified=0;Deferred=0;Unprocessed=0;Batches=0;ProductionReady=$false;AutomaticMoveRetryAllowed=$false;OutlookRestartRequired=$false;LastBatchResult=$null}
        }
        $r.Sources[0].Attempts | Should -Be 1
        $r.Sources[0].Status | Should -BeExactly WorkerStillRunning
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }
    It 'exposes quiet options in public WhatIf and requires explicit consent' {
        $main=Join-Path $script:fRoot 'OutlookPOP3Archive.ps1'
        $r=& $main -Mode Auto -ConfirmDevAutoArchive -Quiet -AutoBatchDelaySeconds 4 -AutoRecoveryDelaySeconds 7 -AutoLogRetentionDays 20 -WhatIf
        $r.Status | Should -BeExactly NoOutlookOrPersistentWrites
        $r.Quiet | Should -BeTrue
        $r.BatchDelaySeconds | Should -Be 4
        $r.RecoveryDelaySeconds | Should -Be 7
        $r.LogRetentionDays | Should -Be 20
        {& $main -Mode Analyze -Quiet -WhatIf} | Should -Throw '*options require ConfirmDevAutoArchive*'
    }
}
