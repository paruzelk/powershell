#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7sInventoryRegistryPolicy265.ps1')
    function New-BW4k7sProbe {
        param([string]$Kind='Policy',[long]$Max=-1,[long]$Warn=-1,
              [string]$MaxKind='DWord',[string]$WarnKind='DWord',[bool]$Ansi=$false)
        $v=[ordered]@{}
        foreach($n in @('MaxLargeFileSize','WarnLargeFileSize','MaxFileSize','WarnFileSize')){
            $num=if($n -eq 'MaxLargeFileSize'){$Max}
                 elseif($n -eq 'WarnLargeFileSize'){$Warn}
                 elseif($Ansi -and $n -eq 'MaxFileSize'){2075149312}
                 elseif($Ansi -and $n -eq 'WarnFileSize'){1950368768}
                 else{-1}
            $present=$num -ge 0
            $valueKind=if(-not $present){'NotConfigured'}
                  elseif($n -eq 'MaxLargeFileSize'){$MaxKind}
                  elseif($n -eq 'WarnLargeFileSize'){$WarnKind}
                  else{'DWord'}
            $v[$n]=[pscustomobject]@{
                Present=$present
                RegistryValueKind=$valueKind
                DecimalDwordValue=if($present -and $valueKind -eq 'DWord'){$num}else{$null}
            }
        }
        return [pscustomobject]@{Kind=$Kind;Values=[pscustomobject]$v;RegistryKeyExists=$true}
    }
    function Get-BW4k7sLimits {
        param([psobject]$Policy,[psobject]$User,[long]$Target=45000000000)
        if($null -eq $Policy){$Policy=New-BW4k7sProbe -Kind Policy}
        if($null -eq $User){$User=New-BW4k7sProbe -Kind User}
        return (Get-OPA265BW4k7sPstLimitDecision -PolicyProbe $Policy -UserProbe $User -PlannedMaxArchivePstBytes $Target)
    }
    function New-BW4k7sFullYearEvidence {
        $yrs=New-Object 'System.Collections.Generic.List[object]'
        $counts=[ordered]@{'2020'=3744;'2021'=3598;'2022'=3515;'2023'=2752;'2024'=4252;'2025'=4124;'2026'=4617}
        foreach($year in $counts.Keys){
            $y=[int]$year
            $yrs.Add([pscustomobject]@{
                Year=$y;InboxMailItems=[long]$counts[$year]
                SentItemsMailItems=0L;UserFolderMailItems=0L
                TotalMailItems=[long]$counts[$year]
                ArchiveYearEligible=($y -lt 2026)
                Coverage='FullyEnumeratedObservedMetadata'
                NoArchiveFileCreated=$true
            })
        }
        return [pscustomobject]@{
            Schema='2.6.5-BW4k7r.Pop3YearDistributionCapacityReadOnly.1'
            Status='FullObservedPOP3YearDistributionReadOnlyCapacityForecastOnly'
            YearDistributionComplete=$true
            AllCandidateItemsEnumerated=$true
            ScopeCandidateItemsTotal=26605L;CandidateItemsExamined=26605L
            MailItemsDated=26602L;MailItemsObserved=26602L
            MailItemsUndated=0L;NonMailItemsObserved=3L
            SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
            ArchiveBeforeYear=2026;YearDistribution=@($yrs.ToArray())
            MailMovedOrDeleted=$false;WriterPermit=$false;ProductionReady=$false
            OriginalSEM001Unknown0x00010000StillBlocked=$true
        }
    }
    function Test-BW4k7sFullYear {
        param([psobject]$Evidence)
        if($null -eq $Evidence){$Evidence=New-BW4k7sFullYearEvidence}
        return (Assert-OPA265BW4k7sPriorYearInventory -Inventory $Evidence -ExpectedScopeCandidateItems 26605 -ExpectedSourcePst 'C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst')
    }
}
Describe 'BW4k7s unmodified non-MailItem witnesses, PST registry and original full-year reconciliation' {
    It 'olMail Class 43 documented' {
        Get-OPA265BW4k7sObjectClassName -ClassCode 43 | Should -BeExactly 'olMail'
    }
    It 'olMeetingRequest Class 53 documented' {
        Get-OPA265BW4k7sObjectClassName -ClassCode 53 | Should -BeExactly 'olMeetingRequest'
    }
    It 'olMeetingCancellation Class 54 documented' {
        Get-OPA265BW4k7sObjectClassName -ClassCode 54 | Should -BeExactly 'olMeetingCancellation'
    }
    It 'olMeetingResponsePositive Class 56 documented' {
        Get-OPA265BW4k7sObjectClassName -ClassCode 56 | Should -BeExactly 'olMeetingResponsePositive'
    }
    It 'olReport Class 46 documented' {
        Get-OPA265BW4k7sObjectClassName -ClassCode 46 | Should -BeExactly 'olReport'
    }
    It 'olPost Class 45 documented' {
        Get-OPA265BW4k7sObjectClassName -ClassCode 45 | Should -BeExactly 'olPost'
    }
    It 'olSharing Class 104 documented' {
        Get-OPA265BW4k7sObjectClassName -ClassCode 104 | Should -BeExactly 'olSharing'
    }
    It 'unknown Class is not presumed safe' {
        Get-OPA265BW4k7sObjectClassName -ClassCode 999 | Should -BeExactly 'UnknownOlObjectClass'
    }
    It 'nonmail witness captures exact class 53' {
        $w=New-OPA265BW4k7sNonMailWitness -ClassCode 53 -EntryId id1 -FolderEntryId fid -MessageClass 'IPM.Schedule.Meeting.Request' -MessageClassObservation Read; $w.Class | Should -Be 53; $w.MessageClass | Should -BeExactly 'IPM.Schedule.Meeting.Request'
    }
    It 'nonmail witness has exact EntryID' {
        $w=New-OPA265BW4k7sNonMailWitness -ClassCode 46 -EntryId e123 -FolderEntryId f123; $w.EntryId | Should -BeExactly 'e123'; $w.FolderEntryId | Should -BeExactly 'f123'
    }
    It 'nonmail cannot be auto deleted' {
        (New-OPA265BW4k7sNonMailWitness -ClassCode 53 -EntryId e -FolderEntryId f).CanAutomaticallyDeleteSkipOrMove | Should -BeFalse
    }
    It 'nonmail potentially contains user data' {
        (New-OPA265BW4k7sNonMailWitness -ClassCode 53 -EntryId e -FolderEntryId f).MayContainUserData | Should -BeTrue
    }
    It 'nonmail requires manual preservation' {
        (New-OPA265BW4k7sNonMailWitness -ClassCode 46 -EntryId e -FolderEntryId f).RequiresManualPreservationDecision | Should -BeTrue
    }
    It 'nonmail does not read content or attachment bytes' {
        (New-OPA265BW4k7sNonMailWitness -ClassCode 45 -EntryId e -FolderEntryId f).MessageBodyOrAttachmentPayloadRead | Should -BeFalse
    }
    It 'unknown message class clearly NotAvailable' {
        (New-OPA265BW4k7sNonMailWitness -ClassCode 45 -EntryId e -FolderEntryId f).MessageClassObservation | Should -BeExactly 'NotAvailable'
    }
    It 'mail Class 43 cannot be passed as nonmail' {
        {New-OPA265BW4k7sNonMailWitness -ClassCode 43 -EntryId e -FolderEntryId f} | Should -Throw
    }
    It 'empty EntryID rejected' {
        {New-OPA265BW4k7sNonMailWitness -ClassCode 46 -EntryId '' -FolderEntryId f} | Should -Throw
    }
    It 'empty folder ID rejected' {
        {New-OPA265BW4k7sNonMailWitness -ClassCode 46 -EntryId e -FolderEntryId ''} | Should -Throw
    }
    It 'fake Read with no MessageClass rejected' {
        {New-OPA265BW4k7sNonMailWitness -ClassCode 46 -EntryId e -FolderEntryId f -MessageClassObservation Read} | Should -Throw
    }
    It 'default registry limits not machine verified' {
        (Get-BW4k7sLimits).Status | Should -BeExactly 'MicrosoftDocumentedDefaultsAssumedNotMachineVerified'
    }
    It 'default maximum 51200 MiB' {
        (Get-BW4k7sLimits).AssumedMicrosoftDefaultMaxLargeFileSizeMiB | Should -Be 51200
    }
    It 'default warning 48640 MiB' {
        (Get-BW4k7sLimits).AssumedMicrosoftDefaultWarnLargeFileSizeMiB | Should -Be 48640
    }
    It 'no registry values gives unverified configured pair' {
        (Get-BW4k7sLimits).EffectiveConfiguredPairFound | Should -BeFalse
    }
    It 'default source is explicitly assumed' {
        (Get-BW4k7sLimits).DefaultPstLimitOnlyAssumed | Should -BeTrue
    }
    It 'user full pair 50000 47000 read as configured' {
        $r=Get-BW4k7sLimits -User (New-BW4k7sProbe -Kind User -Max 50000 -Warn 47000); $r.Source | Should -BeExactly 'User'; $r.EffectiveConfiguredPairFound | Should -BeTrue
    }
    It 'user full pair compatible 45e9 forecast' {
        $r=Get-BW4k7sLimits -User (New-BW4k7sProbe -Kind User -Max 50000 -Warn 47000); $r.Status | Should -BeExactly 'ConfiguredUnicodePstLimitCompatibleForecastOnly'
    }
    It 'policy full pair wins over user' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 51200 -Warn 48640) -User (New-BW4k7sProbe -Kind User -Max 50000 -Warn 47000); $r.Source | Should -BeExactly 'Policy'; $r.EffectiveMaxLargeFileSizeMiB | Should -Be 51200
    }
    It 'policy partial is blocked even if user full' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 51200) -User (New-BW4k7sProbe -Kind User -Max 50000 -Warn 47000); $r.Status | Should -BeExactly 'PartialRegistryOverrideNeedsManualReview'
    }
    It 'user partial pair never deemed complete' {
        $r=Get-BW4k7sLimits -User (New-BW4k7sProbe -Kind User -Max 51200); $r.EffectiveConfiguredPairFound | Should -BeFalse
    }
    It 'policy non DWord detected' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 51200 -Warn 48640 -MaxKind String); $r.Status | Should -BeExactly 'InvalidRegistryValueKindNeedsManualReview'
    }
    It 'warning zero is blocked' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 51200 -Warn 0); $r.Status | Should -BeExactly 'RegistryLimitsOutsideConservativeRangeNeedsReview'
    }
    It 'warn larger than max blocked' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 40000 -Warn 41000); $r.Status | Should -BeExactly 'RegistryLimitsOutsideConservativeRangeNeedsReview'
    }
    It 'warn separation under 5 percent blocked' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 50000 -Warn 49000); $r.Status | Should -BeExactly 'RegistryLimitsOutsideConservativeRangeNeedsReview'
    }
    It 'over documented 51200 requires review' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 60000 -Warn 57000); $r.Status | Should -BeExactly 'RegistryLimitsOutsideConservativeRangeNeedsReview'
    }
    It 'planned forecast over warning blocks' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 30000 -Warn 28000); $r.Status | Should -BeExactly 'PlannedPstExceedsReadOnlyWarnLimitBlocked'
    }
    It 'default includes 45e9 but no permission' {
        $r=Get-BW4k7sLimits; $r.WriterPermit | Should -BeFalse; $r.ProductionReady | Should -BeFalse
    }
    It 'configured limits do not grant writer' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 51200 -Warn 48640); $r.WriterPermit | Should -BeFalse; $r.ProductionReady | Should -BeFalse
    }
    It 'configured limits do not establish Unicode format' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 51200 -Warn 48640); $r.CurrentPstUnicodeFormatVerified | Should -BeFalse
    }
    It 'configured limits do not establish physical PST growth' {
        $r=Get-BW4k7sLimits -Policy (New-BW4k7sProbe -Kind Policy -Max 51200 -Warn 48640); $r.CapacityProvenForRealPstWrites | Should -BeFalse
    }
    It 'no unlimited PST limit modification' {
        (Get-BW4k7sLimits).UnlimitedPstSizeEnabled | Should -BeFalse
    }
    It 'no registry write performed' {
        (Get-BW4k7sLimits).RegistryModified | Should -BeFalse
    }
    It 'wrong registry probe kinds rejected' {
        {Get-OPA265BW4k7sPstLimitDecision -PolicyProbe (New-BW4k7sProbe -Kind User) -UserProbe (New-BW4k7sProbe -Kind Policy)} | Should -Throw
    }
    It 'margin >= maximum blocks' {
        {Get-OPA265BW4k7sPstLimitDecision -PolicyProbe (New-BW4k7sProbe -Kind Policy) -UserProbe (New-BW4k7sProbe -Kind User) -PlannedMaxArchivePstBytes 104857600 -PlannedSafetyMarginBytes 104857600} | Should -Throw
    }
    It 'original BW4k7r 26602+3 counts validate' {
        (Test-BW4k7sFullYear).AllObservedMailItems | Should -Be 26602
    }
    It 'original BW4k7r six eligible years' {
        @( (Test-BW4k7sFullYear).EligibleArchiveYears ).Count | Should -Be 6
    }
    It 'original BW4k7r 21985 eligible mails' {
        (Test-BW4k7sFullYear).EligibleArchiveMailItems | Should -Be 21985
    }
    It 'original 2026 not eligible in six-year plan' {
        $r=Test-BW4k7sFullYear; @($r.EligibleArchiveYears | Where-Object {$_.Year -eq 2026}).Count | Should -Be 0
    }
    It 'original input is unsealed not physical guarantee' {
        (Test-BW4k7sFullYear).CryptographicallyBoundToCurrentPst | Should -BeFalse
    }
    It 'missing original evidence not automatically fabricated' {
        $e=New-BW4k7sFullYearEvidence; $e.YearDistributionComplete=$false; {Test-BW4k7sFullYear -Evidence $e} | Should -Throw
    }
    It 'original partial candidate count rejected' {
        $e=New-BW4k7sFullYearEvidence; $e.CandidateItemsExamined=5000; {Test-BW4k7sFullYear -Evidence $e} | Should -Throw
    }
    It 'other POP3 PST path rejected' {
        $e=New-BW4k7sFullYearEvidence; $e.SourcePst='C:\other.pst'; {Test-BW4k7sFullYear -Evidence $e} | Should -Throw
    }
    It 'forged previous writer permit rejected' {
        $e=New-BW4k7sFullYearEvidence; $e.WriterPermit=$true; {Test-BW4k7sFullYear -Evidence $e} | Should -Throw
    }
    It 'original year totals with unaccounted nonmail rejected' {
        $e=New-BW4k7sFullYearEvidence; $e.NonMailItemsObserved=2; {Test-BW4k7sFullYear -Evidence $e} | Should -Throw
    }
    It 'duplicate year in source rejected' {
        $e=New-BW4k7sFullYearEvidence; $e.YearDistribution[1].Year=2020; {Test-BW4k7sFullYear -Evidence $e} | Should -Throw
    }
    It 'source year 2026 incorrectly archived rejected' {
        $e=New-BW4k7sFullYearEvidence; $e.YearDistribution[6].ArchiveYearEligible=$true; {Test-BW4k7sFullYear -Evidence $e} | Should -Throw
    }
    It 'controller reads original Q verified source only' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Match 'Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1'
    }
    It 'controller skips original LIVE3 test folders' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Match 'TestFolderOrDescendant'
    }
    It 'controller uses StoreID for folder lookup' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Match 'GetFolderFromID'
    }
    It 'controller rechecks source scope at end' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); ([regex]::Matches($s,'Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1')).Count | Should -Be 2
    }
    It 'controller does not read item bodies' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Not -Match '[.]Body|[.]HTMLBody|[.]Attachments'
    }
    It 'controller does not modify PST files' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Not -Match '[.](Move|Save|Delete|SetProperty|AddStoreEx|AddStore)[ ]*[(]'
    }
    It 'controller does not write registry' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Not -Match 'Set-ItemProperty|New-ItemProperty|Remove-ItemProperty'
    }
    It 'controller WhatIf no external reads' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Match 'WhatIfNoOutlookOrRegistryReadNoWriter'
    }
    It 'controller preserves BW4k7o SEM-001' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Match 'OriginalSEM001Unknown0x00010000StillBlocked'
    }
    It 'controller still not production' {
        $s=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7sPop3InventoryReadinessReview.ps1'); $s | Should -Match 'ProductionReady=\$false'
    }
}
