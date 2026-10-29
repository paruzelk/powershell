#requires -Version 5.1
# BW4g isolated DEV one-shot COM worker, run with powershell.exe -STA -File.
# Never part of Archive / Resume / Auto production Worker paths.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [Parameter(Mandatory=$true)][string]$FolderEntryId,
    [Parameter(Mandatory=$true)][string]$CandidateEntryId,
    [Parameter(Mandatory=$true)][string]$ExpectedProfileName,
    [Parameter(Mandatory=$true)][string]$CandidateReviewId,
    [Parameter(Mandatory=$true)][string]$ExpectedInternetMessageId,
    [Parameter(Mandatory=$true)][string]$ExpectedSearchKeySha256,
    [Parameter(Mandatory=$true)][string]$ExpectedContentFingerprintSha256,
    [Parameter(Mandatory=$true)][string]$TestId,
    [Parameter(Mandatory=$true)][string]$DestinationPst,
    [Parameter(Mandatory=$true)][string]$DestinationFolderEntryId,
    [switch]$Review,
    [switch]$Execute,
    [switch]$ConfirmOneShotDisposableMove,
    [ValidateRange(1,5000)][int]$MaxFolderItems=1000
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4g requires native Windows PowerShell 5.1 STA in its isolated process.'
}
if ([bool]$Review -eq [bool]$Execute -or
    ($Review -and $ConfirmOneShotDisposableMove) -or
    ($Execute -and -not $ConfirmOneShotDisposableMove)) {
    throw 'BW4g requires exclusive -Review OR -Execute -ConfirmOneShotDisposableMove.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4fFreshFixtureScope265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4cOutlookReadOnlyCapture265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW4gOneShotPermit265.ps1')
$testGuid=[guid]::Empty
if (-not [guid]::TryParse($TestId,[ref]$testGuid) -or
    $testGuid -eq [guid]::Empty -or $TestId -cne $testGuid.ToString('D')) {
    throw 'BW4g requires exact canonical operator TestId.'
}
$claimPath=Get-OPA265BW4gClaimPath -TestId $TestId
if ([IO.File]::Exists($claimPath)) {
    throw ('BW4g persistent prior attempt claim exists; NEVER RETRY this fixture: '+$claimPath)
}
$expectedDestLeaf='OPA265-BW4g-'+$testGuid.ToString('N')+'.pst'
if ([IO.Path]::GetFileName($DestinationPst) -cne $expectedDestLeaf -or
    -not [IO.Path]::IsPathRooted($DestinationPst) -or
    $DestinationPst.StartsWith('\\') -or
    -not [IO.File]::Exists($DestinationPst) -or
    ([IO.File]::GetAttributes($DestinationPst) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    [string]::Equals([IO.Path]::GetFullPath($DestinationPst),[IO.Path]::GetFullPath($SourcePst),[StringComparison]::OrdinalIgnoreCase)) {
    throw 'BW4g requires a precreated distinct local disposable PST named OPA265-BW4g-<TestId:N>.pst.'
}
# Every candidate must pass the BW4f fully independent historical file
# audit and BW4e2 targeted Outlook MAPI dual-route evidence BEFORE claim.
$bw4fSnapshot=& (Join-Path $PSScriptRoot 'Test-OPA265BW4fFreshFixtureScopeReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode Archive -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -ExpectedProfileName $ExpectedProfileName -CandidateReviewId $CandidateReviewId -ExpectedInternetMessageId $ExpectedInternetMessageId -ExpectedSearchKeySha256 $ExpectedSearchKeySha256 -ExpectedContentFingerprintSha256 $ExpectedContentFingerprintSha256 -ExpectedTestId $TestId -MaxFolderItems $MaxFolderItems -UseTargetedMessageIdReadOnly -Review -ConfirmExistingOutlookReadOnly
[void](Assert-OPA265BW4gReady -Review $bw4fSnapshot -TestId $TestId -CandidateEntryId $CandidateEntryId -InternetMessageId $ExpectedInternetMessageId)
# Explicit destination and fresh source inspection occur in the same
# already-running Outlook session. Never create an Outlook account/store here.
$app=$null;$ns=$null;$dest=$null;$mail=$null
$stage='Attach existing Outlook session';$claimed=$false
try {
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
    if ($null -eq $app) {throw 'BW4g requires already-running Outlook.'}
    $ns=$app.GetNamespace('MAPI')
    if ([string]$ns.CurrentProfileName -cne $ExpectedProfileName) {throw 'BW4g Outlook profile mismatch.'}
    $stage='Resolve precreated unique disposable destination PST'
    $dstPath=[IO.Path]::GetFullPath($DestinationPst)
    $destStore=$null;$matches=0
    $count=[int]$ns.Stores.Count
    if ($count -lt 2 -or $count -gt 128) {throw 'BW4g store inventory unsafe.'}
    for($i=1;$i -le $count;$i++){
        $store=$ns.Stores.Item($i)
        $path=''
        try {$path=[string]$store.FilePath} catch {}
        if ($path -and [string]::Equals([IO.Path]::GetFullPath($path),$dstPath,[StringComparison]::OrdinalIgnoreCase)) {
            $destStore=$store;$matches++
        }
    }
    if ($matches -ne 1 -or $null -eq $destStore -or
        [string]::IsNullOrWhiteSpace([string]$destStore.StoreID)) {
        throw 'BW4g target disposable PST is not uniquely mounted.'
    }
    $srcScope=Get-OPA265BW4cPop3Store -Namespace $ns -SourcePst $SourcePst
    if (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$srcScope.StoreId) -Expected ([string]$destStore.StoreID)) {
        throw 'BW4g source and destination StoreIDs must differ.'
    }
    $stage='Resolve one empty exact destination fixture folder'
    $dest=$ns.GetFolderFromID($DestinationFolderEntryId,[string]$destStore.StoreID)
    $folderName='OPA265-BW4g-'+$testGuid.ToString('N')
    if ($null -eq $dest -or [string]$dest.Name -cne $folderName -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$dest.EntryID) -Expected $DestinationFolderEntryId) -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$dest.StoreID) -Expected ([string]$destStore.StoreID)) -or
        [int]$dest.Items.Count -ne 0) {
        throw 'BW4g destination must be the exact pinned empty disposable test folder.'
    }
    $stage='Refresh pinned candidate with BW4e2 second MAPI path'
    $pair=Get-OPA265BW4cDualReadback -Namespace $ns -SourcePst $SourcePst -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -UseTargetedMessageIdReadOnly -MaxFolderItems $MaxFolderItems
    foreach($w in @($pair.Primary,$pair.Independent)){
        if (-not [bool]$w.IsExactOperatorFixture -or
            [string]$w.ObservedOperatorTestId -cne $TestId -or
            [string]$w.InternetMessageId -cne $ExpectedInternetMessageId -or
            [string]$w.SearchKeySha256 -cne $ExpectedSearchKeySha256 -or
            [string]$w.ContentSha256 -cne $ExpectedContentFingerprintSha256) {
            throw 'BW4g fresh source MAPI evidence changed since full BW4f review.'
        }
    }
    if ($null -eq $pair -or $pair.CandidateMatches -ne 1) {throw 'BW4g requires exactly one source candidate.'}
    if ([IO.File]::Exists($claimPath)) {throw 'BW4g prior attempt claim appeared; no retry.'}
    if ($Review) {
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4g.OneShotReviewOnly.1'
            Status='DisposableOneShotPreflightPassedNoMove'
            TestId=$TestId
            CandidateEntryId=$CandidateEntryId
            DestinationPst=$dstPath
            DestinationFolderEntryId=$DestinationFolderEntryId
            HistoricalJournalChanged=$false
            MoveAttemptClaimCreated=$false
            OutlookMoveExecuted=$false
            CanRetryPreviousMove=$false
            ProductionReady=$false
            NextAction='UseNewExplicitReviewIdAndExecuteOnlyIfOperatorStillApproves'
        }
        return
    }
    $stage='Durably create irreversible one-attempt claim'
    $claim=[pscustomobject][ordered]@{
        Schema='2.6.5-BW4g.ImmutableOneShotClaim.1'
        TestId=$TestId
        CandidateReviewId=$CandidateReviewId
        SourcePst=[IO.Path]::GetFullPath($SourcePst)
        SourceEntryId=$CandidateEntryId
        InternetMessageId=$ExpectedInternetMessageId
        DestinationPst=$dstPath
        DestinationFolderEntryId=$DestinationFolderEntryId
        Utc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
    $written=Write-OPA265BW4gOneShotClaim -ClaimPath $claimPath -Claim $claim
    $claimed=$true
    $stage='Attempt exactly ONE disposable cross-PST MailItem.Move'
    $mail=$ns.GetItemFromID($CandidateEntryId,[string]$srcScope.StoreId)
    if ($null -eq $mail -or [int]$mail.Class -ne 43 -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$mail.EntryID) -Expected $CandidateEntryId) -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$mail.Parent.EntryID) -Expected $FolderEntryId)) {
        throw 'BW4g source changed immediately after claim; never retry.'
    }
    $moved=$mail.Move($dest)
    if ($null -eq $moved -or [string]::IsNullOrWhiteSpace([string]$moved.EntryID)) {
        throw 'BW4g one Move returned indeterminate destination; never retry.'
    }
    $afterId=[string]$moved.EntryID
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4g.OneShotMoveReturned.1'
        Status='OneSyntheticMoveReturnedRequiresIndependentReconciliation'
        TestId=$TestId
        ClaimPath=$written
        CandidateEntryId=$CandidateEntryId
        DestinationEntryId=$afterId
        DestinationPst=$dstPath
        MoveAttempts=1
        OutlookMoveReturned=$true
        HistoricalJournalChanged=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='IndependentReadOnlySourceAndDestinationPstReconciliationNeverRetry'
    }
} catch {
    throw ('BW4g STOP at ['+$stage+']: '+[string]$_.Exception.Message+
        $(if($claimed){'. Move attempt claimed; outcome MAY BE INDETERMINATE; NEVER RETRY.'}else{'. No attempt claim created; no Move issued.'}))
} finally {
    if($null -ne $ns -and [Runtime.InteropServices.Marshal]::IsComObject($ns)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ns)
    }
    if($null -ne $app -and [Runtime.InteropServices.Marshal]::IsComObject($app)){
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app)
    }
}
