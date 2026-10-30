#requires -Version 5.1
# BW4h: read-only reconciliation of ONE completed BW4g1 disposable Move.
# NEVER invoke Outlook MailItem.Move, create a claim or write a journal.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [Parameter(Mandatory=$true)][string]$SourceFolderEntryId,
    [Parameter(Mandatory=$true)][string]$OriginalSourceEntryId,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [Parameter(Mandatory=$true)][string]$DestinationFolderEntryId,
    [Parameter(Mandatory=$true)][string]$DestinationEntryId,
    [Parameter(Mandatory=$true)][string]$ExpectedProfileName,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$ExpectedInternetMessageId,
    [Parameter(Mandatory=$true)][string]$ExpectedSearchKeySha256,
    [Parameter(Mandatory=$true)][string]$ExpectedContentFingerprintSha256,
    [string]$HistoryRoot=([IO.Path]::GetTempPath()),
    [ValidateRange(1,512)][int]$MaxHistoryRuns=256,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if (-not $Review -or $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4h requires explicit -Review under native Windows PowerShell 5.1 STA.'
}
foreach($file in @(
    '../Worker/Live3SyntheticScope.ps1',
    '../Worker/BW3OneShotProtocol265.ps1',
    '../Worker/BW3bIndependentAudit265.ps1',
    '../Worker/BW3dSyntheticSizeEvidence265.ps1',
    '../Worker/BW3eSyntheticBodyTailEvidence265.ps1',
    '../Worker/BW3gManualSizeAcceptance265.ps1',
    '../Worker/BW3hIndependentEvidenceChain265.ps1',
    '../Worker/BW3iJournalResolutionPreflight265.ps1',
    '../Worker/BW3jResolutionDesign265.ps1',
    '../Worker/WorkerProtocol.ps1',
    '../Archive/OperationJournal.ps1',
    '../Worker/BW4aHistoricalIntentIsolation265.ps1',
    '../Worker/BW4aHistoricalFenceReadOnly265.ps1',
    '../Worker/BW4cOutlookReadOnlyCapture265.ps1',
    '../Worker/BW4dHistoricalReplayAudit265.ps1',
    '../Worker/BW4gOneShotPermit265.ps1',
    '../Worker/BW4hIndependentReconciliation265.ps1')) {
    . (Join-Path $PSScriptRoot $file)
}
$stage='Validate operator inputs and durable BW4g1 one-shot claim'
$app=$null;$ns=$null
try {
    $guid=[guid]::Empty
    if (-not [guid]::TryParse($TestId,[ref]$guid) -or
        $guid -eq [guid]::Empty -or $TestId -cne $guid.ToString('D') -or
        [string]$ExpectedSearchKeySha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$ExpectedContentFingerprintSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ExpectedInternetMessageId.Length -gt 512 -or
        $ExpectedInternetMessageId -cnotmatch '^<[A-Za-z0-9.!#$%&*+/=?^_{}|~-]+@[A-Za-z0-9.-]+>$') {
        throw 'BW4h requires strict pinned operator TestId, MessageId and SHA256 values.'
    }
    if ([string]::IsNullOrWhiteSpace($SourceFolderEntryId) -or
        [string]::IsNullOrWhiteSpace($OriginalSourceEntryId) -or
        [string]::IsNullOrWhiteSpace($DestinationFolderEntryId) -or
        [string]::IsNullOrWhiteSpace($DestinationEntryId) -or
        $OriginalSourceEntryId -ceq $DestinationEntryId) {
        throw 'BW4h requires distinct complete original and moved EntryIDs and pinned folders.'
    }
    if (-not [IO.File]::Exists($DestinationPst) -or
        ([IO.File]::GetAttributes($DestinationPst) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        -not [IO.File]::Exists($SourcePst) -or
        ([IO.File]::GetAttributes($SourcePst) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW4h requires existing regular local source and destination PST files.'
    }
    $claimPath=Get-OPA265BW4gClaimPath -TestId $TestId
    if (-not [IO.File]::Exists($claimPath) -or
        ([IO.File]::GetAttributes($claimPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW4h: irreversible BW4g claim missing or symlinked; NEVER RETRY.'
    }
    $claimInfo=Get-Item -LiteralPath $claimPath -Force
    if ($claimInfo.Length -lt 64 -or $claimInfo.Length -gt 16384) {
        throw 'BW4h: suspicious or oversized one-shot claim.'
    }
    $claimBefore=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $claim=Get-Content -LiteralPath $claimPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    [void](Assert-OPA265BW4hClaim -Claim $claim -TestId $TestId -SourcePst $SourcePst -DestinationPst $DestinationPst -SourceEntryId $OriginalSourceEntryId -DestinationFolderEntryId $DestinationFolderEntryId -InternetMessageId $ExpectedInternetMessageId)
    $stage='Audit unchanged historical original BW3a intent and all visible journals'
    $historyBefore=Get-OPA265BW4dHistoryCatalog -HistoryRoot $HistoryRoot -MaxRunDirectories $MaxHistoryRuns
    $historicPre=Invoke-OPA265BW4aHistoricalFenceReview -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode Archive
    if (-not $historicPre.SevenHistoricalEvidenceHashesUnchanged -or
        $historicPre.HistoricJournalEventCount -ne 1 -or
        $historicPre.HistoricJournalPhase -cne 'Intent') {
        throw 'BW4h: immutable historical BW3a source evidence did not pass.'
    }
    $stage='Attach already-running Outlook and resolve source POP3 store and distinct destination PST'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'BW4h requires existing Outlook session.' }
    $ns=$app.GetNamespace('MAPI')
    if ([string]$ns.CurrentProfileName -cne $ExpectedProfileName) {
        throw 'BW4h: active profile does not match pinned Outlook profile.'
    }
    $src=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    $destStore=$null;$destHits=0
    if ([int]$ns.Stores.Count -lt 2 -or [int]$ns.Stores.Count -gt 128) {
        throw 'BW4h: Outlook store cardinality outside guard.'
    }
    for($i=1;$i -le [int]$ns.Stores.Count;$i++){
        $s=$ns.Stores.Item($i)
        $p=''
        try {$p=[string]$s.FilePath} catch {}
        if (-not [string]::IsNullOrWhiteSpace($p) -and
            [string]::Equals([IO.Path]::GetFullPath($p),
                [IO.Path]::GetFullPath($DestinationPst),
                [StringComparison]::OrdinalIgnoreCase)) {
            $destHits++;$destStore=$s
        }
    }
    if ($destHits -ne 1 -or $null -eq $destStore -or
        [string]::IsNullOrWhiteSpace([string]$destStore.StoreID) -or
        (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$src.StoreId) -Expected ([string]$destStore.StoreID))) {
        throw 'BW4h: source and destination Outlook PST StoreIDs not uniquely distinct.'
    }
    $stage='Read exact source Inbox using targeted MAPI InternetMessageId Restrict'
    $sourceFolder=$ns.GetFolderFromID($SourceFolderEntryId,[string]$src.StoreId)
    if ($null -eq $sourceFolder -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$sourceFolder.EntryID) -Expected $SourceFolderEntryId) -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$sourceFolder.StoreID) -Expected ([string]$src.StoreId))) {
        throw 'BW4h: pinned source Inbox folder/store mismatch.'
    }
    if ([int]$sourceFolder.Items.Count -lt 0 -or
        [int]$sourceFolder.Items.Count -gt 100000) {
        throw 'BW4h: source Inbox cardinality unsafe.'
    }
    $restriction='@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = '+[char]39+$ExpectedInternetMessageId+[char]39
    $sourceMatches=[int]$sourceFolder.Items.Restrict($restriction).Count

    $stage='Independently resolve exact pinned destination folder and unique message via two MAPI paths'
    $destFolder=$ns.GetFolderFromID($DestinationFolderEntryId,[string]$destStore.StoreID)
    $expectedFolderName='OPA265-BW4g-'+$guid.ToString('N')
    if ($null -eq $destFolder -or
        [string]$destFolder.Name -cne $expectedFolderName -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$destFolder.EntryID) -Expected $DestinationFolderEntryId) -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$destFolder.StoreID) -Expected ([string]$destStore.StoreID))) {
        throw 'BW4h: destination not pinned isolated GUID-named test folder.'
    }
    $targetFolderCount=[int]$destFolder.Items.Count
    $restricted=$destFolder.Items.Restrict($restriction)
    $destinationMatches=[int]$restricted.Count
    $actualEntryIdMatched=$false;$messageIdMatched=$false;$fixtureMatched=$false
    $searchKeyMatched=$false;$contentMatched=$false
    $observedSearchKey='';$observedContentHash='';$observedEntryId=''
    if ($destinationMatches -eq 1 -and $targetFolderCount -eq 1) {
        $direct=$ns.GetItemFromID($DestinationEntryId,[string]$destStore.StoreID)
        $secondary=$restricted.Item(1)
        $a=Get-OPA265BW4cItemWitness -Mail $direct -SourcePst ([IO.Path]::GetFullPath($DestinationPst)) -StoreId ([string]$destStore.StoreID) -FolderEntryId $DestinationFolderEntryId -CandidateEntryId $DestinationEntryId -Method PrimaryReadOnly
        $b=Get-OPA265BW4cItemWitness -Mail $secondary -SourcePst ([IO.Path]::GetFullPath($DestinationPst)) -StoreId ([string]$destStore.StoreID) -FolderEntryId $DestinationFolderEntryId -CandidateEntryId $DestinationEntryId -Method IndependentReadOnly
        $observedEntryId=[string]$a.SourceEntryId
        $actualEntryIdMatched=((Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$a.SourceEntryId) -Expected $DestinationEntryId) -and
            (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$b.SourceEntryId) -Expected $DestinationEntryId))
        foreach($field in @('InternetMessageId','SearchKeySha256','ContentSha256',
                'IsExactOperatorFixture','ObservedOperatorTestId')) {
            if ([string]$a.$field -cne [string]$b.$field) {
                throw ('BW4h: direct and filtered destination MAPI read disagree: '+$field)
            }
        }
        $messageIdMatched=([string]$a.InternetMessageId -ceq $ExpectedInternetMessageId)
        $fixtureMatched=([bool]$a.IsExactOperatorFixture -and [string]$a.ObservedOperatorTestId -ceq $TestId)
        $observedSearchKey=[string]$a.SearchKeySha256
        $observedContentHash=[string]$a.ContentSha256
        $searchKeyMatched=($observedSearchKey -ceq $ExpectedSearchKeySha256)
        $contentMatched=($observedContentHash -ceq $ExpectedContentFingerprintSha256)
    }
    $stage='Repeat independent original BW3a historical seals and journal catalog, then hash one-shot claim'
    $historicPost=Invoke-OPA265BW4aHistoricalFenceReview -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode Archive
    $historyAfter=Get-OPA265BW4dHistoryCatalog -HistoryRoot $HistoryRoot -MaxRunDirectories $MaxHistoryRuns
    $claimAfter=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $historyUnchanged=($historicPost.SevenHistoricalEvidenceHashesUnchanged -and
        $historicPost.HistoricJournalEventCount -eq 1 -and
        $historicPost.HistoricJournalPhase -ceq 'Intent' -and
        [string]$historyBefore.EvidenceSnapshotSha256 -ceq [string]$historyAfter.EvidenceSnapshotSha256 -and
        [int]$historyBefore.RunDirectoriesScanned -eq [int]$historyAfter.RunDirectoriesScanned -and
        [int]$historyBefore.JournalsScanned -eq [int]$historyAfter.JournalsScanned -and
        [int]$historyBefore.ClaimOnlyDirectories -eq [int]$historyAfter.ClaimOnlyDirectories)
    $claimUnchanged=($claimBefore -ceq $claimAfter)
    $decision=Get-OPA265BW4hReadOnlyDecision -SourceMatches $sourceMatches -DestinationMatches $destinationMatches -DestinationFolderCount $targetFolderCount -DestinationEntryIdMatches $actualEntryIdMatched -InternetMessageIdMatches $messageIdMatched -FixtureMatches $fixtureMatched -SearchKeyMatches $searchKeyMatched -ContentFingerprintMatches $contentMatched -HistoricalEvidenceUnchanged $historyUnchanged -ClaimUnchanged $claimUnchanged
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4h.IndependentSourceDestinationOutlookReadOnly.1'
        Status=$decision.Status
        TestId=$TestId
        OriginalSourceEntryId=$OriginalSourceEntryId
        SourceFolderEntryId=$SourceFolderEntryId
        SourceMessageIdMatches=$sourceMatches
        DestinationPst=[IO.Path]::GetFullPath($DestinationPst)
        DestinationFolderEntryId=$DestinationFolderEntryId
        DestinationEntryId=$DestinationEntryId
        ObservedDestinationEntryId=$observedEntryId
        DestinationFolderItemCount=$targetFolderCount
        DestinationMessageIdMatches=$destinationMatches
        SourceAndDestinationStoresDistinct=$true
        OriginalInternetMessageId=$ExpectedInternetMessageId
        InternetMessageIdMatches=$messageIdMatched
        FixtureTestIdMatches=$fixtureMatched
        OriginalSearchKeySha256=$ExpectedSearchKeySha256
        ObservedDestinationSearchKeySha256=$observedSearchKey
        SearchKeySha256Matches=$searchKeyMatched
        OriginalContentFingerprintSha256=$ExpectedContentFingerprintSha256
        ObservedDestinationContentFingerprintSha256=$observedContentHash
        ContentFieldFingerprintSha256Matches=$contentMatched
        ClaimPath=$claimPath
        ClaimSha256Before=$claimBefore
        ClaimSha256After=$claimAfter
        ClaimUnchanged=$claimUnchanged
        HistoryEvidenceSnapshotSha256Before=$historyBefore.EvidenceSnapshotSha256
        HistoryEvidenceSnapshotSha256After=$historyAfter.EvidenceSnapshotSha256
        HistoricalEvidenceUnchanged=$historyUnchanged
        SevenHistoricalEvidenceHashesUnchanged=[bool]$historicPost.SevenHistoricalEvidenceHashesUnchanged
        HistoricalJournalEventCount=[int]$historicPost.HistoricJournalEventCount
        HistoricalJournalPhase=$historicPost.HistoricJournalPhase
        OutlookMAPIReadOnlyExecuted=$true
        OutlookMoveExecuted=$false
        MailItemsMovedByThisAudit=0
        ReadOnlyReconciliationPassed=$decision.ReadOnlyReconciliationPassed
        FullMAPIByteEqualityProven=$false
        PhysicalPstDurabilityProven=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ArchiveResumeIntegrationActivated=$false
        ProductionReady=$false
        NextAction=$(if($decision.ReadOnlyReconciliationPassed){'PreserveClaim;NoRetry;ReviewDurabilityLimits'}else{'NoRetry;ManualReviewOfNonMatchingEvidenceBeforeAnyJournalAction'})
    }
} catch {
    throw ('BW4h READ-ONLY STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No Move, PST edits, journal/claim writer or automatic retry.')
} finally {
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
