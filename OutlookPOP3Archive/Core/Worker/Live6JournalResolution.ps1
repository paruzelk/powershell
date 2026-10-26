#requires -Version 5.1
# LIVE6 synthetic-only, explicit append-once journal resolution.
# No Outlook COM in this module. NEVER retries MailItem.Move or edits a PST.
function Get-OPA264Live6ClaimPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths)
    return (Join-Path ([string]$Paths.Directory) 'live6-resolution.claim')
}
function Assert-OPA264Live6CommitReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256)
    if ($ExpectedJournalSha256 -cnotmatch '^[a-fA-F0-9]{64}$' -or
        [string]$Review.Schema -cne '2.6.4-LIVE5.ReconciliationReview.1' -or
        [string]$Review.RunId -cne [string]$Request.RunId -or
        [string]$Review.OperationId -cne [string]$Request.OperationId -or
        [string]$Review.CrashWindow -cne 'AfterMoveBeforeResponse' -or
        [string]$Review.Decision -cne 'MoveConfirmed' -or
        [int]$Review.SourceItemCount -ne 0 -or
        [int]$Review.ArchiveItemCount -ne 1 -or
        [int]$Review.SyntheticSourceMatches -ne 0 -or
        [int]$Review.SyntheticArchiveMatches -ne 1 -or
        -not [bool]$Review.MoveAttemptClaimExists -or
        -not [bool]$Review.EvidenceSufficientForClassification -or
        -not [bool]$Review.JournalUnchanged -or
        [bool]$Review.OutlookMoveExecuted -or
        [bool]$Review.JournalCompleted -or
        [bool]$Review.JournalReconciled -or
        [bool]$Review.AutomaticRetryAllowed -or
        -not [bool]$Review.RequiresManualJournalDecision -or
        [bool]$Review.ProductionReady -or
        [string]$Review.JournalSha256 -cne $ExpectedJournalSha256.ToLowerInvariant()) {
        throw 'LIVE6 proof is not the exact independently confirmed post-Move crash and pinned journal SHA256.'
    }
    return $true
}
function New-OPA264Live6Claim {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
          [Parameter(Mandatory=$true)][string]$ArchiveEntryId,
          [long]$IntentSizeBytes=0,
          [long]$ObservedArchiveSizeBytes=0,
          [bool]$ExplicitSizeDifferenceApproved=$false)
    if (($IntentSizeBytes -gt 0 -or $ObservedArchiveSizeBytes -gt 0) -and
        ($IntentSizeBytes -le 0 -or $ObservedArchiveSizeBytes -le 0 -or
         ($IntentSizeBytes -ne $ObservedArchiveSizeBytes -and -not $ExplicitSizeDifferenceApproved) -or
         ($IntentSizeBytes -eq $ObservedArchiveSizeBytes -and $ExplicitSizeDifferenceApproved))) {
        throw 'LIVE6 durable claim size evidence must be complete and explicitly approved when changed.'
    }
    if ($ExpectedJournalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace($ArchiveEntryId)) {
        throw 'LIVE6 requires a pinned journal SHA256 and exact nonempty archive EntryID.'
    }
    $claim=[pscustomobject]@{
        Schema='2.6.4-LIVE6.ResolutionClaim.1'
        RunId=[string]$Request.RunId
        OperationId=[string]$Request.OperationId
        PreviousJournalSha256=$ExpectedJournalSha256
        ArchiveEntryId=$ArchiveEntryId
        IntentSizeBytes=$IntentSizeBytes
        ObservedArchiveSizeBytes=$ObservedArchiveSizeBytes
        ExplicitSizeDifferenceApproved=$ExplicitSizeDifferenceApproved
        Utc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(
        (ConvertTo-Json -InputObject $claim -Depth 5))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new((Get-OPA264Live6ClaimPath -Paths $Paths),
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    return $claim
}
function Assert-OPA264Live6Completed {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Journal,
          [Parameter(Mandatory=$true)][object]$Claim)
    if ([bool]$Journal.TrailingPartial -or @($Journal.Events).Count -ne 2) {
        throw 'LIVE6 completed resolution must contain exactly Intent and Reconciled.'
    }
    $first=[pscustomobject]@{Events=@($Journal.Events[0]);TrailingPartial=$false}
    [void](Assert-OPA264Live5Journal -Request $Request -Paths $Paths -Journal $first)
    $event=$Journal.Events[1]
    if ([string]$Claim.Schema -cne '2.6.4-LIVE6.ResolutionClaim.1' -or
        [string]$Claim.RunId -cne [string]$Paths.RunId -or
        [string]$Claim.OperationId -cne [string]$Request.OperationId -or
        [string]$Claim.PreviousJournalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$Claim.ArchiveEntryId) -or
        [bool]$Claim.AutomaticRetryAllowed -or
        [bool]$Claim.ProductionReady -or
        [string]$event.Phase -cne 'Reconciled' -or
        [string]$event.OperationKind -cne 'MailMove' -or
        [long]$event.Sequence -ne 2 -or
        [string]$event.TransactionId -cne [string]$Paths.RunId -or
        [string]$event.OperationId -cne [string]$Request.OperationId -or
        [string]$event.ArchiveEntryId -cne [string]$Claim.ArchiveEntryId -or
        [string]$event.ArchivePst -cne [string]$Paths.ArchivePst) {
        throw 'LIVE6 existing resolution claim and journal disagree.'
    }
    $replay=Resolve-OPAOperationRecovery -Journal $Journal
    if (@($replay.Indeterminate).Count -ne 0 -or
        @($replay.Resolved).Count -ne 1 -or
        [string]$replay.Resolved[0].Status -cne 'Reconciled' -or
        [string]$replay.Resolved[0].ArchiveEntryId -cne [string]$Claim.ArchiveEntryId) {
        throw 'LIVE6 completed journal replay is invalid.'
    }
    return $true
}
function Write-OPA264Live6ReconciledLocked {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Intent,
          [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
          [Parameter(Mandatory=$true)][string]$ArchiveEntryId)
    if ($ExpectedJournalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace($ArchiveEntryId) -or
        [string]$Intent.Phase -cne 'Intent' -or
        [string]$Intent.OperationKind -cne 'MailMove' -or
        [long]$Intent.Sequence -ne 1) {
        throw 'LIVE6 refuses to append without one validated Intent and pinned journal.'
    }
    $claimPath=Get-OPA264Live6ClaimPath -Paths $Paths
    if (-not [IO.File]::Exists($claimPath)) {
        throw 'LIVE6 refuses journal append without prior durable CreateNew resolution claim.'
    }
    $claim=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($claimPath)) -ErrorAction Stop
    if ([string]$claim.Schema -cne '2.6.4-LIVE6.ResolutionClaim.1' -or
        [string]$claim.RunId -cne [string]$Intent.TransactionId -or
        [string]$claim.OperationId -cne [string]$Intent.OperationId -or
        [string]$claim.ArchiveEntryId -cne $ArchiveEntryId -or
        [string]$claim.PreviousJournalSha256 -cne $ExpectedJournalSha256 -or
        [bool]$claim.AutomaticRetryAllowed -or [bool]$claim.ProductionReady) {
        throw 'LIVE6 durable resolution claim does not match exact intended append.'
    }
    $JournalPath=[string]$Paths.JournalPath
    $stream=$null
    try {
        # Exclusive lock covers both pinned byte check and full append.
        $stream=[IO.FileStream]::new($JournalPath,[IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if ($stream.Length -lt 2 -or $stream.Length -gt 1048576) {
            throw 'LIVE6 journal length outside single-Intent bounds.'
        }
        $bytes=New-Object byte[] ([int]$stream.Length)
        $offset=0
        while ($offset -lt $bytes.Length) {
            $read=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if ($read -le 0) { throw 'LIVE6 short read while holding journal lock.' }
            $offset+=$read
        }
        if ($bytes[$bytes.Length-1] -ne 10 -or
            (Get-OPAOperationJournalSha256 -Bytes $bytes) -cne $ExpectedJournalSha256) {
            throw 'LIVE6 journal changed before exclusive append; no write made.'
        }
        $entry=[ordered]@{
            SchemaVersion='1.0'
            Utc=[datetime]::UtcNow.ToString('o')
            TransactionId=[string]$Intent.TransactionId
            OperationId=[string]$Intent.OperationId
            Sequence=2
            Phase='Reconciled'
            OperationKind='MailMove'
            WorkerProcessId=0
            FailureKind=''
            SourceEntryId=[string]$Intent.SourceEntryId
            ArchiveEntryId=$ArchiveEntryId
            ArchivePst=[string]$Intent.ArchivePst
            SourceStoreId=[string]$Intent.SourceStoreId
            SourceFolderPath=[string]$Intent.SourceFolderPath
            TargetFolderPath=[string]$Intent.TargetFolderPath
            InternetMessageId=[string]$Intent.InternetMessageId
            Subject=[string]$Intent.Subject
            Sender=[string]$Intent.Sender
            Size=[long]$Intent.Size
            Message='LIVE6 explicit synthetic-only independent MoveConfirmed journal resolution'
        }
        $utf8=New-Object Text.UTF8Encoding($false)
        $payloadBytes=$utf8.GetBytes((ConvertTo-Json -InputObject $entry -Depth 8 -Compress))
        $envelope=[ordered]@{
            V=1
            Payload=[Convert]::ToBase64String($payloadBytes)
            Sha256=(Get-OPAOperationJournalSha256 -Bytes $payloadBytes)
        }
        $encoded=$utf8.GetBytes((ConvertTo-Json -InputObject $envelope -Depth 4 -Compress)+[char]10)
        [void]$stream.Seek(0,[IO.SeekOrigin]::End)
        $stream.Write($encoded,0,$encoded.Length)
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    return $true
}

# MAPI PR_MESSAGE_SIZE is store-computed, not a byte-identical cross-PST
# content hash. A difference demands explicit separately pinned manual consent.
function Get-OPA264Live6SizeEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][long]$IntentSizeBytes,
          [Parameter(Mandatory=$true)][long]$ObservedArchiveSizeBytes)
    if ($IntentSizeBytes -le 0 -or $ObservedArchiveSizeBytes -le 0) {
        throw 'LIVE6 refuses unknown, zero or negative MailItem sizes.'
    }
    return [pscustomobject]@{
        IntentSizeBytes=$IntentSizeBytes
        ObservedArchiveSizeBytes=$ObservedArchiveSizeBytes
        SizeDifferenceBytes=($ObservedArchiveSizeBytes - $IntentSizeBytes)
        CrossPstSizeDiffers=($IntentSizeBytes -ne $ObservedArchiveSizeBytes)
    }
}
function Assert-OPA264Live6SizeApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence,
          [switch]$ConfirmCrossPstSizeDifference,
          [long]$ExpectedArchiveSizeBytes=-1)
    if ([bool]$Evidence.CrossPstSizeDiffers) {
        if (-not $ConfirmCrossPstSizeDifference -or
            $ExpectedArchiveSizeBytes -le 0 -or
            $ExpectedArchiveSizeBytes -ne [long]$Evidence.ObservedArchiveSizeBytes) {
            throw 'LIVE6 cross-PST size changed: explicit consent and exact pinned observed archive size are required.'
        }
    } elseif ($ConfirmCrossPstSizeDifference -or $ExpectedArchiveSizeBytes -ne -1) {
        throw 'LIVE6 refuses unsolicited size-difference override when sizes match.'
    }
    return $true
}
