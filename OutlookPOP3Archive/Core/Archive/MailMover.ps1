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
        [string]$AccountEmail,
        [switch]$ARCH3oRequireNewUnusedPst
    )

    # ARCH3o: original creator must NEVER open an existing/mounted archive
    # when the operator explicitly pins a fresh Year 2020 Part2. Default
    # behavior is identical for all legacy callers without this switch.
    if($ARCH3oRequireNewUnusedPst){
        if([IO.File]::Exists($ArchivePst) -or [IO.Directory]::Exists($ArchivePst)){
            throw 'ARCH3o original New-OPAArchivePst requires a NEW absent target.'
        }
        if($null -ne (Get-OpaStoreByPathCached -Namespace $Namespace -Path $ArchivePst)){
            throw 'ARCH3o original New-OPAArchivePst refuses a mounted existing store.'
        }
    }
    $store = Get-OpaStoreByPathCached -Namespace $Namespace -Path $ArchivePst
    if ($null -eq $store) {
        $target = [IO.Path]::GetFullPath($ArchivePst)
        $dir = [IO.Path]::GetDirectoryName($target)

        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if($ARCH3oRequireNewUnusedPst -and (Test-Path -LiteralPath $target)){
            throw 'ARCH3o target appeared immediately before AddStoreEx. No Attach/Overwrite.'
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
    if([double]::IsPositiveInfinity($MaxArchivePstSizeGB)){return [int64]::MaxValue}
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
    if([double]::IsPositiveInfinity($MaxArchivePstSizeGB)){return 'WithinSafe'}
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
        [string]$AccountEmail,
        # ARCH3m only: forced Part2 route INSIDE the original destination
        # API, accepted with an independently validated ARCH3d fake scope.
        [object]$ARCH3mSyntheticPart2Scope,
        [object]$ARCH3mSyntheticCandidate,
        [object[]]$ARCH3mSyntheticExistingParts,
        # ARCH3n optional read-only ORIGINAL real Intent binding; only used
        # after existing ARCH3m fake TEMP checks, NEVER grants a real writer.
        [object]$ARCH3nSyntheticRealIntentBinding
    )

    $year = $ReceivedTime.Year
    $safeBytes = Get-OPAArchiveSafeCapacityBytes -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB
    if ($ItemSize -gt $safeBytes) { throw "Message size $ItemSize bytes exceeds safe archive PST capacity $safeBytes bytes." }

    if($null -ne $ARCH3mSyntheticPart2Scope){
        # This branch is INSIDE the original Get-OPAArchiveDestination and
        # BEFORE existing part selection / New-OPAArchivePst / AddStoreEx.
        # The caller MUST already be within the original ARCH3d synthetic
        # boundary. Revalidate here to reject direct unsafe callers.
        . (Join-Path $PSScriptRoot 'ARCH3mOriginalPart2PreAllocation.ps1')
        $plan=Assert-OPA265ARCH3mSyntheticPreAllocation -Namespace $Namespace -Transaction $Transaction -Scope $ARCH3mSyntheticPart2Scope -Candidate $ARCH3mSyntheticCandidate -ExistingArchiveParts @($ARCH3mSyntheticExistingParts) -SourcePst $SourcePst -ReceivedTime $ReceivedTime -SourceFolderName $SourceFolderName -SourceFolderPath $SourceFolderPath -AccountEmail $AccountEmail
        if($null -ne $ARCH3nSyntheticRealIntentBinding){
            . (Join-Path $PSScriptRoot 'ARCH3nPinnedRealIntentBridge.ps1')
            [void](Assert-OPA265ARCH3nSyntheticRealIntentBridge -RealPlan $ARCH3nSyntheticRealIntentBinding -SyntheticPreAllocation $plan -SyntheticCandidate $ARCH3mSyntheticCandidate)
        }
        $estimate=[double]$ItemSize * [double]$script:OPAArchiveGrowthRatioDefault
        if($estimate -gt [double]$safeBytes){
            throw 'ARCH3m original synthetic Part2 size would exceed safe capacity.'
        }
        # Only the original PST and folder functions allocate the destination.
        # In GitHub Actions these functions are mocked; no PST is created.
        $forcedPath=[string]$plan.ForcedPart2
        $store=New-OPAArchivePst -Namespace $Namespace -ArchivePst $forcedPath -AccountEmail $AccountEmail
        Register-OPAArchivePstInTransaction -Transaction $Transaction -ArchivePst $forcedPath -Year 2020 -Part 2 -PhysicalSizeBeforeBytes (Get-OPAArchivePstSizeBytes -Path $forcedPath)
        Clear-OPAArchivePartCache -SourcePst $SourcePst
        $Transaction.State.ArchivePst=$forcedPath
        $Transaction.State.CurrentArchivePst=$forcedPath
        $folder=Get-OPAArchiveFolder -ArchiveStore $store -SourceFolderName $SourceFolderName -SourceFolderPath $SourceFolderPath -ReceivedTime $ReceivedTime -Grouping Year
        $afterSize=Get-OPAArchivePstSizeBytes -Path $forcedPath
        if(([double]$afterSize + $estimate) -gt [double]$safeBytes){
            throw 'ARCH3m original synthetic Part2 capacity after initialization exceeded.'
        }
        $dest=[pscustomobject]@{Store=$store;Folder=$folder;Path=$forcedPath;Year=2020;Part=2}
        [void](Assert-OPA265ARCH3lSyntheticPart2 -Scope $ARCH3mSyntheticPart2Scope -Transaction $Transaction -Candidate $ARCH3mSyntheticCandidate -ExistingArchiveParts @($ARCH3mSyntheticExistingParts) -Stage DestinationReady -Destination $dest)
        return $dest
    }

    if($null -ne $ARCH3nSyntheticRealIntentBinding){
        throw 'ARCH3n real intent binding cannot reach the generic original live archive selection path.'
    }

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
        [switch]$Resume,
        # ARCH3d: test-only hooks within THIS legacy Move-OPAItemsWithLimit.
        # Real Outlook/PST must never enter this mode; default path unchanged.
        [switch]$ARCH3dSyntheticBoundary,
        # ARCH3l is ONLY an additional fake-PST scope under ARCH3d;
        # never authorizes an existing Outlook COM/PST writer.
        [switch]$ARCH3lSyntheticPart2Boundary,
        # ARCH3m: fake-only forced Part2 INSIDE original destination API.
        [switch]$ARCH3mSyntheticForcePart2,
        [switch]$ARCH4Batch,
        [switch]$ARCH5Batch,
        [switch]$ConfirmComplexAttachments
    )

    if(($ARCH5Batch -and -not $ARCH4Batch) -or ($ConfirmComplexAttachments -and (-not $ARCH5Batch -or $Limit -gt 10))){throw 'ARCH5 complex attachments require explicit bounded test batch (1..10).'}

    if($ARCH4Batch -and ($Resume -or $ARCH3dSyntheticBoundary -or $Limit -gt 500 -or $Limit -lt 1)){
        throw 'ARCH4 only allows a fresh bounded batch of 1..500; never legacy Resume.'
    }
    if($ARCH3mSyntheticForcePart2 -and -not $ARCH3lSyntheticPart2Boundary){
        throw 'ARCH3m requires original ARCH3d+ARCH3l synthetic boundaries and is not a real Outlook writer.'
    }
    if($ARCH3lSyntheticPart2Boundary){
        if(-not $ARCH3dSyntheticBoundary -or $Resume -or $ArchiveGrouping -cne 'Year' -or $Limit -ne 1){
            throw 'ARCH3l accepts only ARCH3d synthetic one-shot Year Part2, never live Outlook/Resume.'
        }
    }
    if($ARCH3dSyntheticBoundary){
        # Must run before ANY original file/journal/destination side effects.
        if(-not (Get-Command Write-OPA265ARCH3cJsonOnce -ErrorAction SilentlyContinue)){
            . (Join-Path $PSScriptRoot 'ARCH3cDurableOperationLedger.ps1')
        }
        if(-not (Get-Command Assert-OPA265ARCH3dSyntheticBoundary -ErrorAction SilentlyContinue)){
            . (Join-Path $PSScriptRoot 'ARCH3dOriginalMoverBoundary.ps1')
        }
        if($Resume){throw 'ARCH3d synthetic one-shot integration forbids Resume.'}
        $arch3dScope=Assert-OPA265ARCH3dSyntheticBoundary -Namespace $Namespace -Transaction $Transaction -SourceFolders @($SourceFolders)
    }

    if($ARCH3lSyntheticPart2Boundary){
        . (Join-Path $PSScriptRoot 'ARCH3lOriginalPart2SyntheticGate.ps1')
    }
    # SourceFolder may be a single Outlook Folder or an array. The array form
    # is the production path: one transaction spans the complete POP3 PST tree.
    $sourceFolders = @($SourceFolders) | Where-Object { $_ }
    if ($sourceFolders.Count -eq 0) { return [int]$Transaction.State.Executed }

    # ARCH2a: a prior Move Started without durable Move Completed is NOT an
    # ordinary skipped item, even if the original source still looks present.
    # Before any Resume, scan the FULL original journal, not its 200-step
    # in-memory checkpoint tail. Never infer retry permission from COM state.
    if ($Resume) {
        . (Join-Path $PSScriptRoot 'ARCH2aMoveOutcomeFence.ps1')
        $stepJournalPath = Get-OPAStepJournalPath -Transaction $Transaction
        if (-not (Test-Path -LiteralPath $stepJournalPath -PathType Leaf)) {
            throw 'ARCH2a Resume STOP: original step journal missing; manual reconciliation required.'
        }
        # Read-OPAJsonlLocal tolerates a malformed LAST record, which could
        # hide a Move Started. In ARCH2a Resume that is not acceptable: stop
        # BEFORE the reader can silently omit an ambiguous attempt.
        $fs = $null
        try {
            $fs = [IO.File]::Open($stepJournalPath,
                [IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            if ($fs.Length -lt 2) { throw 'ARCH2a Resume STOP: original step journal empty or truncated.' }
            $fs.Position = $fs.Length - 1
            if ($fs.ReadByte() -ne 10) {
                throw 'ARCH2a Resume STOP: unterminated step journal; manual read-only recovery required.'
            }
        }
        finally { if ($null -ne $fs) { $fs.Dispose() } }
        # Do not trust Read-OPAJsonlLocal's intentional tolerance of a
        # malformed LAST record: that record could be the missing claim.
        $lastOriginalLine = [string](Get-Content -LiteralPath $stepJournalPath -Encoding UTF8 -Tail 1)
        try {
            $lastOriginalRecord = ConvertFrom-Json -InputObject $lastOriginalLine -ErrorAction Stop
            if ($null -eq $lastOriginalRecord -or
                $lastOriginalRecord.PSObject.Properties.Name -notcontains 'Step') {
                throw 'Last record is not a step entry.'
            }
        }
        catch { throw 'ARCH2a Resume STOP: last original journal record malformed; manual reconciliation required.' }
        $journalSteps = @(Read-OPAStepJournal -Transaction $Transaction)
        [void](Assert-OPA265ARCH2aNoUnresolvedMove -Transaction $Transaction -JournalSteps $journalSteps)
    }

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
        if(-not $ARCH3lSyntheticPart2Boundary){
            if(-not $ARCH4Batch){
                [void](Sync-OPADuplicateIndexFromJournal -Transaction $Transaction -Index $sharedIndex -ArchivePst ([string]$existingArchivePaths[0].Path))
            }
        }
        # ARCH3l reads the original shared DuplicateIndex but deliberately
        # NEVER invokes the legacy pre-verification sync/write path.
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
                $folderLimit=if($ARCH4Batch){$Limit}else{[Math]::Max($Limit * 3, $Limit + 20)}
                if($ARCH5Batch){
                    $selection=Get-OPAArchiveCandidates -SourceFolder $folder -Limit $folderLimit -ExcludeEntryIds $duplicateIds -OlderThanCutoff $OlderThanCutoff -Diagnostics
                    if($null -eq $selection -or [int]$selection.SelectionErrors -gt 0 -or [int]$selection.MissingArchiveDate -gt 0){
                        throw 'ARCH6 candidate selection incomplete; no automatic exhaustion or new Move.'
                    }
                    $folderCandidates=@($selection.Candidates)
                }else{
                    $folderCandidates=@(Get-OPAArchiveCandidates -SourceFolder $folder -Limit $folderLimit -ExcludeEntryIds $duplicateIds -OlderThanCutoff $OlderThanCutoff)
                }
                foreach ($candidate in $folderCandidates) {
                    $candidateRows.Add($candidate) | Out-Null
                }
            }
            catch {
                if($ARCH5Batch){throw}
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'FolderSelectionSkipped' -Message ("Folder selection failed and was skipped: {0} | {1}" -f [string]$folder.FolderPath,$_.Exception.Message) -TargetFolderPath $null
            }
        }

        # Keep a replacement pool so a locked/unavailable message does not
        # consume the requested move limit. The transaction checkpoint itself
        # stores only the controlled batch; the pool is used during this run.
        $candidatePool = @($candidateRows | Sort-Object ArchiveDate,EntryID)
        if($ARCH4Batch){
            $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $candidatePool=@($candidatePool | Where-Object { $_.EntryID -and $seen.Add([string]$_.EntryID) } | Select-Object -First $Limit)
        }
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
    $batchClock=[Diagnostics.Stopwatch]::StartNew()
    while ($candidateIndex -lt $candidatePool.Count -and $executed -lt $Limit) {
        $candidate = $candidatePool[$candidateIndex]
        $candidateIndex++
        if($ARCH5Batch){
            $rate=if($batchClock.Elapsed.TotalSeconds -gt 0){($candidateIndex-1)/$batchClock.Elapsed.TotalSeconds}else{0}
            $eta=if($rate -gt 0){[int][math]::Ceiling(($candidatePool.Count-$candidateIndex+1)/$rate)}else{-1}
            Write-Progress -Id 50 -Activity 'Архивация почты' -Status ('{0}/{1}; перенесено {2}; {3:N1} писем/с' -f $candidateIndex,$candidatePool.Count,$executed,$rate) -PercentComplete ([int](100*$candidateIndex/$candidatePool.Count)) -SecondsRemaining $eta
        }

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

        $item = $null; $moved = $null; $moveCompleted = $false; $moveAttemptClaimed = $false
        $semanticPreflightBlocked = $false
        $arch3dOperation=$null; $arch3dDestinationPath=''; $arch3dTargetFolder=''; $arch3dWitnessSha=''
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
                if($ARCH4Batch){throw 'ARCH4 source item disappeared before claim.'}
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
            if($ARCH4Batch){
                Assert-OPAARCH4Candidate -Item $item -SourceFolder $source -Candidate $candidate -Cutoff $OlderThanCutoff
                $itemSize=[long]$item.Size
            }
            if($ARCH3lSyntheticPart2Boundary){
                [void](Assert-OPA265ARCH3lSyntheticPart2 -Scope $arch3dScope -Transaction $Transaction -Candidate $candidate -ExistingArchiveParts @($existingArchivePaths) -Stage BeforeDestination)
            }
            if($ARCH3dSyntheticBoundary){
                # This is the original MailMover loop. Persist the durable
                # intent BEFORE Get-OPAArchiveDestination can create a PST.
                $arch3dOperation=Get-OPA265ARCH3dOperationIdentity -Scope $arch3dScope -Candidate $candidate -ArchiveGrouping $ArchiveGrouping
                [void](Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage PrepareIntent)
            }
            $dest = $null
            try {
                if($ARCH3mSyntheticForcePart2){
                    $dest = Get-OPAArchiveDestination -Namespace $Namespace -Transaction $Transaction -SourcePst $Transaction.State.SourcePst -ReceivedTime $dt -ItemSize $itemSize -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB -ArchiveGrouping $ArchiveGrouping -SourceFolderName ([string]$source.Name) -SourceFolderPath $folderPath -AccountEmail ([string]$Transaction.State.AccountEmail) -ARCH3mSyntheticPart2Scope $arch3dScope -ARCH3mSyntheticCandidate $candidate -ARCH3mSyntheticExistingParts @($existingArchivePaths)
                }else{
                    $dest = Get-OPAArchiveDestination -Namespace $Namespace -Transaction $Transaction -SourcePst $Transaction.State.SourcePst -ReceivedTime $dt -ItemSize $itemSize -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB -ArchiveGrouping $ArchiveGrouping -SourceFolderName ([string]$source.Name) -SourceFolderPath $folderPath -AccountEmail ([string]$Transaction.State.AccountEmail)
                }
            }
            catch {
                if($ARCH3dSyntheticBoundary){
                    # Intent may already be sealed: never downgrade failure
                    # after destination choice to Skipped or retry another mail.
                    throw ('ARCH3d protected destination outcome requires manual review: '+[string]$_.Exception.Message)
                }
                $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason=$(if ($_.Exception.Message -match 'exceeds safe archive PST capacity') { 'ExceedsArchiveCapacity' } else { 'DestinationFailed' }); Message=$_.Exception.Message; Time=(Get-Date).ToString('o')}) | Out-Null
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Destination selection failed and item was skipped: {0} | {1}" -f [string]$candidate.Subject,$_.Exception.Message) -EntryId ([string]$candidate.EntryId) -ReceivedTime $dt
                continue
            }

            if($ARCH3lSyntheticPart2Boundary){
                [void](Assert-OPA265ARCH3lSyntheticPart2 -Scope $arch3dScope -Transaction $Transaction -Candidate $candidate -ExistingArchiveParts @($existingArchivePaths) -Stage DestinationReady -Destination $dest)
            }
            if($ARCH3dSyntheticBoundary){
                # Bind actual rollover part chosen by ORIGINAL destination API.
                $arch3dDestinationPath=[string]$dest.Path
                $arch3dTargetFolder=[string]$dest.Folder.FolderPath
                [void](Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage DestinationReady -ArchivePst $arch3dDestinationPath -TargetFolderPath $arch3dTargetFolder)
            }
            $index = $null
            if ($allIndexes.ContainsKey($dest.Path)) { $index = $allIndexes[$dest.Path] }
            elseif ($sharedIndex) { $index = $sharedIndex; $allIndexes[$dest.Path] = $index }
            else { $index = Import-OPADuplicateIndex -ArchivePst $dest.Path; $allIndexes[$dest.Path] = $index }
            if (Test-OPADuplicateEntry -Index $index -SourceEntryId ([string]$candidate.EntryId)) {
                if($ARCH3dSyntheticBoundary){throw 'ARCH3d protected operation cannot skip after persisted PrepareIntent; manual review, no retry.'}
                continue
            }

            # ARCH2b: persist the exact ALREADY-SAVED source message user
            # content (including by-value attachment BYTE SHA256) before
            # the one-shot COM call. An inability to capture is a hard stop.
            # The captured witness is never rebaselined after the Move.
            $semanticPreflightBlocked = -not $ARCH4Batch
            if($ARCH4Batch){
                Assert-OPAARCH4Destination -Namespace $Namespace -SourceFolder $source -Destination $dest
                Assert-OPAARCH4Candidate -Item $item -SourceFolder $source -Candidate $candidate -Cutoff $OlderThanCutoff
            }
            if($ARCH5Batch){
                Assert-OPAARCH5Route -SourcePst ([string]$Transaction.State.SourcePst) -ArchiveDate $dt -SourceFolderPath $folderPath -TargetFolderPath ([string]$dest.Folder.FolderPath) -ArchivePst ([string]$dest.Path) -Grouping $ArchiveGrouping
                $sourceSemanticWitness = Get-OPA265ARCH2bMailSemanticWitness -Mail $item -ExtendedAttachmentWitness -RecursiveEmbeddedWitness -AllowComplexAttachments:$ConfirmComplexAttachments
            }else{
                $sourceSemanticWitness = Get-OPA265ARCH2bMailSemanticWitness -Mail $item
            }
            if($ARCH4Batch -and -not (Test-OPA265ARCH2bWitnessSchema -Witness $sourceSemanticWitness)){
                throw 'ARCH4 source semantic witness unavailable before claim.'
            }
            if($ARCH3dSyntheticBoundary){
                $arch3dWitnessSha=Get-OPA265ARCH3dOriginalWitnessHash -Witness $sourceSemanticWitness
                [void](Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage SourceWitnessAnchored -ArchivePst $arch3dDestinationPath -TargetFolderPath $arch3dTargetFolder -WitnessSha256 $arch3dWitnessSha)
            }
            $semanticPreflightBlocked = $false

            # ARCH2a: claim before any possible Outlook provider mutation.
            # The checkpoint plus explicit Flush(true) are the last durability
            # boundary before calling COM. If any part fails, stop; never move.
            $moveAttemptClaimed = $true
            Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Move Started' -Message ("Starting Move: {0}" -f [string]$candidate.Subject) -EntryId $candidate.EntryId -ArchivePst $dest.Path -TargetFolderPath $dest.Folder.FolderPath -SourceFolderPath $folderPath -ReceivedTime $dt -SemanticWitness $sourceSemanticWitness -WriteCheckpoint
            Sync-OPAStepJournalStreams
            if($ARCH4Batch){
                [void](Write-OPAOperationJournalEvent -Path (Get-OPAARCH4OperationPath -Transaction $Transaction) -TransactionId $Transaction.TransactionId -OperationId ([string]$candidate.EntryId) -Sequence ([long]($executed+1)) -Phase Intent -SourceEntryId ([string]$candidate.EntryId) -SourceStoreId ([string]$source.StoreID) -SourceFolderPath $folderPath -TargetFolderPath ([string]$dest.Folder.FolderPath) -ArchivePst ([string]$dest.Path))
            }
            if($ARCH3dSyntheticBoundary){
                # The real legacy step claim is already force-flushed.
                # This second linked claim is immutable and must precede Move.
                [void](Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage MoveClaimed -ArchivePst $arch3dDestinationPath -TargetFolderPath $arch3dTargetFolder -WitnessSha256 $arch3dWitnessSha)
            }

            try {
                $moved = $item.Move($dest.Folder)
                $moveCompleted = $true
            }
            catch {
                # ARCH2a: an Outlook COM exception cannot establish whether
                # a cross-store Move already reached the destination. Preserve
                # the original one-shot claim and STOP this entire transaction.
                # Never classify this message as skipped or select another
                # candidate; only independent read-only reconciliation is safe.
                $originalMoveError = [string]$_.Exception.Message
                if($ARCH3dSyntheticBoundary -and $null -ne $arch3dOperation){
                    try{
                        [void](Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage MoveIndeterminate -ArchivePst $arch3dDestinationPath -TargetFolderPath $arch3dTargetFolder -WitnessSha256 $arch3dWitnessSha)
                    }catch{Write-Warning ('ARCH3d original indeterminate claim remains immutable: '+[string]$_.Exception.Message)}
                }
                try {
                    Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Failed' -Step 'Move Indeterminate' -Message 'Outlook COM Move outcome unknown; independent reconciliation required; no automatic retry.' -EntryId ([string]$candidate.EntryId) -ReceivedTime $dt -ArchivePst $dest.Path -TargetFolderPath $dest.Folder.FolderPath -SourceFolderPath $folderPath -WriteCheckpoint
                    Sync-OPAStepJournalStreams
                }
                catch {
                    Write-Warning ('ARCH2a could not seal Move Indeterminate; preserve original Move Started claim and stop: '+[string]$_.Exception.Message)
                }
                throw ('ARCH2a MOVE OUTCOME UNKNOWN, transaction stopped, never retry original source EntryID='+
                    [string]$candidate.EntryId+'; original COM error: '+$originalMoveError)
            }

            $archiveId = [string]$moved.EntryID
            if ([string]::IsNullOrWhiteSpace($archiveId)) {
                throw "Move succeeded but Outlook returned no destination EntryID for source $($candidate.EntryId)."
            }

            if($ARCH3dSyntheticBoundary){
                # Synthetic original mover actually returned via a TEST DOUBLE.
                # The linked receipt is pinned separately; WITHOUT independent
                # post-restart verification, index/transaction completion blocked.
                $arch3dReceipt=Write-OPA265ARCH3dSyntheticBoundary -Operation $arch3dOperation -Stage MoveReturned -ArchivePst $arch3dDestinationPath -TargetFolderPath $arch3dTargetFolder -WitnessSha256 $arch3dWitnessSha -ArchiveEntryId $archiveId
                throw ('ARCH3d SYNTHETIC STOP after immutable MoveReturned receipt SHA256='+[string]$arch3dReceipt.Sha256+'; no DuplicateIndex until independent Outlook restart reconciliation; NEVER retry.')
            }
            if($ARCH4Batch){
                # Return is not verification. Preserve original source witness
                # and destination before any index or completion is written.
                Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'ARCH4 Move Returned' -Message 'Provider returned; independent postrestart verification pending' -EntryId ([string]$candidate.EntryId) -ArchiveEntryId $archiveId -ArchivePst $dest.Path -TargetFolderPath $dest.Folder.FolderPath -SourceFolderPath $folderPath -ReceivedTime $dt
                Sync-OPAStepJournalStreams
                $executed++
                $logical=[long]$Transaction.State.LogicalFreedBytes+[long]$itemSize
                Set-OPAArchiveTransactionCount -Transaction $Transaction -Planned ([int]$Transaction.State.Planned) -Executed $executed -Verified 0
                Set-OPAArchiveTransactionStorageStats -Transaction $Transaction -LogicalFreedBytes $logical
                $physical=Get-OPAArchivePstSizeBytes -Path $dest.Path
                Update-OPAArchivePstTelemetry -Transaction $Transaction -ArchivePst $dest.Path -PhysicalSizeBytes $physical -LogicalAddedBytes $itemSize
                if((Get-OPAArchivePostMoveCapacityAction -PhysicalSizeBytes $physical -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB) -eq 'HardLimitExceeded'){
                    throw 'ARCH4 archive hard limit exceeded after returned Move; reconcile before new batch.'
                }
                continue
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
            if($ARCH3dSyntheticBoundary){
                # An immutable PrepareIntent/MoveClaimed may already exist.
                # Test-only protected mode NEVER converts an exception into a
                # harmless Skipped row or normal completion; refuse rerun.
                Sync-OPAStepJournalStreams
                throw
            }
            # Once Outlook.Move() has returned successfully, the source item
            # is no longer safely classifiable as "skipped". A failure in
            # post-move durability must stop the batch and be recovered from
            # DuplicateIndex/the step journal; silently counting it as skipped
            # could allow a duplicate move on a later run.
            if ($semanticPreflightBlocked) {
                # If even one required content field or attachment cannot be
                # hashed, stop the transaction before claiming or moving.
                throw
            }
            if ($moveCompleted -or $moveAttemptClaimed) {
                # ARCH2a: do NOT fall into the old 'Unexpected / Skipped'
                # handler once a Move attempt was claimed. A failed COM call
                # may have completed in Outlook while its response was lost.
                Sync-OPAStepJournalStreams
                throw
            }

            if ($Resume) { throw }

            # Pre-move errors are isolated to the current item. The transaction
            # remains resumable and the next candidate can continue.
            $reason='Unexpected'
            if($ARCH5Batch -and $_.Exception.Message -match '^ARCH5(?:b)? (AttachmentTypeUnsupported|AttachmentSizeUnsupported|AttachmentExportUnverified|AttachmentCleanupFailed|ArchiveRouteMismatch):'){$reason=$Matches[1]}
            $skippedList.Add([pscustomobject]@{EntryId=[string]$candidate.EntryId; SourceFolderPath=$folderPath; Reason=$reason; Message=$_.Exception.Message; Time=(Get-Date).ToString('o')}) | Out-Null
            Save-OPAArchiveTransaction -Transaction $Transaction -Status 'Running' -Step 'Skipped' -Message ("Item skipped after unexpected error: {0} | {1}" -f [string]$candidate.Subject,$_.Exception.Message) -EntryId ([string]$candidate.EntryId) -ReceivedTime ([datetime]$candidate.ReceivedTime)
        }
        finally {
            Release-OPAComObject -Object $moved
            Release-OPAComObject -Object $item
        }
    }

    if($ARCH5Batch){Write-Progress -Id 50 -Activity 'Архивация почты' -Completed}
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


# ARCH3o: Exactly ONE operator-pinned real test-PST Outlook MailItem.Move,
# inside the ORIGINAL MailMover module. Called ONLY with a durably sealed
# ARCH3o-MoveClaimed CreateNew record, and a SECOND provider-invocation fence.
# Do not use this for production Archive/Resume/Auto or batch movement.
function Invoke-OPA265ARCH3oOneOriginalMailMoverProviderCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [Parameter(Mandatory=$true)][object]$Folder,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$ClaimSha256
    )
    if($RunId -cne '9d276dc4-a0e6-4e74-891f-81502fafe7db' -or
       $ClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH3o provider identity not pinned to operator ARCH3j one-shot.'
    }
    $root=Join-Path $env:LOCALAPPDATA ('OPA265-ARCH3j-'+$RunId)
    if(-not [IO.Directory]::Exists($root) -or
       (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3o provider protected operator workspace missing or redirected.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $root)
    $claim=Read-OPA265ARCH3cPinnedJson -Path (Join-Path $root 'ARCH3o-MoveClaimed.json') -ExpectedSha256 $ClaimSha256
    if([string]$claim.Schema -cne '2.6.5-ARCH3o.RealOneShotMoveClaim.1' -or
       [string]$claim.RunId -cne $RunId -or
       [string]$claim.IntentSha256 -cne 'f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b' -or
       [string]$claim.JournalSha256 -cne 'a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e' -or
       [string]$claim.SourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00' -or
       [string]$claim.SourceEntryId -cne [string]$Mail.EntryID -or
       [int]$Mail.Class -ne 43 -or
       [string]$claim.OriginalWitnessSha256 -cne '8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c' -or
       [string]$claim.DestinationFolderEntryId -cne [string]$Folder.EntryID -or
       [string]$claim.DestinationStoreId -cne [string]$Folder.StoreID -or
       [string]$claim.NewArchivePst -cne 'C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.Archive-2020-02.pst' -or
       -not [bool]$claim.OperatorApprovedOneRealMove -or
       [bool]$claim.AutomaticRetryAllowed -or [bool]$claim.ProductionReady){
        throw 'ARCH3o provider claim does not match original operator source/Part2.'
    }
    $record=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3o.ProviderInvocation.1'
        RunId=$RunId
        ClaimSha256=$ClaimSha256
        SourceEntryId=[string]$claim.SourceEntryId
        NewArchivePst=[string]$claim.NewArchivePst
        DestinationFolderEntryId=[string]$Folder.EntryID
        OneProviderInvocationOnly=$true
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
    # CreateNew + Flush(true) before COM: if process dies during Move, second
    # invocation is impossible even when previous MoveReturned is missing.
    $invocationSha=Write-OPA265ARCH3cJsonOnce -Path (Join-Path $root 'ARCH3o-ProviderInvocation.json') -Record $record
    $moved=$null
    try{
        $moved=$Mail.Move($Folder)
        if($null -eq $moved -or [string]::IsNullOrWhiteSpace([string]$moved.EntryID) -or
           [int]$moved.Class -ne 43){
            throw 'ARCH3o Outlook COM Move outcome UNKNOWN: no automatic replay.'
        }
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3o.OriginalMailMoverProviderReturned.1'
            RunId=$RunId
            DestinationEntryId=[string]$moved.EntryID
            ProviderInvocationSha256=$invocationSha
            OneMoveReturned=$true
            IndependentPostRestartVerified=$false
            AutomaticRetryAllowed=$false
        }
    }finally{
        if($null -ne $moved -and $moved -is [__ComObject]){
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($moved)
        }
    }
}


# ARCH3x: fake-only ten-message provider boundary in ORIGINAL MailMover.
# Real COM, PST and main Archive/Resume/Auto are forbidden here.
function Invoke-OPA265ARCH3xFakeOnlyOriginalProviderCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [Parameter(Mandatory=$true)][object]$Folder,
        [Parameter(Mandatory=$true)][string]$ClaimPath,
        [Parameter(Mandatory=$true)][string]$ExpectedClaimSha256,
        [Parameter(Mandatory=$true)][string]$InvocationPath,
        [switch]$FaultAfterInvocation
    )
    if($Mail -is [__ComObject] -or $Folder -is [__ComObject] -or
       -not [bool]$Mail.SyntheticOnly -or -not [bool]$Folder.SyntheticOnly -or
       [int]$Mail.Class -ne 43 -or
       $ExpectedClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH3x original MailMover rejects real Outlook COM or unpinned fake inputs.'
    }
    $root=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ClaimPath))
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
    if(-not $root.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       [IO.Path]::GetFileName($root) -cnotmatch '^OPA265-ARCH3x-SYNTH-[a-f0-9]{32}$' -or
       -not [IO.Directory]::Exists($root) -or
       (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($InvocationPath)) -cne $root){
        throw 'ARCH3x original fake provider must use a private OS TEMP synthetic directory.'
    }
    $claim=Read-OPA265ARCH3cPinnedJson -Path $ClaimPath -ExpectedSha256 $ExpectedClaimSha256
    if([string]$claim.Schema -cne '2.6.5-ARCH3x.SyntheticMoveClaim.1' -or
       -not [bool]$claim.SyntheticOnly -or [bool]$claim.AutomaticRetryAllowed -or
       [string]$claim.SourceEntryId -cne [string]$Mail.EntryID -or
       [string]$claim.DestinationEntryId -cne [string]$Mail.TargetEntryId -or
       [string]$claim.DestinationFolderEntryId -cne [string]$Folder.EntryID -or
       [string]$claim.WitnessSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [int]$claim.Ordinal -lt 1 -or [int]$claim.Ordinal -gt 10){
        throw 'ARCH3x original provider rejected mismatched or incomplete synthetic claim.'
    }
    if([IO.Path]::GetFileName($InvocationPath) -cne ('{0:00}-Invocation.json' -f [int]$claim.Ordinal)){
        throw 'ARCH3x original fake invocation ordinal does not match claim.'
    }
    $record=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x.SyntheticProviderInvocation.1'
        RunId=[string]$claim.RunId;Ordinal=[int]$claim.Ordinal
        ClaimSha256=$ExpectedClaimSha256
        SourceEntryId=[string]$Mail.EntryID
        DestinationEntryId=[string]$Mail.TargetEntryId
        DestinationFolderEntryId=[string]$Folder.EntryID
        SyntheticOnly=$true;AutomaticRetryAllowed=$false;ProductionReady=$false
    }
    # Existing immutable original ARCH3c CreateNew/Flush(true) writer BEFORE fake Move.
    $invocationSha=Write-OPA265ARCH3cJsonOnce -Path $InvocationPath -Record $record
    if($FaultAfterInvocation){throw 'ARCH3x fault after durable provider invocation, before fake Move.'}
    $moved=$Mail.Move($Folder)
    if($null -eq $moved -or [int]$moved.Class -ne 43 -or
       [string]$moved.EntryID -cne [string]$claim.DestinationEntryId){
        throw 'ARCH3x synthetic provider unknown; automatic replay forbidden.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x.SyntheticProviderReturned.1'
        RunId=[string]$claim.RunId;Ordinal=[int]$claim.Ordinal
        DestinationEntryId=[string]$moved.EntryID
        ClaimSha256=$ExpectedClaimSha256
        ProviderInvocationSha256=$invocationSha
        FakeMoveReturned=$true;RealOutlookContacted=$false
        AutomaticRetryAllowed=$false;ProductionReady=$false
    }
}


# ARCH3x1: exactly ten individually pinned REAL TEST-PST provider operations.
# A separate, immutable ARCH3w1 prepared ten-Intent journal is REQUIRED.
# This helper is invoked only AFTER the caller durably writes one claim.
# Each provider-invocation record is CreateNew + Flush(true) BEFORE COM Move.
# Never use this route from the production Archive/Resume/Auto dispatcher.
function Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [Parameter(Mandatory=$true)][object]$Folder,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][ValidateRange(1,10)][int]$Ordinal,
        [Parameter(Mandatory=$true)][string]$ClaimSha256
    )
    if($RunId -cne '093b5ce9-4a90-46fa-b6a5-7cdba61d2f15' -or
       $ClaimSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $Mail -isnot [__ComObject] -or $Folder -isnot [__ComObject]){
        throw 'ARCH3x1 original real provider requires pinned operator RunId, SHA and actual Outlook COM.'
    }
    $root=Join-Path $env:LOCALAPPDATA ('OPA265-ARCH3x1-'+$RunId)
    if(-not [IO.Directory]::Exists($root) -or
       (([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3x1 protected one-shot provider workspace missing/redirected.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $root)
    $writerPath=Join-Path $root 'writer-entry.json'
    if(-not [IO.File]::Exists($writerPath)){throw 'ARCH3x1 writer entry missing, no provider invocation.'}
    $claimPath=Join-Path $root (('{0:00}' -f $Ordinal)+'-claim.json')
    foreach($p in @($writerPath,$claimPath)){
        if(-not [IO.File]::Exists($p) -or
           (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3x1 original provider protected claim/writer file is missing or redirected.'
        }
    }
    $writerSha=(Get-FileHash -LiteralPath $writerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $writer=Read-OPA265ARCH3cPinnedJson -Path $writerPath -ExpectedSha256 $writerSha
    $prefix=('{0:00}' -f $Ordinal)
    $claim=Read-OPA265ARCH3cPinnedJson -Path (Join-Path $root ($prefix+'-claim.json')) -ExpectedSha256 $ClaimSha256
    if([string]$writer.Schema -cne '2.6.5-ARCH3x1.RealTenWriterEntry.1' -or
       [string]$writer.RunId -cne $RunId -or
       [string]$writer.PreparedManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$writer.PreparedJournalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$writer.SourceStoreIdSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$claim.Schema -cne '2.6.5-ARCH3x1.RealTenMoveClaim.1' -or
       [string]$claim.RunId -cne $RunId -or
       [int]$claim.Ordinal -ne $Ordinal -or
       [string]$claim.WriterEntrySha256 -cne $writerSha -or
       [string]$claim.PreparedManifestSha256 -cne [string]$writer.PreparedManifestSha256 -or
       [string]$claim.PreparedJournalSha256 -cne [string]$writer.PreparedJournalSha256 -or
       [string]$claim.SourceStoreIdSha256 -cne [string]$writer.SourceStoreIdSha256 -or
       [string]$claim.SourceEntryId -cne [string]$Mail.EntryID -or
       [int]$Mail.Class -ne 43 -or
       [string]$claim.TargetPst -cne [string]$writer.TargetPst -or
       [string]$claim.DestinationStoreId -cne [string]$Folder.StoreID -or
       [string]$claim.DestinationFolderEntryId -cne [string]$Folder.EntryID -or
       -not ([string]$Folder.FolderPath).EndsWith('\2020\Входящие',[StringComparison]::OrdinalIgnoreCase) -or
       [string]$claim.FullOriginalWitnessSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [bool]$claim.OperatorApprovedTenRealMoves -or
       [bool]$claim.AutomaticRetryAllowed -or [bool]$claim.ProductionReady){
        throw 'ARCH3x1 real original MailMover source/destination/claim not pinned.'
    }
    $preparedLayout=Get-OPA265ARCH3w1Layout -RunId $RunId
    $prepared=Read-OPA265ARCH3cPinnedJson -Path ([string]$preparedLayout.ManifestPath) -ExpectedSha256 ([string]$writer.PreparedManifestSha256)
    $row=$prepared.Rows[$Ordinal-1]
    if([string]$prepared.RunId -cne $RunId -or
       [int]$prepared.BatchSize -ne 10 -or
       [string]$prepared.TargetPstPreview -cne [string]$writer.TargetPst -or
       [int]$row.Ordinal -ne $Ordinal -or
       [string]$row.SourceEntryId -cne [string]$claim.SourceEntryId -or
       [string]$row.FullOriginalWitnessSha256 -cne [string]$claim.FullOriginalWitnessSha256 -or
       [string]$row.OriginalOperationId -cne [string]$claim.OriginalOperationId -or
       [string]$row.OriginalContractSha256 -cne [string]$claim.OriginalContractSha256){
        throw 'ARCH3x1 original provider does not match immutable ARCH3w1 ten Intent manifest.'
    }
    $parent=$null;$moved=$null
    try{
        $parent=$Mail.Parent
        if($null -eq $parent -or
           [string]$parent.EntryID -cne [string]$writer.SourceFolderEntryId -or
           (Get-OPA265ARCH2bTextSha256 -Text ([string]$parent.StoreID)) -cne [string]$writer.SourceStoreIdSha256 -or
           [string]$parent.FolderPath -cne '\\info@stios.ru\Входящие'){
            throw 'ARCH3x1 original provider source parent drift before COM.'
        }
        $invocation=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x1.RealTenProviderInvocation.1'
            RunId=$RunId;Ordinal=$Ordinal
            ClaimSha256=$ClaimSha256
            WriterEntrySha256=$writerSha
            SourceEntryId=[string]$claim.SourceEntryId
            DestinationFolderEntryId=[string]$Folder.EntryID
            DestinationStoreId=[string]$Folder.StoreID
            TargetPst=[string]$writer.TargetPst
            OneProviderCallOnly=$true
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $invocationSha=Write-OPA265ARCH3cJsonOnce -Path (Join-Path $root ($prefix+'-invocation.json')) -Record $invocation
        # No COM retry or catch-and-continue: throws have UNKNOWN outcome.
        $moved=$Mail.Move($Folder)
        if($null -eq $moved -or [int]$moved.Class -ne 43 -or
           [string]$moved.EntryID -cnotmatch '^[a-fA-F0-9]{16,1024}$'){
            throw 'ARCH3x1 actual COM Move result indeterminate. NEVER RETRY.'
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x1.RealOriginalProviderReturned.1'
            RunId=$RunId;Ordinal=$Ordinal
            DestinationEntryId=[string]$moved.EntryID
            ProviderInvocationSha256=$invocationSha
            OneMoveReturned=$true;IndependentPostRestartVerified=$false
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
    }finally{
        # Parent is also held by the caller's per-item scope. Never
        # FinalRelease its shared RCW here; the caller owns that lifetime.
        # A double FinalRelease after a successful Move would raise a false
        # indeterminate exception and stop the remaining original batch.
        if($null -ne $moved -and $moved -is [__ComObject]){
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($moved)
        }
    }
}
