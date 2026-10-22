BeforeAll {
    # Resolve repo root dynamically (same pattern as TransactionSchema.Tests).
    # Dot-source order matters: JsonSupport provides Read-OPAJsonFile that
    # StoragePolicy now uses for the AV-locked checkpoint reads.
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'Core\Runtime\JsonSupport.ps1')
    . (Join-Path $repoRoot 'Core\Archive\StoragePolicy.ps1')
}
Describe 'Convert-OPAStoragePolicyGBToBytes' {
    It 'converts GB to bytes' {
        Convert-OPAStoragePolicyGBToBytes -Gigabytes 1 | Should -Be 1GB
    }
    It 'rejects negative values' {
        { Convert-OPAStoragePolicyGBToBytes -Gigabytes -1 } | Should -Throw
    }
}

Describe 'Test-OPAStoragePolicyConfiguration' {
    It 'accepts a valid configuration' {
        Test-OPAStoragePolicyConfiguration -HighWatermarkGB 40 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 500 | Should -BeTrue
    }
    It 'rejects target size at or above the high watermark' {
        { Test-OPAStoragePolicyConfiguration -HighWatermarkGB 40 -TargetSizeGB 40 -OlderThanMonths 12 -BatchLimit 500 } | Should -Throw
        { Test-OPAStoragePolicyConfiguration -HighWatermarkGB 40 -TargetSizeGB 41 -OlderThanMonths 12 -BatchLimit 500 } | Should -Throw
    }
    It 'rejects zero/negative sizes and batch limit' {
        { Test-OPAStoragePolicyConfiguration -HighWatermarkGB 0 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 500 } | Should -Throw
        { Test-OPAStoragePolicyConfiguration -HighWatermarkGB 40 -TargetSizeGB 0 -OlderThanMonths 12 -BatchLimit 500 } | Should -Throw
        { Test-OPAStoragePolicyConfiguration -HighWatermarkGB 40 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 0 } | Should -Throw
    }
}

Describe 'Get-OPAStoragePolicyDecision' {
    BeforeEach {
        $script:pst = Join-Path $TestDrive 'source.pst'
        [IO.File]::WriteAllBytes($script:pst, (New-Object byte[] (50MB)))
    }
    It 'requires archive when size is above the high watermark' {
        $d = Get-OPAStoragePolicyDecision -SourcePst $script:pst -HighWatermarkGB 0.04 -TargetSizeGB 0.03 -OlderThanMonths 12 -BatchLimit 500
        $d.Decision | Should -Be 'ArchiveRequired'
        $d.RequiredReductionGB | Should -BeGreaterThan 0
    }
    It 'takes no action at or below the high watermark' {
        $d = Get-OPAStoragePolicyDecision -SourcePst $script:pst -HighWatermarkGB 1 -TargetSizeGB 0.5 -OlderThanMonths 12 -BatchLimit 500
        $d.Decision | Should -Be 'NoAction'
        $d.RequiredReductionGB | Should -Be 0
    }
    It 'throws when the PST is missing' {
        { Get-OPAStoragePolicyDecision -SourcePst (Join-Path $TestDrive 'missing.pst') -HighWatermarkGB 40 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 500 } | Should -Throw
    }
}


Describe 'Average message size transaction filtering' {
    It 'function is available for completed-only telemetry' {
        (Get-Command Get-OPAAverageMessageSize -ErrorAction Stop).Name | Should -Be 'Get-OPAAverageMessageSize'
    }
}

# FIX13b: these values deliberately cross the signed Int32 range. The legacy
# [Math]::Max(0, <Double>) overload threw on the live 7.03 GB / 35 GB plan.
Describe 'FIX13b storage decisions with 64-bit physical sizes' {
    BeforeEach {
        # Tests are independent of a real, large PST: emulate only the file
        # length and progress ledger, and exercise the real policy function.
        Mock Get-OPAAutoStorageProgress { return $null }
    }

    It 'returns NoAction for a 7 GB PST with default 40/35 GB thresholds' {
        Mock Get-OPAPstFileSize {
            [pscustomobject]@{Path='mock-7gb.pst';SizeBytes=[int64](7GB);SizeGB=7.00}
        }
        $d = Get-OPAStoragePolicyDecision -SourcePst 'mock-7gb.pst' -HighWatermarkGB 40 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'NoAction'
        $d.PhysicalBytesAboveTarget | Should -Be ([int64]0)
        $d.RemainingLogicalTargetBytes | Should -Be ([int64]0)
        $d.RequiredReductionBytes | Should -Be ([int64]0)
    }

    It 'keeps a 36 GB source below the 40 GB high-watermark in NoAction' {
        Mock Get-OPAPstFileSize {
            [pscustomobject]@{Path='mock-36gb.pst';SizeBytes=[int64](36GB);SizeGB=36.00}
        }
        $d = Get-OPAStoragePolicyDecision -SourcePst 'mock-36gb.pst' -HighWatermarkGB 40 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'NoAction'
        $d.PhysicalBytesAboveTarget | Should -Be ([int64](1GB))
        $d.RemainingLogicalTargetBytes | Should -Be ([int64](1GB))
    }

    It 'requires 10 GB logical reduction for a 45 GB PST targeting 35 GB' {
        Mock Get-OPAPstFileSize {
            [pscustomobject]@{Path='mock-45gb.pst';SizeBytes=[int64](45GB);SizeGB=45.00}
        }
        $d = Get-OPAStoragePolicyDecision -SourcePst 'mock-45gb.pst' -HighWatermarkGB 40 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'ArchiveRequired'
        $d.PhysicalBytesAboveTarget | Should -Be ([int64](10GB))
        $d.RequiredReductionBytes | Should -Be ([int64](10GB))
    }

    It 'subtracts 3 GB credited progress from the 10 GB physical over-target amount' {
        Mock Get-OPAPstFileSize {
            [pscustomobject]@{Path='mock-progress.pst';SizeBytes=[int64](45GB);SizeGB=45.00}
        }
        Mock Get-OPAAutoStorageProgress {
            [pscustomobject]@{CumulativeLogicalFreedBytes=[int64](3GB);EmptyBatchCount=0;CompletedBatches=1}
        }
        $d = Get-OPAStoragePolicyDecision -SourcePst 'mock-progress.pst' -HighWatermarkGB 40 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'ArchiveRequired'
        $d.RemainingLogicalTargetBytes | Should -Be ([int64](7GB))
    }

    It 'stops at CompactRequired when credited bytes exceed a 10 GB target' {
        Mock Get-OPAPstFileSize {
            [pscustomobject]@{Path='mock-compact.pst';SizeBytes=[int64](45GB);SizeGB=45.00}
        }
        Mock Get-OPAAutoStorageProgress {
            [pscustomobject]@{CumulativeLogicalFreedBytes=[int64](11GB);EmptyBatchCount=0;CompletedBatches=2}
        }
        $d = Get-OPAStoragePolicyDecision -SourcePst 'mock-compact.pst' -HighWatermarkGB 40 -TargetSizeGB 35 -OlderThanMonths 12 -BatchLimit 50
        $d.Decision | Should -Be 'CompactRequired'
        $d.RemainingLogicalTargetBytes | Should -Be ([int64]0)
        $d.CompactRecommended | Should -BeTrue
    }

    It 'reports physical growth across many gigabytes without Int32 binding' {
        $d = Get-OPAStorageReclaimEstimate -PhysicalBeforeBytes (7GB) -PhysicalAfterBytes (45GB) -LogicalFreedBytes (3GB)
        $d.PhysicalReductionBytes | Should -Be ([int64]0)
        $d.PhysicalGrowthBytes | Should -Be ([int64](38GB))
        $d.UnmatchedLogicalReductionBytes | Should -Be ([int64](3GB))
    }

    It 'reports a large physical shrink without losing 64-bit precision' {
        $d = Get-OPAStorageReclaimEstimate -PhysicalBeforeBytes (45GB) -PhysicalAfterBytes (7GB) -LogicalFreedBytes (40GB)
        $d.PhysicalReductionBytes | Should -Be ([int64](38GB))
        $d.PhysicalGrowthBytes | Should -Be ([int64]0)
        $d.UnmatchedLogicalReductionBytes | Should -Be ([int64](2GB))
    }
}
