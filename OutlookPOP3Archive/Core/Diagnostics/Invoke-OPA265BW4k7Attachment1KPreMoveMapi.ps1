#requires -Version 5.1
# BW4k7: pin exact original Attachment1K source witness and 15 bounded MAPI properties.
# Review never writes. Capture writes a separate immutable SHA evidence file ONCE.
# NEVER Move/Save/Send/Delete MailItem or modify historical journal/old claims.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Review','Capture')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedProfileName='Outlook',
    [switch]$ConfirmCaptureOnce
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7 requires native Windows PowerShell 5.1 STA.'
}
if(($Mode -ceq 'Capture') -ne [bool]$ConfirmCaptureOnce){
    throw 'BW4k7 only Capture permits -ConfirmCaptureOnce. Review is read only.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7Attachment1KEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$stage='Verify exact original five-case plan and five immutable witnesses'
$app=$null;$ns=$null
try{
    if($ExpectedPlanSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $ExpectedFiveEvidenceSetSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$ExpectedProfileName -cne 'Outlook' -or
       -not [IO.Path]::IsPathRooted($SourcePst) -or
       $SourcePst.StartsWith('\',[StringComparison]::Ordinal) -or
       -not [IO.File]::Exists($SourcePst) -or
       (([IO.File]::GetAttributes($SourcePst) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'BW4k7 requires exact SHA-256 pins, Outlook profile and real local POP3 PST.'
    }
    $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
    if(-not [IO.File]::Exists($planPath) -or
       (([IO.File]::GetAttributes($planPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $planPath -Force).Length -gt 16384 -or
       (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256){
        throw 'BW4k7 original suite plan absent, changed or unsafe.'
    }
    $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4jPlan -Plan $plan)
    if([string]$plan.SuiteId -cne $SuiteId){throw 'BW4k7 SuiteId not pinned to original plan.'}
    $case=@($plan.Cases|Where-Object {([string]$_.TestId -ceq $TestId)})
    if($case.Count -ne 1 -or [string]$case[0].Name -cne 'Attachment1K' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       $SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f'){
        throw 'BW4k7 is restricted to exact original Attachment1K, no other mail.'
    }
    $set=Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId
    if($set.EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256){
        throw 'BW4k7 immutable five-source seal mismatch.'
    }
    [void](Assert-OPA265BW4k7HistoricCompletedMoves -SuiteId $SuiteId)
    $sourceEvidencePath=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
    if(-not [IO.File]::Exists($sourceEvidencePath) -or
       (([IO.File]::GetAttributes($sourceEvidencePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-Item -LiteralPath $sourceEvidencePath -Force).Length -gt 16384 -or
       (Get-Item -LiteralPath $sourceEvidencePath -Force).Length -gt 16384){
        throw 'BW4k7 original Attachment1K source evidence missing or changed.'
    }
    $originalEvidenceSha256=(Get-FileHash -LiteralPath $sourceEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $original=Get-Content -LiteralPath $sourceEvidencePath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4jWitness -Witness $original -Case $case[0] -SuiteId $SuiteId)
    $sourceEntryId=[string]$original.EntryId
    if([string]::IsNullOrWhiteSpace($sourceEntryId) -or
       [string]$original.ProfileName -cne $ExpectedProfileName -or
       @($original.Attachments).Count -ne 1 -or
       [long]$original.Attachments[0].ByteCount -lt 1024){
        throw 'BW4k7 original MailItem ID or Outlook profile differs.'
    }
    $claimPath=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId
    $oldClaim=Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$TestId+'.json')
    if([IO.File]::Exists($claimPath) -or [IO.File]::Exists($oldClaim)){
        throw 'BW4k7 prior attempt claim exists for Attachment1K. NEVER RECYCLE.'
    }
    $snapshotPath=Get-OPA265BW4k7Attachment1KSnapshotPath -SuiteId $SuiteId -TestId $TestId
    if($Mode -ceq 'Capture' -and [IO.File]::Exists($snapshotPath)){
        throw 'BW4k7 immutable MAPI source snapshot already exists. NEVER OVERWRITE.'
    }
    $stage='Verify original historical seven-file evidence and quarantine'
    $historic=& (Join-Path $PSScriptRoot 'Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1') -RunId 'a7b51427-7494-43f4-bc96-64915f6bee7e' -SourcePst $SourcePst -ExpectedJournalSha256 '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648' -Mode Archive -Review
    if(-not [bool]$historic.SevenHistoricalEvidenceHashesUnchanged -or
       [int]$historic.HistoricJournalEventCount -ne 1 -or
       [string]$historic.HistoricJournalPhase -cne 'Intent' -or
       [bool]$historic.WorkerDispatchAllowed){
        throw 'BW4k7 original historical Intent quarantine differs.'
    }
    $stage='Verify exact original Outlook POP3 store and Attachment1K Inbox mail'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if($null -eq $app){throw 'BW4k7 requires already-running Outlook.'}
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4k7 active Outlook profile mismatch.'
    }
    $src=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $inbox=$src.Store.GetDefaultFolder(6)
    if(-not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$inbox.EntryID) -Expected ([string]$original.FolderEntryId)) -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$src.StoreId) -Expected ([string]$original.StoreId))){
        throw 'BW4k7 original Inbox/Store identity mismatch.'
    }
    $mail=$ns.GetItemFromID($sourceEntryId,[string]$src.StoreId)
    if($null -eq $mail){throw 'BW4k7 selected Attachment1K mail absent.'}
    $wargs=@{
        Mail=$mail;Case=$case[0];SuiteId=$SuiteId
        ProfileName=$ExpectedProfileName
        ExpectedEntryId=$sourceEntryId
        ExpectedFolderEntryId=[string]$original.FolderEntryId
        ExpectedStoreId=[string]$src.StoreId
    }
    $w1=Get-OPA265BW4jMailWitness @wargs
    $w2=Get-OPA265BW4jMailWitness @wargs
    [void](Assert-OPA265BW4k1PinnedSource -Original $original -Current $w1 -Case $case[0] -SuiteId $SuiteId)
    [void](Assert-OPA265BW4k1PinnedSource -Original $original -Current $w2 -Case $case[0] -SuiteId $SuiteId)
    $filter='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+"'"+[string]$original.InternetMessageId+"'"
    $matches=$inbox.Items.Restrict($filter)
    if([int]$matches.Count -ne 1 -or
       -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$matches.Item(1).EntryID) -Expected $sourceEntryId)){
        throw 'BW4k7 original Attachment1K must appear exactly once in the source Inbox.'
    }
    $stage='Take TWO bounded read-only MAPI property hash snapshots'
    $margs=@{
        Mail=$mail;SuiteId=$SuiteId;TestId=$TestId
        ExpectedEntryId=$sourceEntryId
        ExpectedFolderEntryId=[string]$original.FolderEntryId
        ExpectedStoreId=[string]$src.StoreId
    }
    $first=Get-OPA265BW4k3MapiSnapshot @margs
    $second=Get-OPA265BW4k3MapiSnapshot @margs
    [void](Assert-OPA265BW4k3StableSnapshots -First $first -Second $second)
    $stage='Repeat source/plan/five-evidence hashes and both prior real Move seals'
    [void](Assert-OPA265BW4k7HistoricCompletedMoves -SuiteId $SuiteId)
    if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
       (Get-FileHash -LiteralPath $sourceEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $originalEvidenceSha256 -or
       (Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId).EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256 -or
       [IO.File]::Exists($claimPath) -or [IO.File]::Exists($oldClaim)){
        throw 'BW4k7 original evidence changed or source fixture acquired a prior Move claim.'
    }
    $record=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7.ImmutableAttachment1KSourceMapiEvidence.1'
        SuiteId=$SuiteId;TestId=$TestId;CaseName=$case[0].Name
        PlanSha256=$ExpectedPlanSha256
        OriginalEvidenceSha256=$originalEvidenceSha256
        FiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        SourceEntryId=$sourceEntryId
        SourceFolderEntryId=[string]$original.FolderEntryId
        SourceStoreIdSha256=(Get-OPA265BW4jTextHash -Value ([string]$src.StoreId))
        SourceSize=[long]$original.Size
        CapturedUtc=[datetime]::UtcNow.ToString('o')
        Snapshot=$second
        OutlookMoveExecuted=$false
        ProductionReady=$false
    }
    [void](Assert-OPA265BW4k7Attachment1KRecord -Record $record -Original $original -SuiteId $SuiteId -TestId $TestId -OriginalEvidenceSha256 $originalEvidenceSha256 -ExpectedPlanSha256 $ExpectedPlanSha256 -ExpectedFiveEvidenceSetSha256 $ExpectedFiveEvidenceSetSha256)
    $outPath='';$outSha=''
    if($Mode -ceq 'Capture'){
        $stage='Write exactly ONE standalone immutable source metadata evidence, no Outlook mutation'
        $saved=Write-OPA265BW4k7Attachment1KSnapshotOnce -Record $record -Path $snapshotPath
        $outPath=[string]$saved.SnapshotPath
        $outSha=[string]$saved.SnapshotSha256
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7.Attachment1KPreMoveMapiReview.1'
        Status=if($Mode -ceq 'Capture'){'ImmutablePreMoveMapiEvidenceCapturedNoMove'}else{'ExactAttachment1KBoundedMapiPreMoveReadOnlyReady'}
        SuiteId=$SuiteId;TestId=$TestId;CaseName=$case[0].Name
        SourceEntryId=$sourceEntryId
        SourceSize=[long]$original.Size
        PlanSha256=$ExpectedPlanSha256
        OriginalSourceEvidenceSha256=$originalEvidenceSha256
        FiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        PropertyCount=[int]$second.PropertyCount
        AvailableCount=[int]$second.AvailableCount
        PropertyRows=@($second.Rows)
        SnapshotPath=$outPath
        SnapshotSha256=$outSha
        OriginalSevenHistoricalHashesUnchanged=$true
        OutlookMoveExecuted=$false
        CanRetryMove=$false
        ProductionReady=$false
        NextAction='Stop;PreserveOriginalMailAndEvidence;NoMovePermissionIssued'
    }
} catch {
    throw ('BW4k7 STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No MailItem.Move or historical journal mutation permitted.')
} finally {
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
