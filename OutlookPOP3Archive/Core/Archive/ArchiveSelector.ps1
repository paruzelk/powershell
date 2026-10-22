function Get-OPAInternetMessageId {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Item)

    $pa = $null
    try {
        $pa = $Item.PropertyAccessor
        foreach ($tag in @('http://schemas.microsoft.com/mapi/proptag/0x1035001E','http://schemas.microsoft.com/mapi/proptag/0x1035001F')) {
            try {
                $value = [string]$pa.GetProperty($tag)
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            } catch {}
        }
    } catch {}
    finally { Release-OPAComObject -Object $pa }
    return $null
}

function Get-OPAArchiveItemDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [switch]$PreferSentOn
    )

    $value = $null
    if ($PreferSentOn) {
        try { $value = [datetime]$Item.SentOn } catch {}
        if ($value -and $value -gt [datetime]::MinValue) { return $value }
    }

    try { $value = [datetime]$Item.ReceivedTime } catch {}
    if ($value -and $value -gt [datetime]::MinValue) { return $value }

    try { $value = [datetime]$Item.SentOn } catch {}
    if ($value -and $value -gt [datetime]::MinValue) { return $value }

    try { $value = [datetime]$Item.CreationTime } catch {}
    if ($value -and $value -gt [datetime]::MinValue) { return $value }

    return $null
}

function Get-OPADateRestrictFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][datetime]$Cutoff,
        [switch]$PreferSentOn
    )
    # A DASL property URI must be quoted separately from the comparison.
    # The formatted date uses culture-independent digits and separators.
    $property = if ($PreferSentOn) { 'http://schemas.microsoft.com/mapi/proptag/0x00390040' } else { 'urn:schemas:httpmail:datereceived' }
    $dateText = $Cutoff.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    return ('@SQL="{0}" < {1}{2}{1}' -f $property, [char]39, $dateText)
}

function Get-OPAArchiveCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$SourceFolder,
        [ValidateRange(1,2147483647)][int]$Limit,
        [object]$ExcludeEntryIds,
        [object]$OlderThanCutoff,
        [switch]$Diagnostics
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $items = $null
    try { $items = $SourceFolder.Items }
    catch { throw "Unable to access Outlook folder items: $($_.Exception.Message)" }

    $originalCount = 0
    try { $originalCount = [int]$items.Count } catch {}

    $cutoff = $null
    if ($null -ne $OlderThanCutoff) {
        try { $cutoff = [datetime]$OlderThanCutoff }
        catch { throw "Invalid OlderThanCutoff value '$OlderThanCutoff': $($_.Exception.Message)" }
    }

    $excludeSet = $null
    if ($null -ne $ExcludeEntryIds) {
        $excludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($id in @($ExcludeEntryIds)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$id)) { [void]$excludeSet.Add([string]$id) }
        }
    }

    $mailItemCount = 0
    $excludedByAge = 0
    $excludedByDuplicate = 0
    $selectionErrors = 0
    $selectionErrorDetails = New-Object System.Collections.Generic.List[string]
    $missingArchiveDate = 0
    $usedRestrict = $false
    $usedSort = $false
    $filteredItems = $items
    $limitBoundaryReceived = $null
    $scannedAllFilteredItems = $true

    $folderName = ''
    try { $folderName = [string]$SourceFolder.Name } catch {}
    $folderEntryId = ''
    try { $folderEntryId = [string]$SourceFolder.EntryID } catch {}

    $wellKnownMap = $null
    $parentStore = $null
    try {
        $parentStore = $SourceFolder.Store
        if ($null -ne $parentStore) {
            $wellKnownMap = Get-OPAWellKnownFolderEntryIds -Store $parentStore
        }
    }
    catch { }
    # Do not release the Store COM wrapper here: it may be shared with
    # source discovery and Sent Items folder resolution during this scan.

    $folderPathForSent = ''
    try { $folderPathForSent = [string]$SourceFolder.FolderPath } catch {}
    $specialSentFolder = Test-OPASentLikeFolder -Name $folderName -EntryID $folderEntryId `
        -WellKnownEntryIdMap $wellKnownMap -FolderPath $folderPathForSent `
        -Store $parentStore

    # Age filtering for ordinary folders. Try Restrict first: on Exchange
    # and IMAP stores it filters server-side and is the fastest path. On
    # POP3 PSTs DASL Restrict can still fail for individual stores, so fall
    # back to Sort by ReceivedTime, and break when the cutoff is reached. Sent-like folders are excluded
    # because their archive age may be SentOn-based rather than ReceivedTime.
    if ($null -ne $cutoff -and -not $specialSentFolder) {
        try {
            # DASL date comparisons use UTC; include a one-minute margin
            # and enforce the exact local cutoff on each COM item below.
            $filter = Get-OPADateRestrictFilter -Cutoff ($cutoff.ToUniversalTime().AddMinutes(1))
            $filteredItems = $items.Restrict($filter)
            $filteredItems.Sort('[ReceivedTime]', $false)
            $usedRestrict = $true
        }
        catch {
            $filteredItems = $items
            $usedRestrict = $false
            try {
                # Ascending by ReceivedTime: oldest first. We iterate from
                # index 1 and stop at the first item >= cutoff.
                $items.Sort('[ReceivedTime]', $false)
                $usedSort = $true
            }
            catch {
                $usedSort = $false
            }
        }
    }
    elseif ($null -ne $cutoff -and $specialSentFolder) {
        # SentOn-based fast path for Sent-like folders. Their archive age is
        # SentOn (PR_CLIENT_SUBMIT_TIME), not ReceivedTime. Try Restrict with
        # the corresponding DASL property; fall back to Sort('[SentOn]').
        # Both may not work on every PST: in that case we keep the full-scan
        # behaviour and emit a warning so a slow Sent scan is at least
        # explained in the log.
        try {
            $filter = Get-OPADateRestrictFilter -Cutoff ($cutoff.ToUniversalTime().AddMinutes(1)) -PreferSentOn
            $filteredItems = $items.Restrict($filter)
            $filteredItems.Sort('[SentOn]', $false)
            $usedRestrict = $true
        }
        catch {
            $filteredItems = $items
            $usedRestrict = $false
            try {
                $items.Sort('[SentOn]', $false)
                $usedSort = $true
            }
            catch {
                $usedSort = $false
                Write-Warning ("Sent-like folder '{0}': neither Restrict(date) nor Sort([SentOn]) is available; falling back to full scan ({1} items)." -f $folderName, $originalCount)
            }
        }
    }

    # No age cutoff must not change chronological semantics. Use the same
    # oldest-first ordering; if Outlook refuses sorting, scan the entire folder
    # and sort the candidate rows rather than taking an arbitrary prefix.
    if ($null -eq $cutoff) {
        try {
            $items.Sort($(if ($specialSentFolder) { '[SentOn]' } else { '[ReceivedTime]' }), $false)
            $usedSort = $true
        }
        catch {
            $usedSort = $false
            Write-Warning ("Folder '{0}': Outlook Sort unavailable; full scan required to select oldest messages." -f $folderName)
        }
    }

    $count = 0
    try { $count = [int]$filteredItems.Count } catch {}

    # Upper bound on collected candidates. Prevents an end-to-end scan when
    # every item passes the age test (Sort path has no cutoff-based early
    # break in that case). For planner-style huge limits, fall back to the
    # folder size so enumeration remains complete but bounded by reality.
    if ($Limit -ge 1000000) {
        $maxScan = $count
    }
    else {
        $maxScan = [int][math]::Min([int]$count, [int][math]::Max($Limit * 3, $Limit + 20))
    }

    for ($i = 1; $i -le $count; $i++) {
        $item = $null
        try {
            $item = $filteredItems.Item($i)
            if ($null -eq $item) { continue }

            $class = 0
            try { $class = [int]$item.Class } catch { $selectionErrors++; if ($selectionErrorDetails.Count -lt 20) { $selectionErrorDetails.Add(("Class read failed in '{0}': {1}" -f $folderName,$_.Exception.Message)) | Out-Null }; continue }
            if ($class -ne 43) { continue }
            $mailItemCount++

            $entryId = $null
            try { $entryId = [string]$item.EntryID } catch {}
            if ([string]::IsNullOrWhiteSpace($entryId)) { $selectionErrors++; if ($selectionErrorDetails.Count -lt 20) { $selectionErrorDetails.Add(("EntryID missing in '{0}'" -f $folderName)) | Out-Null }; continue }

            if ($null -ne $excludeSet -and $excludeSet.Contains($entryId)) { $excludedByDuplicate++; continue }

            $archiveDate = Get-OPAArchiveItemDate -Item $item -PreferSentOn:$specialSentFolder
            if ($null -eq $archiveDate) { $missingArchiveDate++; continue }

            # Sort fallback: ascending by ReceivedTime. First item at or past
            # cutoff implies every remaining item is too young too.
            if ($usedSort -and $null -ne $cutoff -and $archiveDate -ge $cutoff) {
                $scannedAllFilteredItems = $false
                break
            }

            # Always enforce the precise local cutoff. The DASL filter above
            # intentionally includes a margin to avoid truncation at minutes.
            if ($null -ne $cutoff -and $archiveDate -ge $cutoff) {
                $excludedByAge++
                continue
            }

            $internetMessageId = Get-OPAInternetMessageId -Item $item
            $senderEmail = $null
            try { $senderEmail = [string]$item.SenderEmailAddress } catch {}
            $size = $null
            try { $size = [int64]$item.Size } catch {}

            $rows.Add([pscustomobject]@{
                EntryID           = $entryId
                Subject           = [string]$item.Subject
                ReceivedTime      = $archiveDate
                ArchiveDate       = $archiveDate
                SentOn            = $(try { [datetime]$item.SentOn } catch { $null })
                FolderName        = $folderName
                FolderPath        = [string]$SourceFolder.FolderPath
                SourceFolderPath  = [string]$SourceFolder.FolderPath
                InternetMessageId = $internetMessageId
                Sender            = $senderEmail
                Size              = $size
            }) | Out-Null

            # Restrict path: bounded by Limit. Preserve deterministic
            # ReceivedTime + EntryID ordering by walking through all items
            # that share the boundary ReceivedTime.
            if ($usedRestrict -and $rows.Count -ge $Limit -and $null -eq $limitBoundaryReceived) {
                $limitBoundaryReceived = $archiveDate
            }
            if ($usedRestrict -and $null -ne $limitBoundaryReceived -and $archiveDate -gt $limitBoundaryReceived) {
                $scannedAllFilteredItems = $false
                break
            }

            # Sort/no-Restrict path: bounded by the safety-margin cap.
            if (-not $usedRestrict -and $usedSort -and $rows.Count -ge $maxScan) {
                $scannedAllFilteredItems = $false
                break
            }
        }
        catch {
            $selectionErrors++
            if ($selectionErrorDetails.Count -lt 20) {
                $selectionErrorDetails.Add(("Selection error in '{0}' item #{1}: {2}" -f $folderName,$i,$_.Exception.Message)) | Out-Null
            }
        }
        finally {
            Release-OPAComObject -Object $item
        }
    }

    $result = @($rows | Sort-Object ArchiveDate,EntryID | Select-Object -First $Limit)

    if ($Diagnostics) {
        [pscustomobject]@{
            Items               = $originalCount
            FilteredItems       = $count
            MailItems           = $mailItemCount
            EligibleByAge       = $rows.Count
            ExcludedByAge       = $excludedByAge
            # Restrict and early-stop Sort do not inspect the entire original
            # folder. In those cases the excluded-by-age figure is partial;
            # planners must not present it as an exact 0.
            ExcludedByAgeExact  = ($null -eq $cutoff -or (-not $usedRestrict -and $scannedAllFilteredItems))
            ExcludedByDuplicate = $excludedByDuplicate
            MissingArchiveDate  = $missingArchiveDate
            MissingReceivedTime = $missingArchiveDate
            SelectionErrors     = $selectionErrors
            SelectionErrorDetails = $selectionErrorDetails.ToArray()
            UsedRestrict        = $usedRestrict
            UsedSort            = $usedSort
            Candidates          = $result
        }
        return
    }

    # Do not release the folder Items collection here. Outlook may return a
    # shared COM Runtime Callable Wrapper that is reused by discovery/planning
    # or subsequent archive operations. Premature ReleaseComObject can make
    # later access fail or produce an empty candidate set.
    $result
}