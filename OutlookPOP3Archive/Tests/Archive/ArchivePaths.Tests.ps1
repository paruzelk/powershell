BeforeAll {
    . "$PSScriptRoot/../../Core/Archive/MailMover.ps1"
}

Describe 'Get-OPAArchivePartPath' {
    It 'names the first part without a suffix' {
        Get-OPAArchivePartPath -SourcePst 'C:\Mail\user.pst' -Year 2023 | Should -Be 'C:\Mail\user.Archive-2023.pst'
    }
    It 'pads multi-parts to two digits' {
        Get-OPAArchivePartPath -SourcePst 'C:\Mail\user.pst' -Year 2023 -Part 2 | Should -Be 'C:\Mail\user.Archive-2023-02.pst'
    }
}

Describe 'Get-OPAArchivePstPartsOnDiskAll' {
    BeforeEach {
        $script:OPAArchivePartsCache = @{}
    }
    It 'finds and sorts parts by year and part' {
        foreach ($n in @('user.Archive-2022.pst','user.Archive-2023.pst','user.Archive-2023-02.pst','unrelated.pst')) {
            [IO.File]::WriteAllBytes((Join-Path $TestDrive $n), @())
        }
        $parts = @(Get-OPAArchivePstPartsOnDiskAll -SourcePst (Join-Path $TestDrive 'user.pst'))
        $parts.Count | Should -Be 3
        $parts[0].Year | Should -Be 2022
        $parts[1].Part | Should -Be 1
        $parts[2].Part | Should -Be 2
    }
    It 'returns empty for no parts and caches the result' {
        $src = Join-Path $TestDrive 'none.pst'
        @(Get-OPAArchivePstPartsOnDiskAll -SourcePst $src) | Should -Be @()
        $script:OPAArchivePartsCache.ContainsKey([IO.Path]::GetFullPath($src)) | Should -BeTrue
    }
}

Describe 'Archive capacity helpers' {
    It 'computes safe capacity in bytes' {
        Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB 10 -SafetyMarginGB 0.5 | Should -Be ([int64](9.5GB))
    }
    It 'throws when the margin consumes the whole archive' {
        { Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB 0.5 -SafetyMarginGB 0.5 } | Should -Throw
    }
    It 'classifies items against capacity' {
        Test-OPAItemFitsArchiveCapacity -ItemSize ([int64](1GB)) -MaxArchivePstSizeGB 10 -SafetyMarginGB 0.5 | Should -BeTrue
        Test-OPAItemFitsArchiveCapacity -ItemSize ([int64](20GB)) -MaxArchivePstSizeGB 10 -SafetyMarginGB 0.5 | Should -BeFalse
    }
}

Describe 'Get-OPAArchiveDisplayName' {
    BeforeAll {
        # Force a Russian UI culture so display-name assertions are
        # deterministic regardless of the CI runner locale.
        $script:OPASavedUICulture = [System.Globalization.CultureInfo]::CurrentUICulture
        [System.Globalization.CultureInfo]::CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('ru-RU')
    }
    AfterAll {
        if ($script:OPASavedUICulture) {
            [System.Globalization.CultureInfo]::CurrentUICulture = $script:OPASavedUICulture
        }
    }
    It 'builds the first-part name without a suffix' {
        Get-OPAArchiveDisplayName -AccountEmail 'user@example.com' -Year 2023 | Should -Be 'Архив user@example.com 2023'
    }
    It 'builds the multi-part name with a suffix' {
        Get-OPAArchiveDisplayName -AccountEmail 'user@example.com' -Year 2023 -Part 2 | Should -Be 'Архив user@example.com 2023 ч.2'
    }
    It 'rejects an empty email' {
        { Get-OPAArchiveDisplayName -AccountEmail ' ' -Year 2023 } | Should -Throw
    }
}
