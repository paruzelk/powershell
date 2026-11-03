#requires -Version 5.1
# BW4k7r - exact BW4k7q POP3 candidate-only read-only Outlook year/size metadata.
# Capacity names and rollover counts are forecasts, no PST/registry/evidence/Claim changes.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst',
    [string]$ExpectedProfileName='Outlook',
    [ValidateRange(1,1000000)][int]$MaxTotalItems=5000,
    [ValidateRange(1,1000000)][int]$MaxItemsPerFolder=5000,
    [ValidateRange(10,10000)][int]$ProgressEvery=250,
    [ValidateRange(1990,2101)][int]$ArchiveBeforeYear=2026,
    [ValidateRange(104857600,1099511627776)][long]$MaxArchivePstSizeBytes=45000000000,
    [ValidateRange(0,1099511627775)][long]$SafetyMarginBytes=3000000000,
    [ValidateRange(0,200)][int]$EstimatedExpansionPct=25,
    [ValidateRange(0,1048576)][long]$PerMessageOverheadBytes=65536
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7r requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7pFolderScopeInventory265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k7rYearCapacityPlan265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$capacity=Get-OPA265BW4k7rSafeCapacity -MaxArchivePstSizeBytes $MaxArchivePstSizeBytes -SafetyMarginBytes $SafetyMarginBytes -EstimatedExpansionPct $EstimatedExpansionPct -PerMessageOverheadBytes $PerMessageOverheadBytes
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7r.WhatIf.1'
        Status='WhatIfCapacityForecastNoOutlookAccessOrWrites'
        MaxTotalItems=$MaxTotalItems;MaxItemsPerFolder=$MaxItemsPerFolder
        ArchiveBeforeYear=$ArchiveBeforeYear;CapacityPolicy=$capacity
        NoPstOrRegistryChanges=$true
        WriterPermit=$false;ProductionReady=$false
    }
}
$stage='Verified BW4k7q original POP3 candidate folder-only inventory'
$app=$null;$ns=$null
try{
    $scopeArgs=@{SourcePst=$SourcePst;ExpectedProfileName=$ExpectedProfileName}
    $scope=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1') @scopeArgs
    if([string]$scope.Schema -cne '2.6.5-BW4k7q.LivePop3FolderScopeExclusionReview.1' -or
       -not [bool]$scope.Pop3StoreVerified -or [bool]$scope.ImapStoreItemsInspected -or
       -not [bool]$scope.SentItemsIncludedEvenWhenEmpty -or
       -not [bool]$scope.ProposedScopeDoesNotIncludeTestFolders -or
       -not [bool]$scope.HistoricUnknownRaw0x00010000StillBlocked -or
       [bool]$scope.WriterPermit -or [bool]$scope.ProductionReady){
        throw 'BW4k7r unsafe original POP3 store/scope/SEM-001 evidence.'
    }
    $stage='Unique running Outlook and exact original POP3 DeliveryStore'
    $process=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($process.Count -ne 1){throw 'BW4k7r requires exactly one OUTLOOK.EXE.'}
    $oldPidValue=[int]$process[0].Id
    $oldProcessTicks=[long]$process[0].StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4k7r wrong Outlook profile.'
    }
    $source=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $storeId=[string]$source.StoreId
    if([string]::IsNullOrWhiteSpace($storeId)){throw 'BW4k7r missing POP3 StoreID.'}
    $sizeBefore=[long](Get-Item -LiteralPath $SourcePst -ErrorAction Stop).Length
    if($sizeBefore -ne [long]$scope.SourcePstLengthBytes){
        throw 'BW4k7r source PST size changed between scope and year scan.'
    }
    $acc=New-OPA265BW4k7rYearAccumulator
    $folderRows=New-Object 'System.Collections.Generic.List[object]'
    $matrix=New-Object 'System.Collections.Generic.List[object]'
    $allowed=@($scope.ProposedFolderScope | Where-Object {$_.IncludedInProposedPop3Scope})
    if($allowed.Count -lt 2 -or
       @($allowed | Where-Object {$_.PreviousBW4k7pRole -ceq 'Inbox'}).Count -ne 1 -or
       @($allowed | Where-Object {$_.PreviousBW4k7pRole -ceq 'SentItems'}).Count -ne 1){
        throw 'BW4k7r cannot find one Inbox and one Sent in approved POP3 scope.'
    }
    $stage='Bounded MailItem metadata enumeration (no body, attachment or writer)'
    foreach($row in $allowed){
        $role=[string]$row.PreviousBW4k7pRole
        if($role -cnotin @('Inbox','SentItems','UserMail') -or
           [bool]$row.TestFolderOrDescendant){
            throw ('BW4k7r invalid included role or test folder: '+$row.FolderPath)
        }
        $folder=$ns.GetFolderFromID([string]$row.FolderEntryId,$storeId)
        if($null -eq $folder -or
           [string]$folder.StoreID -cne $storeId -or
           [string]$folder.EntryID -ine [string]$row.FolderEntryId){
            throw ('BW4k7r source POP3 folder ID/store changed: '+$row.FolderPath)
        }
        $items=$folder.Items
        $before=[int]$items.Count
        if($before -lt 0 -or $before -ne [int]$row.ItemsCount){
            throw ('BW4k7r folder Items.Count differs from BW4k7q: '+$row.FolderPath)
        }
        $budget=[long]$MaxTotalItems-[long]$acc.ItemsExamined
        $limit=if($budget -le 0){0}else{
            [int][math]::Min([long]$before,[math]::Min([long]$MaxItemsPerFolder,$budget))
        }
        $local=New-OPA265BW4k7rYearAccumulator
        $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $mail=$null
        if($limit -gt 0){$mail=$items.GetFirst()}
        for($i=0;$i -lt $limit;$i++){
            if($null -eq $mail){throw ('BW4k7r unexpected Outlook Items end: '+$row.FolderPath)}
            $entry=[string]$mail.EntryID
            if([string]::IsNullOrWhiteSpace($entry) -or -not $seen.Add($entry)){
                throw ('BW4k7r repeated or missing MailItem EntryID: '+$row.FolderPath)
            }
            $d=Get-OPA265BW4k7pYear -Item $mail -Role $role
            $size=if($d.IsMail){[long]$mail.Size}else{0L}
            $ob=@{Role=$role;ItemClass=[int]$mail.Class;DateField=[string]$d.DateField;ItemSizeBytes=$size}
            if($d.DateAvailable){$ob.Year=[int]$d.Year}
            Add-OPA265BW4k7rItemObservation -Accumulator $acc @ob
            Add-OPA265BW4k7rItemObservation -Accumulator $local @ob
            if(($acc.ItemsExamined % $ProgressEvery) -eq 0){
                $pct=[int][math]::Min(100,[math]::Floor(
                    100*[double]$acc.ItemsExamined/[math]::Max(1,[double]$scope.ProposedScopeItemCount)))
                $status=('{0:N0} of {1:N0}; {2}' -f $acc.ItemsExamined,$scope.ProposedScopeItemCount,$row.FolderPath)
                Write-Progress -Id 7 -Activity 'BW4k7r POP3 read-only year scan' -Status $status -PercentComplete $pct
            }
            if($i -lt ($limit-1)){$mail=$items.GetNext()}
        }
        if([int]$items.Count -ne $before){
            throw ('BW4k7r folder changed during read-only scan: '+$row.FolderPath)
        }
        $state=if($limit -eq $before){'Complete'}
                elseif($budget -le 0){'PartialGlobalBudgetReached'}
                else{'PartialPerFolderBudgetReached'}
        $folderRows.Add([pscustomobject][ordered]@{
            FolderPath=[string]$row.FolderPath
            FolderEntryId=[string]$row.FolderEntryId
            Role=$role
            ExpectedFolderItems=[int]$before
            ItemsExamined=[long]$local.ItemsExamined
            DatedMailItems=[long]$local.DatedMailObserved
            UndatedMailItems=[long]$local.UndatedMailObserved
            NonMailItems=[long]$local.NonMailObserved
            FallbackDateItems=[long]$local.FallbackDateObserved
            ObservedMailSizeBytes=[long]$local.MailItemSizeObservedBytes
            ScanState=$state
            FullFolderRead=($limit -eq $before)
            MailBodyOrAttachmentBytesRead=$false
        })
        foreach($key in @($local.Buckets.Keys | Sort-Object {[int]$_})){
            $b=$local.Buckets[$key]
            $matrix.Add([pscustomobject][ordered]@{
                FolderPath=[string]$row.FolderPath;Role=$role;Year=[int]$key
                MailItems=[long]$b.InboxMailItems+[long]$b.SentItemsMailItems+[long]$b.UserFolderMailItems
                ObservedMailItemSizeBytes=[long]$b.InboxSizeBytes+[long]$b.SentItemsSizeBytes+[long]$b.UserFolderSizeBytes
                Coverage=if($limit -eq $before){'FullyEnumeratedFolder'}else{'PartialLowerBoundOnly'}
                FolderHierarchyCreatedOrAltered=$false
            })
        }
    }
    Write-Progress -Id 7 -Activity 'BW4k7r POP3 read-only year scan' -Completed
    $stage='Independent Outlook process/PST size and BW4k7q topology check after scan'
    $now=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($now.Count -ne 1 -or [int]$now[0].Id -ne $oldPidValue -or
       [long]$now[0].StartTime.ToUniversalTime().Ticks -ne $oldProcessTicks){
        throw 'BW4k7r Outlook restarted during scan.'
    }
    $sizeAfter=[long](Get-Item -LiteralPath $SourcePst -ErrorAction Stop).Length
    if($sizeAfter -ne $sizeBefore){throw 'BW4k7r source PST changed size during scan.'}
    $fresh=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1') @scopeArgs
    if([long]$fresh.SourcePstLengthBytes -ne $sizeBefore -or
       [int]$fresh.CurrentFolderCount -ne [int]$scope.CurrentFolderCount -or
       [long]$fresh.ProposedScopeItemCount -ne [long]$scope.ProposedScopeItemCount -or
       [long]$fresh.ExcludedScopeItemCount -ne [long]$scope.ExcludedScopeItemCount){
        throw 'BW4k7r original POP3 scope changed during scan.'
    }
    $firstRows=@($scope.ProposedFolderScope);$lastRows=@($fresh.ProposedFolderScope)
    if($firstRows.Count -ne $lastRows.Count){throw 'BW4k7r source folder structure changed.'}
    for($j=0;$j -lt $firstRows.Count;$j++){
        if([string]$firstRows[$j].FolderEntryId -ine [string]$lastRows[$j].FolderEntryId -or
           [string]$firstRows[$j].FolderPath -cne [string]$lastRows[$j].FolderPath -or
           [string]$firstRows[$j].Disposition -cne [string]$lastRows[$j].Disposition -or
           [long]$firstRows[$j].ItemsCount -ne [long]$lastRows[$j].ItemsCount){
            throw ('BW4k7r source folder identity/disposition/count drift: '+$firstRows[$j].FolderPath)
        }
    }
    $allRead=([long]$acc.ItemsExamined -eq [long]$scope.ProposedScopeItemCount)
    $allDated=([long]$acc.UndatedMailObserved -eq 0)
    $yearComplete=($allRead -and $allDated)
    $planArgs=@{Accumulator=$acc;SourcePst=$SourcePst;Capacity=$capacity
                ArchiveBeforeYear=$ArchiveBeforeYear;ScanComplete=$yearComplete}
    $yearPlan=@(Get-OPA265BW4k7rCapacityPlan @planArgs)
    [void](Assert-OPA265BW4k7rPlanIntegrity -Accumulator $acc -YearPlan $yearPlan)
    $status=if(-not $allRead){
        'BoundedPartialPOP3YearDistributionNoCompleteCoverage'
    }elseif(-not $allDated){
        'AllCandidateItemsReadButUnknownDatesPreventYearCompletion'
    }elseif([long]$acc.FallbackDateObserved -gt 0){
        'FullReadOnlyYearDistributionWithDateFallbackNeedsReview'
    }else{'FullObservedPOP3YearDistributionReadOnlyCapacityForecastOnly'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7r.Pop3YearDistributionCapacityReadOnly.1'
        Status=$status
        ScopePolicyId='POP3-SCOPE-001-BW4k7q-v1'
        CapacityPolicyId='CAPACITY-FORECAST-001-BW4k7r-v1'
        SourcePst=$SourcePst
        SourcePstLengthBytesBefore=$sizeBefore
        SourcePstLengthBytesAfter=$sizeAfter
        OutlookProcessUnchanged=$true
        Pop3ScopeRepeatedAndStable=$true
        AtomicPstSnapshotEstablished=$false
        ImapOrOtherStoreMailRead=$false
        CurrentInboxItemsObserved=[long]$scope.CurrentInboxCount
        CurrentSentItemsCount=[long]$scope.CurrentSentItemsCount
        SentItemsAlwaysIncluded=$true
        ReservedTestFolderItemsExcluded=[long]$scope.CurrentReservedTestFolderItemsQuarantined
        ScopeCandidateItemsTotal=[long]$scope.ProposedScopeItemCount
        CandidateItemsExamined=[long]$acc.ItemsExamined
        AllCandidateItemsEnumerated=$allRead
        YearDistributionComplete=$yearComplete
        AllMailItemsDated=$allDated
        MailItemsObserved=[long]$acc.MailItemsObserved
        MailItemsDated=[long]$acc.DatedMailObserved
        MailItemsUndated=[long]$acc.UndatedMailObserved
        NonMailItemsObserved=[long]$acc.NonMailObserved
        FallbackDateItemsObserved=[long]$acc.FallbackDateObserved
        ObservedLogicalMailItemSizeBytes=[long]$acc.MailItemSizeObservedBytes
        LargestMailItemSizeObservedBytes=[long]$acc.LargestMailItemSizeObservedBytes
        ArchiveBeforeYear=$ArchiveBeforeYear
        EligibleArchiveYearCount=@($yearPlan | Where-Object {$_.ArchiveYearEligible}).Count
        MaxTotalItems=$MaxTotalItems
        MaxItemsPerFolder=$MaxItemsPerFolder
        YearDistribution=@($yearPlan)
        FolderYearMatrix=@($matrix.ToArray())
        FolderScanSummary=@($folderRows.ToArray())
        CapacityForecastSettings=$capacity
        PhysicalPstSizeCannotBeDerivedFromMailItemSize=$true
        ForecastDoesNotCommitActualPstSegments=$true
        NoPostCrashDurableResumeCheckpointCreated=$true
        RestartWithLargerExplicitLimitsToComplete=$true
        SourceFolderHierarchyPreservedAsReadOnlyMetadata=$true
        RealArchivePstCapacityAndRegistryLimitVerified=$false
        ArchivePstCreatedOrReplaced=$false
        RegistryPstLimitChanged=$false
        MailOrAttachmentContentRead=$false
        MailMovedOrDeleted=$false
        TestFoldersOrPstsDeleted=$false
        OriginalBW4k7lEvidenceOrBW4k7mClaimRewritten=$false
        OriginalSEM001Unknown0x00010000StillBlocked=$true
        ArchiveResumeAutoEnabled=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='ReviewObservedYearDistributionAndCapacityForecast;NoActualPstCreationOrMove;NoProduction'
    }
}catch{
    Write-Progress -Id 7 -Activity 'BW4k7r POP3 read-only year scan' -Completed
    throw ('BW4k7r READ-ONLY STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Move, PST/registry/Claim/journal writes or production waiver.')
}finally{
    foreach($obj in @($ns,$app)){
        if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)
        }
    }
}
