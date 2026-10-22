# FIX12: behavioral archive destination tests using real temporary files and
# mocked Outlook COM store/folder operations. No Outlook or large PST required.
BeforeAll {
    . "$PSScriptRoot/../../Core/Archive/ArchiveTransaction.ps1"
    . "$PSScriptRoot/../../Core/Archive/MailMover.ps1"

    function Set-FIX12FileLength {
        param([string]$Path, [int64]$Length)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
        try { $stream.SetLength($Length) }
        finally { $stream.Dispose() }
    }
}

Describe 'FIX12 archive capacity decisions' {
    It 'uses an inclusive safe-capacity boundary' {
        $safe = Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB 1 -SafetyMarginGB 0.1
        (Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes $safe -MaxArchivePstSizeGB 1 -SafetyMarginGB 0.1) | Should -Be 'WithinSafe'
        (Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes ($safe + 1) -MaxArchivePstSizeGB 1 -SafetyMarginGB 0.1) | Should -Be 'RolloverNext'
    }
    It 'treats the configured hard maximum independently from safety margin' {
        (Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes ([int64](1GB)) -MaxArchivePstSizeGB 1 -SafetyMarginGB 0.1) | Should -Be 'RolloverNext'
        (Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes ([int64](1GB) + 1) -MaxArchivePstSizeGB 1 -SafetyMarginGB 0.1) | Should -Be 'HardLimitExceeded'
    }
    It 'rejects invalid capacity settings' {
        { Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes 0 -MaxArchivePstSizeGB 0.1 -SafetyMarginGB 0.1 } | Should -Throw
    }
    It 'keeps the next-item rollover in the move loop and stops on a hard breach' {
        $text = Get-Content -LiteralPath "$PSScriptRoot/../../Core/Archive/MailMover.ps1" -Raw
        $text | Should -Match "(?s)if \(\`$postMoveCapacityAction -eq 'HardLimitExceeded'\).*?throw"
        $text | Should -Match "(?s)if \(\`$postMoveCapacityAction -eq 'RolloverNext'\).*?continue"
    }
}

Describe 'FIX12 Get-OPAArchiveDestination with mock Outlook and real PST size' {
    BeforeEach {
        $script:OPAArchivePartsCache = @{}
        $script:fixtureDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixtureDir -Force | Out-Null
        $script:source = Join-Path $script:fixtureDir 'account.pst'
        $script:tx = [pscustomobject]@{
            State = [pscustomobject]@{
                ArchivePsts = @()
                ArchivePst = ''
                CurrentArchivePst = ''
                Updated = ''
            }
        }
        $script:fakeNs = [pscustomobject]@{Name='OutlookMock'}
        Mock New-OPAArchivePst {
            param($Namespace,$ArchivePst,$AccountEmail)
            if (-not (Test-Path -LiteralPath $ArchivePst)) {
                [IO.File]::WriteAllBytes($ArchivePst, [byte[]]@())
            }
            return [pscustomobject]@{FilePath=$ArchivePst}
        }
        Mock Get-OPAArchiveFolder {
            param($ArchiveStore,$SourceFolderName,$SourceFolderPath,$ReceivedTime,$Grouping)
            return [pscustomobject]@{FolderPath='\\Archive\2020\Q1\Inbox'}
        }
    }

    It 'creates part 1 for the first message and registers its physical baseline' {
        $r = Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-01-10') -ItemSize (40KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox'
        [IO.Path]::GetFileName($r.Path) | Should -Be 'account.Archive-2020.pst'
        $r.Part | Should -Be 1
        $script:tx.State.ArchivePsts.Count | Should -Be 1
        Test-Path -LiteralPath $r.Path | Should -BeTrue
        Should -Invoke New-OPAArchivePst -Times 1 -Exactly
    }

    It 'selects the same part while the projected growth fits' {
        $p = Get-OPAArchivePartPath -SourcePst $script:source -Year 2020
        Set-FIX12FileLength -Path $p -Length (100KB)
        $r = Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-01-10') -ItemSize (40KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox'
        $r.Path | Should -Be $p
        $r.Part | Should -Be 1
        $script:tx.State.ArchivePsts.Count | Should -Be 1
    }

    It 'rolls to part 2 and then part 3 when highest part becomes full' {
        $p1 = Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 1
        Set-FIX12FileLength -Path $p1 -Length (800KB)
        $r1 = Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-01-10') -ItemSize (50KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox'
        $r1.Part | Should -Be 2
        [IO.Path]::GetFileName($r1.Path) | Should -Be 'account.Archive-2020-02.pst'
        Set-FIX12FileLength -Path $r1.Path -Length (800KB)
        $r2 = Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-01-11') -ItemSize (50KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox'
        $r2.Part | Should -Be 3
        [IO.Path]::GetFileName($r2.Path) | Should -Be 'account.Archive-2020-03.pst'
        $script:tx.State.ArchivePsts.Count | Should -Be 2
        Test-Path -LiteralPath $p1 | Should -BeTrue
    }

    It 'recovers from a persisted plan with part 2 and reuses that part when space allows' {
        $p1 = Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 1
        $p2 = Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 2
        Set-FIX12FileLength -Path $p1 -Length (800KB)
        Set-FIX12FileLength -Path $p2 -Length (120KB)
        $script:tx.State.ArchivePsts = @(
            [pscustomobject]@{Path=$p1;Year=2020;Part=1;PhysicalGrowthBytes=0;LogicalAddedBytes=0},
            [pscustomobject]@{Path=$p2;Year=2020;Part=2;PhysicalGrowthBytes=0;LogicalAddedBytes=0}
        )
        $r = Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-02-01') -ItemSize (50KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox'
        $r.Part | Should -Be 2
        $script:tx.State.ArchivePsts.Count | Should -Be 2
        Should -Invoke New-OPAArchivePst -Times 1 -Exactly
    }

    It 'never re-creates an archive part missing from a resumed transaction' {
        $missing = Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 2
        $script:tx.State.ArchivePsts = @([pscustomobject]@{Path=$missing;Year=2020;Part=2})
        { Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-02-01') -ItemSize (50KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox' } | Should -Throw '*registered archive part is missing*'
        Should -Invoke New-OPAArchivePst -Times 0 -Exactly
    }

    It 'rejects estimated oversized messages before creating the first PST' {
        { Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-02-01') -ItemSize (500KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox' } | Should -Throw '*estimated physical growth*'
        Should -Invoke New-OPAArchivePst -Times 0 -Exactly
        @(Get-ChildItem -LiteralPath $script:fixtureDir -Filter '*.pst').Count | Should -Be 0
    }

    It 'rechecks physical baseline after Outlook initializes a new PST' {
        # The initially empty file appears to fit, but Outlook's PST header
        # and directory pages may use capacity before the first message.
        Mock New-OPAArchivePst {
            param($Namespace,$ArchivePst,$AccountEmail)
            Set-FIX12FileLength -Path $ArchivePst -Length (300KB)
            return [pscustomobject]@{FilePath=$ArchivePst}
        }
        { Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-02-01') -ItemSize (300KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox' } | Should -Throw '*after initialization*'
    }

    It 'keeps distinct years in their own archives regardless of other years capacity' {
        $old = Get-OPAArchivePartPath -SourcePst $script:source -Year 2019 -Part 1
        $current = Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 1
        Set-FIX12FileLength -Path $old -Length (800KB)
        Set-FIX12FileLength -Path $current -Length (100KB)
        $r = Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-02-01') -ItemSize (50KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox'
        $r.Path | Should -Be $current
        $r.Part | Should -Be 1
    }

    It 'recognizes archive parts numbered 100 and higher' {
        $p = Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 100
        Set-FIX12FileLength -Path $p -Length (100KB)
        $parts = @(Get-OPAArchivePstPartsOnDisk -SourcePst $script:source -Year 2020)
        $parts.Count | Should -Be 1
        $parts[0].Part | Should -Be 100
        $r = Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-02-01') -ItemSize (40KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox'
        $r.Part | Should -Be 100
    }

    It 'rolls after a simulated post-Move overflow with no extra message moves in the old part' {
        $p1 = Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 1
        Set-FIX12FileLength -Path $p1 -Length (800KB)
        (Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes (800KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002) | Should -Be 'WithinSafe'
        # A simulated Outlook Move grew part 1 beyond the safe margin.
        Set-FIX12FileLength -Path $p1 -Length (900KB)
        (Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes (900KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002) | Should -Be 'RolloverNext'
        $r = Get-OPAArchiveDestination -Namespace $script:fakeNs -Transaction $script:tx -SourcePst $script:source -ReceivedTime ([datetime]'2020-02-01') -ItemSize (10KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox'
        $r.Part | Should -Be 2
    }
}


Describe 'FIX13b large-byte capacity diagnostics' {
    It 'reports zero remaining safe bytes even if an initialized PST is 5 GB over a small limit' {
        # The first part is created successfully, but the simulated COM
        # initialization measurement later reports a much larger PST.
        # This must throw the intentional capacity error, not an Int32 cast.
        $case = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $case -Force)
        $source = Join-Path $case 'source.pst'
        $transaction = [pscustomobject]@{
            State=[pscustomobject]@{ArchivePsts=@();ArchivePst='';CurrentArchivePst='';Updated=''}
        }
        $namespace = [pscustomobject]@{Name='MockNamespace'}
        Mock New-OPAArchivePst {
            param($Namespace,$ArchivePst,$AccountEmail)
            if (-not (Test-Path -LiteralPath $ArchivePst)) { [IO.File]::WriteAllBytes($ArchivePst, [byte[]]@()) }
            [pscustomobject]@{FilePath=$ArchivePst}
        }
        Mock Get-OPAArchiveFolder {
            param($ArchiveStore,$SourceFolderName,$SourceFolderPath,$ReceivedTime,$Grouping)
            [pscustomobject]@{FolderPath='\Archive\2020\Q1\Inbox'}
        }
        Mock Get-OPAArchivePstSizeBytes { return [int64](5GB) }
        { Get-OPAArchiveDestination -Namespace $namespace -Transaction $transaction -SourcePst $source -ReceivedTime ([datetime]'2020-01-10') -ItemSize (40KB) -MaxArchivePstSizeGB 0.001 -SafetyMarginGB 0.0002 -SourceFolderName 'Inbox' } |
            Should -Throw '*after initialization*'
    }

    It 'does not fail converting negative physical growth of more than 2 GB' {
        $path = 'mock-archive.pst'
        $e = [pscustomobject]@{
            Path=$path; PhysicalSizeBeforeBytes=[int64](6GB)
            PhysicalSizeAfterBytes=[int64](6GB)
            PhysicalGrowthBytes=[int64]0; LogicalAddedBytes=[int64]0
            PhysicalSizeBaselineCaptured=$true
        }
        $tx = [pscustomobject]@{State=[pscustomobject]@{ArchivePsts=@($e);Updated=''}}
        Update-OPAArchivePstTelemetry -Transaction $tx -ArchivePst $path -PhysicalSizeBytes (1GB)
        $e.PhysicalGrowthBytes | Should -Be ([int64]0)
        $e.PhysicalSizeAfterBytes | Should -Be ([int64](1GB))
    }
}
