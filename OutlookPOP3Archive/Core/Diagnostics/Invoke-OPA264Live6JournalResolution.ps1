#requires -Version 5.1
# LIVE6: explicit, synthetic-only journal Reconciled append; no Outlook mutation.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [switch]$Review,
    [switch]$Execute,
    [switch]$ConfirmSyntheticJournalResolution,
    [string]$ExpectedJournalSha256=''
)
$ErrorActionPreference='Stop'
if ([bool]$Review -eq [bool]$Execute) {
    throw 'LIVE6 requires exactly one of -Review or -Execute.'
}
if ($Execute -and (-not $ConfirmSyntheticJournalResolution -or
    $ExpectedJournalSha256 -cnotmatch '^[a-fA-F0-9]{64}$')) {
    throw 'LIVE6 Execute requires -ConfirmSyntheticJournalResolution and -ExpectedJournalSha256.'
}
if ($Review -and ($ConfirmSyntheticJournalResolution -or $ExpectedJournalSha256)) {
    throw 'LIVE6 Review must be strictly read-only, without Execute confirmations.'
}
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'LIVE6 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live5Reconciliation.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live6JournalResolution.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$request=Read-OPAWorkerJson -Path $paths.RequestPath
if (-not [string]::Equals([string]$request.SourcePst,[string]$paths.SourcePst,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw 'LIVE6 selected source PST does not match synthetic fixture request.'
}
$paths=Assert-OPA264Live3Request -Request $request
$claimPath=Get-OPA264Live6ClaimPath -Paths $paths
$initial=Read-OPAOperationJournal -Path $paths.JournalPath
$initialSha=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([IO.File]::Exists($claimPath)) {
    if (@($initial.Events).Count -ne 2 -or [bool]$initial.TrailingPartial) {
        throw 'LIVE6 durable resolution claim exists but journal is not terminal: STOP, preserve evidence; NEVER auto-retry.'
    }
    $existing=Read-OPAWorkerJson -Path $claimPath
    [void](Assert-OPA264Live6Completed -Request $request -Paths $paths -Journal $initial -Claim $existing)
    if ($initialSha -cne (Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()) {
        throw 'LIVE6 existing journal changed during completed-state review.'
    }
    Write-Output ([pscustomobject]@{
        Schema='2.6.4-LIVE6.JournalResolutionResult.1'
        RunId=$paths.RunId
        OperationId=[string]$request.OperationId
        Status='AlreadyReconciled'
        ArchiveEntryId=[string]$existing.ArchiveEntryId
        JournalSha256=$initialSha
        JournalEventCount=2
        JournalReconciled=$true
        JournalChangedByThisInvocation=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    })
    return
}
if (@($initial.Events).Count -ne 1 -or [bool]$initial.TrailingPartial) {
    throw 'LIVE6 refuses missing/duplicate/partial/terminal journal without its own durable claim.'
}
[void](Assert-OPA264Live5Journal -Request $request -Paths $paths -Journal $initial)
$live5=& (Join-Path $PSScriptRoot 'Test-OPA264Live5Reconciliation.ps1') -RunId $paths.RunId -SourcePst $paths.SourcePst -Review
$archiveEntryId=''
if ([string]$live5.Decision -ceq 'MoveConfirmed') {
    [void](Assert-OPA264Live6CommitReview -Review $live5 -Request $request -ExpectedJournalSha256 $initialSha)
    # Retrieve exact destination EntryID from already-running test Outlook.
    # No store mounting; never inspect Inbox or arbitrary messages.
    $app=$null;$ns=$null
    try {
        $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
        if ($null -eq $app) { throw 'LIVE6 requires already-running Outlook.' }
        $ns=$app.GetNamespace('MAPI')
        if ([string]$ns.CurrentProfileName -cne 'Outlook') {
            throw 'LIVE6 refuses any Outlook profile other than approved TEST Outlook.'
        }
        $sourceStore=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.SourcePst
        $archiveStore=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.ArchivePst
        [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $sourceStore)
        if ([string]$sourceStore.StoreID -cne [string]$request.SourceStoreId -or
            [string]$archiveStore.StoreID -cne [string]$request.ArchiveStoreId) {
            throw 'LIVE6 StoreID identity changed after LIVE5 observation.'
        }
        $src=$ns.GetFolderFromID([string]$request.SourceFolderEntryId,[string]$request.SourceStoreId)
        $dst=$ns.GetFolderFromID([string]$request.ArchiveFolderEntryId,[string]$request.ArchiveStoreId)
        if ($null -eq $src -or $null -eq $dst -or
            [string]$src.FolderPath -cne [string]$request.SourceFolderPath -or
            [string]$dst.FolderPath -cne [string]$request.ArchiveFolderPath -or
            [int]$src.Items.Count -ne 0 -or [int]$dst.Items.Count -ne 1) {
            throw 'LIVE6 source/target folder identity or exact counts changed.'
        }
        $item=$dst.Items.Item(1)
        if ($null -eq $item -or [int]$item.Class -ne 43) {
            throw 'LIVE6 target is not exactly one MailItem.'
        }
        $msgid=[string]$item.PropertyAccessor.GetProperty(
            'http://schemas.microsoft.com/mapi/proptag/0x1035001F')
        $intent=$initial.Events[0]
        if ($msgid -cne [string]$intent.InternetMessageId -or
            [string]$item.Subject -cne [string]$intent.Subject) {
            throw 'LIVE6 archive MailItem fingerprint changed.'
        }
        if ([long]$intent.Size -gt 0 -and [long]$item.Size -ne [long]$intent.Size) {
            throw 'LIVE6 archive MailItem size differs from durable Intent.'
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$intent.Sender) -and
            [string]$item.SenderEmailAddress -cne [string]$intent.Sender) {
            throw 'LIVE6 archive MailItem sender differs from durable Intent.'
        }
        $archiveEntryId=[string]$item.EntryID
        if ([string]::IsNullOrWhiteSpace($archiveEntryId)) {
            throw 'LIVE6 unique archive MailItem has no EntryID.'
        }
    } finally {
        if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
        }
        if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
        }
    }
}
$afterProofSha=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($afterProofSha -cne $initialSha -or
    [string]$live5.JournalSha256 -cne $initialSha) {
    throw 'LIVE6 durable journal changed during independent proof; stop.'
}
if ($Review) {
    Write-Output ([pscustomobject]@{
        Schema='2.6.4-LIVE6.JournalResolutionResult.1'
        RunId=$paths.RunId
        OperationId=[string]$request.OperationId
        Status='ReviewOnly'
        Decision=[string]$live5.Decision
        CanExecute=([string]$live5.Decision -ceq 'MoveConfirmed' -and
                    -not [string]::IsNullOrWhiteSpace($archiveEntryId))
        ArchiveEntryId=$archiveEntryId
        ExpectedJournalSha256=$initialSha
        JournalEventCount=1
        JournalUnchanged=$true
        JournalReconciled=$false
        JournalChangedByThisInvocation=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    })
    return
}
# Explicit execution only for independently proved post-Move success.
[void](Assert-OPA264Live6CommitReview -Review $live5 -Request $request -ExpectedJournalSha256 $ExpectedJournalSha256)
if ([string]::IsNullOrWhiteSpace($archiveEntryId)) {
    throw 'LIVE6 requires exactly one independently identified target MailItem EntryID.'
}
if ([IO.File]::Exists($claimPath)) {
    throw 'LIVE6 concurrent resolution claim appeared; no retry.'
}
# Durable CreateNew claim before any journal mutation. If the host dies in
# the gap, the claim blocks all retries and needs separate manual review.
$claim=New-OPA264Live6Claim -Request $request -Paths $paths -ExpectedJournalSha256 $initialSha -ArchiveEntryId $archiveEntryId
[void](Write-OPA264Live6ReconciledLocked -Paths $paths -Intent $initial.Events[0] -ExpectedJournalSha256 $initialSha -ArchiveEntryId $archiveEntryId)
$complete=Read-OPAOperationJournal -Path $paths.JournalPath
[void](Assert-OPA264Live6Completed -Request $request -Paths $paths -Journal $complete -Claim $claim)
$finalSha=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($finalSha -ceq $initialSha) {
    throw 'LIVE6 append did not change journal; retain claim and inspect manually.'
}
Write-Output ([pscustomobject]@{
    Schema='2.6.4-LIVE6.JournalResolutionResult.1'
    RunId=$paths.RunId
    OperationId=[string]$request.OperationId
    Status='ReconciledJournalAppended'
    ArchiveEntryId=$archiveEntryId
    PreviousJournalSha256=$initialSha
    JournalSha256=$finalSha
    JournalEventCount=2
    JournalReconciled=$true
    JournalChangedByThisInvocation=$true
    OutlookMoveExecuted=$false
    AutomaticRetryAllowed=$false
    ProductionReady=$false
})
