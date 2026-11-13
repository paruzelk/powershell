#requires -Version 5.1
# ARCH3g: existing annual PST collision + pinned Inbox MailItem identity gate.
# This stage is READ ONLY. It never moves mail, writes journal or creates PST.
. (Join-Path $PSScriptRoot 'ARCH3fRealTestPstPreflight.ps1')

function Assert-OPA265ARCH3gSourceEntryId {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourceEntryId)
    if($SourceEntryId -cnotmatch '^[0-9A-Fa-f]{16,1024}$'){
        throw 'ARCH3g requires a complete exact hex Outlook SourceEntryId.'
    }
    return $SourceEntryId.ToUpperInvariant()
}

function Get-OPA265ARCH3gPartPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][ValidateRange(1900,2100)][int]$ArchiveYear,
          [Parameter(Mandatory=$true)][string]$SourceEntryId,
          [AllowEmptyCollection()][object[]]$ExistingParts=@())
    $path=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst
    $id=Assert-OPA265ARCH3gSourceEntryId -SourceEntryId $SourceEntryId
    if(@($ExistingParts).Count -gt 100){throw 'ARCH3g unexpected annual part count; manual review.'}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $highest=0
    foreach($part in @($ExistingParts)){
        if($null -eq $part){throw 'ARCH3g null archive part.'}
        $n=[int]$part.Part
        if($n -lt 1 -or $n -gt 99 -or [int]$part.Year -ne $ArchiveYear){
            throw 'ARCH3g anomalous archive part year/ordinal.'
        }
        $expected=[IO.Path]::GetFullPath((Get-OPAArchivePartPath -SourcePst $path -Year $ArchiveYear -Part $n))
        $actual=[IO.Path]::GetFullPath([string]$part.Path)
        if(-not [string]::Equals($actual,$expected,[StringComparison]::OrdinalIgnoreCase) -or
           -not $seen.Add($expected)){
            throw 'ARCH3g archive part path or duplication mismatch.'
        }
        $rows.Add([pscustomobject][ordered]@{Year=$ArchiveYear;Part=$n;Path=$expected})|Out-Null
        if($n -gt $highest){$highest=$n}
    }
    if($highest -ge 99){throw 'ARCH3g annual part count/number exceeds bounded preview.'}
    $fresh=Get-OPAArchivePartPath -SourcePst $path -Year $ArchiveYear -Part ($highest+1)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3g.OriginalPartCollisionPlan.1'
        Status=if($rows.Count -gt 0){'ExistingAnnualArchiveCollisionManualReviewBeforeAnyWriter'}else{'NoAnnualArchiveDetectedPlanOnlyNoWrite'}
        SourcePst=$path
        SourceEntryId=$id
        ArchiveYear=$ArchiveYear
        ExistingPartCount=$rows.Count
        ExistingParts=@($rows.ToArray() | Sort-Object Part)
        ExistingYearArchiveCollision=($rows.Count -gt 0)
        OriginalPart1Path=(Get-OPAArchivePartPath -SourcePst $path -Year $ArchiveYear -Part 1)
        NextUnusedPartPathPreview=$fresh
        NextUnusedPartNotReserved=$true
        DoNotAppendToExistingAnnualPst=$true
        OriginalYearPartNamingUsed=$true
        FullSemanticWitnessCaptured=$false
        NoPstOrJournalWrites=$true
        LiveMovePerformed=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3gExistingArchiveGate {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Plan','Audit')][string]$Mode,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$SourceEntryId,
          [ValidateRange(1900,2100)][int]$ArchiveYear=2020)
    $source=Assert-OPA265ARCH3fRealTestSource -SourcePst $SourcePst -RequireExisting:($Mode -ceq 'Audit')
    $id=Assert-OPA265ARCH3gSourceEntryId -SourceEntryId $SourceEntryId
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){
        throw 'ARCH3g requires Windows PowerShell 5.1.'
    }
    if($Mode -ceq 'Audit' -and [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3g Outlook audit requires -STA.'
    }
    # Reuse original disk-part enumeration, forcing a fresh read on each run.
    Clear-OPAArchivePartCache -SourcePst $source
    $parts=@(Get-OPAArchivePstPartsOnDisk -SourcePst $source -Year $ArchiveYear)
    $plan=Get-OPA265ARCH3gPartPlan -SourcePst $source -SourceEntryId $id -ArchiveYear $ArchiveYear -ExistingParts $parts
    foreach($row in @($plan.ExistingParts)){
        if(-not [IO.File]::Exists([string]$row.Path)){throw 'ARCH3g annual PST disappeared; manual review.'}
        $attrs=[IO.File]::GetAttributes([string]$row.Path)
        if(($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'ARCH3g linked annual archive refused.'
        }
        $row | Add-Member -NotePropertyName FileLengthBytes -NotePropertyValue ([int64]([IO.FileInfo]::new([string]$row.Path)).Length)
    }
    if([IO.File]::Exists([string]$plan.NextUnusedPartPathPreview)){
        throw 'ARCH3g suggested next part already exists; refresh original inventory.'
    }
    if($Mode -ceq 'Plan'){
        $plan | Add-Member -NotePropertyName OutlookContacted -NotePropertyValue $false
        $plan | Add-Member -NotePropertyName ExactInboxItemIndependentlyLocated -NotePropertyValue $false
        return $plan
    }
    $layout=Get-OPA265ARCH2dLayout -RunId '11111111-2222-4333-8444-555555555555' -LocalAppData $env:LOCALAPPDATA
    $session=$null;$item=$null;$parent=$null;$attachments=$null
    try {
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst $source
        if(-not [bool]$session.Scope.Approved){throw 'ARCH3g source POP3 scope not approved.'}
        $storeId=[string]$session.SourceStore.StoreID
        if([string]::IsNullOrWhiteSpace($storeId) -or $storeId -cne [string]$session.Scope.SourceStoreId){
            throw 'ARCH3g exact source StoreID drift.'
        }
        $item=$session.Namespace.GetItemFromID($id,$storeId)
        if($null -eq $item -or [int]$item.Class -ne 43 -or
           [string]$item.EntryID -cne $id){
            throw 'ARCH3g selected EntryID no longer resolves to exact MailItem.'
        }
        $parent=$item.Parent
        if($null -eq $parent -or
           [string]$parent.EntryID -cne [string]$session.Inbox.EntryID -or
           [string]$parent.StoreID -cne $storeId -or
           [string]$parent.FolderPath -cne [string]$session.Inbox.FolderPath){
            throw 'ARCH3g selected MailItem not inside exact approved POP3 Inbox.'
        }
        $archiveDate=Get-OPAArchiveItemDate -Item $item
        if($null -eq $archiveDate -or ([datetime]$archiveDate).Year -ne $ArchiveYear){
            throw 'ARCH3g source original archive date/year drift.'
        }
        $attachments=$item.Attachments
        $attachmentCount=[int]$attachments.Count
        if($attachmentCount -lt 0 -or $attachmentCount -gt 256){
            throw 'ARCH3g unbounded attachment count.'
        }
        $target=Get-OPAArchiveTargetPath -ReceivedTime ([datetime]$archiveDate) -SourceFolderName ([string]$parent.Name) -SourceFolderPath ([string]$parent.FolderPath) -Grouping Year
        $plan | Add-Member -NotePropertyName OutlookContacted -NotePropertyValue $true
        $plan | Add-Member -NotePropertyName ExactInboxItemIndependentlyLocated -NotePropertyValue $true
        $plan | Add-Member -NotePropertyName SourceFolderEntryId -NotePropertyValue ([string]$parent.EntryID)
        $plan | Add-Member -NotePropertyName SourceFolderPath -NotePropertyValue ([string]$parent.FolderPath)
        $plan | Add-Member -NotePropertyName SourceStoreIdSha256 -NotePropertyValue (Get-OPA265ARCH2bTextSha256 -Text $storeId)
        $plan | Add-Member -NotePropertyName SourceArchiveDate -NotePropertyValue ([datetime]$archiveDate)
        $plan | Add-Member -NotePropertyName OriginalTargetFolderPath -NotePropertyValue ([string]$target)
        $plan | Add-Member -NotePropertyName AttachmentCount -NotePropertyValue $attachmentCount
        $plan | Add-Member -NotePropertyName FullWitnessPending -NotePropertyValue $true
        $plan | Add-Member -NotePropertyName OutlookProcessId -NotePropertyValue ([int]$session.OutlookProcessId)
        $plan | Add-Member -NotePropertyName OutlookProcessStartUtcTicks -NotePropertyValue ([int64]$session.OutlookProcessStartUtcTicks)
        $plan | Add-Member -NotePropertyName SourcePstLengthBytes -NotePropertyValue ([int64]([IO.FileInfo]::new($source)).Length)
        return $plan
    }finally{
        Release-OPA265ARCH2c4Com -Object $attachments
        Release-OPA265ARCH2c4Com -Object $parent
        Release-OPA265ARCH2c4Com -Object $item
        Close-OPA265ARCH2dSession -Session $session
    }
}
