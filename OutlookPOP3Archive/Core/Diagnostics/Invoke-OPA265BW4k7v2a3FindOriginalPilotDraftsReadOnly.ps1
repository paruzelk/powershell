#requires -Version 5.1
# BW4k7v2a3 read-only: only Restrict exact synthetic Subject in already-present Store Drafts.
# Never attach, create, save, move, delete or resend any Outlook object.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [ValidateSet('Plan','Review')][string]$Mode='Review',
    [string]$ExpectedIntentSha256=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7v2a3 requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a1ExistingProfilePolicy265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a3DraftsEvidence265.ps1')
[void](Assert-OPA265BW4k7v2a1SuiteId -SuiteId $SuiteId)
$layout=Get-OPA265BW4k7v2a1Layout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
[void](Assert-OPA265BW4k7v2a1Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a3.Plan.1'
        Status='ReadOnlyDraftsSearchPlanNoOutlookOrFileAccess'
        SuiteId=$SuiteId;ExpectedProfile='Outlook'
        TestPstPath=[string]$layout.PstPath
        OriginalIntentPath=[string]$layout.IntentPath
        ExactPilotSubject=[string]$layout.PilotSubject
        Scope='Store.GetDefaultFolder(16) in already mounted stores only'
        SearchRestriction='Exact synthetic Subject only'
        NoPstMountOrMailSaveOrMove=$true
        WriterPermit=$false;ProductionReady=$false
    }
}
if($ExpectedIntentSha256 -cnotmatch '^[a-f0-9]{64}$'){
    throw 'BW4k7v2a3 Review requires original lowercase IntentSha256.'
}
if(-not [IO.File]::Exists([string]$layout.IntentPath) -or
   -not [IO.File]::Exists([string]$layout.PstPath)){
    throw 'BW4k7v2a3 original intent or original disposable PST missing; no repair.'
}
$actualIntentSha=(Get-FileHash -LiteralPath $layout.IntentPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualIntentSha -cne $ExpectedIntentSha256){
    throw 'BW4k7v2a3 original one-shot Intent SHA256 mismatch; STOP.'
}
$intent=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText(
    [string]$layout.IntentPath,[Text.Encoding]::UTF8))
if([string]$intent.Schema -cne '2.6.5-BW4k7v2a1.Intent.1' -or
   [string]$intent.SuiteId -cne $SuiteId -or
   [string]$intent.ProfileName -cne 'Outlook' -or
   [string]$intent.TestPstPath -cne [string]$layout.PstPath -or
   [string]::IsNullOrWhiteSpace([string]$intent.Pop3DeliveryStoreId) -or
   -not [bool]$intent.NeverRetry){
    throw 'BW4k7v2a3 original Intent fields not authentic for this test.'
}
$app=$null;$ns=$null
try{
    $processes=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($processes.Count -ne 1){throw 'Exactly one existing Outlook.exe process required.'}
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'BW4k7v2a3 profile mismatch; STOP.'
    }
    $accountMatches=0
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $account=$ns.Accounts.Item($i)
        if([string]$account.SmtpAddress -ieq 'info@stios.ru' -and
           [int]$account.AccountType -eq 2){
            $accountMatches++
            if([string]$account.DeliveryStore.StoreID -cne [string]$intent.Pop3DeliveryStoreId){
                throw 'BW4k7v2a3 original POP3 delivery StoreID changed; STOP.'
            }
        }
    }
    if($accountMatches -ne 1){
        throw 'BW4k7v2a3 original POP3 account must be unique.'
    }
    $number=[int]$ns.Stores.Count
    if($number -lt 1 -or $number -gt 32){
        throw 'BW4k7v2a3 store count outside bounded 1..32.'
    }
    $targetCount=0
    $storeSnapshots=New-Object 'System.Collections.Generic.List[object]'
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for($i=1;$i -le $number;$i++){
        $store=$ns.Stores.Item($i)
        $id=[string]$store.StoreID
        $path=[string]$store.FilePath
        if([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)){
            throw 'BW4k7v2a3 missing/duplicate store ID; STOP.'
        }
        $isTarget=$false
        if(-not [string]::IsNullOrWhiteSpace($path)){
            $isTarget=[string]::Equals([IO.Path]::GetFullPath($path),
                [string]$layout.PstPath,[StringComparison]::OrdinalIgnoreCase)
        }
        if($isTarget){
            $targetCount++
            if($id -ceq [string]$intent.Pop3DeliveryStoreId){
                throw 'BW4k7v2a3 disposable target PST equals POP3 delivery store; STOP.'
            }
        }
        $storeSnapshots.Add([pscustomobject]@{
            Index=$i;StoreId=$id;FilePath=$path;IsTargetTestPst=$isTarget
        })
    }
    if($targetCount -ne 1){
        throw 'BW4k7v2a3 original test PST must already be mounted exactly once; no auto-mount.'
    }
    $defaultStoreId=[string]$ns.DefaultStore.StoreID
    # olFolderDrafts=16; Store.GetDefaultFolder avoids NameSpace.GetDefaultFolder
    # and permits explicit store scoping without opening other mailbox folders.
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $summaries=New-Object 'System.Collections.Generic.List[object]'
    $candidates=New-Object 'System.Collections.Generic.List[object]'
    foreach($snap in @($storeSnapshots.ToArray())){
        $store=$ns.Stores.Item([int]$snap.Index)
        $id=[string]$snap.StoreId
        $idHash=Get-OPA265BW4k7v2a1Sha256 -Text $id
        $state='Read'
        $errorText=''
        $draftPath=''
        $draftId=''
        $draftsCount=-1
        $matches=New-Object 'System.Collections.Generic.List[object]'
        try{
            $drafts=$store.GetDefaultFolder(16)
            if($null -eq $drafts){
                $state='NoDraftsFolder'
            }else{
                $draftId=[string]$drafts.EntryID
                $draftPath=[string]$drafts.FolderPath
                if([string]$drafts.StoreID -cne $id){
                    throw 'Store.GetDefaultFolder(16) returned wrong StoreID.'
                }
                $rawCount=$drafts.Items.Count
                if($null -eq $rawCount){throw 'Drafts.Items.Count unreadable.'}
                $draftsCount=[int]$rawCount
                if($draftsCount -lt 0){
                    throw 'Drafts.Items.Count negative.'
                }
                # Query only the exact controlled ASCII synthetic Subject.
                # Do not enumerate or materialize unrelated mail items/bodies.
                $restricted=$drafts.Items.Restrict(
                    "[Subject] = '"+[string]$layout.PilotSubject+"'")
                $rawMatches=$restricted.Count
                if($null -eq $rawMatches){throw 'Restricted Items.Count unreadable.'}
                $matchedCount=[int]$rawMatches
                if($matchedCount -lt 0 -or $matchedCount -gt 8){
                    $state='MatchLimitExceeded'
                }else{
                    for($j=1;$j -le $matchedCount;$j++){
                        $item=$restricted.Item($j)
                        if([string]$item.Subject -cne [string]$layout.PilotSubject){
                            throw 'Outlook Restrict returned non-exact Subject.'
                        }
                        $itemId=[string]$item.EntryID
                        $itemClass=[int]$item.Class
                        $parent=$item.Parent
                        $parentStore=[string]$parent.StoreID
                        $parentFolder=[string]$parent.EntryID
                        $sameStore=$parentStore -ceq $id
                        $sameFolder=$parentFolder -ceq $draftId
                        $readById=$false
                        $readStatus='SkippedNoEntryID'
                        if(-not [string]::IsNullOrWhiteSpace($itemId)){
                            try{
                                $reopened=$ns.GetItemFromID($itemId,$id)
                                $readById=([string]$reopened.Subject -ceq
                                    [string]$layout.PilotSubject -and
                                    [string]$reopened.EntryID -ceq $itemId -and
                                    [string]$reopened.Parent.StoreID -ceq $id -and
                                    [string]$reopened.Parent.EntryID -ceq $draftId)
                                $readStatus=if($readById){'ExactById'}else{'MismatchById'}
                            }catch{$readStatus='ByIdError: '+[string]$_.Exception.Message}
                        }
                        $record=[pscustomobject][ordered]@{
                            SubjectMatches=$true;StoreIdSha256=$idHash
                            StoreIsDefault=($id -ceq $defaultStoreId)
                            StoreIsPop3Delivery=($id -ceq [string]$intent.Pop3DeliveryStoreId)
                            StoreIsOriginalTestPst=[bool]$snap.IsTargetTestPst
                            StorePath=[string]$snap.FilePath
                            DraftsFolderPath=$draftPath
                            Class=$itemClass;ClassIsMail=($itemClass -eq 43)
                            ItemEntryId=$itemId
                            ParentStoreMatches=$sameStore
                            ParentDraftsFolderMatches=$sameFolder
                            GetItemFromIdMatches=$readById
                            ByIdReadStatus=$readStatus
                        }
                        $matches.Add($record)
                        $candidates.Add($record)
                        if($candidates.Count -gt 16){
                            throw 'BW4k7v2a3 aggregate matched item bound exceeded.'
                        }
                    }
                }
            }
        }catch{
            $state='ProviderError'
            $errorText=[string]$_.Exception.Message
            # Never classify partially enumerated matches as a complete store read.
            while($matches.Count -gt 0){
                $matches.RemoveAt($matches.Count-1)
                $candidates.RemoveAt($candidates.Count-1)
            }
        }
        $rows.Add([pscustomobject]@{
            StoreIdSha256=$idHash;Status=$state
            Matches=@($matches.ToArray())
        })
        $summaries.Add([pscustomobject][ordered]@{
            StoreIndex=[int]$snap.Index
            StoreIdSha256=$idHash
            StorePath=[string]$snap.FilePath
            IsProfileDefault=($id -ceq $defaultStoreId)
            IsPop3Delivery=($id -ceq [string]$intent.Pop3DeliveryStoreId)
            IsOriginalTestPst=[bool]$snap.IsTargetTestPst
            DraftsStatus=$state
            DraftsFolderPath=$draftPath
            DraftsItemCount=$draftsCount
            RestrictedSubjectMatchCount=$matches.Count
            InspectionError=$errorText
        })
    }
    $diag=Test-OPA265BW4k7v2a3DraftsEvidence -Rows @($rows.ToArray())
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a3.LiveDraftsReadOnly.1'
        Status=[string]$diag.Status
        SuiteId=$SuiteId;ProfileName='Outlook'
        OriginalIntentSha256=$actualIntentSha
        OriginalTargetPstPath=[string]$layout.PstPath
        ExistingStoresChecked=$number
        DraftsFoldersWithReadableSearch=$diag.ReadDraftsFolderCount
        ExactPilotSubjectMatches=$diag.ExactSubjectMatchCount
        StoreChecks=@($summaries.ToArray())
        PilotMatches=@($candidates.ToArray())
        Diagnosis=$diag
        OtherFoldersAndMessageBodiesNotRead=$true
        OriginalFailedCreatePilotReplayed=$false
        AddStoreExSaveMoveSendDeleteExecuted=$false
        EvidenceOrPstWritten=$false
        WriterPermit=$false;ProductionReady=$false
    }
}finally{
    foreach($obj in @($ns,$app)){
        if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)
        }
    }
}