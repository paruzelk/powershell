#requires -Version 5.1
# ARCH3k: live source-backed ORIGINAL MailMover boundary audit.
# Read-only. Existing PrepareIntent is immutable, no PST/Journal/Index writes.
# Deliberately no writer, MoveClaimed, AddStoreEx, Resume, or retry mode.
. (Join-Path $PSScriptRoot 'ARCH3jRealOneShotPrepareIntent.ps1')

function Assert-OPA265ARCH3kPinnedPreparation {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$IntentSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256)
    if($RunId -cne '9d276dc4-a0e6-4e74-891f-81502fafe7db' -or
       $IntentSha256 -cne 'f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b' -or
       $JournalSha256 -cne 'a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'){
        throw 'ARCH3k requires exact operator-confirmed ARCH3j RunId, Intent SHA and Original Journal SHA.'
    }
    $layout=Get-OPA265ARCH3jLayout -RunId $RunId
    $review=Test-OPA265ARCH3jPreparedIntent -Layout $layout -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    if(-not [bool]$review.OriginalOperationJournalIntentWritten -or
       [bool]$review.MoveClaimed -or [bool]$review.LiveMovePerformed -or
       [bool]$review.WriterPermit){
        throw 'ARCH3k only accepts untouched original Intent, no writer claim.'
    }
    $intent=Read-OPA265ARCH3cPinnedJson -Path ([string]$layout.IntentPath) -ExpectedSha256 $IntentSha256
    if([string]$intent.RunId -cne $RunId -or
       [string]$intent.SourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00' -or
       [string]$intent.FullOriginalWitnessSha256 -cne '8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c' -or
       [string]$intent.SourceSealRunId -cne '3773bcd7-5a07-4c31-8ce5-dfb16ddd30bf' -or
       [string]$intent.SourceSealSha256 -cne '5f5a86b6c1aba8a3d2ee328a36a5632f8edf1e89fdda8e7fd728688fe881b2a4' -or
       [string]$intent.PlannedTargetFolderPath -cne '2020\Входящие' -or
       [long]$intent.ExistingArchivePart1LengthBytes -ne 271360 -or
       -not [bool]$intent.OriginalSharedIndexReadOnlyApproved){
        throw 'ARCH3k Prepared original MailMover destination/source evidence inconsistent.'
    }
    $sealed=Get-OPA265ARCH3jSealedSource -SealRunId ([string]$intent.SourceSealRunId) -SealSha256 ([string]$intent.SourceSealSha256
    )
    if([string]$sealed.SourceEntryId -cne [string]$intent.SourceEntryId -or
       [string]$sealed.OriginalWitnessSha256 -cne [string]$intent.FullOriginalWitnessSha256 -or
       [string]$sealed.SourceFolderEntryId -cne [string]$intent.SourceFolderEntryId -or
       [string]$sealed.SourceStoreIdSha256 -cne [string]$intent.SourceStoreIdSha256){
        throw 'ARCH3k independent original ARCH3i source semantic seal changed.'
    }
    return [pscustomobject]@{Layout=$layout;Intent=$intent;Sealed=$sealed;Review=$review}
}

function Get-OPA265ARCH3kOriginalMoverUnsafeDefaultMarkers {
    [CmdletBinding()]
    param()
    $path=Join-Path $PSScriptRoot 'MailMover.ps1'
    $source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $sourceSha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $route=($source -match 'Get-OPAArchiveDestination -Namespace' -and
        $source -match '\$states = @\(\$states \| Sort-Object Part -Descending\)' -and
        $source -match 'if \(\(\$size \+ \$estimatedPhysicalGrowth\) -le \$safeBytes\)')
    $index=($source -match 'Sync-OPADuplicateIndexFromJournal -Transaction' -and
        $source -match 'Add-OPADuplicateEntry -Index')
    $move=($source -match '\$moved = \$item\.Move\(\$dest\.Folder\)')
    $synthetic=($source -match 'ARCH3dSyntheticBoundary' -and
        $source -match 'Assert-OPA265ARCH3dSyntheticBoundary')
    if(-not $route -or -not $index -or -not $move -or -not $synthetic){
        throw 'ARCH3k original MailMover source contract changed. Inspect manually before any writer.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3k.OriginalMoverStaticBoundary.1'
        OriginalMailMoverSha256=$sourceSha
        ExistingPartSelectedWhenCapacityAllows=$true
        GenericMoverUsesOriginalGetArchiveDestination=$true
        GenericMoverMayAppendToExistingYearPart1=$true
        GenericMoverHealsSharedDuplicateIndexBeforeMove=$true
        GenericMoverAppendsSharedDuplicateIndexBeforeIndependentRestart=$true
        ProtectedARCH3dBoundaryIsSyntheticOnly=$true
        DirectGenericMoverSafeForPinnedPart2=$false
        RealSingleMoveRequiresDedicatedIsolatedOriginalBoundary=$true
        WriterPermit=$false
    }
}

function Invoke-OPA265ARCH3kLiveReadOnlyBoundary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Plan','Audit')][string]$Mode,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$IntentSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256)
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3k requires Windows PowerShell 5.1.'
    }
    $p=Assert-OPA265ARCH3kPinnedPreparation -RunId $RunId -IntentSha256 $IntentSha256 -JournalSha256 $JournalSha256
    $risk=Get-OPA265ARCH3kOriginalMoverUnsafeDefaultMarkers
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3k.Plan.1'
            Status='PreparedOriginalRealMoverRiskGateNoOutlookOrWrites'
            RunId=$RunId
            OriginalWitnessSha256=[string]$p.Sealed.OriginalWitnessSha256
            SourceEntryId=[string]$p.Sealed.SourceEntryId
            ExistingPart1=[string]$p.Intent.ExistingArchivePart1
            ProtectedFuturePart2=[string]$p.Intent.NewArchivePst
            OriginalMailMoverSha256=$risk.OriginalMailMoverSha256
            GenericMoverPart1AndIndexRiskDetected=$true
            LiveMovePerformed=$false
            OutlookContacted=$false
            WriterPermit=$false
            ProductionReady=$false
        }
    }
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3k real read-only Audit requires Windows PowerShell 5.1 -STA.'
    }
    $session=$null;$mail=$null;$parent=$null
    try{
        $layout=Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst ([string]$p.Sealed.SourcePst)
        if(-not [bool]$session.Scope.Approved){throw 'ARCH3k exact real POP3 scope rejected.'}
        $storeId=[string]$session.SourceStore.StoreID
        if((Get-OPA265ARCH2bTextSha256 -Text $storeId) -cne [string]$p.Sealed.SourceStoreIdSha256){
            throw 'ARCH3k source StoreId drifted since ARCH3i.'
        }
        $mail=$session.Namespace.GetItemFromID([string]$p.Sealed.SourceEntryId,$storeId)
        if($null -eq $mail -or [int]$mail.Class -ne 43 -or
           [string]$mail.EntryID -cne [string]$p.Sealed.SourceEntryId){
            throw 'ARCH3k exact original MailItem not found.'
        }
        $parent=$mail.Parent
        if($null -eq $parent -or
           [string]$parent.EntryID -cne [string]$p.Sealed.SourceFolderEntryId -or
           [string]$parent.EntryID -cne [string]$session.Inbox.EntryID -or
           [string]$parent.StoreID -cne $storeId -or
           [string]$parent.FolderPath -cne '\\info@stios.ru\Входящие'){
            throw 'ARCH3k original MailItem not in exact POP3 Inbox.'
        }
        $date=Get-OPAArchiveItemDate -Item $mail
        if($null -eq $date -or ([datetime]$date).Ticks -ne [long]$p.Sealed.ArchiveDateLocalTicks){
            throw 'ARCH3k original archive date drift.'
        }
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
        [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $w -ExpectedOriginalWitnessSha256 ([string]$p.Sealed.OriginalWitnessSha256))
        $contract=Get-OPA265ARCH3jOriginalRoutePlan -Sealed $p.Sealed -RunId $RunId -SourceStoreId $storeId
        if([string]$contract.OperationId -cne [string]$p.Intent.OperationId -or
           [string]$contract.ContractSha256 -cne [string]$p.Intent.OriginalContractSha256 -or
           [string]$contract.PlannedArchivePst -cne [string]$p.Intent.NewArchivePst -or
           [string]$contract.PlannedTargetFolderPath -cne '2020\Входящие' -or
           [string]$contract.SourceFolderPath -cne [string]$parent.FolderPath){
            throw 'ARCH3k original Year Part2 route changed since PrepareIntent.'
        }
        $index=Get-OPA265ARCH3jIndexSafety -Part1 ([string]$p.Intent.ExistingArchivePart1) -SourceEntryId ([string]$p.Sealed.SourceEntryId)
        if(-not [bool]$index.Approved){throw ('ARCH3k original shared index blocks live writer: '+[string]$index.Reason)}
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3k.LiveReadOnlyBoundary.1'
            Status='ExactOriginalPOP3SemanticAndPart2RevalidatedMassWriterStillBlocked'
            RunId=$RunId
            SourceEntryId=[string]$p.Sealed.SourceEntryId
            FullWitnessSha256=[string]$p.Sealed.OriginalWitnessSha256
            OriginalContractSha256=[string]$contract.ContractSha256
            OriginalMailMoverSha256=$risk.OriginalMailMoverSha256
            Part1=[string]$p.Intent.ExistingArchivePart1
            Part1SizeBytes=[long]$p.Sealed.ExistingArchivePart1LengthBytes
            Part2Preview=[string]$contract.PlannedArchivePst
            OriginalSharedIndexReadOnly=$true
            OriginalIndexEntryCount=[int]$index.EntryCount
            GenericMoverPart1RiskDetected=$true
            OriginalDuplicateIndexPreverificationMutationDetected=$true
            OutlookProcessId=[int]$session.OutlookProcessId
            OutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            PrepareIntentUnmodified=$true
            MoveClaimed=$false
            LiveMovePerformed=$false
            WriterPermit=$false
            ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $parent
        Release-OPA265ARCH2c4Com -Object $mail
        Close-OPA265ARCH2dSession -Session $session
    }
}
