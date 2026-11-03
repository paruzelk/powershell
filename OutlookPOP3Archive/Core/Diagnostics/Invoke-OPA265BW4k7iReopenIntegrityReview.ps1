#requires -Version 5.1
# BW4k7i: Review / Capture one immutable read-only baseline / VerifyAfterReopen.
# Outlook process is NOT restarted here. NEVER calls MailItem.Move, Save, Delete,
# nor modifies source/target PST, journal, original evidence, existing claim.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Review','Capture','VerifyAfterReopen')][string]$Mode,
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
    [string]$ExpectedProfileName='Outlook',
    [string]$ExpectedBaselineSha256='',
    [switch]$ConfirmImmutableReopenBaseline,
    [string]$ApprovalText=''
)
$ErrorActionPreference='Stop'
$requestedWhatIf=[bool]$WhatIfPreference
if($requestedWhatIf){$WhatIfPreference=$false}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4k7i requires Windows PowerShell 5.1 STA.'
}
if($Mode -ceq 'Capture' -and
   (-not $ConfirmImmutableReopenBaseline -or
    $ApprovalText -cne 'CAPTURE EXACT BW4K7I READONLY REOPEN BASELINE')){
    throw 'BW4k7i immutable pre-reopen evidence capture requires separate exact operator confirmation.'
}
if($Mode -cne 'Capture' -and ($ConfirmImmutableReopenBaseline -or $ApprovalText)){
    throw 'BW4k7i Review/Verify cannot accept baseline capture approval.'
}
if($Mode -ceq 'VerifyAfterReopen'){
    if($ExpectedBaselineSha256 -cnotmatch '^[a-f0-9]{64}$' -or $requestedWhatIf){
        throw 'BW4k7i VerifyAfterReopen requires independently pinned immutable baseline SHA256 and no WhatIf.'
    }
}elseif($ExpectedBaselineSha256){
    throw 'BW4k7i only VerifyAfterReopen accepts pre-existing baseline SHA256.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4k7iReopenIntegrity265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$stage='Pin exact original source, Claim and already verified archived destination'
try{
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       $ExpectedPlanSha256 -cne '6464f562eec08082d1db7781281e3cb0a4efd5264f1c2197ab9f14aedfb74f63' -or
       $ExpectedFiveEvidenceSetSha256 -cne 'ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3' -or
       $ExpectedSourceEvidenceSha256 -cne '0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0' -or
       $ExpectedDecisionSha256 -cne '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6' -or
       $ExpectedSemanticSnapshotSha256 -cne 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac' -or
       $ExpectedClaimSha256 -cne '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c' -or
       $ExpectedDestinationEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B24002000' -or
       $ExpectedDestinationFolderEntryId -cne '00000000D3E190022DF61241BBDE594AD46A661B82800000' -or
       $ExpectedProfileName -cne 'Outlook'){
        throw 'BW4k7i immutable original identity/Claim/policy hashes changed.'
    }
    $path=Get-OPA265BW4k7iBaselinePath -SuiteId $SuiteId -TestId $TestId
    if($Mode -ceq 'Capture' -and [IO.File]::Exists($path)){
        throw 'BW4k7i immutable baseline already exists: NEVER overwrite or rebaseline.'
    }
    $prior=$null
    if($Mode -ceq 'VerifyAfterReopen'){
        $prior=Read-OPA265BW4k7iBaselineVerified -ExpectedBaselineSha256 $ExpectedBaselineSha256
    }
    $stage='Verify current OUTLOOK.EXE identity before full independent archived mail audits'
    $processBefore=Get-OPA265BW4k7iProcessIdentity
    if($Mode -ceq 'VerifyAfterReopen' -and
       [long]$processBefore.StartUtcTicks -le [long]$prior.OriginalOutlookProcessStartUtcTicks){
        throw 'BW4k7i STOP: Outlook process has not been fully restarted after baseline capture.'
    }
    $a=@{
        SuiteId=$SuiteId;TestId=$TestId
        ExpectedPlanSha256=$ExpectedPlanSha256
        ExpectedFiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        ExpectedSourceEvidenceSha256=$ExpectedSourceEvidenceSha256
        ExpectedDecisionSha256=$ExpectedDecisionSha256
        ExpectedSemanticSnapshotSha256=$ExpectedSemanticSnapshotSha256
        ExpectedClaimSha256=$ExpectedClaimSha256
        ExpectedDestinationEntryId=$ExpectedDestinationEntryId
        ExpectedDestinationFolderEntryId=$ExpectedDestinationFolderEntryId
        SourcePst=$SourcePst;DestinationPst=$DestinationPst
        ExpectedProfileName=$ExpectedProfileName
    }
    $stage='Repeat full BW4k7g postmove audit, no Claim and no Move'
    $audit=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7gPostMoveReadOnly.ps1') @a
    $stage='Repeat BW4k7h full read-only raw MAPIFlags attribution'
    $attrib=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4k7hPostMoveFlagReview.ps1') @a
    [void](Assert-OPA265BW4k7iExactPriorAudit -Audit $audit -Attribution $attrib)
    $processAfter=Get-OPA265BW4k7iProcessIdentity
    if([int]$processBefore.ProcessId -ne [int]$processAfter.ProcessId -or
       [long]$processBefore.StartUtcTicks -ne [long]$processAfter.StartUtcTicks){
        throw 'BW4k7i OUTLOOK.EXE changed during independent evidence reads.'
    }
    $baseline=New-OPA265BW4k7iBaseline -Audit $audit -Attribution $attrib -OutlookProcess $processAfter
    [void](Assert-OPA265BW4k7iBaseline -Baseline $baseline)
    $stage='Independent SHA-256 check of original Claim after all Outlook reads'
    $null=Read-OPA265BW4k7gClaimVerified -ExpectedClaimSha256 $ExpectedClaimSha256
    [void](Assert-OPA265BW4k7HistoricCompletedMoves -SuiteId $SuiteId)
    if($Mode -ceq 'VerifyAfterReopen'){
        $stage='Compare immutable pre-reopen baseline to reopened independent content/recipient/state evidence'
        $decision=Compare-OPA265BW4k7iAfterReopen -Baseline $prior -Reopened $baseline -ReopenedProcess $processAfter
        $stored=Read-OPA265BW4k7iBaselineVerified -ExpectedBaselineSha256 $ExpectedBaselineSha256
        if([string]$stored.DestinationUserStateSha256 -cne [string]$prior.DestinationUserStateSha256){
            throw 'BW4k7i immutable evidence changed during post-restart audit.'
        }
        $decision | Add-Member -NotePropertyName VerifiedImmutableBaselineSha256 -NotePropertyValue $ExpectedBaselineSha256
        return $decision
    }
    if($Mode -ceq 'Review' -or $requestedWhatIf){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7i.PreReopenReadOnlyReview.1'
            Status=$(if($requestedWhatIf){'WhatIfNoBaselineFileOrOutlookWrite'}
                else{'ExactArchiveStateReadyForImmutableReopenBaselineNoWrite'})
            SuiteId=$SuiteId;TestId=$TestId
            SourceMessageIdMatches=0;DestinationMessageIdMatches=1
            DestinationEntryId=$ExpectedDestinationEntryId
            DestinationMapiFlags=17
            DifferenceMapiFlagsXorHex='0x00010002'
            MapiUnmodifiedBit0x2='DocumentedStorageModificationStateCleared'
            MapiUnspecifiedBit0x10000='UnclassifiedRemainsBlocked'
            OutlookProcessId=[int]$processAfter.ProcessId
            OutlookProcessStartUtcTicks=[long]$processAfter.StartUtcTicks
            ExistingBaselinePresent=[IO.File]::Exists($path)
            BaselineWritten=$false;OutlookMoveExecuted=$false
            UnknownFlagWaived=$false;ProductionReady=$false
            AutomaticRetryAllowed=$false
        }
    }
    $stage='Operator-approved one-time write of evidence JSON only (no Outlook/PST change)'
    if(-not $PSCmdlet.ShouldProcess(('New immutable evidence file '+$path),
        'Capture read-only Outlook PST reopening baseline with FileMode.CreateNew and Flush(true)')){
        return [pscustomobject][ordered]@{
            Status='WhatIfNoBaselineFileOrOutlookWrite'
            BaselineWritten=$false;OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
    }
    $written=Write-OPA265BW4k7iBaselineOnce -Baseline $baseline
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7i.PreReopenImmutableEvidenceCapture.1'
        Status='ImmutablePreReopenReadOnlyBaselineCapturedNoOutlookMutation'
        SuiteId=$SuiteId;TestId=$TestId
        BaselinePath=[string]$written.BaselinePath
        BaselineSha256=[string]$written.BaselineSha256
        OriginalOutlookProcessId=[int]$processAfter.ProcessId
        OriginalOutlookProcessStartUtcTicks=[long]$processAfter.StartUtcTicks
        SourceMessageIdMatches=0;DestinationMessageIdMatches=1
        DestinationMapiFlags=17
        ChangedMapiFlagsXorHex='0x00010002'
        UnknownFlag0x10000StillBlocked=$true
        BaselineWritten=$true
        ExistingClaimRewritten=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='CloseOutlookCompletely;ReopenOutlookSameProfile;InvokeVerifyAfterReopenWithBaselineSha256'
    }
}catch{
    throw ('BW4k7i STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No MailItem.Move/Claim/journal modifications. NEVER RETRY the original Move.')
}
