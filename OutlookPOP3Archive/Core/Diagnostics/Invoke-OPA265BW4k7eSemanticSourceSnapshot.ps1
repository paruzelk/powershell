#requires -Version 5.1
# BW4k7e: original 1 KiB attachment recipient-state source snapshot.
# Review read-only, Capture one explicit metadata-only record, Verify read-only.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Review','Capture','Verify')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SuiteId,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedDecisionSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [string]$ExpectedProfileName='Outlook',
    [switch]$ConfirmCaptureOnce,
    [string]$ApprovalText='',
    [string]$ExpectedSnapshotSha256=''
)
$ErrorActionPreference='Stop'
$dryRun=[bool]$WhatIfPreference
if($dryRun){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7e STOP: native Windows PowerShell 5.1 STA required.'
}
if(($Mode -cne 'Capture') -and ($ConfirmCaptureOnce -or $ApprovalText)){
    throw 'BW4k7e Review/Verify cannot carry Capture approval.'
}
if($Mode -ceq 'Capture' -and (-not $ConfirmCaptureOnce -or
   $ApprovalText -cne 'CAPTURE EXACT BW4K7E RECIPIENT STATE SOURCE NO MOVE')){
    throw 'BW4k7e Capture requires explicit operator confirmation.'
}
if(($Mode -ceq 'Verify') -ne ($ExpectedSnapshotSha256 -cne '')){
    throw 'BW4k7e Verify requires snapshot SHA256, other modes forbid it.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7eImmutableSemanticSnapshot265.ps1')
$stage='Repeat independent exact BW4k7d live recipient/flags review'
try{
    $opts=@{
        SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        ExpectedDecisionSha256=$ExpectedDecisionSha256
        SourcePst=$SourcePst;ExpectedProfileName=$ExpectedProfileName
    }
    $first=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7dRecipientFlagsReview.ps1') @opts
    [void](Assert-OPA265BW4k7eExactReview -Review $first)
    $path=Get-OPA265BW4k7eSnapshotPath -SuiteId $SuiteId -TestId $TestId
    if($Mode -ceq 'Review'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7e.ExactSourceSemanticPreCaptureReview.1'
            Status='ExactRecipientStateEvidenceReviewedNoCaptureNoMove'
            SuiteId=$SuiteId;TestId=$TestId
            OriginalDecisionSha256=$ExpectedDecisionSha256
            RecipientCount=[int]$first.RecipientCount
            ToCount=[int]$first.ToCount
            CcCount=[int]$first.CcCount
            BccCount=[int]$first.BccCount
            RecipientDigestSha256=[string]$first.RecipientDigestSha256
            UserStateDigestSha256=[string]$first.UserStateDigestSha256
            MapiFlags=[int]$first.MapiFlags
            SnapshotPath=$path
            SnapshotAlreadyExists=[bool][IO.File]::Exists($path)
            SnapshotWritten=$false
            OutlookMoveExecuted=$false
            WriterPermit=$false
            ProductionReady=$false
            NextAction='Stop;SeparateOperatorCaptureDecision;NoMove'
        }
    }
    if($Mode -ceq 'Verify'){
        $stage='Read existing immutable snapshot and verify independently by its SHA256'
        return Read-OPA265BW4k7eSnapshotVerified -Review $first -ExpectedSnapshotSha256 $ExpectedSnapshotSha256
    }
    $stage='Capture: check no prior record and independently reread original source'
    if([IO.File]::Exists($path)){
        throw 'BW4k7e original snapshot already exists; NEVER overwrite.'
    }
    $second=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7dRecipientFlagsReview.ps1') @opts
    [void](Assert-OPA265BW4k7eExactReview -Review $second)
    $compare=@('SuiteId','TestId','OriginalSourceEntryId','VerifiedDecisionSha256',
        'RecipientCount','ToCount','CcCount','BccCount',
        'RecipientDigestSha256','UserStateDigestSha256','UnRead',
        'MapiFlags','SemanticReadAndAttachMask','SourceAttachmentCount')
    foreach($name in $compare){
        if([string]$first.$name -cne [string]$second.$name){
            throw ('BW4k7e source changed between independent read-only reviews: '+$name)
        }
    }
    if($dryRun){
        return [pscustomobject][ordered]@{
            Status='WhatIfNoSemanticSnapshotNoMove'
            SnapshotWritten=$false
            OutlookMoveExecuted=$false
            WriterPermit=$false
            ProductionReady=$false
        }
    }
    $stage='One and only standalone immutable semantic JSON write'
    if(-not $PSCmdlet.ShouldProcess($path,'Capture exact original recipient/state digests only; NO MOVE')){
        return
    }
    $record=New-OPA265BW4k7eSnapshot -Review $second
    $written=Write-OPA265BW4k7eSnapshotOnce -Snapshot $record -Review $second -Path $path
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7e.OneShotSemanticSourceCapture.1'
        Status='ExactSourceRecipientStateSnapshotCapturedNoMove'
        SuiteId=$SuiteId;TestId=$TestId
        SnapshotPath=[string]$written.SnapshotPath
        SnapshotSha256=[string]$written.SnapshotSha256
        RecipientDigestSha256=[string]$second.RecipientDigestSha256
        UserStateDigestSha256=[string]$second.UserStateDigestSha256
        SnapshotWritten=$true
        OutlookMoveExecuted=$false
        AttemptClaimWritten=$false
        JournalChanged=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='Stop;RunIndependentSnapshotVerify;NoMove'
    }
}catch{
    throw ('BW4k7e STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. Do not repeat Capture if file might exist; no Outlook Move/retry permitted.')
}
