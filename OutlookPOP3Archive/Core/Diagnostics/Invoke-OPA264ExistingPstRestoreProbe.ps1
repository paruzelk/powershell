#requires -Version 5.1
# LIVE2 test only. Explicit opt-in, one-shot TEMP copy restore drill.
# Never touches mail items, primary POP3 PST or the reference backup.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$BackupPst,
    [Parameter(Mandatory=$true)][string]$ExpectedBackupSHA256,
    [Parameter(Mandatory=$true)][long]$ExpectedSizeBytes,
    [switch]$Review,
    [switch]$PrepareClone,
    [switch]$ProbeClone,
    [switch]$ConfirmCurrentTestProfile
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'LIVE2 requires Windows PowerShell 5.1 STA.'
}
if (([int][bool]$Review+[int][bool]$PrepareClone+[int][bool]$ProbeClone) -ne 1) {
    throw 'Specify exactly one of -Review, -PrepareClone or -ProbeClone.'
}
if (($PrepareClone -or $ProbeClone) -and -not $ConfirmCurrentTestProfile) {
    throw 'A TEMP-file/Profile change requires -ConfirmCurrentTestProfile.'
}
. (Join-Path $PSScriptRoot '../Worker/ExistingPstRestoreGuard.ps1')
$params=@{
    RunId=$RunId
    SourcePst=$SourcePst
    BackupPst=$BackupPst
    ExpectedBackupSHA256=$ExpectedBackupSHA256
    ExpectedSizeBytes=$ExpectedSizeBytes
}
$plan=Get-OPA264RestorePlan @params
if ($Review) {
    [void](Assert-OPA264RestoreClonePlan -Plan $plan)
    Write-Output ([pscustomobject]@{
        Status='ReadyForExplicitClonePreparation'
        RunId=$plan.RunId
        TempClone=$plan.ClonePst
        ReferenceBackup=$plan.BackupPst
        BackupSHA256=$plan.ExpectedBackupSHA256
        ExistingMailMoveAllowed=$false
    })
    return
}
if ($PrepareClone) {
    if (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Close Outlook completely before preparing a 7.2GB restore clone.'
    }
    [void](Assert-OPA264RestoreClonePlan -Plan $plan)
    if (-not $PSCmdlet.ShouldProcess($plan.ClonePst,
        'Create one new verified TEMP clone of the backup')) { return }
    if (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Outlook started during confirmation.'
    }
    $srcHash=(Get-FileHash -LiteralPath $plan.SourcePst -Algorithm SHA256).Hash
    if ($srcHash -cne $plan.ExpectedBackupSHA256.ToUpperInvariant()) {
        throw 'Original source PST changed since LIVE1 backup; stop and preserve backup.'
    }
    [void](Assert-OPA264RestoreClonePlan -Plan $plan)
    [void][IO.Directory]::CreateDirectory($plan.Directory)
    $input=$null;$output=$null
    try {
        $input=[IO.FileStream]::new($plan.BackupPst,
            [IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $output=[IO.FileStream]::new($plan.ClonePst,
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] (1MB)
        while($true){
            $n=$input.Read($buffer,0,$buffer.Length)
            if ($n -le 0) { break }
            $output.Write($buffer,0,$n)
        }
        $output.Flush($true)
    }
    finally{
        if($null -ne $output){$output.Dispose()}
        if($null -ne $input){$input.Dispose()}
    }
    if (@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Outlook appeared while cloning. Preserve evidence; do not probe.'
    }
    $size=[long](Get-Item -LiteralPath $plan.ClonePst -Force).Length
    $hash=(Get-FileHash -LiteralPath $plan.ClonePst -Algorithm SHA256).Hash
    if($size -ne $plan.ExpectedSizeBytes -or
        $hash -cne $plan.ExpectedBackupSHA256.ToUpperInvariant()){
        throw 'TEMP clone size/SHA256 mismatch; preserve incomplete clone.'
    }
    $marker=[pscustomobject]@{
        Purpose='OPA264-OneShot-Backup-Restore-Copy'
        RunId=$plan.RunId
        ClonePst=$plan.ClonePst
        SourcePst=$plan.SourcePst
        BackupPst=$plan.BackupPst
        BackupSHA256=$plan.ExpectedBackupSHA256
        ExpectedSizeBytes=$plan.ExpectedSizeBytes
        MailMoveAllowed=$false
        OriginalPstMutationAllowed=$false
    }
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(
        (ConvertTo-Json -InputObject $marker -Depth 5))
    $file=$null
    try {
        $file=[IO.FileStream]::new($plan.MarkerPath,
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $file.Write($bytes,0,$bytes.Length)
        $file.Flush($true)
    }
    finally { if($null -ne $file){$file.Dispose()} }
    Write-Output ([pscustomobject]@{
        Status='VerifiedDisposableClonePrepared'
        RunId=$plan.RunId
        TempClone=$plan.ClonePst
        SHA256=$hash.ToLowerInvariant()
        SizeBytes=$size
        ReferenceBackupUntouched=$true
        OriginalPstUntouched=$true
        MailMoveExecuted=$false
    })
    return
}
# Probe exact clone using the already running test profile only.
if (-not [IO.File]::Exists($plan.MarkerPath) -or
    -not [IO.File]::Exists($plan.ClonePst)) {
    throw 'Prepared TEMP clone and scope marker are missing.'
}
if ([IO.File]::Exists($plan.ClaimPath) -or [IO.File]::Exists($plan.ReportPath)) {
    throw 'One-shot clone probe already attempted; never retry this RunId.'
}
foreach($p in @($plan.Directory,$plan.ClonePst,$plan.MarkerPath)){
    $item=Get-Item -LiteralPath $p -Force
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'Restore probe refuses reparse-point paths.'
    }
}
$marker=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($plan.MarkerPath))
[void](Assert-OPA264RestoreMarker -Plan $plan -Marker $marker)
if ([long](Get-Item -LiteralPath $plan.ClonePst).Length -ne $plan.ExpectedSizeBytes -or
    (Get-FileHash -LiteralPath $plan.ClonePst -Algorithm SHA256).Hash -cne
        $plan.ExpectedBackupSHA256.ToUpperInvariant()) {
    throw 'Prepared TEMP clone SHA256/size mismatch.'
}
$app=$null;$ns=$null;$stage='Outlook preflight'
try {
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if($null -eq $app){ throw 'Outlook must already be running.' }
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook' -or [int]$ns.Accounts.Count -ne 2){
        throw 'Current Outlook profile/account count differs from the user-validated test environment.'
    }
    $beforeCount=[int]$ns.Stores.Count
    $defaultId=[string]$ns.DefaultStore.StoreID
    $srcStore=$null;$srcMatches=0
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $store=$ns.Stores.Item($i)
        $path=''
        try{$path=[string]$store.FilePath}catch{continue}
        if([string]::Equals($path,$plan.ClonePst,[StringComparison]::OrdinalIgnoreCase)){
            throw 'Restore clone is already mounted; refuse repeat.'
        }
        if([string]::Equals($path,$plan.SourcePst,[StringComparison]::OrdinalIgnoreCase)){
            $srcStore=$store;$srcMatches++
        }
    }
    if($srcMatches -ne 1 -or [string]$srcStore.StoreID -ceq $defaultId){
        throw 'Unique nondefault POP3 source store not found.'
    }
    $deliveries=0
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $account=$ns.Accounts.Item($i)
        if([int]$account.AccountType -ne 2){continue}
        if([string]$account.DeliveryStore.StoreID -ceq [string]$srcStore.StoreID){$deliveries++}
    }
    if($deliveries -ne 1){throw 'Source is not uniquely bound to one POP3 account.'}
    $stage='Read source folder inventory'
    $srcInventory=Get-OPA264RestoreFolderInventory -Store $srcStore -MaxFolders 200
    if(-not $PSCmdlet.ShouldProcess($plan.ClonePst,
        'One-shot attach/inspect/detach temporary clone ONLY')){return}
    $claim=$null
    try{
        $claim=[IO.FileStream]::new($plan.ClaimPath,
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=[Text.Encoding]::UTF8.GetBytes($plan.RunId+[char]10)
        $claim.Write($buffer,0,$buffer.Length)
        $claim.Flush($true)
    }
    finally{if($null -ne $claim){$claim.Dispose()}}
    $stage='Attach disposable clone'
    $ns.AddStoreEx($plan.ClonePst,2)
    if([int]$ns.Stores.Count -ne ($beforeCount+1) -or
        [int]$ns.Accounts.Count -ne 2 -or
        [string]$ns.DefaultStore.StoreID -cne $defaultId){
        throw 'Outlook profile changed unexpectedly after clone attachment.'
    }
    $clone=$null;$found=0
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $store=$ns.Stores.Item($i)
        $path=''
        try{$path=[string]$store.FilePath}catch{continue}
        if([string]::Equals($path,$plan.ClonePst,[StringComparison]::OrdinalIgnoreCase)){
            $clone=$store;$found++
        }
    }
    if($found -ne 1 -or [string]$clone.StoreID -ceq $defaultId -or
        [string]$clone.StoreID -ceq [string]$srcStore.StoreID){
        throw 'Attached clone cannot be uniquely distinguished from original store.'
    }
    $stage='Read clone inventory'
    $cloneInventory=Get-OPA264RestoreFolderInventory -Store $clone -MaxFolders 200
    $comparison=Compare-OPA264RestoreFolderInventories -Source $srcInventory -Restored $cloneInventory
    $stage='Detach exact temporary clone'
    $ns.RemoveStore($clone.GetRootFolder())
    $present=0
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $store=$ns.Stores.Item($i)
        $path=''
        try{$path=[string]$store.FilePath}catch{continue}
        if([string]::Equals($path,$plan.ClonePst,[StringComparison]::OrdinalIgnoreCase)){
            $present++
        }
    }
    if($present -ne 0 -or [int]$ns.Stores.Count -ne $beforeCount -or
        [int]$ns.Accounts.Count -ne 2 -or
        [string]$ns.DefaultStore.StoreID -cne $defaultId){
        throw 'Outlook profile state did not return to original after clone detach.'
    }
    $status='StructureOrCountsDiffer'
    if($comparison.FolderStructureAndCountsEqual){$status='RestoredCloneStructureMatches'}
    $report=[pscustomobject]@{
        Schema='2.6.4-LIVE2.RestoreReport.1'
        RunId=$plan.RunId
        Status=$status
        Comparison=$comparison
        CloneDetached=$true
        MailMoveExecuted=$false
        ReferenceBackupUntouched=$true
        OriginalPstUntouchedByThisScript=$true
        RequiresManualReview=$true
        ExistingPstMoveAuthorized=$false
        ProductionReady=$false
    }
    $data=(New-Object Text.UTF8Encoding($false)).GetBytes(
        (ConvertTo-Json -InputObject $report -Depth 8))
    $output=$null
    try{
        $output=[IO.FileStream]::new($plan.ReportPath,
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $output.Write($data,0,$data.Length)
        $output.Flush($true)
    }
    finally{if($null -ne $output){$output.Dispose()}}
    Write-Output $report
}
catch{
    throw ("LIVE2 stopped at {0}: {1}. Preserve TEMP clone and claim; never retry RunId or detach an unverified Outlook store." -f $stage,$_.Exception.Message)
}
finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
