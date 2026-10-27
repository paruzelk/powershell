#requires -Version 5.1
# BW3d: ONE historical synthetic +8-byte Outlook size audit, read-only.
# Never dispatches a Worker, calls Move/Save, mounts PST, or writes artifacts.
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
    throw 'BW3d requires explicit -Review in native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
$pinned=Get-OPA265BW3dPinnedSizeReview
if ($RunId -cne [string]$pinned.RunId -or
    $SourcePst -cne [string]$pinned.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$pinned.JournalSha256) {
    throw 'BW3d refuses any non-pinned RunId, POP3 SourcePst or journal SHA256.'
}
# The existing independent BW3b audit validates all three durable claims,
# exact Outlook archive EntryID, 0/1 item counts and unchanged Intent.
$previous=& (Join-Path $PSScriptRoot 'Test-OPA265BW3bIndependentMoveAudit.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
[void](Assert-OPA265BW3dPinnedBw3bAudit -Previous $previous -Pinned $pinned)
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$request=Read-OPAWorkerJson -Path $paths.RequestPath
if ([string]$request.RunId -cne [string]$pinned.RunId -or
    [string]$request.OperationId -cne [string]$pinned.OperationId -or
    [string]$request.SourcePst -cne [string]$pinned.SourcePst) {
    throw 'BW3d fixture request no longer matches approved synthetic operation.'
}
$paths=Assert-OPA264Live3Request -Request $request
$extra=Get-OPA265BW3Paths -FixturePaths $paths
$evidenceFiles=@($paths.JournalPath,$paths.RequestPath,$paths.ScopePath,$paths.ClaimPath,
    $extra.DispatchClaimPath,$extra.ControllerResultPath)
$before=@{}
foreach($file in $evidenceFiles) {
    if (-not [IO.File]::Exists($file) -or
        ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3d requires regular durable journal, request, scope, dispatch, attempt and result files.'
    }
    $before[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
}
if ([string]$before[$paths.JournalPath] -cne [string]$pinned.JournalSha256) {
    throw 'BW3d pinned journal SHA256 mismatch before Outlook access.'
}
$app=$null;$ns=$null;$stage='Attach existing test Outlook'
try {
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) {throw 'BW3d requires already-running Outlook.'}
    $ns=$app.GetNamespace('MAPI')
    if ([string]$ns.CurrentProfileName -cne 'Outlook') {
        throw 'BW3d refuses a non-test Outlook profile.'
    }
    $stage='Validate uniquely mounted POP3 source and synthetic archive PSTs'
    $src=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.SourcePst
    $dst=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.ArchivePst
    [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $src)
    if ([string]$src.StoreID -cne [string]$request.SourceStoreId -or
        [string]$dst.StoreID -cne [string]$request.ArchiveStoreId -or
        [string]$src.StoreID -ceq [string]$dst.StoreID) {
        throw 'BW3d mounted test PST identity mismatch.'
    }
    $stage='Validate exact GUID-scoped source and target folder identities'
    $from=$ns.GetFolderFromID([string]$request.SourceFolderEntryId,[string]$request.SourceStoreId)
    $to=$ns.GetFolderFromID([string]$request.ArchiveFolderEntryId,[string]$request.ArchiveStoreId)
    if ($null -eq $from -or $null -eq $to -or
        [string]$from.Name -cne [string]$paths.SourceFolderName -or
        [string]$to.Name -cne [string]$paths.ArchiveFolderName -or
        [string]$from.FolderPath -cne [string]$request.SourceFolderPath -or
        [string]$to.FolderPath -cne [string]$request.ArchiveFolderPath -or
        -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$from.StoreID) -ObservedFolderEntryId ([string]$from.EntryID) -ExpectedStoreId ([string]$request.SourceStoreId) -ExpectedFolderEntryId ([string]$request.SourceFolderEntryId)) -or
        -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$to.StoreID) -ObservedFolderEntryId ([string]$to.EntryID) -ExpectedStoreId ([string]$request.ArchiveStoreId) -ExpectedFolderEntryId ([string]$request.ArchiveFolderEntryId))) {
        throw 'BW3d exact synthetic folder identity mismatch.'
    }
    $stage='Inspect single moved synthetic MailItem by exact archive EntryID'
    $srcCount=[int]$from.Items.Count
    $dstCount=[int]$to.Items.Count
    if ($srcCount -ne 0 -or $dstCount -ne 1) {
        throw 'BW3d refuses missing/duplicate archived synthetic mail.'
    }
    $mail=$ns.GetItemFromID([string]$pinned.ArchiveEntryId,[string]$request.ArchiveStoreId)
    if ($null -eq $mail -or [int]$mail.Class -ne 43 -or
        [string]$mail.MessageClass -cne 'IPM.Note' -or
        [string]$mail.EntryID -cne [string]$pinned.ArchiveEntryId -or
        [string]$mail.Parent.StoreID -cne [string]$request.ArchiveStoreId -or
        [string]$mail.Parent.EntryID -cne [string]$request.ArchiveFolderEntryId -or
        [string]$mail.Parent.FolderPath -cne [string]$request.ArchiveFolderPath) {
        throw 'BW3d archived MailItem identity, class or parent mismatch.'
    }
    $subject=[string]$mail.Subject
    $messageId=[string]$mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    $stage='Read only archived Body, Attachments.Count and MAPI message sizes'
    $body=[string]$mail.Body
    $attachments=[int]$mail.Attachments.Count
    $size=[long]$mail.Size
    $prAvailable=$false
    $prSize=0L
    $prError=''
    try {
        # PidTagMessageSize: optional provider-reported PR_MESSAGE_SIZE.
        $prSize=[long]$mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x0E080003')
        $prAvailable=$true
    } catch {
        $prSize=0L
        $prError='UnavailableOrProviderRejected'
    }
    $observed=[pscustomobject]@{
        RunId=[string]$pinned.RunId
        OperationId=[string]$pinned.OperationId
        ArchiveEntryId=[string]$mail.EntryID
        ArchiveStoreId=[string]$mail.Parent.StoreID
        ArchiveFolderEntryId=[string]$mail.Parent.EntryID
        ArchiveFolderPath=[string]$mail.Parent.FolderPath
        Subject=$subject
        InternetMessageId=$messageId
        MailClass=[int]$mail.Class
        MessageClass=[string]$mail.MessageClass
        SourceItemCount=$srcCount
        ArchiveItemCount=$dstCount
        AttachmentsCount=$attachments
        BodyText=$body
        MailItemSizeBytes=$size
        PrMessageSizeAvailable=[bool]$prAvailable
        PrMessageSizeBytes=[long]$prSize
        PrMessageSizeReadError=$prError
    }
    [void](Assert-OPA265BW3dObservation -Evidence $observed -Pinned $pinned)
    $stage='Recheck journal and original durable evidence checksums'
    foreach($file in $evidenceFiles) {
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            [string]$before[$file]) {
            throw 'BW3d durable journal or claim evidence changed during Outlook inspection.'
        }
    }
    Write-Output (Get-OPA265BW3dSizeEvidenceVerdict -Previous $previous -Observation $observed -Pinned $pinned)
} catch {
    throw ('BW3d read-only audit STOP at [{0}]: {1}. NO MOVE/RETRY/RECONCILED.' -f $stage,[string]$_.Exception.Message)
} finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
