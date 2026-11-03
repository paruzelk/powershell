#requires -Version 5.1
# BW4k7p read-only POP3 store FOLDER and optional bounded YEAR inventory.
# No Move/Save/Delete/SetProperty; no PST creation/mount; no Claim/journal.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst',
    [string]$ExpectedProfileName='Outlook',
    [switch]$ScanYears,
    [switch]$InspectAttachmentMetadata,
    [ValidateRange(1,20000)][int]$MaxFolders=5000,
    [ValidateRange(1,1000000)][int]$MaxTotalItems=5000,
    [ValidateRange(1,1000000)][int]$MaxItemsPerFolder=5000,
    [ValidateRange(1,200)][int]$MaxAttachmentsPerMail=50
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7p requires native Windows PowerShell 5.1 STA.'
}
if($ExpectedProfileName -cne 'Outlook'){throw 'BW4k7p only exact operator Outlook profile supported.'}
. (Join-Path $PSScriptRoot '../Worker/BW4k7pFolderScopeInventory265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
[void](Assert-OPA265BW4k7pReadOnlyLimits -MaxFolders $MaxFolders -MaxTotalItems $MaxTotalItems -MaxItemsPerFolder $MaxItemsPerFolder -MaxAttachmentsPerMail $MaxAttachmentsPerMail)
if($InspectAttachmentMetadata -and -not $ScanYears){
    throw 'BW4k7p attachment metadata inspection requires -ScanYears.'
}
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7p.WhatIf.1'
        Status='WhatIfNoOutlookAccessNoPstChanges'
        YearScanRequested=[bool]$ScanYears
        AttachmentMetadataRequested=[bool]$InspectAttachmentMetadata
        ReadOnly=$true;WriterPermit=$false;ProductionReady=$false
    }
}
$stage='Exact POP3 source PST and Outlook process/profile'
$app=$null;$ns=$null;$source=$null;$root=$null
try{
    $proc=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($proc.Count -ne 1){throw 'BW4k7p must have exactly one running Outlook process.'}
    $oldProcessId=[int]$proc[0].Id
    $oldTicks=[long]$proc[0].StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4k7p Outlook profile differs from expected.'
    }
    $source=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $sourceStore=$source.Store
    $sourceStoreId=[string]$source.StoreId
    $root=$sourceStore.GetRootFolder()
    if($null -eq $root -or [string]$root.StoreID -cne $sourceStoreId){
        throw 'BW4k7p cannot establish root belongs to selected POP3 PST.'
    }
    $map=Get-OPA265BW4k7pDefaultFolderMap -Store $sourceStore
    $sentResolved=(-not [string]::IsNullOrWhiteSpace([string]$map.SentItems))
    $outboxResolved=(-not [string]::IsNullOrWhiteSpace([string]$map.Outbox))
    $stage='BFS folder topology, identity verification and read-only folder counts'
    $queue=New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue([pscustomobject]@{Folder=$root;Depth=0;Path='';ParentRole='Root'})
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $folderTotal=0;$eligibleCount=0L;$excludedCount=0L
    $scanned=0L;$partial=$false;$unknownDate=0L;$nonMail=0L
    $observedBytes=0L;$observedAttachmentCount=0L;$attachIncomplete=$false
    $allYears=@{};$byRole=@{}
    foreach($role in @('Inbox','SentItems','UserMail')){$byRole[$role]=@{}}
    while($queue.Count -gt 0){
        $node=$queue.Dequeue()
        $folder=$node.Folder
        if([int]$node.Depth -gt 32){throw 'BW4k7p folder nesting exceeds safe depth 32.'}
        $folderTotal++
        if($folderTotal -gt $MaxFolders){throw 'BW4k7p MaxFolders reached. No claim that topology is complete.'}
        $fid=[string]$folder.EntryID
        if([string]::IsNullOrWhiteSpace($fid) -or
           [string]$folder.StoreID -cne $sourceStoreId -or
           -not $seen.Add($fid)){
            throw 'BW4k7p duplicate/missing folder identity or wrong store inside source PST.'
        }
        $name=[string]$folder.Name
        if($name.Length -gt 1024){throw 'BW4k7p folder name exceeds display bound.'}
        $path=if([int]$node.Depth -eq 0){'\'}else{[string]$node.Path}
        if($path.Length -gt 4096){throw 'BW4k7p folder path exceeds safe display bound.'}
        $role='Root';$typ=20
        if([int]$node.Depth -gt 0){
            try{$typ=[int]$folder.DefaultItemType}catch{$typ=20}
            $scopeArgs=@{
                EntryId=$fid;InboxEntryId=[string]$map.Inbox
                SentEntryId=[string]$map.SentItems
                OutboxEntryId=[string]$map.Outbox
                ExcludedSystemEntryIds=@($map.SystemExcluded)
                ParentRole=[string]$node.ParentRole
                DefaultItemType=$typ
            }
            $role=Get-OPA265BW4k7pFolderRole @scopeArgs
        }
        $itemCount=$null
        if($role -ne 'Root'){
            $itemCount=[int]$folder.Items.Count
            if($itemCount -lt 0){throw 'BW4k7p negative item count.'}
            if($role -in @('Inbox','SentItems','UserMail')){$eligibleCount+=[long]$itemCount}
            else{$excludedCount+=[long]$itemCount}
        }
        $row=[pscustomobject][ordered]@{
            FolderPath=$path;FolderEntryId=$fid
            ParentRole=[string]$node.ParentRole
            Role=$role;Depth=[int]$node.Depth
            DefaultItemType=$typ;ItemsCount=$itemCount
            IncludedInFutureScope=($role -in @('Inbox','SentItems','UserMail') -and $sentResolved)
            YearScanStatus=if($ScanYears){'NotEligibleOrSkipped'}else{'NotRequested'}
            ItemsExamined=0;MailItemsDated=0L;MailItemsUndated=0L
            NonMailItemsSeen=0L;FallbackDateCount=0L
            ObservedMailSizeBytes=0L
            AttachmentMetadataInspected=$false
            AttachmentsObserved=$null;EstimatedAttachmentBytes=$null;YearCounts=@{}
        }
        if($ScanYears -and $role -in @('Inbox','SentItems','UserMail')){
            if($scanned -ge $MaxTotalItems){
                $partial=$true;$row.YearScanStatus='PartialGlobalLimitReached'
            }else{
                $remaining=[int][Math]::Min(([long]$MaxTotalItems-$scanned),[long]$MaxItemsPerFolder)
                $scanArgs=@{
                    Folder=$folder;Role=$role;MaxItems=$remaining
                    MaxAttachmentsPerMail=$MaxAttachmentsPerMail
                    InspectAttachments=$InspectAttachmentMetadata
                }
                $data=Get-OPA265BW4k7pFolderItems @scanArgs
                $scanned+=[long]$data.ScannedItems
                $nonMail+=[long]$data.NonMailObserved
                $unknownDate+=[long]$data.MailDateUnavailableObserved
                $observedBytes+=[long]$data.MailSizeObservedBytes
                if($InspectAttachmentMetadata){
                    $observedAttachmentCount+=[long]$data.AttachmentCountObserved
                    if(-not $data.AttachmentSizeEvidenceComplete){$attachIncomplete=$true}
                    $row.AttachmentsObserved=[long]$data.AttachmentCountObserved
                    $row.EstimatedAttachmentBytes=[long]$data.AttachmentSizeObservedBytes
                    $row.AttachmentMetadataInspected=$true
                }
                if(-not $data.FullyScanned){$partial=$true}
                $row.YearScanStatus=if($data.FullyScanned){'Complete'}else{'PartialBounded'}
                $row.ItemsExamined=[int]$data.ScannedItems
                $row.MailItemsUndated=[long]$data.MailDateUnavailableObserved
                $row.NonMailItemsSeen=[long]$data.NonMailObserved
                $row.FallbackDateCount=[long]$data.SentOrReceivedFallbackObserved
                $row.ObservedMailSizeBytes=[long]$data.MailSizeObservedBytes
                foreach($year in @($data.YearCounts.Keys)){
                    $value=[long]$data.YearCounts[$year]
                    $row.YearCounts[$year]=$value
                    if(-not $allYears.ContainsKey($year)){$allYears[$year]=0L}
                    if(-not $byRole[$role].ContainsKey($year)){$byRole[$role][$year]=0L}
                    $allYears[$year]+=$value
                    $byRole[$role][$year]+=$value
                    $row.MailItemsDated+=$value
                }
            }
        }
        $rows.Add($row)
        $subs=$folder.Folders
        $childStart=[int]$subs.Count
        if($childStart -lt 0){throw 'BW4k7p invalid subfolder count.'}
        for($i=1;$i -le $childStart;$i++){
            $child=$subs.Item($i)
            if($null -eq $child){throw 'BW4k7p missing subfolder in enumeration.'}
            $childName=[string]$child.Name
            if([string]::IsNullOrWhiteSpace($childName)){throw 'BW4k7p unnamed subfolder.'}
            $childPath=if($path -eq '\'){'\' + $childName}else{$path+'\' + $childName}
            $queue.Enqueue([pscustomobject]@{
                Folder=$child;Depth=([int]$node.Depth+1)
                Path=$childPath;ParentRole=$role
            })
        }
        if([int]$subs.Count -ne $childStart){
            throw 'BW4k7p folder hierarchy changed during enumeration.'
        }
    }
    if($seen.Count -ne $rows.Count){throw 'BW4k7p duplicate folder identities detected.'}
    $stage='Verify Outlook process stable and compute bounded inventory coverage'
    $newProc=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($newProc.Count -ne 1 -or
       [int]$newProc[0].Id -ne $oldProcessId -or
       [long]$newProc[0].StartTime.ToUniversalTime().Ticks -ne $oldTicks){
        throw 'BW4k7p Outlook process restarted during scan; evidence incomplete.'
    }
    if($ScanYears -and ($unknownDate -gt 0 -or $scanned -lt $eligibleCount)){$partial=$true}
    $complete=([bool]$ScanYears -and -not $partial -and $sentResolved)
    $status=if(-not $sentResolved){
        'SentItemsDefaultNotResolvedNoArchiveScopeApproval'
    }elseif(-not $ScanYears){
        'Pop3FolderTopologyIdentifiedYearScanNotRequested'
    }elseif($partial){
        'Pop3BoundedPartialYearInventoryNoFullCoverageClaim'
    }else{
        'Pop3YearInventoryCompleteReadOnlyNoProductionPermit'
    }
    $years=if($ScanYears){@(New-OPA265BW4k7pYearPlan -SourcePst ([string]$source.SourcePst) -YearCounts $allYears -ScanComplete:$complete)}else{@()}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7p.Pop3FolderScopeReadOnlyInventory.1'
        Status=$status;SourcePst=[string]$source.SourcePst
        SourcePstLengthBytes=[long](Get-Item -LiteralPath $source.SourcePst).Length
        ExpectedProfileName=$ExpectedProfileName
        ExactPop3DeliveryStoreVerified=$true
        ScopeRestrictedToOnePop3Store=$true
        OtherImapOrPop3StoresRead=$false
        RootFolderEntryId=[string]$root.EntryID
        InboxDefaultFolderEntryId=[string]$map.Inbox
        SentItemsDefaultFolderEntryId=[string]$map.SentItems
        OutboxDefaultFolderEntryId=[string]$map.Outbox
        SentItemsResolvedInThisPop3Store=$sentResolved
        OutboxResolvedInThisPop3Store=$outboxResolved
        SentItemsScopeStatement='Only Sent Mail default of this POP3 DeliveryStore; other accounts may save sent elsewhere'
        OutboxNeverEquivalentToSentItems=$true
        DefaultStoreFolderNamesNotUsedForIdentity=$true
        FolderCount=$rows.Count
        EligibleFolderCount=@($rows.ToArray() | Where-Object {$_.Role -in @('Inbox','SentItems','UserMail')}).Count
        EligibleFolderItemsObserved=[long]$eligibleCount
        ExcludedFolderItemsObserved=[long]$excludedCount
        YearScanRequested=[bool]$ScanYears
        YearScanComplete=$complete
        YearItemsExamined=[long]$scanned
        YearItemsDateUnavailable=[long]$unknownDate
        YearNonMailItemsSeen=[long]$nonMail
        ApproxMailItemSizeObservedBytes=if($ScanYears){[long]$observedBytes}else{$null}
        AttachmentMetadataInspected=[bool]$InspectAttachmentMetadata
        AttachmentCountObserved=if($InspectAttachmentMetadata){[long]$observedAttachmentCount}else{$null}
        AttachmentSizeScanComplete=([bool]$InspectAttachmentMetadata -and $complete -and -not $attachIncomplete)
        BoundedMaxFolders=$MaxFolders;BoundedMaxTotalItems=$MaxTotalItems
        BoundedMaxItemsPerFolder=$MaxItemsPerFolder
        FolderInventory=@($rows.ToArray())
        ProposedYearArchiveNames=$years
        InboxYears=if($ScanYears){@(New-OPA265BW4k7pYearPlan -SourcePst $source.SourcePst -YearCounts $byRole.Inbox -ScanComplete:$complete)}else{@()}
        SentItemsYears=if($ScanYears){@(New-OPA265BW4k7pYearPlan -SourcePst $source.SourcePst -YearCounts $byRole.SentItems -ScanComplete:$complete)}else{@()}
        UserFolderYears=if($ScanYears){@(New-OPA265BW4k7pYearPlan -SourcePst $source.SourcePst -YearCounts $byRole.UserMail -ScanComplete:$complete)}else{@()}
        ProposedArchiveFilesCreated=$false;PstCapacityAndYearRolloverValidated=$false
        ProductionSentCoverageProven=$false;FullProductionSemanticIntegrityProven=$false
        OutlookMoveExecuted=$false;ClaimOrJournalWritten=$false
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        NextAction='ReviewSentDefaultAndUserFolders;PreserveExistingPstAndClaim;NoMoveOrProduction'
    }
}catch{
    throw ('BW4k7p READ-ONLY STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Move, PST creation, journal or Claim writes; no production approval.')
}finally{
    foreach($com in @($root,$ns,$app)){
        if($null -ne $com -and [Runtime.InteropServices.Marshal]::IsComObject($com)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($com)
        }
    }
}
