#requires -Version 5.1
# BW3h pure final READ-ONLY chain classification. No COM, journal or JSON writes.
# Manual +8 size acceptance is NOT permission to append Reconciled.
function Get-OPA265BW3hPinnedChain {
    [CmdletBinding()]
    param()
    $p=Get-OPA265BW3gPinnedAcceptance
    return [pscustomobject]@{
        RunId=[string]$p.RunId
        OperationId=[string]$p.OperationId
        WorkerRequestId=[string]$p.WorkerRequestId
        SourcePst=[string]$p.SourcePst
        DestinationEntryId=[string]$p.DestinationEntryId
        JournalSha256=[string]$p.JournalSha256
        BodyUtf8Sha256=[string]$p.BodyUtf8Sha256
        OriginalSizeBytes=1436L
        ArchivedSizeBytes=1444L
        AcceptedSizeDeltaBytes=8L
        AcceptanceFileName=[string]$p.RecordFileName
        AcceptanceFileSha256='c7b066436b03d5f9cd400ebf560c82852e46d943d15d276a2d42e3fa3fb01161'
    }
}
function Assert-OPA265BW3hPinnedIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pinned)
    $fixed=Get-OPA265BW3hPinnedChain
    foreach($key in @('RunId','OperationId','WorkerRequestId','SourcePst',
        'DestinationEntryId','JournalSha256','BodyUtf8Sha256',
        'AcceptanceFileName','AcceptanceFileSha256')) {
        if ([string]$Pinned.$key -cne [string]$fixed.$key) {
            throw ('BW3h changed pinned evidence identifier: '+$key)
        }
    }
    if ([long]$Pinned.OriginalSizeBytes -ne 1436 -or
        [long]$Pinned.ArchivedSizeBytes -ne 1444 -or
        [long]$Pinned.AcceptedSizeDeltaBytes -ne 8) {
        throw 'BW3h altered size evidence.'
    }
    return $true
}
function Assert-OPA265BW3hPreviousAcceptanceReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][string]$ExactRecordPath)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $names=@('Schema','Status','Decision','RunId','JournalSha256',
        'AcceptanceRecordPath','AcceptanceRecordSha256','AcceptedDifferenceBytes',
        'ManualSizeAcceptancePersisted','JournalReconciliationAuthorized',
        'JournalChanged','JournalReconciled','MailMoveExecuted',
        'AutomaticRetryAllowed','ProductionReady')
    if ($null -eq $Review -or $Review -is [array] -or $Review -is [string] -or
        @($Review.PSObject.Properties.Name).Count -ne $names.Count) {
        throw 'BW3h requires exactly one complete BW3g1 read-only Review result.'
    }
    foreach($n in $names) {
        if ($Review.PSObject.Properties.Name -cnotcontains $n) {
            throw ('BW3h missing BW3g1 Review field: '+$n)
        }
    }
    if ([string]$Review.Schema -cne '2.6.5-BW3g.ManualSizeAcceptanceStatus.1' -or
        [string]$Review.Status -cne 'HistoricalSyntheticSizeAcceptanceRecordVerified' -or
        [string]$Review.Decision -cne 'OnlyEightByteSyntheticSizeDeviationRecorded' -or
        [string]$Review.RunId -cne [string]$Pinned.RunId -or
        [string]$Review.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Review.AcceptanceRecordPath -cne $ExactRecordPath -or
        [string]$Review.AcceptanceRecordSha256 -cne [string]$Pinned.AcceptanceFileSha256 -or
        [long]$Review.AcceptedDifferenceBytes -ne 8) {
        throw 'BW3h rejects previous BW3g1 evidence scope or SHA256.'
    }
    foreach($n in @('ManualSizeAcceptancePersisted',
        'JournalReconciliationAuthorized','JournalChanged',
        'JournalReconciled','MailMoveExecuted','AutomaticRetryAllowed','ProductionReady')) {
        $expected=($n -ceq 'ManualSizeAcceptancePersisted')
        if ($Review.$n -isnot [bool] -or $Review.$n -ne $expected) {
            throw ('BW3h unsafe/non-Boolean previous Review flag: '+$n)
        }
    }
    return $true
}
function Get-OPA265BW3hEvidenceSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Extra,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $original=Get-OPA265BW3gEvidenceFileHashes -Paths $Paths -Extra $Extra
    $recordPath=Get-OPA265BW3gRecordPath -Paths $Paths
    if ([IO.Path]::GetFileName($recordPath) -cne [string]$Pinned.AcceptanceFileName -or
        -not [IO.File]::Exists($recordPath) -or
        (([IO.File]::GetAttributes($recordPath)) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3h requires existing regular exact-run size acceptance JSON.'
    }
    $sha=(Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha -cne [string]$Pinned.AcceptanceFileSha256) {
        throw 'BW3h acceptance file SHA256 differs from independently observed pinned value.'
    }
    if ([string]$original.Journal -cne [string]$Pinned.JournalSha256) {
        throw 'BW3h historical Intent SHA256 mismatch.'
    }
    return [pscustomobject][ordered]@{
        Journal=[string]$original.Journal
        Request=[string]$original.Request
        Scope=[string]$original.Scope
        MoveAttemptClaim=[string]$original.MoveAttemptClaim
        DispatchClaim=[string]$original.DispatchClaim
        ControllerResult=[string]$original.ControllerResult
        ManualSizeAcceptance=[string]$sha
    }
}
function Assert-OPA265BW3hSnapshotUnchanged {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Before,
          [Parameter(Mandatory=$true)][object]$After,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $keys=@('Journal','Request','Scope','MoveAttemptClaim',
        'DispatchClaim','ControllerResult','ManualSizeAcceptance')
    if (@($Before.PSObject.Properties.Name).Count -ne 7 -or
        @($After.PSObject.Properties.Name).Count -ne 7) {
        throw 'BW3h requires exactly seven durable evidence hashes.'
    }
    foreach($key in $keys) {
        if ($Before.PSObject.Properties.Name -cnotcontains $key -or
            $After.PSObject.Properties.Name -cnotcontains $key -or
            [string]$Before.$key -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$After.$key -cne [string]$Before.$key) {
            throw ('BW3h durable evidence changed during audit: '+$key)
        }
    }
    if ([string]$After.Journal -cne [string]$Pinned.JournalSha256 -or
        [string]$After.ManualSizeAcceptance -cne [string]$Pinned.AcceptanceFileSha256) {
        throw 'BW3h pinned journal or consent SHA256 mismatch.'
    }
    return $true
}
function Get-OPA265BW3hChainVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][string]$ExactRecordPath,
          [Parameter(Mandatory=$true)][object]$Before,
          [Parameter(Mandatory=$true)][object]$After)
    [void](Assert-OPA265BW3hPreviousAcceptanceReview -Review $Review -Pinned $Pinned -ExactRecordPath $ExactRecordPath)
    [void](Assert-OPA265BW3hSnapshotUnchanged -Before $Before -After $After -Pinned $Pinned)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3h.IndependentDurableEvidenceChainReadOnly.1'
        Status='IndependentEvidenceChainVerifiedJournalDecisionPending'
        Decision='StopBeforeSeparateExplicitJournalReconciliationAuthorization'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        OriginalIntentSha256=[string]$Pinned.JournalSha256
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        ArchivedBodyUtf8Sha256=[string]$Pinned.BodyUtf8Sha256
        AcceptanceRecordPath=$ExactRecordPath
        AcceptanceRecordSha256=[string]$Pinned.AcceptanceFileSha256
        SevenDurableEvidenceHashesVerified=$true
        OriginalIntentUnchanged=$true
        WorkerDispatchClaimCorrelated=$true
        MoveAttemptClaimCorrelated=$true
        WorkerDestinationIdentityConfirmed=$true
        SourceItemCount=0
        ArchiveItemCount=1
        SyntheticAttachmentsCount=0
        BodyBaselinePlusSpaceCrLfConfirmed=$true
        IntentSizeBytes=1436L
        ArchivedSizeBytes=1444L
        ManuallyAcceptedSyntheticDifferenceBytes=8L
        ManualSizeAcceptancePersisted=$true
        SizeDiscrepancyCauseEstablished=$false
        BeforeMoveActualBodyHashAvailable=$false
        FullMAPIContentByteEqualityVerified=$false
        JournalReconciliationAuthorized=$false
        JournalWritePermitIssued=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='PreserveAllEvidenceAndRequireSeparateExplicitJournalDecision'
    }
}
