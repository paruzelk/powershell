#requires -Version 5.1
# BW4k7v2a6 READ-ONLY synthetic Body forensics. Historical failed suite only.
# Never output observed Body, HTMLBody or appended signature text.
# Never create/attach PST or Save/Move/Delete any Outlook object.
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
    throw 'BW4k7v2a6 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a4OneShotMovePolicy265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k7v2a6BodyIntegrityPolicy265.ps1')
if($SuiteId -cne '7451b8f5-6404-4496-ae7b-5b1cdfb9063a'){
    throw 'BW4k7v2a6 only observes the exact already-failed BW4k7v2a4 SuiteId.'
}
$layout=Get-OPA265BW4k7v2a4Layout -SuiteId $SuiteId -LocalAppData $env:LOCALAPPDATA
[void](Assert-OPA265BW4k7v2a4Layout -Layout $layout -LocalAppData $env:LOCALAPPDATA)
if($Mode -ceq 'Plan'){
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a6.Plan.1'
        Status='ReadOnlyPlanNoOutlookContactNoEvidenceWrites'
        SuiteId=$SuiteId;ExpectedProfile='Outlook'
        OriginalIntentPath=[string]$layout.IntentPath
        OriginalTestPstPath=[string]$layout.PstPath
        ExactSyntheticSubject=[string]$layout.Subject
        Scope='Only exact existing default Drafts + existing empty disposable PST fixture'
        RealMessageBodyReturned=$false
        OriginalCreatePilotRetried=$false;OriginalMovePilotAllowed=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
if($ExpectedIntentSha256 -cne 'd31a549a4b9baca30a9bcce661230d2f545b1e538d7da4bbccf1a33f6b16e1f8'){
    throw 'BW4k7v2a6 requires exact independently observed original CreateIntent SHA256.'
}
if(-not [IO.File]::Exists([string]$layout.PstPath)){
    throw 'BW4k7v2a6 original disposable PST missing; no mounting or repair.'
}
if([IO.File]::Exists([string]$layout.ManifestPath) -or
   [IO.File]::Exists([string]$layout.MoveClaimPath) -or
   [IO.File]::Exists([string]$layout.MoveReturnPath)){
    throw 'BW4k7v2a6 failed original SuiteId has unexpected manifest/claim/MoveReturn; STOP.'
}
$intent=Read-OPA265BW4k7v2a1SealedJson -Path $layout.IntentPath -ExpectedSha256 $ExpectedIntentSha256
if([string]$intent.Schema -cne '2.6.5-BW4k7v2a4.CreationIntent.1' -or
   [string]$intent.SuiteId -cne $SuiteId -or
   [string]$intent.PstPath -cne [string]$layout.PstPath -or
   [string]$intent.Subject -cne [string]$layout.Subject -or
   [string]::IsNullOrWhiteSpace([string]$intent.DefaultDraftsStoreId) -or
   [string]::IsNullOrWhiteSpace([string]$intent.DefaultDraftsFolderId) -or
   [string]::IsNullOrWhiteSpace([string]$intent.Pop3DeliveryStoreId) -or
   -not [bool]$intent.AtMostOneDraft -or
   -not [bool]$intent.AtMostOneMove -or
   -not [bool]$intent.NoAutomaticRetry -or
   [bool]$intent.ProductionReady){
    throw 'BW4k7v2a6 original CreateIntent scope mismatch.'
}
$app=$null;$ns=$null
try{
    if(@(Get-Process -Name OUTLOOK -ErrorAction Stop).Count -ne 1){
        throw 'BW4k7v2a6 exactly one existing OUTLOOK.EXE process required.'
    }
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne 'Outlook'){
        throw 'BW4k7v2a6 exact original Outlook profile not active.'
    }
    $acctCount=0
    for($i=1;$i -le [int]$ns.Accounts.Count;$i++){
        $account=$ns.Accounts.Item($i)
        if([string]$account.SmtpAddress -ieq [string]$layout.Pop3SmtpAddress -and
           [int]$account.AccountType -eq 2){
            $acctCount++
            if([string]$account.DeliveryStore.StoreID -cne [string]$intent.Pop3DeliveryStoreId){
                throw 'BW4k7v2a6 POP3 original delivery store changed.'
            }
        }
    }
    if($acctCount -ne 1){throw 'BW4k7v2a6 original POP3 account no longer unique.'}
    $defaultId=[string]$ns.DefaultStore.StoreID
    $drafts=$ns.DefaultStore.GetDefaultFolder(16)
    if($defaultId -cne [string]$intent.DefaultDraftsStoreId -or
       $defaultId -ceq [string]$intent.Pop3DeliveryStoreId -or
       [string]$drafts.StoreID -cne $defaultId -or
       [string]$drafts.EntryID -cne [string]$intent.DefaultDraftsFolderId){
        throw 'BW4k7v2a6 original default Drafts identity changed.'
    }
    $testStore=$null;$targetMatches=0
    $n=[int]$ns.Stores.Count
    if($n -lt 1 -or $n -gt 32){throw 'BW4k7v2a6 unbounded store count; STOP.'}
    for($i=1;$i -le $n;$i++){
        $s=$ns.Stores.Item($i)
        $path=[string]$s.FilePath
        if(-not [string]::IsNullOrWhiteSpace($path) -and
            [string]::Equals([IO.Path]::GetFullPath($path),
                [string]$layout.PstPath,[StringComparison]::OrdinalIgnoreCase)){
            $testStore=$s;$targetMatches++
        }
    }
    if($targetMatches -ne 1 -or
       [string]$testStore.StoreID -ceq $defaultId -or
       [string]$testStore.StoreID -ceq [string]$intent.Pop3DeliveryStoreId){
        throw 'BW4k7v2a6 exact disposable PST is not uniquely mounted and isolated.'
    }
    $root=$testStore.GetRootFolder()
    if([int]$root.Folders.Count -gt 128){throw 'BW4k7v2a6 unbounded PST root folders.'}
    $destination=$null;$folderMatches=0
    for($i=1;$i -le [int]$root.Folders.Count;$i++){
        $f=$root.Folders.Item($i)
        if([string]$f.Name -ceq [string]$layout.TargetFolderName){
            $destination=$f;$folderMatches++
        }
    }
    if($folderMatches -ne 1 -or
       [string]$destination.StoreID -cne [string]$testStore.StoreID){
        throw 'BW4k7v2a6 expected original disposable target fixture missing/ambiguous.'
    }
    if([int]$destination.Items.Count -ne 0){
        throw 'BW4k7v2a6 original target fixture now nonempty; no body claim.'
    }
    $sourceItems=$drafts.Items
    $sourceCount=[int]$sourceItems.Count
    if($sourceCount -lt 0 -or $sourceCount -gt 16){
        throw 'BW4k7v2a6 default Drafts too large for bounded exact Subject scan.'
    }
    $subjectCount=0;$synthetic=$null
    for($i=1;$i -le $sourceCount;$i++){
        $item=$sourceItems.Item($i)
        if([string]$item.Subject -cne [string]$layout.Subject){continue}
        $synthetic=$item;$subjectCount++
    }
    if($subjectCount -ne 1){
        throw 'BW4k7v2a6 exact synthetic subject not uniquely found in default Drafts.'
    }
    $subjectRestriction=$drafts.Items.Restrict(("[Subject] = '"+[string]$layout.Subject+"'"))
    if([int]$subjectRestriction.Count -ne 1){
        throw 'BW4k7v2a6 exact synthetic Subject Restrict cardinality not one.'
    }
    $id=[string]$synthetic.EntryID
    if([string]::IsNullOrWhiteSpace($id) -or
       [int]$synthetic.Class -ne 43 -or
       [string]$synthetic.Parent.StoreID -cne $defaultId -or
       [string]$synthetic.Parent.EntryID -cne [string]$drafts.EntryID){
        throw 'BW4k7v2a6 exact synthetic MailItem ID/Class/Parent mismatch.'
    }
    $firstBody=[string]$synthetic.Body
    $first=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody ([string]$layout.Body) -ObservedBody $firstBody
    $reopened=$ns.GetItemFromID($id,$defaultId)
    $matchIdentity=([string]$reopened.EntryID -ceq $id -and
        [string]$reopened.Subject -ceq [string]$layout.Subject -and
        [int]$reopened.Class -eq 43)
    $matchParent=([string]$reopened.Parent.StoreID -ceq $defaultId -and
        [string]$reopened.Parent.EntryID -ceq [string]$drafts.EntryID)
    if(-not $matchIdentity -or -not $matchParent){
        throw 'BW4k7v2a6 matching original synthetic item cannot be reopened by ID.'
    }
    $secondBody=[string]$reopened.Body
    $second=Get-OPA265BW4k7v2a6BodyEvidence -ExpectedBody ([string]$layout.Body) -ObservedBody $secondBody
    $assessment=Test-OPA265BW4k7v2a6FreshBodyRead -InitialEvidence $first -IndependentEvidence $second -OneExactSyntheticCandidate ($subjectCount -eq 1) -ParentStoreAndFolderSame $matchParent -EntryIdAndSubjectSame $matchIdentity
    $bodyFormat='Unavailable'
    try{$bodyFormat=[string]$reopened.BodyFormat}catch{}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a6.LiveReadOnlySyntheticBody.1'
        Status=[string]$assessment.Status
        SuiteId=$SuiteId;ExpectedIntentSha256=$ExpectedIntentSha256
        ProfileName='Outlook'
        SourceFolderPath=[string]$drafts.FolderPath
        SourceFolderItemCount=$sourceCount
        ExactOriginalSyntheticSubjectCount=$subjectCount
        TargetDisposablePstPath=[string]$layout.PstPath
        TargetFolderItems=0
        SourceEntryId=$id
        SourceParentStoreIdSha256=(Get-OPA265BW4k7v2a1Sha256 -Text $defaultId)
        ToMatchesExpected=([string]$reopened.To -ceq [string]$layout.Recipient)
        Unread=[bool]$reopened.UnRead
        BodyFormat=$bodyFormat
        FirstReadBodyEvidence=$first
        ReopenedByIdBodyEvidence=$second
        Assessment=$assessment
        RawBodyOrSignatureReturned=$false
        CreatePilotReplayed=$false;MovePilotCalled=$false
        AnyMailOrEvidenceWrites=$false
        OriginalHistoryRewritten=$false
        WriterPermit=$false;ProductionReady=$false
    }
}finally{
    foreach($o in @($ns,$app)){
        if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)
        }
    }
}