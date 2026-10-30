#requires -Version 5.1
# BW4h2: SourceReview/SourceCapture write-once evidence BEFORE a future Move;
# DestinationCompare is strictly READ ONLY after the independently permitted Move.
# Never use a previous TestId to reissue Move or backfill a missing source snapshot.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('SourceReview','SourceCapture','DestinationCompare')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedProfileName,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$SourceFolderEntryId,
    [Parameter(Mandatory=$true)][string]$SourceEntryId,
    [Parameter(Mandatory=$true)][string]$ExpectedInternetMessageId,
    [Parameter(Mandatory=$true)][string]$ExpectedSearchKeySha256,
    [Parameter(Mandatory=$true)][string]$ExpectedContentFingerprintSha256,
    [string]$DestinationPst='',
    [string]$DestinationFolderEntryId='',
    [string]$DestinationEntryId='',
    [string]$ExpectedSourceEvidenceSha256='',
    [string]$HistoryRoot=([IO.Path]::GetTempPath()),
    [ValidateRange(1,512)][int]$MaxHistoryRuns=256,
    [ValidateRange(1,5000)][int]$MaxFolderItems=1000,
    [switch]$ConfirmWriteOnceEvidence
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
    throw 'BW4h2 requires native Windows PowerShell 5.1 STA.'
}
if(($Mode -ceq 'SourceCapture') -ne [bool]$ConfirmWriteOnceEvidence){
    throw 'BW4h2 SourceCapture requires -ConfirmWriteOnceEvidence; other modes refuse it.'
}
if($TestId -cnotmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' -or
    $ExpectedInternetMessageId.Length -gt 512 -or
    $ExpectedInternetMessageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$' -or
    $ExpectedSearchKeySha256 -cnotmatch '^[a-f0-9]{64}$' -or
    $ExpectedContentFingerprintSha256 -cnotmatch '^[a-f0-9]{64}$'){
    throw 'BW4h2 requires exact fresh TestId and previously pinned MAPI identities.'
}
if($Mode -ceq 'DestinationCompare'){
    if($ExpectedSourceEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace($DestinationPst) -or
        [string]::IsNullOrWhiteSpace($DestinationFolderEntryId) -or
        [string]::IsNullOrWhiteSpace($DestinationEntryId)) {
        throw 'BW4h2 compare requires independently pinned source evidence SHA256 and exact moved destination.'
    }
} elseif($DestinationPst -or $DestinationFolderEntryId -or $DestinationEntryId -or $ExpectedSourceEvidenceSha256){
    throw 'BW4h2 pre-Move source modes refuse unrelated destination / retrospective pins.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4h1PostMoveFieldDrift265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4hIndependentReconciliation265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4gOneShotPermit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4h2DurableFiveFieldEvidence265.ps1')
$stage='Check exact independent historical BW3a evidence and claim'
$app=$null;$ns=$null
try {
    $evidencePath=Get-OPA265BW4h2EvidencePath -TestId $TestId
    $claimPath=Get-OPA265BW4gClaimPath -TestId $TestId
    if($Mode -cne 'DestinationCompare' -and [IO.File]::Exists($claimPath)){
        throw 'BW4h2 cannot take a source-before-Move snapshot after any one-shot claim exists.'
    }
    $hist=& (Join-Path $PSScriptRoot 'Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode Archive -Review
    if(-not [bool]$hist.SevenHistoricalEvidenceHashesUnchanged -or
        [int]$hist.HistoricJournalEventCount -ne 1 -or
        [string]$hist.HistoricJournalPhase -cne 'Intent' -or
        [bool]$hist.WorkerDispatchAllowed) {
        throw 'BW4h2 original seven historical seals / one Intent failed closed.'
    }
    $stage='Attach existing Outlook session'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if($null -eq $app){throw 'BW4h2 requires already running Outlook.'}
    $ns=$app.GetNamespace('MAPI')
    if([string]$ns.CurrentProfileName -cne $ExpectedProfileName){
        throw 'BW4h2 active Outlook profile mismatch.'
    }
    if($Mode -cne 'DestinationCompare'){
        $stage='Read exact new source fixture by two independent Outlook paths'
        $pair=Get-OPA265BW4cDualReadback -Namespace $ns -SourcePst $SourcePst -FolderEntryId $SourceFolderEntryId -CandidateEntryId $SourceEntryId -UseTargetedMessageIdReadOnly -MaxFolderItems $MaxFolderItems
        if($pair.CandidateMatches -ne 1 -or $pair.FolderItemsScanned -ne 0){
            throw 'BW4h2 no unbounded source folder scan permitted.'
        }
        foreach($w in @($pair.Primary,$pair.Independent)){
            if(-not [bool]$w.IsExactOperatorFixture -or
                [string]$w.ObservedOperatorTestId -cne $TestId -or
                [string]$w.InternetMessageId -cne $ExpectedInternetMessageId -or
                [string]$w.SearchKeySha256 -cne $ExpectedSearchKeySha256 -or
                [string]$w.ContentSha256 -cne $ExpectedContentFingerprintSha256){
                throw 'BW4h2 exact source fixture/pins differ from independent BW4c witness.'
            }
        }
        $src=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
        $mail=$ns.GetItemFromID($SourceEntryId,[string]$src.StoreId)
        $evidence=Get-OPA265BW4h2FieldEvidence -Mail $mail -TestId $TestId -ProfileName $ExpectedProfileName -PstPath $SourcePst -StoreId ([string]$src.StoreId) -FolderEntryId $SourceFolderEntryId -ItemEntryId $SourceEntryId
        if([string]$evidence.ContentFingerprintSha256 -cne $ExpectedContentFingerprintSha256){
            throw 'BW4h2 source field evidence changed after two original MAPI reads.'
        }
        $stage='Recheck historic original before optional one-shot evidence write'
        $h2=& (Join-Path $PSScriptRoot 'Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode Archive -Review
        if(-not $h2.SevenHistoricalEvidenceHashesUnchanged -or
            $h2.HistoricJournalPhase -cne 'Intent'){throw 'BW4h2 historical seals changed.'}
        if($Mode -ceq 'SourceCapture'){
            $stage='Commit one immutable per-user source field evidence BEFORE future Move'
            if([IO.File]::Exists($evidencePath) -or [IO.File]::Exists($claimPath)){
                throw 'BW4h2 source evidence or previous Move claim already exists. NEVER OVERWRITE.'
            }
            $written=Write-OPA265BW4h2OnceEvidence -Evidence $evidence -TestId $TestId -EvidencePath $evidencePath
            $hash=(Get-FileHash -LiteralPath $written -Algorithm SHA256).Hash.ToLowerInvariant()
        }else{
            $written=''
            $hash=''
        }
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4h2.SourceEvidenceReadOnlyOrOnce.1'
            Status=$(if($Mode -ceq 'SourceCapture'){'ImmutablePreMoveFiveFieldEvidenceCreated'}else{'SourceFiveFieldPreflightPassedNoWrite'})
            TestId=$TestId
            SourceEntryId=$SourceEntryId
            InternetMessageId=$evidence.InternetMessageId
            SourceSize=[long]$evidence.Size
            SubjectUtf8Sha256=$evidence.SubjectUtf8Sha256
            SenderEmailAddressUtf8Sha256=$evidence.SenderEmailAddressUtf8Sha256
            BodyUtf8Sha256=$evidence.BodyUtf8Sha256
            ReceivedUtcTicks=[long]$evidence.ReceivedUtcTicks
            ReceivedUtcTicksSha256=$evidence.ReceivedUtcTicksSha256
            OriginalCompositeSha256=$evidence.ContentFingerprintSha256
            EvidencePath=$written
            EvidenceSha256=$hash
            SevenHistoricalEvidenceHashesUnchanged=$true
            HistoricJournalEventCount=1
            HistoricJournalPhase='Intent'
            SourcePstModified=$false
            MailItemMoveExecuted=$false
            CanRetryMove=$false
            ProductionReady=$false
            NextAction=$(if($Mode -ceq 'SourceCapture'){'PreserveEvidenceHashOutsidePst;LaterExplicitNewFixtureMoveOnly'}else{'ToPersistPreMoveWitnessUseSourceCaptureOnce'})
        }
        return
    }
    $stage='Read separately pinned immutable source evidence and original Move claim'
    if(-not [IO.File]::Exists($evidencePath) -or
        ([IO.File]::GetAttributes($evidencePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4h2 no valid PRE-MOVE evidence file. Do not retroactively invent one.'
    }
    $length=(Get-Item -LiteralPath $evidencePath).Length
    if($length -lt 128 -or $length -gt 16384){
        throw 'BW4h2 original field witness size outside 128..16384.'
    }
    $shaBefore=(Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($shaBefore -cne $ExpectedSourceEvidenceSha256){
        throw 'BW4h2 original source evidence differs from independently recorded SHA256.'
    }
    $before=Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    [void](Assert-OPA265BW4h2Evidence -Evidence $before -TestId $TestId)
    if([string]$before.PstPath -cne [IO.Path]::GetFullPath($SourcePst) -or
        [string]$before.ItemEntryId -cne $SourceEntryId -or
        [string]$before.FolderEntryId -cne $SourceFolderEntryId -or
        [string]$before.ProfileName -cne $ExpectedProfileName -or
        [string]$before.InternetMessageId -cne $ExpectedInternetMessageId -or
        [string]$before.SearchKeySha256 -cne $ExpectedSearchKeySha256 -or
        [string]$before.ContentFingerprintSha256 -cne $ExpectedContentFingerprintSha256){
        throw 'BW4h2 source evidence does not exactly match the pre-Move pins.'
    }
    if(-not [IO.File]::Exists($claimPath)){throw 'BW4h2 original one-shot Move claim missing. NEVER RETRY.'}
    $claimBefore=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $claim=Get-Content -LiteralPath $claimPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    [void](Assert-OPA265BW4hClaim -Claim $claim -TestId $TestId -SourcePst $SourcePst -DestinationPst $DestinationPst -SourceEntryId $SourceEntryId -DestinationFolderEntryId $DestinationFolderEntryId -InternetMessageId $ExpectedInternetMessageId)
    $stage='Rerun complete independent BW4h source-zero/destination-one, claim/history read-only audit'
    $recheck=& (Join-Path $PSScriptRoot 'Test-OPA265BW4hIndependentReconciliationReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -SourceFolderEntryId $SourceFolderEntryId -OriginalSourceEntryId $SourceEntryId -DestinationPst $DestinationPst -DestinationFolderEntryId $DestinationFolderEntryId -DestinationEntryId $DestinationEntryId -ExpectedProfileName $ExpectedProfileName -TestId $TestId -ExpectedInternetMessageId $ExpectedInternetMessageId -ExpectedSearchKeySha256 $ExpectedSearchKeySha256 -ExpectedContentFingerprintSha256 $ExpectedContentFingerprintSha256 -HistoryRoot $HistoryRoot -MaxHistoryRuns $MaxHistoryRuns -Review
    if($recheck.Status -cnotin @('MoveObservedButMAPIFieldFingerprintDriftNeedsManualReview',
            'IndependentOutlookReadOnlyMoveReconciled') -or
        [int]$recheck.SourceMessageIdMatches -ne 0 -or
        [int]$recheck.DestinationMessageIdMatches -ne 1 -or
        [int]$recheck.DestinationFolderItemCount -ne 1 -or
        -not [bool]$recheck.ClaimUnchanged -or
        -not [bool]$recheck.HistoricalEvidenceUnchanged -or
        -not [bool]$recheck.SevenHistoricalEvidenceHashesUnchanged -or
        -not [bool]$recheck.InternetMessageIdMatches -or
        -not [bool]$recheck.SearchKeySha256Matches -or
        -not [bool]$recheck.FixtureTestIdMatches){
        throw 'BW4h2 independent BW4h reconciliation/historical claim gate failed.'
    }
    $stage='Independently inspect destination store, item and five fields'
    $hit=0;$destStore=$null
    $count=[int]$ns.Stores.Count
    if($count -lt 2 -or $count -gt 128){throw 'BW4h2 unsafe number of stores.'}
    for($i=1;$i -le $count;$i++){
        $s=$ns.Stores.Item($i)
        $file=''
        try{$file=[string]$s.FilePath}catch{}
        if($file -and [string]::Equals([IO.Path]::GetFullPath($file),
            [IO.Path]::GetFullPath($DestinationPst),
            [StringComparison]::OrdinalIgnoreCase)){
            $hit++;$destStore=$s
        }
    }
    if($hit -ne 1 -or $null -eq $destStore){throw 'BW4h2 target PST not uniquely mounted.'}
    $mail=$ns.GetItemFromID($DestinationEntryId,[string]$destStore.StoreID)
    $after=Get-OPA265BW4h2FieldEvidence -Mail $mail -TestId $TestId -ProfileName $ExpectedProfileName -PstPath $DestinationPst -StoreId ([string]$destStore.StoreID) -FolderEntryId $DestinationFolderEntryId -ItemEntryId $DestinationEntryId
    if([string]$after.ContentFingerprintSha256 -cne [string]$recheck.ObservedDestinationContentFingerprintSha256 -or
        [string]$after.SearchKeySha256 -cne $ExpectedSearchKeySha256) {
        throw 'BW4h2 destination fields drifted since independent BW4h read-only gate.'
    }
    $comparison=Compare-OPA265BW4h2FieldEvidence -Before $before -After $after
    $stage='Recheck original evidence and claim hashes after field comparison'
    $shaAfter=(Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $claimAfter=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($shaAfter -cne $shaBefore -or $claimAfter -cne $claimBefore){
        throw 'BW4h2 original source witness or Move claim changed during read-only compare.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4h2.IndependentFiveFieldPostMoveCompare.1'
        Status=$comparison.Status
        TestId=$TestId
        OriginalSourceEntryId=$SourceEntryId
        ConfirmedDestinationEntryId=$DestinationEntryId
        SourceMessageIdMatches=[int]$recheck.SourceMessageIdMatches
        DestinationMessageIdMatches=[int]$recheck.DestinationMessageIdMatches
        SubjectMatches=$comparison.SubjectMatches
        SenderEmailAddressMatches=$comparison.SenderEmailAddressMatches
        BodyMatches=$comparison.BodyMatches
        SizeMatches=$comparison.SizeMatches
        ReceivedUtcTicksMatches=$comparison.ReceivedUtcTicksMatches
        FourNonSizeFieldsMatch=$comparison.FourNonSizeFieldsMatch
        SourceSize=$comparison.SourceSize
        DestinationSize=$comparison.DestinationSize
        DestinationMinusSourceSize=$comparison.DestinationMinusSourceSize
        CompositeFingerprintMatches=$comparison.CompositeFingerprintMatches
        IndependentPreMoveFieldEvidenceAvailable=$true
        SourceFieldEvidencePath=$evidencePath
        SourceFieldEvidenceSha256=$shaAfter
        ImmutableOneShotClaimSha256=$claimAfter
        OriginalHistoricIntentUnchanged=$true
        SevenHistoricalEvidenceHashesUnchanged=$true
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        MailItemMoveExecuted=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
        NextAction='PreserveImmutableWitnessAndClaim;ManualReviewOnly;NeverRetryMove'
    }
} catch {
    throw ('BW4h2 STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Outlook Move, source PST mutation, original historical journal write or automatic retry.')
} finally {
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
