. "$PSScriptRoot\ArchiveSelector.ps1"

function Get-OPAFlatFolders {
    param([Parameter(Mandatory=$true)][object]$Folder)
    if ($null -eq $Folder) { return @() }

    # Shared accumulator avoids the O(N^2) reallocation caused by
    # '$result += ...' on plain arrays. The helper below appends directly
    # into this single list. Returned as Object[] for compatibility with
    # every existing caller.
    $acc = New-Object System.Collections.Generic.List[object]
    Add-OPAFlatFoldersAccumulator -Folder $Folder -Accumulator $acc
    return $acc.ToArray()
}

function Add-OPAFlatFoldersAccumulator {
    param(
        [Parameter(Mandatory=$true)][object]$Folder,
        [Parameter(Mandatory=$true)][object]$Accumulator
    )
    if ($null -eq $Folder) { return }

    $Accumulator.Add($Folder) | Out-Null

    # Do not wrap $Folder.Folders in @() -- that would materialize the COM
    # collection into a new array on every call. foreach over the Folders
    # collection is already a valid enumerator; the try/catch keeps the
    # previous behaviour for folders whose Folders property throws.
    try {
        foreach ($child in $Folder.Folders) {
            Add-OPAFlatFoldersAccumulator -Folder $child -Accumulator $Accumulator
        }
    }
    catch { }
}

# FIX10a: common recursive source-folder enumeration used by Plan, Archive and Resume.
# Excluded system folders are pruned together with their descendants. Traversal
# errors are fatal: silently skipping a nested folder would make an incomplete
# archive look successful.
function Get-OPAEligiblePop3MailFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$RootFolder,
        [object]$WellKnownEntryIdMap = $null,
        [switch]$ArchiveDeletedItems,
        [switch]$ArchiveDrafts,
        [switch]$ArchiveJunk
    )
    $result = New-Object System.Collections.Generic.List[object]
    Add-OPAEligiblePop3MailFolders -Folder $RootFolder -Accumulator $result `
        -WellKnownEntryIdMap $WellKnownEntryIdMap `
        -ArchiveDeletedItems:$ArchiveDeletedItems -ArchiveDrafts:$ArchiveDrafts `
        -ArchiveJunk:$ArchiveJunk -IsRoot
    # Return individual objects through the pipeline; callers wrap with @().
    return $result.ToArray()
}

function Add-OPAEligiblePop3MailFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Folder,
        [Parameter(Mandatory=$true)][object]$Accumulator,
        [object]$WellKnownEntryIdMap,
        [switch]$ArchiveDeletedItems,
        [switch]$ArchiveDrafts,
        [switch]$ArchiveJunk,
        [switch]$IsRoot
    )
    $path = ''
    try { $path = [string]$Folder.FolderPath } catch { throw "Unable to read folder path while enumerating POP3 PST: $($_.Exception.Message)" }
    if (-not $IsRoot) {
        $name = ''
        $entryId = ''
        try { $name = [string]$Folder.Name } catch { throw "Unable to read POP3 folder name '$path': $($_.Exception.Message)" }
        try { $entryId = [string]$Folder.EntryID } catch { }
        if (Test-OPAExcludedSystemFolder -Name $name -EntryID $entryId `
                -WellKnownEntryIdMap $WellKnownEntryIdMap `
                -ArchiveDeletedItems ([bool]$ArchiveDeletedItems) `
                -ArchiveDrafts ([bool]$ArchiveDrafts) -ArchiveJunk ([bool]$ArchiveJunk)) {
            return  # Exclude the folder AND its complete subtree.
        }
        $mailCapable = $true
        try { $mailCapable = ([int]$Folder.DefaultItemType -eq 0) } catch { }
        if ($mailCapable) {
            $count = 0
            try { $count = [int]$Folder.Items.Count }
            catch { throw "Unable to count POP3 mail items in '$path': $($_.Exception.Message)" }
            if ($count -gt 0) { [void]$Accumulator.Add($Folder) }
        }
    }
    try {
        foreach ($child in $Folder.Folders) {
            Add-OPAEligiblePop3MailFolders -Folder $child -Accumulator $Accumulator `
                -WellKnownEntryIdMap $WellKnownEntryIdMap `
                -ArchiveDeletedItems:$ArchiveDeletedItems -ArchiveDrafts:$ArchiveDrafts `
                -ArchiveJunk:$ArchiveJunk
        }
    }
    catch { throw "Unable to traverse nested POP3 folders under '$path': $($_.Exception.Message)" }
}

function New-OPAArchivePlan {
    param(
        [Parameter(Mandatory=$true)][object]$Discovery,
        [object]$Settings,
        [ValidateRange(0,2147483647)][int]$Limit = 0,
        [int]$OlderThanMonths = 12,
        [object]$ArchiveCutoff,
        [switch]$ArchiveDeletedItems,
        [switch]$ArchiveDrafts,
        [switch]$ArchiveJunk,
        [switch]$VerboseItems
    )

    if (-not $PSBoundParameters.ContainsKey('ArchiveCutoff')) {
        if ($OlderThanMonths -gt 0) { $ArchiveCutoff = (Get-Date).AddMonths(-$OlderThanMonths) } else { $ArchiveCutoff = $null }
    }

    $sources=@($Discovery.Pop3Sources)
    $items=@()
    $folders=@()
    $n=0

    foreach ($source in $sources) {
        $n++
        $path=[string]$source.FilePath
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ([IO.Path]::GetExtension($path) -ine ".pst") { continue }

        $id="POP3-{0:D3}" -f $n
        $handle=$null
        if ($source.PSObject.Properties.Name -contains "StoreHandle") {
            $handle=$source.StoreHandle
        }

        $items += [pscustomobject]@{
            PlanItemId="$id-SOURCE"; SourceId=$id
            AccountName=$source.AccountName; UserName=$source.UserName
            Protocol=$source.Protocol; SourceStoreName=$source.StoreName
            SourceFilePath=$path; Operation="Archive"; Status="Planned"
            HasStoreHandle=($null -ne $handle)
        }

        if ($null -eq $handle) { continue }

        try { $rootFolder=$handle.GetRootFolder() } catch { $rootFolder=$null }
        if ($null -eq $rootFolder) { continue }

        $wellKnownMap = $null
        try { $wellKnownMap = Get-OPAWellKnownFolderEntryIds -Store $handle } catch { $wellKnownMap = $null }

        $fi=0
        $rootPath = ''
        try { $rootPath = [string]$rootFolder.FolderPath } catch {}
        # One shared policy for Plan, Archive and Resume: all nested mail
        # folders are included, except entire excluded system subtrees.
        foreach ($folder in @(Get-OPAEligiblePop3MailFolders -RootFolder $rootFolder `
                    -WellKnownEntryIdMap $wellKnownMap `
                    -ArchiveDeletedItems:$ArchiveDeletedItems `
                    -ArchiveDrafts:$ArchiveDrafts -ArchiveJunk:$ArchiveJunk)) {
            $folderNameForPolicy = ''
            $folderPath = ''
            $count = 0
            try { $folderNameForPolicy = [string]$folder.Name } catch {}
            try { $folderPath = [string]$folder.FolderPath } catch {}
            try { $count = [int]$folder.Items.Count } catch { $count = 0 }

            # The store root and empty folders are not archive source folders.
            # This keeps Plan and Archive aligned and prevents empty Outlook
            # system folders from polluting the folder summary.
            if (-not [string]::IsNullOrWhiteSpace($rootPath) -and $folderPath -ieq $rootPath) { continue }
            if ($count -le 0) { continue }
            $folderEntryIdForPolicy = ''
            try { $folderEntryIdForPolicy = [string]$folder.EntryID } catch {}
            if (Test-OPAExcludedSystemFolder -Name $folderNameForPolicy -EntryID $folderEntryIdForPolicy -WellKnownEntryIdMap $wellKnownMap -ArchiveDeletedItems ([bool]$ArchiveDeletedItems) -ArchiveDrafts ([bool]$ArchiveDrafts) -ArchiveJunk ([bool]$ArchiveJunk)) { continue }
            try { if ([int]$folder.DefaultItemType -ne 0) { continue } } catch {}
            $fi++
            $entryId=""
            try { $entryId=[string]$folder.EntryID } catch {}

            $folders += [pscustomobject]@{
                FolderItemId="{0}-F{1:D3}" -f $id,$fi
                SourceId=$id; AccountName=$source.AccountName
                UserName=$source.UserName; Protocol=$source.Protocol
                StoreName=$source.StoreName; PSTPath=$path
                FolderName=[string]$folder.Name; FolderPath=$folderPath
                EntryID=$entryId; ItemCount=$count
                TestLimit=$Limit; OlderThanMonths=$OlderThanMonths; ArchiveCutoff=$(if($PSBoundParameters.ContainsKey('ArchiveCutoff')){$ArchiveCutoff}else{$null}); ArchiveGrouping=$(if($Settings -and $Settings.PSObject.Properties.Name -contains "ArchiveGrouping"){$Settings.ArchiveGrouping}else{"YearQuarter"}); ArchiveDeletedItems=[bool]$ArchiveDeletedItems; ArchiveDrafts=[bool]$ArchiveDrafts; ArchiveJunk=[bool]$ArchiveJunk; EligibleItemCount=$null; ExcludedByAge=0; ExcludedByAgeExact=$false; ExcludedByDuplicate=0; SelectionErrors=0; MissingReceivedTime=0; PlannedItemCount=0
                Operation="Evaluate"; Status="Planned"; LiveFolder=$folder
            }
            $folderPlan = $folders[-1]
            try {
                $selection = Get-OPAArchiveCandidates -SourceFolder $folder -Limit 2147483647 -OlderThanCutoff $(if($OlderThanMonths -gt 0){$ArchiveCutoff}else{$null}) -Diagnostics
                $folderPlan.EligibleItemCount = [int]$selection.EligibleByAge
                $folderPlan.ExcludedByAge = [int]$selection.ExcludedByAge
                $folderPlan.ExcludedByAgeExact = [bool]$selection.ExcludedByAgeExact
                $folderPlan.ExcludedByDuplicate = [int]$selection.ExcludedByDuplicate
                $folderPlan.SelectionErrors = [int]$selection.SelectionErrors
                $folderPlan.MissingReceivedTime = [int]$selection.MissingReceivedTime
                $folderPlan.PlannedItemCount = if($Limit -gt 0){[Math]::Min($Limit,[int]$selection.EligibleByAge)}else{[int]$selection.EligibleByAge}
                # Cache the selected candidates so Write-OPAArchivePlan does not
                # enumerate the same Outlook folder a second time.
                if ($Limit -gt 0) {
                    $folderPlan | Add-Member -NotePropertyName SelectedCandidates -NotePropertyValue @($selection.Candidates | Select-Object -First $Limit) -Force
                }
                else {
                    $folderPlan | Add-Member -NotePropertyName SelectedCandidates -NotePropertyValue @($selection.Candidates) -Force
                }
            } catch {
                $folderPlan.EligibleItemCount = $null
                $folderPlan.PlannedItemCount = 0
            }
        }
    }

    # The Archive workflow uses one transaction-wide Limit. Normalize the
    # planner output to the same global candidate pool so Plan and Archive
    # cannot disagree merely because candidates are distributed across folders.
    if ($Limit -gt 0) {
        $globalCandidates = @($folders | ForEach-Object { @($_.SelectedCandidates) } | Sort-Object ArchiveDate,EntryID | Select-Object -First $Limit)
        $selectedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($candidate in $globalCandidates) { [void]$selectedIds.Add([string]$candidate.EntryID) }
        foreach ($folderPlan in $folders) {
            $selected = @($folderPlan.SelectedCandidates | Where-Object { $selectedIds.Contains([string]$_.EntryID) } | Sort-Object ArchiveDate,EntryID)
            $folderPlan.SelectedCandidates = $selected
            $folderPlan.PlannedItemCount = $selected.Count
        }
    }

    [pscustomobject]@{
        PlanVersion="1.4"; Created=Get-Date; Profile=$Discovery.Profile
        TestLimit=$Limit; OlderThanMonths=$OlderThanMonths; ArchiveCutoff=$(if($PSBoundParameters.ContainsKey('ArchiveCutoff')){$ArchiveCutoff}else{$null}); ArchiveGrouping=$(if($Settings -and $Settings.PSObject.Properties.Name -contains "ArchiveGrouping"){$Settings.ArchiveGrouping}else{"YearQuarter"}); ArchiveDeletedItems=[bool]$ArchiveDeletedItems; ArchiveDrafts=[bool]$ArchiveDrafts
        SourceCount=$sources.Count; ItemCount=$items.Count
        FolderCount=$folders.Count; Sources=$sources
        Items=$items; Folders=$folders; Settings=$Settings
    }
}

function Test-OPAArchivePlan {
    param([Parameter(Mandatory=$true)][object]$Plan)
    if ($null -eq $Plan) { throw "Plan is null." }

    foreach ($item in @($Plan.Items)) {
        if ($item.Protocol -ne "POP3") { throw "Safety check: non-POP3 source." }
        if ([IO.Path]::GetExtension([string]$item.SourceFilePath) -ine ".pst") {
            throw "Safety check: source is not PST."
        }
    }
    foreach ($folder in @($Plan.Folders)) {
        if ($folder.Protocol -ne "POP3") { throw "Safety check: non-POP3 folder." }
    }
    $true
}

function Write-OPAArchivePlan {
    param([Parameter(Mandatory=$true)][object]$Plan,[switch]$VerboseItems)

    Write-Host ""
    Write-Host "## Archive Plan"
    Write-Host ""
    Write-Host ("Sources : {0}" -f $Plan.SourceCount)
    Write-Host ("Items   : {0}" -f $Plan.ItemCount)
    Write-Host ("Folders : {0}" -f $Plan.FolderCount)
    Write-Host ("Available items : {0}" -f (($Plan.Folders | Measure-Object -Property ItemCount -Sum).Sum))
    Write-Host ("Older than     : {0}" -f $(if($Plan.OlderThanMonths -gt 0){"$($Plan.ArchiveCutoff.ToString('yyyy-MM-dd HH:mm:ss')) (OlderThanMonths=$($Plan.OlderThanMonths))"}else{'Disabled'}))
    if($Plan.TestLimit -gt 0){ Write-Host ("Selected limit  : {0}" -f $Plan.TestLimit) }
    Write-Host ""

    foreach ($item in @($Plan.Items)) {
        Write-Host ("[{0}] {1}" -f $item.PlanItemId,$item.AccountName)
        Write-Host ("Protocol : {0}" -f $item.Protocol)
        Write-Host ("Store    : {0}" -f $item.SourceStoreName)
        Write-Host ("PST      : {0}" -f $item.SourceFilePath)
        Write-Host ("Store    : {0}" -f $(if($item.HasStoreHandle){"Available"}else{"Unavailable"}))
        Write-Host ("Operation: {0}" -f $item.Operation)
        Write-Host ("Status   : {0}" -f $item.Status)
        Write-Host ""
    }

    if ($Plan.FolderCount -gt 0) {
        Write-Host "Folder summary"
        Write-Host "--------------"
        foreach ($folder in @($Plan.Folders)) {
            Write-Host ("[{0}] {1}" -f $folder.FolderItemId,$folder.FolderPath)
            Write-Host ("  Items: {0}" -f $folder.ItemCount)
            Write-Host ("  Eligible by age: {0}" -f $(if($null -ne $folder.EligibleItemCount){$folder.EligibleItemCount}else{'unknown'}))
            Write-Host ("  Excluded by age: {0}" -f $(if ($folder.ExcludedByAgeExact) {
                [string]$folder.ExcludedByAge
            } else {
                'not fully counted (optimized selection)'
            }))
            Write-Host ("  Excluded duplicate: {0}" -f $folder.ExcludedByDuplicate)
            Write-Host ("  Missing ReceivedTime: {0}" -f $folder.MissingReceivedTime)
            Write-Host ("  Selection errors: {0}" -f $folder.SelectionErrors)
            Write-Host ("  Planned by Limit: {0}" -f $folder.PlannedItemCount)
        }
        if($Plan.TestLimit -gt 0){
            $grouping=if($Plan.ArchiveGrouping){[string]$Plan.ArchiveGrouping}else{"YearQuarter"}
            $selectedTotal=0
            foreach($folder in @($Plan.Folders)){
                if($folder.ItemCount -le 0 -or $null -eq $folder.LiveFolder){continue}
                try{
                    $c=@($folder.SelectedCandidates)
                    $selectedTotal += $c.Count
                    if($VerboseItems){
                        foreach($x in $c){Write-Host ("  {0:yyyy-MM-dd HH:mm:ss} | {1} | Target={2}" -f $x.ReceivedTime,$x.Subject,(Get-OPAArchiveTargetPath -ReceivedTime $x.ReceivedTime -SourceFolderName ([string]$folder.FolderName) -SourceFolderPath ([string]$folder.FolderPath) -Grouping $grouping))}
                    }
                    if($c.Count -gt 0){Write-Host ("  Selected oldest : {0:yyyy-MM-dd HH:mm:ss}" -f $c[0].ReceivedTime); Write-Host ("  Selected newest : {0:yyyy-MM-dd HH:mm:ss}" -f $c[$c.Count-1].ReceivedTime); Write-Host ("  Selected count  : {0}" -f $c.Count)}
                }catch{Write-Host ("  Candidate selection output failed: {0}" -f $_.Exception.Message)}
            }
            Write-Host ("Selected total : {0}" -f $selectedTotal)
        }
    } else {
        Write-Host "Folder analysis: no live Outlook Store was exposed by Discovery."
        Write-Host "Source-level planning remains valid."
    }
}
