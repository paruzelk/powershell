#requires -Version 5.1
# BW3b INDEPENDENT READ-ONLY audit of the ONE previously moved BW3a mail.
# NEVER writes a journal/claim, never replays Move, never mounts/edits PST.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if (-not $Review -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW3b requires explicit -Review in native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live5Reconciliation.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
$pinned=Get-OPA265BW3bPinnedIdentity
if ($RunId -cne $pinned.RunId -or
    $ExpectedJournalSha256 -cne $pinned.JournalSha256 -or
    $SourcePst -cne [string]$pinned.SourcePst) {
    throw 'BW3b only audits the exact approved BW3a synthetic RunId/PST/journal SHA256.'
}
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$request=Read-OPAWorkerJson -Path $paths.RequestPath
if ([string]$request.RunId -cne $pinned.RunId -or
    [string]$request.OperationId -cne $pinned.OperationId -or
    [string]$request.SourcePst -cne [string]$paths.SourcePst) {
    throw 'BW3b fixture request identity mismatch.'
}
$paths=Assert-OPA264Live3Request -Request $request
$journal=Read-OPAOperationJournal -Path $paths.JournalPath
[void](Assert-OPA264Live5Journal -Request $request -Paths $paths -Journal $journal)
$intent=Assert-OPA264Live3Intent -Request $request -Paths $paths
$originalHash=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($originalHash -cne $pinned.JournalSha256 -or [long]$intent.Size -ne 1436) {
    throw 'BW3b original durable Intent/hash changed; audit stops.'
}
$extra=Get-OPA265BW3Paths -FixturePaths $paths
$proof=[pscustomobject]@{
    RunId=$paths.RunId
    OperationId=[string]$request.OperationId
    SourcePst=[string]$paths.SourcePst
    JournalSha256=$originalHash
    Request=$request
    Intent=$intent
}
foreach($path in @($extra.DispatchClaimPath,$extra.ControllerResultPath,$paths.ClaimPath)) {
    if (-not [IO.File]::Exists([string]$path) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3b requires exact regular durable dispatch, attempt and controller evidence files.'
    }
}
# Worker protocol's transient response is NOT stored in the LIVE3 fixture.
# All old LIVE4 and LIVE6 artifacts must remain absent in this BW3b audit.
foreach($path in @($paths.ResponsePath,(Join-Path $paths.Directory 'controller-dispatch.claim'),
    (Join-Path $paths.Directory 'crash-barrier.json'),
    (Join-Path $paths.Directory 'live6-resolution.claim'))) {
    if ([IO.File]::Exists([string]$path)) {
        throw 'BW3b unexpected legacy response/crash/reconciliation artifact.'
    }
}
$dispatchRaw=[IO.File]::ReadAllText($extra.DispatchClaimPath)
$reportRaw=[IO.File]::ReadAllText($extra.ControllerResultPath)
$attempt=[IO.File]::ReadAllText($paths.ClaimPath)
$dispatch=ConvertFrom-Json -InputObject $dispatchRaw -ErrorAction Stop
$report=ConvertFrom-Json -InputObject $reportRaw -ErrorAction Stop
[void](Assert-OPA265BW3bRecords -Proof $proof -Dispatch $dispatch -Report $report -MoveClaimText $attempt -Pinned $pinned)
$app=$null;$ns=$null;$stage='Attach existing test Outlook'
try {
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) {throw 'BW3b requires already-running Outlook.'}
    $ns=$app.GetNamespace('MAPI')
    if ([string]$ns.CurrentProfileName -cne 'Outlook') {
        throw 'BW3b refuses another Outlook profile.'
    }
    $stage='Check uniquely mounted exact PSTs and POP3 account binding'
    $src=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.SourcePst
    $dst=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.ArchivePst
    [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $src)
    if ([string]$src.StoreID -cne [string]$request.SourceStoreId -or
        [string]$dst.StoreID -cne [string]$request.ArchiveStoreId -or
        [string]$src.StoreID -ceq [string]$dst.StoreID) {
        throw 'BW3b mounted store identity mismatch.'
    }
    $stage='Check exact run-scoped source and archive folder identities'
    $from=$ns.GetFolderFromID([string]$request.SourceFolderEntryId,[string]$request.SourceStoreId)
    $to=$ns.GetFolderFromID([string]$request.ArchiveFolderEntryId,[string]$request.ArchiveStoreId)
    if ($null -eq $from -or $null -eq $to -or
        [string]$from.Name -cne [string]$paths.SourceFolderName -or
        [string]$to.Name -cne [string]$paths.ArchiveFolderName -or
        [string]$from.FolderPath -cne [string]$request.SourceFolderPath -or
        [string]$to.FolderPath -cne [string]$request.ArchiveFolderPath -or
        -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$from.StoreID) -ObservedFolderEntryId ([string]$from.EntryID) -ExpectedStoreId ([string]$request.SourceStoreId) -ExpectedFolderEntryId ([string]$request.SourceFolderEntryId)) -or
        -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$to.StoreID) -ObservedFolderEntryId ([string]$to.EntryID) -ExpectedStoreId ([string]$request.ArchiveStoreId) -ExpectedFolderEntryId ([string]$request.ArchiveFolderEntryId))) {
        throw 'BW3b synthetic folder identity mismatch.'
    }
    $stage='Inspect zero source items and exactly one archive MailItem'
    $srcCount=[int]$from.Items.Count
    $dstCount=[int]$to.Items.Count
    if ($srcCount -ne 0 -or $dstCount -ne 1) {
        throw 'BW3b requires source=0 and archive=1; stop on missing or duplicate mail.'
    }
    $mail=$to.Items.Item(1)
    if ($null -eq $mail -or [int]$mail.Class -ne 43 -or
        [string]$mail.EntryID -cne [string]$pinned.ArchiveEntryId -or
        [string]$mail.Parent.EntryID -cne [string]$request.ArchiveFolderEntryId -or
        [string]$mail.Parent.StoreID -cne [string]$request.ArchiveStoreId -or
        [string]$mail.Subject -cne [string]$intent.Subject) {
        throw 'BW3b archive mail EntryID, parent, class or subject mismatch.'
    }
    $messageId=[string]$mail.PropertyAccessor.GetProperty(
        'http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if ($messageId -cne [string]$intent.InternetMessageId) {
        throw 'BW3b archive mail InternetMessageId differs from durable Intent.'
    }
    $stage='Verify direct archive EntryID lookup in exact archive store'
    $lookup=$ns.GetItemFromID([string]$pinned.ArchiveEntryId,[string]$request.ArchiveStoreId)
    if ($null -eq $lookup -or [int]$lookup.Class -ne 43 -or
        [string]$lookup.EntryID -cne [string]$mail.EntryID -or
        [string]$lookup.Parent.EntryID -cne [string]$request.ArchiveFolderEntryId -or
        [string]$lookup.Parent.StoreID -cne [string]$request.ArchiveStoreId) {
        throw 'BW3b direct archive lookup cannot confirm Worker destination EntryID.'
    }
    $observed=[pscustomobject]@{
        RunId=[string]$paths.RunId
        SourceItemCount=$srcCount
        ArchiveItemCount=$dstCount
        SyntheticSourceMatches=0
        SyntheticArchiveMatches=1
        ArchiveEntryId=[string]$mail.EntryID
        ArchiveStoreId=[string]$mail.Parent.StoreID
        ArchiveFolderEntryId=[string]$mail.Parent.EntryID
        ArchiveFolderPath=[string]$mail.Parent.FolderPath
        InternetMessageId=$messageId
        Subject=[string]$mail.Subject
        MailClass=[int]$mail.Class
        ObservedArchiveSizeBytes=[long]$mail.Size
        OnlySyntheticFoldersInspected=$true
    }
    [void](Assert-OPA265BW3bMailboxEvidence -Observed $observed -Proof $proof -Pinned $pinned)
    $stage='Recheck immutable Intent and durable claims after Outlook inspection'
    $finalHash=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($finalHash -cne $originalHash -or
        [IO.File]::ReadAllText($paths.ClaimPath) -cne $attempt -or
        [IO.File]::ReadAllText($extra.DispatchClaimPath) -cne $dispatchRaw -or
        [IO.File]::ReadAllText($extra.ControllerResultPath) -cne $reportRaw) {
        throw 'BW3b durable evidence changed while reading Outlook.'
    }
    Write-Output (Get-OPA265BW3bVerdict -Proof $proof -Pinned $pinned -Observed $observed)
} catch {
    throw ('BW3b independent read-only audit STOP at [{0}]: {1}. NO MOVE/RETRY; preserve evidence.' -f $stage,[string]$_.Exception.Message)
} finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
