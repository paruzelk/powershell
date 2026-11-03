#requires -Version 5.1
# BW4k7g: INDEPENDENT read-only post-Move content/attachment/recipients audit.
# NEVER calls MailItem.Move, creates a claim, replays writer or changes journal.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$SuiteId,
 [Parameter(Mandatory=$true)][string]$TestId,
 [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedSourceEvidenceSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedDecisionSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedSemanticSnapshotSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedClaimSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedDestinationEntryId,
 [Parameter(Mandatory=$true)][string]$SourcePst,
 [Parameter(Mandatory=$true)][string]$DestinationPst,
 [Parameter(Mandatory=$true)][string]$ExpectedDestinationFolderEntryId,
 [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
 [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
 throw 'BW4k7g postmove requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7gPostMoveSemanticReadOnly265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$stage='Exact source/claim/destination identity and immutable pre-Move records'
$app=$null;$ns=$null
try{
 if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
    $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
    $ExpectedPlanSha256 -cne '6464f562eec08082d1db7781281e3cb0a4efd5264f1c2197ab9f14aedfb74f63' -or
    $ExpectedFiveEvidenceSetSha256 -cne 'ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3' -or
    $ExpectedSourceEvidenceSha256 -cne '0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0' -or
    $ExpectedDecisionSha256 -cne '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6' -or
    $ExpectedSemanticSnapshotSha256 -cne 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac' -or
    $ExpectedDestinationFolderEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B82800000' -or
    $ExpectedProfileName -cne 'Outlook' -or
    $ExpectedDestinationEntryId -cnotmatch '^[a-fA-F0-9]{40,512}$' -or
    -not [IO.File]::Exists($SourcePst) -or -not [IO.File]::Exists($DestinationPst)){
  throw 'BW4k7g postmove strict fixture/destination pins mismatch.'
 }
 $claim=Read-OPA265BW4k7gClaimVerified -ExpectedClaimSha256 $ExpectedClaimSha256
 if(-not [string]::Equals([string]$claim.SourcePst,[IO.Path]::GetFullPath($SourcePst),[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals([string]$claim.DestinationPst,[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
  throw 'BW4k7g immutable Claim source/target PST differs.'
 }
 $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
 $originalPath=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
 if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
    (Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256){
  throw 'BW4k7g original five-case plan or original source witness altered.'
 }
 $plan=Get-Content -LiteralPath $planPath -Encoding UTF8 -Raw | ConvertFrom-Json
 [void](Assert-OPA265BW4jPlan -Plan $plan)
 if((Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId).EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256){
  throw 'BW4k7g previously completed three claims or 5-case evidence changed.'
 }
 $case=@($plan.Cases | Where-Object {([string]$_.TestId -ceq $TestId)})
 if($case.Count -ne 1 -or [string]$case[0].Name -cne 'Attachment1K'){
  throw 'BW4k7g postmove supports only exact original Attachment1K.'
 }
 $original=Get-Content -LiteralPath $originalPath -Raw -Encoding UTF8 | ConvertFrom-Json
 [void](Assert-OPA265BW4jWitness -Witness $original -Case $case[0] -SuiteId $SuiteId)
 if([string]$original.InternetMessageId -cne [string]$claim.InternetMessageId -or
    [string]$original.EntryId -cne [string]$claim.SourceEntryId){
  throw 'BW4k7g postmove original InternetMessageId/EntryID differs from claim.'
 }
 $manualPath=Get-OPA265BW4k7cDecisionPath -SuiteId $SuiteId -TestId $TestId
 $snapshotPath=Get-OPA265BW4k7eSnapshotPath -SuiteId $SuiteId -TestId $TestId
 foreach($path in @($manualPath,$snapshotPath)){
  $expected=if($path -ceq $manualPath){$ExpectedDecisionSha256}else{$ExpectedSemanticSnapshotSha256}
  if(-not [IO.File]::Exists($path) -or
     (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
     (Get-Item -LiteralPath $path -Force).Length -gt 16384 -or
     (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){
   throw 'BW4k7g original source-size decision or recipient snapshot SHA-256 changed.'
  }
 }
 $static=Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
 [void](Assert-OPA265BW4k7gOriginalStaticSnapshot -Record $static)
 $stage='Exact source-zero and uniquely mounted destination store'
 $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
 $ns=$app.GetNamespace('MAPI')
 if([string]$ns.CurrentProfileName -cne 'Outlook'){throw 'BW4k7g active profile changed.'}
 $src=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
 if((Get-OPA265BW4jTextHash -Value ([string]$src.StoreId)) -cne [string]$claim.SourceStoreIdSha256){
  throw 'BW4k7g original source POP3 StoreID not pinned by claim.'
 }
 $folder=$ns.GetFolderFromID([string]$original.FolderEntryId,[string]$src.StoreId)
 $dst=$null;$hit=0;$count=[int]$ns.Stores.Count
 if($count -lt 2 -or $count -gt 128){throw 'BW4k7g Outlook store count unsafe.'}
 for($i=1;$i -le $count;$i++){
  $store=$ns.Stores.Item($i);$fp=''
  try{$fp=[string]$store.FilePath}catch{continue}
  if($fp -and [string]::Equals([IO.Path]::GetFullPath($fp),[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
   $dst=$store;$hit++
  }
 }
 if($hit -ne 1 -or $null -eq $dst -or
    (Get-OPA265BW4jTextHash -Value ([string]$dst.StoreID)) -cne [string]$claim.DestinationStoreIdSha256){
  throw 'BW4k7g destination PST/store absent, duplicate or changed.'
 }
 $targetFolder=$ns.GetFolderFromID($ExpectedDestinationFolderEntryId,[string]$dst.StoreID)
 if([string]$targetFolder.EntryID -cne $ExpectedDestinationFolderEntryId -or
    [string]$targetFolder.Name -cne 'OPA265-BW4j-87e72fd09e774098a403cbe99870b9e7' -or
    [string]$targetFolder.StoreID -cne [string]$dst.StoreID -or
    [string]$targetFolder.Parent.EntryID -cne [string]$dst.GetRootFolder().EntryID){
  throw 'BW4k7g destination target folder or store differs from original claim.'
 }
 $query='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+"'"+[string]$claim.InternetMessageId+"'"
 $sourceMatches=$folder.Items.Restrict($query)
 $targetMatches=$targetFolder.Items.Restrict($query)
 if([int]$sourceMatches.Count -ne 0 -or [int]$targetMatches.Count -ne 1 -or
    [int]$targetFolder.Items.Count -ne 1 -or
    [string]$targetMatches.Item(1).EntryID -cne $ExpectedDestinationEntryId -or
    $ExpectedDestinationEntryId -ceq [string]$original.EntryId){
  throw 'BW4k7g postmove STOP: must observe exact source-zero/destination-one, not ambiguous.'
 }
 $stage='Two independent destination content witnesses and attached binary SHA256'
 $mail=$ns.GetItemFromID($ExpectedDestinationEntryId,[string]$dst.StoreID)
 $w=@{
  Mail=$mail;Case=$case[0];SuiteId=$SuiteId;ProfileName='Outlook'
  ExpectedEntryId=$ExpectedDestinationEntryId
  ExpectedFolderEntryId=$ExpectedDestinationFolderEntryId
  ExpectedStoreId=[string]$dst.StoreID
 }
 $first=Get-OPA265BW4jMailWitness @w
 $second=Get-OPA265BW4jMailWitness @w
 if((ConvertTo-Json -InputObject $first -Depth 8 -Compress) -cne
    (ConvertTo-Json -InputObject $second -Depth 8 -Compress)){
  throw 'BW4k7g destination content drift between independent reads.'
 }
 $compare=Compare-OPA265BW4jWitness -Source $original -Destination $second -Case $case[0] -SuiteId $SuiteId
 $stage='Two independent destination To/Cc/Bcc, significant flag and user-state witnesses'
 $args=@{
  Mail=$mail;ExpectedEntryId=$ExpectedDestinationEntryId
  ExpectedFolderId=$ExpectedDestinationFolderEntryId
  ExpectedStoreId=[string]$dst.StoreID
 }
 $s1=Get-OPA265BW4k7gDestinationSemantic @args
 $s2=Get-OPA265BW4k7gDestinationSemantic @args
 [void](Assert-OPA265BW4k7gStableDestSemantics -First $s1 -Second $s2)
 $recipientMatch=([string]$s2.RecipientDigestSha256 -ceq [string]$static.RecipientDigestSha256 -and
   [int]$s2.RecipientCount -eq 1 -and [int]$s2.ToCount -eq 1 -and
   [int]$s2.CcCount -eq 0 -and [int]$s2.BccCount -eq 0)
 $stateMatch=([string]$s2.UserStateDigestSha256 -ceq [string]$static.UserStateDigestSha256)
 $flagMatch=([int]$s2.ReadHasAttachBits -eq 17 -and -not [bool]$s2.UnRead)
 $bodyMatch=([bool]$compare.SubjectMatches -and [bool]$compare.SenderMatches -and
   [bool]$compare.BodyMatches -and [bool]$compare.HtmlBodyMatches -and
   [bool]$compare.ReceivedUtcTicksMatches -and [bool]$compare.AttachmentsMatch)
 $all=([bool]$compare.IdentityMatches -and $bodyMatch -and $recipientMatch -and $stateMatch -and $flagMatch)
 $stage='Final original files and one-off claim SHA check after Outlook reads'
 if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
    (Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256 -or
    (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSemanticSnapshotSha256 -or
    (Get-FileHash -LiteralPath $manualPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedDecisionSha256){
  throw 'BW4k7g postmove immutable source evidence changed during audit.'
 }
 $claim2=Read-OPA265BW4k7gClaimVerified -ExpectedClaimSha256 $ExpectedClaimSha256
 if([string]$claim2.Schema -cne [string]$claim.Schema){
  throw 'BW4k7g postmove claim changed.'
 }
 [pscustomobject][ordered]@{
  Schema='2.6.5-BW4k7g.IndependentPostMoveSemanticAudit.1'
  Status=$(if($all){'SourceZeroDestinationOneFullCapturedContentRecipientsStateMatchNoWriter'}else{'SourceZeroDestinationOneSemanticMismatchRequiresManualReview'})
  SuiteId=$SuiteId;TestId=$TestId
  VerifiedOneShotClaimSha256=$ExpectedClaimSha256
  VerifiedSourceSemanticSnapshotSha256=$ExpectedSemanticSnapshotSha256
  SourceMessageIdMatches=0;DestinationMessageIdMatches=1
  DestinationEntryId=$ExpectedDestinationEntryId
  DestinationFolderEntryId=$ExpectedDestinationFolderEntryId
  SubjectMatches=[bool]$compare.SubjectMatches
  SenderMatches=[bool]$compare.SenderMatches
  BodyMatches=[bool]$compare.BodyMatches
  HtmlBodyMatches=[bool]$compare.HtmlBodyMatches
  ReceivedUtcTicksMatches=[bool]$compare.ReceivedUtcTicksMatches
  AttachmentBytesAndSha256Match=[bool]$compare.AttachmentsMatch
  SearchKeyAndInternetMessageIdentityMatches=[bool]$compare.IdentityMatches
  FullRecipientSha256Matches=$recipientMatch
  FullUserStateSha256Matches=$stateMatch
  SignificantReadAttachBitsMatch=$flagMatch
  OriginalSourceSize=[long]$original.Size
  DestinationSize=[long]$second.Size
  ProviderCalculatedSizeDelta=([long]$second.Size-[long]$original.Size)
  IndependentDestinationContentReads=2
  IndependentDestinationSemanticReads=2
  AllCapturedContentMatched=$all
  PhysicalPstDurabilityProven=$false
  FullProductionSignificantFlagCoverageProven=$false
  OutlookMoveExecutedByAudit=$false
  AutomaticRetryAllowed=$false;WriterPermit=$false;ProductionReady=$false
  NextAction='Stop;NeverRetryMove;ManualReviewPostMoveEvidenceAndPstDurability'
 }
}catch{
 throw ('BW4k7g postmove STOP at ['+$stage+']: '+[string]$_.Exception.Message+
  '. NEVER RETRY irreversible Move. Only independent read-only investigation permitted.')
}finally{
 if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
 }
 if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
 }
}
