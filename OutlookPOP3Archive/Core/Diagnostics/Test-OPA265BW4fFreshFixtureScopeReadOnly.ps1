#requires -Version 5.1
# BW4f: exact operator-created disposable fixture scope, READ ONLY.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
    [string]$Transaction='',
    [Parameter(Mandatory=$true)][string]$FolderEntryId,
    [Parameter(Mandatory=$true)][string]$CandidateEntryId,
    [Parameter(Mandatory=$true)][string]$ExpectedProfileName,
    [Parameter(Mandatory=$true)][string]$CandidateReviewId,
    [Parameter(Mandatory=$true)][string]$ExpectedInternetMessageId,
    [Parameter(Mandatory=$true)][string]$ExpectedSearchKeySha256,
    [Parameter(Mandatory=$true)][string]$ExpectedContentFingerprintSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedTestId,
    [ValidateRange(1,5000)][int]$MaxFolderItems=1000,
    [switch]$UseTargetedMessageIdReadOnly,
    [string]$HistoryRoot=([IO.Path]::GetTempPath()),
    [ValidateRange(1,512)][int]$MaxHistoryRuns=256,
    [switch]$Review,
    [switch]$ConfirmExistingOutlookReadOnly
)
$ErrorActionPreference='Stop'
if (-not $Review -or -not $ConfirmExistingOutlookReadOnly -or
    -not $UseTargetedMessageIdReadOnly -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4f requires -Review, -ConfirmExistingOutlookReadOnly, -UseTargetedMessageIdReadOnly and Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/BW4fFreshFixtureScope265.ps1')
$operatorGuid=[guid]::Empty
if (-not [guid]::TryParse($ExpectedTestId,[ref]$operatorGuid) -or
    $operatorGuid -eq [guid]::Empty -or
    $ExpectedTestId -cne $operatorGuid.ToString('D')) {
    throw 'BW4f requires a canonical independent operator TestId GUID.'
}
try {
    # Original BW4e2 performs the full BW4d history audit + BW4c dual
    # Outlook reads and preserves BW3a's seven hashed evidence files.
    $bw4eSnapshot=& (Join-Path $PSScriptRoot 'Test-OPA265BW4eFreshSyntheticReadOnly.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode $Mode -Transaction $Transaction -FolderEntryId $FolderEntryId -CandidateEntryId $CandidateEntryId -ExpectedProfileName $ExpectedProfileName -CandidateReviewId $CandidateReviewId -ExpectedInternetMessageId $ExpectedInternetMessageId -ExpectedSearchKeySha256 $ExpectedSearchKeySha256 -ExpectedContentFingerprintSha256 $ExpectedContentFingerprintSha256 -MaxFolderItems $MaxFolderItems -UseTargetedMessageIdReadOnly -HistoryRoot $HistoryRoot -MaxHistoryRuns $MaxHistoryRuns -Review -ConfirmExistingOutlookReadOnly
    $result=Get-OPA265BW4fScopeDecision -Bw4eReview $bw4eSnapshot -ExpectedTestId $ExpectedTestId
    if ($result.CanInvokeMailMove -or $result.CanDispatchWorker -or
        $result.CanRetryPreviousMove -or $result.CanWriteHistoricalJournal) {
        throw 'BW4f no-Move invariant violated.'
    }
    return $result
} catch {
    throw ('BW4f STOP (no Outlook Move, Worker, journal writer, PST edit or claim): '+[string]$_.Exception.Message)
}
