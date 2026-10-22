# FIX13 Storage Policy: behavioral tests with sparse temporary PST files.
# These tests do not require Outlook or a production mailbox.
BeforeAll {
    . "$PSScriptRoot/../../Core/Runtime/JsonSupport.ps1"
    . "$PSScriptRoot/../../Core/Archive/ArchiveTransaction.ps1"
    . "$PSScriptRoot/../../Core/Archive/StoragePolicy.ps1"

    function Set-FIX13SparseFileLength {
        param([string]$Path,[int64]$Length)
        $stream = [IO.File]::Open($Path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
        try { $stream.SetLength($Length) }
        finally { $stream.Dispose() }
    }

    function New-FIX13VerifiedTransaction {
        param([string]$Source,[string]$Id,[int64]$Logical,[int]$Executed=1,[string]$Status='Completed',[int]$Verified=-1)
        if ($Verified -eq -1) { $Verified = $Executed }
        [pscustomobject]@{
            TransactionId = $Id
            State = [pscustomobject]@{
                Status = $Status
                SourcePst = $Source
                LogicalFreedBytes = $Logical
                SourcePstSizeBeforeBytes = [int64](12MB)
                SourcePstSizeAfterBytes = [int64](12MB)
                Executed = $Executed
                Planned = $Executed
                Verified = $Verified
            }
        }
    }
}

Describe 'FIX13 Auto storage-progress accounting' {
    BeforeEach {
        $script:caseDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $script:caseDir -Force)
        $script:sourcePst = Join-Path $script:caseDir 'source.pst'
        Set-FIX13SparseFileLength -Path $script:sourcePst -Length (12MB)
    }

    It 'keeps sidecars outside *.json transaction discovery and cleanup' {
        $path = Get-OPAAutoStorageProgressPath -SourcePst $script:sourcePst
        $path | Should -Match '\.auto-storage\.state$'
        (Split-Path -Leaf (Split-Path -Parent $path)) | Should -Be 'OutlookPOP3Archive-Transactions'
        (Get-OPAAutoStorageProgress -SourcePst $script:sourcePst -CurrentPhysicalBytes (12MB)) | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'requires archiving above the high watermark without ledger data' {
        $d = Get-OPAStoragePolicyDecision -SourcePst $script:sourcePst -HighWatermarkGB 0.01 -TargetSizeGB 0.008 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'ArchiveRequired'
        $d.CumulativeLogicalFreedBytes | Should -Be 0
        $d.RequiredReductionBytes | Should -BeGreaterThan (3MB)
        $d.CompactRecommended | Should -BeFalse
    }

    It 'credits only independently verified completed transactions' {
        $tx = New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'TX-A' -Logical (2MB)
        $p = Register-OPAAutoStorageProgress -Transaction $tx
        $p.CumulativeLogicalFreedBytes | Should -Be (2MB)
        $p.CompletedBatches | Should -Be 1
        $path = Get-OPAAutoStorageProgressPath -SourcePst $script:sourcePst
        Test-Path -LiteralPath $path | Should -BeTrue
        $after = Get-OPAAutoStorageProgress -SourcePst $script:sourcePst -CurrentPhysicalBytes (12MB)
        $after.CumulativeLogicalFreedBytes | Should -Be (2MB)
    }

    It 'refuses Running and VerificationFailed checkpoints' {
        $tx = New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'TX-R' -Logical (2MB) -Status 'Running'
        { Register-OPAAutoStorageProgress -Transaction $tx } | Should -Throw '*Completed*'
        $tx.State.Status = 'VerificationFailed'
        { Register-OPAAutoStorageProgress -Transaction $tx } | Should -Throw '*Completed*'
        Test-Path -LiteralPath (Get-OPAAutoStorageProgressPath -SourcePst $script:sourcePst) | Should -BeFalse
    }

    It 'refuses Completed checkpoints with inconsistent verification count' {
        $tx = New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'TX-V' -Logical (1MB) -Executed 2 -Verified 1
        { Register-OPAAutoStorageProgress -Transaction $tx } | Should -Throw '*independently verified*'
    }

    It 'pre-credits a verified batch before the Completed checkpoint is written' {
        $tx = New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'PRE-COMMIT' -Logical (2MB) -Status 'Running'
        $p = Register-OPAAutoStorageProgress -Transaction $tx -ConfirmedVerifiedCompletion
        $p.CumulativeLogicalFreedBytes | Should -Be (2MB)
        # Recovered Resume can repeat the credit and must remain idempotent.
        $tx.State.Status = 'Completed'
        $again = Register-OPAAutoStorageProgress -Transaction $tx
        $again.CompletedBatches | Should -Be 1
    }

    It 'refuses pre-credit when any planned item is still unfinished' {
        $tx = New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'INCOMPLETE' -Logical (1MB) -Status 'Running'
        $tx.State.Planned = 2
        { Register-OPAAutoStorageProgress -Transaction $tx -ConfirmedVerifiedCompletion } | Should -Throw '*incomplete batch*'
        Test-Path -LiteralPath (Get-OPAAutoStorageProgressPath -SourcePst $script:sourcePst) | Should -BeFalse
    }

    It 'does not credit the same completed transaction twice' {
        $tx = New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'TX-X' -Logical (2MB)
        [void](Register-OPAAutoStorageProgress -Transaction $tx)
        $p = Register-OPAAutoStorageProgress -Transaction $tx
        $p.CumulativeLogicalFreedBytes | Should -Be (2MB)
        $p.CompletedBatches | Should -Be 1
    }

    It 'subtracts credited logical removal from the remaining Auto target' {
        $tx = New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'TX-1' -Logical (1MB)
        [void](Register-OPAAutoStorageProgress -Transaction $tx)
        $d = Get-OPAStoragePolicyDecision -SourcePst $script:sourcePst -HighWatermarkGB 0.01 -TargetSizeGB 0.008 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'ArchiveRequired'
        $d.CumulativeLogicalFreedBytes | Should -Be (1MB)
        $d.RequiredReductionBytes | Should -BeGreaterThan (2MB)
        $d.RequiredReductionBytes | Should -BeLessThan (3MB)
    }

    It 'blocks additional Auto batches after logical target met with physical PST unchanged' {
        $tx = New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'TX-ENOUGH' -Logical (5MB)
        [void](Register-OPAAutoStorageProgress -Transaction $tx)
        $d = Get-OPAStoragePolicyDecision -SourcePst $script:sourcePst -HighWatermarkGB 0.01 -TargetSizeGB 0.008 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'CompactRequired'
        $d.CompactRecommended | Should -BeTrue
        $d.RequiredReductionBytes | Should -Be 0
        $d.RemainingLogicalTargetBytes | Should -Be 0
    }

    It 'pauses Auto after two verified no-progress batches' {
        [void](Register-OPAAutoStorageProgress -Transaction (New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'EMPTY-1' -Logical 0 -Executed 0))
        [void](Register-OPAAutoStorageProgress -Transaction (New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'EMPTY-2' -Logical 0 -Executed 0))
        $d = Get-OPAStoragePolicyDecision -SourcePst $script:sourcePst -HighWatermarkGB 0.01 -TargetSizeGB 0.008 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'AutoPaused'
        $d.EmptyAutoBatches | Should -Be 2
    }

    It 'uses a configurable no-progress threshold' {
        [void](Register-OPAAutoStorageProgress -Transaction (New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'EMPTY-1' -Logical 0 -Executed 0))
        $d = Get-OPAStoragePolicyDecision -SourcePst $script:sourcePst -HighWatermarkGB 0.01 -TargetSizeGB 0.008 -OlderThanMonths 12 -BatchLimit 50 -AutoMaxEmptyBatches 1
        $d.Decision | Should -Be 'AutoPaused'
    }

    It 'resets the consecutive no-progress count after a successful move' {
        [void](Register-OPAAutoStorageProgress -Transaction (New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'EMPTY-1' -Logical 0 -Executed 0))
        $p = Register-OPAAutoStorageProgress -Transaction (New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'RECOVERED' -Logical (1MB))
        $p.EmptyBatchCount | Should -Be 0
        $p.CompletedBatches | Should -Be 2
    }

    It 'does not count a physical PST shrink as another removal batch' {
        [void](Register-OPAAutoStorageProgress -Transaction (New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'BEFORE-COMPACT' -Logical (5MB)))
        Set-FIX13SparseFileLength -Path $script:sourcePst -Length (10MB)
        $now = Get-OPAAutoStorageProgress -SourcePst $script:sourcePst -CurrentPhysicalBytes (10MB)
        $now | Should -BeNullOrEmpty
        $d = Get-OPAStoragePolicyDecision -SourcePst $script:sourcePst -HighWatermarkGB 0.008 -TargetSizeGB 0.006 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'ArchiveRequired'
        $d.CumulativeLogicalFreedBytes | Should -Be 0
    }

    It 'does not persist a reset merely by reading the ledger (WhatIf-safe)' {
        [void](Register-OPAAutoStorageProgress -Transaction (New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'ORIGINAL' -Logical (2MB)))
        $path = Get-OPAAutoStorageProgressPath -SourcePst $script:sourcePst
        $original = [IO.File]::ReadAllBytes($path)
        Set-FIX13SparseFileLength -Path $script:sourcePst -Length (10MB)
        [void](Get-OPAStoragePolicyDecision -SourcePst $script:sourcePst -HighWatermarkGB 0.008 -TargetSizeGB 0.006 -OlderThanMonths 12 -BatchLimit 50)
        $after = [IO.File]::ReadAllBytes($path)
        [Convert]::ToBase64String($after) | Should -Be ([Convert]::ToBase64String($original))
    }

    It 'fails closed on corrupt ledger JSON' {
        $path = Get-OPAAutoStorageProgressPath -SourcePst $script:sourcePst
        [void](New-Item -Path (Split-Path -Parent $path) -ItemType Directory -Force)
        [IO.File]::WriteAllText($path,'not-a-json-document')
        { Get-OPAStoragePolicyDecision -SourcePst $script:sourcePst -HighWatermarkGB 0.01 -TargetSizeGB 0.008 -OlderThanMonths 12 -BatchLimit 50 } | Should -Throw
    }

    It 'fails closed if the ledger belongs to a different source PST' {
        $path = Get-OPAAutoStorageProgressPath -SourcePst $script:sourcePst
        [void](New-Item -Path (Split-Path -Parent $path) -ItemType Directory -Force)
        $bad = [pscustomobject]@{Version=1;SourcePst=(Join-Path $script:caseDir 'alien.pst');BaselinePhysicalBytes=1;LastPhysicalBytes=1;CumulativeLogicalFreedBytes=1;EmptyBatchCount=0;CompletedBatches=1;CompletedTransactionIds=@('alien')}
        [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $bad -Depth 5))
        { Get-OPAAutoStorageProgress -SourcePst $script:sourcePst -CurrentPhysicalBytes (12MB) } | Should -Throw '*mismatch*'
    }

    It 'keeps different PSTs in the same directory independent' {
        $other = Join-Path $script:caseDir 'other.pst'
        Set-FIX13SparseFileLength -Path $other -Length (12MB)
        [void](Register-OPAAutoStorageProgress -Transaction (New-FIX13VerifiedTransaction -Source $script:sourcePst -Id 'A' -Logical (2MB)))
        $first = Get-OPAAutoStorageProgressPath -SourcePst $script:sourcePst
        $second = Get-OPAAutoStorageProgressPath -SourcePst $other
        $first | Should -Not -Be $second
        Test-Path -LiteralPath $second | Should -BeFalse
    }

    It 'does not report a physical shrink when PST allocation has grown' {
        $d = Get-OPAStorageReclaimEstimate -PhysicalBeforeBytes (12MB) -PhysicalAfterBytes (13MB) -LogicalFreedBytes (2MB)
        $d.PhysicalReductionBytes | Should -Be 0
        $d.PhysicalGrowthBytes | Should -Be (1MB)
        $d.CompactAssessment | Should -Be 'ReviewRecommended'
    }

    It 'reports physical shrink separately from logical bytes moved' {
        $d = Get-OPAStorageReclaimEstimate -PhysicalBeforeBytes (12MB) -PhysicalAfterBytes (11MB) -LogicalFreedBytes (2MB)
        $d.PhysicalReductionBytes | Should -Be (1MB)
        $d.PhysicalGrowthBytes | Should -Be 0
        $d.LogicalFreedBytes | Should -Be (2MB)
        # 2 MB logical removal minus 1 MB already reflected in PST shrink = 1 MB.
        $d.UnmatchedLogicalReductionBytes | Should -Be (1MB)
        $d.CompactAssessment | Should -Be 'ReviewRecommended'
    }

    It 'does not report unmatched logical bytes when PST shrink exceeds logical removal' {
        $d = Get-OPAStorageReclaimEstimate -PhysicalBeforeBytes (12MB) -PhysicalAfterBytes (9MB) -LogicalFreedBytes (2MB)
        $d.PhysicalReductionBytes | Should -Be (3MB)
        $d.LogicalFreedBytes | Should -Be (2MB)
        $d.UnmatchedLogicalReductionBytes | Should -Be 0
        $d.CompactAssessment | Should -Be 'NotIndicated'
    }

    It 'reports all logical reduction as unmatched when PST physical length is unchanged' {
        $d = Get-OPAStorageReclaimEstimate -PhysicalBeforeBytes (12MB) -PhysicalAfterBytes (12MB) -LogicalFreedBytes (2MB)
        $d.PhysicalReductionBytes | Should -Be 0
        $d.PhysicalGrowthBytes | Should -Be 0
        $d.UnmatchedLogicalReductionBytes | Should -Be (2MB)
        $d.CompactAssessment | Should -Be 'ReviewRecommended'
    }

    It 'does not recommend Compact after all logical reduction is matched by shrink' {
        $d = Get-OPAStorageReclaimEstimate -PhysicalBeforeBytes (12MB) -PhysicalAfterBytes (10MB) -LogicalFreedBytes (1MB)
        $d.CompactAssessment | Should -Be 'NotIndicated'
    }

    It 'keeps the Auto origin flag for a manually resumed Auto transaction' {
        $scriptText = Get-Content -LiteralPath "$PSScriptRoot/../../OutlookPOP3Archive.ps1" -Raw
        $scriptText | Should -Match '\$tx\.State\[''AutoStorageTracked''\] = \[bool\]\$script:OPAAutoStorageTrackArchive'
        $scriptText | Should -Match '\$autoOrigin = \(Test-OPAStateHasKey'
    }

    It 'keeps Auto progress bookkeeping restricted to verified Auto runs' {
        $code = Get-Content -LiteralPath "$PSScriptRoot/../../OutlookPOP3Archive.ps1" -Raw
        $code | Should -Match 'if \(\$script:OPAAutoStorageTrackArchive -and \$archiveStatus -eq ''Completed''\)'
        $code | Should -Match 'if \(\(\$script:OPAAutoStorageTrackResume -or \$autoOrigin\) -and \$resumeStatus -eq ''Completed''\)' 
        $code | Should -Not -Match 'CompactNow\('
    }
}
