#requires -Version 5.1
# BW4h1 diagnostic-only. This does NOT make an Outlook Move or approve drift.
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
    [ValidateRange(1,4096)][int]$MaxSizeDelta=256,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if (-not $Review -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4h1 requires explicit -Review with native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4h1PostMoveFieldDrift265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
$app=$null;$ns=$null;$stage='Independent BW4h read-only historical/claim source/destination audit'
try {
    $audit=& (Join-Path $PSScriptRoot 'Test-OPA265BW4hIndependentReconciliationReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -SourceFolderEntryId $SourceFolderEntryId -OriginalSourceEntryId $OriginalSourceEntryId -DestinationPst $DestinationPst -DestinationFolderEntryId $DestinationFolderEntryId -DestinationEntryId $DestinationEntryId -ExpectedProfileName $ExpectedProfileName -TestId $TestId -ExpectedInternetMessageId $ExpectedInternetMessageId -ExpectedSearchKeySha256 $ExpectedSearchKeySha256 -ExpectedContentFingerprintSha256 $ExpectedContentFingerprintSha256 -HistoryRoot $HistoryRoot -MaxHistoryRuns $MaxHistoryRuns -Review
    if ([string]$audit.Schema -cne '2.6.5-BW4h.IndependentSourceDestinationOutlookReadOnly.1' -or
        [string]$audit.Status -cne 'MoveObservedButMAPIFieldFingerprintDriftNeedsManualReview' -or
        [int]$audit.SourceMessageIdMatches -ne 0 -or
        [int]$audit.DestinationMessageIdMatches -ne 1 -or
        [int]$audit.DestinationFolderItemCount -ne 1 -or
        $audit.SourceAndDestinationStoresDistinct -isnot [bool] -or -not $audit.SourceAndDestinationStoresDistinct -or
        $audit.InternetMessageIdMatches -isnot [bool] -or -not $audit.InternetMessageIdMatches -or
        $audit.FixtureTestIdMatches -isnot [bool] -or -not $audit.FixtureTestIdMatches -or
        $audit.SearchKeySha256Matches -isnot [bool] -or -not $audit.SearchKeySha256Matches -or
        $audit.ContentFieldFingerprintSha256Matches -isnot [bool] -or $audit.ContentFieldFingerprintSha256Matches -or
        $audit.ClaimUnchanged -isnot [bool] -or -not $audit.ClaimUnchanged -or
        $audit.HistoricalEvidenceUnchanged -isnot [bool] -or -not $audit.HistoricalEvidenceUnchanged -or
        $audit.SevenHistoricalEvidenceHashesUnchanged -isnot [bool] -or -not $audit.SevenHistoricalEvidenceHashesUnchanged -or
        [int]$audit.HistoricalJournalEventCount -ne 1 -or
        [string]$audit.HistoricalJournalPhase -cne 'Intent' -or
        [string]$audit.OriginalContentFingerprintSha256 -cne $ExpectedContentFingerprintSha256) {
        throw 'BW4h1 requires prior independently observed source-zero/dest-one BW4h field-hash drift and unchanged historical seals. No mutation authorized.'
    }
    $stage='Independently read exact already-moved destination MailItem'
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) { throw 'BW4h1 requires Outlook already running.' }
    $ns=$app.GetNamespace('MAPI')
    if ([string]$ns.CurrentProfileName -cne $ExpectedProfileName) { throw 'BW4h1 wrong Outlook profile.' }
    $destHits=0;$destStore=$null
    $storeCount=[int]$ns.Stores.Count
    if($storeCount -lt 2 -or $storeCount -gt 128){throw 'BW4h1 unsafe Outlook store inventory.'}
    for($i=1;$i -le $storeCount;$i++){
        $store=$ns.Stores.Item($i)
        $p=''
        try{$p=[string]$store.FilePath}catch{}
        if($p -and [string]::Equals(
            [IO.Path]::GetFullPath($p),
            [IO.Path]::GetFullPath($DestinationPst),
            [StringComparison]::OrdinalIgnoreCase)){
            $destHits++;$destStore=$store
        }
    }
    if($destHits -ne 1 -or $null -eq $destStore){throw 'BW4h1 destination PST not uniquely mounted.'}
    $mail=$ns.GetItemFromID($DestinationEntryId,[string]$destStore.StoreID)
    $w=Get-OPA265BW4cItemWitness -Mail $mail -SourcePst ([IO.Path]::GetFullPath($DestinationPst)) -StoreId ([string]$destStore.StoreID) -FolderEntryId $DestinationFolderEntryId -CandidateEntryId $DestinationEntryId -Method PrimaryReadOnly
    if ([string]$w.InternetMessageId -cne $ExpectedInternetMessageId -or
        [string]$w.SearchKeySha256 -cne $ExpectedSearchKeySha256 -or
        [string]$w.ContentSha256 -cne [string]$audit.ObservedDestinationContentFingerprintSha256 -or
        -not [bool]$w.IsExactOperatorFixture -or
        [string]$w.ObservedOperatorTestId -cne $TestId) {
        throw 'BW4h1 destination changed between independent audit and field-by-field read.'
    }
    $stage='Exact BW4c field hashing and size-only hypothesis'
    $sub=[string]$mail.Subject
    $sender=[string]$mail.SenderEmailAddress
    $body=[string]$mail.Body
    $size=[long]$mail.Size
    $ticks=([datetime]$mail.ReceivedTime).ToUniversalTime().Ticks
    $check=Get-OPA265BW4h1ContentHash -Subject $sub -SenderEmailAddress $sender -Body $body -Size $size -ReceivedUtcTicks $ticks
    if($check -cne [string]$w.ContentSha256){throw 'BW4h1 raw field hash disagrees with BW4c witness in same Outlook session.'}
    $hypothesis=Get-OPA265BW4h1SizeOnlyHypotheses -Subject $sub -SenderEmailAddress $sender -Body $body -ObservedSize $size -ReceivedUtcTicks $ticks -ExpectedOriginalHash $ExpectedContentFingerprintSha256 -MaxSizeDelta $MaxSizeDelta
    $stage='Repeat check of immutable BW4g attempt claim SHA'
    $claimShaFinal=(Get-FileHash -LiteralPath ([string]$audit.ClaimPath) -Algorithm SHA256).Hash.ToLowerInvariant()
    if($claimShaFinal -cne [string]$audit.ClaimSha256Before){
        throw 'BW4h1 durable one-shot claim changed during read-only diagnosis.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4h1.FieldLevelPostMoveReadOnly.1'
        Status=$hypothesis.Status
        TestId=$TestId
        OriginalSourceEntryId=$OriginalSourceEntryId
        ConfirmedDestinationEntryId=$DestinationEntryId
        SourceMessageIdMatches=[int]$audit.SourceMessageIdMatches
        DestinationMessageIdMatches=[int]$audit.DestinationMessageIdMatches
        InternetMessageIdMatches=[bool]$audit.InternetMessageIdMatches
        SearchKeySha256Matches=[bool]$audit.SearchKeySha256Matches
        SubjectLength=$sub.Length
        SubjectUtf8Sha256=(Get-OPA265BW4h1FieldDigest -Text $sub)
        SenderEmailAddressLength=$sender.Length
        SenderEmailAddressUtf8Sha256=(Get-OPA265BW4h1FieldDigest -Text $sender)
        BodyLength=$body.Length
        BodyCR=([regex]::Matches($body,'\r')).Count
        BodyLF=([regex]::Matches($body,'\n')).Count
        BodyUtf8Sha256=(Get-OPA265BW4h1FieldDigest -Text $body)
        ReceivedTimeUtcTicks=$ticks
        OriginalContentFingerprintSha256=$ExpectedContentFingerprintSha256
        ObservedDestinationContentFingerprintSha256=$check
        ObservedDestinationSize=$size
        InferredOriginalSize=$hypothesis.InferredOriginalSize
        DestinationMinusInferredSourceSize=$hypothesis.DestinationMinusInferredSourceSize
        SizeSearchDeltaBound=$MaxSizeDelta
        SizeOnlyMatches=$hypothesis.SizeOnlyMatches
        ClaimSha256=$claimShaFinal
        ClaimUnchanged=$true
        HistoricalEvidenceUnchanged=[bool]$audit.HistoricalEvidenceUnchanged
        HistoricalJournalEventCount=[int]$audit.HistoricalJournalEventCount
        HistoricalJournalPhase=[string]$audit.HistoricalJournalPhase
        SizeOnlyHypothesisNotIndependentlyProven=$true
        RawSourceFieldSnapshotAvailable=$false
        ReadOnlyReconciliationPassed=$false
        FullMAPIByteEqualityProven=$false
        OutlookMoveExecuted=$false
        CanRetryMove=$false
        CanWriteHistoricalJournal=$false
        ProductionReady=$false
        NextAction='PreserveClaimAndOriginalIntent;ManualSizeAndFieldDriftReviewNeverRetry'
    }
} catch {
    throw ('BW4h1 READ-ONLY STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        '. No MailItem.Move, journal edit, claim write, or replay.')
} finally {
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
