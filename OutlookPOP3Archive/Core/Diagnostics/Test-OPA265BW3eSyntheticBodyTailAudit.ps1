#requires -Version 5.1
# BW3e: ONE archived synthetic Body tail audit, READ-ONLY. NO Move or writes.
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
    throw 'BW3e requires explicit -Review and native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3eSyntheticBodyTailEvidence265.ps1')
$pinned=Get-OPA265BW3ePinnedTailEvidence
if ($RunId -cne [string]$pinned.RunId -or
    $SourcePst -cne [string]$pinned.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$pinned.JournalSha256) {
    throw 'BW3e only inspects the one pinned historical synthetic operation.'
}
# Existing BW3d reruns BW3b: immutable claims, single synthetic EntryID.
$previous=& (Join-Path $PSScriptRoot 'Test-OPA265BW3dSyntheticSizeAudit.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
[void](Assert-OPA265BW3ePriorSizeEvidence -Previous $previous -Pinned $pinned)
$paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
$request=Read-OPAWorkerJson -Path $paths.RequestPath
if ([string]$request.RunId -cne [string]$pinned.RunId -or
    [string]$request.OperationId -cne [string]$pinned.OperationId -or
    [string]$request.SourcePst -cne [string]$pinned.SourcePst) {
    throw 'BW3e fixture request identity mismatch.'
}
$paths=Assert-OPA264Live3Request -Request $request
$extra=Get-OPA265BW3Paths -FixturePaths $paths
$evidenceFiles=@($paths.JournalPath,$paths.RequestPath,$paths.ScopePath,
    $paths.ClaimPath,$extra.DispatchClaimPath,$extra.ControllerResultPath)
$originalHashes=@{}
foreach($path in $evidenceFiles) {
    if (-not [IO.File]::Exists($path) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW3e original durable evidence must exist as regular files.'
    }
    $originalHashes[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
if ([string]$originalHashes[$paths.JournalPath] -cne [string]$pinned.JournalSha256) {
    throw 'BW3e original Intent journal SHA256 no longer matches approved hash.'
}
$app=$null;$ns=$null;$stage='Attach already-running Outlook test profile'
try {
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) {throw 'BW3e requires already-running Outlook.'}
    $ns=$app.GetNamespace('MAPI')
    if ([string]$ns.CurrentProfileName -cne 'Outlook') {
        throw 'BW3e refuses non-test Outlook profile.'
    }
    $stage='Verify unique source POP3 and archival synthetic PST identities'
    $src=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.SourcePst
    $dst=Get-OPA264Live3MountedStore -Namespace $ns -Path $paths.ArchivePst
    [void](Assert-OPA264Live3Pop3Source -Namespace $ns -Store $src)
    if ([string]$src.StoreID -cne [string]$request.SourceStoreId -or
        [string]$dst.StoreID -cne [string]$request.ArchiveStoreId -or
        [string]$src.StoreID -ceq [string]$dst.StoreID) {
        throw 'BW3e mounted PST StoreID mismatch.'
    }
    $stage='Verify exact source and target synthetic folder identities and counts'
    $from=$ns.GetFolderFromID([string]$request.SourceFolderEntryId,[string]$request.SourceStoreId)
    $to=$ns.GetFolderFromID([string]$request.ArchiveFolderEntryId,[string]$request.ArchiveStoreId)
    if ($null -eq $from -or $null -eq $to -or
        [string]$from.Name -cne [string]$paths.SourceFolderName -or
        [string]$to.Name -cne [string]$paths.ArchiveFolderName -or
        [string]$from.FolderPath -cne [string]$request.SourceFolderPath -or
        [string]$to.FolderPath -cne [string]$request.ArchiveFolderPath -or
        -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$from.StoreID) -ObservedFolderEntryId ([string]$from.EntryID) -ExpectedStoreId ([string]$request.SourceStoreId) -ExpectedFolderEntryId ([string]$request.SourceFolderEntryId)) -or
        -not (Test-OPA264Live3FolderIdentity -ObservedStoreId ([string]$to.StoreID) -ObservedFolderEntryId ([string]$to.EntryID) -ExpectedStoreId ([string]$request.ArchiveStoreId) -ExpectedFolderEntryId ([string]$request.ArchiveFolderEntryId)) -or
        [int]$from.Items.Count -ne 0 -or [int]$to.Items.Count -ne 1) {
        throw 'BW3e requires source=0/archive=1 and exact synthetic folder identities.'
    }
    $stage='Read only exact archived synthetic MailItem Body and tail code units'
    $mail=$ns.GetItemFromID([string]$pinned.ArchiveEntryId,[string]$request.ArchiveStoreId)
    if ($null -eq $mail -or [int]$mail.Class -ne 43 -or
        [string]$mail.MessageClass -cne 'IPM.Note' -or
        [string]$mail.EntryID -cne [string]$pinned.ArchiveEntryId -or
        [string]$mail.Parent.EntryID -cne [string]$request.ArchiveFolderEntryId -or
        [string]$mail.Parent.StoreID -cne [string]$request.ArchiveStoreId -or
        [string]$mail.Parent.FolderPath -cne [string]$request.ArchiveFolderPath -or
        [string]$mail.Subject -cne ('OPA264 LIVE3 synthetic '+[string]$pinned.RunId) -or
        [string]$mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F') -cne
            ('<opa264-live3-'+[string]$pinned.RunId+'@example.invalid>') -or
        [long]$mail.Size -ne 1444 -or [int]$mail.Attachments.Count -ne 0) {
        throw 'BW3e refuses changed MailItem identity, body scope or pinned archive size.'
    }
    $body=[string]$mail.Body
    $stage='Verify original Intent and all claims unchanged after COM getters'
    foreach($path in $evidenceFiles) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            [string]$originalHashes[$path]) {
            throw 'BW3e durable evidence changed during independent read-only inspection.'
        }
    }
    $stage='Classify exact three Unicode trailing code units without size approval'
    Write-Output (Get-OPA265BW3eTailVerdict -BodyText $body -Previous $previous -Pinned $pinned)
} catch {
    throw ('BW3e read-only body-tail audit STOP at [{0}]: {1}. NO MOVE/RETRY/RECONCILED.' -f
        $stage,[string]$_.Exception.Message)
} finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
