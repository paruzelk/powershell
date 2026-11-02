#requires -Version 5.1
# BW4k7a: read-only diagnosis of unexpected Attachment1K MailItem.Size drift.
# No Move, Capture, Save, Send, journal changes or size-drift acceptance.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedProfileName='Outlook'
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7a STOP: requires native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7aAttachmentSizeDriftReadOnly265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')

$stage='Pin original plan, five source witnesses and all three irreversible claims'
$app=$null;$ns=$null
try{
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       $ExpectedPlanSha256 -cne '6464f562eec08082d1db7781281e3cb0a4efd5264f1c2197ab9f14aedfb74f63' -or
       $ExpectedFiveEvidenceSetSha256 -cne 'ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3' -or
       $ExpectedProfileName -cne 'Outlook' -or
       -not [IO.Path]::IsPathRooted($SourcePst) -or
       $SourcePst.StartsWith('\',[StringComparison]::Ordinal) -or
       -not [IO.File]::Exists($SourcePst) -or
       [IO.Path]::GetExtension($SourcePst) -cne '.pst' -or
       (([IO.File]::GetAttributes($SourcePst) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'BW4k7a exact original plan/source/profile/PST pins invalid.'
    }
    $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
    if(-not [IO.File]::Exists($planPath) -or
       (([IO.File]::GetAttributes($planPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $planPath -Force).Length -gt 16384 -or
       (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256){
        throw 'BW4k7a original plan evidence missing or altered.'
    }
    $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4jPlan -Plan $plan)
    $cases=@($plan.Cases | Where-Object { [string]$_.TestId -ceq $TestId })
    if($cases.Count -ne 1 -or [string]$cases[0].Name -cne 'Attachment1K'){
        throw 'BW4k7a exact original attachment case missing.'
    }
    $set=Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId
    if([string]$set.EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256){
        throw 'BW4k7a original five-evidence set seal changed.'
    }
    [void](Assert-OPA265BW4k7HistoricCompletedMoves -SuiteId $SuiteId)
    $evidencePath=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
    if(-not [IO.File]::Exists($evidencePath) -or
       (([IO.File]::GetAttributes($evidencePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $evidencePath -Force).Length -gt 16384){
        throw 'BW4k7a original source witness file missing or unsafe.'
    }
    $origSha=(Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $original=Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4jWitness -Witness $original -Case $cases[0] -SuiteId $SuiteId)
    if([string]$original.ProfileName -cne $ExpectedProfileName -or
       @($original.Attachments).Count -ne 1 -or
       [long]$original.Attachments[0].ByteCount -lt 1024){
        throw 'BW4k7a original source profile or one-attachment witness differs.'
    }
    $claimPath=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId
    $legacyClaim=Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$TestId+'.json')
    $sourceSnapshotPath=Get-OPA265BW4k7Attachment1KSnapshotPath -SuiteId $SuiteId -TestId $TestId
    if([IO.File]::Exists($claimPath) -or [IO.File]::Exists($legacyClaim) -or
       [IO.File]::Exists($sourceSnapshotPath)){
        throw 'BW4k7a existing current-fixture claim or Capture snapshot: STOP; never overwrite or retry.'
    }
    $stage='Confirm untouched historical Intent isolation and seven original hashes'
    $historic=& (Join-Path $PSScriptRoot 'Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1') -RunId 'a7b51427-7494-43f4-bc96-64915f6bee7e' -SourcePst $SourcePst -ExpectedJournalSha256 '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648' -Mode Archive -Review
    if(-not [bool]$historic.SevenHistoricalEvidenceHashesUnchanged -or
       [int]$historic.HistoricJournalEventCount -ne 1 -or
       [string]$historic.HistoricJournalPhase -cne 'Intent' -or
       [bool]$historic.WorkerDispatchAllowed){
        throw 'BW4k7a historic Intent quarantine changed.'
    }
    $stage='Take two live exact source MailItem witnesses, including SHA256 of attachment bytes'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4k7a wrong Outlook profile.'
    }
    $scope=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $inbox=$scope.Store.GetDefaultFolder(6)
    if(-not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$inbox.EntryID) -Expected ([string]$original.FolderEntryId)) -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$scope.StoreId) -Expected ([string]$original.StoreId))){
        throw 'BW4k7a original Inbox or source StoreID changed.'
    }
    $mail=$ns.GetItemFromID([string]$original.EntryId,[string]$scope.StoreId)
    if($null -eq $mail){throw 'BW4k7a exact source MailItem not found.'}
    $opts=@{
        Mail=$mail;Case=$cases[0];SuiteId=$SuiteId;ProfileName=$ExpectedProfileName
        ExpectedEntryId=[string]$original.EntryId
        ExpectedFolderEntryId=[string]$original.FolderEntryId
        ExpectedStoreId=[string]$scope.StoreId
    }
    $one=Get-OPA265BW4jMailWitness @opts
    $two=Get-OPA265BW4jMailWitness @opts
    [void](Assert-OPA265BW4k1PinnedSource -Original $one -Current $two -Case $cases[0] -SuiteId $SuiteId)

    $stage='Verify exact original InternetMessageId unique in source Inbox'
    $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+"'"+[string]$original.InternetMessageId+"'"
    $matches=$inbox.Items.Restrict($filter)
    if([int]$matches.Count -ne 1 -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$matches.Item(1).EntryID) -Expected ([string]$original.EntryId))){
        throw 'BW4k7a zero/duplicate/nonmatching original message id.'
    }
    $stage='Diagnose original-vs-current source size without acceptance'
    $compare=Compare-OPA265BW4k7aSourceWitnessReadOnly -Original $original -Current $two -Case $cases[0] -SuiteId $SuiteId
    $snapOpts=@{
        Mail=$mail;SuiteId=$SuiteId;TestId=$TestId
        ExpectedEntryId=[string]$original.EntryId
        ExpectedFolderEntryId=[string]$original.FolderEntryId
        ExpectedStoreId=[string]$scope.StoreId
    }
    $mapi1=Get-OPA265BW4k3MapiSnapshot @snapOpts
    $mapi2=Get-OPA265BW4k3MapiSnapshot @snapOpts
    [void](Assert-OPA265BW4k3StableSnapshots -First $mapi1 -Second $mapi2)
    $sizeRows=@($mapi2.Rows | Where-Object { [string]$_.Name -ceq 'PR_MESSAGE_SIZE' })
    $flagRows=@($mapi2.Rows | Where-Object { [string]$_.Name -ceq 'PR_MESSAGE_FLAGS' })
    if($sizeRows.Count -ne 1 -or $flagRows.Count -ne 1){
        throw 'BW4k7a bounded source MAPI size/flags rows missing.'
    }
    $stage='Repeat original seven hashes, five-case seal and all three Claim pins'
    [void](Assert-OPA265BW4k7HistoricCompletedMoves -SuiteId $SuiteId)
    if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
       (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $origSha -or
       (Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId).EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256 -or
       [IO.File]::Exists($claimPath) -or [IO.File]::Exists($legacyClaim) -or
       [IO.File]::Exists($sourceSnapshotPath)){
        throw 'BW4k7a original evidence changed or new Claim/Capture appeared during review.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7a.Attachment1KOriginalSizeDriftReadOnlyReview.1'
        Status=[string]$compare.Status
        SuiteId=$SuiteId;TestId=$TestId;CaseName='Attachment1K'
        OriginalSourceEvidenceSha256=$origSha
        FiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        OriginalSourceEntryId=[string]$original.EntryId
        SourceFolderEntryId=[string]$original.FolderEntryId
        OriginalSize=[long]$compare.OriginalSize
        CurrentSize=[long]$compare.CurrentSize
        DeltaSize=[long]$compare.DeltaSize
        OriginalAttachmentByteCount=[long]$compare.OriginalAttachmentByteCount
        CurrentAttachmentByteCount=[long]$compare.CurrentAttachmentByteCount
        OriginalAttachmentSha256=[string]$compare.OriginalAttachmentSha256
        CurrentAttachmentSha256=[string]$compare.CurrentAttachmentSha256
        AttachmentByteExactMatch=[bool]$compare.AttachmentByteExactMatch
        OtherFieldMismatchCount=[int]$compare.OtherFieldMismatchCount
        OtherFieldMismatchNames=@($compare.OtherFieldMismatchNames)
        ReadOnlyWitnessCount=2
        SourceMapiPropertyCount=[int]$mapi2.PropertyCount
        SourceMapiAvailableCount=[int]$mapi2.AvailableCount
        LiveMapiMessageSize=if([bool]$sizeRows[0].Available){[string]$sizeRows[0].Scalar}else{'Unavailable'}
        LiveMapiMessageFlags=if([bool]$flagRows[0].Available){[string]$flagRows[0].Scalar}else{'Unavailable'}
        OriginalThreeMoveClaimsUnchanged=$true
        OriginalSevenHistoricalHashesUnchanged=$true
        OriginalWitnessUnchanged=$true
        SizeDriftAccepted=$false
        AttemptClaimWritten=$false
        OutlookMoveExecuted=$false
        CanRetryMove=$false
        ProductionReady=$false
        NextAction='StopNoWriter;InvestigateSourceSizeCause;NeverRecaptureOrMove;NoGlobalSizeWaiver'
    }
}catch{
    throw ('BW4k7a STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. Source PST/mail and historical journal/claim artifacts must not be modified. No Move or Capture attempted.')
}finally{
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
