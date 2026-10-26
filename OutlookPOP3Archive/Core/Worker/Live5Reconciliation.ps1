#requires -Version 5.1
# LIVE5 pure, test-only evidence classification. No Outlook COM or file mutation.
# NEVER appends Completed/Reconciled; NEVER authorizes re-Move.
function Assert-OPA264Live5Journal {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Journal)
    if ([bool]$Journal.TrailingPartial -or @($Journal.Events).Count -ne 1) {
        throw 'LIVE5 requires exactly one complete, unresolved durable Intent.'
    }
    $intent=$Journal.Events[0]
    if ([string]$intent.Phase -cne 'Intent' -or
        [string]$intent.OperationKind -cne 'MailMove' -or
        [string]$intent.TransactionId -cne [string]$Paths.RunId -or
        [string]$intent.OperationId -cne [string]$Request.OperationId -or
        [string]$intent.SourceEntryId -cne [string]$Request.SourceEntryId -or
        [string]$intent.SourceStoreId -cne [string]$Request.SourceStoreId -or
        [string]$intent.SourceFolderPath -cne [string]$Request.SourceFolderPath -or
        [string]$intent.TargetFolderPath -cne [string]$Request.ArchiveFolderPath -or
        [string]$intent.ArchivePst -cne [string]$Paths.ArchivePst -or
        [string]$intent.InternetMessageId -cne
            ('<opa264-live3-'+$Paths.RunId+'@example.invalid>') -or
        [string]$intent.Subject -cne ('OPA264 LIVE3 synthetic '+$Paths.RunId) -or
        [long]$intent.Size -lt 0) {
        throw 'LIVE5 durable Intent identity/fingerprint mismatch.'
    }
    $replay=Resolve-OPAOperationRecovery -Journal $Journal
    if ([string]$replay.TransactionId -cne [string]$Paths.RunId -or
        @($replay.Indeterminate).Count -ne 1 -or
        @($replay.Resolved).Count -ne 0 -or
        -not [bool]$replay.BlockAutomaticRetry -or
        -not [bool]$replay.RequiresPstReconciliation) {
        throw 'LIVE5 journal replay cannot prove a single unresolved MailMove.'
    }
    return $replay
}
function Get-OPA264Live5Decision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Recovery,
          [Parameter(Mandatory=$true)][object]$JournalReplay)
    if ([string]$Recovery.RunId -cne [string]$Request.RunId -or
        [string]$Recovery.OperationId -cne [string]$Request.OperationId -or
        [string]$JournalReplay.TransactionId -cne [string]$Request.RunId) {
        throw 'LIVE5 cross-evidence RunId/OperationId mismatch.'
    }
    if ([string]$Recovery.Schema -cne '2.6.4-LIVE4.RecoverySnapshot.1' -or
        [string]$Recovery.CrashWindow -cnotin @('WorkerStartedBeforeMove','AfterMoveBeforeResponse') -or
        [string]$Recovery.Status -cnotin @(
            'PreMoveCrashNoMoveObserved','PostMoveCrashMoveObserved','IndeterminateNeedsManualReview') -or
        -not [bool]$Recovery.ControllerDispatchClaimExists -or
        -not [bool]$Recovery.WorkerKilledByOwningController -or
        -not [bool]$Recovery.OutlookExaminedOnlySyntheticFolders -or
        [bool]$Recovery.MoveExecutedByThisInspection -or
        [bool]$Recovery.WorkerResponseExists -or
        [bool]$Recovery.JournalCompleted -or
        [bool]$Recovery.AutomaticRetryAllowed -or
        -not [bool]$Recovery.RequiresIndependentReconciliation -or
        [bool]$Recovery.ProductionReady -or
        @($JournalReplay.Indeterminate).Count -ne 1 -or
        @($JournalReplay.Resolved).Count -ne 0 -or
        -not [bool]$JournalReplay.BlockAutomaticRetry -or
        -not [bool]$JournalReplay.RequiresPstReconciliation) {
        throw 'LIVE5 untrusted recovery snapshot or resolved journal; stop.'
    }
    $source=[int]$Recovery.SourceItemCount
    $archive=[int]$Recovery.ArchiveItemCount
    $srcExact=[int]$Recovery.SyntheticSourceMatches
    $dstExact=[int]$Recovery.SyntheticArchiveMatches
    if ($source -lt 0 -or $archive -lt 0 -or
        $srcExact -lt 0 -or $dstExact -lt 0 -or
        $srcExact -gt $source -or $dstExact -gt $archive) {
        throw 'LIVE5 impossible message counts; do not reconcile.'
    }
    $window=[string]$Recovery.CrashWindow
    $claim=[bool]$Recovery.MoveAttemptClaimExists
    $status=[string]$Recovery.Status
    $decision='Ambiguous'
    if ($source -eq 1 -and $archive -eq 1 -and
        $srcExact -eq 1 -and $dstExact -eq 1) {
        $decision='AmbiguousDuplicate'
    } elseif ($source -eq 0 -and $archive -eq 0) {
        $decision='MissingItem'
    } elseif ($source -eq 1 -and $archive -eq 0 -and
        $srcExact -eq 1 -and $dstExact -eq 0 -and
        $window -ceq 'WorkerStartedBeforeMove' -and -not $claim -and
        $status -ceq 'PreMoveCrashNoMoveObserved') {
        $decision='NoMoveObserved'
    } elseif ($source -eq 0 -and $archive -eq 1 -and
        $srcExact -eq 0 -and $dstExact -eq 1 -and
        $window -ceq 'AfterMoveBeforeResponse' -and $claim -and
        $status -ceq 'PostMoveCrashMoveObserved') {
        $decision='MoveConfirmed'
    }
    return [pscustomobject]@{
        Schema='2.6.4-LIVE5.Decision.1'
        RunId=[string]$Request.RunId
        OperationId=[string]$Request.OperationId
        CrashWindow=$window
        Decision=$decision
        SourceItemCount=$source
        ArchiveItemCount=$archive
        SyntheticSourceMatches=$srcExact
        SyntheticArchiveMatches=$dstExact
        MoveAttemptClaimExists=$claim
        EvidenceSufficientForClassification=($decision -in @('NoMoveObserved','MoveConfirmed'))
        JournalCompleted=$false
        JournalReconciled=$false
        AutomaticRetryAllowed=$false
        RequiresManualJournalDecision=$true
        ProductionReady=$false
    }
}
