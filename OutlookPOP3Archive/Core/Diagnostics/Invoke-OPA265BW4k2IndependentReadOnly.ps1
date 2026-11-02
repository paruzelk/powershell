#requires -Version 5.1
# BW4k2: ONLY independent read-only post-Move audit for disposable BW4k1.
# Does not Move, Save, Send, Delete, authorize retry, accept drift, or write journals.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceEvidenceSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedClaimSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedProfileName,
    [Parameter(Mandatory=$true)][string]$SourceFolderEntryId,
    [Parameter(Mandatory=$true)][string]$SourceEntryId,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [Parameter(Mandatory=$true)][string]$DestinationFolderEntryId,
    [Parameter(Mandatory=$true)][string]$DestinationEntryId,
    [Parameter(Mandatory=$true)][int]$ExpectedObservedDeltaSize,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if(-not $Review -or
   $PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k2 requires explicit -Review with Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k1RealOneShotGuards265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4k2IndependentRealMoveAudit265.ps1')
$stage='Validate source, plan and pinned original five-witness evidence'
try {
    foreach($value in @($ExpectedPlanSha256,$ExpectedFiveEvidenceSetSha256,
         $ExpectedSourceEvidenceSha256,$ExpectedClaimSha256)){
        if($value -cnotmatch '^[a-f0-9]{64}$'){
            throw 'BW4k2 requires lowercase full SHA-256 pins.'
        }
    }
    if([string]$ExpectedProfileName -cne 'Outlook' -or
       [string]::IsNullOrWhiteSpace($SourceFolderEntryId) -or
       [string]::IsNullOrWhiteSpace($SourceEntryId) -or
       [string]::IsNullOrWhiteSpace($DestinationFolderEntryId) -or
       [string]::IsNullOrWhiteSpace($DestinationEntryId) -or
       $SourceEntryId -ceq $DestinationEntryId -or
       $ExpectedObservedDeltaSize -eq 0){
        throw 'BW4k2 exact operator-supplied identity or nonzero observed drift missing.'
    }
    foreach($pst in @($SourcePst,$DestinationPst)){
        if(-not [IO.Path]::IsPathRooted($pst) -or
           $pst.StartsWith('\',[StringComparison]::Ordinal) -or
           [IO.Path]::GetExtension($pst) -ine '.pst' -or
           -not [IO.File]::Exists($pst) -or
           (([IO.File]::GetAttributes($pst) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'BW4k2 requires existing ordinary local PSTs, no reparse points.'
        }
    }
    $g=[guid]::Empty;$t=[guid]::Empty
    if(-not [guid]::TryParse($SuiteId,[ref]$g) -or
       $g -eq [guid]::Empty -or $SuiteId -cne $g.ToString('D') -or
       -not [guid]::TryParse($TestId,[ref]$t) -or
       $t -eq [guid]::Empty -or $TestId -cne $t.ToString('D') -or
       [IO.Path]::GetFileName($DestinationPst) -cne ('OPA265-BW4j-'+$g.ToString('N')+'-'+$t.ToString('N')+'.pst') -or
       [string]::Equals([IO.Path]::GetFullPath($SourcePst),[IO.Path]::GetFullPath($DestinationPst),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k2 suite, TestId, destination PST filename or store separation mismatch.'
    }
    $planPath=Get-OPA265BW4jPlanPath -SuiteId $SuiteId
    $sourceEvidencePath=Get-OPA265BW4jEvidencePath -SuiteId $SuiteId -TestId $TestId
    $claimPath=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId
    foreach($p in @($planPath,$sourceEvidencePath,$claimPath)){
        if(-not [IO.File]::Exists($p) -or
           (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
           (Get-Item -LiteralPath $p -Force).Length -gt 16384){
            throw 'BW4k2 source plan, witness or original durable claim missing/unsafe.'
        }
    }
    if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
       (Get-FileHash -LiteralPath $sourceEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256 -or
       (Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedClaimSha256){
        throw 'BW4k2 exact original plan/source/one-shot claim SHA-256 mismatch.'
    }
    $plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4jPlan -Plan $plan)
    if([string]$plan.SuiteId -cne $SuiteId){
        throw 'BW4k2 original plan suite mismatch.'
    }
    $case=@($plan.Cases|Where-Object {([string]$_.TestId -ceq $TestId)})
    if($case.Count -ne 1){throw 'BW4k2 TestId must resolve exactly one planned disposable fixture.'}
    $set=Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId
    if([string]$set.EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256){
        throw 'BW4k2 five-original-source-evidence seal mismatch.'
    }
    $original=Get-Content -LiteralPath $sourceEvidencePath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4jWitness -Witness $original -Case $case[0] -SuiteId $SuiteId)
    if([string]$original.EntryId -cne $SourceEntryId -or
       [string]$original.FolderEntryId -cne $SourceFolderEntryId -or
       [string]$original.ProfileName -cne $ExpectedProfileName){
        throw 'BW4k2 original witness source identity mismatch.'
    }
    $claim=Get-Content -LiteralPath $claimPath -Raw -Encoding UTF8|ConvertFrom-Json
    [void](Assert-OPA265BW4k2Claim -Claim $claim -Original $original -SuiteId $SuiteId -TestId $TestId -PlanSha256 $ExpectedPlanSha256 -FiveSealSha256 $ExpectedFiveEvidenceSetSha256 -SourceEvidenceSha256 $ExpectedSourceEvidenceSha256 -SourcePst $SourcePst -DestinationPst $DestinationPst -DestinationFolderEntryId $DestinationFolderEntryId -SourceEntryId $SourceEntryId)
    $stage='Read same pinned source and target in independent BW4j audit TWICE'
    $argsToReview=@{
        Mode='DestinationReview';SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        SourcePst=$SourcePst;ExpectedProfileName=$ExpectedProfileName
        SourceFolderEntryId=$SourceFolderEntryId;SourceEntryId=$SourceEntryId
        DestinationPst=$DestinationPst
        DestinationFolderEntryId=$DestinationFolderEntryId
        DestinationEntryId=$DestinationEntryId
        ExpectedSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
    }
    $auditor=Join-Path $PSScriptRoot 'Invoke-OPA265BW4jSuiteReadOnly.ps1'
    $first=(& $auditor @argsToReview)
    [void](Assert-OPA265BW4k2IndependentAudit -Audit $first -Original $original -SuiteId $SuiteId -TestId $TestId -PlanSha256 $ExpectedPlanSha256 -SourceEvidenceSha256 $ExpectedSourceEvidenceSha256)
    if([int]$first.DeltaSize -ne $ExpectedObservedDeltaSize){
        throw 'BW4k2 live observed MAPI delta differs from the independently pinned operator value.'
    }
    $stage='Second independent post-Move source/target read-only audit'
    $second=(& $auditor @argsToReview)
    [void](Assert-OPA265BW4k2IndependentAudit -Audit $second -Original $original -SuiteId $SuiteId -TestId $TestId -PlanSha256 $ExpectedPlanSha256 -SourceEvidenceSha256 $ExpectedSourceEvidenceSha256)
    [void](Assert-OPA265BW4k2StableAudits -First $first -Second $second)
    $stage='Repeat exact immutable claim, source and five-evidence seals after independent reads'
    if((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPlanSha256 -or
       (Get-FileHash -LiteralPath $sourceEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSourceEvidenceSha256 -or
       (Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedClaimSha256 -or
       (Get-OPA265BW4k1EvidenceSet -Plan $plan -SuiteId $SuiteId).EvidenceSetSha256 -cne $ExpectedFiveEvidenceSetSha256){
        throw 'BW4k2 immutable witness set or claim changed during two independent Outlook reviews.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k2.IndependentOneShotClaimAndDoubleDestinationReview.1'
        Status='RealDisposableSourceZeroDestinationOneContentMatchSizeDriftUnaccepted'
        SuiteId=$SuiteId;TestId=$TestId;CaseName=$original.CaseName
        VerifiedClaimSha256=$ExpectedClaimSha256
        VerifiedSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
        VerifiedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        MoveAttemptIndependentlyClaimed=$true
        RealMoveAttemptClaimUnchanged=$true
        IndependentOutlookReadOnlyPassCount=2
        SourceMessageIdMatches=[int]$second.SourceMessageIdMatches
        DestinationMessageIdMatches=[int]$second.DestinationMessageIdMatches
        SubjectMatches=[bool]$second.SubjectMatches
        SenderMatches=[bool]$second.SenderMatches
        BodyMatches=[bool]$second.BodyMatches
        HtmlBodyMatches=[bool]$second.HtmlBodyMatches
        ReceivedUtcTicksMatches=[bool]$second.ReceivedUtcTicksMatches
        AttachmentsMatch=[bool]$second.AttachmentsMatch
        SourceSize=[long]$second.SourceSize
        DestinationSize=[long]$second.DestinationSize
        DeltaSize=[long]$second.DeltaSize
        DeltaSizeAccepted=$false
        DeltaSizeExplanationProven=$false
        HistoricalSevenHashesUnchanged=$true
        PhysicalPstDurabilityProven=$false
        FullMAPIByteEqualityProven=$false
        OutlookMoveExecutedByThisAudit=$false
        AutomaticRetryAllowed=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
        NextAction='StopWriters;KeepOriginalClaimAndEvidence;NoGlobalSizeDriftPermit'
    }
} catch {
    throw ('BW4k2 STOP at ['+$stage+']: '+[string]$_.Exception.Message+
       '. No Outlook move, claim write, production journal write or drift acceptance permitted.')
}
