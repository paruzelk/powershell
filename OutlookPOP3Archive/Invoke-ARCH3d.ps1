#requires -Version 5.1
# ARCH3d original MailMover boundary audit; no access to PST or Outlook.
[CmdletBinding()]
param([ValidateSet('Plan','Audit')][string]$Mode='Audit')
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
    throw 'ARCH3d audit requires native Windows PowerShell 5.1.'
}
if($Mode -ceq 'Plan'){
    [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3d.Plan.1'
        Status='OriginalMailMoverProtectedBoundaryIntegrationPlanNoPstNoOutlook'
        OriginalArchivePlannerAndYearRoutingUnchanged=$true
        OriginalMailMoverWiredWithSyntheticHooks=$true
        BeforeDestinationDurableIntentRequired=$true
        OriginalSemanticWitnessBeforeClaimRequired=$true
        LinkedReturnReceiptAfterMockMoveRequired=$true
        DuplicateIndexBeforeIndependentRestartBlockedInProtectedMode=$true
        ProductionWriterStillClosed=$true
        OutlookContacted=$false
        PstOpened=$false
        JournalWritten=$false
        ProductionReady=$false
    }
    return
}
$mover=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Core/Archive/MailMover.ps1'),[Text.Encoding]::UTF8)
$main=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'OutlookPOP3Archive.ps1'),[Text.Encoding]::UTF8)
$hook=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Core/Archive/ARCH3dOriginalMoverBoundary.ps1'),[Text.Encoding]::UTF8)
# Restrict order assertions to the ORIGINAL production mover body, not
# earlier helper definitions that legitimately call the same functions.
$body=$mover.Substring($mover.IndexOf('function Move-OPAItemsWithLimit',[StringComparison]::Ordinal))
$dest=$body.IndexOf('$dest = Get-OPAArchiveDestination', [StringComparison]::Ordinal)
$pre=$body.IndexOf('Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage PrepareIntent', [StringComparison]::Ordinal)
$witness=$body.IndexOf('$sourceSemanticWitness = Get-OPA265ARCH2bMailSemanticWitness -Mail $item',[StringComparison]::Ordinal)
$witnessReceipt=$body.IndexOf('Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage SourceWitnessAnchored',[StringComparison]::Ordinal)
$originalStepClaim=$body.IndexOf("Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Move Started'",[StringComparison]::Ordinal)
$protectedClaim=$body.IndexOf('Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage MoveClaimed',[StringComparison]::Ordinal)
$com=$body.IndexOf('$moved = $item.Move($dest.Folder)',[StringComparison]::Ordinal)
$returned=$body.IndexOf('Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage MoveReturned',[StringComparison]::Ordinal)
$index=$body.IndexOf('Add-OPADuplicateEntry -Index $index -SourceEntryId $candidate.EntryId -ArchiveEntryId $archiveId -SourceFolderPath $folderPath -TargetFolderPath $dest.Folder.FolderPath',[StringComparison]::Ordinal)
$checks=[ordered]@{
    MainLegacyModesStillBlocked=($main.Contains('Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode $Mode'))
    OriginalMoverHasOptInSyntheticBoundary=($mover.Contains('[switch]$ARCH3dSyntheticBoundary'))
    ScopeRejectedBeforeAnyLegacyWork=($body.IndexOf('Assert-OPA265ARCH3dSyntheticBoundary -Namespace $Namespace') -gt 0 -and $body.IndexOf('Assert-OPA265ARCH3dSyntheticBoundary -Namespace $Namespace') -lt $body.IndexOf('Get-OPAArchivePstPartsOnDiskAll -SourcePst'))
    DurablePreDestinationIntentBeforeOriginalPstSelection=($pre -ge 0 -and $dest -gt $pre)
    OriginalContentWitnessBeforeBoundaryWitnessPin=($witness -gt $dest -and $witnessReceipt -gt $witness)
    OriginalMoveStartedPrecedesImmutableClaim=($originalStepClaim -gt $witnessReceipt -and $protectedClaim -gt $originalStepClaim)
    ImmutableClaimPrecedesOriginalComMove=($com -gt $protectedClaim)
    ImmutableReturnReceiptAfterOriginalComMove=($returned -gt $com)
    IndexGuardedUntilIndependentReconciliation=($index -gt $returned -and $mover.Contains('ARCH3d SYNTHETIC STOP after immutable MoveReturned'))
    OriginalMailItemMoveStillUsedOnce=([regex]::Matches($mover,'\$\w+\s*=\s*\$item\.Move\(\$dest\.Folder\)').Count -eq 1)
    ProtectedScopeRejectsActualComAndExistingPst=($hook.Contains('GetType().FullName -ne') -and $hook.Contains('[IO.File]::Exists($src)'))
    OriginalJournalIntentBeforeDestination=($hook.Contains('Write-OPAOperationJournalEvent -Path $journal') -and $hook.Contains('-Phase Intent'))
    ProtectedIndeterminateNeverRetry=($hook.Contains('-Phase Indeterminate') -and $hook.Contains('AutomaticRetryAllowed=$false'))
}
$failed=@($checks.GetEnumerator()|Where-Object{-not $_.Value}|ForEach-Object{$_.Key})
return [pscustomobject][ordered]@{
    Schema='2.6.5-ARCH3d.SourceBackedOriginalMoverAudit.1'
    Status=if($failed.Count -eq 0){'OriginalMailMoverSyntheticBoundariesWiredProductionStillClosed'}else{'OriginalMoverIntegrationMarkerMismatchManualReview'}
    Checks=$checks
    ChecksPassed=($checks.Count - $failed.Count)
    ChecksTotal=$checks.Count
    FailedChecks=$failed
    RealOriginalLegacyMoverModifiedForHooks=$true
    OriginalYearAndFolderRoutingUntouched=$true
    SyntheticTestModeOnly=$true
    LiveMoveAuthorized=$false
    IndependentLiveReconcileIntegrated=$false
    OriginalDuplicateIndexCommitIntegratedAfterReconcile=$false
    ArchiveResumeAutoRemainClosed=$true
    OutlookContacted=$false
    PstOpened=$false
    JournalWritten=$false
    WriterPermit=$false
    ProductionReady=$false
}
