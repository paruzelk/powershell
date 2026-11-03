#requires -Version 5.1
# BW4k7q: immutable in-memory policy for POP3-only archive folder scope, READ ONLY.
# Existing BW4k7p COM enumerator supplies the exact POP3 delivery-store topology.
# This module never opens Outlook, reads message bodies, creates PSTs or writes claims.
function Get-OPA265BW4k7qScopePolicy {
    [CmdletBinding()]
    param()
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7q.Pop3ScopeExclusionPolicy.1'
        PolicyId='POP3-SCOPE-001-BW4k7q-v1'
        ExpectedProfileName='Outlook'
        ExpectedSourcePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.pst'
        RequiredRoles=@('Inbox','SentItems','UserMail')
        RequiredDefaultFolderTypes=@(6,5)
        OutboxDefaultFolderType=4
        ReservedTestRootPattern='^(?i:OPA264-LIVE3-[0-9a-f]{32}|OPA265-(?:BW[0-9a-z]+|LIVE[0-9a-z]+)-[0-9a-f]{32})$'
        KnownSettingsRootNames=@('Настройка действий беседы','Настройка быстрых действий')
        ExactPop3StoreOnly=$true
        ImapSentItemsIncluded=$false
        EmptyPop3SentStillRequired=$true
        TestFoldersRetainedOnDisk=$true
        ExclusionsRequireNoDeletes=$true
        HistoricIrreversibleClaimRewritten=$false
        PreviousUnknownMapi0x00010000Waived=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7qInventoryContract {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Inventory)
    $p=Get-OPA265BW4k7qScopePolicy
    if([string]$Inventory.Schema -cne '2.6.5-BW4k7p.Pop3FolderScopeReadOnlyInventory.1' -or
       [string]$Inventory.Status -cne 'Pop3FolderTopologyIdentifiedYearScanNotRequested' -or
       [string]$Inventory.ExpectedProfileName -cne [string]$p.ExpectedProfileName -or
       [string]::IsNullOrWhiteSpace([string]$Inventory.SourcePst)){
        throw 'BW4k7q requires original BW4k7p structure-only exact POP3 inventory.'
    }
    $expected=[IO.Path]::GetFullPath([string]$p.ExpectedSourcePst)
    $actual=[IO.Path]::GetFullPath([string]$Inventory.SourcePst)
    if(-not [string]::Equals($expected,$actual,[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k7q source PST path changed (other store). STOP.'
    }
    $truth=@('ExactPop3DeliveryStoreVerified','ScopeRestrictedToOnePop3Store',
             'SentItemsResolvedInThisPop3Store','OutboxResolvedInThisPop3Store',
             'OutboxNeverEquivalentToSentItems','DefaultStoreFolderNamesNotUsedForIdentity')
    foreach($field in $truth){
        if($Inventory.PSObject.Properties.Name -cnotcontains $field -or
           $Inventory.$field -isnot [bool] -or -not $Inventory.$field){
            throw ('BW4k7q missing verified exact POP3 identity: '+$field)
        }
    }
    $falses=@('OtherImapOrPop3StoresRead','YearScanRequested','YearScanComplete',
              'ProposedArchiveFilesCreated','PstCapacityAndYearRolloverValidated',
              'ProductionSentCoverageProven','FullProductionSemanticIntegrityProven',
              'OutlookMoveExecuted','ClaimOrJournalWritten','AutomaticRetryAllowed',
              'WriterPermit','ProductionReady')
    foreach($field in $falses){
        if($Inventory.PSObject.Properties.Name -cnotcontains $field -or
           $Inventory.$field -isnot [bool] -or $Inventory.$field){
            throw ('BW4k7q unexpected write/read scope or false proof: '+$field)
        }
    }
    foreach($field in @('RootFolderEntryId','InboxDefaultFolderEntryId',
                       'SentItemsDefaultFolderEntryId','OutboxDefaultFolderEntryId')){
        if([string]::IsNullOrWhiteSpace([string]$Inventory.$field)){
            throw ('BW4k7q missing POP3 default folder EntryID '+$field)
        }
    }
    $ids=@([string]$Inventory.RootFolderEntryId,
           [string]$Inventory.InboxDefaultFolderEntryId,
           [string]$Inventory.SentItemsDefaultFolderEntryId,
           [string]$Inventory.OutboxDefaultFolderEntryId)
    if(@($ids | Select-Object -Unique).Count -ne 4){
        throw 'BW4k7q default POP3 Inbox, Sent, Outbox and root folder IDs must be distinct.'
    }
    $folders=@($Inventory.FolderInventory)
    if($folders.Count -lt 4 -or $folders.Count -gt 20000 -or
       [int]$Inventory.FolderCount -ne $folders.Count -or
       [long]$Inventory.SourcePstLengthBytes -lt 1){
        throw 'BW4k7q untrusted folder topology count or PST length.'
    }
    $byPath=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $seenId=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $sumEligible=0L;$sumExcluded=0L;$rootCount=0;$inboxCount=0;$sentCount=0;$outboxCount=0
    foreach($r in $folders){
        $path=[string]$r.FolderPath;$entry=[string]$r.FolderEntryId
        $role=[string]$r.Role;$level=[int]$r.Depth
        if([string]::IsNullOrWhiteSpace($path) -or $path.Length -gt 4096 -or
           $path[0] -ne '\' -or $path -match '\\\\' -or
           [string]::IsNullOrWhiteSpace($entry) -or
           -not $seenId.Add($entry) -or $byPath.ContainsKey($path) -or
           $role -cnotin @('Root','Inbox','SentItems','OutboxExcluded',
                            'SystemExcluded','UserMail','NonMailExcluded','Unresolved')){
            throw 'BW4k7q duplicate/invalid folder path, EntryID or role.'
        }
        if($path -ceq '\'){
            if($role -cne 'Root' -or $level -ne 0 -or
               $entry -cne [string]$Inventory.RootFolderEntryId -or
               $null -ne $r.ItemsCount){throw 'BW4k7q root folder identity inconsistent.'}
            $rootCount++
        }else{
            $tail=$path.LastIndexOf('\')
            $parent=if($tail -eq 0){'\'}else{$path.Substring(0,$tail)}
            if(-not $byPath.ContainsKey($parent)){
                throw ('BW4k7q missing or out-of-order ancestor: '+$path)
            }
            $pr=$byPath[$parent]
            if($level -ne ([int]$pr.Depth+1) -or
               [string]$r.ParentRole -cne [string]$pr.Role -or
               $null -eq $r.ItemsCount -or [long]$r.ItemsCount -lt 0){
                throw ('BW4k7q folder ancestor, depth, item count or inherited role changed: '+$path)
            }
            if($role -in @('Inbox','SentItems','UserMail')){$sumEligible+=[long]$r.ItemsCount}
            else{$sumExcluded+=[long]$r.ItemsCount}
        }
        if($entry -ieq [string]$Inventory.InboxDefaultFolderEntryId){
            if($role -cne 'Inbox') {throw 'BW4k7q exact Inbox folder cannot be reclassified.'}
            $inboxCount++
        }
        if($entry -ieq [string]$Inventory.SentItemsDefaultFolderEntryId){
            if($role -cne 'SentItems'){throw 'BW4k7q exact Sent folder cannot be reclassified.'}
            $sentCount++
        }
        if($entry -ieq [string]$Inventory.OutboxDefaultFolderEntryId){
            if($role -cne 'OutboxExcluded'){throw 'BW4k7q Outbox mistaken for Sent.'}
            $outboxCount++
        }
        if($role -in @('Inbox','SentItems','UserMail') -and -not [bool]$r.IncludedInFutureScope){
            throw ('BW4k7q old inventory unexpectedly omitted mail candidate '+$path)
        }
        if($role -notin @('Inbox','SentItems','UserMail') -and [bool]$r.IncludedInFutureScope){
            throw ('BW4k7q old inventory marked non-mail as eligible '+$path)
        }
        $byPath.Add($path,$r)
    }
    if($rootCount -ne 1 -or $inboxCount -ne 1 -or
       $sentCount -ne 1 -or $outboxCount -ne 1 -or
       $sumEligible -ne [long]$Inventory.EligibleFolderItemsObserved -or
       $sumExcluded -ne [long]$Inventory.ExcludedFolderItemsObserved){
        throw 'BW4k7q failed exact POP3 default folder uniqueness / count reconciliation.'
    }
    return $true
}
function Get-OPA265BW4k7qScopeDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Inventory)
    [void](Assert-OPA265BW4k7qInventoryContract -Inventory $Inventory)
    $policy=Get-OPA265BW4k7qScopePolicy
    $items=@($Inventory.FolderInventory)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $byPath=@{};$counts=@{};$included=0L;$excluded=0L;$quarantined=0L
    $specialReview=0;$testCount=0;$settingsCount=0;$sentItems=0L
    foreach($r in $items){
        $path=[string]$r.FolderPath
        $entry=[string]$r.FolderEntryId
        $role=[string]$r.Role
        $reason='';$include=$false;$review=$false;$scope='Excluded'
        $parentName=''
        if($path -cne '\'){
            $pos=$path.LastIndexOf('\')
            $parentName=if($pos -eq 0){'\'}else{$path.Substring(0,$pos)}
        }
        $parentClass=if($parentName -and $byPath.ContainsKey($parentName)){
            [string]$byPath[$parentName].Disposition
        }else{''}
        if($role -ceq 'Root'){
            $reason='Pop3StoreRoot';$scope='Root'
        }elseif($role -ceq 'OutboxExcluded'){
            $reason='ExactPop3OutboxByEntryId'
        }elseif($role -in @('SystemExcluded','NonMailExcluded','Unresolved')){
            $reason='StoreDefaultOrNonMailExcluded'
        }elseif($parentClass -in @('QuarantinedTestFolder','QuarantinedTestDescendant')){
            $reason='NestedUnderReservedTestFolder';$scope='Quarantine'
        }elseif($parentClass -in @('ExcludedSpecialSettings','ExcludedSpecialSettingsNeedsReview','ExcludedInheritedSpecialSettings')){
            $reason='NestedUnderSpecialSettings';$scope='Excluded'
            $review=($parentClass -ceq 'ExcludedSpecialSettingsNeedsReview' -or
                     [bool]$byPath[$parentName].NeedsManualReview)
        }else{
            $last=$path.LastIndexOf('\')
            $base=$path.Substring($last+1)
            $topLevel=($last -eq 0)
            $isReserved=($topLevel -and
                         $base -match [string]$policy.ReservedTestRootPattern)
            $isSettings=($topLevel -and
                         $base -cin [string[]]$policy.KnownSettingsRootNames)
            if($isReserved){
                $reason='ExactReservedTestFolderName';$scope='Quarantine';$testCount++
            }elseif($isSettings){
                $reason='ExactKnownOutlookSettingsFolder';$scope='Excluded';$settingsCount++
                if([long]$r.ItemsCount -gt 0){$review=$true}
            }elseif($role -ceq 'Inbox'){
                $reason='ExactPop3InboxByEntryId';$scope='Include';$include=$true
            }elseif($role -ceq 'SentItems'){
                $reason='ExactPop3SentByEntryIdEvenWhenEmpty';$scope='Include';$include=$true
                $sentItems=[long]$r.ItemsCount
            }elseif($role -ceq 'UserMail'){
                $reason='Pop3UserMailFolder';$scope='Include';$include=$true
            }else{
                throw ('BW4k7q unresolved classifier role '+$role)
            }
        }
        $disposition=if($scope -eq 'Quarantine'){
            if($reason -eq 'NestedUnderReservedTestFolder'){'QuarantinedTestDescendant'}else{'QuarantinedTestFolder'}
        }elseif($reason -eq 'ExactKnownOutlookSettingsFolder'){
            if($review){'ExcludedSpecialSettingsNeedsReview'}else{'ExcludedSpecialSettings'}
        }elseif($reason -eq 'NestedUnderSpecialSettings'){
            'ExcludedInheritedSpecialSettings'
        }elseif($include){'IncludedReadOnlyCandidate'}else{'ExcludedReadOnly'}
        if($include){$included+=[long]$r.ItemsCount}
        elseif($role -ne 'Root'){
            $excluded+=[long]$r.ItemsCount
            if($scope -eq 'Quarantine'){$quarantined+=[long]$r.ItemsCount}
        }
        if($review){$specialReview++}
        if(-not $counts.ContainsKey($disposition)){$counts[$disposition]=0}
        $counts[$disposition]=[int]$counts[$disposition]+1
        $result=[pscustomobject][ordered]@{
            FolderPath=$path
            FolderEntryId=$entry
            PreviousBW4k7pRole=$role
            ItemsCount=$r.ItemsCount
            Disposition=$disposition
            InclusionReason=$reason
            IncludedInProposedPop3Scope=[bool]$include
            NeedsManualReview=[bool]$review
            TestFolderOrDescendant=($scope -eq 'Quarantine')
            RootOfReservedTestFolder=($reason -eq 'ExactReservedTestFolderName')
            OutlookOrPstModified=$false
        }
        $rows.Add($result)
        $byPath[$path]=$result
    }
    $expectedTotal=[long]$Inventory.EligibleFolderItemsObserved+[long]$Inventory.ExcludedFolderItemsObserved
    if($included+$excluded -ne $expectedTotal){
        throw 'BW4k7q total item coverage or exclusion reconciliation failed.'
    }
    $sentRow=@($rows.ToArray() | Where-Object {$_.FolderEntryId -ieq [string]$Inventory.SentItemsDefaultFolderEntryId})
    if($sentRow.Count -ne 1 -or
       -not [bool]$sentRow[0].IncludedInProposedPop3Scope){
        throw 'BW4k7q Sent Mail must be included even when empty.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7q.Pop3FolderScopeDecision.1'
        Status=if($specialReview -gt 0){
            'ExactPop3ScopeReadOnlySpecialSettingsNonemptyManualReview'
        }else{
            'ExactPop3ScopeReadOnlyTestFoldersQuarantinedNoProductionPermit'
        }
        PolicyId=$policy.PolicyId
        SourcePst=[string]$Inventory.SourcePst
        Pop3StoreSourceVerified=$true
        ImapStoreItemsInspected=$false
        SentItemsEntryId=[string]$Inventory.SentItemsDefaultFolderEntryId
        InboxEntryId=[string]$Inventory.InboxDefaultFolderEntryId
        OutboxEntryId=[string]$Inventory.OutboxDefaultFolderEntryId
        SentItemsIncludedEvenWhenEmpty=$true
        CurrentSentItemsCount=[long]$sentRow[0].ItemsCount
        HistoricSentItemsCoverageProven=$false
        FoldersObserved=$rows.Count
        ReservedTestRootFolders=$testCount
        SpecialOutlookSettingsFoldersExcluded=$settingsCount
        SpecialSettingsFolderReviewCount=$specialReview
        ScopeIncludedMailCandidatesObserved=$included
        ScopeExcludedItemsObserved=$excluded
        ReservedTestFolderItemsQuarantined=$quarantined
        TotalFolderItemsReconciled=$true
        FinalFolderDecisions=@($rows.ToArray())
        FolderDispositionCounts=$counts
        ProposeOutlookPstChanges=$false
        NoTestFoldersDeleted=$true
        NoTestArchivePstsDetachedOrDeleted=$true
        NoOriginalEvidenceOrClaimMutation=$true
        NoOutlookMoveOrOtherWriter=$true
        Unknown0x00010000StillBlocked=$true
        YearlyArchiveCapacityRolloverProven=$false
        FullInboxSentCustomFolderMessageContentIntegrityProven=$false
        PhysicalPstDurabilityProven=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='PreserveAllTestFoldersAndPsts;OperatorReviewPop3Scope;NoMoveNoJournalNoProduction'
    }
}
