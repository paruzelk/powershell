#requires -Version 5.1
# BW4k7c: original Attachment1K source-side +512B decision, never Move.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Review','Accept','Verify')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedProfileName='Outlook',
    [switch]$ConfirmExactSource512,
    [string]$ApprovalText='',
    [string]$ExpectedDecisionSha256=''
)
$ErrorActionPreference='Stop'
$dryRun=[bool]$WhatIfPreference
# Read-only COM Get-FileHash etc should never inherit suppressive WhatIfPreference.
if($dryRun){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7c requires native Windows PowerShell 5.1 STA.'
}
if(($Mode -cne 'Accept') -and ($ConfirmExactSource512 -or $ApprovalText)){
    throw 'BW4k7c Review/Verify do not accept operator approval switches.'
}
if($Mode -ceq 'Accept' -and (-not $ConfirmExactSource512 -or
   $ApprovalText -cne 'ACCEPT EXACT SOURCE 8122 TO 8634 PLUS 512 ATTACHMENT1K NO MOVE')){
    throw 'BW4k7c Accept requires separate exact explicit operator decision.'
}
if(($Mode -ceq 'Verify') -ne ($ExpectedDecisionSha256 -cne '')){
    throw 'BW4k7c -ExpectedDecisionSha256 is mandatory only in Verify.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7cExactSourceSizeDecision265.ps1')
$stage='Recheck original BW4k7a/BW4k7b semantics with read-only Outlook MAPI'
try{
    $argsReadOnly=@{
        SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        SourcePst=$SourcePst
        ExpectedProfileName=$ExpectedProfileName
    }
    $verdict=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7bSemanticSourceReview.ps1') @argsReadOnly
    [void](Assert-OPA265BW4k7cSemanticVerdict -Verdict $verdict)
    $path=Get-OPA265BW4k7cDecisionPath -SuiteId $SuiteId -TestId $TestId
    if($Mode -ceq 'Review'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7c.ExactSourceSizeOperatorReview.1'
            Status='Exact512SourceOnlyEvidenceReadyManualDecisionPending'
            SuiteId=$SuiteId;TestId=$TestId
            OriginalSize=[long]$verdict.OriginalSize
            CurrentSize=[long]$verdict.CurrentSize
            DeltaSize=[long]$verdict.DeltaSize
            AttachmentByteCount=[long]$verdict.AttachmentByteCount
            AttachmentSha256=[string]$verdict.AttachmentSha256
            DecisionPath=$path
            DecisionAlreadyExists=[bool][IO.File]::Exists($path)
            SourceContentMatches=$true
            OriginalThreeMoveClaimsUnchanged=$true
            ExactSizeAcknowledged=$false
            AttemptClaimWritten=$false
            OutlookMoveExecuted=$false
            WriterPermit=$false
            ProductionReady=$false
            NextAction='Stop;RequireSeparateExactOperatorDecision;NoMovePermit'
        }
    }
    if($Mode -ceq 'Verify'){
        $stage='Independently validate existing immutable decision SHA256 and exact payload'
        $verified=Read-OPA265BW4k7cManualDecisionVerified -Verdict $verdict -Path $path -ExpectedDecisionSha256 $ExpectedDecisionSha256
        return $verified
    }
    $stage='Accept: re-read same original live source before one standalone decision write'
    if([IO.File]::Exists($path)){
        throw 'BW4k7c already has original immutable decision file. NEVER overwrite.'
    }
    $verdict2=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7bSemanticSourceReview.ps1') @argsReadOnly
    [void](Assert-OPA265BW4k7cSemanticVerdict -Verdict $verdict2)
    $names=@('Schema','Status','SuiteId','TestId','OriginalSourceEvidenceSha256',
        'OriginalSize','CurrentSize','DeltaSize','AttachmentSha256','AttachmentByteCount',
        'AllCapturedContentWitnessFieldsEqual','OriginalThreeMoveClaimsUnchanged',
        'NoGlobalSizeWaiver')
    foreach($name in $names){
        if([string]$verdict.$name -cne [string]$verdict2.$name){
            throw ('BW4k7c live source changed between independent reviews: '+$name)
        }
    }
    if($dryRun){
        return [pscustomobject][ordered]@{
            Status='WhatIfNoDecisionNoMove'
            DecisionPath=$path
            ExactSourceSizeAcknowledged=$false
            DecisionWritten=$false
            OutlookMoveExecuted=$false
            WriterPermit=$false
            ProductionReady=$false
        }
    }
    $stage='Persist one exact, operator-approved immutable JSON decision only'
    if(-not $PSCmdlet.ShouldProcess($path,'Record exact +512 source-size decision; NO MOVE')){
        return
    }
    $decision=New-OPA265BW4k7cManualDecision -Verdict $verdict2 -ApprovalText $ApprovalText
    $written=Write-OPA265BW4k7cManualDecisionOnce -Decision $decision -Verdict $verdict2 -Path $path
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7c.Exact512SourceSizeDecisionReturned.1'
        Status='OneImmutableExactSourceSizeDecisionCreatedNoMove'
        SuiteId=$SuiteId;TestId=$TestId
        DecisionPath=[string]$written.DecisionPath
        DecisionSha256=[string]$written.DecisionSha256
        OriginalSize=8122
        CurrentSize=8634
        DeltaSize=512
        DecisionWritten=$true
        OutlookMoveExecuted=$false
        AttemptClaimWritten=$false
        JournalChanged=$false
        WriterPermit=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='Stop;RunIndependentVerifyWithDecisionSha256;NoMovePermit'
    }
}catch{
    throw ('BW4k7c STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Outlook Move, historic journal/claim editing or automatic retry is permitted.')
}
