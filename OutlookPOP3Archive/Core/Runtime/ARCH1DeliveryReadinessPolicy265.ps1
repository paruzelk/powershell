#requires -Version 5.1
# ARCH1 audit: source-code evidence only. Not a runtime/Outlook/PST validation.
function Test-OPA265ARCH1DeliveryReadiness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence)
    foreach($name in @('EntryPoint','Mover','Verifier','Grouping','Planner',
        'Journal','DuplicateIndex','SystemFolders','Release')){
        if($null -eq $Evidence.PSObject.Properties[$name] -or
           $null -eq $Evidence.$name){
            throw ('ARCH1 missing evidence: '+$name)
        }
    }
    $release=$Evidence.Release
    if($null -eq $release.Integration -or
       $null -eq $release.Verification){
        throw 'ARCH1 RELEASE.json integration/verification metadata missing.'
    }
    $checks=New-Object 'System.Collections.Generic.List[object]'
    function Add-OPA265ARCH1Row {
        param([string]$Area,[string]$State,[string]$Proof,[string]$Next)
        $checks.Add([pscustomobject][ordered]@{
            Area=$Area;State=$State;ObservedEvidence=$Proof;NextAction=$Next
        })
    }
    $entry=[string]$Evidence.EntryPoint
    $mover=[string]$Evidence.Mover
    $verifier=[string]$Evidence.Verifier
    $group=[string]$Evidence.Grouping
    $planner=[string]$Evidence.Planner
    $journal=[string]$Evidence.Journal
    $dup=[string]$Evidence.DuplicateIndex
    $sys=[string]$Evidence.SystemFolders
    $entryMove=($entry.Contains('Move-OPAItemsWithLimit') -and
        $entry.Contains("'Archive'"))
    $year=($group.Contains("function Get-OPAArchiveGroupParts") -and
        $group.Contains("'Year'"))
    $folders=($planner.Contains('Get-OPAEligiblePop3MailFolders') -and
        $sys.Contains('Outbox'))
    $journalExists=$journal.Contains('Write-OPAOperationJournalEvent')
    $duplicate=$dup.Contains('Test-OPADuplicateEntry')
    $hasMove=$mover.Contains('$item.Move(')
    $hasCopy=$mover.Contains('$item.Copy(')
    $skipOnMoveError=($mover.Contains("Reason='MoveFailed'") -and
        $mover.Contains('continue'))
    $fullSemantic=(($verifier.Contains('HTMLBody')) -and
        ($verifier.Contains('Attachments')) -and
        ($verifier.Contains('Body')))
    $integrated=([bool]$release.Integration.ArchiveWorkerEnabled -and
        [bool]$release.Integration.ResumeWorkerEnabled)
    if($entryMove){Add-OPA265ARCH1Row 'DirectArchiveEntrypoint' 'PresentNotCertified' 'Existing Archive mode calls Move-OPAItemsWithLimit' 'Do not run on 90GB source until guarded end-to-end validation.'}
    else{Add-OPA265ARCH1Row 'DirectArchiveEntrypoint' 'RequiresManualAudit' 'Expected entrypoint marker absent' 'Inspect CLI dispatch.'}
    if($hasMove -and -not $hasCopy){
        Add-OPA265ARCH1Row 'LegacyMover' 'PresentDirectMoveNotCertified' 'MailMover contains item.Move but no item.Copy' 'Assess Copy/Verify/Delete as an OPTION, never treat it as inherently atomic.'}
    else{Add-OPA265ARCH1Row 'LegacyMover' 'RequiresManualAudit' 'Mover patterns changed' 'Re-audit actual mutation and reconciliation sequence.'}
    if($skipOnMoveError){Add-OPA265ARCH1Row 'AmbiguousMoveFailure' 'CriticalGap' 'Legacy mover catches MoveFailed and continues' 'Prove ambiguous COM outcome is fenced and reconciled before any retry/resume.'}
    else{Add-OPA265ARCH1Row 'AmbiguousMoveFailure' 'NeedsProof' 'No legacy skip pattern found' 'Prove crash/timeout/COM-unknown handling using a controlled test.'}
    if($fullSemantic){Add-OPA265ARCH1Row 'ArchiveVerifier' 'MarkersPresentNotVerified' 'Body, HTMLBody, Attachments marker strings present' 'Validate byte SHA and all mandatory fields in end-to-end tests.'}
    else{Add-OPA265ARCH1Row 'ArchiveVerifier' 'CriticalGap' 'Legacy ArchiveVerifier has no complete Body/HTMLBody/Attachments checks' 'Integrate existing BW4k semantic witness and byte-SHA attachment comparison.'}
    if($year){Add-OPA265ARCH1Row 'YearGrouping' 'ImplementedInSourceNotIntegrated' 'Year grouping exists in ArchiveGrouping' 'Verify -ArchiveGrouping Year at CLI and year/part PST names.'}
    else{Add-OPA265ARCH1Row 'YearGrouping' 'MissingOrUnknown' 'Year grouping marker absent' 'Implement/test archive grouping by year.'}
    if($folders){Add-OPA265ARCH1Row 'FolderScope' 'ImplementedInSourceNotIntegrated' 'Planner enumerator and Outbox exclusion markers exist' 'Prove Inbox/Sent/user folders and exclusions in POP3 scope.'}
    else{Add-OPA265ARCH1Row 'FolderScope' 'NeedsAudit' 'Planner or Outbox marker absent' 'Confirm strict POP3-only folder selection.'}
    if($journalExists -and $duplicate){
        Add-OPA265ARCH1Row 'JournalAndDuplicates' 'ImplementedInSourceNotProven' 'Operation journal and duplicate index modules exist' 'Prove restart/resume and no-blind-retry on real disposable PST.'}
    else{Add-OPA265ARCH1Row 'JournalAndDuplicates' 'MissingOrUnknown' 'Journal/index marker absent' 'Restore recovery protocol and tests.'}
    if(-not $integrated){
        Add-OPA265ARCH1Row 'WorkerIntegration' 'Disabled' 'RELEASE Integration.ArchiveWorkerEnabled/ResumeWorkerEnabled not both true' 'Do not infer disabling the legacy direct Archive path; review both separately.'}
    else{Add-OPA265ARCH1Row 'WorkerIntegration' 'DeclaredEnabledUnproven' 'RELEASE integration switches true' 'Prove actual invocation; switch alone is no runtime evidence.'}
    $critical=($skipOnMoveError -or -not $fullSemantic -or -not $integrated)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH1.StaticDeliveryAudit.1'
        Status='ExistingArchiveCodePresentProductionUncertified'
        EvidenceKind='StaticSourceMarkersOnly'
        SourceMarkerEvidenceIsNotRuntimeCertification=$true
        DirectArchiveEntrypointPresent=$entryMove
        LegacyDirectMovePresent=$hasMove
        CopyThenVerifyDeleteIntegrated=$false
        LegacyMoveFailureContinuePatternDetected=$skipOnMoveError
        LegacyVerifierIncludesFullBodyHtmlAttachmentWitness=$fullSemantic
        YearGroupingPresentInSource=$year
        Pop3FolderScopeMarkersPresent=$folders
        JournalAndDuplicateModulesPresent=($journalExists -and $duplicate)
        ArchiveWorkerIntegrationSwitchesEnabled=$integrated
        DirectArchiveModeNotAutomaticallyBlockedByWorkerSwitches=$true
        CriticalGapsDetected=$critical
        RequiredOriginalMessageContentAndAttachmentShaValidation=$true
        NewMapiSizeOrFlagForensicsAuthorizedByThisBuild=$false
        PreviousLiveMoveClaimsMayBeRetried=$false
        SafeFor90GBProductionArchive=$false
        AuditRows=@($checks.ToArray())
        WriterPermit=$false
        ProductionReady=$false
    }
}
