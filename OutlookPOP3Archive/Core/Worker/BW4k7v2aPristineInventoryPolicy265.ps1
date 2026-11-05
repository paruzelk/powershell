#requires -Version 5.1
# BW4k7v2a: bounded, fail-closed, read-only PST visible-folder inventory.
function Test-OPA265BW4k7v2aPristineInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Rows)
    if ($null -eq $Rows -or $Rows.Count -eq 0) {
        throw 'BW4k7v2a inventory missing: refuse pilot creation.'
    }
    if ($Rows.Count -gt 128) {
        throw 'BW4k7v2a inventory exceeds maximum 128 folders.'
    }
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $totalChildren=0L
    $visibleItems=0L
    $index=0
    foreach($row in $Rows) {
        if ($null -eq $row) { throw 'BW4k7v2a null folder observation.' }
        foreach($field in @('FolderId','Depth','ItemCount','ChildFolderCount')) {
            if ($row.PSObject.Properties.Name -cnotcontains $field) {
                throw ('BW4k7v2a missing mandatory folder field '+$field)
            }
        }
        $folderId=[string]$row.FolderId
        if ([string]::IsNullOrWhiteSpace($folderId)) {
            throw 'BW4k7v2a folder EntryID missing.'
        }
        if (-not $ids.Add($folderId)) { throw 'BW4k7v2a repeated folder EntryID.' }
        $depth=[long]$row.Depth
        $itemCount=[long]$row.ItemCount
        $childCount=[long]$row.ChildFolderCount
        if ($depth -lt 0 -or $depth -gt 32 -or
            $itemCount -lt 0 -or $childCount -lt 0 -or $childCount -gt 128) {
            throw 'BW4k7v2a invalid or unbounded folder observation.'
        }
        if (($index -eq 0 -and $depth -ne 0) -or
            ($index -gt 0 -and $depth -eq 0)) {
            throw 'BW4k7v2a folder root/depth structure invalid.'
        }
        if ($depth -eq 32 -and $childCount -gt 0) {
            throw 'BW4k7v2a folder depth limit prevents complete scan.'
        }
        $totalChildren += $childCount
        $visibleItems += $itemCount
        $index++
    }
    if ($totalChildren -ne ($Rows.Count-1)) {
        throw 'BW4k7v2a incomplete or inconsistent folder enumeration.'
    }
    $reasons=@()
    if ($visibleItems -gt 0) { $reasons=@('PreexistingVisibleOutlookItems') }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a.PristineVisiblePst.1'
        Pristine=($visibleItems -eq 0)
        FolderCount=[int]$Rows.Count
        VisibleItemCount=$visibleItems
        ReasonCodes=$reasons
        ReadOnlyVisibleFolderInventoryOnly=$true
        PhysicalPstEmptinessProven=$false
        AutomaticRecoveryOrFallbackAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
