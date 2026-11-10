#requires -Version 5.1
# BW4k7v2a5: read-only investigation of failed CreatePilot in original BW4k7v2a4 suite.
# No AddStore, Save, Move, Delete, Message creation, mailbox cleanup, file writes.
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
    throw 'BW4k7v2a5 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a4OneShotMovePolicy265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a5CountEvidence265.ps1')
$layout=Get-OPA265BW4k7v2a4Layout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
[void](Assert-OPA265BW4k7v2a4Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a5.Plan.1'
        Status='ReadOnlyPlanNoOutlookOrFileContact'
        SuiteId=$SuiteId;ExpectedProfile='Outlook'
        OriginalIntentPath=[string]$layout.IntentPath
        ExpectedTargetPstPath=[string]$layout.PstPath
        ExactSyntheticSubject=[string]$layout.Subject
        SubjectScanBoundPerFolder=16
        SearchFolders='Only existing default Drafts and exact disposable PST fixture folder'
        NoRetryOrComWriters=$true;WriterPermit=$false;ProductionReady=$false
    }
}
if(-not [IO.File]::Exists([string]$layout.IntentPath) -or
   -not [IO.File]::Exists([string]$layout.PstPath)){
    throw 'BW4k7v2a5 original CreateIntent or original test PST missing; no reconstruction.'
}
$intentSha=(Get-FileHash -LiteralPath $layout.IntentPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($ExpectedIntentSha256 -and $ExpectedIntentSha256 -cne $intentSha){
    throw 'BW4k7v2a5 optional independently pinned original IntentSha256 mismatch.'
}
$intent=ConvertFrom-Json -InputObject (
    [IO.File]::ReadAllText([string]$layout.IntentPath,[Text.Encoding]::UTF8))
if([string]$intent.Schema -cne '2.6.5-BW4k7v2a4.CreationIntent.1' -or
   [string]$intent.SuiteId -cne $SuiteId -or
   [string]$intent.PstPath -cne [string]$layout.PstPath -or
   [string]$intent.Subject -cne [string]$layout.Subject -or
   [string]::IsNullOrWhiteSpace([string]$intent.DefaultDraftsStoreId) -or
   [string]::IsNullOrWhiteSpace([string]$intent.DefaultDraftsFolderId) -or
   [string]::IsNullOrWhiteSpace([string]$intent.Pop3DeliveryStoreId) -or
   -not [bool]$intent.AtMostOneDraft -or -not [bool]$intent.AtMostOneMove -or
   -not [bool]$intent.NoAutomaticRetry -or [bool]$intent.ProductionReady){
    throw 'BW4k7v2a5 original CreateIntent invalid or wrong suite, STOP.'
}
function Get-OPA265BW4k7v2a5FolderSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Folder,
        [Parameter(Mandatory=$true)][object]$Ns,
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$Body,
        [Parameter(Mandatory=$true)][string]$Recipient,
        [Parameter(Mandatory=$true)][string]$StoreId
    )
    $count=0;$restrictCount=0;$complete=$false;$restrictComplete=$false
    $err='';$itemsOut=New-Object 'System.Collections.Generic.List[object]'
    $restrictedSubjects=New-Object 'System.Collections.Generic.List[object]'
    try{
        if([string]$Folder.StoreID -cne $StoreId){
            throw 'BW4k7v2a5 folder belongs to wrong StoreID.'
        }
        $items=$Folder.Items
        $raw=$items.Count
        if($null -eq $raw){throw 'BW4k7v2a5 unreadable Items.Count.'}
        $count=[int]$raw
        if($count -lt 0 -or $count -gt 16){
            throw 'BW4k7v2a5 >16 folder items, bounded scan refused.'
        }
        for($i=1;$i -le $count;$i++){
            $item=$items.Item($i)
            if([string]$item.Subject -cne $Subject){continue}
            $id=[string]$item.EntryID
            $parent=$item.Parent
            $exactParent=([string]$parent.StoreID -ceq $StoreId -and
                [string]$parent.EntryID -ceq [string]$Folder.EntryID)
            $byId=$false
            $byIdError=''
            if(-not [string]::IsNullOrWhiteSpace($id)){
                try{
                    $fresh=$Ns.GetItemFromID($id,$StoreId)
                    $byId=([string]$fresh.EntryID -ceq $id -and
                        [string]$fresh.Subject -ceq $Subject -and
                        [string]$fresh.Parent.StoreID -ceq $StoreId -and
                        [string]$fresh.Parent.EntryID -ceq [string]$Folder.EntryID)
                }catch{$byIdError=[string]$_.Exception.Message}
            }
            $itemsOut.Add([pscustomobject][ordered]@{
                SubjectMatches=$true
                EntryId=$id;EntryIdPresent=(-not [string]::IsNullOrWhiteSpace($id))
                Class=[int]$item.Class;ClassIsMail=([int]$item.Class -eq 43)
                ParentMatchesFolder=$exactParent
                BodyMatchesExpected=([string]$item.Body -ceq $Body)
                ToMatchesExpected=([string]$item.To -ceq $Recipient)
                Unread=[bool]$item.UnRead
                ByIdReopenMatches=$byId;ByIdError=$byIdError
            })
        }
        $complete=$true
    }catch{$err=('ManualItems: '+[string]$_.Exception.Message)}
    try{
        $restricted=$Folder.Items.Restrict(("[Subject] = '"+$Subject+"'"))
        $r=$restricted.Count
        if($null -eq $r){throw 'BW4k7v2a5 unreadable restricted Items.Count.'}
        $restrictCount=[int]$r
        if($restrictCount -lt 0 -or $restrictCount -gt 16){
            throw 'BW4k7v2a5 >16 restricted matches, STOP.'
        }
        for($j=1;$j -le $restrictCount;$j++){
            $candidate=$restricted.Item($j)
            if([string]$candidate.Subject -cne $Subject){
                throw 'BW4k7v2a5 Restrict returned non-exact Subject.'
            }
            $restrictedSubjects.Add([pscustomobject]@{
                SubjectMatches=$true;EntryId=[string]$candidate.EntryID
                ParentMatches=([string]$candidate.Parent.StoreID -ceq $StoreId -and
                    [string]$candidate.Parent.EntryID -ceq [string]$Folder.EntryID)
            })
        }
        $restrictComplete=$true
    }catch{
        $err=($err+' Restrict: '+[string]$_.Exception.Message).Trim()
    }
    if(-not $complete){
        $itemsOut.Clear()
    }
    return [pscustomobject][ordered]@{
        FolderPath=[string]$Folder.FolderPath
        FolderId=[string]$Folder.EntryID
        StoreIdSha256=(Get-OPA265BW4k7v2a1Sha256 -Text $StoreId)
        FullItemsCount=$count
        RestrictCount=$restrictCount
        ManualExactSubjectCount=$itemsOut.Count
        RestrictEnumeratedCount=$restrictedSubjects.Count
        ReadComplete=$complete
        RestrictionReadComplete=$restrictComplete
        MatchingCandidates=@($itemsOut.ToArray())
        RestrictedCandidates=@($restrictedSubjects.ToArray())
        ReadError=$err
        COMCollectionObjectScalarCountNotUsed=$true
    }
}
$app=$null;$ns=$null
try{
    $procs=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($procs.Count -ne 1){throw 'BW4k7v2a5 exactly one running Outlook.exe required; no auto-start.'}
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'BW4k7v2a5 unexpected Outlook profile; STOP.'
    }
    $matchedPop3=0
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $a=$ns.Accounts.Item($i)
        if([string]$a.SmtpAddress -ieq [string]$layout.Pop3SmtpAddress -and
           [int]$a.AccountType -eq 2){
            $matchedPop3++
            if([string]$a.DeliveryStore.StoreID -cne
               [string]$intent.Pop3DeliveryStoreId){
                throw 'BW4k7v2a5 POP3 delivery StoreID changed since original intent.'
            }
        }
    }
    if($matchedPop3 -ne 1){throw 'BW4k7v2a5 original POP3 account no longer unique.'}
    $defaultStore=$ns.DefaultStore
    $defaultId=[string]$defaultStore.StoreID
    $drafts=$defaultStore.GetDefaultFolder(16)
    if($defaultId -cne [string]$intent.DefaultDraftsStoreId -or
       $defaultId -ceq [string]$intent.Pop3DeliveryStoreId -or
       [string]$drafts.StoreID -cne $defaultId -or
       [string]$drafts.EntryID -cne [string]$intent.DefaultDraftsFolderId){
        throw 'BW4k7v2a5 original default Drafts StoreID or EntryID changed.'
    }
    $target=$null;$matches=0
    $storeCount=[int]$ns.Stores.Count
    if($storeCount -lt 1 -or $storeCount -gt 32){
        throw 'BW4k7v2a5 too many/zero connected stores.'
    }
    for($i=1;$i -le $storeCount;$i++){
        $s=$ns.Stores.Item($i)
        $path=[string]$s.FilePath
        if(-not [string]::IsNullOrWhiteSpace($path) -and
           [string]::Equals([IO.Path]::GetFullPath($path),[string]$layout.PstPath,
             [StringComparison]::OrdinalIgnoreCase)){
            $matches++;$target=$s
        }
    }
    if($matches -ne 1 -or
       [string]$target.StoreID -ceq $defaultId -or
       [string]$target.StoreID -ceq [string]$intent.Pop3DeliveryStoreId){
        throw 'BW4k7v2a5 exact original disposable test PST not uniquely attached.'
    }
    $root=$target.GetRootFolder()
    $rootCount=[int]$root.Folders.Count
    if($rootCount -lt 0 -or $rootCount -gt 128){
        throw 'BW4k7v2a5 original test PST root folder count invalid.'
    }
    $folder=$null;$folderCount=0
    for($i=1;$i -le $rootCount;$i++){
        $f=$root.Folders.Item($i)
        if([string]$f.Name -ceq [string]$layout.TargetFolderName){
            $folder=$f;$folderCount++
        }
    }
    if($folderCount -ne 1 -or
       [string]$folder.StoreID -cne [string]$target.StoreID){
        throw 'BW4k7v2a5 original disposable target folder missing or ambiguous.'
    }
    $params=@{
        Ns=$ns;Subject=[string]$layout.Subject
        Body=[string]$layout.Body;Recipient=[string]$layout.Recipient
    }
    $source=Get-OPA265BW4k7v2a5FolderSnapshot @params -Folder $drafts -StoreId $defaultId
    $destination=Get-OPA265BW4k7v2a5FolderSnapshot @params -Folder $folder -StoreId ([string]$target.StoreID)
    $diagnosis=Test-OPA265BW4k7v2a5CountEvidence -Source $source -Target $destination
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a5.FailedCreatePilotReadOnly.1'
        Status=[string]$diagnosis.Status
        SuiteId=$SuiteId
        ProfileName='Outlook'
        OriginalIntentSha256=$intentSha
        OriginalIntentPath=[string]$layout.IntentPath
        OriginalPstPath=[string]$layout.PstPath
        TargetPstFilePresent=$true
        OriginalPreMoveManifestExists=[IO.File]::Exists([string]$layout.ManifestPath)
        OriginalMoveClaimExists=[IO.File]::Exists([string]$layout.MoveClaimPath)
        Source=$source;Target=$destination
        Diagnosis=$diagnosis
        OriginalFailedCreatePilotReplayed=$false
        AnyMailMoveSaveOrCreateExecuted=$false
        AnyPstOrEvidenceWritesExecuted=$false
        OtherStoresMailSearched=$false
        MovePilotAllowedForThisSuite=$false
        WriterPermit=$false;ProductionReady=$false
    }
}finally{
    foreach($o in @($ns,$app)){
        if($null -ne $o -and
           [Runtime.InteropServices.Marshal]::IsComObject($o)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)
        }
    }
}