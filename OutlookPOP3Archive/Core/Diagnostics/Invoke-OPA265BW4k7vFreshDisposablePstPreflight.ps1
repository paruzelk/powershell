#requires -Version 5.1
# BW4k7v: explicit NEW isolated PST creation OR independent post-restart verification.
# No MailItem.Move/Send/Delete. Existing POP3, IMAP, older test PSTs untouched.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Medium')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Plan','Create','Verify')][string]$Mode,
    [string]$SuiteId=([guid]::NewGuid().ToString('D')),
    [string]$ExpectedProfileName='Outlook',
    [switch]$ConfirmFreshFixtureCreation,
    [string]$ApprovalText='',
    [string]$ExpectedManifestSha256=''
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7v requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7vOutlookFixtureCapture265.ps1')
[void](Assert-OPA265BW4k7vSuiteId -SuiteId $SuiteId)
if($ExpectedProfileName -cne 'Outlook'){throw 'BW4k7v exact Outlook profile name required.'}
$layout=Get-OPA265BW4k7vLayout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
$expected=Get-OPA265BW4k7vFixtureExpectations -SuiteId $SuiteId
if($Mode -ceq 'Create' -and (-not $ConfirmFreshFixtureCreation -or
   $ApprovalText -cne ('CREATE NEW BW4K7V PST '+$SuiteId))){
    throw 'BW4k7v Create requires exact GUID-specific explicit approval.'
}
if($Mode -cne 'Create' -and ($ConfirmFreshFixtureCreation -or $ApprovalText)){
    throw 'BW4k7v Plan/Verify refuse creation approval.'
}
if($Mode -ceq 'Verify' -and $ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
    throw 'BW4k7v Verify requires original lowercase SHA256 of sealed manifest.'
}
if($Mode -cne 'Verify' -and $ExpectedManifestSha256){
    throw 'BW4k7v only Verify may specify a manifest hash.'
}
if($dry -or $Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v.DisposablePstPlan.1'
        Status=if($dry){'WhatIfNoPstOrOutlookWrites'}else{'NewIsolatedDisposablePstPlanOnly'}
        SuiteId=$SuiteId;SourcePst=$layout.SourcePst
        ManifestPath=$layout.ManifestPath
        FixtureRootFolderName=$layout.FixtureRootFolderName
        PlannedMailItems=@($expected.FixtureItems | ForEach-Object {
            [pscustomobject]@{
                Name=$_.Name;Role=$_.Role;SyntheticYear=$_.Year
                SourceFolderPath=$_.SourceFolderPath
                AttachmentCount=@($_.Attachments).Count
            }
        })
        PlannedMailItemCount=8;SyntheticYearOnlyNotActualMapiDate=$true
        GenuineSentMessagesNotCreated=$true
        OutlookAccessed=$false;PstCreated=$false
        ManifestWritten=$false;OutlookMoveExecuted=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
$stage='Preflight isolated filesystem and manifest'
$app=$null;$ns=$null;$store=$null;$root=$null
try{
    if($Mode -ceq 'Create'){
        [void](Assert-OPA265BW4k7vSafePath -Layout $layout -Mode Create)
        if(-not $PSCmdlet.ShouldProcess([string]$layout.SourcePst,
             'Create one new isolated Unicode PST and save eight fabricated unsent messages')){
            throw 'BW4k7v new-PST creation declined.'
        }
    }else{
        [void](Assert-OPA265BW4k7vSafePath -Layout $layout -Mode Review)
        $manifest=Read-OPA265BW4k7vManifest -Layout $layout -ExpectedManifestSha256 $ExpectedManifestSha256
    }
    $stage='Get existing Outlook process and original default store'
    $proc=Get-OPA265BW4k7vOutlookProcess
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){throw 'BW4k7v wrong Outlook profile.'}
    $originalDefaultStoreId=[string]$ns.DefaultStore.StoreID
    if($Mode -ceq 'Create'){
        $stage='New isolated suite directory then AddStoreEx Unicode'
        if(-not [IO.Directory]::Exists($layout.Root)){
            [void][IO.Directory]::CreateDirectory([string]$layout.Root)
        }
        [void][IO.Directory]::CreateDirectory([string]$layout.SuiteDirectory)
        [void][IO.Directory]::CreateDirectory([string]$layout.AttachmentScratchDirectory)
        if([IO.File]::Exists($layout.SourcePst) -or
           [IO.File]::Exists($layout.ManifestPath)){
            throw 'BW4k7v fresh fixture collision: refuse overwrite.'
        }
        # olStoreUnicode=3. AddStoreEx only for the new isolated GUID path.
        $ns.AddStoreEx([string]$layout.SourcePst,3)
    }
    $stage='Verify unique mounted isolated store (not default POP3)'
    $store=Get-OPA265BW4k7vExactMountedStore -Namespace $ns -Layout $layout
    if([string]$store.StoreID -ceq $originalDefaultStoreId){
        throw 'BW4k7v target unexpectedly Outlook default/production store.'
    }
    if($Mode -ceq 'Verify' -and (
       [int]$proc.Pid -eq [int]$manifest.CreatingOutlookProcessId -or
       [long]$proc.StartTicks -eq [long]$manifest.CreatingOutlookProcessStartUtcTicks)){
        throw 'BW4k7v Outlook must be closed and restarted after creation before Verify.'
    }
    $stage='Verify exact new fixture root under isolated PST'
    $pstRoot=$store.GetRootFolder()
    if($Mode -ceq 'Create'){
        $root=$pstRoot.Folders.Add([string]$layout.FixtureRootFolderName)
    }else{
        $root=$ns.GetFolderFromID([string]$manifest.RootFolderEntryId,[string]$store.StoreID)
    }
    if($null -eq $root -or
       [string]$root.Name -cne [string]$layout.FixtureRootFolderName -or
       [string]$root.StoreID -cne [string]$store.StoreID -or
       [string]$root.Parent.EntryID -cne [string]$pstRoot.EntryID){
        throw 'BW4k7v root folder not exact test PST child.'
    }
    if($Mode -ceq 'Verify' -and (
       [string]$root.EntryID -cne [string]$manifest.RootFolderEntryId -or
       [string]$store.StoreID -cne [string]$manifest.SourcePstStoreId)){
        throw 'BW4k7v original root or StoreID changed since Create.'
    }
    $stage='Save or reread exact eight test PST MailItems and independent witnesses'
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $folderCounters=@{}
    foreach($case in $expected.FixtureItems){
        $folder=Get-OPA265BW4k7vExactFolder -FixtureRoot $root -Case $case -CreateIfMissing:($Mode -ceq 'Create')
        if([string]$folder.StoreID -cne [string]$store.StoreID){
            throw 'BW4k7v fixture folder outside isolated PST.'
        }
        $old=$null
        if($Mode -ceq 'Create'){
            $id=New-OPA265BW4k7vSavedMail -Folder $folder -Case $case -Layout $layout
        }else{
            $matches=@($manifest.Items | Where-Object {$_.CaseId -ceq $case.CaseId})
            if($matches.Count -ne 1){throw 'BW4k7v manifest lacks exactly one expected item.'}
            $old=$matches[0]
            if([string]$old.FolderEntryId -cne [string]$folder.EntryID){
                throw 'BW4k7v original synthetic folder ID changed.'
            }
            $id=[string]$old.EntryId
        }
        $args=@{
            Case=$case;Folder=$folder;Store=$store;Layout=$layout
        }
        $mailOne=$ns.GetItemFromID($id,[string]$store.StoreID)
        $one=Get-OPA265BW4k7vMailWitness -Mail $mailOne @args
        $mailTwo=$ns.GetItemFromID($id,[string]$store.StoreID)
        $two=Get-OPA265BW4k7vMailWitness -Mail $mailTwo @args
        $jsonOne=ConvertTo-Json -InputObject $one -Depth 12 -Compress
        $jsonTwo=ConvertTo-Json -InputObject $two -Depth 12 -Compress
        if($jsonOne -cne $jsonTwo){
            throw 'BW4k7v two separate MAPI reads disagree before sealing/review.'
        }
        $wSha=Get-OPA265BW4k7vSha -Text $jsonTwo
        if($Mode -ceq 'Verify' -and $wSha -cne [string]$old.WitnessSha256){
            throw ('BW4k7v saved mail changed across restart: '+[string]$case.Name)
        }
        $key=[string]$case.SourceFolderPath
        if(-not $folderCounters.ContainsKey($key)){
            $folderCounters[$key]=[pscustomobject]@{Folder=$folder;Count=0}
        }
        $folderCounters[$key].Count=[int]$folderCounters[$key].Count+1
        $rows.Add([pscustomobject][ordered]@{
            CaseId=[string]$case.CaseId;Name=[string]$case.Name
            Role=[string]$case.Role;SourceFolderPath=$key
            SyntheticArchiveYear=[int]$case.Year
            Subject=[string]$two.Subject
            Class=43;MessageClass='IPM.Note'
            EntryId=$id;FolderEntryId=[string]$folder.EntryID
            StoreId=[string]$store.StoreID
            WitnessSha256=$wSha;Witness=$two
        })
    }
    $stage='Exact folder item count consistency and original default store stability'
    foreach($key in @($folderCounters.Keys)){
        $info=$folderCounters[$key]
        if([int]$info.Folder.Items.Count -ne [int]$info.Count){
            throw ('BW4k7v isolated PST folder count changed: '+$key)
        }
    }
    if([string]$ns.DefaultStore.StoreID -cne $originalDefaultStoreId){
        throw 'BW4k7v Outlook default store changed during test fixture operation.'
    }
    if(@($rows.ToArray()).Count -ne 8){throw 'BW4k7v eight fixture witnesses incomplete.'}
    if($Mode -ceq 'Create'){
        $stage='Seal immutable pre-Move evidence file (CreateNew, Flush(true))'
        $evidence=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v.ImmutableFreshDisposablePreMove.1'
            SuiteId=$SuiteId;OutlookProfile='Outlook'
            SourcePst=[string]$layout.SourcePst
            SourcePstStoreId=[string]$store.StoreID
            RootFolderEntryId=[string]$root.EntryID
            FixtureRootFolderName=[string]$layout.FixtureRootFolderName
            SyntheticSuiteManifestSha256=[string]$expected.SuiteManifestSha256
            CreatingOutlookProcessId=[int]$proc.Pid
            CreatingOutlookProcessStartUtcTicks=[long]$proc.StartTicks
            FixtureCount=8;Items=@($rows.ToArray())
            OnlySyntheticItemsCreated=$true
            GenuineSentItemsProven=$false;ActualMapiCalendarYearsProven=$false
            OutlookMoveExecuted=$false;OutlookSendExecuted=$false
            ProductionPstOrMailboxModified=$false
            DurableMoveIntentOrClaimCreated=$false
            WriterPermit=$false;ProductionReady=$false
        }
        $seal=Write-OPA265BW4k7vManifestOnce -Layout $layout -Manifest $evidence
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v.CreateFreshPst.1'
            Status='FreshIsolatedUnicodePstEightSavedSyntheticMailAndSealedPreMoveManifest'
            SuiteId=$SuiteId;SourcePst=[string]$layout.SourcePst
            ManifestPath=[string]$seal.ManifestPath
            ManifestSha256=[string]$seal.ManifestSha256
            CreatedFixtureCount=8;IndependentPreMoveReads=16
            RequiresOutlookRestartBeforeVerify=$true
            ActualMapiYearOrGenuineSentProven=$false
            TestPstCreated=$true;OutlookMoveOrSendExecuted=$false
            HistoricalEvidenceOrClaimModified=$false
            AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v.ReopenedPstReview.1'
        Status='ReopenedOutlookAllEightSyntheticMailWitnessesMatchNoMove'
        SuiteId=$SuiteId;SourcePst=[string]$layout.SourcePst
        ManifestSha256=$ExpectedManifestSha256
        NewOutlookProcessObserved=$true
        VerifiedFixtureCount=8;IndependentPostRestartReads=16
        AttachmentPayloadSha256Verified=$true
        OriginalFolderHierarchyAndRolesMatched=$true
        FullObservedUserStateWitnessesMatched=$true
        ArchiveYearIsSyntheticTagNotActualMapiDate=$true
        GenuineSentMailProven=$false
        HistoricalPstsOrClaimsModified=$false
        OutlookMoveOrSendExecuted=$false
        NewMoveJournalOrClaimCreated=$false
        RealPowerLossRecoveryProven=$false
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        NextAction='Stop and keep sealed PST; separate BW4k7w approval required for any Move'
    }
}catch{
    throw ('BW4k7v STOP at ['+$stage+']: '+[string]$_.Exception.Message+
      '. No retry of this SuiteId; no Move/Send/Delete. Preserve all old PST and Claim files.')
}finally{
    foreach($o in @($root,$store,$ns,$app)){
        if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)
        }
    }
}
