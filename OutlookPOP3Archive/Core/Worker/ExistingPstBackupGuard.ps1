#requires -Version 5.1
# Pure preflight logic for a manually authorized immutable backup of an
# EXISTING Outlook POP3 PST. NO Outlook COM, Move, attachment or journal writes.
function Assert-OPA264BackupLocalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [switch]$MustExist,
        [switch]$File
    )
    if (-not [IO.Path]::IsPathRooted($Path) -or
        $Path.StartsWith('\\',[StringComparison]::Ordinal)) {
        throw 'Backup requires an absolute local filesystem path, not UNC.'
    }
    $full=[IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($full) -ine '.pst' -and $File) {
        throw 'Backup source and destination must be PST files.'
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $full)) {
        throw 'Required backup path does not exist.'
    }
    $cursor=$full
    if (-not (Test-Path -LiteralPath $cursor)) {
        $parent=[IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { throw 'Backup destination parent does not exist.' }
        $cursor=$parent.FullName
    }
    while (-not [string]::IsNullOrEmpty($cursor)) {
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Backup refuses symlinks or junctions in path: '+$cursor)
        }
        $parent=[IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor=$parent.FullName
    }
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) {
        throw 'Backup requires a fixed local drive.'
    }
    return $full
}

function Get-OPA264ExistingPstBackupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$BackupPst
    )
    $source=Assert-OPA264BackupLocalPath -Path $SourcePst -File -MustExist
    $destination=Assert-OPA264BackupLocalPath -Path $BackupPst -File
    $sourceInfo=Get-Item -LiteralPath $source -Force -ErrorAction Stop
    if ($sourceInfo.PSIsContainer) { throw 'Source PST path is not a file.' }
    if ($sourceInfo.Length -le 1024) { throw 'Source PST is unexpectedly small.' }
    $sourceParent=[IO.Path]::GetDirectoryName($source)
    $backupParent=[IO.Path]::GetDirectoryName($destination)
    if ([string]::Equals($source,$destination,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backup source and destination must differ.'
    }
    if ([string]::Equals($sourceParent,$backupParent,[StringComparison]::OrdinalIgnoreCase) -or
        $backupParent.StartsWith(($sourceParent.TrimEnd([char]'\')+'\'),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backup directory must be OUTSIDE the active Outlook PST directory.'
    }
    if (-not [IO.Directory]::Exists($backupParent)) {
        throw 'Backup destination directory must already exist.'
    }
    if ([IO.File]::Exists($destination) -or
        [IO.File]::Exists($destination+'.opa264-partial')) {
        throw 'Backup destination or partial file already exists; never overwrite.'
    }
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($destination))
    if ($drive.AvailableFreeSpace -lt ($sourceInfo.Length+128MB)) {
        throw 'Insufficient free backup disk space (PST size plus 128MB margin).'
    }
    return [pscustomobject]@{
        SourcePst=$source
        BackupPst=$destination
        IncompletePath=$destination+'.opa264-partial'
        SourceSizeBytes=[long]$sourceInfo.Length
        SourceSizeMB=[Math]::Round(($sourceInfo.Length/1MB),2)
        BackupFreeSpaceMB=[Math]::Round(($drive.AvailableFreeSpace/1MB),2)
        OutlookMustBeClosed=$true
        MailItemsModified=$false
        BackupVerified=$false
        ExistingPstMoveAuthorized=$false
    }
}
