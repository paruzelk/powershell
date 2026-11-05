#requires -Version 5.1
# BW4k7v2a2: only read previously failed pilot suite; never mount, create, save, or move.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [ValidateSet('Plan','Review')][string]$Mode='Review'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7v2a2 requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a1ExistingProfilePolicy265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a2ReadOnlyPilotObservation265.ps1')
[void](Assert-OPA265BW4k7v2a1SuiteId -SuiteId $SuiteId)
$layout=Get-OPA265BW4k7v2a1Layout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
[void](Assert-OPA265BW4k7v2a1Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a2.Plan.1'
        Status='ReadOnlyPlanNoOutlookContactNoFileWrites'
        SuiteId=$SuiteId;ExpectedProfile='Outlook'
        ExpectedPstPath=[string]$layout.PstPath
        ExpectedIntentPath=[string]$layout.IntentPath
        NoPstAttachOrCreate=$true;NoMailMovementOrSaves=$true
        WriterPermit=$false;ProductionReady=$false
    }
}
if(-not [IO.Directory]::Exists([string]$layout.SuiteDirectory)){
    throw 'BW4k7v2a2 original suite directory not found; cannot reconstruct it.'
}
if(-not [IO.File]::Exists([string]$layout.IntentPath)){
    throw 'BW4k7v2a2 original one-pilot-intent.json absent; stop (do not recreate).'
}
$intentSha=(Get-FileHash -LiteralPath $layout.IntentPath -Algorithm SHA256).Hash.ToLowerInvariant()
$intent=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText(
    [string]$layout.IntentPath,[Text.Encoding]::UTF8))
if([string]$intent.Schema -cne '2.6.5-BW4k7v2a1.Intent.1' -or
   [string]$intent.SuiteId -cne $SuiteId -or
   [string]$intent.TestPstPath -cne [string]$layout.PstPath -or
   [string]$intent.ProfileName -cne 'Outlook' -or
   [string]::IsNullOrWhiteSpace([string]$intent.Pop3DeliveryStoreId) -or
   -not [bool]$intent.NeverRetry){
    throw 'BW4k7v2a2 original one-shot intent invalid or mismatched; STOP.'
}
$manifestPresent=[IO.File]::Exists([string]$layout.ManifestPath)
$manifestSha=''
if($manifestPresent){
    $manifestSha=(Get-FileHash -LiteralPath $layout.ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$pstPresent=[IO.File]::Exists([string]$layout.PstPath)
$pstSize=if($pstPresent){[long](Get-Item -LiteralPath $layout.PstPath).Length}else{0L}
$app=$null;$ns=$null;$store=$null;$folder=$null
try{
    $procs=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($procs.Count -ne 1){
        throw 'BW4k7v2a2 requires one running Outlook.exe process; never auto-launch.'
    }
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    $profile=[string]$ns.CurrentProfileName
    if($profile -cne 'Outlook'){throw 'BW4k7v2a2 unexpected current profile; STOP.'}
    $matchedPop3=0
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $a=$ns.Accounts.Item($i)
        if([string]$a.SmtpAddress -ieq 'info@stios.ru' -and [int]$a.AccountType -eq 2){
            $matchedPop3++
            if([string]$a.DeliveryStore.StoreID -cne [string]$intent.Pop3DeliveryStoreId){
                throw 'BW4k7v2a2 POP3 DeliveryStore changed since original intent.'
            }
        }
    }
    if($matchedPop3 -ne 1){throw 'BW4k7v2a2 original POP3 delivery account not unique.'}
    $storeMatches=0
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $s=$ns.Stores.Item($i)
        $path=[string]$s.FilePath
        if(-not [string]::IsNullOrWhiteSpace($path) -and
           [string]::Equals([IO.Path]::GetFullPath($path),
               [string]$layout.PstPath,[StringComparison]::OrdinalIgnoreCase)){
            $storeMatches++
            $store=$s
        }
    }
    $folderMatches=0;$itemsCount=-1;$rootChildren=-1
    $storeId='';$folderId='';$folderPath=''
    $rows=New-Object 'System.Collections.Generic.List[object]'
    if($storeMatches -eq 1 -and $pstPresent){
        $storeId=[string]$store.StoreID
        if($storeId -ceq [string]$intent.Pop3DeliveryStoreId){
            throw 'BW4k7v2a2 target PST is POP3 delivery store: STOP without item reads.'
        }
        $root=$store.GetRootFolder()
        $rawCount=$root.Folders.Count
        if($null -eq $rawCount){throw 'BW4k7v2a2 root child count unreadable.'}
        $rootChildren=[int]$rawCount
        if($rootChildren -lt 0 -or $rootChildren -gt 128){
            throw 'BW4k7v2a2 root folder count outside 0..128 limit.'
        }
        for($j=1;$j -le $rootChildren;$j++){
            $f=$root.Folders.Item($j)
            if([string]$f.Name -ceq [string]$layout.TestFolderName){
                $folderMatches++;$folder=$f
            }
        }
        if($folderMatches -eq 1){
            $folderId=[string]$folder.EntryID
            $folderPath=[string]$folder.FolderPath
            if([string]$folder.StoreID -cne $storeId){
                throw 'BW4k7v2a2 test folder StoreID differs from target PST.'
            }
            $rawItems=$folder.Items.Count
            if($null -eq $rawItems){throw 'BW4k7v2a2 test folder Items.Count unreadable.'}
            $itemsCount=[int]$rawItems
            if($itemsCount -lt 0 -or $itemsCount -gt 16){
                throw 'BW4k7v2a2 folder >16 items: stop bounded read-only inspection.'
            }
            for($k=1;$k -le $itemsCount;$k++){
                $item=$folder.Items.Item($k)
                $subject=[string]$item.Subject
                $subjectMatches=($subject -ceq [string]$layout.PilotSubject)
                $entryId=[string]$item.EntryID
                $class=[int]$item.Class
                $parentStore='';$parentFolder='';$parentReadError=''
                try{
                    $parent=$item.Parent
                    $parentStore=[string]$parent.StoreID
                    $parentFolder=[string]$parent.EntryID
                }catch{$parentReadError=[string]$_.Exception.Message}
                $readById=$false;$readByIdError=''
                if($subjectMatches -and -not [string]::IsNullOrWhiteSpace($entryId)){
                    try{
                        $fresh=$ns.GetItemFromID($entryId,$storeId)
                        $readById=([string]$fresh.EntryID -ceq $entryId -and
                            [string]$fresh.Subject -ceq [string]$layout.PilotSubject -and
                            [string]$fresh.Parent.StoreID -ceq $storeId -and
                            [string]$fresh.Parent.EntryID -ceq $folderId)
                    }catch{$readByIdError=[string]$_.Exception.Message}
                }
                $rows.Add([pscustomobject][ordered]@{
                    Index=$k;SubjectMatches=$subjectMatches
                    SubjectLabel=if($subjectMatches){$subject}else{'OtherItemInTestFolder'}
                    Class=$class;ClassIsMail=($class -eq 43)
                    ItemEntryIdPresent=(-not [string]::IsNullOrWhiteSpace($entryId))
                    EntryId=$entryId
                    ParentStoreMatches=($parentStore -ceq $storeId)
                    ParentFolderMatches=($parentFolder -ceq $folderId)
                    GetItemFromIdMatches=$readById
                    ParentReadError=$parentReadError
                    GetItemFromIdError=$readByIdError
                })
            }
        }
    }
    $obsArgs=@{
        PstFilePresent=$pstPresent;IntentPresent=$true
        TargetStoreMatches=$storeMatches;TestFolderMatches=$folderMatches
        TestFolderItemCount=$itemsCount;Candidates=@($rows.ToArray())
    }
    $observation=Test-OPA265BW4k7v2a2PilotObservation @obsArgs
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a2.LiveForensicReadOnly.1'
        Status=[string]$observation.Status
        SuiteId=$SuiteId;ProfileName=$profile
        TargetPstPath=[string]$layout.PstPath
        TargetPstFilePresent=$pstPresent;TargetPstLengthBytes=$pstSize
        IntentSha256=$intentSha
        OriginalManifestExists=$manifestPresent;OriginalManifestSha256=$manifestSha
        OutlookStoreCount=[int]$ns.Stores.Count
        ExactTargetPstStores=$storeMatches;RootChildFolderCount=$rootChildren
        ExactTestFolderMatches=$folderMatches;TestFolderPath=$folderPath
        TargetStoreId=$storeId;TestFolderId=$folderId
        TestFolderItemCount=$itemsCount
        CandidateItems=@($rows.ToArray());Diagnosis=$observation
        OriginalFailedCreatePilotReplayed=$false
        AddStoreExOrSaveOrMoveExecuted=$false;OtherStoresMailSearched=$false
        PstOrEvidenceFilesChanged=$false
        ProductionReady=$false;WriterPermit=$false
    }
}finally{
    foreach($obj in @($folder,$store,$ns,$app)){
        if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)
        }
    }
}