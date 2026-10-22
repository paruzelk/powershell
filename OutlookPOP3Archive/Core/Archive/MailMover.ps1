$script:OPAArchiveDisplayNameApplied = @{}
$script:OPAArchivePartsCache = @{}

# DuplicateIndex is append-only (.jsonl): every Add-OPADuplicateEntry writes
# one line durably, so no batched flush exists. The step journal remains the
# recovery source, and Sync-OPADuplicateIndexFromJournal heals any gap on
# the next run.
$script:OPAIndexFlushInterval = 25

# Capacity prediction uses a historical growth ratio so logical Item.Size
# does not underestimate PST growth from MIME encoding and MAPI overhead.
$script:OPAArchiveGrowthRatioDefault      = 2.0
$script:OPAArchiveGrowthRatioMin          = 1.0
$script:OPAArchiveGrowthRatioMax          = 5.0
$script:OPAArchiveGrowthRatioMinSampleBytes = 20MB
$script:OPACheckpointInterval = 25

function Get-OPAItemByEntryIdFromSourceFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][object]$SourceFolder,
        [Parameter(Mandatory=$true)][string]$EntryId
    )

    $directError = $null

    try {
        $item = $Namespace.GetItemFromID($EntryId, [string]$SourceFolder.StoreID)
        if ($null -ne $item) {
            return $item
        }
    }
    catch {
        $directError = $_.Exception.Message
    }

    # Outlook can occasionally reject GetItemFromID for an otherwise valid
    # item/store combination. Fall back to the live source collection.
    $items = $null
    try {
        $items = $SourceFolder.Items
    }
    catch {
        throw "EntryID could not be reopened and source folder Items are unavailable: $EntryId. Direct error: $directError"
    }

    $count = 0
    try { $count = [int]$items.Count } catch {}

    for ($i = 1; $i -le $count; $i++) {
        $probe = $null
        try {
            $probe = $items.Item($i)
            if ($null -eq $probe) { continue }

            if ([string]$probe.EntryID -eq $EntryId) {
                $found = $probe
                $probe = $null
                return $found
            }
        }
        catch {}
        finally { Release-OPAComObject -Object $probe }
    }

    throw "EntryID could not be reopened: $EntryId. Direct GetItemFromID error: $directError"
}

# FIX8b: fail-closed reconciliation of a crash after Outlook Move returned,
# but before the durable Move Completed event was written.
function Find-OPAInterruptedMoveInArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object]$Candidate
    )

    $sourceId = [string]$Candidate.EntryId
    $started = @($Transaction.State.Steps | Where-Object {
        [string]$_.Step -eq 'Move Started' -and [string]$_.EntryId -eq $sourceId
    } | Select-Object -Last 1)
    if ($started.Count -ne 1) { throw "Resume safety: no durable Move Started event for '$sourceId'; cannot reconcile." }
    $step = $started[0]
    $pst = [string]$step.ArchivePst
    $folderPath = [string]$step.TargetFolderPath
    $messageId = [string]$Candidate.InternetMessageId
    if ([string]::IsNullOrWhiteSpace($messageId)) {
        throw "Resume safety: missing InternetMessageId for '$sourceId'; manual reconciliation required."
    }
    if ([string]::IsNullOrWhiteSpace($pst) -or -not (Test-Path -LiteralPath $pst) -or
        [string]::IsNullOrWhiteSpace($folderPath)) {
        throw "Resume safety: archive path or destination folder from Move Started is unavailable for '$sourceId'."
    }
    # Open ONLY an existing archive; never create a new PST as part of reconciliation.
    $store = New-OPAArchivePst -Namespace $Namespace -ArchivePst $pst
    $root = $store.GetRootFolder()
    # Store display names can change after restart. Resolve only the relative
    # child path; the leading segment is the old archive store display name.
    $parts = @($folderPath -split '\\' | Where-Object { $_ })
    if ($parts.Count -lt 2) { throw "Resume safety: unexpected destination path '$folderPath'." }
    $relativePath = [string]::Join('\\', [string[]]@($parts | Select-Object -Skip 1))
    $target = Get-OPAFolderByPath -Root $root -RelativePath $relativePath
    if ($null -eq $target) { throw "Resume safety: destination folder '$folderPath' is missing." }

    $matches = New-Object System.Collections.Generic.List[object]
    $items = $target.Items
    $count = [int]$items.Count
    for ($i=1; $i -le $count; $i++) {
        $probe = $null
        try {
            $probe = $items.Item($i)
            if ($null -eq $probe -or [int]$probe.Class -ne 43) { continue }
            $foundId = [string](Get-OPAInternetMessageId -Item $probe)
            if ($foundId -cne $messageId) { continue }
            if ($null -ne $Candidate.Size -and [int64]$probe.Size -ne [int64]$Candidate.Size) { continue }
            if ([string]$probe.Subject -cne [string]$Candidate.Subject) { continue }
            if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.Sender) -and
                [string]$probe.SenderEmailAddress -ine [string]$Candidate.Sender) { continue }
            $foundEntryId = [string]$probe.EntryID
            if ([string]::IsNullOrWhiteSpace($foundEntryId)) { continue }
            $matches.Add([pscustomobject]@{ArchiveEntryId=$foundEntryId;ArchivePst=$pst;TargetFolderPath=$folderPath}) | Out-Null
            if ($matches.Count -gt 1) { break }
        }
        finally { Release-OPAComObject -Object $probe }
    }
    if ($matches.Count -ne 1) {
        throw ("Resume safety: found {0} matching archive messages for '{1}'; manual reconciliation required." -f $matches.Count,$sourceId)
    }
    return $matches[0]
}

function Get-OPAArchiveDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$AccountEmail,
        [Parameter(Mandatory=$true)][int]$Year,
        [int]$Part = 1
    )

    $email = $AccountEmail.Trim()
    if ([string]::IsNullOrWhiteSpace($email)) {
        throw 'AccountEmail is required to build the archive Outlook root-folder name.'
    }

    $lang = ''
    try { $lang = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName } catch {}
    switch ($lang) {
        'ru'    { $prefix = 'Архив';    $partSuffix = ' ч.' }
        'de'    { $prefix = 'Archiv';    $partSuffix = ' T.' }
        'fr'    { $prefix = 'Archives';  $partSuffix = ' p.' }
        default { $prefix = 'Archive';   $partSuffix = ' p.' }
    }

    if ($Part -le 1) {
        return "$prefix $email $Year"
    }
    return "$prefix $email $Year$partSuffix$Part"
}

function Set-OPAArchiveStoreDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Store,
        [Parameter(Mandatory=$true)][string]$DisplayName
    )

    $rootFolder = $null
    $storePath = ''
    try {
        try { $storePath = [IO.Path]::GetFullPath([string]$Store.FilePath) } catch {}
        $cacheKey = if ([string]::IsNullOrWhiteSpace($storePath)) { $DisplayName } else { $storePath }
        if ($script:OPAArchiveDisplayNameApplied.ContainsKey($cacheKey) -and
            [string]$script:OPAArchiveDisplayNameApplied[$cacheKey] -eq $DisplayName) {
            return $true
        }

        # Outlook Store.DisplayName is read-only in the COM object.
        # For a PST, the writable user-visible name is the root folder name.
        $rootFolder = $Store.GetRootFolder()
        if ($null -eq $rootFolder) {
            throw 'Archive PST root folder is unavailable.'
        }

        if ([string]$rootFolder.Name -ne $DisplayName) {
            $rootFolder.Name = $DisplayName
        }
        $ok = ([string]$rootFolder.Name -eq $DisplayName)
        if ($ok) { $script:OPAArchiveDisplayNameApplied[$cacheKey] = $DisplayName }
        return $ok
    }
    catch {
        Write-Warning ("Unable to set archive PST root-folder name to '{0}': {1}" -f $DisplayName,$_.Exception.Message)
        return $false
    }
    finally { Release-OPAComObject -Object $rootFolder }
}

function New-OPAArchivePst {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][string]$ArchivePst,
        [string]$AccountEmail
    )

    $store = Get-OpaStoreByPathCached -Namespace $Namespace -Path $ArchivePst
    if ($null -eq $store) {
        $target = [IO.Path]::GetFullPath($ArchivePst)
        $dir = [IO.Path]::GetDirectoryName($target)

        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if (-not (Test-Path -LiteralPath $target)) {
            # AddStoreEx StoreType: 2 = olStoreUnicode (new PSTs must be
            # Unicode to avoid the legacy ANSI size limits).
            $Namespace.AddStoreEx($target, 2)
        }
        else {
            $Namespace.AddStore($target)
        }

        # The visible store set changed; invalidate derived caches.
        $script:OPAArchivePartsCache = @{}
        $store = Get-OpaStoreByPathCached -Namespace $Namespace -Path $target
    }

    if ($null -eq $store) {
        throw "Unable to expose archive PST in Outlook: $ArchivePst"
    }

    if (-not [string]::IsNullOrWhiteSpace($AccountEmail)) {
        try {
            $year = 0
            $part = 1
            $base = [IO.Path]::GetFileNameWithoutExtension($ArchivePst)
            $m = [regex]::Match($base, '\.Archive-(?<year>\d{4})(?:-(?<part>\d{2}))?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m.Success) {
                $year = [int]$m.Groups['year'].Value
                if ($m.Groups['part'].Success) { $part = [int]$m.Groups['part'].Value }
            }
            if ($year -gt 0) {
                $displayName = Get-OPAArchiveDisplayName -AccountEmail $AccountEmail -Year $year -Part $part
                Set-OPAArchiveStoreDisplayName -Store $store -DisplayName $displayName | Out-Null
            }
        }
        catch {
            Write-Warning ("Unable to derive/apply archive PST display name for '{0}': {1}" -f $ArchivePst,$_.Exception.Message)
        }
    }

    return $store
}

function Get-OPAArchiveFolder {
    param(
        [Parameter(Mandatory=$true)][object]$ArchiveStore,
        [Parameter(Mandatory=$true)][string]$SourceFolderName,
        [string]$SourceFolderPath,
        [Parameter(Mandatory=$true)][datetime]$ReceivedTime,
        [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$Grouping = 'YearQuarter'
    )

    Get-OPAArchiveNestedFolder `
        -ArchiveStore $ArchiveStore `
        -ReceivedTime $ReceivedTime `
        -SourceFolderName $SourceFolderName `
        -SourceFolderPath $SourceFolderPath `
        -Grouping $Grouping
}

function Get-OPAArchivePartPath {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][int]$Year,
        [int]$Part = 1
    )
    $base = [IO.Path]::GetFileNameWithoutExtension($SourcePst)
    $dir = [IO.Path]::GetDirectoryName($SourcePst)
    $name = if ($Part -eq 1) { "$base.Archive-$Year.pst" } else { "$base.Archive-$Year-{0:00}.pst" -f $Part }
    Join-Path $dir $name
}

function Get-OPAArchivePstSizeBytes {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path -LiteralPath $Path) { return [int64](Get-Item -LiteralPath $Path).Length }
    return [int64]0
}

function Get-OPAArchivePstPartsOnDiskAll {
    <#
    .SYNOPSIS
        Lists all archive PST parts for a source. Results are cached per
        source for the duration of the run — destination selection runs this
        for every message and a directory scan per message is wasteful.
        Call Clear-OPAArchivePartCache after creating a new part.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst)

    try { $key = [IO.Path]::GetFullPath($SourcePst) } catch { $key = $SourcePst }
    if ($script:OPAArchivePartsCache.ContainsKey($key)) { return $script:OPAArchivePartsCache[$key] }

    $base = [IO.Path]::GetFileNameWithoutExtension($SourcePst)
    $dir = [IO.Path]::GetDirectoryName($SourcePst)
    $pattern = "$base.Archive-*.pst"
    $escapedBase = [regex]::Escape($base)
    $result = @()

    foreach ($file in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern })) {
        $m = [regex]::Match($file.Name, "^$escapedBase\.Archive-(?<year>\d{4})(?:-(?<part>\d{2,}))?\.pst$", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $m.Success) { continue }
        $result += [pscustomobject]@{
            Path = $file.FullName
            Year = [int]$m.Groups['year'].Value
            Part = if ($m.Groups['part'].Success) { [int]$m.Groups['part'].Value } else { 1 }
        }
    }

    $sorted = @($result | Sort-Object @{Expression='Year';Descending=$false}, @{Expression='Part';Descending=$false}, @{Expression='Path';Descending=$false})
    $script:OPAArchivePartsCache[$key] = $sorted
    return $sorted
}

function Clear-OPAArchivePartCache {
    param([Parameter(Mandatory=$true)][string]$SourcePst)
    try { $key = [IO.Path]::GetFullPath($SourcePst) } catch { $key = $SourcePst }
    $script:OPAArchivePartsCache.Remove($key)
}

function Get-OPAArchivePstPartsOnDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][int]$Year
    )

    @((Get-OPAArchivePstPartsOnDiskAll -SourcePst $SourcePst) |
        Where-Object { [int]$_.Year -eq $Year } |
        Sort-Object Part -Unique)
}

function Get-OPAArchiveSafeCapacityBytes {
    param(
        [Parameter(Mandatory=$true)][double]$MaxArchivePstSizeGB,
        [Parameter(Mandatory=$true)][double]$SafetyMarginGB
    )
    $safeBytes = [int64](($MaxArchivePstSizeGB - $SafetyMarginGB) * 1GB)
    if ($safeBytes -le 0) { throw 'MaxArchivePstSizeGB minus SafetyMarginGB must be greater than zero.' }
    return $safeBytes
}

# FIX12: a post-Move physical measurement has three distinct outcomes.
# Physical growth inside a PST is not synchronous with Outlook COM Move;
# this is a guard, not a guarantee that a PST can never cross a hard limit.
function Get-OPAArchivePostMoveCapacityAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateRange(0,9223372036854775807)][int64]$PhysicalSizeBytes,
        [Parameter(Mandatory=$true)][double]$MaxArchivePstSizeGB,
        [Parameter(Mandatory=$true)][double]$SafetyMarginGB
    )

    $safeBytes = Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB
    $hardBytes = [int64]($MaxArchivePstSizeGB * 1GB)
    if ($PhysicalSizeBytes -gt $hardBytes) { return 'HardLimitExceeded' }
    if ($PhysicalSizeBytes -gt $safeBytes) { return 'RolloverNext' }
    return 'WithinSafe'
}

function Test-OPAItemFitsArchiveCapacity {
    param(
        [Parameter(Mandatory=$true)][int64]$ItemSize,
        [Parameter(Mandatory=$true)][double]$MaxArchivePstSizeGB,
        [Parameter(Mandatory=$true)][double]$SafetyMarginGB
    )
    return ($ItemSize -le (Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB))
}

function Get-OPAArchivePstGrowthRatio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][string]$ArchivePst
    )

    # Item.Size is a logical size; the physical PST file grows by more due
    # to MIME encoding, index entries and MAPI page allocations. Historical
    # telemetry on the same PST gives a reliable per-year ratio once enough
    # samples have accumulated. Below the sample threshold the default is
    # returned so prediction stays conservative but never wild.
    $entry = @($Transaction.State.ArchivePsts |
        Where-Object { [string]$_.Path -ieq $ArchivePst } |
        Select-Object -First 1)
    if ($entry.Count -eq 0) { return $script:OPAArchiveGrowthRatioDefault }

    $e = $entry[0]
    $logical  = [int64]0
    $physical = [int64]0
    if ($e.PSObject.Properties.Name -contains 'LogicalAddedBytes') {
        try { $logical = [int64]$e.LogicalAddedBytes } catch {}
    }
    if ($e.PSObject.Properties.Name -contains 'PhysicalGrowthBytes') {
        try { $physical = [int64]$e.PhysicalGrowthBytes } catch {}
    }

    if ($logical -lt $script:OPAArchiveGrowthRatioMinSampleBytes -or $physical -le 0) {
        return $script:OPAArchiveGrowthRatioDefault
    }

    $ratio = [double]$physical / [double]$logical
    if ($ratio -lt $script:OPAArchiveGrowthRatioMin) { $ratio = $script:OPAArchiveGrowthRatioMin }
    if ($ratio -gt $script:OPAArchiveGrowthRatioMax) { $ratio = $script:OPAArchiveGrowthRatioMax }
    return $ratio
}
function Get-OPAArchiveDestination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][datetime]$ReceivedTime,
        [int64]$ItemSize = 0,
        [double]$MaxArchivePstSizeGB = 10,
        [double]$SafetyMarginGB = 0.5,
        [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$ArchiveGrouping = 'YearQuarter',
        [string]$SourceFolderName,
        [string]$SourceFolderPath,
        [string]$AccountEmail
    )

    $year = $ReceivedTime.Year
    $safeBytes = Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB
    if ($ItemSize -gt $safeBytes) { throw "Message size $ItemSize bytes exceeds safe archive PST capacity $safeBytes bytes." }

    # A persisted transaction can reference an archive part that was moved or
    # deleted after interruption. Treat this as a recovery error; never silently
    # recreate a missing PST and assume it contains the previous messages.
    $registered = @($Transaction.State.ArchivePsts | Where-Object { [int]$_.Year -eq $year })
    foreach ($existing in $registered) {
        if ([string]::IsNullOrWhiteSpace([string]$existing.Path) -or
            -not (Test-Path -LiteralPath ([string]$existing.Path) -PathType Leaf)) {
            throw ("Capacity safety: registered archive part is missing from disk: '{0}'." -f [string]$existing.Path)
        }
    }
    $states = @($registered | ForEach-Object { [pscustomobject]@{Path=[string]$_.Path;Year=$year;Part=[int]$_.Part} })

    # Reconcile transaction state with archive PSTs already present on disk.
    # A new transaction must never recreate/overwrite an existing same-year part.
    foreach ($diskState in @(Get-OPAArchivePstPartsOnDisk -SourcePst $SourcePst -Year $year)) {
        if (@($states | Where-Object { [string]$_.Path -ieq [string]$diskState.Path }).Count -eq 0) {
            $states += $diskState
        }
    }

    # Reuse the Store COM object obtained while creating the first part.
    # Reopening it within the same selection would duplicate Outlook COM work.
    $store = $null
    if ($states.Count -eq 0) {
        # Do not create an empty first PST for an item whose predicted physical
        # growth exceeds the safe capacity of even a fresh part.
        $freshEstimate = [double]$ItemSize * [double]$script:OPAArchiveGrowthRatioDefault
        if ($freshEstimate -gt [double]$safeBytes) {
            throw ("Capacity safety: estimated physical growth {0:N0} bytes exceeds safe archive PST capacity {1:N0} bytes." -f $freshEstimate,$safeBytes)
        }
        $path = Get-OPAArchivePartPath -SourcePst $SourcePst -Year $year -Part 1
        $store = New-OPAArchivePst -Namespace $Namespace -ArchivePst $path -AccountEmail $AccountEmail
        Register-OPAArchivePstInTransaction -Transaction $Transaction -ArchivePst $path -Year $year -Part 1 -PhysicalSizeBeforeBytes (Get-OPAArchivePstSizeBytes -Path $path)
        Clear-OPAArchivePartCache -SourcePst $SourcePst
        $states = @([pscustomobject]@{Path=$path;Year=$year;Part=1})
    }

    $states = @($states | Sort-Object Part -Descending)
    $highest = if ($states.Count -gt 0) { $states[0] } else { $null }
    $chosen = $null

    # Ratio used for both the fit test on the current part and the guard
    # against pathological part creation below.
    $growthRatio = $script:OPAArchiveGrowthRatioDefault
    $estimatedPhysicalGrowth = [int64]$ItemSize

    if ($highest) {
        $growthRatio = Get-OPAArchivePstGrowthRatio -Transaction $Transaction -ArchivePst ([string]$highest.Path)
        $estimatedPhysicalGrowth = [int64][Math]::Ceiling([double]$ItemSize * $growthRatio)
        $size = Get-OPAArchivePstSizeBytes -Path ([string]$highest.Path)
        if (($size + $estimatedPhysicalGrowth) -le $safeBytes) {
            $chosen = $highest
        }
    }

    if ($null -eq $chosen) {
        # A new part starts at size 0. If the estimated physical growth
        # already exceeds the safe capacity, no new part will hold this
        # item -- raise instead of creating empty parts indefinitely. The
        # caller's catch block classifies this as a Skipped item.
        if ($estimatedPhysicalGrowth -gt $safeBytes) {
            throw ("Item logical size {0} bytes (estimated physical growth {1} at ratio {2}) exceeds safe archive PST capacity {3} bytes." -f `
                $ItemSize, $estimatedPhysicalGrowth, [Math]::Round($growthRatio, 2), $safeBytes)
        }
        $part = if ($highest) { [int]$highest.Part + 1 } else { 1 }
        $path = Get-OPAArchivePartPath -SourcePst $SourcePst -Year $year -Part $part
        $store = New-OPAArchivePst -Namespace $Namespace -ArchivePst $path -AccountEmail $AccountEmail
        Register-OPAArchivePstInTransaction -Transaction $Transaction -ArchivePst $path -Year $year -Part $part -PhysicalSizeBeforeBytes (Get-OPAArchivePstSizeBytes -Path $path)
        Clear-OPAArchivePartCache -SourcePst $SourcePst
        $chosen = [pscustomobject]@{Path=$path;Year=$year;Part=$part}
    }
    else {
        # First-part creation already opened this Store. For existing parts
        # it has not yet been opened, so initialize it exactly once.
        if ($null -eq $store) {
            $store = New-OPAArchivePst -Namespace $Namespace -ArchivePst ([string]$chosen.Path) -AccountEmail $AccountEmail
        }

        # Register a pre-existing archive PST in this transaction only once,
        # when this transaction first starts using it.
        $alreadyRegistered = @($Transaction.State.ArchivePsts | Where-Object { [string]$_.Path -ieq [string]$chosen.Path }).Count -gt 0
        if (-not $alreadyRegistered) {
            $sizeNow = Get-OPAArchivePstSizeBytes -Path ([string]$chosen.Path)
            $Transaction.State.ArchivePsts = @($Transaction.State.ArchivePsts) + [pscustomobject]@{
                Path = [string]$chosen.Path
                Year = [int]$chosen.Year
                Part = [int]$chosen.Part
                CreatedAt = (Get-Date).ToString('o')
                PhysicalSizeBeforeBytes = [int64]$sizeNow
                PhysicalSizeAfterBytes = [int64]$sizeNow
                PhysicalGrowthBytes = [int64]0
                LogicalAddedBytes = [int64]0
                LastMeasuredAt = (Get-Date).ToString('o')
                PhysicalSizeBaselineCaptured = $true
            }
        }
    }

    $Transaction.State.ArchivePst = [string]$chosen.Path
    $Transaction.State.CurrentArchivePst = [string]$chosen.Path

    $target = Get-OPAArchiveFolder -ArchiveStore $store -SourceFolderName $SourceFolderName -SourceFolderPath $SourceFolderPath -ReceivedTime $ReceivedTime -Grouping $ArchiveGrouping
    # PST initialization and folder creation allocate physical pages too.
    # Recheck against the measured baseline before permitting Outlook Move.
    $initializedSize = Get-OPAArchivePstSizeBytes -Path ([string]$chosen.Path)
    if (([double]$initializedSize + [double]$estimatedPhysicalGrowth) -gt [double]$safeBytes) {
        $remainingCapacity = [Math]::Max([int64]0, ([int64]$safeBytes - [int64]$initializedSize))
        throw ("Capacity safety: destination '{0}' has only {1:N0} bytes of safe capacity after initialization; estimated physical growth is {2:N0} bytes." -f [string]$chosen.Path,$remainingCapacity,$estimatedPhysicalGrowth)
    }
    [pscustomobject]@{ Store=$store; Folder=$target; Path=[string]$chosen.Path; Year=$year; Part=[int]$chosen.Part }
}

function Get-OPASourceFolderByPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$SourceFolders,
        [Parameter(Mandatory=$true)][string]$FolderPath
    )

    foreach ($folder in @($SourceFolders)) {
        try {
            if ([string]$folder.FolderPath -ieq $FolderPath) { return $folder }
        } catch {}
    }
    return $null
}


function Save-OPAFlushDirtyIndexes {
    <#
    .SYNOPSIS
        Legacy no-op. Under the append-only DuplicateIndex (.jsonl) design,
        every entry is already written durably by Add-OPADuplicateEntry, so
        no batched flush exists. This stub is retained so external callers
        and existing tests keep working; it deliberately does nothing.
    #>
    param([Parameter(Mandatory=$true)][hashtable]$Dirty)
    return
}

function Move-OPAItemsWithLimit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][Alias('SourceFolder')][object]$SourceFolders,
        [Parameter(Mandatory=$true)][object]$Transaction,
        [ValidateRange(1,2147483647)][int]$Limit,
        [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$ArchiveGrouping = 'YearQuarter',
        [Nullable[datetime]]$OlderThanCutoff,
        [double]$MaxArchivePstSizeGB = 10,
        [double]$SafetyMarginGB = 0.5,
        [switch]$Resume
    )

    # SourceFolder may be a single Outlook Folder or an array. The array form
    # is the production path: one transaction spans the complete POP3 PST tree.
    $sourceFolders = @($SourceFolders) | Where-Object { $_ }
    if ($sourceFolders.Count -eq 0) { return [int]$Transaction.State.Executed }

    # --- Shared duplicate index (one physical file per source directory) ---
    $allIndexes = @{}
    $sharedIndex = $null
    $existingArchivePaths = @(Get-OPAArchivePstPartsOnDiskAll -SourcePst ([string]$Transaction.State.SourcePst))
    if ($existingArchivePaths.Count -gt 0) {
        $indexArchivePst = [string]$existingArchivePaths[0].Path
        $legacyIndexPath = Get-OPADuplicateIndexPath -ArchivePst $indexArchivePst
        $journalIndexPath = Get-OPADuplicateIndexJournalPath -ArchivePst $indexArchivePst
        # Schema 1.2 uses DuplicateIndex.jsonl as the authoritative append-only
        # index. The legacy DuplicateIndex.json base is optional; Import-OPA
        # merges either file (or both). Refuse only when neither exists.
        if (-not (Test-Path -LiteralPath $legacyIndexPath) -and
            -not (Test-Path -LiteralPath $journalIndexPath)) {
            throw "Existing archive PSTs were found for source '$($Transaction.State.SourcePst)', but neither DuplicateIndex.json nor DuplicateIndex.jsonl exists. Refusing to start a new Archive transaction because previously archived messages cannot be excluded safely."
        }
        $sharedIndex = Import-OPADuplicateIndex -ArchivePst ([string]$existingArchivePaths[0].Path)
        # Heal from the durable step journal before selecting candidates: any
        # move journaled but not yet index-flushed (crashed run) is re-added.
        [void](Sync-OPADuplicateIndexFromJournal -Transaction $Transaction -Index $sharedIndex -ArchivePst ([string]$existingArchivePaths[0].Path))
        foreach ($p in @($existingArchivePaths | ForEach-Object { [string]$_.Path })) { $allIndexes[$p] = $sharedIndex }
    }
    elseif ($Resume) {
        foreach ($ap in @($Transaction.State.ArchivePsts)) {
            if ($ap.Path -and (Test-Path -LiteralPath ([string]$ap.Path))) {
                $sharedIndex = Import-OPADuplicateIndex -ArchivePst ([string]$ap.Path)
                [void](Sync-OPADuplicateIndexFromJournal -Transaction $Transaction -Index $sharedIndex -ArchivePst ([string]$ap.Path))
                $allIndexes[[string]$ap.Path] = $sharedIndex
                break
            }
        }
    }

    $sourcePstForIndex = [IO.Path]::GetFullPath([string]$Transaction.State.SourcePst)
    $indexEntries = @($allIndexes.Values | Select-Object -Unique | ForEach-Object { $_.Entries } | Where-Object {
        try { [IO.Path]::GetFullPath([string]$_.SourcePst) -ieq $sourcePstForIndex } catch { $false }
    })

    if ($Resume) {
        $duplicateIds = @($indexEntries | Where-Object { [string]$_.TransactionId -eq [string]$Transaction.TransactionId } | ForEach-Object { [string]$_.SourceEntryId } | Where-Object { $_ } | Select-Object -Unique)
    } else {
        $duplicateIds = @($indexEntries | ForEach-Object { [string]$_.SourceEntryId } | Where-Object { $_ } | Select-Object -Unique)
    }

    # --- Candidate pool ---
    if ($Resume) {
        # FIX8: A resumed transaction may move only items persisted in its
        # original plan. Never substitute new candidates to satisfy -Limit.
        $planned = @($Transaction.State.PlannedItems)
        $planIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($p in $planned) {
            $id = [string]$p.EntryId
            if ([string]::IsNullOrWhiteSpace($id) -or -not $planIds.Add($id)) {
                throw 'Resume safety: PlannedItems contains an empty or duplicate EntryId.'
            }
        }
        if ($planned.Count -ne [int]$Transaction.State.Planned -or
            $planned.Count -gt $Limit) {
            throw 'Resume safety: persisted PlannedItems count does not match transaction Planned/Limit.'
        }

        # Completion entries must have a destination EntryID. A marker without
        # an archive ID is not enough to claim a successful, verified move.
        $completion = Get-OPAResumeCompletionState -Transaction $Transaction -DuplicateIndex ([pscustomobject]@{ Entries=$indexEntries })
        if (@($completion.SourceEntryIds).Count -ne @($completion.ArchiveEntryIds).Count) {
            throw 'Resume safety: completion journal contains moves without unique destination EntryIDs; manual reconciliation required.'
        }
        $doneSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($id in @($completion.SourceEntryIds)) { [void]$doneSet.Add([string]$id) }
        $candidates = @($planned | Where-Object { -not $doneSet.Contains([string]$_.EntryId) })
        $candidatePool = @($candidates)
        $Transaction.State.Executed = $doneSet.Count
    }
    else {
        $candidateRows = New-Object System.Collections.Generic.List[object]
        foreach ($folder in $sourceFolders) {
            try {
                foreach ($candidate in @(Get-OPAArchiveCandidates -SourceFolder $folder -Limit ([Math]::Max($Limit * 3, $Limit + 20)) -ExcludeEntryIds $duplicateIds -OlderThanCutoff $OlderThanCutoff)) {
                    $candidateRows.Add($candidate) | Out-Null
                }
            }
            catch {
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'FolderSelectionSkipped' -Message ("Folder selection failed and was skipped: {0} | {1}" -f [string]$folder.FolderPath,$_.Exception.Message) -TargetFolderPath $null
            }
        }

        # Keep a replacement pool so a locked/unavailable message does not
        # consume the requested move limit. The transaction checkpoint itself
        # stores only the controlled batch; the pool is used during this run.
        $candidatePool = @($candidateRows | Sort-Object ArchiveDate,EntryID)
        $candidates = @($candidatePool | Select-Object -First $Limit)
        $Transaction.State.PlannedItems = @($candidates | ForEach-Object {
            [pscustomobject]@{
                EntryId=[string]$_.EntryID; Subject=[string]$_.Subject
                ReceivedTime=([datetime]$_.ArchiveDate).ToString('o')
                ArchiveDate=([datetime]$_.ArchiveDate).ToString('o')
                SourceFolderPath=[string]$_.SourceFolderPath
                SourceFolderName=[string]$_.FolderName
                InternetMessageId=[string]$_.InternetMessageId
                Sender=[string]$_.Sender
                Size=if($null -ne $_.Size){[int64]$_.Size}else{$null}
            }
        })
        Set-OPAArchiveTransactionCount -Transaction $Transaction -Planned $candidates.Count -Executed 0 -Verified 0
        # 'Planned' always rewrites the checkpoint (PlannedItems must be durable).
        Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Planned' -Step 'Candidates' -Message ("Selected {0} oldest non-duplicate items across {1} folders" -f $candidates.Count,$sourceFolders.Count)
    }

    $executed = [int]$Transaction.State.Executed
    $executedAtPhaseStart = $executed
    $recoveredMovesThisRun = 0
    $skippedList = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($Transaction.State.SkippedItems)) { $skippedList.Add($s) | Out-Null }

    $movesSinceFlush = 0
    $safeCapacityBytes = Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB

    $candidateIndex = 0
    while ($candidateIndex -lt $candidatePool.Count -and $executed -lt $Limit) {
        $candidate = $candidatePool[$candidateIndex]
        $candidateIndex++

        $folderPath = [string]$candidate.SourceFolderPath
        if ([string]::IsNullOrWhiteSpace($folderPath) -and $candidate.FolderPath) { $folderPath = [string]$candidate.FolderPath }
        $source = Get-OPASourceFolderByPath -SourceFolders $sourceFolders -FolderPath $folderPath

        if ($Resume -and $null -eq $source) {
            throw ("Resume safety: source folder '{0}' is unavailable; cannot verify planned item '{1}'." -f $folderPath, [string]$candidate.EntryId)
        }
        if ($null -eq $source) {
            $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason='SourceFolderUnavailable'; Message='Source folder is no longer available'; Time=(Get-Date).ToString('o')}) | Out-Null
            Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Source folder unavailable: {0}" -f $folderPath) -EntryId ([string]$candidate.EntryId) -ReceivedTime ([datetime]$candidate.ReceivedTime)
            continue
        }

        $itemSize = 0
        try { if ($candidate.Size) { $itemSize = [int64]$candidate.Size } } catch {}

        # Per-item capacity check: one oversized message must skip, not abort
        # the whole batch (Get-OPAArchiveDestination keeps a throw as backstop).
        if ($itemSize -gt $safeCapacityBytes) {
            $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason='ExceedsArchiveCapacity'; Message="Message size $itemSize bytes exceeds safe archive capacity $safeCapacityBytes bytes"; Time=(Get-Date).ToString('o')}) | Out-Null
            Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Item exceeds archive capacity and was skipped: {0} ({1} bytes)" -f [string]$candidate.Subject,$itemSize) -EntryId ([string]$candidate.EntryId) -ReceivedTime ([datetime]$candidate.ReceivedTime)
            continue
        }

        $item = $null; $moved = $null; $moveCompleted = $false
        try {
            try { $item = Get-OPAItemByEntryIdFromSourceFolder -Namespace $Namespace -SourceFolder $source -EntryId ([string]$candidate.EntryId) }
            catch {
                if ($Resume) {
                    # A crash can occur after COM Move but before Move Completed.
                    # Only reconcile from the persisted destination, with a unique
                    # fingerprint match; otherwise stop without retrying Move.
                    $reconciled = Find-OPAInterruptedMoveInArchive -Namespace $Namespace -Transaction $Transaction -Candidate $candidate
                    $archiveId = [string]$reconciled.ArchiveEntryId
                    $archivePst = [string]$reconciled.ArchivePst
                    $index = if ($allIndexes.ContainsKey($archivePst)) { $allIndexes[$archivePst] } elseif ($sharedIndex) { $sharedIndex } else { Import-OPADuplicateIndex -ArchivePst $archivePst }
                    $allIndexes[$archivePst] = $index
                    # Persist the durable completion BEFORE updating auxiliary index.
                    Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Move Completed' -Message 'ReconciledFromArchive after interrupted Move' -EntryId ([string]$candidate.EntryId) -ArchiveEntryId $archiveId -ArchivePst $archivePst -TargetFolderPath ([string]$reconciled.TargetFolderPath) -SourceFolderPath $folderPath -ReceivedTime ([datetime]$candidate.ReceivedTime)
                    if (-not (Test-OPADuplicateEntry -Index $index -SourceEntryId ([string]$candidate.EntryId))) {
                        Add-OPADuplicateEntry -Index $index -SourceEntryId $candidate.EntryId -ArchiveEntryId $archiveId -SourceFolderPath $folderPath -TargetFolderPath ([string]$reconciled.TargetFolderPath) -ReceivedTime ([datetime]$candidate.ReceivedTime) -Subject $candidate.Subject -TransactionId $Transaction.TransactionId -TransactionLimit ([int]$Transaction.State.Limit) -ArchiveGrouping $Transaction.State.ArchiveGrouping -SourcePst $Transaction.State.SourcePst -OlderThanMonths ([int]$Transaction.State.OlderThanMonths) -ArchiveCutoff ([string]$Transaction.State.ArchiveCutoff) -ArchivePst $archivePst
                    }
                    $executed++
                    $recoveredMovesThisRun++
                    $logical = [int64]$Transaction.State.LogicalFreedBytes + [int64]$itemSize
                    Set-OPAArchiveTransactionCount -Transaction $Transaction -Planned ([int]$Transaction.State.Planned) -Executed $executed -Verified 0
                    Set-OPAArchiveTransactionStorageStats -Transaction $Transaction -LogicalFreedBytes $logical -SourcePstSizeAfterBytes ([int64](Get-Item -LiteralPath ([string]$Transaction.State.SourcePst)).Length)
                    Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'ReconciledFromArchive' -Message 'Verified interrupted Move in destination archive' -EntryId ([string]$candidate.EntryId) -ArchiveEntryId $archiveId -ArchivePst $archivePst -TargetFolderPath ([string]$reconciled.TargetFolderPath) -SourceFolderPath $folderPath -ReceivedTime ([datetime]$candidate.ReceivedTime) -WriteCheckpoint
                    continue
                }
                $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason='Unavailable'; Message=$_.Exception.Message; Time=(Get-Date).ToString('o')}) | Out-Null
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Item unavailable/locked: {0} | {1}" -f [string]$candidate.Subject,$_.Exception.Message) -EntryId ([string]$candidate.EntryId) -ReceivedTime ([datetime]$candidate.ReceivedTime)
                continue
            }

            if ($null -eq $item) {
                if ($Resume) {
                    throw ("Resume safety: planned source item '{0}' not found. Check whether an interrupted Move reached the archive before proceeding." -f [string]$candidate.EntryId)
                }
                continue
            }
            if ([int]$item.Class -ne 43) {
                $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason='NotMailItem'; Message='Selected object is not a MailItem'; Time=(Get-Date).ToString('o')}) | Out-Null
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Not a MailItem: {0}" -f [string]$candidate.Subject) -EntryId ([string]$candidate.EntryId) -ReceivedTime ([datetime]$candidate.ReceivedTime)
                continue
            }

            $dt = [datetime]$candidate.ReceivedTime
            $dest = $null
            try {
                $dest = Get-OPAArchiveDestination -Namespace $Namespace -Transaction $Transaction -SourcePst $Transaction.State.SourcePst -ReceivedTime $dt -ItemSize $itemSize -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB -ArchiveGrouping $ArchiveGrouping -SourceFolderName ([string]$source.Name) -SourceFolderPath $folderPath -AccountEmail ([string]$Transaction.State.AccountEmail)
            }
            catch {
                $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason=$(if ($_.Exception.Message -match 'exceeds safe archive PST capacity') { 'ExceedsArchiveCapacity' } else { 'DestinationFailed' }); Message=$_.Exception.Message; Time=(Get-Date).ToString('o')}) | Out-Null
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Destination selection failed and item was skipped: {0} | {1}" -f [string]$candidate.Subject,$_.Exception.Message) -EntryId ([string]$candidate.EntryId) -ReceivedTime $dt
                continue
            }

            $index = $null
            if ($allIndexes.ContainsKey($dest.Path)) { $index = $allIndexes[$dest.Path] }
            elseif ($sharedIndex) { $index = $sharedIndex; $allIndexes[$dest.Path] = $index }
            else { $index = Import-OPADuplicateIndex -ArchivePst $dest.Path; $allIndexes[$dest.Path] = $index }
            if (Test-OPADuplicateEntry -Index $index -SourceEntryId ([string]$candidate.EntryId)) { continue }

            Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Move Started' -Message ("Starting Move: {0}" -f [string]$candidate.Subject) -EntryId $candidate.EntryId -ArchivePst $dest.Path -TargetFolderPath $dest.Folder.FolderPath -SourceFolderPath $folderPath -ReceivedTime $dt

            try {
                $moved = $item.Move($dest.Folder)
                $moveCompleted = $true
            }
            catch {
                # A single item may be locked by an open Inspector, another
                # Outlook operation, a provider restriction, or transient COM
                # state. Treat it as skippable work; never abort the batch.
                $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason='MoveFailed'; Message=$_.Exception.Message; Time=(Get-Date).ToString('o')}) | Out-Null
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Move skipped: {0} | {1}" -f [string]$candidate.Subject,$_.Exception.Message) -EntryId ([string]$candidate.EntryId) -ReceivedTime $dt -ArchivePst $dest.Path -TargetFolderPath $dest.Folder.FolderPath
                continue
            }

            $archiveId = [string]$moved.EntryID
            if ([string]::IsNullOrWhiteSpace($archiveId)) {
                throw "Move succeeded but Outlook returned no destination EntryID for source $($candidate.EntryId)."
            }

            Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Move Completed' -Message ("Move completed: {0}" -f [string]$candidate.Subject) -EntryId $candidate.EntryId -ArchiveEntryId $archiveId -ArchivePst $dest.Path -TargetFolderPath $dest.Folder.FolderPath -SourceFolderPath $folderPath -ReceivedTime $dt

            $executed++
            try {
                Add-OPADuplicateEntry -Index $index -SourceEntryId $candidate.EntryId -ArchiveEntryId $archiveId -SourceFolderPath $folderPath -TargetFolderPath $dest.Folder.FolderPath -ReceivedTime $dt -Subject $candidate.Subject -TransactionId $Transaction.TransactionId -TransactionLimit ([int]$Transaction.State.Limit) -ArchiveGrouping $Transaction.State.ArchiveGrouping -SourcePst $Transaction.State.SourcePst -OlderThanMonths ([int]$Transaction.State.OlderThanMonths) -ArchiveCutoff ([string]$Transaction.State.ArchiveCutoff) -ArchivePst $dest.Path
            }
            catch {
                Sync-OPAStepJournalStreams
                throw ("DuplicateIndex append failed after successful Move for '{0}': {1}" -f [string]$candidate.EntryId,$_.Exception.Message)
            }

            $logicalAdded = if($candidate.Size){[int64]$candidate.Size}else{0}
            $archivePhysicalSize = Get-OPAArchivePstSizeBytes -Path $dest.Path
            Update-OPAArchivePstTelemetry -Transaction $Transaction -ArchivePst $dest.Path -PhysicalSizeBytes $archivePhysicalSize -LogicalAddedBytes $logicalAdded
            $safeCapacityBytes = Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB
            $postMoveCapacityAction = Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes $archivePhysicalSize -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB
            $capacityExceededAfterMove = ($postMoveCapacityAction -ne 'WithinSafe')
            $logical = [int64]$Transaction.State.LogicalFreedBytes + $logicalAdded
            $sourceSize = [int64]0; try { $sourceSize = [int64](Get-Item -LiteralPath ([string]$Transaction.State.SourcePst)).Length } catch {}
            Set-OPAArchiveTransactionCount -Transaction $Transaction -Planned ([int]$Transaction.State.Planned) -Executed $executed -Verified 0
            Set-OPAArchiveTransactionStorageStats -Transaction $Transaction -LogicalFreedBytes $logical -SourcePstSizeAfterBytes $sourceSize

            # Durability order: the Move is complete, then the step journal is
            # appended (durable, cheap, on every move). The full DuplicateIndex
            # rewrite is batched; Sync-OPADuplicateIndexFromJournal heals any
            # crash gap on the next run.
            Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step ("Move {0}/{1}" -f $executed,$Limit) -Message ("{0} | Source={1} | Target={2} | ArchivePhysical={3:N2} MB; SafeCapacityExceeded={4}" -f [string]$candidate.Subject,$folderPath,$dest.Folder.FolderPath,([double]$archivePhysicalSize/1MB),$capacityExceededAfterMove) -EntryId $candidate.EntryId -ArchiveEntryId $archiveId -ArchivePst $dest.Path -TargetFolderPath $dest.Folder.FolderPath -SourceFolderPath $folderPath -ReceivedTime $dt

            $movesSinceFlush++
            if ($movesSinceFlush -ge $script:OPAIndexFlushInterval) {
                # Full durability boundary: flush the journal to disk, then
                # persist DuplicateIndex and the transaction checkpoint.
                Sync-OPAStepJournalStreams
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Checkpoint' -Message ("Periodic checkpoint at {0}/{1} moves" -f $executed,$Limit) -WriteCheckpoint
                $movesSinceFlush = 0
            }
            if ($postMoveCapacityAction -eq 'HardLimitExceeded') {
                # The Move has already completed and is journaled. The script
                # cannot undo Outlook's physical allocation, so stop rather
                # than concealing the hard-limit breach or moving more items.
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'VerificationFailed' -Step 'Archive Hard Capacity Exceeded' -Message ("Physical archive size {0:N2} MB exceeds configured hard maximum {1:N2} MB. Stop; inspect this PST before resuming." -f ([double]$archivePhysicalSize/1MB),([double]$MaxArchivePstSizeGB*1024)) -ArchivePst $dest.Path -WriteCheckpoint
                throw ("Capacity safety: archive '{0}' exceeds configured maximum after Move ({1:N2} MB)." -f $dest.Path,([double]$archivePhysicalSize/1MB))
            }
            if ($postMoveCapacityAction -eq 'RolloverNext') {
                # A post-Move file size can exceed the conservative prediction.
                # Do not abandon the remaining planned messages: destination
                # selection sees the full physical PST and rolls to part -02.
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Capacity Rollover Required' -Message ("Physical archive size {0:N2} MB exceeded safe capacity {1:N2} MB after Move; next item will use a new part." -f ([double]$archivePhysicalSize/1MB),([double]$safeCapacityBytes/1MB)) -ArchivePst $dest.Path
                continue
            }
        }
        catch {
            # Once Outlook.Move() has returned successfully, the source item
            # is no longer safely classifiable as "skipped". A failure in
            # post-move durability must stop the batch and be recovered from
            # DuplicateIndex/the step journal; silently counting it as skipped
            # could allow a duplicate move on a later run.
            if ($moveCompleted) {
                # Move succeeded; make its journal event durable before unwinding.
                Sync-OPAStepJournalStreams
                throw
            }

            if ($Resume) { throw }

            # Pre-move errors are isolated to the current item. The transaction
            # remains resumable and the next candidate can continue.
            $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason='Unexpected'; Message=$_.Exception.Message; Time=(Get-Date).ToString('o')}) | Out-Null
            Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Item skipped after unexpected error: {0} | {1}" -f [string]$candidate.Subject,$_.Exception.Message) -EntryId ([string]$candidate.EntryId) -ReceivedTime ([datetime]$candidate.ReceivedTime)
        }
        finally {
            Release-OPAComObject -Object $moved
            Release-OPAComObject -Object $item
        }
    }

    # Final durability boundary before verification.
    Sync-OPAStepJournalStreams

    if ($skippedList.Count -gt $script:OPASkippedInlineLimit) {
        $Transaction.State.SkippedItems = @($skippedList | Select-Object -Last $script:OPASkippedInlineLimit)
    } else {
        $Transaction.State.SkippedItems = $skippedList.ToArray()
    }
    $skippedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in @($Transaction.State.SkippedEntryIds)) { if ($id) { [void]$skippedIds.Add([string]$id) } }
    foreach ($item in $skippedList.ToArray()) { $id=[string]$item.EntryId; if ($id) { [void]$skippedIds.Add($id) } }
    $Transaction.State.SkippedEntryIds = @($skippedIds)
    $Transaction.State.Skipped = $skippedIds.Count

    # Record how many moves this invocation actually performed,
    # so ArchiveReport can compute a real throughput figure.
    $performance = Ensure-OPATransactionPerformance -TransactionState $Transaction.State
    $phaseCompleted = [int]($executed - $executedAtPhaseStart)
    Set-OPAPerformanceValue -Performance $performance -Name 'MovesThisRun' -Value $phaseCompleted
    Set-OPAPerformanceValue -Performance $performance -Name 'RecoveredMovesThisRun' -Value $recoveredMovesThisRun
    Set-OPAPerformanceValue -Performance $performance -Name 'NewMovesThisRun' -Value ([Math]::Max(0, $phaseCompleted - $recoveredMovesThisRun))
    return $executed
}
# Backward-compat alias. New callers should use New-OPAArchivePst.
Set-Alias -Name Ensure-OPAArchivePst -Value New-OPAArchivePst -Scope Script
