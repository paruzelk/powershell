#requires -Version 5.1
# ARCH3f: REAL test PST, READ-ONLY Outlook inspection.
# Uses original ARCH2d POP3 scope, ArchivePlanner/SystemFolders and
# ArchiveSelector Year routing. No Archive/Resume/Auto, no COM Move,
# no AddStoreEx/Save/Delete, no claims and NO PST/journal file writes.
. (Join-Path $PSScriptRoot 'ARCH2dBatchCore.ps1')
. (Join-Path $PSScriptRoot 'ArchivePlanner.ps1')
. (Join-Path $PSScriptRoot 'SystemFolders.ps1')
. (Join-Path $PSScriptRoot 'ArchiveGrouping.ps1')
if(-not (Get-Command Get-OPAArchivePartPath -ErrorAction SilentlyContinue)){
    $originalWhatIf=$WhatIfPreference
    try {
        $WhatIfPreference=$false
        . (Join-Path $PSScriptRoot 'MailMover.ps1')
    }finally { $WhatIfPreference=$originalWhatIf }
}
function Assert-OPA265ARCH3fRealTestSource {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [switch]$RequireExisting)
    $p=[IO.Path]::GetFullPath($SourcePst)
    if($p.StartsWith('\\') -or [IO.Path]::GetFileName($p) -cne 'info@stios.ru.pst' -or
       [IO.Path]::GetExtension($p) -cne '.pst'){
        throw 'ARCH3f exact operator-designated local test source info@stios.ru.pst required.'
    }
    if($RequireExisting){
        if(-not [IO.File]::Exists($p)){throw 'ARCH3f test PST must exist for Outlook read-only inventory.'}
        if(([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'ARCH3f forbids reparse/link test PST.'
        }
        if(([IO.FileInfo]::new($p)).Length -le 0){throw 'ARCH3f test PST is empty.'}
    }
    return $p
}
function ConvertTo-OPA265ARCH3fOriginalYearPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Folders,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Candidates,
          [object]$WellKnownEntryIdMap=$null,
          [ValidateSet('Year')][string]$ArchiveGrouping='Year',
          [ValidateRange(1,500)][int]$MaximumCandidates=500)
    $p=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst
    if(@($Folders).Count -gt 128 -or @($Candidates).Count -gt $MaximumCandidates){
        throw 'ARCH3f candidate/folder preview exceeds read-only bound.'
    }
    $folderRows=New-Object 'System.Collections.Generic.List[object]'
    $paths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($folder in $Folders){
        if($null -eq $folder -or
           [string]::IsNullOrWhiteSpace([string]$folder.FolderPath) -or
           [string]::IsNullOrWhiteSpace([string]$folder.FolderName) -or
           -not $paths.Add([string]$folder.FolderPath) -or
           [int]$folder.ItemsCount -lt 0 -or [int]$folder.ItemsCount -gt 500000){
            throw 'ARCH3f malformed/duplicated original folder.'
        }
        if(Test-OPAExcludedSystemFolder -Name ([string]$folder.FolderName) -EntryID ([string]$folder.FolderEntryId) -WellKnownEntryIdMap $WellKnownEntryIdMap){
            throw 'ARCH3f excluded system folder reached candidate plan.'
        }
        $folderRows.Add([pscustomobject][ordered]@{
            SourceFolderPath=[string]$folder.FolderPath
            SourceFolderName=[string]$folder.FolderName
            SourceFolderEntryId=[string]$folder.FolderEntryId
            ItemsCount=[int]$folder.ItemsCount
            SentLike=[bool]$folder.SentLike
        })|Out-Null
    }
    $candidateRows=New-Object 'System.Collections.Generic.List[object]'
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($item in $Candidates){
        $id=[string]$item.EntryID
        $date=[datetime]$item.ArchiveDate
        $folderPath=[string]$item.SourceFolderPath
        $folderName=[string]$item.FolderName
        if($id -cnotmatch '^[0-9A-Fa-f]{16,1024}$' -or -not $ids.Add($id) -or
           -not $paths.Contains($folderPath) -or
           $date.Year -lt 1900 -or $date.Year -gt 2100){
            throw 'ARCH3f original candidate identity, date or folder invalid.'
        }
        $year=$date.Year
        # Reuse ORIGINAL MailMover PST-part naming and ArchiveGrouping target.
        $archive=Get-OPAArchivePartPath -SourcePst $p -Year $year -Part 1
        $target=Get-OPAArchiveTargetPath -ReceivedTime $date -SourceFolderName $folderName -SourceFolderPath $folderPath -Grouping $ArchiveGrouping
        $candidateRows.Add([pscustomobject][ordered]@{
            EntryID=$id
            SourceFolderPath=$folderPath
            ArchiveDate=$date
            ArchiveYear=$year
            PlannedArchivePart1Pst=$archive
            PlannedTargetFolderPath=$target
            AttachmentCount=if($item.PSObject.Properties.Name -contains 'AttachmentCount'){[int]$item.AttachmentCount}else{-1}
        })|Out-Null
    }
    $years=@($candidateRows.ToArray()|Group-Object ArchiveYear|Sort-Object Name|ForEach-Object{
        [pscustomobject]@{Year=[int]$_.Name;SampleCount=[int]$_.Count}
    })
    $sum=0
    foreach($f in $folderRows){$sum+=[int64]$f.ItemsCount}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3f.OriginalYearPreview.1'
        Status='ExistingTestPstRealMailRoutePreviewNoPstOrComWrites'
        SourcePst=$p
        SourceDesignation='OperatorDesignatedTestPstWithRealMailboxContent'
        ArchiveGrouping='Year'
        EligibleNonemptyFolderCount=$folderRows.Count
        FolderItemsCountSum=[int64]$sum
        SampleCandidateCount=$candidateRows.Count
        YearSampleCounts=$years
        Folders=@($folderRows.ToArray())
        Candidates=@($candidateRows.ToArray())
        YearCountsAreFullInventory=$false
        YearFolderRoutesUseOriginalFunctions=$true
        NoRealMoveMade=$true
        RealPilotWriterIntegrated=$false
        ArchiveResumeAutoRemainClosed=$true
        AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
function Invoke-OPA265ARCH3fRealTestPreflight {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Plan','Inventory')][string]$Mode,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [ValidateRange(1,20)][int]$SamplePerFolder=5,
          [ValidateRange(1,128)][int]$MaxFolders=64,
          [ValidateRange(0,120)][int]$OlderThanMonths=0)
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst -RequireExisting:($Mode -ceq 'Inventory')
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3f.Plan.1'
            Status='OperatorDesignatedRealTestPstAcceptedReadOnlyIntegrationPlan'
            SourcePst=$source
            SourceDesignation='OperatorDesignatedTestPstWithRealMailboxContent'
            UsesExistingArch2dPop3SessionScope=$true
            UsesOriginalEligibleFolderWalker=$true
            UsesOriginalCandidateDateAndSentOn=$true
            UsesOriginalYearArchiveRoutes=$true
            RealPstMayBeUsedForFutureBoundedLivePilot=$true
            CurrentMode='Plan'
            OutlookContacted=$false
            SourcePstOpened=$false
            ArchivePstOpenedOrCreated=$false
            NoPstOrJournalWrites=$true
            LiveMoveIntegrated=$false
            OriginalArchiveResumeAutoStillBlocked=$true
            AutomaticMoveRetryAllowed=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
       [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3f Inventory requires Windows PowerShell 5.1 in STA mode.'
    }
    # Use the original verified real POP3 AccountType=2, profile Outlook,
    # StoreID != DefaultStore and exact file-path scope from ARCH2d pilot.
    # Never create PST; dummy layout archive path is not read or written.
    $layout=Get-OPA265ARCH2dLayout -RunId '11111111-2222-4333-8444-555555555555' -LocalAppData $env:LOCALAPPDATA
    $session=$null;$root=$null
    try {
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst $source
        $root=$session.SourceStore.GetRootFolder()
        $known=Get-OPAWellKnownFolderEntryIds -Store $session.SourceStore
        $folders=@(Get-OPAEligiblePop3MailFolders -RootFolder $root -WellKnownEntryIdMap $known)
        if($folders.Count -gt $MaxFolders -or $folders.Count -gt 128){
            throw 'ARCH3f folder inventory exceeds authorized bounded folder count; no results accepted.'
        }
        $folderRows=New-Object 'System.Collections.Generic.List[object]'
        $candidates=New-Object 'System.Collections.Generic.List[object]'
        $diagnostics=New-Object 'System.Collections.Generic.List[object]'
        $cutoff=if($OlderThanMonths -gt 0){(Get-Date).AddMonths(-$OlderThanMonths)}else{$null}
        foreach($folder in $folders){
            $name=[string]$folder.Name
            $entry=[string]$folder.EntryID
            $path=[string]$folder.FolderPath
            $num=[int]$folder.Items.Count
            if($num -lt 1 -or $num -gt 500000){throw 'ARCH3f original folder item count outside bounded range.'}
            $sent=Test-OPASentLikeFolder -Name $name -EntryID $entry -WellKnownEntryIdMap $known -FolderPath $path -Store $session.SourceStore
            $folderRows.Add([pscustomobject]@{
                FolderName=$name;FolderPath=$path;FolderEntryId=$entry;ItemsCount=$num;SentLike=[bool]$sent
            })|Out-Null
            # Original selector handles SentOn, age/filter/order, and Outlook's
            # candidate scope. Use small Limit; year counts are SAMPLE ONLY.
            $remaining=[Math]::Min($SamplePerFolder,[Math]::Max(0,500-$candidates.Count))
            if($remaining -lt 1){break}
            $diag=Get-OPAArchiveCandidates -SourceFolder $folder -Limit $remaining -OlderThanCutoff $cutoff -Diagnostics
            if([int]$diag.SelectionErrors -gt 0){
                throw ('ARCH3f original selector errors in '+$path+': '+(@($diag.SelectionErrorDetails) -join '; '))
            }
            $diagnostics.Add([pscustomobject]@{SourceFolderPath=$path;ItemsCount=$num;CandidateSampleCount=@($diag.Candidates).Count;UsedSort=[bool]$diag.UsedSort;UsedRestrict=[bool]$diag.UsedRestrict})|Out-Null
            foreach($item in @($diag.Candidates)){
                $candidates.Add($item)|Out-Null
            }
        }
        $preview=ConvertTo-OPA265ARCH3fOriginalYearPreview -SourcePst $source -Folders @($folderRows.ToArray()) -Candidates @($candidates.ToArray()) -WellKnownEntryIdMap $known
        $preview | Add-Member -NotePropertyName OutlookProcessId -NotePropertyValue ([int]$session.OutlookProcessId)
        $preview | Add-Member -NotePropertyName OutlookProcessStartUtcTicks -NotePropertyValue ([int64]$session.OutlookProcessStartUtcTicks)
        $preview | Add-Member -NotePropertyName ProfileName -NotePropertyValue ([string]$session.Namespace.CurrentProfileName)
        $preview | Add-Member -NotePropertyName SourceStoreId -NotePropertyValue ([string]$session.SourceStore.StoreID)
        $preview | Add-Member -NotePropertyName Pop3ScopeApproved -NotePropertyValue ([bool]$session.Scope.Approved)
        $preview | Add-Member -NotePropertyName SelectedFolderDiagnostics -NotePropertyValue @($diagnostics.ToArray())
        $preview | Add-Member -NotePropertyName OutlookContacted -NotePropertyValue $true
        $preview | Add-Member -NotePropertyName SourcePstOpened -NotePropertyValue $true
        $preview | Add-Member -NotePropertyName ArchivePstOpenedOrCreated -NotePropertyValue $false
        $preview | Add-Member -NotePropertyName NoPstOrJournalWrites -NotePropertyValue $true
        $preview | Add-Member -NotePropertyName SourcePstLengthBytes -NotePropertyValue ([int64]([IO.FileInfo]::new($source)).Length)
        return $preview
    }finally {
        # Session owns its SourceStore and Namespace COM wrappers. Release only
        # the extra root and leave folder wrappers managed by the original
        # Outlook session. No Outlook.Quit or Attach/AddStore/Delete/Save.
        Release-OPA265ARCH2c4Com -Object $root
        Close-OPA265ARCH2dSession -Session $session
    }
}
