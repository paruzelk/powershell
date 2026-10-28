#requires -Version 5.1
# BW3m: independent final SECURITY REVIEW. No original journal writer exists.
# Read-only historical evidence + read-only inspection of BW3l's TEMP byte copy.
function Assert-OPA265BW3mBw3lReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $fields=@('Schema','Status','Decision','RunId','OperationId',
        'OriginalIntentSha256','AcceptanceRecordSha256','DestinationEntryId',
        'SandboxDirectory','SandboxCopyFinalSha256','IndependentBW3jReviewPassed',
        'HistoricalSevenHashesUnchanged','CopyContainsOriginalExactBytes',
        'CopyReconciled','CopyJournalEventCount','CopyDurableClaimCreated',
        'HistoricalJournalEventCount','HistoricalJournalPhase',
        'HistoricalResolutionClaimCreated','HistoricalJournalChanged',
        'HistoricalJournalReconciled','HistoricalJournalWritePermitIssued',
        'OutlookMoveExecuted','AutomaticRetryAllowed','ProductionReady','NextAction')
    if ($null -eq $Review -or $Review -is [array] -or
        $Review -is [string] -or @($Review.PSObject.Properties.Name).Count -ne $fields.Count) {
        throw 'BW3m refuses incomplete/extra BW3l result.'
    }
    foreach($f in $fields) {
        if ($Review.PSObject.Properties.Name -cnotcontains $f) {throw ('BW3m missing BW3l field '+$f)}
    }
    if ([string]$Review.Schema -cne '2.6.5-BW3l.HistoricalByteCopyRehearsalReadOnlyOriginal.1' -or
        [string]$Review.Status -cne 'HistoricalJournalCopyRehearsalVerifiedOriginalUntouched' -or
        [string]$Review.Decision -cne 'DoNotWriteHistoricalJournalWithoutNewSeparateExplicitAuthorization' -or
        [string]$Review.RunId -cne [string]$Pinned.RunId -or
        [string]$Review.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Review.OriginalIntentSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Review.AcceptanceRecordSha256 -cne [string]$Pinned.AcceptanceFileSha256 -or
        [string]$Review.DestinationEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$Review.SandboxCopyFinalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Review.SandboxCopyFinalSha256 -ceq [string]$Pinned.JournalSha256 -or
        [int]$Review.CopyJournalEventCount -ne 2 -or
        [int]$Review.HistoricalJournalEventCount -ne 1 -or
        [string]$Review.HistoricalJournalPhase -cne 'Intent' -or
        [string]$Review.NextAction -cne 'ReviewBW3ScopedWriterSecurityAndObtainSeparateExactRunJournalAuthorization') {
        throw 'BW3m rejects wrong pinned scope, original journal state, or copy result.'
    }
    foreach($f in @('IndependentBW3jReviewPassed','HistoricalSevenHashesUnchanged',
        'CopyContainsOriginalExactBytes','CopyReconciled','CopyDurableClaimCreated')) {
        if ($Review.$f -isnot [bool] -or -not $Review.$f) {
            throw ('BW3m refuses false/untyped copy evidence '+$f)
        }
    }
    foreach($f in @('HistoricalResolutionClaimCreated','HistoricalJournalChanged',
        'HistoricalJournalReconciled','HistoricalJournalWritePermitIssued',
        'OutlookMoveExecuted','AutomaticRetryAllowed','ProductionReady')) {
        if ($Review.$f -isnot [bool] -or $Review.$f) {
            throw ('BW3m refuses granted original journal authority '+$f)
        }
    }
    [void](Get-OPA265BW3lCopyPaths -Directory ([string]$Review.SandboxDirectory))
    return $true
}
function Assert-OPA265BW3mCopyReadback {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][byte[]]$OriginalBytes,
          [switch]$OfflineReplicaForTests)
    [void](Assert-OPA265BW3mBw3lReview -Review $Review -Pinned $Pinned)
    $paths=Get-OPA265BW3lCopyPaths -Directory ([string]$Review.SandboxDirectory)
    $m=Read-OPA265BW3lCopyMarker -Paths $paths -Pinned $Pinned
    $expectedCopySha=if($OfflineReplicaForTests){
        Get-OPAOperationJournalSha256 -Bytes $OriginalBytes
    }else{
        [string]$Pinned.JournalSha256
    }
    if (($OfflineReplicaForTests -and [string]$m.Mode -cne 'OfflineReplicaNotHistoricalProof') -or
        (-not $OfflineReplicaForTests -and [string]$m.Mode -cne 'ActualHistoricalByteCopy') -or
        [string]$m.OriginalIntentSha256 -cne $expectedCopySha) {
        throw 'BW3m copy marker provenance/hash does not match independently read bytes.'
    }
    [void](Assert-OPA265BW3lRegular -Path $paths.JournalPath)
    [void](Assert-OPA265BW3lRegular -Path $paths.ClaimPath)
    $claim=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($paths.ClaimPath)) -ErrorAction Stop
    $claimFields=@('Schema','RunId','OperationId','CopyOriginalSha256','DestinationEntryId',
        'Scope','HistoricJournalWriteAuthorized','AutomaticRetryAllowed','ProductionReady')
    if (@($claim.PSObject.Properties.Name).Count -ne $claimFields.Count) {
        throw 'BW3m refuses forged/partial TEMP copy claim.'
    }
    foreach($f in $claimFields) {
        if ($claim.PSObject.Properties.Name -cnotcontains $f) {throw ('BW3m missing TEMP claim '+$f)}
    }
    if ([string]$claim.Schema -cne '2.6.5-BW3l.CopyOnlyResolutionClaim.1' -or
        [string]$claim.RunId -cne [string]$Pinned.RunId -or
        [string]$claim.OperationId -cne [string]$Pinned.OperationId -or
        [string]$claim.CopyOriginalSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$claim.DestinationEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$claim.Scope -cne 'OS-TEMP-COPY-ONLY-NOT-ORIGINAL') {
        throw 'BW3m TEMP claim scope/identity differs from historical BW3a.'
    }
    foreach($f in @('HistoricJournalWriteAuthorized','AutomaticRetryAllowed','ProductionReady')) {
        if ($claim.$f -isnot [bool] -or $claim.$f) {
            throw ('BW3m TEMP claim elevates original journal permissions '+$f)
        }
    }
    $old=Assert-OPA265BW3lOneIntent -Bytes $OriginalBytes -Pinned $Pinned -ExpectedSha256 $expectedCopySha
    $copyBytes=[IO.File]::ReadAllBytes([string]$paths.JournalPath)
    $copyHash=Get-OPAOperationJournalSha256 -Bytes $copyBytes
    if ($copyHash -cne [string]$Review.SandboxCopyFinalSha256 -or
        $copyBytes.Length -le $OriginalBytes.Length) {
        throw 'BW3m copied journal SHA256/length differs from completed BW3l result.'
    }
    for($n=0;$n -lt $OriginalBytes.Length;$n++) {
        if($copyBytes[$n] -ne $OriginalBytes[$n]) {
            throw 'BW3m original one-Intent byte prefix was altered inside the copy.'
        }
    }
    $journal=Read-OPAOperationJournal -Path $paths.JournalPath
    if ([bool]$journal.TrailingPartial -or @($journal.Events).Count -ne 2) {
        throw 'BW3m copy must contain exactly two complete journal records.'
    }
    $first=$journal.Events[0];$last=$journal.Events[1]
    if ([string]$first.Phase -cne 'Intent' -or
        [string]$first.TransactionId -cne [string]$Pinned.RunId -or
        [string]$first.OperationId -cne [string]$Pinned.OperationId -or
        [string]$first.SourceEntryId -cne [string]$old.SourceEntryId -or
        [string]$first.ArchivePst -cne [string]$old.ArchivePst -or
        [string]$last.SchemaVersion -cne '1.0' -or
        [string]$last.Phase -cne 'Reconciled' -or
        [string]$last.OperationKind -cne 'MailMove' -or
        [long]$last.Sequence -ne 2 -or
        [string]$last.TransactionId -cne [string]$Pinned.RunId -or
        [string]$last.OperationId -cne [string]$Pinned.OperationId -or
        [string]$last.ArchiveEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$last.ArchivePst -cne [string]$old.ArchivePst -or
        [string]$last.SourceEntryId -cne [string]$old.SourceEntryId -or
        [string]$last.SourceStoreId -cne [string]$old.SourceStoreId -or
        [string]$last.SourceFolderPath -cne [string]$old.SourceFolderPath -or
        [string]$last.TargetFolderPath -cne [string]$old.TargetFolderPath -or
        [string]$last.InternetMessageId -cne [string]$old.InternetMessageId -or
        [string]$last.Subject -cne [string]$old.Subject -or
        [string]$last.Sender -cne [string]$old.Sender -or
        [long]$last.Size -ne 1436 -or
        [string]$last.Message -cne 'BW3l COPY-ONLY rehearsal; +8 synthetic size acceptance is not journal authorization') {
        throw 'BW3m copy terminal event changed original fields or expected destination.'
    }
    $replay=Resolve-OPAOperationRecovery -Journal $journal
    if ([string]$replay.TransactionId -cne [string]$Pinned.RunId -or
        [long]$replay.LastSequence -ne 2 -or
        @($replay.Indeterminate).Count -ne 0 -or
        @($replay.Resolved).Count -ne 1 -or
        [string]$replay.Resolved[0].Status -cne 'Reconciled' -or
        [string]$replay.Resolved[0].ArchiveEntryId -cne [string]$Pinned.DestinationEntryId) {
        throw 'BW3m copy terminal replay did not resolve exact one historical-shaped operation.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3m.IndependentCopyReadback.1'
        SandboxDirectory=[string]$paths.Directory
        CopyFinalSha256=$copyHash
        CopyMode=[string]$m.Mode
        OriginalIntentBytePrefixPreserved=$true
        ClaimScopeCopyOnlyVerified=$true
        TwoJournalEventsReplayVerified=$true
        HistoricalJournalWriteAuthorized=$false
        ProductionReady=$false
    }
}
function Get-OPA265BW3mSecurityDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$Bw3l,
          [Parameter(Mandatory=$true)][object]$CopyAudit,
          [Parameter(Mandatory=$true)][object]$EvidenceBefore,
          [Parameter(Mandatory=$true)][object]$EvidenceAfter)
    [void](Assert-OPA265BW3mBw3lReview -Review $Bw3l -Pinned $Pinned)
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $EvidenceBefore -After $EvidenceAfter -Pinned $Pinned)
    if ([string]$CopyAudit.Schema -cne '2.6.5-BW3m.IndependentCopyReadback.1' -or
        [string]$CopyAudit.SandboxDirectory -cne [string]$Bw3l.SandboxDirectory -or
        [string]$CopyAudit.CopyFinalSha256 -cne [string]$Bw3l.SandboxCopyFinalSha256 -or
        [string]$CopyAudit.CopyMode -cne 'ActualHistoricalByteCopy' -or
        $CopyAudit.OriginalIntentBytePrefixPreserved -isnot [bool] -or
        -not $CopyAudit.OriginalIntentBytePrefixPreserved -or
        $CopyAudit.ClaimScopeCopyOnlyVerified -isnot [bool] -or
        -not $CopyAudit.ClaimScopeCopyOnlyVerified -or
        $CopyAudit.TwoJournalEventsReplayVerified -isnot [bool] -or
        -not $CopyAudit.TwoJournalEventsReplayVerified -or
        $CopyAudit.HistoricalJournalWriteAuthorized -isnot [bool] -or
        $CopyAudit.HistoricalJournalWriteAuthorized -or
        $CopyAudit.ProductionReady -isnot [bool] -or
        $CopyAudit.ProductionReady) {
        throw 'BW3m copy readback is untrusted/does not match BW3l source evidence.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3m.HistoricalJournalWriterSecurityReview.1'
        Status='HistoricalBW3ScopedWriterSecurityReviewedOriginalStillUnresolved'
        Decision='NoHistoricalWriteExecutorOrPermitInBW3mSeparateAuthorizationStillRequired'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        OriginalIntentSha256=[string]$Pinned.JournalSha256
        AcceptanceRecordSha256=[string]$Pinned.AcceptanceFileSha256
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        SandboxDirectory=[string]$Bw3l.SandboxDirectory
        SandboxCopyFinalSha256=[string]$CopyAudit.CopyFinalSha256
        IndependentBW3jAuditPassed=$true
        IndependentBW3lCopyRehearsalPassed=$true
        IndependentBW3mCopyReadbackPassed=$true
        SevenHistoricalEvidenceHashesUnchanged=$true
        OriginalIntentBytePrefixPreserved=$true
        CopyReconciled=$true
        HistoricalJournalEventCount=1
        HistoricalJournalPhase='Intent'
        HypotheticalNextJournalSequence=2
        HypotheticalNextJournalPhase='Reconciled'
        SingleSyntheticEightByteAcceptanceVerified=$true
        SizeDriftCauseEstablished=$false
        FullMAPIContentByteEqualityVerified=$false
        HistoricalClaimCreated=$false
        HistoricalJournalChanged=$false
        HistoricalJournalReconciled=$false
        HistoricalJournalWriterImplemented=$false
        HistoricalWriterExecutionRouteEnabled=$false
        HistoricalJournalWritePermitIssued=$false
        CreateNewClaimRequiredForFutureWriter=$true
        ExclusiveLockWithFreshShaRequiredForFutureWriter=$true
        RevalidateSevenEvidenceHashesBeforeWriteRequired=$true
        CrashAfterClaimBeforeAppendRequiresManualStop=$true
        CrashAfterAppendBeforeVerificationRequiresManualStop=$true
        SeparateExactRunExplicitUserAuthorizationRequired=$true
        AutomaticRetryAllowed=$false
        OutlookMoveExecuted=$false
        ProductionReady=$false
        NextAction='SeparateSecurityApprovalAndExplicitOneRunJournalDecisionBeforeOriginalWriterCanBeBuilt'
    }
}
