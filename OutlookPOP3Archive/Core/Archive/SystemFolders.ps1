# Centralized Outlook system-folder classification.
# Plan, Archive and Selector all used to keep their own copies of these
# lists; any edit in one place silently desynchronized the others.

$script:OPADeletedFolderNames = @(
    'Deleted Items','Deleted','Уделенные','Удаленные','Удалённые','Корзина','Trash'
)

$script:OPADraftsFolderNames = @(
    'Drafts','Черновики'
)
$script:OPAOutboxFolderNames = @('Outbox','Исходящие','Исходящие сообщения')
$script:OPAJunkFolderNames = @('Junk','Junk E-mail','Junk Email','Спам','Нежелательная почта')

# Folders whose archive age is based on SentOn rather than ReceivedTime.
$script:OPASentLikeFolderPattern = '^(Отправленные|Sent Items|Sent Mail)$'

function Test-OPAExcludedSystemFolder {
    param(
        [AllowEmptyString()][string]$Name,
        [AllowEmptyString()][string]$EntryID = '',
        [object]$WellKnownEntryIdMap = $null,
        [bool]$ArchiveDeletedItems = $false,
        [bool]$ArchiveDrafts = $false,
        [bool]$ArchiveJunk = $false
    )

    # Fail closed for Outbox, even when GetDefaultFolder(4) was unavailable
    # but other well-known IDs were present. Moving unsent messages is unsafe.
    if ($Name -and $script:OPAOutboxFolderNames -icontains $Name) { return $true }
    # Junk remains an explicit opt-in; favor safety if a partial map lacks Junk.
    if (-not $ArchiveJunk -and $Name -and $script:OPAJunkFolderNames -icontains $Name) { return $true }

    # Map is authoritative whenever it is non-empty. A folder whose EntryID
    # is absent from the map is user-defined, not a system folder, and must
    # not be classified by name -- otherwise a user folder literally named
    # "Drafts" under any path would be wrongly excluded.
    if (-not [string]::IsNullOrWhiteSpace($EntryID) -and
        $null -ne $WellKnownEntryIdMap -and
        @($WellKnownEntryIdMap.Keys).Count -gt 0) {
        if ($WellKnownEntryIdMap.ContainsKey($EntryID)) {
            $kind = [string]$WellKnownEntryIdMap[$EntryID]
            if ($kind -eq 'DeletedItems' -and -not $ArchiveDeletedItems) { return $true }
            if ($kind -eq 'Drafts'       -and -not $ArchiveDrafts)       { return $true }
            if ($kind -eq 'Outbox')                                      { return $true }
            if ($kind -eq 'Junk'         -and -not $ArchiveJunk)         { return $true }
        }
        return $false
    }

    # Map unavailable: name-based fallback for stores where
    # GetDefaultFolder did not resolve any well-known folder.
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if (-not $ArchiveDeletedItems -and $script:OPADeletedFolderNames -icontains $Name) { return $true }
    if (-not $ArchiveDrafts -and $script:OPADraftsFolderNames -icontains $Name) { return $true }
    return $false
}

function Test-OPASentLikeFolder {
    param(
        [AllowEmptyString()][string]$Name,
        [AllowEmptyString()][string]$EntryID = '',
        [object]$WellKnownEntryIdMap = $null,
        [string]$FolderPath = '',
        [object]$Store = $null
    )

    if (-not [string]::IsNullOrWhiteSpace($EntryID) -and
        $null -ne $WellKnownEntryIdMap -and
        $WellKnownEntryIdMap.ContainsKey($EntryID)) {
        return ([string]$WellKnownEntryIdMap[$EntryID] -eq 'SentMail')
    }

    # Subfolders under Outlook's default Sent Items are sent-like, even if
    # their own EntryIDs are not present in the well-known folder map.
    # Resolve the official path before falling back to localized names.
    if ($null -ne $Store -and -not [string]::IsNullOrWhiteSpace($FolderPath)) {
        $sent = $null
        try {
            $sent = $Store.GetDefaultFolder(5)
            if ($null -ne $sent) {
                $sentPath = [string]$sent.FolderPath
                if (-not [string]::IsNullOrWhiteSpace($sentPath)) {
                    if ($FolderPath -ieq $sentPath -or
                        $FolderPath.StartsWith($sentPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
                        return $true
                    }
                }
            }
        }
        catch { }
        finally {
            # GetDefaultFolder can return a shared RCW. Do not release it here.
        }
    }

    # A populated map distinguishes user-defined folders named 'Sent Items'
    # from Outlook's system folder. Fall back to localized names only when
    # the system SentMail folder could not be resolved.
    if ($null -ne $WellKnownEntryIdMap -and @($WellKnownEntryIdMap.Values | Where-Object { $_ -eq 'SentMail' }).Count -gt 0) {
        return $false
    }
    return (-not [string]::IsNullOrWhiteSpace($Name) -and
        $Name -match $script:OPASentLikeFolderPattern)
}
# Well-known folder EntryIDs, keyed by StoreID. EntryID-based classification
# is locale- and rename-proof: a user folder literally named "Drafts" has a
# different EntryID than the store's own Drafts folder.
$script:OPAWellKnownFolderCache = @{}

function Get-OPAWellKnownFolderEntryIds {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Store)

    $storeId = ''
    try { $storeId = [string]$Store.StoreID } catch {}
    if (-not [string]::IsNullOrWhiteSpace($storeId) -and
        $script:OPAWellKnownFolderCache.ContainsKey($storeId)) {
        return $script:OPAWellKnownFolderCache[$storeId]
    }

    # OlDefaultFolders: 3=DeletedItems, 4=Outbox, 5=SentMail, 16=Drafts, 23=Junk.
    # GetDefaultFolder throws for folders missing in the store (POP3 PST may
    # lack Junk, for instance), so each lookup is guarded.
    $kinds = [ordered]@{
        DeletedItems = 3
        Outbox       = 4
        SentMail     = 5
        Drafts       = 16
        Junk         = 23
    }

    $map = @{}
    foreach ($kind in $kinds.Keys) {
        $folder = $null
        try {
            $folder = $Store.GetDefaultFolder([int]$kinds[$kind])
            if ($null -ne $folder) {
                $eid = ''
                try { $eid = [string]$folder.EntryID } catch {}
                if (-not [string]::IsNullOrWhiteSpace($eid)) {
                    $map[$eid] = $kind
                }
            }
        }
        catch { }
        finally {
            if ($folder) {
                try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($folder) } catch {}
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($storeId)) {
        $script:OPAWellKnownFolderCache[$storeId] = $map
    }
    return $map
}
function Clear-OPAWellKnownFolderCache {
    [CmdletBinding()]
    param()
    $script:OPAWellKnownFolderCache = @{}
}