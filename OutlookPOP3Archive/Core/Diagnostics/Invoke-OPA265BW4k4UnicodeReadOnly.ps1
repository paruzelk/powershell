#requires -Version 5.1
# BW4k4: NO Move. Prepare UnicodePlain isolated PST for separate BW4k1 Review,
# or compare existing real post-Move mail against pinned pre-Move MAPI snapshot.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('PreMoveReview','PostMoveCompare')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceEvidenceSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceMapiSnapshotSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedProfileName='Outlook',
    [Parameter(Mandatory=$true)][string]$ExpectedSourceEntryId,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [string]$ExpectedDestinationFolderEntryId='',
    [string]$ExpectedDestinationEntryId='',
    [string]$ExpectedClaimSha256=''
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k4 requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k4UnicodeReadOnlyGuards265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$stage='Pin original immutable plan, source witness and pre-Move MAPI snapshot'
$app=$null;$ns=$null
try{
    foreach($sha in @($ExpectedPlanSha256,$ExpectedFiveEvidenceSetSha256,
        $ExpectedSourceEvidenceSha256,$ExpectedSourceMapiSnapshotSha256)){
        if($sha -cnotmatch '^[a-f0-9]{64}$'){throw 'BW4k4 requires exact lowercase SHA256 pins.'}
    }
    if($ExpectedProfileName -cne 'Outlook' -or
       [string]::IsNullOrWhiteSpace($ExpectedSourceEntryId) -or
       -not [IO.Path]::IsPathRooted($SourcePst) -or
       -not [IO.Path]::IsPathRooted($DestinationPst) -or
       $SourcePst.StartsWith('\',[StringComparison]::Ordinal) -or
       $DestinationPst.StartsWith('\',[StringComparison]::Ordinal) -or
       -not [IO.File]::Exists($SourcePst) -or
       -not [IO.File]::Exists($DestinationPst) -or
       (([IO.File]::GetAttributes($SourcePst) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (([IO.File]::GetAttributes($DestinationPst) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       [string]::Equals([IO.Path]::GetFullPath($SourcePst),[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k4 source and destination must be distinct ordinary existing local PSTs.'
    }
    $g=[guid]::Empty;$t=[guid]::Empty
    if(-not [guid]::TryParse($SuiteId,[ref]$g) -or $g -eq [guid]::Empty -or
       $SuiteId -cne $g.ToString('D') -or
       -not [guid]::TryParse($TestId,[ref]$t) -or $t -eq [guid]::Empty -or
       $TestId -cne $t.ToString('D') -or
       [IO.Path]::GetFileName($DestinationPst) -cne ('OPA265-BW4j-'+$g.ToString('N')+'-'+$t.ToString('N')+'.pst')){
        throw 'BW4k4 exact canonical suite, fixture or target PST filename mismatch.'
    }
    if($Mode -ceq 'PreMoveReview' -and ($ExpectedDestinationFolderEntryId -or
       $ExpectedDestinationEntryId -or $ExpectedClaimSha256)){
        throw 'BW4k4 PreMoveReview forbids post-Move pins and precreated destination folder EntryID.'
    }
    if($Mode -ceq 'PostMoveCompare' -and
       ($ExpectedClaimSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace($ExpectedDestinationFolderEntryId) -or
        [string]::IsNullOrWhiteSpace($ExpectedDestinationEntryId) -or
        $ExpectedDestinationEntryId -ceq $ExpectedSourceEntryId)){
        throw 'BW4k4 PostMoveCompare requires exact Claim SHA, independently obtained destination Item and Folder EntryIDs.'
    }
    $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
    $sourcePath=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
    $snapPath=Get-OPA265BW4k3SnapshotPath -SuiteId $SuiteId -TestId $TestId
    $claimPath=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId
    foreach($file in @($planPath,$sourcePath,$snapPath)){
        if(-not [IO.File]::Exists($file) -or
           (([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
           (Get-Item -LiteralPath $file -Force).Length -gt 65536){
            throw 'BW4k4 immutable source input missing, oversized or reparse point.'
        }
    }
    if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
       (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256 -or
       (Get-FileHash -LiteralPath $snapPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceMapiSnapshotSha256){
        throw 'BW4k4 original source/plan/MAPI evidence SHA256 mismatch.'
    }
    $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4jPlan -Plan $plan)
    if([string]$plan.SuiteId -cne $SuiteId){throw 'BW4k4 wrong original suite.'}
    $case=@($plan.Cases|Where-Object {([string]$_.TestId -ceq $TestId)})
    if($case.Count -ne 1 -or [string]$case[0].Name -cne 'UnicodePlain'){
        throw 'BW4k4 only original UnicodePlain fixture allowed.'
    }
    $set=Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId
    if($set.EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256){
        throw 'BW4k4 original five-source evidence seal mismatch.'
    }
    $original=Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4jWitness -Witness $original -Case $case[0] -SuiteId $SuiteId)
    if([string]$original.EntryId -cne $ExpectedSourceEntryId -or
       [string]$original.ProfileName -cne $ExpectedProfileName){
        throw 'BW4k4 original UnicodePlain source identity mismatch.'
    }
    $pre=Get-Content -LiteralPath $snapPath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4k4OriginalMapiEvidence -Record $pre -Original $original -SuiteId $SuiteId -TestId $TestId -PlanSha256 $ExpectedPlanSha256 -FiveEvidenceSetSha256 $ExpectedFiveEvidenceSetSha256 -SourceEvidenceSha256 $ExpectedSourceEvidenceSha256)
    $legacyClaimPath=Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$TestId+'.json')
    if([IO.File]::Exists($legacyClaimPath)){
        throw 'BW4k4 legacy claim exists. NEVER RETRY.'
    }
    if($Mode -ceq 'PreMoveReview'){
        if([IO.File]::Exists($claimPath)){
            throw 'BW4k4 BW4k1 claim exists before PreMoveReview; NEVER RETRY.'
        }
        $stage='Independent BW4k1 real Outlook two-witness Review and empty exact PST folder'
        $review=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k1RealOneShotMove.ps1') -Mode Review -SuiteId $SuiteId -ExpectedPlanSha256 $ExpectedPlanSha256 -TestId $TestId -ExpectedSourceEvidenceSha256 $ExpectedSourceEvidenceSha256 -ExpectedFiveEvidenceSetSha256 $ExpectedFiveEvidenceSetSha256 -SourcePst $SourcePst -ExpectedProfileName $ExpectedProfileName -ExpectedSourceEntryId $ExpectedSourceEntryId -DestinationPst $DestinationPst
        if([string]$review.Status -cne 'ExactOneShotRealDisposableReviewPassedNoMove' -or
           [bool]$review.OutlookMoveExecuted -or
           [bool]$review.AttemptClaimWritten -or
           [string]::IsNullOrWhiteSpace([string]$review.DestinationFolderEntryId)){
            throw 'BW4k4 independent exact empty-target Outlook Review did not pass.'
        }
        $stage='Verify 15 pinned source MAPI properties STILL match immutable pre-Move capture'
        $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
        $ns=$app.GetNamespace('MAPI')
        if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){throw 'BW4k4 pre-Move wrong Outlook profile.'}
        $srcStore=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
        $srcMail=$ns.GetItemFromID($ExpectedSourceEntryId,[string]$srcStore.StoreId)
        $liveOpts=@{
            Mail=$srcMail;SuiteId=$SuiteId;TestId=$TestId
            ExpectedEntryId=$ExpectedSourceEntryId
            ExpectedFolderEntryId=[string]$original.FolderEntryId
            ExpectedStoreId=[string]$srcStore.StoreId
        }
        $live1=Get-OPA265BW4k3MapiSnapshot @liveOpts
        $live2=Get-OPA265BW4k3MapiSnapshot @liveOpts
        [void](Assert-OPA265BW4k3StableSnapshots -First $live1 -Second $live2)
        [void](Assert-OPA265BW4k3StableSnapshots -First $pre.Snapshot -Second $live2)
        if((Get-FileHash -LiteralPath $snapPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceMapiSnapshotSha256 -or [IO.File]::Exists($claimPath)){
            throw 'BW4k4 pre-move metadata snapshot changed or new attempt claim appeared.'
        }
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k4.UnicodePlainIndependentPreMoveReview.1'
            Status='OriginalUnicodeMapiAndEmptyTargetReviewedNoMove'
            SuiteId=$SuiteId;TestId=$TestId
            SourceSize=[long]$original.Size
            SourceMapiSnapshotSha256=$ExpectedSourceMapiSnapshotSha256
            SourceMapiPropertyCount=[int]$pre.Snapshot.PropertyCount
            SourceMapiAvailableCount=[int]$pre.Snapshot.AvailableCount
            DestinationPst=[IO.Path]::GetFullPath($DestinationPst)
            DestinationFolderEntryId=[string]$review.DestinationFolderEntryId
            PriorClaimExists=$false
            OutlookMoveExecuted=$false;CanRetryMove=$false
            ProductionReady=$false
            NextAction='Stop;NoMovePermit;RequireSeparateBW4k1WhatIfAndOperatorDecision'
        }
        return
    }
    $stage='Verify exact BW4k1 immutable original Move claim'
    if(-not [IO.File]::Exists($claimPath) -or
       (([IO.File]::GetAttributes($claimPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $claimPath -Force).Length -gt 16384 -or
       (Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedClaimSha256){
        throw 'BW4k4 post-Move requires original unmodified explicitly pinned BW4k1 claim.'
    }
    $claim=Get-Content -LiteralPath $claimPath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4k2Claim -Claim $claim -Original $original -SuiteId $SuiteId -TestId $TestId -PlanSha256 $ExpectedPlanSha256 -FiveSealSha256 $ExpectedFiveEvidenceSetSha256 -SourceEvidenceSha256 $ExpectedSourceEvidenceSha256 -SourcePst $SourcePst -DestinationPst $DestinationPst -DestinationFolderEntryId $ExpectedDestinationFolderEntryId -SourceEntryId $ExpectedSourceEntryId)
    $stage='Independently compare exact BW4j content and source zero/target one'
    $arg=@{
        Mode='DestinationReview';SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256;SourcePst=$SourcePst
        ExpectedProfileName=$ExpectedProfileName
        SourceFolderEntryId=[string]$original.FolderEntryId
        SourceEntryId=$ExpectedSourceEntryId
        DestinationPst=$DestinationPst
        DestinationFolderEntryId=$ExpectedDestinationFolderEntryId
        DestinationEntryId=$ExpectedDestinationEntryId
        ExpectedSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
    }
    $auditor=Join-Path $PSScriptRoot 'Invoke-OPA265BW4jSuiteReadOnly.ps1'
    $a=& $auditor @arg
    $b=& $auditor @arg
    $requiredFields=@('SubjectMatches','SenderMatches','BodyMatches','HtmlBodyMatches',
        'ReceivedUtcTicksMatches','AttachmentsMatch','HistoricalSevenHashesUnchanged')
    if([int]$a.SourceMessageIdMatches -ne 0 -or [int]$a.DestinationMessageIdMatches -ne 1 -or
       [string]$a.SuiteId -cne $SuiteId -or [string]$a.TestId -cne $TestId -or
       [string]$a.OriginalSourceEvidenceSha256 -cne $ExpectedSourceEvidenceSha256 -or
       [string]$a.OriginalSuitePlanSha256 -cne $ExpectedPlanSha256 -or
       [long]$a.SourceSize -ne [long]$original.Size -or
       [string]$a.Status -cnotin @('OnlyMAPIMessageSizeChangedNeedsManualReview','AllCheckedFieldsMatchReadOnly')){
        throw 'BW4k4 source-zero target-one independent Outlook content check failed.'
    }
    foreach($f in $requiredFields){if($a.$f -isnot [bool] -or -not $a.$f){throw ('BW4k4 content mismatch '+$f)}}
    [void](Assert-OPA265BW4k2StableAudits -First $a -Second $b)
    $stage='Double bounded MAPI digest snapshot of exactly one pinned target Outlook MailItem'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){throw 'BW4k4 wrong active Outlook profile.'}
    $destStore=$null;$hits=0
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $store=$ns.Stores.Item($i)
        $path=''
        try{$path=[string]$store.FilePath}catch{continue}
        if($path -and [string]::Equals([IO.Path]::GetFullPath($path),[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
            $destStore=$store;$hits++
        }
    }
    if($hits -ne 1 -or $null -eq $destStore){throw 'BW4k4 destination PST not uniquely mounted.'}
    $mail=$ns.GetItemFromID($ExpectedDestinationEntryId,[string]$destStore.StoreID)
    $targetOpts=@{
        Mail=$mail;SuiteId=$SuiteId;TestId=$TestId
        ExpectedEntryId=$ExpectedDestinationEntryId
        ExpectedFolderEntryId=$ExpectedDestinationFolderEntryId
        ExpectedStoreId=[string]$destStore.StoreID
    }
    $first=Get-OPA265BW4k3MapiSnapshot @targetOpts
    $second=Get-OPA265BW4k3MapiSnapshot @targetOpts
    [void](Assert-OPA265BW4k3StableSnapshots -First $first -Second $second)
    $delta=Compare-OPA265BW4k4MapiSnapshots -Original $pre.Snapshot -Destination $second
    $stage='Final unchanged pinned source evidence and claim SHA256 after all Outlook reads'
    if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
       (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256 -or
       (Get-FileHash -LiteralPath $snapPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceMapiSnapshotSha256 -or
       (Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedClaimSha256){
        throw 'BW4k4 original MAPI witness or immutable claim changed during audit.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k4.IndependentUnicodePrePostMapiDigestCompare.1'
        Status='SourceZeroDestinationOneContentMatchedMapiDifferencesForManualReview'
        SuiteId=$SuiteId;TestId=$TestId;CaseName='UnicodePlain'
        ClaimVerified=$true
        VerifiedClaimSha256=$ExpectedClaimSha256
        VerifiedSourceMapiSnapshotSha256=$ExpectedSourceMapiSnapshotSha256
        IndependentContentReviewCount=2
        SourceMessageIdMatches=0
        DestinationMessageIdMatches=1
        SourceSize=[long]$a.SourceSize
        DestinationSize=[long]$a.DestinationSize
        DeltaSize=[long]$a.DeltaSize
        ChangedProperties=[int]$delta.ChangedCount
        AvailabilityChangedProperties=[int]$delta.AvailabilityChangedCount
        MatchedProperties=[int]$delta.MatchedCount
        PropertyDifferences=@($delta.PropertyRows)
        DeltaSizeAccepted=$false
        DeltaSizeExplanationProven=$false
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        OutlookMoveExecutedByThisAudit=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='StopWriter;NeverRetry;ReviewAllMapiDeltas;NoGlobalSizeWaiver'
    }
}catch{
    throw ('BW4k4 STOP at ['+$stage+']: '+[string]$_.Exception.Message+'. No MailItem.Move or claim/journal modifications made by BW4k4.')
}finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
