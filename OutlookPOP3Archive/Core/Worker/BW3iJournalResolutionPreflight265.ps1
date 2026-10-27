#requires -Version 5.1
# BW3i pure read-only preflight of existing LIVE6 reconciliation protocol.
# No permission, claim creation, journal append or Outlook Move.
function Get-OPA265BW3iPinnedScope {
    [CmdletBinding()]
    param()
    return (Get-OPA265BW3hPinnedChain)
}
function Assert-OPA265BW3iBw3hVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Verdict,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][string]$RecordPath)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $fields=@('Schema','Status','Decision','RunId','OperationId','WorkerRequestId',
        'OriginalIntentSha256','DestinationEntryId','ArchivedBodyUtf8Sha256',
        'AcceptanceRecordPath','AcceptanceRecordSha256',
        'SevenDurableEvidenceHashesVerified','OriginalIntentUnchanged',
        'WorkerDispatchClaimCorrelated','MoveAttemptClaimCorrelated',
        'WorkerDestinationIdentityConfirmed','SourceItemCount','ArchiveItemCount',
        'SyntheticAttachmentsCount','BodyBaselinePlusSpaceCrLfConfirmed',
        'IntentSizeBytes','ArchivedSizeBytes','ManuallyAcceptedSyntheticDifferenceBytes',
        'ManualSizeAcceptancePersisted','SizeDiscrepancyCauseEstablished',
        'BeforeMoveActualBodyHashAvailable','FullMAPIContentByteEqualityVerified',
        'JournalReconciliationAuthorized','JournalWritePermitIssued','JournalChanged',
        'JournalCompleted','JournalReconciled','OutlookMoveExecuted',
        'AutomaticRetryAllowed','ProductionReady','NextAction')
    if ($null -eq $Verdict -or $Verdict -is [string] -or $Verdict -is [array] -or
        @($Verdict.PSObject.Properties.Name).Count -ne $fields.Count) {
        throw 'BW3i requires the exact complete BW3h evidence object.'
    }
    foreach($name in $fields) {
        if ($Verdict.PSObject.Properties.Name -cnotcontains $name) {
            throw ('BW3i missing BW3h field: '+$name)
        }
    }
    if ([string]$Verdict.Schema -cne '2.6.5-BW3h.IndependentDurableEvidenceChainReadOnly.1' -or
        [string]$Verdict.Status -cne 'IndependentEvidenceChainVerifiedJournalDecisionPending' -or
        [string]$Verdict.Decision -cne 'StopBeforeSeparateExplicitJournalReconciliationAuthorization' -or
        [string]$Verdict.RunId -cne [string]$Pinned.RunId -or
        [string]$Verdict.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Verdict.WorkerRequestId -cne [string]$Pinned.WorkerRequestId -or
        [string]$Verdict.OriginalIntentSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Verdict.DestinationEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$Verdict.ArchivedBodyUtf8Sha256 -cne [string]$Pinned.BodyUtf8Sha256 -or
        [string]$Verdict.AcceptanceRecordPath -cne $RecordPath -or
        [string]$Verdict.AcceptanceRecordSha256 -cne [string]$Pinned.AcceptanceFileSha256 -or
        [int]$Verdict.SourceItemCount -ne 0 -or
        [int]$Verdict.ArchiveItemCount -ne 1 -or
        [int]$Verdict.SyntheticAttachmentsCount -ne 0 -or
        [long]$Verdict.IntentSizeBytes -ne 1436 -or
        [long]$Verdict.ArchivedSizeBytes -ne 1444 -or
        [long]$Verdict.ManuallyAcceptedSyntheticDifferenceBytes -ne 8 -or
        [string]$Verdict.NextAction -cne 'PreserveAllEvidenceAndRequireSeparateExplicitJournalDecision') {
        throw 'BW3i refuses altered synthetic BW3h evidence or size acceptance.'
    }
    foreach($name in @('SevenDurableEvidenceHashesVerified','OriginalIntentUnchanged',
        'WorkerDispatchClaimCorrelated','MoveAttemptClaimCorrelated',
        'WorkerDestinationIdentityConfirmed','BodyBaselinePlusSpaceCrLfConfirmed',
        'ManualSizeAcceptancePersisted')) {
        if ($Verdict.$name -isnot [bool] -or -not $Verdict.$name) {
            throw ('BW3i missing true BW3h evidence: '+$name)
        }
    }
    foreach($name in @('SizeDiscrepancyCauseEstablished','BeforeMoveActualBodyHashAvailable',
        'FullMAPIContentByteEqualityVerified','JournalReconciliationAuthorized',
        'JournalWritePermitIssued','JournalChanged','JournalCompleted',
        'JournalReconciled','OutlookMoveExecuted','AutomaticRetryAllowed',
        'ProductionReady')) {
        if ($Verdict.$name -isnot [bool] -or [bool]$Verdict.$name) {
            throw ('BW3i refuses forged BW3h permit or journal state: '+$name)
        }
    }
    return $true
}
function Assert-OPA265BW3iLive6Review {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $fields=@('Schema','RunId','OperationId','Status','Decision','CanExecute',
        'CanExecuteWithExplicitSizeConsent','CrossPstSizeDiffers',
        'IntentSizeBytes','ObservedArchiveSizeBytes','SizeDifferenceBytes',
        'ArchiveEntryId','ExpectedJournalSha256','JournalEventCount',
        'JournalUnchanged','JournalReconciled','JournalChangedByThisInvocation',
        'OutlookMoveExecuted','AutomaticRetryAllowed','ProductionReady')
    if ($null -eq $Review -or $Review -is [string] -or $Review -is [array] -or
        @($Review.PSObject.Properties.Name).Count -ne $fields.Count) {
        throw 'BW3i requires exact non-terminal LIVE6 Review-only schema.'
    }
    foreach($name in $fields) {
        if ($Review.PSObject.Properties.Name -cnotcontains $name) {
            throw ('BW3i missing LIVE6 review field: '+$name)
        }
    }
    if ([string]$Review.Schema -cne '2.6.4-LIVE6.JournalResolutionResult.1' -or
        [string]$Review.Status -cne 'ReviewOnly' -or
        [string]$Review.Decision -cne 'MoveConfirmed' -or
        [string]$Review.RunId -cne [string]$Pinned.RunId -or
        [string]$Review.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Review.ArchiveEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$Review.ExpectedJournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [long]$Review.IntentSizeBytes -ne 1436 -or
        [long]$Review.ObservedArchiveSizeBytes -ne 1444 -or
        [long]$Review.SizeDifferenceBytes -ne 8 -or
        [int]$Review.JournalEventCount -ne 1) {
        throw 'BW3i LIVE6 review does not match one outstanding exact synthetic Intent.'
    }
    foreach($name in @('CrossPstSizeDiffers','CanExecuteWithExplicitSizeConsent',
        'JournalUnchanged')) {
        if ($Review.$name -isnot [bool] -or -not $Review.$name) {
            throw ('BW3i expected evidence-only LIVE6 flag missing: '+$name)
        }
    }
    foreach($name in @('CanExecute','JournalReconciled',
        'JournalChangedByThisInvocation','OutlookMoveExecuted',
        'AutomaticRetryAllowed','ProductionReady')) {
        if ($Review.$name -isnot [bool] -or [bool]$Review.$name) {
            throw ('BW3i refuses unsafe LIVE6 state: '+$name)
        }
    }
    # LIVE6 CanExecuteWithExplicitSizeConsent is an existing TECHNICAL
    # capability indicator; never treat it as current operator consent.
    return $true
}
function Assert-OPA265BW3iResolutionClaimAbsent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths)
    $path=Get-OPA264Live6ClaimPath -Paths $Paths
    if ([IO.File]::Exists($path) -or [IO.Directory]::Exists($path) -or
        (Test-Path -LiteralPath $path)) {
        throw 'BW3i refuses existing LIVE6 resolution claim, including partial file. Never delete or retry.'
    }
    return $true
}
function Assert-OPA265BW3iIntentAppendPreconditions {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    [void](Assert-OPA265BW3iResolutionClaimAbsent -Paths $Paths)
    if (-not [IO.File]::Exists([string]$Paths.JournalPath) -or
        (([IO.File]::GetAttributes([string]$Paths.JournalPath)) -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3i expected original regular append-only Intent journal.'
    }
    $bytes=[IO.File]::ReadAllBytes([string]$Paths.JournalPath)
    if ($bytes.Length -lt 2 -or $bytes.Length -gt 1048576 -or
        $bytes[$bytes.Length-1] -ne 10) {
        throw 'BW3i original journal is truncated or not append-safe.'
    }
    $sha=Get-OPAOperationJournalSha256 -Bytes $bytes
    if ($sha -cne [string]$Pinned.JournalSha256) {
        throw 'BW3i original Intent journal changed before journal protocol preflight.'
    }
    $journal=Read-OPAOperationJournal -Path ([string]$Paths.JournalPath)
    if ([bool]$journal.TrailingPartial -or @($journal.Events).Count -ne 1) {
        throw 'BW3i requires one and only one complete original Intent.'
    }
    $evt=$journal.Events[0]
    if ([string]$evt.Phase -cne 'Intent' -or
        [string]$evt.OperationKind -cne 'MailMove' -or
        [long]$evt.Sequence -ne 1 -or
        [string]$evt.TransactionId -cne [string]$Pinned.RunId -or
        [string]$evt.OperationId -cne [string]$Pinned.OperationId -or
        [long]$evt.Size -ne 1436 -or
        [string]$evt.ArchivePst -cne [string]$Paths.ArchivePst -or
        [string]$Request.OperationId -cne [string]$Pinned.OperationId -or
        -not [string]::IsNullOrWhiteSpace([string]$evt.ArchiveEntryId)) {
        throw 'BW3i original Intent fields inconsistent with one-shot journal resolution.'
    }
    [void](Assert-OPA264Live5Journal -Request $Request -Paths $Paths -Journal $journal)
    return [pscustomobject]@{
        JournalSha256=$sha
        JournalEventCount=1
        IntentSequence=1
        IntentSizeBytes=1436L
        NextProtocolSequence=2
        ProposedNextPhase='Reconciled'
        Live6ResolutionClaimAbsent=$true
        JournalAppendEligibleByCurrentBytes=$true
        JournalAppendAuthorized=$false
    }
}
function Get-OPA265BW3iDecisionDossier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$Bw3h,
          [Parameter(Mandatory=$true)][object]$Live6Review,
          [Parameter(Mandatory=$true)][object]$JournalPreflight,
          [Parameter(Mandatory=$true)][object]$SnapshotBefore,
          [Parameter(Mandatory=$true)][object]$SnapshotAfter,
          [Parameter(Mandatory=$true)][string]$ExactRecordPath)
    [void](Assert-OPA265BW3iBw3hVerdict -Verdict $Bw3h -Pinned $Pinned -RecordPath $ExactRecordPath)
    [void](Assert-OPA265BW3iLive6Review -Review $Live6Review -Pinned $Pinned)
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $SnapshotBefore -After $SnapshotAfter -Pinned $Pinned)
    if ([string]$JournalPreflight.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [int]$JournalPreflight.JournalEventCount -ne 1 -or
        [int]$JournalPreflight.IntentSequence -ne 1 -or
        [long]$JournalPreflight.IntentSizeBytes -ne 1436 -or
        [int]$JournalPreflight.NextProtocolSequence -ne 2 -or
        [string]$JournalPreflight.ProposedNextPhase -cne 'Reconciled') {
        throw 'BW3i final journal preflight mismatched pinned original Intent.'
    }
    foreach($field in @('Live6ResolutionClaimAbsent','JournalAppendEligibleByCurrentBytes')) {
        if ($JournalPreflight.$field -isnot [bool] -or -not $JournalPreflight.$field) {
            throw ('BW3i final dossier missing journal preflight proof '+$field)
        }
    }
    if ($JournalPreflight.JournalAppendAuthorized -isnot [bool] -or
        [bool]$JournalPreflight.JournalAppendAuthorized) {
        throw 'BW3i forbids equating technical journal preflight with consent.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3i.JournalResolutionReadOnlyPreflight.1'
        Status='JournalResolutionEvidenceReadySeparateAuthorizationRequired'
        Decision='DoNotAppendReconciledWithoutNewExplicitUserAuthorization'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        JournalSha256=[string]$Pinned.JournalSha256
        AcceptanceRecordSha256=[string]$Pinned.AcceptanceFileSha256
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        SevenDurableEvidenceHashesUnchanged=$true
        SingleUnresolvedIntentConfirmed=$true
        CurrentJournalEventCount=1
        ProtocolNextSequence=2
        ProposedNextPhase='Reconciled'
        Live6ResolutionClaimAbsent=$true
        LegacyLive6ProtocolReadOnlyReviewed=$true
        LegacyLive6CanExecuteWithExplicitSizeConsent=$true
        LegacyLive6CanExecuteWithoutSizeConsent=$false
        IntentSizeBytes=1436L
        ArchiveSizeBytes=1444L
        ManuallyAcceptedSyntheticSizeDifferenceBytes=8L
        ManualSizeAcceptanceRecordVerified=$true
        FullMAPIContentByteEqualityVerified=$false
        SizeDifferenceRootCauseEstablished=$false
        OperatorJournalAuthorizationGiven=$false
        WriteableJournalPermitIssued=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='RequestSeparateExplicitOneRunJournalAppendDecisionAfterIndependentSafetyReview'
    }
}
