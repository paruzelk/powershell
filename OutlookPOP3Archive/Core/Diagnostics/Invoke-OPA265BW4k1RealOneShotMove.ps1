#requires -Version 5.1
# BW4k1 isolated REAL disposable POP3 test MailItem.Move. NEVER production Worker.
# Requires a separately precreated and mounted empty destination PST/folder.
# A flushed immutable claim is written BEFORE exactly one MailItem.Move; no retries.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Seal','Review','Execute')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [string]$TestId='',
    [string]$ExpectedSourceEvidenceSha256='',
    [string]$ExpectedFiveEvidenceSetSha256='',
    [string]$SourcePst='',
    [string]$ExpectedProfileName='Outlook',
    [string]$ExpectedSourceEntryId='',
    [string]$DestinationPst='',
    [string]$ExpectedDestinationFolderEntryId='',
    [switch]$ConfirmOneShotRealMove,
    [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k1 requires Windows PowerShell 5.1 STA.'
}
if($Mode -cne 'Execute' -and ($ConfirmOneShotRealMove -or $ApprovalText)){
    throw 'BW4k1 Seal/Review refuse real Move approval flags.'
}
if($Mode -ceq 'Execute' -and
   (-not $ConfirmOneShotRealMove -or
    $ApprovalText -cne 'MOVE EXACT ONE BW4K1 DISPOSABLE MAIL')){
    throw 'BW4k1 explicit one-real-MailItem.Move approval phrase and switch required.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k1RealOneShotGuards265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$stage='Verify immutable original plan'
$claimPath=''
$claimed=$false
$app=$null;$ns=$null
try{
    if($ExpectedPlanSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4k1 needs pinned lowercase original plan SHA256.'
    }
    $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
    if(-not [IO.File]::Exists($planPath) -or
       (([IO.File]::GetAttributes($planPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $planPath).Length -gt 16384){
        throw 'BW4k1 original plan missing or unsafe.'
    }
    if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256){
        throw 'BW4k1 original plan file hash mismatch.'
    }
    $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4jPlan -Plan $plan)
    if([string]$plan.SuiteId -cne $SuiteId){throw 'BW4k1 plan SuiteId mismatch.'}
    $stage='Verify all five original source evidence files without Outlook'
    $set=Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId
    if($Mode -ceq 'Seal'){
        if($TestId -or $ExpectedSourceEvidenceSha256 -or $ExpectedFiveEvidenceSetSha256 -or
           $SourcePst -or $DestinationPst -or $ExpectedSourceEntryId -or
           $ExpectedDestinationFolderEntryId -or $WhatIfPreference){
            throw 'BW4k1 Seal accepts only exact SuiteId and plan SHA, no mail/target/WhatIf inputs.'
        }
        $set
        return
    }
    if($ExpectedFiveEvidenceSetSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $set.EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256 -or
       $ExpectedSourceEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4k1 original five-evidence seal or per-item SHA256 mismatch.'
    }
    $case=$null;$hits=0
    foreach($row in @($plan.Cases)){
        if([string]$row.TestId -ceq $TestId){$case=$row;$hits++}
    }
    if($hits -ne 1 -or $null -eq $case){throw 'BW4k1 TestId not unique in pinned suite.'}
    $evidencePath=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
    if((Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256){
        throw 'BW4k1 selected original source witness hash mismatch.'
    }
    $original=Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4jWitness -Witness $original -Case $case -SuiteId $SuiteId)
    if([string]$original.EntryId -cne $ExpectedSourceEntryId -or
       [string]$original.ProfileName -cne $ExpectedProfileName){
        throw 'BW4k1 pinned source EntryID or profile mismatch.'
    }
    $claimPath=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId
    $oldClaim=Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$TestId+'.json')
    if([IO.File]::Exists($claimPath) -or [IO.File]::Exists($oldClaim)){
        throw 'BW4k1 prior irreversible claim exists. NEVER RETRY.'
    }
    $sg=[guid]$SuiteId;$tg=[guid]$TestId
    $expectedPstLeaf='OPA265-BW4j-'+$sg.ToString('N')+'-'+$tg.ToString('N')+'.pst'
    $targetFolderName='OPA265-BW4j-'+$tg.ToString('N')
    if(-not [IO.Path]::IsPathRooted($DestinationPst) -or
       $DestinationPst.StartsWith('\',[StringComparison]::Ordinal) -or
       [IO.Path]::GetFileName($DestinationPst) -cne $expectedPstLeaf -or
       -not [IO.File]::Exists($DestinationPst) -or
       (([IO.File]::GetAttributes($DestinationPst) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       -not [IO.Path]::IsPathRooted($SourcePst) -or
       [string]::Equals([IO.Path]::GetFullPath($SourcePst),[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k1 requires the precreated isolated disposable PST with exact SuiteId/TestId filename.'
    }
    if($Mode -ceq 'Execute' -and [string]::IsNullOrWhiteSpace($ExpectedDestinationFolderEntryId)){
        throw 'BW4k1 Execute requires destination folder EntryID independently pinned in Review.'
    }
    $stage='Independent historic Intent and seven-evidence fence'
    $historic=& (Join-Path $PSScriptRoot 'Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1') -RunId 'a7b51427-7494-43f4-bc96-64915f6bee7e' -SourcePst $SourcePst -ExpectedJournalSha256 '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648' -Mode Archive -Review
    if(-not [bool]$historic.SevenHistoricalEvidenceHashesUnchanged -or
       [int]$historic.HistoricJournalEventCount -ne 1 -or
       [string]$historic.HistoricJournalPhase -cne 'Intent' -or
       [bool]$historic.WorkerDispatchAllowed){
        throw 'BW4k1 historic Intent quarantine failed.'
    }
    $stage='Attach existing Outlook and exact POP3 delivery PST'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if($null -eq $app){throw 'BW4k1 needs already-running Outlook.'}
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4k1 incorrect active Outlook profile.'
    }
    $srcScope=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $inbox=$srcScope.Store.GetDefaultFolder(6)
    if($null -eq $inbox -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$inbox.EntryID) -Expected ([string]$original.FolderEntryId)) -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$inbox.StoreID) -Expected ([string]$srcScope.StoreId)) -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$srcScope.StoreId) -Expected ([string]$original.StoreId))){
        throw 'BW4k1 original POP3 Inbox/StoreID identity mismatch.'
    }
    $stage='Resolve precreated unique empty destination PST folder'
    $destStore=$null;$found=0
    $count=[int]$ns.Stores.Count
    if($count -lt 2 -or $count -gt 128){throw 'BW4k1 Outlook store count unsafe.'}
    for($i=1;$i -le $count;$i++){
        $s=$ns.Stores.Item($i)
        $path=''
        try{$path=[string]$s.FilePath}catch{}
        if($path -and [string]::Equals([IO.Path]::GetFullPath($path),[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
            $destStore=$s;$found++
        }
    }
    if($found -ne 1 -or $null -eq $destStore -or
       [string]$destStore.StoreID -ceq [string]$srcScope.StoreId){
        throw 'BW4k1 destination PST must be uniquely mounted and distinct from POP3 PST.'
    }
    $root=$destStore.GetRootFolder()
    $destFolder=$null
    try{$destFolder=$root.Folders.Item($targetFolderName)}catch{}
    if($null -eq $destFolder -or
       [string]$destFolder.Name -cne $targetFolderName -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$destFolder.Parent.EntryID) -Expected ([string]$root.EntryID)) -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$destFolder.StoreID) -Expected ([string]$destStore.StoreID)) -or
       [int]$destFolder.Items.Count -ne 0){
        throw 'BW4k1 destination must be exact top-level empty disposable folder.'
    }
    $actualDestFolderId=[string]$destFolder.EntryID
    if($ExpectedDestinationFolderEntryId -and
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed $actualDestFolderId -Expected $ExpectedDestinationFolderEntryId)){
        throw 'BW4k1 destination folder EntryID differs from independently pinned Review.'
    }
    $stage='Perform TWO independent read-only source witnesses and exact binary comparison'
    $mail=$ns.GetItemFromID($ExpectedSourceEntryId,[string]$srcScope.StoreId)
    if($null -eq $mail){throw 'BW4k1 source MailItem is absent.'}
    $wArgs=@{
        Mail=$mail;Case=$case;SuiteId=$SuiteId;ProfileName=$ExpectedProfileName
        ExpectedEntryId=$ExpectedSourceEntryId
        ExpectedFolderEntryId=[string]$original.FolderEntryId
        ExpectedStoreId=[string]$srcScope.StoreId
    }
    $w1=Get-OPA265BW4jMailWitness @wArgs
    $w2=Get-OPA265BW4jMailWitness @wArgs
    [void](Assert-OPA265BW4k1PinnedSource -Original $original -Current $w1 -Case $case -SuiteId $SuiteId)
    [void](Assert-OPA265BW4k1PinnedSource -Original $original -Current $w2 -Case $case -SuiteId $SuiteId)
    $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+"'"+[string]$original.InternetMessageId+"'"
    $matches=$inbox.Items.Restrict($filter)
    if([int]$matches.Count -ne 1 -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$matches.Item(1).EntryID) -Expected $ExpectedSourceEntryId)){
        throw 'BW4k1 source must contain exactly one expected InternetMessageId.'
    }
    $stage='Verify original plan/source evidence hashes are still pinned before permit'
    if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
       (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256 -or
       (Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId).EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256){
        throw 'BW4k1 original evidence changed during read-only preflight.'
    }
    if([IO.File]::Exists($claimPath) -or [IO.File]::Exists($oldClaim)){
        throw 'BW4k1 claim appeared during review; NEVER RETRY.'
    }
    if($Mode -ceq 'Review'){
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k1.OneShotRealOutlookReview.1'
            Status='ExactOneShotRealDisposableReviewPassedNoMove'
            SuiteId=$SuiteId;TestId=$TestId;CaseName=$case.Name
            SourceEntryId=$ExpectedSourceEntryId
            DestinationPst=[IO.Path]::GetFullPath($DestinationPst)
            DestinationFolderEntryId=$actualDestFolderId
            OriginalPlanSha256=$ExpectedPlanSha256
            OriginalSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
            OriginalFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
            PriorClaimExists=$false;AttemptClaimWritten=$false
            OutlookMoveExecuted=$false;CanRetryMove=$false;ProductionReady=$false
            NextAction='IndependentOperatorApprovalRequiredForExecute'
        }
        return
    }
    if(-not $PSCmdlet.ShouldProcess(('ONE test mail '+$TestId),
        ('ONE irreversible Outlook MailItem.Move into '+$targetFolderName))){
        [pscustomobject]@{
            Status='WhatIfNoClaimNoMove';TestId=$TestId
            AttemptClaimWritten=$false;OutlookMoveExecuted=$false
            CanRetryMove=$false;ProductionReady=$false
        }
        return
    }
    $stage='Durably claim exactly ONE irreversible real Outlook Move BEFORE COM mutation'
    $claim=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4k1.IrreversibleRealMailMoveClaim.1'
        SuiteId=$SuiteId;TestId=$TestId;CaseName=$case.Name
        PlanSha256=$ExpectedPlanSha256
        EvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        SourceEvidenceSha256=$ExpectedSourceEvidenceSha256
        SourcePst=[IO.Path]::GetFullPath($SourcePst)
        SourceEntryId=$ExpectedSourceEntryId
        SourceFolderEntryId=[string]$original.FolderEntryId
        InternetMessageId=[string]$original.InternetMessageId
        DestinationPst=[IO.Path]::GetFullPath($DestinationPst)
        DestinationFolderEntryId=$actualDestFolderId
        ClaimUtc=[datetime]::UtcNow.ToString('o')
        RealOutlookOneShot=$true
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
    $written=Write-OPA265BW4k1ClaimOnce -Claim $claim -ClaimPath $claimPath
    $claimed=$true
    $stage='Perform the ONLY authorized MailItem.Move (NO RETRY)'
    $moved=$mail.Move($destFolder)
    if($null -eq $moved -or [string]::IsNullOrWhiteSpace([string]$moved.EntryID)){
        throw 'BW4k1 Move returned ambiguous target; NEVER RETRY.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k1.RealOneShotMoveReturned.1'
        Status='OneRealDisposableMoveReturnedRequiresIndependentReadOnlyReconciliation'
        SuiteId=$SuiteId;TestId=$TestId;CaseName=$case.Name
        ClaimPath=$written.ClaimPath;ClaimSha256=$written.ClaimSha256
        SourceEntryId=$ExpectedSourceEntryId
        DestinationEntryId=[string]$moved.EntryID
        DestinationFolderEntryId=$actualDestFolderId
        DestinationPst=[IO.Path]::GetFullPath($DestinationPst)
        OriginalSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
        MoveAttempts=1
        OutlookMoveReturned=$true
        CanRetryMove=$false;AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='StopWriter;IndependentlyRunBW4jDestinationReview;NeverRetry'
    }
} catch {
    throw ('BW4k1 STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        $(if($claimed -or ($claimPath -and [IO.File]::Exists($claimPath))){'. Claim may exist: NEVER RETRY; only independent read-only reconciliation.'}else{'. No new BW4k1 claim observed; NO automatic retry.'}))
} finally {
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
