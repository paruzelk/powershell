#requires -Version 5.1
# BW3b: independent POST-MOVE EVIDENCE AUDIT ONLY. No COM, file writes or
# dispatch here. The actual read-only Outlook inspector is a separate script.
function Get-OPA265BW3bPinnedIdentity {
    [CmdletBinding()]
    param()
    # BW3c: Windows PowerShell 5.1 assumes legacy ANSI for a BOM-less .ps1.
    # Construct the exact Cyrillic directory name from Unicode code points
    # instead of embedding non-ASCII source text.
    $rus=(-join @([char]0x0424,[char]0x0430,[char]0x0439,[char]0x043B,[char]0x044B))
    $pinnedSource=('C:\Users\bogoderov_e\Documents\'+$rus+' Outlook\info@stios.ru.pst')
    return [pscustomobject]@{
        SourcePst=$pinnedSource
        RunId='a7b51427-7494-43f4-bc96-64915f6bee7e'
        OperationId='9bd83da2-d47e-404f-a4fd-792852b58dec'
        WorkerRequestId='24553e9c-fa09-497f-b42d-4329ebe27021'
        JournalSha256='5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648'
        ArchiveEntryId='00000000953C628FC9EAC24E97DBE040019A969924002000'
    }
}
function Assert-OPA265BW3bExactFields {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Record,
          [Parameter(Mandatory=$true)][string[]]$Fields,
          [Parameter(Mandatory=$true)][string]$Label)
    if ($null -eq $Record -or $Record -is [string] -or $Record -is [array]) {
        throw ('BW3b invalid object: '+$Label)
    }
    $found=@($Record.PSObject.Properties.Name)
    if ($found.Count -ne $Fields.Count) {
        throw ('BW3b unexpected field count: '+$Label)
    }
    foreach($f in $Fields) {
        if ($found -cnotcontains $f) {
            throw ('BW3b missing field '+$f+' in '+$Label)
        }
    }
    return $true
}
function Assert-OPA265BW3bRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Proof,
          [Parameter(Mandatory=$true)][object]$Dispatch,
          [Parameter(Mandatory=$true)][object]$Report,
          [Parameter(Mandatory=$true)][string]$MoveClaimText,
          [Parameter(Mandatory=$true)][object]$Pinned)
    # This is ONE exact operator-approved historical test, not a
    # generic authorization to classify any old/out-of-scope mail.
    if ([string]$Proof.RunId -cne [string]$Pinned.RunId -or
        [string]$Proof.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Proof.JournalSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Pinned.RunId -cne 'a7b51427-7494-43f4-bc96-64915f6bee7e' -or
        [string]$Pinned.OperationId -cne '9bd83da2-d47e-404f-a4fd-792852b58dec' -or
        [string]$Pinned.WorkerRequestId -cne '24553e9c-fa09-497f-b42d-4329ebe27021' -or
        [string]$Pinned.JournalSha256 -cne '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648' -or
        [string]$Pinned.ArchiveEntryId -cne '00000000953C628FC9EAC24E97DBE040019A969924002000' -or
        [string]$Pinned.SourcePst -cne (Get-OPA265BW3bPinnedIdentity).SourcePst -or
        [string]$Proof.SourcePst -cne [string]$Pinned.SourcePst) {
        throw 'BW3b audit is pinned to a single approved historical fixture.'
    }
    [void](Assert-OPA265BW3bExactFields -Record $Dispatch -Label 'dispatch' -Fields @(
        'Schema','RunId','OperationId','WorkerRequestId','JournalSha256','SourcePst',
        'Utc','AutomaticRetryAllowed','ProductionReady','JournalCompleted','PstReconciliationComplete'))
    [void](Assert-OPA265BW3bExactFields -Record $Report -Label 'controller result' -Fields @(
        'Schema','Status','RunId','OperationId','WorkerRequestId','WorkerProcessId',
        'WorkerStatus','FailureKind','Error','DestinationEntryId','JournalSha256',
        'DispatchClaimExists','MoveAttemptClaimExists','WorkerMoveMayHaveExecuted',
        'JournalCompleted','AutomaticRetryAllowed','RequiresIndependentReconciliation',
        'ProductionReady','NextAction'))
    $id=[guid]::Empty
    if (-not [guid]::TryParse([string]$Dispatch.WorkerRequestId,[ref]$id) -or
        $id -eq [guid]::Empty -or
        [string]$Dispatch.Schema -cne '2.6.5-BW3.DispatchClaim.1' -or
        [string]$Report.Schema -cne '2.6.5-BW3.ControllerResult.1' -or
        [string]$Dispatch.RunId -cne [string]$Proof.RunId -or
        [string]$Report.RunId -cne [string]$Proof.RunId -or
        [string]$Dispatch.OperationId -cne [string]$Proof.OperationId -or
        [string]$Report.OperationId -cne [string]$Proof.OperationId -or
        [string]$Dispatch.WorkerRequestId -cne [string]$Pinned.WorkerRequestId -or
        [string]$Report.WorkerRequestId -cne [string]$Dispatch.WorkerRequestId -or
        [string]$Dispatch.JournalSha256 -cne [string]$Proof.JournalSha256 -or
        [string]$Report.JournalSha256 -cne [string]$Proof.JournalSha256 -or
        [string]$Dispatch.SourcePst -cne [string]$Proof.SourcePst -or
        [string]$MoveClaimText.Trim() -cne [string]$Proof.OperationId -or
        [string]$Report.DestinationEntryId -cne [string]$Pinned.ArchiveEntryId -or
        [string]$Report.Status -cne 'MoveReturnedNeedsIndependentReview' -or
        [string]$Report.WorkerStatus -cne 'Succeeded' -or
        [string]$Report.FailureKind -cne 'None' -or
        -not [string]::IsNullOrEmpty([string]$Report.Error) -or
        [int]$Report.WorkerProcessId -le 0 -or
        -not [bool]$Report.DispatchClaimExists -or
        -not [bool]$Report.MoveAttemptClaimExists -or
        -not [bool]$Report.WorkerMoveMayHaveExecuted -or
        [bool]$Report.JournalCompleted -or
        [bool]$Report.AutomaticRetryAllowed -or
        -not [bool]$Report.RequiresIndependentReconciliation -or
        [bool]$Report.ProductionReady -or
        [string]$Report.NextAction -cne 'StopAndPerformIndependentReadOnlyReview' -or
        [bool]$Dispatch.AutomaticRetryAllowed -or
        [bool]$Dispatch.ProductionReady -or
        [bool]$Dispatch.JournalCompleted -or
        [bool]$Dispatch.PstReconciliationComplete) {
        throw 'BW3b claims/controller record correlation or safety flags mismatch.'
    }
    return $true
}
function Assert-OPA265BW3bMailboxEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Observed,
          [Parameter(Mandatory=$true)][object]$Proof,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3bExactFields -Record $Observed -Label 'Outlook observation' -Fields @(
        'RunId','SourceItemCount','ArchiveItemCount','SyntheticSourceMatches',
        'SyntheticArchiveMatches','ArchiveEntryId','ArchiveStoreId',
        'ArchiveFolderEntryId','ArchiveFolderPath','InternetMessageId','Subject',
        'MailClass','ObservedArchiveSizeBytes','OnlySyntheticFoldersInspected'))
    if ([string]$Observed.RunId -cne [string]$Pinned.RunId -or
        [int]$Observed.SourceItemCount -ne 0 -or
        [int]$Observed.ArchiveItemCount -ne 1 -or
        [int]$Observed.SyntheticSourceMatches -ne 0 -or
        [int]$Observed.SyntheticArchiveMatches -ne 1 -or
        [string]$Observed.ArchiveEntryId -cne [string]$Pinned.ArchiveEntryId -or
        [string]$Observed.ArchiveStoreId -cne [string]$Proof.Request.ArchiveStoreId -or
        [string]$Observed.ArchiveFolderEntryId -cne [string]$Proof.Request.ArchiveFolderEntryId -or
        [string]$Observed.ArchiveFolderPath -cne [string]$Proof.Request.ArchiveFolderPath -or
        [string]$Observed.InternetMessageId -cne [string]$Proof.Intent.InternetMessageId -or
        [string]$Observed.Subject -cne [string]$Proof.Intent.Subject -or
        [int]$Observed.MailClass -ne 43 -or
        [long]$Observed.ObservedArchiveSizeBytes -le 0 -or
        -not [bool]$Observed.OnlySyntheticFoldersInspected) {
        throw 'BW3b independent Outlook identity/count evidence mismatch; NO AUTO RETRY.'
    }
    return $true
}
function Get-OPA265BW3bVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Proof,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][object]$Observed)
    [void](Assert-OPA265BW3bMailboxEvidence -Observed $Observed -Proof $Proof -Pinned $Pinned)
    $same=([long]$Observed.ObservedArchiveSizeBytes -eq [long]$Proof.Intent.Size)
    return [pscustomobject]@{
        Schema='2.6.5-BW3b.IndependentPostMoveAudit.1'
        Status='IndependentPostMoveAuditPassed'
        Decision='MoveConfirmedByEntryIdAndSyntheticIdentity'
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        WorkerRequestId=[string]$Pinned.WorkerRequestId
        JournalSha256=[string]$Pinned.JournalSha256
        SourceItemCount=0
        ArchiveItemCount=1
        SyntheticSourceMatches=0
        SyntheticArchiveMatches=1
        WorkerDestinationEntryId=[string]$Pinned.ArchiveEntryId
        ObservedArchiveEntryId=[string]$Observed.ArchiveEntryId
        ArchiveEntryIdMatchesWorker=$true
        IntentSizeBytes=[long]$Proof.Intent.Size
        ObservedArchiveSizeBytes=[long]$Observed.ObservedArchiveSizeBytes
        ArchiveSizeMatchesIntent=$same
        ArchiveSizeDifferenceBytes=([long]$Observed.ObservedArchiveSizeBytes - [long]$Proof.Intent.Size)
        ArchiveSizeDifferenceApproved=$false
        ContentByteEqualityVerified=$false
        RequiresManualSizeReview=(-not $same)
        ClaimsCorrelated=$true
        OutlookComAccessExecuted=$true
        OnlySyntheticFoldersInspected=$true
        OutlookMoveExecuted=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='StopBeforeManualJournalDecision'
    }
}
