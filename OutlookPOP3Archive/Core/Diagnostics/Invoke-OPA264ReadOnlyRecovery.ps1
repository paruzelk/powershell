#requires -Version 5.1
# 2.6.4-D: independent FRESH-process read-only examination of already mounted
# disposable PSTs. Never creates Outlook, mounts/detaches PSTs or moves mail.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if (-not $Review) { throw 'Fresh-process recovery requires explicit -Review.' }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'Read-only recovery requires Windows PowerShell 5.1 STA.'
}

. (Join-Path $PSScriptRoot '../Runtime/ComManager.ps1')
. (Join-Path $PSScriptRoot '../Archive/ArchiveSelector.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerReadOnlyRecovery.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerProtocol.ps1')

$paths=Get-OPA264TestPaths -RunId $RunId
$request=Read-OPAWorkerJson -Path $paths.RequestPath
[void](Assert-OPA264RecoveryFixture -Request $request -RunId $paths.RunId)

$app=$null; $ns=$null
try {
    # GetActiveObject does not create a profile or start Outlook.
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'Outlook must already be running with the disposable test PST pair.' }
    $ns=$app.GetNamespace('MAPI')
    [void](Assert-OPA264TestStore -Namespace $ns -StoreId ([string]$request.SourceStoreId) -PstPath $paths.SourcePst)
    [void](Assert-OPA264TestStore -Namespace $ns -StoreId ([string]$request.ArchiveStoreId) -PstPath $paths.ArchivePst)
    $source=$ns.GetFolderFromID([string]$request.SourceFolderEntryId,[string]$request.SourceStoreId)
    $archive=$ns.GetFolderFromID([string]$request.ArchiveFolderEntryId,[string]$request.ArchiveStoreId)
    if ($null -eq $source -or $null -eq $archive -or
        [string]$source.StoreID -cne [string]$request.SourceStoreId -or
        [string]$archive.StoreID -cne [string]$request.ArchiveStoreId -or
        [string]$source.FolderPath -cne [string]$request.SourceFolderPath -or
        [string]$archive.FolderPath -cne [string]$request.ArchiveFolderPath) {
        throw 'Fresh-process PST folder StoreID/path identity mismatch.'
    }
    # Full folder scans, not GetItemFromID-only, capture duplicate matches.
    $src=New-OPAReadOnlyMoveSnapshot -Folder $source -FolderPath ([string]$request.SourceFolderPath) -StoreIdentity ([string]$request.SourceStoreId) -Role Source
    $dst=New-OPAReadOnlyMoveSnapshot -Folder $archive -FolderPath ([string]$request.ArchiveFolderPath) -StoreIdentity ([string]$request.ArchiveStoreId) -Role Destination -ArchivePst $paths.ArchivePst
    $report=Resolve-OPA264ReadOnlyRecovery -Request $request -SourceSnapshot $src -DestinationSnapshot $dst
    # No subject, sender, message ID, EntryID, body or PST contents in stdout.
    # This is an observation, NOT a journal transaction completion.
    Write-Output (ConvertTo-Json -InputObject $report -Depth 8)
}
finally {
    if ($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if ($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
