#requires -Version 5.1
# BW4k7v2a1: explicit new PST in existing Outlook POP3 profile. ONE pilot, NO retry.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Prepare','Inspect','CreatePilot','VerifyPilot')][string]$Mode,
    [string]$SuiteId=([guid]::NewGuid().ToString('D')),
    [switch]$ConfirmExistingProfilePilot,
    [string]$ApprovalText='',
    [string]$ExpectedManifestSha256=''
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
  [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7v2a1 requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a1ExistingProfilePolicy265.ps1')
[void](Assert-OPA265BW4k7v2a1SuiteId -SuiteId $SuiteId)
$layout=Get-OPA265BW4k7v2a1Layout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
if(-not $dry){
    if($Mode -ceq 'CreatePilot'){
        if(-not $ConfirmExistingProfilePilot -or
           $ApprovalText -cne ('CREATE BW4K7V2A1 PILOT '+$SuiteId)){
            throw 'BW4k7v2a1 requires exact per-SuiteId creation approval.'
        }
    }elseif($ConfirmExistingProfilePilot -or $ApprovalText){
        throw 'Creation approval only valid for CreatePilot.'
    }
    if($Mode -ceq 'VerifyPilot'){
        if($ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'VerifyPilot requires original lowercase SHA256.'
        }
    }elseif($ExpectedManifestSha256){throw 'Unexpected manifest SHA256.'}
}
if($dry -or $Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a1.Plan.1'
        Status=if($dry){'WhatIfNoOutlookOrFileWrites'}else{'PlanNoOutlookAccess'}
        SuiteId=$SuiteId;ProfileName='Outlook';Pop3SmtpAddress='info@stios.ru'
        PstPath=[string]$layout.PstPath;SuiteDirectory=[string]$layout.SuiteDirectory
        OneNewPstAttachedToExistingProfile=$true;DefaultStoreUntouchedByScript=$true
        MaximumTestItems=1;WriterPermit=$false;ProductionReady=$false
    }
}
[void](Assert-OPA265BW4k7v2a1Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
if($Mode -ceq 'Prepare'){
    if([IO.Directory]::Exists([string]$layout.SuiteDirectory)){
        throw 'Suite already exists; never reuse.'
    }
    if(-not $PSCmdlet.ShouldProcess([string]$layout.SuiteDirectory,'Prepare new disposable PST suite directory')){
        throw 'Prepare not approved.'
    }
    if(-not [IO.Directory]::Exists([string]$layout.Root)){
        [void][IO.Directory]::CreateDirectory([string]$layout.Root)
    }
    [void][IO.Directory]::CreateDirectory([string]$layout.SuiteDirectory)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a1.Prepare.1'
        Status='SuiteDirectoryCreatedNoPstNoOutlook'
        SuiteId=$SuiteId;PstPath=[string]$layout.PstPath
        WriterPermit=$false;ProductionReady=$false
    }
}
if(-not [IO.Directory]::Exists([string]$layout.SuiteDirectory)){
    throw 'Run Prepare with this SuiteId first.'
}
$stage='Read active Outlook profile, accounts and StoreIDs only'
$app=$null;$ns=$null;$target=$null;$pilot=$null;$folder=$null
try{
    $procs=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($procs.Count -ne 1){throw 'Exactly one Outlook process required.'}
    $proc=$procs[0]
    $ticks=[long]$proc.StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    $stores=New-Object 'System.Collections.Generic.List[object]'
    $accounts=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $s=$ns.Stores.Item($i)
        $stores.Add([pscustomobject]@{StoreId=[string]$s.StoreID;FilePath=[string]$s.FilePath})
    }
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $a=$ns.Accounts.Item($i)
        $did=''
        if($null -ne $a.DeliveryStore){$did=[string]$a.DeliveryStore.StoreID}
        $accounts.Add([pscustomobject]@{
            SmtpAddress=[string]$a.SmtpAddress;AccountType=[int]$a.AccountType;DeliveryStoreId=$did
        })
    }
    $verifyMode=($Mode -ceq 'VerifyPilot')
    $scopeArgs=@{
        Layout=$layout;ActualProfileName=[string]$ns.CurrentProfileName
        Accounts=@($accounts.ToArray());Stores=@($stores.ToArray())
        AllowTargetAttached=$verifyMode
    }
    $scope=Test-OPA265BW4k7v2a1ExistingProfileScope @scopeArgs
    if(-not $scope.Approved){
        throw ('Expected Outlook POP3 delivery/store scope rejected: '+($scope.ReasonCodes -join ','))
    }
    if($Mode -ceq 'Inspect'){
        if([IO.File]::Exists([string]$layout.PstPath) -or
           [IO.File]::Exists([string]$layout.IntentPath) -or
           [IO.File]::Exists([string]$layout.ManifestPath)){
            throw 'Fresh PST/intent/manifest already exists.'
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a1.Inspect.1'
            Status='ExistingOutlookPop3VerifiedFreshTestPstUnattached'
            SuiteId=$SuiteId;PstPath=[string]$layout.PstPath
            ProfileName='Outlook';Pop3DeliveryStoreId=$scope.Pop3DeliveryStoreId
            StoresCount=$stores.Count;ExistingMailItemsRead=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    if($Mode -ceq 'CreatePilot'){
        if([IO.File]::Exists([string]$layout.PstPath) -or
           [IO.File]::Exists([string]$layout.IntentPath) -or
           [IO.File]::Exists([string]$layout.ManifestPath)){
            throw 'Suite already started; no retry.'
        }
        if(-not $PSCmdlet.ShouldProcess([string]$layout.PstPath,
            'Attach new Unicode test PST and save ONE pilot directly inside its folder')){
            throw 'CreatePilot declined.'
        }
        $stage='Durably write one-shot intent before ANY Outlook mutation'
        $intent=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a1.Intent.1';SuiteId=$SuiteId
            ProfileName='Outlook';TestPstPath=[string]$layout.PstPath
            Pop3DeliveryStoreId=[string]$scope.Pop3DeliveryStoreId
            OutlookProcessId=[int]$proc.Id;OutlookProcessStartUtcTicks=$ticks
            CreatedMailItemLimit=1;NeverRetry=$true;MoveExecuted=$false
        }
        $intentSha=Write-OPA265BW4k7v2a1JsonOnce -Path $layout.IntentPath -Value $intent
        $stage='AddStoreEx new PST with olStoreUnicode=2'
        $ns.AddStoreEx([string]$layout.PstPath,2)
        if(-not [IO.File]::Exists([string]$layout.PstPath)){
            throw 'New PST not created at expected path.'
        }
        $newStores=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le [int]$ns.Stores.Count;$i++){
            $s=$ns.Stores.Item($i)
            $p=[string]$s.FilePath
            $newStores.Add([pscustomobject]@{StoreId=[string]$s.StoreID;FilePath=$p})
            if(-not [string]::IsNullOrWhiteSpace($p) -and
               [string]::Equals([IO.Path]::GetFullPath($p),[string]$layout.PstPath,
                   [StringComparison]::OrdinalIgnoreCase)){
                if($null -ne $target){throw 'Multiple stores map to new PST.'}
                $target=$s
            }
        }
        $scopeArgs.Stores=@($newStores.ToArray())
        $scopeArgs.AllowTargetAttached=$true
        $scopeArgs.ActualProfileName=[string]$ns.CurrentProfileName
        $after=Test-OPA265BW4k7v2a1ExistingProfileScope @scopeArgs
        if(-not $after.Approved -or $null -eq $target -or
           [string]$target.StoreID -ceq [string]$scope.Pop3DeliveryStoreId){
            throw ('New PST did not map to unique non-POP3 StoreID: '+($after.ReasonCodes -join ','))
        }
        $stage='Create only one dedicated folder in NEW PST'
        $root=$target.GetRootFolder()
        if($null -eq $root.Items.Count -or [int]$root.Items.Count -ne 0){
            throw 'New PST root unexpectedly contains visible items.'
        }
        if($null -eq $root.Folders.Count -or [int]$root.Folders.Count -gt 128){
            throw 'Unexpected folder enumeration in new PST.'
        }
        for($j=1;$j -le [int]$root.Folders.Count;$j++){
            if([string]$root.Folders.Item($j).Name -ceq [string]$layout.TestFolderName){
                throw 'Prior test folder unexpectedly exists.'
            }
        }
        $folder=$root.Folders.Add([string]$layout.TestFolderName)
        if([string]$folder.StoreID -cne [string]$target.StoreID){
            throw 'Folder created outside exact new PST.'
        }
        $stage='Folder.Items.Add IPM.Note in target PST only, then Save'
        $pilot=$folder.Items.Add('IPM.Note')
        $pilot.Subject=[string]$layout.PilotSubject
        $pilot.Body='BW4k7v2a1 direct folder pilot '+$SuiteId
        $pilot.To='synthetic-recipient@example.invalid'
        $pilot.UnRead=$false
        $pilot.Save()
        $stage='Verify actual parent, StoreID, double-read semantics'
        $storeId=[string]$target.StoreID
        $folderId=[string]$folder.EntryID
        $itemId=[string]$pilot.EntryID
        if([int]$pilot.Class -ne 43 -or
           [string]$pilot.Subject -cne [string]$layout.PilotSubject -or
           [string]$pilot.Parent.StoreID -cne $storeId -or
           [string]$pilot.Parent.EntryID -cne $folderId -or
           [int]$folder.Items.Count -ne 1 -or
           [string]::IsNullOrWhiteSpace($itemId)){
            throw 'Misrouted or missing pilot. STOP: no retry.'
        }
        $r1=$ns.GetItemFromID($itemId,$storeId)
        $r2=$ns.GetItemFromID($itemId,$storeId)
        foreach($read in @($r1,$r2)){
            if([int]$read.Class -ne 43 -or
               [string]$read.Parent.StoreID -cne $storeId -or
               [string]$read.Parent.EntryID -cne $folderId -or
               [string]$read.Subject -cne [string]$layout.PilotSubject){
                throw 'Item identity not stable across independent StoreID-bound reads.'
            }
        }
        $w1=Get-OPA265BW4k7v2a1Sha256 -Text (
            ([string]$r1.Subject)+'|'+([string]$r1.Body)+'|'+([string]$r1.To)+'|'+([string]$r1.UnRead))
        $w2=Get-OPA265BW4k7v2a1Sha256 -Text (
            ([string]$r2.Subject)+'|'+([string]$r2.Body)+'|'+([string]$r2.To)+'|'+([string]$r2.UnRead))
        if($w1 -cne $w2){throw 'Independent pilot semantic witnesses differ.'}
        $stage='Seal immutable manifest'
        $manifest=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a1.Manifest.1'
            SuiteId=$SuiteId;ProfileName='Outlook'
            TestPstPath=[string]$layout.PstPath;TestStoreId=$storeId
            Pop3DeliveryStoreId=[string]$scope.Pop3DeliveryStoreId
            FolderId=$folderId;ItemId=$itemId;Subject=[string]$layout.PilotSubject
            WitnessSha256=$w1;IntentSha256=$intentSha
            CreatingProcessId=[int]$proc.Id;CreatingProcessStartUtcTicks=$ticks
            CreatedMailItemCount=1;MoveExecuted=$false;SendExecuted=$false
            WriterPermit=$false;ProductionReady=$false
        }
        $manifestSha=Write-OPA265BW4k7v2a1JsonOnce -Path $layout.ManifestPath -Value $manifest
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a1.CreatePilot.1'
            Status='OneDirectFolderPilotSavedInNewPstOnExistingOutlookProfile'
            SuiteId=$SuiteId;TestPstPath=[string]$layout.PstPath
            TestStoreId=$storeId;Pop3DeliveryStoreId=$scope.Pop3DeliveryStoreId
            ManifestSha256=$manifestSha;IntentSha256=$intentSha
            MustRestartOutlook=$true;MoveExecuted=$false;SendExecuted=$false
            DefaultStoreChangedByScript=$false
            OriginalPop3PstModifiedByScript=$false
            AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    $stage='Read immutable manifest and pilot after OUTLOOK process restart'
    $m=Read-OPA265BW4k7v2a1SealedJson -Path $layout.ManifestPath -ExpectedSha256 $ExpectedManifestSha256
    if([string]$m.Schema -cne '2.6.5-BW4k7v2a1.Manifest.1' -or
       [string]$m.SuiteId -cne $SuiteId -or
       [string]$m.ProfileName -cne 'Outlook' -or
       [string]$m.TestPstPath -cne [string]$layout.PstPath -or
       [string]$m.Subject -cne [string]$layout.PilotSubject -or
       [string]$m.Pop3DeliveryStoreId -cne [string]$scope.Pop3DeliveryStoreId -or
       [string]$m.WitnessSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$m.IntentSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [int]$m.CreatedMailItemCount -ne 1 -or
       [bool]$m.MoveExecuted -or [bool]$m.SendExecuted -or
       [bool]$m.WriterPermit -or [bool]$m.ProductionReady){
        throw 'Sealed original manifest is not valid.'
    }
    $intent=Read-OPA265BW4k7v2a1SealedJson -Path $layout.IntentPath -ExpectedSha256 ([string]$m.IntentSha256)
    if([string]$intent.SuiteId -cne $SuiteId -or
       [string]$intent.TestPstPath -cne [string]$layout.PstPath -or
       [string]$intent.Pop3DeliveryStoreId -cne [string]$scope.Pop3DeliveryStoreId){
        throw 'Original one-shot intent mismatch.'
    }
    if([int]$m.CreatingProcessId -eq [int]$proc.Id -or
       [long]$m.CreatingProcessStartUtcTicks -eq $ticks){
        throw 'Complete Outlook process restart required.'
    }
    $actualStoreCount=0
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $s=$ns.Stores.Item($i)
        if([string]$s.StoreID -ceq [string]$m.TestStoreId){
            $actualStoreCount++
            if(-not [string]::Equals([IO.Path]::GetFullPath([string]$s.FilePath),
                [string]$layout.PstPath,[StringComparison]::OrdinalIgnoreCase)){
                throw 'Pinned target StoreID now points elsewhere.'
            }
        }
    }
    if($actualStoreCount -ne 1){throw 'Pinned target StoreID unavailable after restart.'}
    $folder=$ns.GetFolderFromID([string]$m.FolderId,[string]$m.TestStoreId)
    if([string]$folder.Name -cne [string]$layout.TestFolderName -or
       [string]$folder.StoreID -cne [string]$m.TestStoreId -or
       [int]$folder.Items.Count -ne 1){
        throw 'Pinned pilot folder or item count changed.'
    }
    $pilot=$ns.GetItemFromID([string]$m.ItemId,[string]$m.TestStoreId)
    if([int]$pilot.Class -ne 43 -or
       [string]$pilot.Parent.StoreID -cne [string]$m.TestStoreId -or
       [string]$pilot.Parent.EntryID -cne [string]$m.FolderId -or
       [string]$pilot.Subject -cne [string]$layout.PilotSubject){
        throw 'Pinned pilot item identity changed.'
    }
    $w=Get-OPA265BW4k7v2a1Sha256 -Text (
        ([string]$pilot.Subject)+'|'+([string]$pilot.Body)+'|'+([string]$pilot.To)+'|'+([string]$pilot.UnRead))
    if($w -cne [string]$m.WitnessSha256){throw 'Post-restart original semantic witness mismatch.'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a1.VerifyPilot.1'
        Status='OnePilotReopenedAfterRestartInExactNewPstOfExistingProfile'
        SuiteId=$SuiteId;OriginalManifestSha256=$ExpectedManifestSha256
        OriginalStoreFolderItemIdentityMatched=$true
        OriginalPilotSemanticsReverified=$true
        SourceMailReadOrModifiedByScript=$false
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}catch{
    $h='HResultUnavailable'
    try{$n=[int64]$_.Exception.HResult;$h=('0x{0:X8}' -f ([uint32]($n -band 4294967295L)))}catch{}
    throw ('BW4k7v2a1 STOP at ['+$stage+'] HRESULT='+$h+': '+[string]$_.Exception.Message+
      '. NEVER RETRY CreatePilot for this SuiteId; preserve PST and intent.')
}finally{
    foreach($obj in @($pilot,$folder,$target,$ns,$app)){
        if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)
        }
    }
}