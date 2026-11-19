#requires -Version 5.1
# ARCH3n — bridge previously sealed real ARCH3j Intent to original ARCH3m
# synthetic preallocation. Read-only for real files. Never a writer permit.
. (Join-Path $PSScriptRoot 'ARCH3kOriginalMoverLiveBarrier.ps1')

function Get-OPA265ARCH3nPinnedRealRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$IntentSha256,
        [Parameter(Mandatory=$true)][string]$JournalSha256
    )
    if($RunId -cne '9d276dc4-a0e6-4e74-891f-81502fafe7db' -or
       $IntentSha256 -cne 'f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b' -or
       $JournalSha256 -cne 'a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'){
        throw 'ARCH3n refuses non-operator-pinned real test PST Intent/Journal identity.'
    }
    # ARCH3k reads ORIGINAL ARCH3j PrepareIntent and original OperationJournal
    # with their externally pinned hashes AND independent full ARCH3i witness.
    $p=Assert-OPA265ARCH3kPinnedPreparation -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst ([string]$p.Sealed.SourcePst) -RequireExisting
    $part1=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 1
    $part2=Get-OPAArchivePartPath -SourcePst $source -Year 2020 -Part 2
    $date=[datetime]::new([long]$p.Sealed.ArchiveDateLocalTicks)
    $target=Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderName 'Входящие' -SourceFolderPath '\\info@stios.ru\Входящие' -Grouping Year
    Clear-OPAArchivePartCache -SourcePst $source
    $parts=@(Get-OPAArchivePstPartsOnDisk -SourcePst $source -Year 2020)
    if($parts.Count -ne 1 -or [int]$parts[0].Part -ne 1 -or [int]$parts[0].Year -ne 2020 -or
       -not [string]::Equals([string]$parts[0].Path,$part1,[StringComparison]::OrdinalIgnoreCase) -or
       -not [IO.File]::Exists($part1) -or
       [long]([IO.FileInfo]::new($part1)).Length -ne 271360 -or
       [IO.File]::Exists($part2) -or [IO.Directory]::Exists($part2) -or
       $target -cne '2020\Входящие' -or
       [string]$p.Intent.ExistingArchivePart1 -cne $part1 -or
       [string]$p.Intent.NewArchivePst -cne $part2 -or
       [string]$p.Intent.PlannedTargetFolderPath -cne $target -or
       [string]$p.Intent.OriginalContractSha256 -cne '2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88' -or
       [string]$p.Intent.FullOriginalWitnessSha256 -cne [string]$p.Sealed.OriginalWitnessSha256 -or
       [string]$p.Intent.SourceEntryId -cne [string]$p.Sealed.SourceEntryId -or
       [string]$p.Intent.SourceStoreIdSha256 -cne [string]$p.Sealed.SourceStoreIdSha256 -or
       [string]$p.Intent.SourceFolderEntryId -cne [string]$p.Sealed.SourceFolderEntryId -or
       [bool]$p.Intent.MoveClaimed -or [bool]$p.Intent.LiveMovePerformed -or
       [bool]$p.Intent.WriterPermit){
        throw 'ARCH3n original pinned real Part1/Part2/witness/contract topology changed. STOP.'
    }
    if((([IO.File]::GetAttributes($part1)) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'ARCH3n Part1 reparse point unsafe.'
    }
    $idx=Get-OPA265ARCH3jIndexSafety -Part1 $part1 -SourceEntryId ([string]$p.Intent.SourceEntryId)
    if(-not [bool]$idx.Approved -or [int]$idx.EntryCount -ne 500){
        throw 'ARCH3n original shared DuplicateIndex no longer exactly matches 500-entry read-only pilot.'
    }
    $mover=Get-OPA265ARCH3kOriginalMoverUnsafeDefaultMarkers
    $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'MailMover.ps1') -Raw -Encoding UTF8
    if($text -cnotmatch 'ARCH3mSyntheticForcePart2' -or
       $text -cnotmatch 'Assert-OPA265ARCH3mSyntheticPreAllocation' -or
       $text -cnotmatch 'if\(-not \$ARCH3lSyntheticPart2Boundary\)' -or
       $text -cnotmatch 'ARCH3d SYNTHETIC STOP'){
        throw 'ARCH3n original MailMover ARCH3m synthetic anti-Part1 boundaries missing.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3n.PinnedRealIntentReadOnlyRoute.1'
        Status='OriginalRealIntentAndForcedPart2SyntheticBridgeReadyNoLiveWriter'
        RunId=$RunId
        IntentSha256=$IntentSha256
        JournalSha256=$JournalSha256
        SourceSealRunId=[string]$p.Intent.SourceSealRunId
        SourceSealSha256=[string]$p.Intent.SourceSealSha256
        SourceEntryId=[string]$p.Sealed.SourceEntryId
        SourceStoreIdSha256=[string]$p.Sealed.SourceStoreIdSha256
        SourceFolderEntryId=[string]$p.Sealed.SourceFolderEntryId
        OriginalWitnessSha256=[string]$p.Sealed.OriginalWitnessSha256
        OriginalContractSha256=[string]$p.Intent.OriginalContractSha256
        OriginalOperationId=[string]$p.Intent.OperationId
        RealSourcePst=$source
        ExistingPart1=$part1
        ExistingPart1LengthBytes=[long]271360
        UnusedPart2=$part2
        OriginalTargetFolder=$target
        OriginalSharedIndexEntryCount=[int]$idx.EntryCount
        OriginalMailMoverSha256=[string]$mover.OriginalMailMoverSha256
        PreparedOriginalJournalIntentVerified=$true
        FullOriginalWitnessVerified=$true
        OriginalDuplicateIndexReadOnly=$true
        RealPart2OpenedOrCreated=$false
        RealPstWritten=$false
        MoveClaimed=$false
        AutomaticMoveRetryAllowed=$false
        SyntheticOnly=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Assert-OPA265ARCH3nSyntheticRealIntentBridge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$RealPlan,
        [Parameter(Mandatory=$true)][object]$SyntheticPreAllocation,
        [Parameter(Mandatory=$true)][object]$SyntheticCandidate
    )
    # RealPlan is *only* a read-only projection of original pinned evidence,
    # not a permit. The destination selector revalidates fake ARCH3m scope
    # separately before New-OPAArchivePst can be mocked in the test.
    if([string]$RealPlan.Schema -cne '2.6.5-ARCH3n.PinnedRealIntentReadOnlyRoute.1' -or
       [string]$RealPlan.Status -cne 'OriginalRealIntentAndForcedPart2SyntheticBridgeReadyNoLiveWriter' -or
       [string]$RealPlan.RunId -cne '9d276dc4-a0e6-4e74-891f-81502fafe7db' -or
       [string]$RealPlan.IntentSha256 -cne 'f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b' -or
       [string]$RealPlan.JournalSha256 -cne 'a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e' -or
       [string]$RealPlan.SourceSealSha256 -cne '5f5a86b6c1aba8a3d2ee328a36a5632f8edf1e89fdda8e7fd728688fe881b2a4' -or
       [string]$RealPlan.OriginalWitnessSha256 -cne '8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c' -or
       [string]$RealPlan.OriginalContractSha256 -cne '2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88' -or
       [string]$RealPlan.SourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00' -or
       [string]$RealPlan.OriginalTargetFolder -cne '2020\Входящие' -or
       [long]$RealPlan.ExistingPart1LengthBytes -ne 271360 -or
       [int]$RealPlan.OriginalSharedIndexEntryCount -ne 500 -or
       [string]$SyntheticPreAllocation.Schema -cne '2.6.5-ARCH3m.OriginalSyntheticPart2PreAllocation.1' -or
       [string]$SyntheticPreAllocation.Status -cne 'OriginalPart2SelectedBeforeAnyArchiveStoreOpen' -or
       -not [bool]$SyntheticPreAllocation.SyntheticOnly -or
       [bool]$SyntheticPreAllocation.WriterPermit -or
       [bool]$SyntheticPreAllocation.PSTCreatedByGate -or
       [bool]$SyntheticPreAllocation.ExistingPart1OpenedByGate -or
       [string]$SyntheticPreAllocation.FolderPath -cne [string]$RealPlan.OriginalTargetFolder -or
       [int]$SyntheticPreAllocation.Part -ne 2 -or
       [string]$SyntheticCandidate.EntryID -cne [string]$RealPlan.SourceEntryId -or
       [datetime]$SyntheticCandidate.ArchiveDate -lt [datetime]'2020-01-01' -or
       [datetime]$SyntheticCandidate.ArchiveDate -ge [datetime]'2021-01-01' -or
       [bool]$RealPlan.WriterPermit -or [bool]$RealPlan.ProductionReady -or
       [bool]$RealPlan.MoveClaimed -or [bool]$RealPlan.RealPart2OpenedOrCreated -or
       -not [bool]$RealPlan.PreparedOriginalJournalIntentVerified -or
       -not [bool]$RealPlan.FullOriginalWitnessVerified -or
       -not [bool]$RealPlan.OriginalDuplicateIndexReadOnly){
        throw 'ARCH3n synthetic original Part2 cannot be mapped to the pinned real ARCH3j Intent.'
    }
    $realPart2=[IO.Path]::GetFileName([string]$RealPlan.UnusedPart2)
    $fakePart2=[IO.Path]::GetFileName([string]$SyntheticPreAllocation.ForcedPart2)
    $realPart1=[IO.Path]::GetFileName([string]$RealPlan.ExistingPart1)
    $fakePart1=[IO.Path]::GetFileName([string]$SyntheticPreAllocation.OriginalPart1)
    if($realPart2 -cne 'info@stios.ru.Archive-2020-02.pst' -or
       $fakePart2 -cne $realPart2 -or
       $realPart1 -cne 'info@stios.ru.Archive-2020.pst' -or
       $fakePart1 -cne $realPart1 -or
       [string]::Equals([IO.Path]::GetFullPath([string]$SyntheticPreAllocation.ForcedPart2),
                         [IO.Path]::GetFullPath([string]$RealPlan.UnusedPart2),
                         [StringComparison]::OrdinalIgnoreCase)){
        throw 'ARCH3n real and fake Year2020 archive topology not identical and isolated.'
    }
    # No persisted capability token. Only a report for tests/read-only audit.
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3n.OriginalSyntheticToRealIntentBridge.1'
        Status='OriginalYearPart2AndFullRealIntentBridgeSyntheticOnlyNoWriter'
        RunId=[string]$RealPlan.RunId
        RealOriginalIntentSha256=[string]$RealPlan.IntentSha256
        RealOriginalJournalSha256=[string]$RealPlan.JournalSha256
        OriginalWitnessSha256=[string]$RealPlan.OriginalWitnessSha256
        OriginalContractSha256=[string]$RealPlan.OriginalContractSha256
        RealPart2=[string]$RealPlan.UnusedPart2
        SyntheticPart2=[string]$SyntheticPreAllocation.ForcedPart2
        OriginalSourceEntryId=[string]$SyntheticCandidate.EntryID
        RealOutlookContacted=$false
        SyntheticOnly=$true
        RealPstWritten=$false
        MoveClaimed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3nReadOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Audit')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$IntentSha256,
        [Parameter(Mandatory=$true)][string]$JournalSha256
    )
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3n requires Windows PowerShell 5.1.'
    }
    $bound=Get-OPA265ARCH3nPinnedRealRoute -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    if($Mode -ceq 'Plan'){return $bound}
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3n live read-only Audit requires -STA.'
    }
    $live=Invoke-OPA265ARCH3kLiveReadOnlyBoundary -Mode Audit -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    if([string]$live.Status -cne 'ExactOriginalPOP3SemanticAndPart2RevalidatedMassWriterStillBlocked' -or
       [string]$live.RunId -cne $RunId -or
       [string]$live.SourceEntryId -cne [string]$bound.SourceEntryId -or
       [string]$live.FullWitnessSha256 -cne [string]$bound.OriginalWitnessSha256 -or
       [string]$live.OriginalContractSha256 -cne [string]$bound.OriginalContractSha256 -or
       [string]$live.Part1 -cne [string]$bound.ExistingPart1 -or
       [string]$live.Part2Preview -cne [string]$bound.UnusedPart2 -or
       [int]$live.OriginalIndexEntryCount -ne [int]$bound.OriginalSharedIndexEntryCount -or
       [bool]$live.WriterPermit -or [bool]$live.LiveMovePerformed){
        throw 'ARCH3n independent real Outlook read-only check diverged from original pinned real Intent.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3n.LiveReadOnlyIntentBridge.1'
        Status='ExactSealedRealOriginalIntentPart2AndLiveOutlookSourceLinkedNoMove'
        RunId=$RunId
        SourceEntryId=[string]$bound.SourceEntryId
        SourceSealSha256=[string]$bound.SourceSealSha256
        OriginalWitnessSha256=[string]$bound.OriginalWitnessSha256
        IntentSha256=$IntentSha256
        JournalSha256=$JournalSha256
        OriginalContractSha256=[string]$bound.OriginalContractSha256
        ExistingPart1=[string]$bound.ExistingPart1
        UnusedPart2=[string]$bound.UnusedPart2
        OriginalTargetFolder=[string]$bound.OriginalTargetFolder
        OriginalIndexEntryCount=[int]$bound.OriginalSharedIndexEntryCount
        OutlookProcessId=[int]$live.OutlookProcessId
        OutlookProcessStartUtcTicks=[long]$live.OutlookProcessStartUtcTicks
        OriginalMailMoverSHA256=[string]$bound.OriginalMailMoverSha256
        OriginalJournalIntentIndependentlyVerified=$true
        RealSourceSemanticWitnessVerified=$true
        RealPstWritten=$false
        MoveClaimed=$false
        LiveMovePerformed=$false
        AutomaticMoveRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
