#requires -Version 5.1
# BW4i EXACT known 841545... fixture only.
# Review = read only, Accept = write ONE separate decision, Verify = read only.
# Never MailItem.Move, edit historic journal, or change existing BW4g claim.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Review','Accept','Verify')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedProfileName,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedSourceEvidenceSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedMoveClaimSha256,
    [string]$ExpectedDecisionSha256='',
    [string]$HistoryRoot=([IO.Path]::GetTempPath()),
    [ValidateRange(1,512)][int]$MaxHistoryRuns=256,
    [switch]$ConfirmExactSizeDrift
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4i requires Windows PowerShell 5.1 STA.'
}
if (($Mode -ceq 'Accept') -ne [bool]$ConfirmExactSizeDrift) {
    throw 'BW4i only Accept can specify -ConfirmExactSizeDrift; all other modes refuse confirmation.'
}
if (($Mode -ceq 'Verify') -ne (-not [string]::IsNullOrWhiteSpace($ExpectedDecisionSha256))) {
    throw 'BW4i Verify requires independently recorded -ExpectedDecisionSha256; other modes forbid it.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4h2DurableFiveFieldEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4hIndependentReconciliation265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4iExactSizeDecision265.ps1')
$p=Get-OPA265BW4iPins
$stage='Validate strictly pinned operator inputs'
try {
    if ($TestId -cne $p.TestId -or
        $ExpectedSourceEvidenceSha256 -cne $p.SourceEvidenceSha256 -or
        $ExpectedMoveClaimSha256 -cne $p.MoveClaimSha256 -or
        $ExpectedProfileName -cne 'Outlook' -or
        -not [IO.Path]::IsPathRooted($SourcePst) -or
        $SourcePst.StartsWith('\\',[StringComparison]::Ordinal) -or
        [IO.Path]::GetExtension($SourcePst) -cne '.pst') {
        throw 'BW4i pinned one known synthetic fixture, profile and independently recorded SHA only.'
    }
    if ($Mode -ceq 'Verify' -and $ExpectedDecisionSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'BW4i Verify requires exact lowercase SHA256 pin.'
    }
    $sourceEvidencePath=Get-OPA265BW4h2EvidencePath -TestId $p.TestId
    $decisionPath=Get-OPA265BW4iDecisionPath -TestId $p.TestId
    $claimPath=Join-Path (Join-Path $env:LOCALAPPDATA 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$p.TestId+'.json')
    foreach($path in @($sourceEvidencePath,$claimPath,$SourcePst)){
        if (-not [IO.File]::Exists($path) -or
            (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw ('BW4i source/claim/PST missing or symlinked: '+$path)
        }
    }
    $evidenceBefore=(Get-FileHash -LiteralPath $sourceEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $claimBefore=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($evidenceBefore -cne $p.SourceEvidenceSha256 -or
        $claimBefore -cne $p.MoveClaimSha256) {
        throw 'BW4i original BW4h2 source or BW4g claim HASH CHANGED.'
    }
    $sourceEvidence=Get-Content -LiteralPath $sourceEvidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    [void](Assert-OPA265BW4h2Evidence -Evidence $sourceEvidence -TestId $p.TestId)
    if ([string]$sourceEvidence.PstPath -cne [IO.Path]::GetFullPath($SourcePst) -or
        [string]$sourceEvidence.ItemEntryId -cne $p.SourceEntryId -or
        [string]$sourceEvidence.InternetMessageId -cne $p.InternetMessageId -or
        [string]$sourceEvidence.ContentFingerprintSha256 -cne $p.OriginalCompositeSha256 -or
        [long]$sourceEvidence.Size -ne $p.SourceSize -or
        [string]$sourceEvidence.ProfileName -cne $ExpectedProfileName) {
        throw 'BW4i source evidence contents do not match unique previously observed fixture.'
    }
    $destinationPst=Join-Path ([IO.Path]::GetDirectoryName($SourcePst)) ('OPA265-BW4g-'+([guid]$p.TestId).ToString('N')+'.pst')
    if (-not [IO.File]::Exists($destinationPst) -or
        (([IO.File]::GetAttributes($destinationPst) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'BW4i destination PST unavailable/symlinked.'
    }
    $stage='Rerun full BW4h2 read-only Outlook source-zero destination-one and original historic journal audit'
    $comparison=& (Join-Path $PSScriptRoot 'Invoke-OPA265BW4h2DurableFieldEvidence.ps1') -Mode DestinationCompare -RunId $p.RunId -ExpectedJournalSha256 $p.OriginalJournalSha256 -SourcePst $SourcePst -ExpectedProfileName $ExpectedProfileName -TestId $TestId -SourceFolderEntryId ([string]$sourceEvidence.FolderEntryId) -SourceEntryId $p.SourceEntryId -ExpectedInternetMessageId $p.InternetMessageId -ExpectedSearchKeySha256 ([string]$sourceEvidence.SearchKeySha256) -ExpectedContentFingerprintSha256 $p.OriginalCompositeSha256 -DestinationPst $destinationPst -DestinationFolderEntryId $p.DestinationFolderEntryId -DestinationEntryId $p.DestinationEntryId -ExpectedSourceEvidenceSha256 $p.SourceEvidenceSha256 -HistoryRoot $HistoryRoot -MaxHistoryRuns $MaxHistoryRuns
    [void](Assert-OPA265BW4iComparison -Comparison $comparison)
    $stage='Validate stable exact historical source/claim hashes after independent Outlook check'
    $evidenceAfter=(Get-FileHash -LiteralPath $sourceEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $claimAfter=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($evidenceAfter -cne $evidenceBefore -or $claimAfter -cne $claimBefore) {
        throw 'BW4i immutable old evidence or one-shot claim changed during read-only check.'
    }
    $existingDecision=[IO.File]::Exists($decisionPath)
    $status='ExactDisposableSizeDriftReviewedNoDecisionWritten'
    $decisionSha=''
    if($Mode -ceq 'Accept'){
        $stage='Create ONE immutable manual decision record, never edit original historical journal'
        if($existingDecision){throw 'BW4i decision already exists; CREATE-NEW only, NEVER OVERWRITE.'}
        $newDecision=New-OPA265BW4iDecision -Comparison $comparison
        $written=Write-OPA265BW4iDecisionOnce -Decision $newDecision -DecisionPath $decisionPath
        $decisionSha=(Get-FileHash -LiteralPath $written -Algorithm SHA256).Hash.ToLowerInvariant()
        $status='ExactDisposableSizeDriftManuallyAcknowledgedNoWriterPermit'
    } elseif($Mode -ceq 'Verify') {
        $stage='Verify external independent acceptance record SHA and exact immutable schema'
        if(-not $existingDecision){throw 'BW4i manual decision missing.'}
        if((([IO.File]::GetAttributes($decisionPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'BW4i decision is a symlink.'
        }
        $info=Get-Item -LiteralPath $decisionPath -Force
        if($info.Length -lt 128 -or $info.Length -gt 16384){
            throw 'BW4i decision size invalid.'
        }
        $decisionSha=(Get-FileHash -LiteralPath $decisionPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($decisionSha -cne $ExpectedDecisionSha256){throw 'BW4i independently pinned manual decision SHA256 differs.'}
        $decision=Get-Content -LiteralPath $decisionPath -Encoding UTF8 -Raw | ConvertFrom-Json
        [void](Assert-OPA265BW4iDecision -Decision $decision)
        $finalHash=(Get-FileHash -LiteralPath $decisionPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($finalHash -cne $decisionSha){throw 'BW4i decision changed during verification.'}
        $status='ExactDisposableManualDecisionIndependentlyReverifiedNoWriterPermit'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4i.ExactSizeDriftOperatorDecision.1'
        Status=$status
        Mode=$Mode
        TestId=$p.TestId
        OriginalSourceEntryId=$p.SourceEntryId
        DestinationEntryId=$p.DestinationEntryId
        SourceMessageIdMatches=[int]$comparison.SourceMessageIdMatches
        DestinationMessageIdMatches=[int]$comparison.DestinationMessageIdMatches
        SubjectMatches=[bool]$comparison.SubjectMatches
        SenderEmailAddressMatches=[bool]$comparison.SenderEmailAddressMatches
        BodyMatches=[bool]$comparison.BodyMatches
        ReceivedUtcTicksMatches=[bool]$comparison.ReceivedUtcTicksMatches
        SourceSize=[long]$comparison.SourceSize
        DestinationSize=[long]$comparison.DestinationSize
        DestinationMinusSourceSize=[long]$comparison.DestinationMinusSourceSize
        OriginalSourceEvidenceSha256=$evidenceAfter
        OriginalMoveClaimSha256=$claimAfter
        DecisionPath=$(if($Mode -ceq 'Review'){''}else{$decisionPath})
        DecisionSha256=$decisionSha
        ManualDecisionAlreadyExists=$existingDecision
        HistoricalSevenHashesUnchanged=$true
        OriginalHistoricalJournalUnchanged=$true
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        MailItemMoveExecuted=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
        NextAction=$(if($Mode -ceq 'Review'){'ExplicitAcceptCreatesOneSeparateDecisionNoOriginalJournalChanges'}else{'PreserveDecisionAndEvidence;NeverRetryMove;NoProductionIntegration'})
    }
} catch {
    throw ('BW4i STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No MailItem.Move, original journal write, attempt claim modification, or automatic retry.')
}
