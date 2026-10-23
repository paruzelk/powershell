#requires -Version 5.1
# 2.6.4-LIVE2. Test-only, pure scope validators for a temporary restore
# CLONE of a byte-verified backup. NEVER modifies the original POP3 PST,
# the reference backup, or the production Archive/Resume/Auto worker.
. (Join-Path $PSScriptRoot 'ExistingPstBackupGuard.ps1')

function Get-OPA264RestorePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$BackupPst,
        [Parameter(Mandatory=$true)][string]$ExpectedBackupSHA256,
        [Parameter(Mandatory=$true)][long]$ExpectedSizeBytes,
        [Parameter(Mandatory=$true)][string]$RunId
    )
    if ($ExpectedBackupSHA256 -cnotmatch '^[a-fA-F0-9]{64}$' -or $ExpectedSizeBytes -le 1024) {
        throw 'A pinned backup SHA-256 and nonempty expected size are required.'
    }
    $guid=[guid]::Empty
    if (-not [guid]::TryParse($RunId,[ref]$guid) -or $guid -eq [guid]::Empty) {
        throw 'The restore test RunId must be a nonempty GUID.'
    }
    $source=Assert-OPA264BackupLocalPath -Path $SourcePst -MustExist -File
    $backup=Assert-OPA264BackupLocalPath -Path $BackupPst -MustExist -File
    $sourceParent=[IO.Path]::GetDirectoryName($source)
    $backupParent=[IO.Path]::GetDirectoryName($backup)
    if ([string]::Equals($sourceParent,$backupParent,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Reference backup must not share the active Outlook data directory.'
    }
    if ([string]::Equals($source,$backup,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Restore source PST and reference backup must differ.'
    }
    foreach ($path in @($source,$backup)) {
        $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($file.PSIsContainer -or [long]$file.Length -ne $ExpectedSizeBytes) {
            throw 'Restore source/backup length differs from pinned backup evidence.'
        }
    }
    $referenceHash=[string](Get-FileHash -LiteralPath $backup -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($referenceHash -cne $ExpectedBackupSHA256.ToUpperInvariant()) {
        throw 'The reference backup SHA-256 differs from pinned LIVE1 evidence.'
    }
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $tempInfo=Get-Item -LiteralPath $tempRoot -Force -ErrorAction Stop
    if (($tempInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'System TEMP is a reparse-point location.'
    }
    $root=Join-Path $tempRoot ('OPA264-Restore-'+$guid.ToString('N'))
    $clone=Join-Path $root 'RestoreCopy.pst'
    $marker=Join-Path $root 'restore-scope.json'
    $claim=Join-Path $root 'restore-probe.claim'
    $report=Join-Path $root 'restore-report.json'
    if ([string]::Equals($clone,$source,[StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($clone,$backup,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Temporary clone overlaps reference source or backup.'
    }
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) {
        throw 'Restore test must use a fixed local TEMP volume.'
    }
    return [pscustomobject]@{
        Schema='2.6.4-LIVE2.Plan.1'
        RunId=$guid.ToString('D')
        SourcePst=$source
        BackupPst=$backup
        ExpectedSizeBytes=$ExpectedSizeBytes
        ExpectedBackupSHA256=$ExpectedBackupSHA256.ToLowerInvariant()
        Directory=$root
        ClonePst=$clone
        MarkerPath=$marker
        ClaimPath=$claim
        ReportPath=$report
        BackupValidated=$true
        ExistingPstMutationAllowed=$false
        MailMoveAllowed=$false
    }
}

function Assert-OPA264RestoreClonePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Plan)
    if ($null -eq $Plan -or [string]$Plan.Schema -cne '2.6.4-LIVE2.Plan.1' -or
        -not [bool]$Plan.BackupValidated -or [bool]$Plan.MailMoveAllowed -or
        [bool]$Plan.ExistingPstMutationAllowed) {
        throw 'Restore clone plan is not an approved test-only plan.'
    }
    foreach($p in @($Plan.Directory,$Plan.ClonePst,$Plan.MarkerPath,$Plan.ClaimPath,$Plan.ReportPath)){
        if (Test-Path -LiteralPath ([string]$p)) {
            throw 'Restore clone RunId has existing artifacts; never overwrite or retry.'
        }
    }
    if ([IO.Directory]::Exists([string]$Plan.Directory)) {
        throw 'Restore clone RunId directory already exists.'
    }
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot([string]$Plan.Directory))
    if ($drive.AvailableFreeSpace -lt ([long]$Plan.ExpectedSizeBytes+128MB)) {
        throw 'Insufficient disk space for isolated restore clone plus safety margin.'
    }
    return $true
}

function Assert-OPA264RestoreMarker {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Plan,
          [Parameter(Mandatory=$true)][object]$Marker)
    if ([string]$Marker.Purpose -cne 'OPA264-OneShot-Backup-Restore-Copy' -or
        [string]$Marker.RunId -cne [string]$Plan.RunId -or
        [string]$Marker.ClonePst -cne [string]$Plan.ClonePst -or
        [string]$Marker.SourcePst -cne [string]$Plan.SourcePst -or
        [string]$Marker.BackupPst -cne [string]$Plan.BackupPst -or
        [string]$Marker.BackupSHA256 -cne [string]$Plan.ExpectedBackupSHA256 -or
        [long]$Marker.ExpectedSizeBytes -ne [long]$Plan.ExpectedSizeBytes) {
        throw 'Restore marker mismatches pinned original or reference backup.'
    }
    if ([bool]$Marker.MailMoveAllowed -or [bool]$Marker.OriginalPstMutationAllowed) {
        throw 'Restore marker attempts to authorize source PST mutation.'
    }
    return $true
}

function Get-OPA264RestoreFolderInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Store,
          [ValidateRange(1,1000)][int]$MaxFolders=100)
    $root=$Store.GetRootFolder()
    if ($null -eq $root) { throw 'Outlook backup clone store has no root folder.' }
    $queue=New-Object Collections.Queue
    $queue.Enqueue([pscustomobject]@{Folder=$root;Relative='';Depth=0})
    $counts=New-Object 'System.Collections.Generic.List[object]'
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($queue.Count -gt 0) {
        if ($counts.Count -ge $MaxFolders) {
            throw 'Outlook store exceeds the bounded restore verification folder count.'
        }
        $item=$queue.Dequeue()
        $folder=$item.Folder
        if (-not $seen.Add([string]$item.Relative)) {
            throw 'Outlook store contains duplicate relative folder identities.'
        }
        $children=$folder.Folders
        [void]$counts.Add([pscustomobject]@{
            RelativePath=[string]$item.Relative
            Items=[int]$folder.Items.Count
            Subfolders=[int]$children.Count
        })
        for ($i=1;$i -le [int]$children.Count;$i++){
            $child=$children.Item($i)
            if ($null -eq $child) { throw 'Outlook restore inventory child folder missing.' }
            $part=[string]$child.Name
            if ([string]::IsNullOrWhiteSpace($part)) { throw 'Outlook restore inventory folder name is blank.' }
            $relative=$part
            if ([string]$item.Relative -cne '') { $relative=[string]$item.Relative+'\'+$part }
            $queue.Enqueue([pscustomobject]@{
                Folder=$child
                Relative=$relative
                Depth=([int]$item.Depth+1)
            })
        }
    }
    return [pscustomobject]@{
        FolderCount=$counts.Count
        Folders=$counts.ToArray()
    }
}

function Compare-OPA264RestoreFolderInventories {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Source,
          [Parameter(Mandatory=$true)][object]$Restored)
    $original=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $duplicate=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($Source.Folders)) {
        $path=[string]$row.RelativePath
        if ($original.ContainsKey($path)) { throw 'Source inventory has duplicate relative folder paths.' }
        $original.Add($path,([string]$row.Items+'/'+[string]$row.Subfolders))
    }
    $differences=New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in @($Restored.Folders)) {
        $path=[string]$row.RelativePath
        if (-not $duplicate.Add($path)) { throw 'Restored inventory has duplicate relative paths.' }
        $expected=$null
        if (-not $original.TryGetValue($path,[ref]$expected)) {
            [void]$differences.Add('UnexpectedFolder')
        }
        elseif ($expected -cne ([string]$row.Items+'/'+[string]$row.Subfolders)) {
            [void]$differences.Add('CountMismatch')
        }
    }
    foreach ($path in $original.Keys) {
        if (-not $duplicate.Contains($path)) { [void]$differences.Add('MissingFolder') }
    }
    $equal=($differences.Count -eq 0 -and
        [int]$Source.FolderCount -eq [int]$Restored.FolderCount)
    return [pscustomobject]@{
        Schema='2.6.4-LIVE2.Comparison.1'
        FolderCountSource=[int]$Source.FolderCount
        FolderCountRestored=[int]$Restored.FolderCount
        FolderStructureAndCountsEqual=$equal
        DifferenceTypes=$differences.ToArray()
        MailMoveAllowed=$false
        OriginalPstModified=$false
        ProductionReady=$false
        RequiresManualReview=$true
    }
}
