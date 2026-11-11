#requires -Version 5.1
# BW4k7v2a7 ONE synthetic MailItem, ONE opt-in cross-store Move in existing test profile.
# This is a diagnostic only. Default Drafts may be an IMAP/server-synced mailbox.
# Historical BW4k7v2a1 SuiteId and old mailbox items are never selected or changed.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Plan','Prepare','Inspect','CreatePilot','ReviewPilot','MovePilot','Reconcile')]
    [string]$Mode,
    [string]$SuiteId=([guid]::NewGuid().ToString('D')),
    [string]$ExpectedManifestSha256='',
    [string]$ExpectedClaimSha256='',
    [switch]$AllowDefaultDraftsSyntheticWrite,
    [switch]$ConfirmOneShotMove,
    [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7v2a7 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a7PostSaveBaselinePolicy265.ps1')
$layout=Get-OPA265BW4k7v2a7Layout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
[void](Assert-OPA265BW4k7v2a7Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
if(-not $dry){
    if($Mode -ceq 'CreatePilot'){
        if(-not $AllowDefaultDraftsSyntheticWrite -or
           $ApprovalText -cne ('CREATE BW4K7V2A7 DRAFT '+$SuiteId)){
            throw 'CreatePilot requires per-SuiteId approval of writing one synthetic message into DEFAULT DRAFTS (possibly IMAP/server-synced).'
        }
        if($ConfirmOneShotMove){throw 'CreatePilot cannot receive Move approval.'}
    }elseif($Mode -ceq 'MovePilot'){
        if(-not $ConfirmOneShotMove -or
           $ApprovalText -cne ('MOVE BW4K7V2A7 ONCE '+$SuiteId)){
            throw 'MovePilot requires separate exact single-attempt per-SuiteId approval.'
        }
        if($AllowDefaultDraftsSyntheticWrite){throw 'MovePilot cannot receive creation approval.'}
    }elseif($ApprovalText -or $ConfirmOneShotMove -or $AllowDefaultDraftsSyntheticWrite){
        throw 'Read-only/Prepare modes must not receive write approval.'
    }
    if($Mode -cin @('ReviewPilot','MovePilot','Reconcile')){
        if($ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'BW4k7v2a7 requires original lowercase ManifestSha256.'
        }
    }elseif($ExpectedManifestSha256){throw 'Unexpected ManifestSha256.'}
    if($Mode -ceq 'Reconcile'){
        if($ExpectedClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'BW4k7v2a7 Reconcile requires original lowercase ClaimSha256.'
        }
    }elseif($ExpectedClaimSha256){throw 'Unexpected Move Claim SHA256.'}
}
if($dry -or $Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a7.Plan.1'
        Status=if($dry){'WhatIfNoOutlookContactNoFileWrites'}else{'NoOutlookContactNoFileWrites'}
        SuiteId=$SuiteId;ProfileName='Outlook';Pop3Account='info@stios.ru'
        TestPstPath=[string]$layout.PstPath;SuiteDirectory=[string]$layout.SuiteDirectory
        SyntheticDraftSubject=[string]$layout.Subject
        SourceStore='Existing Outlook DEFAULT Drafts (NOT POP3 source PST)'
        Risk='Default Drafts may be IMAP/server-synced; one synthetic item created only on explicit approval'
        Target='ONE fresh disposable Unicode PST, new folder'
        PilotItemsMaximum=1;MoveAttemptsMaximum=1
        PreviousFailedBW4k7v2a1FixturePreserved=$true
        NoRealOutlookMoveInCI=$true
        WriterPermit=$false;ProductionReady=$false
    }
}
if($Mode -ceq 'Prepare'){
    if([IO.Directory]::Exists([string]$layout.SuiteDirectory)){
        throw 'BW4k7v2a7 suite already exists; cannot reuse or reset.'
    }
    if(-not $PSCmdlet.ShouldProcess([string]$layout.SuiteDirectory,
            'Create new diagnostic suite directory only, no Outlook contact')){
        throw 'BW4k7v2a7 Prepare declined.'
    }
    if(-not [IO.Directory]::Exists([string]$layout.Root)){
        [void][IO.Directory]::CreateDirectory([string]$layout.Root)
    }
    [void][IO.Directory]::CreateDirectory([string]$layout.SuiteDirectory)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a7.Prepared.1'
        Status='FreshSuiteDirectoryCreatedNoOutlookNoPstWrites'
        SuiteId=$SuiteId;PstPath=[string]$layout.PstPath
        WriterPermit=$false;ProductionReady=$false
    }
}
if(-not [IO.Directory]::Exists([string]$layout.SuiteDirectory)){
    throw 'BW4k7v2a7 must run Prepare first.'
}

function Get-OPA265BW4k7v2a7Flags {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Item)
    try{
        $raw=$Item.PropertyAccessor.GetProperty(
            'http://schemas.microsoft.com/mapi/proptag/0x0E070003')
        return [pscustomobject]@{Available=$true;RawValue=[long]$raw;Error=''}
    }catch{
        return [pscustomobject]@{Available=$false;RawValue=$null;Error=[string]$_.Exception.Message}
    }
}
function Get-OPA265BW4k7v2a7MailWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Item)
    $s=[pscustomobject]@{
        Subject=[string]$Item.Subject;Body=[string]$Item.Body
        To=[string]$Item.To;Unread=[bool]$Item.UnRead;Class=[int]$Item.Class
    }
    $w=Get-OPA265BW4k7v2a7SemanticWitness -Snapshot $s
    return [pscustomobject][ordered]@{
        SemanticSha256=[string]$w.SemanticSha256
        Subject=[string]$w.Subject
        Body=[string]$w.Body;To=[string]$w.To
        Unread=[bool]$w.Unread;Class=[int]$w.Class
        Size=[long]$Item.Size
        Flags=(Get-OPA265BW4k7v2a7Flags -Item $Item)
    }
}
function Get-OPA265BW4k7v2a7SubjectItems {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Folder,
          [Parameter(Mandatory=$true)][string]$Subject)
    $items=$Folder.Items.Restrict(("[Subject] = '"+$Subject+"'"))
    $count=[int]$items.Count
    if($count -lt 0 -or $count -gt 2){
        throw 'BW4k7v2a7 unexpected exact pilot subject count (>2); STOP.'
    }
    $matches=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le $count;$i++){
        $item=$items.Item($i)
        if([string]$item.Subject -cne $Subject){
            throw 'BW4k7v2a7 Outlook Restrict returned non-exact Subject.'
        }
        $matches.Add($item)
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a7.ExplicitSubjectQuery.1'
        Count=[int]$count
        Matches=@($matches.ToArray())
    }
}
function Assert-OPA265BW4k7v2a7SourceAndTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Ns,
          [Parameter(Mandatory=$true)][object]$Manifest,
          [Parameter(Mandatory=$true)][object]$Layout,
          [switch]$PreMove)
    if([string]$Manifest.Schema -cne '2.6.5-BW4k7v2a7.PreMoveManifest.1' -or
       [string]$Manifest.SuiteId -cne [string]$Layout.SuiteId -or
       [string]$Manifest.PstPath -cne [string]$Layout.PstPath -or
       [string]$Manifest.Subject -cne [string]$Layout.Subject -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.SourceEntryId) -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.SourceStoreId) -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.SourceFolderId) -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.TargetStoreId) -or
       [string]::IsNullOrWhiteSpace([string]$Manifest.TargetFolderId) -or
       [string]$Manifest.SemanticSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Manifest.IntentSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [int]$Manifest.SourceItemCount -ne 1 -or
       [bool]$Manifest.MoveAttempted -or
       [bool]$Manifest.ProductionReady -or [bool]$Manifest.WriterPermit){
        throw 'BW4k7v2a7 original pre-Move manifest invalid or unsafe.'
    }
    $drafts=$Ns.DefaultStore.GetDefaultFolder(16)
    if([string]$Ns.DefaultStore.StoreID -cne [string]$Manifest.SourceStoreId -or
       [string]$drafts.StoreID -cne [string]$Manifest.SourceStoreId -or
       [string]$drafts.EntryID -cne [string]$Manifest.SourceFolderId){
        throw 'BW4k7v2a7 source default Drafts store/folder changed.'
    }
    $target=$null;$matches=0
    for($i=1;$i -le [int]$Ns.Stores.Count;$i++){
        $store=$Ns.Stores.Item($i)
        if(-not [string]::IsNullOrWhiteSpace([string]$store.FilePath) -and
           [string]::Equals([IO.Path]::GetFullPath([string]$store.FilePath),
             [string]$Layout.PstPath,[StringComparison]::OrdinalIgnoreCase)){
            $target=$store
            $matches++
        }
    }
    if($matches -ne 1 -or
       [string]$target.StoreID -cne [string]$Manifest.TargetStoreId -or
       [string]$target.StoreID -ceq [string]$Manifest.SourceStoreId){
        throw 'BW4k7v2a7 target PST StoreID/path absent, duplicated, or changed.'
    }
    $folder=$Ns.GetFolderFromID([string]$Manifest.TargetFolderId,
        [string]$Manifest.TargetStoreId)
    if([string]$folder.StoreID -cne [string]$Manifest.TargetStoreId -or
       [string]$folder.Name -cne [string]$Layout.TargetFolderName){
        throw 'BW4k7v2a7 target folder changed.'
    }
    if($PreMove){
        if([string]$Manifest.SourceStoreId -ceq [string]$Manifest.Pop3DeliveryStoreId){
            throw 'BW4k7v2a7 POP3 original delivery source forbidden.'
        }
    }
    return [pscustomobject]@{Drafts=$drafts;TargetStore=$target;TargetFolder=$folder}
}

$stage='Read exact Outlook test profile and scope'
$app=$null;$ns=$null;$source=$null;$destination=$null
try{
    $processes=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($processes.Count -ne 1){throw 'BW4k7v2a7 exactly one OUTLOOK.EXE process required.'}
    $proc=$processes[0]
    $ticks=[long]$proc.StartTime.ToUniversalTime().Ticks
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    $profile=[string]$ns.CurrentProfileName
    $storeRows=New-Object 'System.Collections.Generic.List[object]'
    $accounts=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $s=$ns.Stores.Item($i)
        $storeRows.Add([pscustomobject]@{StoreId=[string]$s.StoreID;FilePath=[string]$s.FilePath})
    }
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $a=$ns.Accounts.Item($i)
        $delivery=''
        if($null -ne $a.DeliveryStore){$delivery=[string]$a.DeliveryStore.StoreID}
        $accounts.Add([pscustomobject]@{
            SmtpAddress=[string]$a.SmtpAddress
            AccountType=[int]$a.AccountType;DeliveryStoreId=$delivery
        })
    }
    $isTargetAttached=($Mode -cin @('ReviewPilot','MovePilot','Reconcile'))
    $scopeParams=@{
        Layout=$layout;ActualProfileName=$profile
        Accounts=@($accounts.ToArray());Stores=@($storeRows.ToArray())
        DefaultStoreId=[string]$ns.DefaultStore.StoreID
        TargetAttached=$isTargetAttached
    }
    $scope=Test-OPA265BW4k7v2a7StoreScope @scopeParams
    if(-not $scope.Approved){
        throw ('BW4k7v2a7 wrong POP3/default source/target store scope: '+($scope.ReasonCodes -join ','))
    }
    $drafts=$ns.DefaultStore.GetDefaultFolder(16)
    $srcStoreId=[string]$ns.DefaultStore.StoreID
    $draftsId=[string]$drafts.EntryID
    if([string]$drafts.StoreID -cne $srcStoreId -or
       [string]::IsNullOrWhiteSpace($draftsId)){
        throw 'BW4k7v2a7 explicit default Drafts folder/store identity invalid.'
    }
    $draftsFolderPath=[string]$drafts.FolderPath
    if($Mode -ceq 'Inspect'){
        if([IO.File]::Exists([string]$layout.PstPath) -or
           [IO.File]::Exists([string]$layout.IntentPath) -or
           [IO.File]::Exists([string]$layout.ManifestPath) -or
           [IO.File]::Exists([string]$layout.MoveClaimPath)){
            throw 'BW4k7v2a7 fresh new test PST or intent already exists.'
        }
        $existing=Get-OPA265BW4k7v2a7SubjectItems -Folder $drafts -Subject $layout.Subject
        if($existing.Count -ne 0){
            throw 'BW4k7v2a7 synthetic subject already exists in default Drafts.'
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a7.Inspect.1'
            Status='ExistingProfilePop3AndDefaultDraftsVerifiedFreshTestPstAbsent'
            SuiteId=$SuiteId;ProfileName=$profile
            DraftsFolderPath=$draftsFolderPath;DraftsStoreIsPop3Delivery=$false
            DefaultDraftsCanBeServerSynced=$true
            ExistingPstCount=$storeRows.Count;NewPstPath=[string]$layout.PstPath
            ExistingMailBodyRead=$false;NoWriterExecuted=$true
            WriterPermit=$false;ProductionReady=$false
        }
    }
    if($Mode -ceq 'CreatePilot'){
        if([IO.File]::Exists([string]$layout.PstPath) -or
           [IO.File]::Exists([string]$layout.IntentPath) -or
           [IO.File]::Exists([string]$layout.ManifestPath) -or
           [IO.File]::Exists([string]$layout.MoveClaimPath)){
            throw 'BW4k7v2a7 existing evidence or PST; never retry CreatePilot.'
        }
        if((Get-OPA265BW4k7v2a7SubjectItems -Folder $drafts -Subject $layout.Subject).Count -ne 0){
            throw 'BW4k7v2a7 new synthetic subject already used.'
        }
        if(-not $PSCmdlet.ShouldProcess(
            ($draftsFolderPath+' AND '+[string]$layout.PstPath),
            'Write one NEW synthetic Draft (may sync to IMAP) and attach one disposable Unicode PST')){
            throw 'BW4k7v2a7 CreatePilot not approved.'
        }
        $stage='Durable create-intent BEFORE any Outlook COM writer'
        $intent=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a7.CreationIntent.1'
            SuiteId=$SuiteId;PstPath=[string]$layout.PstPath
            DefaultDraftsStoreId=$srcStoreId;DefaultDraftsFolderId=$draftsId
            Pop3DeliveryStoreId=[string]$scope.Pop3DeliveryStoreId
            Subject=[string]$layout.Subject
            OutlookProcessId=[int]$proc.Id;OutlookProcessStartUtcTicks=$ticks
            AtMostOneDraft=$true;AtMostOneMove=$true
            SavedBodyBaselinePolicy='BW4k7v2a7-ONLY-NEW-DISPOSABLE'
            NoAutomaticRetry=$true;ProductionReady=$false
        }
        $intentSha=Write-OPA265BW4k7v2a1JsonOnce -Path $layout.IntentPath -Value $intent
        $stage='Attach exact new Unicode disposable PST via AddStoreEx'
        $ns.AddStoreEx([string]$layout.PstPath,2)
        $target=$null;$matches=0
        for($i=1;$i -le [int]$ns.Stores.Count;$i++){
            $s=$ns.Stores.Item($i)
            if(-not [string]::IsNullOrWhiteSpace([string]$s.FilePath) -and
               [string]::Equals([IO.Path]::GetFullPath([string]$s.FilePath),
                   [string]$layout.PstPath,[StringComparison]::OrdinalIgnoreCase)){
                $target=$s;$matches++
            }
        }
        if($matches -ne 1 -or [string]$target.StoreID -ceq $srcStoreId -or
           [string]$target.StoreID -ceq [string]$scope.Pop3DeliveryStoreId){
            throw 'BW4k7v2a7 new PST not bound to unique different target StoreID.'
        }
        $root=$target.GetRootFolder()
        if([int]$root.Items.Count -ne 0 -or [int]$root.Folders.Count -gt 128){
            throw 'BW4k7v2a7 new target PST is not visibly empty/bounded.'
        }
        for($j=1;$j -le [int]$root.Folders.Count;$j++){
            if([string]$root.Folders.Item($j).Name -ceq [string]$layout.TargetFolderName){
                throw 'BW4k7v2a7 target fixture folder already exists.'
            }
        }
        $destination=$root.Folders.Add([string]$layout.TargetFolderName)
        if([string]$destination.StoreID -cne [string]$target.StoreID){
            throw 'BW4k7v2a7 target folder not in fresh PST.'
        }
        $stage='Create ONE synthetic unsent MailItem in explicit default Drafts'
        $source=$drafts.Items.Add('IPM.Note')
        $source.Subject=[string]$layout.Subject
        $source.Body=[string]$layout.Body
        $source.To=[string]$layout.Recipient
        $source.UnRead=$false
        $source.Save()
        $stage='Verify pinned default Drafts identity after exactly one Save'
        $sourceId=[string]$source.EntryID
        if([string]::IsNullOrWhiteSpace($sourceId) -or
           [string]$source.Parent.StoreID -cne $srcStoreId -or
           [string]$source.Parent.EntryID -cne $draftsId){
            throw 'BW4k7v2a7 new synthetic Draft saved outside verified default Drafts. No retry.'
        }
        # No immediate post-Save Items.Restrict cardinality: it can lag.
        $stage='Verify new synthetic via exact saved EntryID, no index assumption'
        $read=$ns.GetItemFromID($sourceId,$srcStoreId)
        if([string]$read.EntryID -cne $sourceId -or
           [string]$read.Parent.EntryID -cne $draftsId -or
           [string]$read.Parent.StoreID -cne $srcStoreId -or
           [string]$read.Subject -cne [string]$layout.Subject -or
           [int]$read.Class -ne 43){
            throw 'BW4k7v2a7 synthetic by-ID source identity changed after Save.'
        }
        $witness=Get-OPA265BW4k7v2a7MailWitness -Item $read
        if([string]$witness.To -cne [string]$layout.Recipient -or
           [bool]$witness.Unread){
            throw 'BW4k7v2a7 synthetic To or Unread changed during Save.'
        }
        $baseline=Get-OPA265BW4k7v2a7PostSaveBodyBaseline -ExpectedSyntheticBody ([string]$layout.Body) -ActuallySavedBody ([string]$witness.Body)
        if(-not [bool]$baseline.ApprovedForNewDisposableSyntheticFixtureBaseline){
            throw 'BW4k7v2a7 unexpected post-Save synthetic Body difference blocked.'
        }
        $second=$ns.GetItemFromID($sourceId,$srcStoreId)
        if([string]$second.EntryID -cne $sourceId -or
           [string]$second.Parent.StoreID -cne $srcStoreId -or
           [string]$second.Parent.EntryID -cne $draftsId -or
           [string]$second.Subject -cne [string]$layout.Subject){
            throw 'BW4k7v2a7 independent source by-ID identity changed.'
        }
        $secondWitness=Get-OPA265BW4k7v2a7MailWitness -Item $second
        if([string]$secondWitness.SemanticSha256 -cne [string]$witness.SemanticSha256){
            throw 'BW4k7v2a7 actual saved synthetic witness unstable before Move.'
        }
        if([int]$destination.Items.Count -ne 0){
            throw 'BW4k7v2a7 fresh test PST destination unexpectedly nonempty.'
        }
        $stage='Seal immutable original source pre-Move manifest'
        $manifest=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a7.PreMoveManifest.1'
            SuiteId=$SuiteId;ProfileName='Outlook'
            PstPath=[string]$layout.PstPath
            SourceStoreId=$srcStoreId;SourceFolderId=$draftsId;SourceEntryId=$sourceId
            Pop3DeliveryStoreId=[string]$scope.Pop3DeliveryStoreId
            TargetStoreId=[string]$target.StoreID;TargetFolderId=[string]$destination.EntryID
            Subject=[string]$layout.Subject;SemanticSha256=[string]$witness.SemanticSha256
            SyntheticExpectedTemplateBodySha256=[string]$baseline.OriginalExpectedSha256
            SyntheticSavedActualBodySha256=[string]$baseline.ActualSavedSha256
            SyntheticTemplateBodyUtf8Bytes=[int]$baseline.OriginalExpectedUtf8Bytes
            SyntheticActualSavedBodyUtf8Bytes=[int]$baseline.ActualSavedUtf8Bytes
            SyntheticPostSaveBodyClassification=[string]$baseline.Status
            SyntheticBaselinePolicy='BW4k7v2a7-ONLY-NEW-DISPOSABLE'
            SyntheticPostSaveSubjectIndexNotUsedForManifest=$true
            SyntheticSavedBodyPinnedAsExactPreMoveWitness=$true
            ProductionContentNormalizationWaiverGranted=$false
            SourceSizeBytes=[long]$witness.Size
            SourceRawMapiFlagsAvailable=[bool]$witness.Flags.Available
            SourceRawMapiFlags=if($witness.Flags.Available){[long]$witness.Flags.RawValue}else{$null}
            IntentSha256=$intentSha
            SourceItemCount=1;TargetItemCount=0
            CreatingProcessId=[int]$proc.Id;CreatingProcessStartUtcTicks=$ticks
            SourceDraftsMayBeServerSynced=$true
            MoveAttempted=$false;WriterPermit=$false;ProductionReady=$false
        }
        $sha=Write-OPA265BW4k7v2a1JsonOnce -Path $layout.ManifestPath -Value $manifest
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a7.CreatedPilot.1'
            Status='NewSyntheticDraftByIdSavedBodySealedRequiresIndependentReview'
            SuiteId=$SuiteId;DefaultDraftsFolder=$draftsFolderPath
            TargetPstPath=[string]$layout.PstPath
            ManifestSha256=$sha;IntentSha256=$intentSha
            SourceStoreId=$srcStoreId;TargetStoreId=[string]$target.StoreID
            SyntheticSemanticSha256=[string]$witness.SemanticSha256
            PostSaveBodyClassification=[string]$baseline.Status
            SyntheticSavedActualBodySha256=[string]$baseline.ActualSavedSha256
            SyntheticTemplateBodyUtf8Bytes=[int]$baseline.OriginalExpectedUtf8Bytes
            SyntheticActualSavedBodyUtf8Bytes=[int]$baseline.ActualSavedUtf8Bytes
            SourceOneDestinationZeroNotYetIndependentlyVerified=$true
            MailItemMoveCalled=$false;ConfirmSeparateMoveRequired=$true
            AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
        }
    }
    $stage='Load and validate immutable pre-Move manifest and intent'
    $manifest=Read-OPA265BW4k7v2a1SealedJson -Path $layout.ManifestPath -ExpectedSha256 $ExpectedManifestSha256
    $bindings=Assert-OPA265BW4k7v2a7SourceAndTarget -Ns $ns -Manifest $manifest -Layout $layout -PreMove
    $oldIntent=Read-OPA265BW4k7v2a1SealedJson -Path $layout.IntentPath -ExpectedSha256 ([string]$manifest.IntentSha256)
    if([string]$oldIntent.Schema -cne '2.6.5-BW4k7v2a7.CreationIntent.1' -or
       [string]$oldIntent.SuiteId -cne $SuiteId -or
       [string]$oldIntent.PstPath -cne [string]$layout.PstPath -or
       [string]$oldIntent.DefaultDraftsStoreId -cne [string]$manifest.SourceStoreId -or
       [string]$oldIntent.DefaultDraftsFolderId -cne [string]$manifest.SourceFolderId -or
       [string]$oldIntent.Pop3DeliveryStoreId -cne [string]$scope.Pop3DeliveryStoreId){
        throw 'BW4k7v2a7 sealed creation intent mismatch.'
    }
    $sourceMatches=Get-OPA265BW4k7v2a7SubjectItems -Folder $bindings.Drafts -Subject $layout.Subject
    $targetMatches=Get-OPA265BW4k7v2a7SubjectItems -Folder $bindings.TargetFolder -Subject $layout.Subject
    if($Mode -cin @('ReviewPilot','MovePilot')){
        if([IO.File]::Exists([string]$layout.MoveClaimPath)){
            throw 'BW4k7v2a7 Move attempt already claimed. No pre-Move review or retry; use Reconcile.'
        }
        if($sourceMatches.Count -ne 1 -or $targetMatches.Count -ne 0){
            throw 'BW4k7v2a7 pre-Move exact source=1 target=0 not established.'
        }
        $read=$ns.GetItemFromID([string]$manifest.SourceEntryId,[string]$manifest.SourceStoreId)
        if([string]$read.Parent.StoreID -cne [string]$manifest.SourceStoreId -or
           [string]$read.Parent.EntryID -cne [string]$manifest.SourceFolderId -or
           [string]$read.EntryID -cne [string]$manifest.SourceEntryId){
            throw 'BW4k7v2a7 exact original SourceEntryId no longer maps to Drafts.'
        }
        $witness=Get-OPA265BW4k7v2a7MailWitness -Item $read
        if([string]$witness.SemanticSha256 -cne [string]$manifest.SemanticSha256){
            throw 'BW4k7v2a7 original pre-Move semantic witness changed.'
        }
        if($Mode -ceq 'ReviewPilot'){
            return [pscustomobject][ordered]@{
                Schema='2.6.5-BW4k7v2a7.PreMoveReadOnly.1'
                Status='ExactSyntheticDraftOneTargetZeroOriginalManifestVerifiedNoMove'
                SuiteId=$SuiteId;ManifestSha256=$ExpectedManifestSha256
                DraftsFolderPath=[string]$bindings.Drafts.FolderPath
                TargetPstPath=[string]$layout.PstPath
                SourceMatches=1;DestinationMatches=0
                SourceContentMatch=$true
                OriginalRawMapiFlags=[object]$manifest.SourceRawMapiFlags
                CurrentRawMapiFlags=[object]$witness.Flags.RawValue
                NoMailMoveOrWrite=$true
                WriterPermit=$false;ProductionReady=$false
            }
        }
        if(-not $PSCmdlet.ShouldProcess(
            ([string]$manifest.SourceEntryId+' -> '+[string]$layout.PstPath),
            'Make exactly ONE Outlook MailItem.Move from new synthetic default Drafts to separate disposable PST')){
            throw 'BW4k7v2a7 operator declined one irreversible Move.'
        }
        $stage='Durably seal one-shot Move claim BEFORE calling Outlook MailItem.Move'
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a7.OneShotMoveClaim.1'
            SuiteId=$SuiteId
            ManifestSha256=$ExpectedManifestSha256
            SourceEntryId=[string]$manifest.SourceEntryId
            SourceStoreId=[string]$manifest.SourceStoreId
            SourceFolderId=[string]$manifest.SourceFolderId
            TargetStoreId=[string]$manifest.TargetStoreId
            TargetFolderId=[string]$manifest.TargetFolderId
            SemanticSha256=[string]$manifest.SemanticSha256
            MoveProcessId=[int]$proc.Id;MoveProcessStartUtcTicks=$ticks
            OneShotMoveClaimedBeforeComCall=$true
            RetryForbiddenEvenAfterException=$true
            MoveCompletedNotYetIndependentlyProven=$true
            WriterPermit=$false;ProductionReady=$false
        }
        $claimSha=Write-OPA265BW4k7v2a1JsonOnce -Path $layout.MoveClaimPath -Value $claim
        $stage='ONE irreversible MailItem.Move (never automatic retry)'
        $moved=$read.Move($bindings.TargetFolder)
        # Read returned object only; no additional save or second Move.
        $returned=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a7.MoveReturnObservation.1'
            SuiteId=$SuiteId;ClaimSha256=$claimSha
            MovedItemEntryId=if($null -ne $moved){[string]$moved.EntryID}else{''}
            ObservedParentStoreId=if($null -ne $moved){[string]$moved.Parent.StoreID}else{''}
            ObservedParentFolderId=if($null -ne $moved){[string]$moved.Parent.EntryID}else{''}
            MoveReturnedWithoutComException=$true
            IndependentPostRestartReconciliationRequired=$true
            RetryForbidden=$true;ProductionReady=$false
        }
        $stage='Seal untrusted Move return observation without modifying claim'
        $returnSha=Write-OPA265BW4k7v2a1JsonOnce -Path $layout.MoveReturnPath -Value $returned
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7v2a7.MoveReturned.1'
            Status='SingleOutlookMoveReturnedRequiresIndependentReconciliation'
            SuiteId=$SuiteId;ManifestSha256=$ExpectedManifestSha256
            ClaimSha256=$claimSha;MoveReturnObservationSha256=$returnSha
            OutlookMoveCallCount=1;MustFullyRestartOutlook=$true
            AutomaticRetryAllowed=$false
            MoveConfirmedSafeForProduction=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    $stage='Post-restart independent read-only reconciliation of original one-shot claim'
    $claim=Read-OPA265BW4k7v2a1SealedJson -Path $layout.MoveClaimPath -ExpectedSha256 $ExpectedClaimSha256
    if([string]$claim.Schema -cne '2.6.5-BW4k7v2a7.OneShotMoveClaim.1' -or
       [string]$claim.SuiteId -cne $SuiteId -or
       [string]$claim.ManifestSha256 -cne $ExpectedManifestSha256 -or
       -not [bool]$claim.OneShotMoveClaimedBeforeComCall -or
       -not [bool]$claim.RetryForbiddenEvenAfterException -or
       [bool]$claim.ProductionReady -or [bool]$claim.WriterPermit){
        throw 'BW4k7v2a7 original Move claim invalid.'
    }
    $restart=([int]$proc.Id -ne [int]$claim.MoveProcessId -and
              $ticks -ne [long]$claim.MoveProcessStartUtcTicks)
    if(-not $restart){throw 'BW4k7v2a7 Reconcile requires complete Outlook process restart.'}
    $witnessRows=New-Object 'System.Collections.Generic.List[object]'
    foreach($candidate in @($targetMatches.Matches)){
        if([string]$candidate.Parent.StoreID -cne [string]$manifest.TargetStoreId -or
           [string]$candidate.Parent.EntryID -cne [string]$manifest.TargetFolderId){
            throw 'BW4k7v2a7 independently found candidate outside target folder.'
        }
        $w=Get-OPA265BW4k7v2a7MailWitness -Item $candidate
        $witnessRows.Add([pscustomobject]@{
            SemanticSha256=[string]$w.SemanticSha256
            ParentStoreId=[string]$candidate.Parent.StoreID
            ParentFolderId=[string]$candidate.Parent.EntryID
            DestinationEntryId=[string]$candidate.EntryID
            DestinationSize=[long]$w.Size
            RawMapiFlagsAvailable=[bool]$w.Flags.Available
            RawMapiFlags=[object]$w.Flags.RawValue
        })
    }
    $params=@{
        Manifest=$manifest;Claim=$claim
        SourceMatches=[int]$sourceMatches.Count
        DestinationMatches=[int]$targetMatches.Count
        DestinationWitnesses=@($witnessRows.ToArray())
        OutlookRestartConfirmed=$restart
    }
    $decision=Test-OPA265BW4k7v2a7MoveReconciliation @params
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a7.PostRestartReadOnly.1'
        Status=[string]$decision.Status
        SuiteId=$SuiteId;OriginalManifestSha256=$ExpectedManifestSha256
        OriginalMoveClaimSha256=$ExpectedClaimSha256
        SourceMatches=[int]$sourceMatches.Count;DestinationMatches=[int]$targetMatches.Count
        OriginalSize=[long]$manifest.SourceSizeBytes
        DestinationSize=if($witnessRows.Count -eq 1){[long]$witnessRows[0].DestinationSize}else{$null}
        OriginalRawMapiFlags=[object]$manifest.SourceRawMapiFlags
        DestinationRawMapiFlags=if($witnessRows.Count -eq 1){[object]$witnessRows[0].RawMapiFlags}else{$null}
        DestinationEntryId=if($witnessRows.Count -eq 1){[string]$witnessRows[0].DestinationEntryId}else{''}
        Reconciliation=$decision
        UnknownMapiFlagsAutomaticallyWaived=$false
        LiveProductionArchiveOrResumeEnabled=$false
        NoSecondMoveOrSaveExecuted=$true
        AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
    }
}catch{
    $hex='HResultUnavailable'
    try{$raw=[int64]$_.Exception.HResult;$hex=('0x{0:X8}' -f ([uint32]($raw -band 4294967295L)))}catch{}
    throw ('BW4k7v2a7 STOP at ['+$stage+'] HRESULT='+$hex+': '+
        [string]$_.Exception.Message+
        '. Preserve original suite/claim. NEVER retry MovePilot for this SuiteId.')
}finally{
    foreach($obj in @($source,$destination,$ns,$app)){
        if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)
        }
    }
}