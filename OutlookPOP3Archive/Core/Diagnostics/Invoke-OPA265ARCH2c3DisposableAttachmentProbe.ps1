#requires -Version 5.1
# ARCH2c3 disposable Outlook COM probe. NO PST create/mount, Copy, Move,
# Delete, MailItem.Save or Send. Only Attachment.SaveAsFile touches private TEMP.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Inventory','Probe','PostRestartProbe')][string]$Mode='Plan',
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][ValidateSet('BW4k7v','BW4k7v2a1')][string]$FixtureKind,
    [string]$EntryId='',
    [string]$ExpectedPayloadSha256='',
    [long]$ExpectedPayloadBytes=-1,
    [int]$OriginalOutlookProcessId=0,
    [long]$OriginalOutlookStartUtcTicks=0,
    [string]$TemporaryDirectory=[IO.Path]::GetTempPath()
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'ARCH2c3 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot 'ARCH2c3DisposableProbePolicy.ps1')
. (Join-Path $PSScriptRoot '../Archive/ARCH2bSemanticWitness.ps1')
$layout=Get-OPA265ARCH2c3DisposableLayout -SuiteId $SuiteId -FixtureKind $FixtureKind -LocalAppData $env:LOCALAPPDATA
[void](Assert-OPA265ARCH2c3DisposableLayout -Layout $layout)
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2c3.Plan.1'
        Status='PlanNoOutlookContactNoPstOrTemporaryWrites'
        SuiteId=$SuiteId;FixtureKind=$FixtureKind
        ProfileName='Outlook'
        TestPstPath=[string]$layout.TestPstPath
        ExpectedTestFolderName=[string]$layout.TestFolderName
        Operation='Inventory existing synthetic MailItems or hash exact attachment bytes in protected TEMP'
        RequiresExistingPstAlreadyMounted=$true
        PstWriterCalls=$false
        ArchiveResumeAutoRemainClosed=$true
        WriterPermit=$false;ProductionReady=$false
    }
}
[void](Assert-OPA265ARCH2c3DisposableLayout -Layout $layout -RequirePst)
$probeMode=$Mode -cin @('Probe','PostRestartProbe')
if($probeMode){
    if($EntryId -cnotmatch '^[A-Fa-f0-9]{16,1024}$' -or
       $ExpectedPayloadSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $ExpectedPayloadBytes -lt 0 -or $ExpectedPayloadBytes -gt 268435456){
        throw 'ARCH2c3 probe requires exact EntryId, independent lowercase SHA256 and bounded bytes.'
    }
    [void](Assert-OPA265ARCH2c2TempRoot -Path $TemporaryDirectory)
}elseif($EntryId -or $ExpectedPayloadSha256 -or $ExpectedPayloadBytes -ne -1){
    throw 'ARCH2c3 Inventory does not accept a claimed target or attachment hash.'
}
if($Mode -ceq 'PostRestartProbe'){
    if($OriginalOutlookProcessId -le 0 -or $OriginalOutlookStartUtcTicks -le 0){
        throw 'ARCH2c3 PostRestartProbe requires original PID/start UTC ticks.'
    }
}elseif($OriginalOutlookProcessId -or $OriginalOutlookStartUtcTicks){
    throw 'ARCH2c3 original process identity only allowed for PostRestartProbe.'
}
function Release-OPA265ARCH2c3Com {
    param([object]$Object)
    if($null -ne $Object -and [Runtime.InteropServices.Marshal]::IsComObject($Object)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($Object)
    }
}
$app=$null;$ns=$null;$target=$null;$root=$null;$folder=$null;$items=$null;$message=$null
try {
    $procs=@(Get-Process -Name OUTLOOK -ErrorAction Stop)
    if($procs.Count -ne 1){throw 'ARCH2c3 requires exactly one already running Outlook process.'}
    $proc=$procs[0]
    $ticks=[long]$proc.StartTime.ToUniversalTime().Ticks
    if($Mode -ceq 'PostRestartProbe'){
        [void](Assert-OPA265ARCH2c3RestartedOutlook -OriginalProcessId $OriginalOutlookProcessId -OriginalProcessStartUtcTicks $OriginalOutlookStartUtcTicks -ObservedProcessId ([int]$proc.Id) -ObservedProcessStartUtcTicks $ticks)
    }
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    $storeCount=[int]$ns.Stores.Count
    $accountCount=[int]$ns.Accounts.Count
    if($storeCount -lt 1 -or $storeCount -gt 32 -or $accountCount -gt 64){
        throw 'ARCH2c3 unbounded active Outlook store/account inventory.'
    }
    $storeRows=New-Object 'System.Collections.Generic.List[object]'
    $accountRows=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le $storeCount;$i++){
        $store=$null
        try {
            $store=$ns.Stores.Item($i)
            $p=[string]$store.FilePath
            $storeRows.Add([pscustomobject]@{StoreId=[string]$store.StoreID;FilePath=$p})|Out-Null
            if($p -and [string]::Equals([IO.Path]::GetFullPath($p),
                [string]$layout.TestPstPath,[StringComparison]::OrdinalIgnoreCase)){
                if($null -ne $target){throw 'ARCH2c3 duplicate disposable PST store.'}
                $target=$store
                $store=$null
            }
        }finally {Release-OPA265ARCH2c3Com -Object $store}
    }
    for($i=1;$i -le $accountCount;$i++){
        $account=$null;$delivery=$null
        try {
            $account=$ns.Accounts.Item($i)
            $delivery=$account.DeliveryStore
            $accountRows.Add([pscustomobject]@{
                DeliveryStoreId=if($null -eq $delivery){''}else{[string]$delivery.StoreID}
            })|Out-Null
        }finally {
            Release-OPA265ARCH2c3Com -Object $delivery
            Release-OPA265ARCH2c3Com -Object $account
        }
    }
    $default=$ns.DefaultStore
    try {$defaultId=[string]$default.StoreID}
    finally {Release-OPA265ARCH2c3Com -Object $default}
    $scope=Test-OPA265ARCH2c3StoreScope -Layout $layout -ActualProfileName ([string]$ns.CurrentProfileName) -DefaultStoreId $defaultId -Stores @($storeRows.ToArray()) -Accounts @($accountRows.ToArray())
    if(-not $scope.Approved -or $null -eq $target -or
       [string]$target.StoreID -cne [string]$scope.TargetStoreId){
        throw ('ARCH2c3 disposable store scope blocked: '+($scope.ReasonCodes -join ','))
    }
    $root=$target.GetRootFolder()
    $folderCount=[int]$root.Folders.Count
    if($folderCount -lt 1 -or $folderCount -gt 128){
        throw 'ARCH2c3 disposable root folder topology out of bounds.'
    }
    $matches=0
    for($i=1;$i -le $folderCount;$i++){
        $candidate=$root.Folders.Item($i)
        try {
            if([string]$candidate.Name -ceq [string]$layout.TestFolderName){
                $matches++;if($matches -eq 1){$folder=$candidate;$candidate=$null}
            }
        }finally {Release-OPA265ARCH2c3Com -Object $candidate}
    }
    if($matches -ne 1 -or $null -eq $folder -or
       [string]$folder.StoreID -cne [string]$scope.TargetStoreId){
        throw 'ARCH2c3 exact named disposable folder missing or ambiguous.'
    }
    $items=$folder.Items
    $n=[int]$items.Count
    if($n -lt 1 -or $n -gt 32){throw 'ARCH2c3 exact test folder must have 1..32 items.'}
    if($Mode -ceq 'Inventory'){
        $observed=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le $n;$i++){
            $it=$null
            try {
                $it=$items.Item($i)
                if([int]$it.Class -ne 43 -or
                   -not ([string]$it.Subject).StartsWith('OPA265-',[StringComparison]::Ordinal) -or
                   -not ([string]$it.Subject).Contains($SuiteId)){
                    throw 'ARCH2c3 non-synthetic item encountered; stop.'
                }
                $observed.Add([pscustomobject][ordered]@{
                    EntryId=[string]$it.EntryID
                    SubjectSha256=(Get-OPA265ARCH2bTextSha256 -Text ([string]$it.Subject))
                    AttachmentCount=[int]$it.Attachments.Count
                    ItemClass=43
                })|Out-Null
            }finally {Release-OPA265ARCH2c3Com -Object $it}
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2c3.Inventory.1'
            Status='DisposableAlreadyMountedReadOnlyItemInventory'
            TestPstPath=[string]$layout.TestPstPath
            TestFolderName=[string]$layout.TestFolderName
            OutlookProcessId=[int]$proc.Id
            OutlookProcessStartUtcTicks=$ticks
            Items=@($observed.ToArray())
            SaveAsFileCalled=$false
            PSTWritten=$false
            WriterPermit=$false;ProductionReady=$false
        }
    }
    $message=$ns.GetItemFromID($EntryId,[string]$scope.TargetStoreId)
    $parent=$null
    try {
        if($null -ne $message){$parent=$message.Parent}
        if($null -eq $message -or [int]$message.Class -ne 43 -or
           [string]$message.EntryID -cne $EntryId -or
           [string]$parent.EntryID -cne [string]$folder.EntryID -or
           [string]$parent.StoreID -cne [string]$scope.TargetStoreId -or
           -not ([string]$message.Subject).StartsWith('OPA265-',[StringComparison]::Ordinal) -or
           -not ([string]$message.Subject).Contains($SuiteId)){
            throw 'ARCH2c3 exact disposable mail EntryID, parent or subject mismatch.'
        }
    }finally {Release-OPA265ARCH2c3Com -Object $parent}
    if([int]$message.Attachments.Count -ne 1){
        throw 'ARCH2c3 expects exactly one by-value attachment; never guess an attachment.'
    }
    $captured=@(Get-OPA265ARCH2bAttachmentWitnesses -Mail $message -MaxAttachmentBytes 268435456 -MaxAttachmentCount 1 -TemporaryDirectory $TemporaryDirectory)
    $decision=Test-OPA265ARCH2c3AttachmentEvidence -Witnesses $captured -ExpectedPayloadSha256 $ExpectedPayloadSha256 -ExpectedPayloadBytes $ExpectedPayloadBytes
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2c3.LiveDisposableAttachmentProbe.1'
        Status=[string]$decision.Status
        FixtureKind=$FixtureKind;SuiteId=$SuiteId
        ExactTestPstPath=[string]$layout.TestPstPath
        EntryId=$EntryId
        OutlookProcessId=[int]$proc.Id
        OutlookProcessStartUtcTicks=$ticks
        OutlookRestartRequiredAndVerified=($Mode -ceq 'PostRestartProbe')
        AttachmentByteSha256MatchesIndependentBaseline=[bool]$decision.CriticalPayloadMatches
        AttachmentByteCount=[long]$captured[0].PayloadByteCount
        SecureTempWorkspaceWasClosedByWitness=$true
        PSTWrittenByProbe=$false
        OriginalMessageMoveOrDelete=$false
        WriterPermit=$false;ProductionReady=$false
    }
} finally {
    Release-OPA265ARCH2c3Com -Object $message
    Release-OPA265ARCH2c3Com -Object $items
    Release-OPA265ARCH2c3Com -Object $folder
    Release-OPA265ARCH2c3Com -Object $root
    Release-OPA265ARCH2c3Com -Object $target
    Release-OPA265ARCH2c3Com -Object $ns
    Release-OPA265ARCH2c3Com -Object $app
}
