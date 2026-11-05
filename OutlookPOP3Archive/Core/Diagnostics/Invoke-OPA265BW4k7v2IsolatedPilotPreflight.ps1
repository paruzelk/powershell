#requires -Version 5.1
# BW4k7v2: dedicated one-store no-account Outlook profile, ONE pilot only.
# No default production store, no Move/Send/Delete or old fixture retry.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Prepare','Inspect','CreatePilot','VerifyPilot')][string]$Mode,
    [string]$SuiteId=([guid]::NewGuid().ToString('D')),
    [switch]$ConfirmIsolatedPilot,
    [string]$ApprovalText='',
    [string]$ExpectedManifestSha256=''
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7v2 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2IsolatedProfilePolicy265.ps1')
[void](Assert-OPA265BW4k7v2SuiteId -SuiteId $SuiteId)
$layout=Get-OPA265BW4k7v2Layout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
if($Mode -ceq 'CreatePilot'){
    if(-not $ConfirmIsolatedPilot -or
       $ApprovalText -cne ('CREATE BW4K7V2 PILOT '+$SuiteId)){
        throw 'BW4k7v2 CreatePilot requires exact per-GUID approval.'
    }
}elseif($ConfirmIsolatedPilot -or $ApprovalText){
    throw 'BW4k7v2 non-Create modes reject creation approval.'
}
if($Mode -ceq 'VerifyPilot'){
    if($ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4k7v2 VerifyPilot needs original SHA256.'
    }
}elseif($ExpectedManifestSha256){throw 'BW4k7v2 unexpected manifest SHA.'}
if($dry -or $Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2.ProfilePlan.1'
        Status=if($dry){'WhatIfNoOutlookAndNoWrites'}else{'PilotPlanNoOutlookAccess'}
        SuiteId=$SuiteId
        RequiredProfileName=[string]$layout.ProfileName
        RequiredPstPath=[string]$layout.PstPath
        SuiteDirectory=[string]$layout.SuiteDirectory
        TemplatePath=[string]$layout.TemplatePath
        PilotSubject=[string]$layout.PilotSubject
        AccountCountRequired=0
        StoreCountRequired=1
        SolePstMustBeDefault=$true
        MustUseDedicatedProfile=$true
        OriginalOutlookProfileProhibited=$true
        MessageCountMaximumThisStage=1
        NoActualMAPIYearProof=$true
        OutlookAccessed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
if($Mode -ceq 'Prepare'){
    [void](Assert-OPA265BW4k7v2Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
    if([IO.Directory]::Exists([string]$layout.SuiteDirectory)){
        throw 'BW4k7v2 suite directory already exists; never reuse GUID.'
    }
    if(-not $PSCmdlet.ShouldProcess([string]$layout.SuiteDirectory,
        'Create empty directory for manual standalone profile/PST')){
        throw 'BW4k7v2 Prepare declined.'
    }
    if(-not [IO.Directory]::Exists([string]$layout.Root)){
        [void][IO.Directory]::CreateDirectory([string]$layout.Root)
    }
    [void][IO.Directory]::CreateDirectory([string]$layout.SuiteDirectory)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2.PreparedDirectory.1'
        Status='EmptySuiteDirectoryCreatedNoOutlookOrPstWrites'
        SuiteId=$SuiteId
        RequiredProfileName=[string]$layout.ProfileName
        RequiredPstPath=[string]$layout.PstPath
        SuiteDirectory=[string]$layout.SuiteDirectory
        UserMustProvisionSeparateProfileAndOnlyDefaultPst=$true
        OutlookAccessed=$false;PstCreatedByThisScript=$false
        MailCreated=$false;WriterPermit=$false;ProductionReady=$false
    }
}
$stage='Validate dedicated no-account profile and exact single default PST'
$app=$null;$ns=$null;$store=$null;$pilotFolder=$null;$pilot=$null
try{
    [void](Assert-OPA265BW4k7v2Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
    if(-not [IO.File]::Exists([string]$layout.PstPath)){
        throw 'BW4k7v2 exact manually provisioned standalone PST missing.'
    }
    $processes=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($processes.Count -ne 1){throw 'BW4k7v2 requires exactly one OUTLOOK process.'}
    $process=$processes[0]
    $startTicks=[long]$process.StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    $profile=[string]$ns.CurrentProfileName
    $accounts=[int]$ns.Accounts.Count
    $stores=[int]$ns.Stores.Count
    if($stores -ne 1){
        throw ('BW4k7v2 refuses '+$stores+' stores. Exactly one required.')
    }
    $store=$ns.Stores.Item(1)
    $onlyId=[string]$store.StoreID
    $defaultId=[string]$ns.DefaultStore.StoreID
    $onlyPath=[string]$store.FilePath
    $pstBytes=[long](Get-Item -LiteralPath $layout.PstPath -ErrorAction Stop).Length
    $checkArgs=@{
        Layout=$layout;ActualProfileName=$profile;AccountsCount=$accounts
        StoresCount=$stores;DefaultStoreId=$defaultId;OnlyStoreId=$onlyId
        OnlyStoreFilePath=$onlyPath;PstSizeBytes=$pstBytes
        RequirePristine=($Mode -ceq 'CreatePilot')
    }
    $check=Test-OPA265BW4k7v2StoreIsolation @checkArgs
    if(-not $check.Isolated){throw ('BW4k7v2 isolated profile rejected: '+($check.ReasonCodes -join ','))}
    if($Mode -ceq 'Inspect'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2.IsolatedProfileInspection.1'
            Status='DedicatedProfileExactSingleDefaultPstAndZeroAccountsConfirmed'
            SuiteId=$SuiteId;ProfileName=$profile;PstPath=[string]$layout.PstPath
            PstLengthBytes=$pstBytes;AccountsCount=$accounts;StoresCount=$stores
            Isolation=$check;PilotCreatedByThisReview=$false
            OldOutlookProfileContacted=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    $stage='Locate exact test root and isolated pilot folder'
    $pstRoot=$store.GetRootFolder()
    if($Mode -ceq 'CreatePilot'){
        if([IO.File]::Exists([string]$layout.TemplatePath) -or
           [IO.File]::Exists([string]$layout.ManifestPath)){
            throw 'BW4k7v2 template/manifest already exists; never retry.'
        }
        for($i=1;$i -le [int]$pstRoot.Folders.Count;$i++){
            if([string]$pstRoot.Folders.Item($i).Name -ceq [string]$layout.RootFolderName){
                throw 'BW4k7v2 pilot root already exists; preserve old attempt.'
            }
        }
        if(-not $PSCmdlet.ShouldProcess([string]$layout.PstPath,
            'Create exactly ONE template-based pilot MailItem in test-only default PST')){
            throw 'BW4k7v2 operator declined pilot creation.'
        }
        $fixtureRoot=$pstRoot.Folders.Add([string]$layout.RootFolderName)
        $pilotFolder=$fixtureRoot.Folders.Add([string]$layout.PilotFolderName)
        if([string]$pilotFolder.StoreID -cne $onlyId){
            throw 'BW4k7v2 pilot folder outside isolated store.'
        }
        $stage='Save OFT template only (NOT MailItem.Save)'
        # olMailItem=0, olTemplate=2: current profile cannot contain real mail.
        $templateMail=$app.CreateItem(0)
        $templateMail.Subject='OPA265-BW4k7v2-TEMPLATE-'+$SuiteId
        $templateMail.Body='Synthetic pilot template in isolated profile'
        $templateMail.SaveAs([string]$layout.TemplatePath,2)
        if(-not [IO.File]::Exists([string]$layout.TemplatePath)){
            throw 'BW4k7v2 template missing after SaveAs.'
        }
        $stage='CreateItemFromTemplate with explicit InFolder for exactly one item'
        $pilot=$app.CreateItemFromTemplate([string]$layout.TemplatePath,$pilotFolder)
        $pilot.Subject=[string]$layout.PilotSubject
        $pilot.Body='BW4k7v2 isolated pilot '+$SuiteId
        $pilot.To='synthetic-recipient@example.invalid'
        $pilot.UnRead=$false
        $year=$pilot.UserProperties.Add('OPA265BW4k7v2Year',1,$true)
        $year.Value='2020'
        $stage='Save first pilot then inspect exact actual parent and StoreID'
        $pilot.Save()
        if([int]$pilot.Class -ne 43 -or
           [string]$pilot.Subject -cne [string]$layout.PilotSubject -or
           [string]$pilot.Parent.EntryID -cne [string]$pilotFolder.EntryID -or
           [string]$pilot.Parent.StoreID -cne $onlyId){
            throw 'BW4k7v2 pilot misrouted; STOP before another message.'
        }
        if([int]$pilotFolder.Items.Count -ne 1){
            throw 'BW4k7v2 target pilot folder does not contain exactly one item.'
        }
        $stage='Independent two GetItemFromID reads and immutable original manifest'
        $id=[string]$pilot.EntryID
        $first=$ns.GetItemFromID($id,$onlyId)
        $second=$ns.GetItemFromID($id,$onlyId)
        foreach($item in @($first,$second)){
            if([int]$item.Class -ne 43 -or
               [string]$item.Parent.EntryID -cne [string]$pilotFolder.EntryID -or
               [string]$item.Parent.StoreID -cne $onlyId -or
               [string]$item.Subject -cne [string]$layout.PilotSubject){
                throw 'BW4k7v2 by-ID reopened pilot differs from target.'
            }
        }
        $firstText=([string]$first.Subject)+'|'+([string]$first.Body)+'|'+([string]$first.To)+'|'+([string]$first.UnRead)
        $secondText=([string]$second.Subject)+'|'+([string]$second.Body)+'|'+([string]$second.To)+'|'+([string]$second.UnRead)
        $w1=Get-OPA265BW4k7v2Sha256 -Text $firstText
        $w2=Get-OPA265BW4k7v2Sha256 -Text $secondText
        if($w1 -cne $w2){throw 'BW4k7v2 double-read pilot semantic mismatch.'}
        $record=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2.PilotPreMoveManifest.1'
            SuiteId=$SuiteId;ProfileName=[string]$layout.ProfileName
            PstPath=[string]$layout.PstPath;StoreId=$onlyId
            RootId=[string]$fixtureRoot.EntryID
            FolderId=[string]$pilotFolder.EntryID;EntryId=$id
            Subject=[string]$layout.PilotSubject
            WitnessSha256=$w1;SyntheticArchiveYear=2020
            CreatingProcessId=[int]$process.Id
            CreatingProcessStartUtcTicks=$startTicks
            DedicatedSinglePstNoAccounts=$true
            RealSentOrReceivedTimestampProven=$false
            MoveExecuted=$false;SendExecuted=$false
            OldProfileTouched=$false;WriterPermit=$false;ProductionReady=$false
        }
        $seal=Write-OPA265BW4k7v2ManifestOnce -Layout $layout -Manifest $record
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2.CreatePilotResult.1'
            Status='OneTemplateBasedPilotSavedInExactDedicatedPstAndSealed'
            SuiteId=$SuiteId;ProfileName=[string]$layout.ProfileName
            PstPath=[string]$layout.PstPath
            ActualParentFolderId=[string]$pilotFolder.EntryID
            ActualStoreId=$onlyId;ExactTargetFolderVerified=$true
            ManifestSha256=$seal;CreatedMailItemCount=1
            MustRestartOutlookBeforeVerify=$true
            NoRealMAPIYearOrSentMessageProven=$true
            NoOldOutlookProfileContact=$true
            MoveExecuted=$false;SendExecuted=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    $stage='Verify original manifest only after new Outlook process'
    $manifest=Read-OPA265BW4k7v2Manifest -Layout $layout -ExpectedManifestSha256 $ExpectedManifestSha256
    if([string]$manifest.StoreId -cne $onlyId){
        throw 'BW4k7v2 StoreID changed after restart.'
    }
    if([int]$manifest.CreatingProcessId -eq [int]$process.Id -or
       [long]$manifest.CreatingProcessStartUtcTicks -eq $startTicks){
        throw 'BW4k7v2 VerifyPilot requires Outlook full restart.'
    }
    $pilotFolder=$ns.GetFolderFromID([string]$manifest.FolderId,$onlyId)
    if([string]$pilotFolder.Name -cne [string]$layout.PilotFolderName -or
       [string]$pilotFolder.StoreID -cne $onlyId -or
       [int]$pilotFolder.Items.Count -ne 1){
        throw 'BW4k7v2 original test folder ID, store or count changed.'
    }
    $pilot=$ns.GetItemFromID([string]$manifest.EntryId,$onlyId)
    if([int]$pilot.Class -ne 43 -or
       [string]$pilot.Parent.EntryID -cne [string]$manifest.FolderId -or
       [string]$pilot.Parent.StoreID -cne $onlyId -or
       [string]$pilot.Subject -cne [string]$layout.PilotSubject){
        throw 'BW4k7v2 post-restart pilot missing or misrouted.'
    }
    $txt=([string]$pilot.Subject)+'|'+([string]$pilot.Body)+'|'+([string]$pilot.To)+'|'+([string]$pilot.UnRead)
    $witness=Get-OPA265BW4k7v2Sha256 -Text $txt
    if($witness -cne [string]$manifest.WitnessSha256){
        throw 'BW4k7v2 post-restart original content witness changed.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2.VerifyPilotResult.1'
        Status='OnePilotReopenedAfterOutlookRestartExactFolderAndSemanticsMatched'
        SuiteId=$SuiteId;OriginalManifestSha256=$ExpectedManifestSha256
        NewOutlookProcessVerified=$true
        ExactIsolatedFolderAndStoreVerified=$true
        OriginalPilotSemanticsReverified=$true
        PilotMailItemCount=1;AllEightMailItemsTested=$false
        NoOriginalOutlookProfileContact=$true
        NoMoveOrSendExecuted=$true
        AutomaticRetryAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}catch{
    $hex='HResultUnavailable'
    try{
        $num=[int64]$_.Exception.HResult
        $hex=('0x{0:X8}' -f ([uint32]($num -band 4294967295L)))
    }catch{}
    throw ('BW4k7v2 STOP at ['+$stage+'] HRESULT='+$hex+': '+
        [string]$_.Exception.Message+
        '. NEVER retry CreatePilot for this SuiteId; preserve fixture.')
}finally{
    foreach($obj in @($pilot,$pilotFolder,$store,$ns,$app)){
        if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)
        }
    }
}
