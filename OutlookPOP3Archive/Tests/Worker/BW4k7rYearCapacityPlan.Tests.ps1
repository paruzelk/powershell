#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7pFolderScopeInventory265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7rYearCapacityPlan265.ps1')
    function New-BW4k7rSample {
        $a=New-OPA265BW4k7rYearAccumulator
        Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2025 -DateField ReceivedTime -ItemSizeBytes 1000
        Add-OPA265BW4k7rItemObservation -Accumulator $a -Role SentItems -ItemClass 43 -Year 2025 -DateField SentOn -ItemSizeBytes 2000
        Add-OPA265BW4k7rItemObservation -Accumulator $a -Role UserMail -ItemClass 43 -Year 2024 -DateField ReceivedTime -ItemSizeBytes 3000
        return $a
    }
    function Get-BW4k7rSamplePlan {
        param([psobject]$Accumulator,[psobject]$Capacity,[bool]$Complete=$true,
              [int]$ArchiveBeforeYear=2026)
        if($null -eq $Accumulator){$Accumulator=New-BW4k7rSample}
        if($null -eq $Capacity){$Capacity=Get-OPA265BW4k7rSafeCapacity}
        return @(Get-OPA265BW4k7rCapacityPlan -Accumulator $Accumulator -Capacity $Capacity -SourcePst 'C:\mail\info@stios.ru.pst' -ArchiveBeforeYear $ArchiveBeforeYear -ScanComplete:$Complete)
    }
}
Describe 'BW4k7r per-year POP3 Inbox Sent user folder and capacity read-only forecast policy' {
    It 'pure empty accumulator initial schema' {
        (New-OPA265BW4k7rYearAccumulator).Schema | Should -BeExactly '2.6.5-BW4k7r.InMemoryYearAccumulator.1'
    }
    It 'pure empty accumulator has no years' {
        (New-OPA265BW4k7rYearAccumulator).Buckets.Count | Should -Be 0
    }
    It 'three sample mails counted' {
        (New-BW4k7rSample).MailItemsObserved | Should -Be 3
    }
    It 'three sample messages examined' {
        (New-BW4k7rSample).ItemsExamined | Should -Be 3
    }
    It 'three sample dated mail counted' {
        (New-BW4k7rSample).DatedMailObserved | Should -Be 3
    }
    It 'sample total 6000 metadata bytes' {
        (New-BW4k7rSample).MailItemSizeObservedBytes | Should -Be 6000
    }
    It 'sample largest item size 3000' {
        (New-BW4k7rSample).LargestMailItemSizeObservedBytes | Should -Be 3000
    }
    It 'separate 2024 and 2025 years' {
        (New-BW4k7rSample).Buckets.Count | Should -Be 2
    }
    It 'exact 2025 Inbox count' {
        (New-BW4k7rSample).Buckets['2025'].InboxMailItems | Should -Be 1
    }
    It 'exact 2025 Sent count' {
        (New-BW4k7rSample).Buckets['2025'].SentItemsMailItems | Should -Be 1
    }
    It 'exact 2024 UserFolder count' {
        (New-BW4k7rSample).Buckets['2024'].UserFolderMailItems | Should -Be 1
    }
    It 'sample 2025 Sent size' {
        (New-BW4k7rSample).Buckets['2025'].SentItemsSizeBytes | Should -Be 2000
    }
    It 'sample 2024 user size' {
        (New-BW4k7rSample).Buckets['2024'].UserFolderSizeBytes | Should -Be 3000
    }
    It 'year plan has 2 rows' {
        @(Get-BW4k7rSamplePlan).Count | Should -Be 2
    }
    It 'year plan sorted ascending' {
        $p=@(Get-BW4k7rSamplePlan); $p[0].Year | Should -Be 2024; $p[1].Year | Should -Be 2025
    }
    It 'exact yearly filename 2024' {
        @(Get-BW4k7rSamplePlan)[0].FirstPlannedArchivePst | Should -BeExactly 'info@stios.ru.Archive-2024.pst'
    }
    It 'exact yearly filename 2025' {
        @(Get-BW4k7rSamplePlan)[1].FirstPlannedArchivePst | Should -BeExactly 'info@stios.ru.Archive-2025.pst'
    }
    It 'all observed sample rows complete coverage when claimed' {
        $p=@(Get-BW4k7rSamplePlan); @($p | Where-Object {$_.Coverage -ne 'FullyEnumeratedObservedMetadata'}).Count | Should -Be 0
    }
    It 'partial sample flagged lower bound' {
        @(Get-BW4k7rSamplePlan -Complete $false)[0].Coverage | Should -BeExactly 'PartialLowerBoundOnly'
    }
    It 'archive before 2026 excludes 2026 current year' {
        $a=New-BW4k7rSample; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2026 -DateField ReceivedTime -ItemSizeBytes 1000; $p=@(Get-BW4k7rSamplePlan -Accumulator $a); @($p | Where-Object {$_.Year -eq 2026})[0].ArchiveYearEligible | Should -BeFalse
    }
    It 'archive before 2026 includes 2025' {
        @(Get-BW4k7rSamplePlan)[1].ArchiveYearEligible | Should -BeTrue
    }
    It 'archive before 2025 excludes 2025' {
        $p=@(Get-BW4k7rSamplePlan -ArchiveBeforeYear 2025); $p[1].ArchiveYearEligible | Should -BeFalse
    }
    It 'capacity forecast never creates PST' {
        @(Get-BW4k7rSamplePlan)[0].NoArchiveFileCreated | Should -BeTrue
    }
    It 'capacity never commits rollover' {
        @(Get-BW4k7rSamplePlan)[0].NoRolloverAllocationCommitted | Should -BeTrue
    }
    It 'capacity segment count is explicitly estimate' {
        @(Get-BW4k7rSamplePlan)[0].SegmentCountIsOnlyForecast | Should -BeTrue
    }
    It 'empty year plan no file' {
        @(Get-BW4k7rSamplePlan -Accumulator (New-OPA265BW4k7rYearAccumulator)).Count | Should -Be 0
    }
    It 'empty year plan integrity valid' {
        $a=New-OPA265BW4k7rYearAccumulator; (Assert-OPA265BW4k7rPlanIntegrity -Accumulator $a -YearPlan @()) | Should -BeTrue
    }
    It 'sample plan integrity valid' {
        $a=New-BW4k7rSample; $p=@(Get-BW4k7rSamplePlan -Accumulator $a); (Assert-OPA265BW4k7rPlanIntegrity -Accumulator $a -YearPlan $p) | Should -BeTrue
    }
    It 'default maximum archive PST 45 billion' {
        (Get-OPA265BW4k7rSafeCapacity).MaxArchivePstSizeBytes | Should -Be 45000000000
    }
    It 'default safety margin 3 billion' {
        (Get-OPA265BW4k7rSafeCapacity).SafetyMarginBytes | Should -Be 3000000000
    }
    It 'default usable forecast 42 billion' {
        (Get-OPA265BW4k7rSafeCapacity).UsableEstimatedPayloadBytes | Should -Be 42000000000
    }
    It 'default expansion 25 percent' {
        (Get-OPA265BW4k7rSafeCapacity).EstimatedExpansionPct | Should -Be 25
    }
    It 'default per-message 64 KiB' {
        (Get-OPA265BW4k7rSafeCapacity).PerMessageOverheadBytes | Should -Be 65536
    }
    It 'capacity never verifies actual registry without reading it' {
        (Get-OPA265BW4k7rSafeCapacity).RealArchivePstLimitOrRegistryVerified | Should -BeFalse
    }
    It 'capacity never claims physical growth guarantee' {
        (Get-OPA265BW4k7rSafeCapacity).PhysicalDestinationPstGrowthProven | Should -BeFalse
    }
    It 'capacity never alters registry limits' {
        (Get-OPA265BW4k7rSafeCapacity).NoMaxPstLimitDisabledOrRegistryWritten | Should -BeTrue
    }
    It 'safety margin equal max rejected' {
        {Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes 104857600 -SafetyMarginBytes 104857600} | Should -Throw
    }
    It 'safety margin greater max rejected' {
        {Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes 104857600 -SafetyMarginBytes 105000000} | Should -Throw
    }
    It 'usable segment under 10MiB rejected' {
        {Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes 104857600 -SafetyMarginBytes 102000000} | Should -Throw
    }
    It 'max PST below 100MiB rejected' {
        {Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes 104857599} | Should -Throw
    }
    It 'negative margin rejected' {
        {Get-OPA265BW4k7rSafeCapacity -SafetyMarginBytes -1} | Should -Throw
    }
    It 'expansion over 200 rejected' {
        {Get-OPA265BW4k7rSafeCapacity -EstimatedExpansionPct 201} | Should -Throw
    }
    It 'overhead >1MiB rejected' {
        {Get-OPA265BW4k7rSafeCapacity -PerMessageOverheadBytes 1048577} | Should -Throw
    }
    It 'forecast exact projected sample 2025' {
        $p=@(Get-BW4k7rSamplePlan); $p[1].ForecastRequiredBytes | Should -Be (3750+2*65536)
    }
    It 'large payload causes forecast -02 segment' {
        $a=New-OPA265BW4k7rYearAccumulator; for($i=0;$i -lt 3;$i++){Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2022 -DateField ReceivedTime -ItemSizeBytes 50000000}; $c=Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes 104857600 -SafetyMarginBytes 1048576 -EstimatedExpansionPct 0 -PerMessageOverheadBytes 0; $p=@(Get-BW4k7rSamplePlan -Accumulator $a -Capacity $c); $p[0].ForecastMinimumSegmentsForObservedBytes | Should -Be 2; $p[0].SecondNameIfRolloverEstimated | Should -BeExactly 'info@stios.ru.Archive-2022-02.pst'
    }
    It 'single message bigger than usable segment is flagged' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2020 -DateField ReceivedTime -ItemSizeBytes 110000000; $c=Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes 104857600 -SafetyMarginBytes 1048576 -EstimatedExpansionPct 0 -PerMessageOverheadBytes 0; $p=@(Get-BW4k7rSamplePlan -Accumulator $a -Capacity $c); $p[0].EstimatedLargestMessageFitsSegment | Should -BeFalse
    }
    It 'single message within safe segment fits' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2020 -DateField ReceivedTime -ItemSizeBytes 50000000; $c=Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes 104857600 -SafetyMarginBytes 1048576 -EstimatedExpansionPct 0 -PerMessageOverheadBytes 0; @(Get-BW4k7rSamplePlan -Accumulator $a -Capacity $c)[0].EstimatedLargestMessageFitsSegment | Should -BeTrue
    }
    It 'no rollover when within safe segment' {
        @(Get-BW4k7rSamplePlan)[0].SecondNameIfRolloverEstimated | Should -BeNullOrEmpty
    }
    It 'fallback from Sent to Received recorded' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role SentItems -ItemClass 43 -Year 2024 -DateField ReceivedTime -ItemSizeBytes 500; $a.FallbackDateObserved | Should -Be 1
    }
    It 'fallback from Inbox to Sent recorded' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2024 -DateField SentOn -ItemSizeBytes 500; $a.FallbackDateObserved | Should -Be 1
    }
    It 'normal SentOn for Sent is not fallback' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role SentItems -ItemClass 43 -Year 2024 -DateField SentOn -ItemSizeBytes 500; $a.FallbackDateObserved | Should -Be 0
    }
    It 'normal Received for Inbox is not fallback' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2024 -DateField ReceivedTime -ItemSizeBytes 500; $a.FallbackDateObserved | Should -Be 0
    }
    It 'nonmail item is not allocated to any year' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 48 -DateField NonMailItem; $a.ItemsExamined | Should -Be 1; $a.NonMailObserved | Should -Be 1; $a.Buckets.Count | Should -Be 0
    }
    It 'undated mail is counted separately and not invented as 2026' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -DateField Unknown -ItemSizeBytes 800; $a.UndatedMailObserved | Should -Be 1; $a.Buckets.Count | Should -Be 0
    }
    It 'undated mail keeps size as observed' {
        $a=New-OPA265BW4k7rYearAccumulator; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -DateField Unknown -ItemSizeBytes 800; $a.MailItemSizeObservedBytes | Should -Be 800
    }
    It 'undated and dated counts reconcile' {
        $a=New-BW4k7rSample; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -DateField Unknown -ItemSizeBytes 300; $p=@(Get-BW4k7rSamplePlan -Accumulator $a); (Assert-OPA265BW4k7rPlanIntegrity -Accumulator $a -YearPlan $p) | Should -BeTrue
    }
    It 'nonmail and mail counts reconcile' {
        $a=New-BW4k7rSample; Add-OPA265BW4k7rItemObservation -Accumulator $a -Role UserMail -ItemClass 48 -DateField NonMailItem; $p=@(Get-BW4k7rSamplePlan -Accumulator $a); (Assert-OPA265BW4k7rPlanIntegrity -Accumulator $a -YearPlan $p) | Should -BeTrue
    }
    It 'invalid year before 1990 blocked' {
        $a=New-OPA265BW4k7rYearAccumulator; {Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 1989 -DateField ReceivedTime -ItemSizeBytes 100} | Should -Throw
    }
    It 'invalid year after 2100 blocked' {
        $a=New-OPA265BW4k7rYearAccumulator; {Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2101 -DateField ReceivedTime -ItemSizeBytes 100} | Should -Throw
    }
    It 'invalid negative mail size blocked' {
        $a=New-OPA265BW4k7rYearAccumulator; {Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2025 -DateField ReceivedTime -ItemSizeBytes -1} | Should -Throw
    }
    It 'invalid >2GB single item metadata blocked' {
        $a=New-OPA265BW4k7rYearAccumulator; {Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2025 -DateField ReceivedTime -ItemSizeBytes 2147483648} | Should -Throw
    }
    It 'nonmail cannot pretend to have a year' {
        $a=New-OPA265BW4k7rYearAccumulator; {Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 48 -Year 2025 -DateField NonMailItem} | Should -Throw
    }
    It 'dated mail cannot use Unknown date source' {
        $a=New-OPA265BW4k7rYearAccumulator; {Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -Year 2025 -DateField Unknown} | Should -Throw
    }
    It 'undated mail cannot use SentOn' {
        $a=New-OPA265BW4k7rYearAccumulator; {Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Inbox -ItemClass 43 -DateField SentOn} | Should -Throw
    }
    It 'unrecognized role rejected' {
        $a=New-OPA265BW4k7rYearAccumulator; {Add-OPA265BW4k7rItemObservation -Accumulator $a -Role Outbox -ItemClass 43 -Year 2025 -DateField SentOn} | Should -Throw
    }
    It 'tampered accumulator schema rejected' {
        $a=New-BW4k7rSample; $a.Schema='Fake'; {Get-BW4k7rSamplePlan -Accumulator $a} | Should -Throw
    }
    It 'mismatched yearly count rejected' {
        $a=New-BW4k7rSample; $p=@(Get-BW4k7rSamplePlan -Accumulator $a); $p[0].TotalMailItems=1000; {Assert-OPA265BW4k7rPlanIntegrity -Accumulator $a -YearPlan $p} | Should -Throw
    }
    It 'mismatched item observations rejected' {
        $a=New-BW4k7rSample; $p=@(Get-BW4k7rSamplePlan -Accumulator $a); $a.ItemsExamined=4; {Assert-OPA265BW4k7rPlanIntegrity -Accumulator $a -YearPlan $p} | Should -Throw
    }
    It 'plan claiming it created PST rejected' {
        $a=New-BW4k7rSample; $p=@(Get-BW4k7rSamplePlan -Accumulator $a); $p[0].NoArchiveFileCreated=$false; {Assert-OPA265BW4k7rPlanIntegrity -Accumulator $a -YearPlan $p} | Should -Throw
    }
    It 'plan claiming exact segment assignment rejected' {
        $a=New-BW4k7rSample; $p=@(Get-BW4k7rSamplePlan -Accumulator $a); $p[0].SegmentCountIsOnlyForecast=$false; {Assert-OPA265BW4k7rPlanIntegrity -Accumulator $a -YearPlan $p} | Should -Throw
    }
    It 'controller always chains Q exclusion policy' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1'
    }
    It 'controller rechecks Q policy after scan' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); ([regex]::Matches($s,'Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1')).Count | Should -Be 2
    }
    It 'controller uses StoreID GetFolderFromID not default store' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'GetFolderFromID'
    }
    It 'controller cannot inspect quarantined tests' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'TestFolderOrDescendant'
    }
    It 'controller bounded message count default' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'MaxTotalItems=5000'
    }
    It 'controller output identifies partial year coverage' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'BoundedPartialPOP3YearDistributionNoCompleteCoverage'
    }
    It 'controller progress at bounded intervals' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'Write-Progress'
    }
    It 'controller reports no atomic PST snapshot proof' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'AtomicPstSnapshotEstablished=\$false'
    }
    It 'controller no durable resume false claim' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'NoPostCrashDurableResumeCheckpointCreated=\$true'
    }
    It 'controller never scans IMAP messages' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'ImapOrOtherStoreMailRead=\$false'
    }
    It 'controller default WhatIf no Outlook access' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'WhatIfCapacityForecastNoOutlookAccessOrWrites'
    }
    It 'controller does not alter any registry' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Not -Match 'Set-ItemProperty|New-ItemProperty|Remove-ItemProperty'
    }
    It 'controller disallows Move Save Delete PST' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Not -Match '[.](Move|Save|Delete|Send|SetProperty|AddStoreEx|AddStore)[ ]*[(]'
    }
    It 'controller not ready for production' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'ProductionReady=\$false'
    }
    It 'controller leaves unknown 0x10000 blocked' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'OriginalSEM001Unknown0x00010000StillBlocked=\$true'
    }
    It 'controller no file/archive production' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7rPop3YearCapacityReview.ps1'); $s | Should -Match 'ArchivePstCreatedOrReplaced=\$false'
    }
}
