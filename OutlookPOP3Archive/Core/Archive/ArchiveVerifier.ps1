# FIX9: verification reads actual Outlook source and archive items. A journal
# entry or DuplicateIndex entry is evidence of intent, not proof of location.
function Get-OPAFolderByPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Root,
        [Parameter(Mandatory=$true)][string]$RelativePath
    )
    $parts = @($RelativePath -split '\\' | Where-Object { $_ })
    if ($parts.Count -eq 0) { return $Root }
    if ([string]$parts[0] -ieq [string]$Root.Name) {
        if ($parts.Count -eq 1) { return $Root }
        $parts = @($parts | Select-Object -Skip 1)
    }
    $cur = $Root
    foreach ($part in $parts) {
        $next = $null
        $folders = $null
        try {
            $folders = $cur.Folders
            foreach ($f in @($folders)) {
                try {
                    if ($null -eq $next -and [string]$f.Name -ieq [string]$part) { $next = $f }
                    else { Release-OPAComObject -Object $f }
                }
                catch { Release-OPAComObject -Object $f }
            }
        }
        finally { Release-OPAComObject -Object $folders }
        if ($null -eq $next) { return $null }
        $previous = $cur
        $cur = $next
        if ($previous -ne $Root) { Release-OPAComObject -Object $previous }
    }
    return $cur
}

function Get-OPAExpectedMovesFromTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object]$DuplicateIndex
    )
    $planned = @{}
    foreach ($p in @($Transaction.State.PlannedItems)) {
        $id = [string]$p.EntryId
        if ([string]::IsNullOrWhiteSpace($id) -or $planned.ContainsKey($id)) {
            throw 'FIX9 Verify: PlannedItems has an empty or duplicate EntryId.'
        }
        $planned[$id] = $p
    }
    $completed = @{}
    $txStub = [pscustomobject]@{ Path = $Transaction.Path }
    foreach ($step in @(Read-OPAStepJournal -Transaction $txStub)) {
        if ($null -eq $step -or -not (Test-OPAMoveCompletionStep -Step $step)) { continue }
        $id = [string]$step.EntryId
        if (-not $planned.ContainsKey($id)) { continue }
        $archiveId = [string]$step.ArchiveEntryId
        if ([string]::IsNullOrWhiteSpace($archiveId)) { continue }
        if (-not $completed.ContainsKey($id)) { $completed[$id] = [pscustomobject]@{ ArchiveEntryId=''; ArchivePst=''; TargetFolderPath='' } }
        $record = $completed[$id]
        if ($record.ArchiveEntryId -and $record.ArchiveEntryId -ine $archiveId) { throw "FIX9 Verify: conflicting destination EntryIDs for '$id'." }
        $record.ArchiveEntryId = $archiveId
        if ($step.ArchivePst) {
            if ($record.ArchivePst -and $record.ArchivePst -ine [string]$step.ArchivePst) { throw "FIX9 Verify: conflicting archive PST paths for '$id'." }
            $record.ArchivePst = [string]$step.ArchivePst
        }
        if ($step.TargetFolderPath) {
            if ($record.TargetFolderPath -and $record.TargetFolderPath -ine [string]$step.TargetFolderPath) { throw "FIX9 Verify: conflicting archive folders for '$id'." }
            $record.TargetFolderPath = [string]$step.TargetFolderPath
        }
    }
    foreach ($entry in @($DuplicateIndex.Entries)) {
        if ([string]$entry.TransactionId -ne [string]$Transaction.TransactionId) { continue }
        $id = [string]$entry.SourceEntryId
        if (-not $planned.ContainsKey($id)) { continue }
        $archiveId = [string]$entry.ArchiveEntryId
        if ([string]::IsNullOrWhiteSpace($archiveId)) { continue }
        if (-not $completed.ContainsKey($id)) { $completed[$id] = [pscustomobject]@{ ArchiveEntryId=''; ArchivePst=''; TargetFolderPath='' } }
        $record = $completed[$id]
        if ($record.ArchiveEntryId -and $record.ArchiveEntryId -ine $archiveId) { throw "FIX9 Verify: journal/index destination ID mismatch for '$id'." }
        $record.ArchiveEntryId = $archiveId
        if ($entry.ArchivePst) {
            if ($record.ArchivePst -and $record.ArchivePst -ine [string]$entry.ArchivePst) { throw "FIX9 Verify: journal/index archive path mismatch for '$id'." }
            $record.ArchivePst = [string]$entry.ArchivePst
        }
        if ($entry.TargetFolderPath) {
            if ($record.TargetFolderPath -and $record.TargetFolderPath -ine [string]$entry.TargetFolderPath) { throw "FIX9 Verify: journal/index target folder mismatch for '$id'." }
            $record.TargetFolderPath = [string]$entry.TargetFolderPath
        }
    }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($id in @($completed.Keys | Sort-Object)) {
        $record = $completed[$id]
        $p = $planned[$id]
        $rows.Add([pscustomobject]@{
            SourceEntryId = $id
            ArchiveEntryId = [string]$record.ArchiveEntryId
            ArchivePst = [string]$record.ArchivePst
            TargetFolderPath = [string]$record.TargetFolderPath
            SourceFolderPath = [string]$p.SourceFolderPath
            InternetMessageId = [string]$p.InternetMessageId
            Subject = [string]$p.Subject
            Sender = [string]$p.Sender
            Size = $p.Size
        }) | Out-Null
    }
    return $rows.ToArray()
}

function Get-OPACompletedLogicalBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object[]]$CompletedMoves
    )
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $total = [int64]0
    foreach ($move in $CompletedMoves) {
        $id = [string]$move.SourceEntryId
        if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) { throw "FIX9 Accounting: missing or duplicated completed source ID '$id'." }
        if ($null -eq $move.Size) { continue }
        $size = [int64]$move.Size
        if ($size -lt 0) { throw "FIX9 Accounting: negative item size for '$id'." }
        $total = [int64]([decimal]$total + [decimal]$size)
    }
    return $total
}

function Set-OPAArchiveLogicalTelemetryFromMoves {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object[]]$CompletedMoves
    )
    $sizeByPst = @{}
    foreach ($move in $CompletedMoves) {
        $path = [string]$move.ArchivePst
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $path = [IO.Path]::GetFullPath($path)
        if (-not $sizeByPst.ContainsKey($path)) { $sizeByPst[$path] = [int64]0 }
        if ($null -ne $move.Size) {
            $sizeByPst[$path] = [int64]([decimal]$sizeByPst[$path] + [decimal][int64]$move.Size)
        }
    }
    foreach ($ap in @($Transaction.State.ArchivePsts)) {
        $key = [IO.Path]::GetFullPath([string]$ap.Path)
        $size = [int64]0
        if ($sizeByPst.ContainsKey($key)) { $size = [int64]$sizeByPst[$key] }
        if (Test-OPAStateHasKey -State $ap -Name 'LogicalAddedBytes') {
            $ap.LogicalAddedBytes = $size
        }
        else {
            $ap | Add-Member -NotePropertyName LogicalAddedBytes -NotePropertyValue $size -Force
        }
    }
}

function Test-OPAArchiveItemFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [Parameter(Mandatory=$true)][object]$Expected
    )
    if ([int]$Item.Class -ne 43) { return $false }
    if ($null -ne $Expected.Size -and [int64]$Item.Size -ne [int64]$Expected.Size) { return $false }
    if ([string]$Item.Subject -cne [string]$Expected.Subject) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$Expected.Sender) -and
        [string]$Item.SenderEmailAddress -ine [string]$Expected.Sender) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$Expected.InternetMessageId)) {
        $actualMessageId = [string](Get-OPAInternetMessageId -Item $Item)
        if ($actualMessageId -cne [string]$Expected.InternetMessageId) { return $false }
    }
    return $true
}

function Test-OPAArchiveMoves {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][object]$SourceFolder,
        [object]$ArchiveStore,
        [object[]]$ArchiveStores=@(),
        [Parameter(Mandatory=$true)][int]$ExpectedMoved,
        [int]$SourceItemsBefore = -1,
        [object[]]$ExpectedMoves=@(),
        # Kept as optional legacy parameters; FIX9 callers must pass ExpectedMoves.
        [string[]]$ExpectedEntryIds=@(),
        [string[]]$ExpectedArchiveEntryIds=@(),
        [string[]]$ExpectedTargetPaths=@()
    )
    $missing = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $targets = @{}
    $observedSource = 0
    $sourceIdsByFolder = @{}
    $sourceFoldersByPath = @{}

    $expectedRows = @($ExpectedMoves)
    if ($ExpectedMoved -ne $expectedRows.Count) {
        $missing.Add("COUNT:ExpectedMoved=$ExpectedMoved;ExpectedMoves=$($expectedRows.Count)")
    }
    $seenSource = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seenArchive = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in $expectedRows) {
        if (-not $m -or [string]::IsNullOrWhiteSpace([string]$m.SourceEntryId) -or -not $seenSource.Add([string]$m.SourceEntryId)) {
            $missing.Add('DUPLICATE_OR_EMPTY_SOURCE_ID')
        }
        if ([string]::IsNullOrWhiteSpace([string]$m.ArchiveEntryId) -or -not $seenArchive.Add([string]$m.ArchiveEntryId)) {
            $missing.Add("DUPLICATE_OR_EMPTY_ARCHIVE_ID:$([string]$m.SourceEntryId)")
        }
    }

    # Observe the source folders, rather than deriving remaining count as
    # 'SourceItemsBefore - ExpectedMoved'. One source folder is traversed once.
    foreach ($sf in @($SourceFolder)) {
        if ($null -eq $sf) { continue }
        $path = [string]$sf.FolderPath
        if ([string]::IsNullOrWhiteSpace($path)) { $missing.Add('SOURCE_FOLDER_WITHOUT_PATH'); continue }
        if ($sourceFoldersByPath.ContainsKey($path)) { continue }
        $sourceFoldersByPath[$path] = $sf
        $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $items = $null
        try {
            $items = $sf.Items
            $count = [int]$items.Count
            $observedSource += $count
            for ($i = 1; $i -le $count; $i++) {
                $probe = $null
                try {
                    $probe = $items.Item($i)
                    if ($null -ne $probe -and $probe.EntryID) { [void]$ids.Add([string]$probe.EntryID) }
                }
                finally { Release-OPAComObject -Object $probe }
            }
            $sourceIdsByFolder[$path] = $ids
        }
        catch { $missing.Add("SOURCE_FOLDER_UNREADABLE:${path}:$($_.Exception.Message)") }
        finally { Release-OPAComObject -Object $items }
    }
    foreach ($m in $expectedRows) {
        $sourcePath = [string]$m.SourceFolderPath
        if (-not $sourceIdsByFolder.ContainsKey($sourcePath)) { $missing.Add("SOURCE_FOLDER_UNKNOWN:$sourcePath"); continue }
        if ($sourceIdsByFolder[$sourcePath].Contains([string]$m.SourceEntryId)) {
            $missing.Add("STILL_IN_SOURCE:$([string]$m.SourceEntryId)")
        }
    }

    $stores = @()
    if ($ArchiveStore) { $stores += $ArchiveStore }
    $stores += @($ArchiveStores)
    $storeByPath = @{}
    foreach ($s in $stores) {
        if ($null -eq $s) { continue }
        $path = [string]$s.FilePath
        if ($path) { $storeByPath[[IO.Path]::GetFullPath($path)] = $s }
    }
    # Cache resolved destination folders; all target counts are observed once.
    $targetFolders = @{}
    $targetRoots = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($m in $expectedRows) {
            $archivePst = [string]$m.ArchivePst
            $targetPath = [string]$m.TargetFolderPath
            $id = [string]$m.SourceEntryId
            if ([string]::IsNullOrWhiteSpace($archivePst) -or [string]::IsNullOrWhiteSpace($targetPath)) {
                $missing.Add("DESTINATION_METADATA_MISSING:$id"); continue
            }
            $keyPath = [IO.Path]::GetFullPath($archivePst)
            if (-not $storeByPath.ContainsKey($keyPath)) {
                $missing.Add("ARCHIVE_STORE_MISSING:$archivePst"); continue
            }
            $folderKey = $keyPath + '|' + $targetPath
            if (-not $targetFolders.ContainsKey($folderKey)) {
                $store = $storeByPath[$keyPath]
                $root = $null
                $folder = $null
                try {
                    $root = $store.GetRootFolder()
                    $targetRoots.Add($root) | Out-Null
                    $pieces = @($targetPath -split '\\' | Where-Object { $_ })
                    if ($pieces.Count -lt 2) { throw "Invalid destination path '$targetPath'." }
                    $relativePath = [string]::Join('\', [string[]]@($pieces | Select-Object -Skip 1))
                    $folder = Get-OPAFolderByPath -Root $root -RelativePath $relativePath
                    if ($null -eq $folder) { throw "Destination folder '$targetPath' does not exist." }
                    $count = [int]$folder.Items.Count
                    $targets[$folderKey] = $count
                    $targetFolders[$folderKey] = $folder
                }
                catch { $missing.Add("ARCHIVE_FOLDER_UNREADABLE:${folderKey}:$($_.Exception.Message)") }
            }
            if (-not $targetFolders.ContainsKey($folderKey)) { continue }
            $store = $storeByPath[$keyPath]
            $target = $targetFolders[$folderKey]
            $archiveId = [string]$m.ArchiveEntryId
            $verified = $false
            $direct = $null
            try {
                $direct = $Namespace.GetItemFromID($archiveId, [string]$store.StoreID)
                if ($null -ne $direct -and [string]$direct.EntryID -ieq $archiveId -and
                    (Test-OPAArchiveItemFingerprint -Item $direct -Expected $m)) {
                    # Ensure the item actually belongs to the recorded folder.
                    $parent = $null
                    try {
                        $parent = $direct.Parent
                        $verified = ($null -ne $parent -and [string]$parent.FolderPath -ieq [string]$target.FolderPath)
                    }
                    finally { Release-OPAComObject -Object $parent }
                }
            }
            catch { $verified = $false }
            finally { Release-OPAComObject -Object $direct }
            if (-not $verified -and -not [string]::IsNullOrWhiteSpace([string]$m.InternetMessageId)) {
                # EntryIDs can become stale across Outlook sessions. A unique
                # fingerprint in the recorded destination folder is required.
                $matches = 0
                $items = $null
                try {
                    $items = $target.Items
                    $count = [int]$items.Count
                    for ($i = 1; $i -le $count; $i++) {
                        $probe = $null
                        try {
                            $probe = $items.Item($i)
                            if ($null -ne $probe -and (Test-OPAArchiveItemFingerprint -Item $probe -Expected $m)) { $matches++ }
                            if ($matches -gt 1) { break }
                        }
                        finally { Release-OPAComObject -Object $probe }
                    }
                    if ($matches -eq 1) {
                        $verified = $true
                        $warnings.Add("STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT:$id")
                    }
                }
                catch { $missing.Add("ARCHIVE_SCAN_FAILED:${id}:$($_.Exception.Message)") }
                finally { Release-OPAComObject -Object $items }
            }
            if (-not $verified) { $missing.Add("ARCHIVE_ITEM_NOT_VERIFIED:$id") }
        }
    }
    finally {
        foreach ($key in @($targetFolders.Keys)) { Release-OPAComObject -Object $targetFolders[$key] }
        foreach ($r in $targetRoots.ToArray()) { Release-OPAComObject -Object $r }
    }
    $targetCount = 0
    foreach ($v in @($targets.Values)) { $targetCount += [int]$v }
    [pscustomobject]@{
        ExpectedMoved = $ExpectedMoved
        SourceRemaining = $observedSource
        ObservedSourceCount = $observedSource
        TargetCount = $targetCount
        TargetFolders = $targets
        ExpectedEntryIdsChecked = $expectedRows.Count
        MissingEntryIds = $missing.ToArray()
        WarningEntryIds = $warnings.ToArray()
        EntryIdsVerified = ($missing.Count -eq 0)
        Verified = ($missing.Count -eq 0)
    }
}
