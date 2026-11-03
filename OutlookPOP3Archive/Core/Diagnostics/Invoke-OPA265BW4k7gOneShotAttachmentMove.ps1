#requires -Version 5.1
# BW4k7g. One original disposable Attachment1K; durable claim before ONE Move.
# Review and -WhatIf do not change Outlook/PST, claim or historic journal.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
 [Parameter(Mandatory=$true)][ValidateSet('Review','Execute')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$SuiteId,
 [Parameter(Mandatory=$true)][string]$TestId,
 [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedSourceEvidenceSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedDecisionSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedSemanticSnapshotSha256,
 [Parameter(Mandatory=$true)][string]$SourcePst,
 [Parameter(Mandatory=$true)][string]$DestinationPst,
 [Parameter(Mandatory=$true)][string]$ExpectedDestinationFolderEntryId,
 [string]$ExpectedProfileName='Outlook',
 [switch]$ConfirmOneShotAttachmentMove,
 [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
$dry=[bool]$WhatIfPreference
if($dry){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
 [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
 throw 'BW4k7g requires Windows PowerShell 5.1 STA.'
}
if($Mode -ceq 'Review' -and ($ConfirmOneShotAttachmentMove -or $ApprovalText)){
 throw 'BW4k7g Review refuses execution approval.'
}
if($Mode -ceq 'Execute' -and (-not $ConfirmOneShotAttachmentMove -or
 $ApprovalText -cne 'MOVE EXACT ONE BW4K7G ATTACHMENT1K DISPOSABLE MAIL')){
 throw 'BW4k7g Execute requires the separate exact operator approval.'
}
if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
 $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
 $ExpectedPlanSha256 -cne '6464f562eec08082d1db7781281e3cb0a4efd5264f1c2197ab9f14aedfb74f63' -or
 $ExpectedFiveEvidenceSetSha256 -cne 'ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3' -or
 $ExpectedSourceEvidenceSha256 -cne '0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0' -or
 $ExpectedDecisionSha256 -cne '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6' -or
 $ExpectedSemanticSnapshotSha256 -cne 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac' -or
 $ExpectedDestinationFolderEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B82800000' -or
 $ExpectedProfileName -cne 'Outlook'){
 throw 'BW4k7g original proof and exact destination Folder EntryID pins mismatch.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7gOneShotAttachmentGuard265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$stage='Preflight'
$claimPath=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId
$legacyClaim=Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$TestId+'.json')
$claimed=$false;$app=$null;$ns=$null
try{
 if([IO.File]::Exists($claimPath) -or [IO.File]::Exists($legacyClaim)){
  throw 'BW4k7g prior irreversible Claim exists. NEVER RETRY.'
 }
 $p=@{
  SuiteId=$SuiteId;TestId=$TestId;ExpectedPlanSha256=$ExpectedPlanSha256
  ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
  ExpectedSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
  ExpectedDecisionSha256=$ExpectedDecisionSha256
  ExpectedSemanticSnapshotSha256=$ExpectedSemanticSnapshotSha256
  SourcePst=$SourcePst;DestinationPst=$DestinationPst
  ExpectedProfileName=$ExpectedProfileName
 }
 $pre=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7fEmptyTargetReview.ps1') @p
 if([string]$pre.Status -cne 'ExactAttachment1KEmptyTargetIndependentlyReviewedNoMove' -or
    [int]$pre.SourceMessageIdMatches -ne 1 -or [int]$pre.DestinationMessageIdMatches -ne 0 -or
    [int]$pre.DestinationFolderItemCount -ne 0 -or [int]$pre.IndependentSemanticReviews -ne 2 -or
    [string]$pre.DestinationFolderEntryId -cne $ExpectedDestinationFolderEntryId -or
    [bool]$pre.AttemptClaimWritten -or [bool]$pre.OutlookMoveExecuted -or [bool]$pre.WriterPermit){
   throw 'BW4k7g immutable source and original empty destination preflight failed.'
 }
 $stage='Original five witnesses, attachment bytes and recipient/state source comparison'
 $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
 $evidencePath=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
 $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
 [void](Assert-OPA265BW4jPlan -Plan $plan)
 $case=@($plan.Cases | Where-Object {([string]$_.TestId -ceq $TestId)})
 if($case.Count -ne 1 -or [string]$case[0].Name -cne 'Attachment1K' -or
    (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
    (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256 -or
    (Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId).EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256){
  throw 'BW4k7g immutable source evidence or plan changed.'
 }
 $original=Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
 $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
 $ns=$app.GetNamespace('MAPI')
 if([string]$ns.CurrentProfileName -cne 'Outlook'){throw 'BW4k7g Outlook profile mismatch.'}
 $src=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
 if([string]$src.StoreId -cne [string]$original.StoreId){
  throw 'BW4k7g source POP3 StoreID changed.'
 }
 $mail=$ns.GetItemFromID([string]$original.EntryId,[string]$src.StoreId)
 $inbox=$src.Store.GetDefaultFolder(6)
 if([string]$mail.EntryID -cne '00000000E1878292411BC64291BD506DCEFD2A35A46D3C00' -or
    [string]$inbox.EntryID -cne [string]$original.FolderEntryId -or
    [string]$mail.Parent.EntryID -cne [string]$original.FolderEntryId){
  throw 'BW4k7g pinned original MailItem/Inbox identity changed.'
 }
 $w=@{
  Mail=$mail;Case=$case[0];SuiteId=$SuiteId;ProfileName='Outlook'
  ExpectedEntryId=[string]$original.EntryId
  ExpectedFolderEntryId=[string]$original.FolderEntryId
  ExpectedStoreId=[string]$src.StoreId
 }
 $w1=Get-OPA265BW4jMailWitness @w;$w2=Get-OPA265BW4jMailWitness @w
 [void](Assert-OPA265BW4k7gPinnedSourceContent -Original $original -Current $w1 -Case $case[0] -SuiteId $SuiteId)
 [void](Assert-OPA265BW4k7gPinnedSourceContent -Original $original -Current $w2 -Case $case[0] -SuiteId $SuiteId)
 $v=@{Mail=$mail;SuiteId=$SuiteId;TestId=$TestId;SourceEntryId=[string]$original.EntryId}
 $s1=Get-OPA265BW4k7dLiveWitness @v
 $s2=Get-OPA265BW4k7dLiveWitness @v
 [void](Assert-OPA265BW4k7gLiveSemanticSource -Witness $s1)
 [void](Assert-OPA265BW4k7gLiveSemanticSource -Witness $s2)
 [void](Assert-OPA265BW4k7dStableWitness -First $s1 -Second $s2)
 $stage='Uniquely mounted target and pinned destination Folder EntryID'
 $destStore=$null;$hits=0;$count=[int]$ns.Stores.Count
 if($count -lt 2 -or $count -gt 128){throw 'BW4k7g invalid Outlook store count.'}
 for($i=1;$i -le $count;$i++){
  $store=$ns.Stores.Item($i);$path=''
  try{$path=[string]$store.FilePath}catch{continue}
  if($path -and [string]::Equals([IO.Path]::GetFullPath($path),
      [IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
   $hits++;$destStore=$store
  }
 }
 if($hits -ne 1 -or $null -eq $destStore -or
    [string]$destStore.StoreID -ceq [string]$src.StoreId){
  throw 'BW4k7g destination store absent, duplicate or equal to source.'
 }
 $root=$destStore.GetRootFolder()
 $destFolder=$ns.GetFolderFromID($ExpectedDestinationFolderEntryId,[string]$destStore.StoreID)
 if([string]$destFolder.EntryID -cne $ExpectedDestinationFolderEntryId -or
    [string]$destFolder.Name -cne 'OPA265-BW4j-87e72fd09e774098a403cbe99870b9e7' -or
    [string]$destFolder.Parent.EntryID -cne [string]$root.EntryID -or
    [string]$destFolder.StoreID -cne [string]$destStore.StoreID -or
    [int]$destFolder.Items.Count -ne 0){
  throw 'BW4k7g exact empty top-level folder changed.'
 }
 $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+"'"+[string]$original.InternetMessageId+"'"
 $hitsSrc=$inbox.Items.Restrict($filter)
 if([int]$hitsSrc.Count -ne 1 -or
    [string]$hitsSrc.Item(1).EntryID -cne [string]$original.EntryId -or
    [int]$destFolder.Items.Restrict($filter).Count -ne 0){
  throw 'BW4k7g exact source unique and destination empty no longer hold.'
 }
 $stage='Second full independent BW4k7f preflight immediately before Claim'
 $pre2=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7fEmptyTargetReview.ps1') @p
 if([string]$pre2.Status -cne 'ExactAttachment1KEmptyTargetIndependentlyReviewedNoMove' -or
    [string]$pre2.DestinationFolderEntryId -cne $ExpectedDestinationFolderEntryId -or
    [IO.File]::Exists($claimPath) -or [IO.File]::Exists($legacyClaim)){
  throw 'BW4k7g second preflight or irreversible Claim fence failed.'
 }
 if($Mode -ceq 'Review' -or $dry){
  return [pscustomobject][ordered]@{
   Schema='2.6.5-BW4k7g.OneShotAttachmentPreMove.1'
   Status=$(if($dry){'WhatIfNoClaimNoMove'}else{'ExactAttachment1KOneShotReadyForOperatorDecisionNoMove'})
   SuiteId=$SuiteId;TestId=$TestId;SourceMessageIdMatches=1;DestinationMessageIdMatches=0
   OriginalSourceSize=8122;CurrentSourceSize=8634;SourceSizeDrift=512
   DestinationFolderEntryId=$ExpectedDestinationFolderEntryId
   VerifiedSourceSnapshotSha256=$ExpectedSemanticSnapshotSha256
   VerifiedSizeDecisionSha256=$ExpectedDecisionSha256
   RecipientDigestSha256=[string]$s2.RecipientDigestSha256
   UserStateDigestSha256=[string]$s2.UserStateDigestSha256
   ClaimPath=$claimPath
   AttemptClaimWritten=$false;OutlookMoveExecuted=$false
   WriterPermit=$false;AutomaticRetryAllowed=$false;ProductionReady=$false
  }
 }
 $stage='Final explicit ShouldProcess boundary'
 if(-not $PSCmdlet.ShouldProcess(('Exact disposable Attachment1K '+$TestId),
   'Durable irreversible Claim then ONE MailItem.Move; NEVER RETRY')){
  return [pscustomobject]@{
   Status='WhatIfNoClaimNoMove';AttemptClaimWritten=$false
   OutlookMoveExecuted=$false;AutomaticRetryAllowed=$false;ProductionReady=$false
  }
 }
 $stage='Durably write ONLY ONE irreversible Claim BEFORE MailItem.Move'
 $claimArgs=@{
  SourcePst=$SourcePst;DestinationPst=$DestinationPst
  SourceStoreId=[string]$src.StoreId
  DestinationStoreId=[string]$destStore.StoreID
  InternetMessageId=[string]$original.InternetMessageId
 }
 $attempt=New-OPA265BW4k7gAttemptClaim @claimArgs
 $written=Write-OPA265BW4k7gClaimOnce -Claim $attempt
 $claimed=$true
 $stage='Exactly ONE Outlook MailItem.Move; no exception retry'
 $moved=$mail.Move($destFolder)
 if($null -eq $moved -or [string]::IsNullOrWhiteSpace([string]$moved.EntryID)){
  throw 'BW4k7g Move returned no unique destination EntryID. NEVER RETRY.'
 }
 return [pscustomobject][ordered]@{
  Schema='2.6.5-BW4k7g.RealDisposableMoveReturned.1'
  Status='OneAttachment1KMoveReturnedIndependentAuditRequired'
  SuiteId=$SuiteId;TestId=$TestId
  ClaimPath=[string]$written.ClaimPath;ClaimSha256=[string]$written.ClaimSha256
  DestinationEntryId=[string]$moved.EntryID
  DestinationFolderEntryId=$ExpectedDestinationFolderEntryId
  DestinationPst=[IO.Path]::GetFullPath($DestinationPst)
  MoveAttempts=1;OutlookMoveReturned=$true
  AutomaticRetryAllowed=$false;ProductionReady=$false
  NextAction='StopWriter;NeverRetry;IndependentReadOnlyDestinationAuditRequired'
 }
}catch{
 throw ('BW4k7g STOP at ['+$stage+']: '+[string]$_.Exception.Message+
  $(if($claimed -or ($claimPath -and [IO.File]::Exists($claimPath))){
   '. Claim exists or may exist: NEVER RETRY; independent read-only reconciliation only.'}
   else{'. No Claim observed; no automatic retry allowed.'}))
}finally{
 if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
 }
 if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
 }
}
