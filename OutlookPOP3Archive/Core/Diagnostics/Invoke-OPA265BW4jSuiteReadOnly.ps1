#requires -Version 5.1
# BW4j early DEV: a five-fixture plan; optional ONE pre-Move source evidence
# per fixture; later independent target comparison. NEVER executes MailItem.Move.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('NewPlan','SourceReview','SourceCapture','DestinationReview')][string]$Mode,
    [string]$SuiteId='',
    [string]$TestId='',
    [string]$ExpectedPlanSha256='',
    [string]$SourcePst='',
    [string]$ExpectedProfileName='Outlook',
    [string]$SourceFolderEntryId='',
    [string]$SourceEntryId='',
    [string]$DestinationPst='',
    [string]$DestinationFolderEntryId='',
    [string]$DestinationEntryId='',
    [string]$ExpectedSourceEvidenceSha256='',
    [switch]$ConfirmCaptureSourceOnce
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4j requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4jSuitePlan265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4jMultiFormatWitness265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
if ($Mode -ceq 'NewPlan'){
    if ($SuiteId -or $TestId -or $ExpectedPlanSha256 -or $SourcePst -or
        $SourceFolderEntryId -or $SourceEntryId -or $DestinationPst -or
        $DestinationFolderEntryId -or $DestinationEntryId -or
        $ExpectedSourceEvidenceSha256 -or $ConfirmCaptureSourceOnce) {
        throw 'BW4j NewPlan requires no existing fixture or store inputs.'
    }
    $new=New-OPA265BW4jPlan
    Write-OPA265BW4jPlanOnce -Plan $new
    return
}
if (($Mode -ceq 'SourceCapture') -ne [bool]$ConfirmCaptureSourceOnce){
    throw 'BW4j only SourceCapture permits -ConfirmCaptureSourceOnce.'
}
if($ExpectedPlanSha256 -cnotmatch '^[a-f0-9]{64}$' -or
    -not [IO.Path]::IsPathRooted($SourcePst) -or
    $SourcePst.StartsWith('\\',[StringComparison]::Ordinal) -or
    [IO.Path]::GetExtension($SourcePst) -ine '.pst' -or
    [string]::IsNullOrWhiteSpace($SourceFolderEntryId) -or
    [string]::IsNullOrWhiteSpace($SourceEntryId) -or
    [string]::IsNullOrWhiteSpace($ExpectedProfileName)){
    throw 'BW4j requires explicit exact plan SHA, local POP3 PST and source identifiers.'
}
$stage='Read and validate immutable five-fixture suite plan'
$app=$null;$ns=$null
try {
    $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
    if(-not [IO.File]::Exists($planPath) -or
       (([IO.File]::GetAttributes($planPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $planPath).Length -gt 16384){
        throw 'BW4j original plan missing, too large or symlinked.'
    }
    $planHash=(Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($planHash -cne $ExpectedPlanSha256){throw 'BW4j pinned five-fixture manifest SHA256 mismatch.'}
    $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4jPlan -Plan $plan)
    $case=$null;$matches=0
    foreach($item in @($plan.Cases)){
        if ([string]$item.TestId -ceq $TestId){$case=$item;$matches++}
    }
    if($matches -ne 1 -or $null -eq $case){throw 'BW4j TestId not unique in original plan.'}
    $evidencePath=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
    if($Mode -ceq 'DestinationReview'){
        if($ExpectedSourceEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            -not [IO.Path]::IsPathRooted($DestinationPst) -or
            $DestinationPst.StartsWith('\\',[StringComparison]::Ordinal) -or
            [string]::IsNullOrWhiteSpace($DestinationFolderEntryId) -or
            [string]::IsNullOrWhiteSpace($DestinationEntryId)){
            throw 'BW4j destination comparison requires exact pinned source witness and target.'
        }
    } elseif($DestinationPst -or $DestinationFolderEntryId -or
            $DestinationEntryId -or $ExpectedSourceEvidenceSha256) {
        throw 'BW4j source review/capture refuses retrospective or target arguments.'
    }
    $stage='Attach existing Outlook profile and uniquely identify POP3 source store'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if($null -eq $app){throw 'BW4j Outlook must already be running.'}
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){throw 'BW4j wrong active Outlook profile.'}
    $src=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    if($Mode -cne 'DestinationReview'){
        $stage='Two bounded read-only source MAPI witness captures'
        $sourceMail=$ns.GetItemFromID($SourceEntryId,[string]$src.StoreId)
        $a=Get-OPA265BW4jMailWitness -Mail $sourceMail -Case $case -SuiteId $SuiteId -ProfileName $ExpectedProfileName -ExpectedEntryId $SourceEntryId -ExpectedFolderEntryId $SourceFolderEntryId -ExpectedStoreId ([string]$src.StoreId)
        $b=Get-OPA265BW4jMailWitness -Mail $sourceMail -Case $case -SuiteId $SuiteId -ProfileName $ExpectedProfileName -ExpectedEntryId $SourceEntryId -ExpectedFolderEntryId $SourceFolderEntryId -ExpectedStoreId ([string]$src.StoreId)
        [void](Assert-OPA265BW4jWitness -Witness $a -Case $case -SuiteId $SuiteId)
        [void](Assert-OPA265BW4jWitness -Witness $b -Case $case -SuiteId $SuiteId)
        if ((ConvertTo-Json -InputObject $a -Depth 9 -Compress) -cne
            (ConvertTo-Json -InputObject $b -Depth 9 -Compress)) {
            throw 'BW4j two sequential source witnesses disagree; no evidence capture.'
        }
        if($Mode -ceq 'SourceCapture'){
            $stage='Write one original source witness; never overwrite'
            if([IO.File]::Exists($evidencePath)){throw 'BW4j source evidence already exists; no replay.'}
            $p=Write-OPA265BW4jOnce -Object $a -Path $evidencePath
            $hash=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
        } else {$p='';$hash=''}
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4j.SourceWitnessReviewOrCapture.1'
            Status=$(if($Mode -ceq 'SourceCapture'){'OneSourceFixtureEvidenceCapturedNoMove'}else{'SourceFixtureReadOnlyReadyNoMove'})
            SuiteId=$SuiteId
            TestId=$TestId
            CaseName=$case.Name
            SourceSize=$a.Size
            AttachmentCount=@($a.Attachments).Count
            BodyUtf8Sha256=$a.BodyUtf8Sha256
            HtmlBodyUtf8Sha256=$a.HtmlBodyUtf8Sha256
            EvidencePath=$p
            EvidenceSha256=$hash
            PlanSha256=$planHash
            OutlookMoveExecuted=$false
            CanRetryMove=$false
            ProductionReady=$false
        }
        return
    }
    $stage='Verify original source evidence and exact pre-Move identities'
    if(-not [IO.File]::Exists($evidencePath) -or
        (([IO.File]::GetAttributes($evidencePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
        (Get-Item -LiteralPath $evidencePath).Length -gt 16384){
        throw 'BW4j original source evidence is missing/unsafe.'
    }
    $beforeHash=(Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($beforeHash -cne $ExpectedSourceEvidenceSha256){
        throw 'BW4j original witness hash changed.'
    }
    $before=Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4jWitness -Witness $before -Case $case -SuiteId $SuiteId)
    if($before.EntryId -cne $SourceEntryId -or
        $before.FolderEntryId -cne $SourceFolderEntryId -or
        $before.StoreId -cne [string]$src.StoreId -or
        $before.ProfileName -cne $ExpectedProfileName){
        throw 'BW4j source identity no longer matches original witness.'
    }
    $stage='Independently ensure source zero and one exact synthetic target item'
    $g=[guid]$SuiteId;$t=[guid]$TestId
    $expectedLeaf='OPA265-BW4j-'+$g.ToString('N')+'-'+$t.ToString('N')+'.pst'
    if([IO.Path]::GetFileName($DestinationPst) -cne $expectedLeaf -or
        -not [IO.File]::Exists($DestinationPst) -or
        (([IO.File]::GetAttributes($DestinationPst) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'BW4j exact disposable target PST missing or invalid filename.'
    }
    $destStore=$null;$hit=0;$stores=[int]$ns.Stores.Count
    if($stores -lt 2 -or $stores -gt 128){throw 'BW4j unsafe Outlook store count.'}
    for($i=1;$i -le $stores;$i++){
        $s=$ns.Stores.Item($i)
        $path=''
        try{$path=[string]$s.FilePath}catch{}
        if($path -and [string]::Equals([IO.Path]::GetFullPath($path),
           [IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
           $destStore=$s;$hit++
        }
    }
    if($hit -ne 1 -or $null -eq $destStore -or
        [string]$destStore.StoreID -ceq [string]$src.StoreId){
        throw 'BW4j source and destination stores must be unique and distinct.'
    }
    $sourceFolder=$ns.GetFolderFromID($SourceFolderEntryId,[string]$src.StoreId)
    $destFolder=$ns.GetFolderFromID($DestinationFolderEntryId,[string]$destStore.StoreID)
    if([string]$sourceFolder.EntryID -cne $SourceFolderEntryId -or
        [string]$destFolder.EntryID -cne $DestinationFolderEntryId -or
        [string]$destFolder.Name -cne ('OPA265-BW4j-'+$t.ToString('N')) -or
        [int]$destFolder.Items.Count -ne 1){
        throw 'BW4j target must be exact named folder containing exactly ONE synthetic MailItem.'
    }
    $id=[string]$before.InternetMessageId
    $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+"'"+$id+"'"
    $sourceMatches=$sourceFolder.Items.Restrict($filter)
    $destinationMatches=$destFolder.Items.Restrict($filter)
    if([int]$sourceMatches.Count -ne 0 -or [int]$destinationMatches.Count -ne 1){
        throw 'BW4j source-zero / target-one independently observed condition not met.'
    }
    $targetMail=$ns.GetItemFromID($DestinationEntryId,[string]$destStore.StoreID)
    $after=Get-OPA265BW4jMailWitness -Mail $targetMail -Case $case -SuiteId $SuiteId -ProfileName $ExpectedProfileName -ExpectedEntryId $DestinationEntryId -ExpectedFolderEntryId $DestinationFolderEntryId -ExpectedStoreId ([string]$destStore.StoreID)
    if([string]$destinationMatches.Item(1).EntryID -cne $DestinationEntryId){
        throw 'BW4j filtered target InternetMessageId returned an unpinned EntryID.'
    }
    $comparison=Compare-OPA265BW4jWitness -Source $before -Destination $after -Case $case -SuiteId $SuiteId
    if((Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $beforeHash -or
       (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $planHash){
       throw 'BW4j source witness or immutable suite plan changed during compare.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4j.IndependentSourceDestinationReadOnly.1'
        Status=$comparison.Status
        SuiteId=$SuiteId
        TestId=$TestId
        CaseName=$case.Name
        SourceMessageIdMatches=0
        DestinationMessageIdMatches=1
        SubjectMatches=$comparison.SubjectMatches
        SenderMatches=$comparison.SenderMatches
        BodyMatches=$comparison.BodyMatches
        HtmlBodyMatches=$comparison.HtmlBodyMatches
        ReceivedUtcTicksMatches=$comparison.ReceivedUtcTicksMatches
        AttachmentsMatch=$comparison.AttachmentsMatch
        SourceSize=$comparison.SourceSize
        DestinationSize=$comparison.DestinationSize
        DeltaSize=$comparison.DeltaSize
        OriginalSourceEvidenceSha256=$beforeHash
        OriginalSuitePlanSha256=$planHash
        MoveAttemptIndependentlyClaimed=$false
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        OutlookMoveExecutedByThisAudit=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
        NextAction='ReadOnlyDiagnosticsOnly;NoWriterOrOneShotMovePermitImplemented'
    }
} catch {
    throw ('BW4j STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. Source PST, original journals and original BW4g/BW4i claims are untouched.')
} finally {
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
