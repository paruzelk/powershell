#requires -Version 5.1
BeforeAll {
    $root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $main=Join-Path $root 'OutlookPOP3Archive.ps1'
    . (Join-Path $root 'Core/Version.ps1')
    . (Join-Path $root 'Core/Runtime/JsonSupport.ps1')
    . (Join-Path $root 'Core/Runtime/ComManager.ps1')
    . (Join-Path $root 'Core/Archive/ArchiveGrouping.ps1')
    . (Join-Path $root 'Core/Archive/ArchiveTransaction.ps1')
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($main,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw 'Stable monolithic script must parse.' }
    $func=@($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Get-OPAArchiveCutoff'
    },$true))
    if ($func.Count -ne 1) { throw 'Expected exactly one stable archive cutoff function.' }
    Invoke-Expression ([string]$func[0].Extent.Text)
}
Describe 'FIX13b stable yearly operator cutoff and rollover protection' {
    BeforeEach { $script:ArchiveThroughYear=2025 }
    It 'uses 2026-01-01 midnight as exclusive boundary for full 2025 calendar year' {
        $cut=Get-OPAArchiveCutoff -OlderThanMonths 0
        $cut | Should -Be ([datetime]'2026-01-01T00:00:00')
        ([datetime]'2025-12-31T23:59:59' -lt $cut) | Should -BeTrue
        ([datetime]'2026-01-01T00:00:00' -lt $cut) | Should -BeFalse
    }
    It 'ignores rolling-month count when an explicit yearly cutoff is pinned' {
        (Get-OPAArchiveCutoff -OlderThanMonths 12) | Should -Be ([datetime]'2026-01-01T00:00:00')
    }
    It 'preserves original FIX13b rolling-month default without yearly opt-in' {
        $script:ArchiveThroughYear=0
        (Get-OPAArchiveCutoff -OlderThanMonths 0) | Should -BeNullOrEmpty
        $cut=Get-OPAArchiveCutoff -OlderThanMonths 12
        [math]::Abs(((Get-Date).AddMonths(-12)-$cut).TotalSeconds) | Should -BeLessThan 5
    }
    It 'routes 2025 and 2024 to different YEAR PST basenames' {
        $src=Join-Path $TestDrive 'source.pst'
        $p25=Get-OPAArchivePartPath -SourcePst $src -Year 2025
        $p24=Get-OPAArchivePartPath -SourcePst $src -Year 2024
        $p25 | Should -Match 'source.Archive-2025.pst$'
        $p24 | Should -Match 'source.Archive-2024.pst$'
        $p25 | Should -Not -Be $p24
    }
    It 'preserves Inbox, Sent and custom folder hierarchy within each yearly PST' {
        (Get-OPAArchiveTargetPath -ReceivedTime ([datetime]'2025-07-01') -SourceFolderPath '\\Store\Входящие' -Grouping 'Year') | Should -Be '2025\Входящие'
        (Get-OPAArchiveTargetPath -ReceivedTime ([datetime]'2024-07-01') -SourceFolderPath '\\Store\Отправленные' -Grouping 'Year') | Should -Be '2024\Отправленные'
        (Get-OPAArchiveTargetPath -ReceivedTime ([datetime]'2023-07-01') -SourceFolderPath '\\Store\Проекты\Отдел' -Grouping 'Year') | Should -Be '2023\Проекты\Отдел'
    }
    It 'persists fixed cutoff for manual safe Resume even when OlderThanMonths is zero' {
        $source=Join-Path $TestDrive ('year-'+[guid]::NewGuid().ToString('N')+'.pst')
        $tx=New-OPAArchiveTransaction -SourcePst $source -ArchivePst '' -Limit 1000 -ArchiveGrouping 'Year' -OlderThanMonths 0 -ArchiveCutoff ([datetime]'2026-01-01T00:00:00') -AccountEmail 'synthetic@example.invalid'
        $tx.State.ArchiveCutoff | Should -Match '^2026-01-01T00:00:00'
        $loaded=Get-OPAArchiveTransaction -SourcePst $source -TransactionId $tx.TransactionId
        [datetime]$loaded.State.ArchiveCutoff | Should -Be ([datetime]'2026-01-01T00:00:00')
        Test-OPAArchiveTransactionSchema -TransactionState $loaded.State | Should -BeTrue
    }
    It 'preserves original safe PST rollover when archive approaches configured physical cap' {
        $safe=Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB 47.5 -SafetyMarginGB 0.5
        $safe | Should -Be ([int64](47GB))
        (Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes ($safe + 1) -MaxArchivePstSizeGB 47.5 -SafetyMarginGB 0.5) | Should -Be 'RolloverNext'
    }
    It 'operator launcher uses explicit Year and Safe durability, never production DEV Worker or physical-limit bypass' {
        $launch=Get-Content -LiteralPath (Join-Path $root 'StableYearly/Start-StableYearlyArchive.ps1') -Raw
        $launch | Should -Match "ArchiveGrouping='Year'"
        $launch | Should -Match "ArchiveThroughYear=\`$ArchiveThroughYear"
        $launch | Should -Match "DurabilityMode='Safe'"
        $launch | Should -Match "WarnLargeFileSize"
        $launch | Should -Not -Match '\.Move\('
    }
}
AfterAll {
    if (Get-Command Close-OPAStepJournalStreams -ErrorAction SilentlyContinue) { Close-OPAStepJournalStreams }
}
