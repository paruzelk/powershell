#requires -Version 5.1
# BW3j: read-only, one historical BW3a operation. NO writer or journal permit.
function Get-OPA265BW3jFutureClaimPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    if ([string]$Paths.RunId -cne [string]$Pinned.RunId -or
        [string]$Paths.SourcePst -cne [string]$Pinned.SourcePst -or
        -not [IO.Directory]::Exists([string]$Paths.Directory) -or
        (([IO.File]::GetAttributes([string]$Paths.Directory)) -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3j rejects foreign or reparse-point synthetic fixture.'
    }
    return (Join-Path ([string]$Paths.Directory) 'bw3j-resolution.claim')
}
function Assert-OPA265BW3jResolutionClaimSlotsAbsent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Pinned)
    $future=Get-OPA265BW3jFutureClaimPath -Paths $Paths -Pinned $Pinned
    $legacy=Join-Path ([string]$Paths.Directory) 'live6-resolution.claim'
    foreach($name in @($future,$legacy)) {
        if ([IO.File]::Exists($name) -or [IO.Directory]::Exists($name) -or
            (Test-Path -LiteralPath $name)) {
            throw ('BW3j STOP existing or partial resolution claim: '+[IO.Path]::GetFileName($name))
        }
    }
    return $true
}
function Assert-OPA265BW3jOriginalIntent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    [void](Assert-OPA265BW3jResolutionClaimSlotsAbsent -Paths $Paths -Pinned $Pinned)
    if (-not [IO.File]::Exists([string]$Paths.JournalPath) -or
        (([IO.File]::GetAttributes([string]$Paths.JournalPath)) -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3j original Intent must be a regular file.'
    }
    $bytes=[IO.File]::ReadAllBytes([string]$Paths.JournalPath)
    if ($bytes.Length -lt 2 -or $bytes.Length -gt 1048576 -or
        $bytes[$bytes.Length-1] -ne 10) {
        throw 'BW3j original journal truncated or outside single-Intent bounds.'
    }
    $sha=Get-OPAOperationJournalSha256 -Bytes $bytes
    if ($sha -cne [string]$Pinned.JournalSha256) {
        throw 'BW3j original journal bytes changed.'
    }
    $j=Read-OPAOperationJournal -Path ([string]$Paths.JournalPath)
    if ([bool]$j.TrailingPartial -or @($j.Events).Count -ne 1) {
        throw 'BW3j requires exactly one unresolved Intent, no duplicates or terminal event.'
    }
    $e=$j.Events[0]
    if ([string]$e.Phase -cne 'Intent' -or
        [string]$e.OperationKind -cne 'MailMove' -or
        [long]$e.Sequence -ne 1 -or
        [string]$e.TransactionId -cne [string]$Pinned.RunId -or
        [string]$e.OperationId -cne [string]$Pinned.OperationId -or
        [string]$e.ArchivePst -cne [string]$Paths.ArchivePst -or
        [string]$e.SourceEntryId -cne [string]$Request.SourceEntryId -or
        [string]$e.SourceStoreId -cne [string]$Request.SourceStoreId -or
        [string]$e.SourceFolderPath -cne [string]$Request.SourceFolderPath -or
        [string]$e.TargetFolderPath -cne [string]$Request.ArchiveFolderPath -or
        [string]$e.InternetMessageId -cne ('<opa264-live3-'+[string]$Pinned.RunId+'@example.invalid>') -or
        [string]$e.Subject -cne ('OPA264 LIVE3 synthetic '+[string]$Pinned.RunId) -or
        [long]$e.Size -ne 1436 -or
        -not [string]::IsNullOrEmpty([string]$e.ArchiveEntryId) -or
        [string]$Request.RunId -cne [string]$Pinned.RunId -or
        [string]$Request.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Request.SourcePst -cne [string]$Pinned.SourcePst -or
        [string]$Request.ArchivePst -cne [string]$Paths.ArchivePst) {
        throw 'BW3j one-shot original Intent and fixture request mismatch.'
    }
    $replay=Resolve-OPAOperationRecovery -Journal $j
    if ([string]$replay.TransactionId -cne [string]$Pinned.RunId -or
        @($replay.Indeterminate).Count -ne 1 -or
        @($replay.Resolved).Count -ne 0 -or
        $replay.BlockAutomaticRetry -isnot [bool] -or -not $replay.BlockAutomaticRetry -or
        $replay.RequiresPstReconciliation -isnot [bool] -or -not $replay.RequiresPstReconciliation) {
        throw 'BW3j original journal replay does not preserve unresolved Intent fence.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3j.OriginalIntentReadOnly.1'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        JournalSha256=$sha
        JournalEventCount=1
        OriginalPhase='Intent'
        OriginalSequence=1
        OriginalSizeBytes=1436L
        ProposedNextSequence=2
        ProposedNextPhase='Reconciled'
        FutureBw3jResolutionClaimAbsent=$true
        LegacyLive6ResolutionClaimAbsent=$true
        AutomaticRetryBlocked=$true
        ReconciliationAuthorized=$false
    }
}
function Assert-OPA265BW3jOriginalIntentEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $fields=@('Schema','RunId','OperationId','JournalSha256','JournalEventCount',
        'OriginalPhase','OriginalSequence','OriginalSizeBytes','ProposedNextSequence',
        'ProposedNextPhase','FutureBw3jResolutionClaimAbsent',
        'LegacyLive6ResolutionClaimAbsent','AutomaticRetryBlocked','ReconciliationAuthorized')
    if ($null -eq $Evidence -or $Evidence -is [string] -or
        $Evidence -is [array] -or
        @($Evidence.PSObject.Properties.Name).Count -ne $fields.Count) {
        throw 'BW3j original journal evidence malformed.'
    }
    foreach($key in $fields) {
        if ($Evidence.PSObject.Properties.Name -cnotcontains $key) {
            throw ('BW3j original journal evidence missing '+$key)
        }
    }
    if ([string]$Evidence.Schema -cne '2.6.5-BW3j.OriginalIntentReadOnly.1' -or
        [string]$Evidence.RunId -cne [string]$Pinned.RunId -or
        [string]$Evidence.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Evidence.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [int]$Evidence.JournalEventCount -ne 1 -or
        [string]$Evidence.OriginalPhase -cne 'Intent' -or
        [int]$Evidence.OriginalSequence -ne 1 -or
        [long]$Evidence.OriginalSizeBytes -ne 1436 -or
        [int]$Evidence.ProposedNextSequence -ne 2 -or
        [string]$Evidence.ProposedNextPhase -cne 'Reconciled') {
        throw 'BW3j original journal evidence does not match pinned single Intent.'
    }
    foreach($key in @('FutureBw3jResolutionClaimAbsent',
        'LegacyLive6ResolutionClaimAbsent','AutomaticRetryBlocked','ReconciliationAuthorized')) {
        $expected=($key -cne 'ReconciliationAuthorized')
        if ($Evidence.$key -isnot [bool] -or $Evidence.$key -ne $expected) {
            throw ('BW3j evidence attempts to bypass journal safety: '+$key)
        }
    }
    return $true
}
function Get-OPA265BW3jResolutionDesignDossier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$Bw3h,
          [Parameter(Mandatory=$true)][object]$OriginalIntent,
          [Parameter(Mandatory=$true)][object]$Before,
          [Parameter(Mandatory=$true)][object]$After,
          [Parameter(Mandatory=$true)][string]$AcceptanceRecordPath)
    [void](Assert-OPA265BW3iBw3hVerdict -Verdict $Bw3h -Pinned $Pinned -RecordPath $AcceptanceRecordPath)
    [void](Assert-OPA265BW3jOriginalIntentEvidence -Evidence $OriginalIntent -Pinned $Pinned)
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $Before -After $After -Pinned $Pinned)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3j.BW3ScopedJournalResolutionDesignReadOnly.1'
        Status='BW3ScopedResolutionDesignEvidenceVerifiedAuthorizationNotIssued'
        Decision='DesignOnlyNoJournalAppendWithoutSeparateExplicitAuthorization'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        OriginalIntentSha256=[string]$Pinned.JournalSha256
        AcceptanceRecordSha256=[string]$Pinned.AcceptanceFileSha256
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        VerifiedHistoricalMoveViaBW3h=$true
        SevenHistoricalEvidenceHashesUnchanged=$true
        SourceItemCount=0
        ArchiveItemCount=1
        OriginalJournalEventCount=1
        OriginalJournalPhase='Intent'
        ProposedJournalSequence=2
        ProposedJournalPhase='Reconciled'
        PinnedIntentSizeBytes=1436L
        PinnedArchiveSizeBytes=1444L
        ManuallyAcceptedSyntheticDifferenceBytes=8L
        SingleSyntheticSizeAcceptanceVerified=$true
        LegacyLive6ExecuteApplicable=$false
        ExistingResolutionClaimFound=$false
        FutureClaimPathReservedInDesignOnly=$true
        FutureClaimCreated=$false
        FutureExclusiveJournalLockImplemented=$false
        FutureJournalAppendWriterImplemented=$false
        CrashGapAfterClaimBeforeAppendRequiresManualStop=$true
        CrashGapAfterAppendBeforeVerifyRequiresManualStop=$true
        ConcurrentAppendRequiresExclusiveLockAndFreshSHA256=$true
        OriginalJournalRetentionRequired=$true
        FullMAPIContentByteEqualityVerified=$false
        SizeDriftCauseEstablished=$false
        JournalReconciliationAuthorized=$false
        JournalWritePermitIssued=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='IndependentReviewOfSeparateBW3ScopedWriterDesignAndFreshOneRunUserAuthorization'
    }
}
