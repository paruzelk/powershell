#requires -Version 5.1
# BW4k7s - original POP3 PST only, Class/MessageClass/EntryID witnesses + Office16 registry READ ONLY.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$SourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst',
    [string]$ExpectedProfileName='Outlook',
    [ValidateRange(1,1000000)][int]$MaxTotalItems=5000,
    [ValidateRange(1,200)][int]$MaxNonMailWitnesses=25,
    [ValidateRange(10,10000)][int]$ProgressEvery=500,
    [ValidateRange(104857600,1099511627776)][long]$PlannedMaxArchivePstBytes=45000000000,
    [ValidateRange(0,1099511627775)][long]$PlannedSafetyMarginBytes=3000000000,
    [psobject]$PreviousFullYearInventory=$null,
    [switch]$RegistryOnly
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7s requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7sInventoryRegistryPolicy265.ps1')
if($PlannedSafetyMarginBytes -ge $PlannedMaxArchivePstBytes){
    throw 'BW4k7s safety margin must be strictly smaller than planned PST maximum.'
}
if($dry){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7s.WhatIf.1';Status='WhatIfNoOutlookOrRegistryReadNoWriter'
        OutlookReadPerformed=$false;RegistryReadPerformed=$false
        PstFilesModified=$false;RegistryWritePerformed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
$policy=Get-OPA265BW4k7sPstRegistryProbe -Kind Policy
$user=Get-OPA265BW4k7sPstRegistryProbe -Kind User
$limitArgs=@{
    PolicyProbe=$policy;UserProbe=$user
    PlannedMaxArchivePstBytes=$PlannedMaxArchivePstBytes
    PlannedSafetyMarginBytes=$PlannedSafetyMarginBytes
}
$limits=Get-OPA265BW4k7sPstLimitDecision @limitArgs
if($RegistryOnly){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7s.RegistryOnlyReadOnly.1'
        Status='Office16PstRegistryInspectedReadOnlyNoOutlook'
        LimitDecision=$limits;PolicyProbe=$policy;UserProbe=$user
        OutlookReadPerformed=$false;PstOrRegistryModified=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
$stage='First original BW4k7q source POP3 store and excluded-test scope audit'
$app=$null;$ns=$null
try{
    $q=@{SourcePst=$SourcePst;ExpectedProfileName=$ExpectedProfileName}
    $scope=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1') @q
    if([string]$scope.Schema -cne '2.6.5-BW4k7q.LivePop3FolderScopeExclusionReview.1' -or
       -not [bool]$scope.Pop3StoreVerified -or [bool]$scope.ImapStoreItemsInspected -or
       -not [bool]$scope.SentItemsIncludedEvenWhenEmpty -or
       -not [bool]$scope.ProposedScopeDoesNotIncludeTestFolders -or
       -not [bool]$scope.HistoricUnknownRaw0x00010000StillBlocked -or
       [bool]$scope.WriterPermit -or [bool]$scope.ProductionReady){
        throw 'BW4k7s exact BW4k7q POP3 scope or SEM-001 writer barrier failed.'
    }
    $stage='Existing Outlook process and unique original POP3 DeliveryStore'
    $p=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($p.Count -ne 1){throw 'BW4k7s exactly one OUTLOOK.EXE required.'}
    $processIdBefore=[int]$p[0].Id
    $processStartBefore=[long]$p[0].StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4k7s Outlook profile mismatch.'
    }
    . (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
    $store=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $storeId=[string]$store.StoreId
    if([string]::IsNullOrWhiteSpace($storeId)){throw 'BW4k7s POP3 StoreID unavailable.'}
    $pstBefore=[long](Get-Item -LiteralPath $SourcePst -ErrorAction Stop).Length
    if($pstBefore -ne [long]$scope.SourcePstLengthBytes){
        throw 'BW4k7s original PST length changed between scope and scan.'
    }
    $rows=@($scope.ProposedFolderScope | Where-Object {$_.IncludedInProposedPop3Scope})
    if(@($rows | Where-Object {$_.PreviousBW4k7pRole -ceq 'Inbox'}).Count -ne 1 -or
       @($rows | Where-Object {$_.PreviousBW4k7pRole -ceq 'SentItems'}).Count -ne 1){
        throw 'BW4k7s Inbox and Sent identities must be unique.'
    }
    $witnesses=New-Object 'System.Collections.Generic.List[object]'
    $stats=New-Object 'System.Collections.Generic.List[object]'
    $examined=0L;$mails=0L;$nonMails=0L
    $stage='Bounded POP3 item Class and nonMail MessageClass without body or attachment reads'
    foreach($row in $rows){
        if([bool]$row.TestFolderOrDescendant -or
           [string]$row.PreviousBW4k7pRole -cnotin @('Inbox','SentItems','UserMail')){
            throw 'BW4k7s quarantined or non-mail folder in candidate set.'
        }
        $folder=$ns.GetFolderFromID([string]$row.FolderEntryId,$storeId)
        if($null -eq $folder -or
           [string]$folder.EntryID -ine [string]$row.FolderEntryId -or
           [string]$folder.StoreID -cne $storeId){
            throw 'BW4k7s folder wrong EntryID or StoreID.'
        }
        $items=$folder.Items
        $total=[int]$items.Count
        if($total -lt 0 -or $total -ne [int]$row.ItemsCount){
            throw 'BW4k7s source Inbox/Sent/user folder counts changed.'
        }
        $remain=[long]$MaxTotalItems-$examined
        $take=if($remain -le 0){0}else{[int][math]::Min([long]$total,$remain)}
        $localMail=0L;$localOther=0L
        $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $item=$null
        if($take -gt 0){$item=$items.GetFirst()}
        for($i=0;$i -lt $take;$i++){
            if($null -eq $item){throw 'BW4k7s Outlook item enumeration stopped early.'}
            $eid=[string]$item.EntryID
            if([string]::IsNullOrWhiteSpace($eid) -or -not $seen.Add($eid)){
                throw 'BW4k7s duplicate or missing item EntryID.'
            }
            $class=[int]$item.Class
            if($class -eq 43){$mails++;$localMail++}
            else{
                $nonMails++;$localOther++
                if($nonMails -gt $MaxNonMailWitnesses){throw 'BW4k7s nonmail witness cap exceeded.'}
                $msgClass='';$state='NotAvailable'
                try{
                    $msgClass=[string]$item.MessageClass
                    if(-not [string]::IsNullOrWhiteSpace($msgClass)){$state='Read'}
                }catch{$state='NotAvailable';$msgClass=''}
                $wa=@{
                    ClassCode=$class;EntryId=$eid
                    FolderEntryId=[string]$row.FolderEntryId
                    MessageClass=$msgClass;MessageClassObservation=$state
                }
                $w=New-OPA265BW4k7sNonMailWitness @wa
                $w | Add-Member -MemberType NoteProperty -Name FolderPath -Value ([string]$row.FolderPath)
                $witnesses.Add($w)
            }
            $examined++
            if(($examined % $ProgressEvery) -eq 0){
                $pct=[int][math]::Min(100,[math]::Floor(100*[double]$examined/
                     [math]::Max(1,[double]$scope.ProposedScopeItemCount)))
                $progressArgs=@{
                    Id=8;Activity='BW4k7s READ ONLY nonMail class inventory'
                    Status=('{0:N0}/{1:N0} items' -f $examined,$scope.ProposedScopeItemCount)
                    PercentComplete=$pct
                }
                Write-Progress @progressArgs
            }
            if($i -lt ($take-1)){$item=$items.GetNext()}
        }
        if([int]$items.Count -ne $total){throw 'BW4k7s folder changed during scan.'}
        $stats.Add([pscustomobject][ordered]@{
            FolderPath=[string]$row.FolderPath
            Role=[string]$row.PreviousBW4k7pRole
            ExpectedFolderItems=$total;ItemsExamined=$take
            MailItemClass43Observed=$localMail;NonMailObserved=$localOther
            FullFolderRead=($take -eq $total)
        })
    }
    Write-Progress -Id 8 -Activity 'BW4k7s READ ONLY nonMail class inventory' -Completed
    $stage='Independent process identity and second POP3 scope consistency check'
    $p2=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($p2.Count -ne 1 -or [int]$p2[0].Id -ne $processIdBefore -or
       [long]$p2[0].StartTime.ToUniversalTime().Ticks -ne $processStartBefore){
        throw 'BW4k7s Outlook process restarted during scan.'
    }
    $pstAfter=[long](Get-Item -LiteralPath $SourcePst -ErrorAction Stop).Length
    if($pstAfter -ne $pstBefore){throw 'BW4k7s source PST physical length changed.'}
    $fresh=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7qPop3ScopeExclusionReview.ps1') @q
    if([long]$fresh.SourcePstLengthBytes -ne $pstBefore -or
       [int]$fresh.CurrentFolderCount -ne [int]$scope.CurrentFolderCount -or
       [long]$fresh.ProposedScopeItemCount -ne [long]$scope.ProposedScopeItemCount -or
       [long]$fresh.ExcludedScopeItemCount -ne [long]$scope.ExcludedScopeItemCount){
        throw 'BW4k7s POP3 scope changed after scan.'
    }
    $beforeRows=@($scope.ProposedFolderScope)
    $afterRows=@($fresh.ProposedFolderScope)
    if($beforeRows.Count -ne $afterRows.Count){throw 'BW4k7s source folder count changed.'}
    for($j=0;$j -lt $beforeRows.Count;$j++){
        if([string]$beforeRows[$j].FolderEntryId -ine [string]$afterRows[$j].FolderEntryId -or
           [string]$beforeRows[$j].FolderPath -cne [string]$afterRows[$j].FolderPath -or
           [string]$beforeRows[$j].Disposition -cne [string]$afterRows[$j].Disposition -or
           [long]$beforeRows[$j].ItemsCount -ne [long]$afterRows[$j].ItemsCount){
            throw ('BW4k7s folder identity, count or scope changed: '+$beforeRows[$j].FolderPath)
        }
    }
    $complete=($examined -eq [long]$scope.ProposedScopeItemCount)
    $cross=$null
    if($null -ne $PreviousFullYearInventory){
        $cArgs=@{
            Inventory=$PreviousFullYearInventory
            ExpectedScopeCandidateItems=[long]$scope.ProposedScopeItemCount
            ExpectedSourcePst=[string]$scope.SourcePst
        }
        $cross=Assert-OPA265BW4k7sPriorYearInventory @cArgs
        if($complete -and
           ([long]$cross.NonMailItemsExpected -ne $nonMails -or
            [long]$cross.AllObservedMailItems -ne $mails)){
            throw 'BW4k7s prior full-year and current nonmail counts conflict.'
        }
    }
    $status=if(-not $complete){'BoundedPartialNonMailWitnessesCannotProveFullCoverage'}
            elseif($nonMails -eq 0){'CompleteReadOnlyNoNonMailObjectsSeen'}
            else{'CompleteReadOnlyNonMailWitnessesManualPreservationReview'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7s.Pop3NonMailAndPstRegistryReadOnly.1'
        Status=$status
        SourcePst=[string]$scope.SourcePst
        SourcePstLengthBytesBefore=$pstBefore;SourcePstLengthBytesAfter=$pstAfter
        Pop3StoreVerified=$true;OtherImapOrTestArchivesRead=$false
        ScopeCandidateItems=[long]$scope.ProposedScopeItemCount
        CandidateItemsExamined=$examined;FullNonMailInventoryCoverage=$complete
        MailItemsObserved=$mails;NonMailItemsObserved=$nonMails
        NonMailWitnesses=@($witnesses.ToArray())
        FolderClassSummary=@($stats.ToArray())
        AllNonMailObjectsRequireManualPreservationDecision=($nonMails -gt 0)
        NonMailSafeToAutomaticallyDiscard=$false
        PriorBW4k7rFullYearCrosscheck=$cross
        ReadOnlyArchiveYearCandidates=if($null -ne $cross){@($cross.EligibleArchiveYears)}else{@()
        }
        PriorYearSnapshotCryptographicallySealed=$false
        RegistryLimitDecision=$limits
        PolicyRegistryValues=$policy;UserRegistryValues=$user
        CurrentPstUnicodeFormatIndependentlyVerified=$false
        PhysicalPstWriteCapacityProven=$false
        SourceFolderCountsReconciled=$true;OutlookProcessUnchanged=$true
        AtomicPstSnapshotEstablished=$false
        TestFoldersOrPstDeleted=$false;ArchivePstCreated=$false
        PstOrRegistryWritten=$false;OriginalEvidenceOrClaimRewritten=$false
        OriginalSEM001Unknown0x00010000StillBlocked=$true
        ArchiveResumeAutoEnabled=$false;AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
        NextAction='InspectNonMailClassAndMessageClassAndRegistryLimit;NoMoveOrUnlimitedPstSizeChange'
    }
}catch{
    Write-Progress -Id 8 -Activity 'BW4k7s READ ONLY nonMail class inventory' -Completed
    throw ('BW4k7s READ-ONLY STOP ['+$stage+']: '+[string]$_.Exception.Message+
       '. No Outlook/PST/registry writes or SEM-001 waiver.')
}finally{
    foreach($o in @($ns,$app)){
        if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)
        }
    }
}
