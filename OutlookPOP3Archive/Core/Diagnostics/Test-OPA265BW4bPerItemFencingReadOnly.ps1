#requires -Version 5.1
# Two local read-only JSON witness files; review never opens Outlook COM or writes anything.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
    [string]$Transaction='',
    [Parameter(Mandatory=$true)][string]$PrimaryPath,
    [Parameter(Mandatory=$true)][string]$IndependentPath,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if (-not $Review -or $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW4b needs explicit -Review under Windows PowerShell 5.1 STA.'
}
foreach($file in @('../Worker/Live3SyntheticScope.ps1','../Worker/BW3OneShotProtocol265.ps1',
    '../Worker/BW3bIndependentAudit265.ps1','../Worker/BW3dSyntheticSizeEvidence265.ps1',
    '../Worker/BW3eSyntheticBodyTailEvidence265.ps1','../Worker/BW3gManualSizeAcceptance265.ps1',
    '../Worker/BW3hIndependentEvidenceChain265.ps1','../Worker/BW3iJournalResolutionPreflight265.ps1',
    '../Worker/BW3jResolutionDesign265.ps1','../Worker/WorkerProtocol.ps1',
    '../Archive/OperationJournal.ps1','../Worker/BW4aHistoricalIntentIsolation265.ps1',
    '../Worker/BW4aHistoricalFenceReadOnly265.ps1','../Worker/BW4bPerItemFence265.ps1')) {
    . (Join-Path $PSScriptRoot $file)
}
try {
    if ([string]::Equals([IO.Path]::GetFullPath($PrimaryPath),[IO.Path]::GetFullPath($IndependentPath),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'BW4b requires distinct witness paths.'
    }
    $observations=New-Object 'System.Collections.Generic.List[object]'
    foreach($path in @($PrimaryPath,$IndependentPath)) {
        if (-not [IO.Path]::IsPathRooted($path) -or $path.StartsWith('\',[StringComparison]::Ordinal) -or
            [IO.Path]::GetExtension($path) -cne '.json') { throw 'BW4b requires an absolute local JSON witness path.' }
        $item=Get-Item -LiteralPath $path -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Length -gt 16384 -or $item.Length -lt 2 -or
            (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw 'BW4b witness must be a small regular JSON file.'
        }
        $hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        $value=ConvertFrom-Json -InputObject (Get-Content -LiteralPath $item.FullName -Encoding UTF8 -Raw)
        if ((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -cne $hash) { throw 'BW4b witness changed during read.' }
        [void]$observations.Add([pscustomobject]@{Path=$item.FullName;Hash=$hash;Value=$value})
    }
    # Full read-only audit BEFORE classification of item-level witness data.
    $pre=Invoke-OPA265BW4aHistoricalFenceReview -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode $Mode -Transaction $Transaction
    $p=Get-OPA265BW3hPinnedChain
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $snap=Get-OPA265BW3hEvidenceSnapshot -Paths $paths -Extra $extra -Pinned $p
    $journal=Read-OPAOperationJournal -Path ([string]$paths.JournalPath)
    if ([bool]$journal.TrailingPartial -or @($journal.Events).Count -ne 1) { throw 'BW4b requires exactly one original Intent.' }
    $fence=Get-OPA265BW4aKnownHistoricalFence -Pinned $p -Paths $paths -Snapshot $snap -Intent $journal.Events[0]
    $result=Get-OPA265BW4bPerItemDecision -Fence $fence -Mode $Mode -TransactionId $Transaction -SourcePst $SourcePst -Primary $observations[0].Value -Independent $observations[1].Value
    # Repeat the independent exact historical read-only audit AFTER classification.
    $post=Invoke-OPA265BW4aHistoricalFenceReview -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Mode $Mode -Transaction $Transaction
    foreach($o in $observations) {
        if ((Get-FileHash -LiteralPath $o.Path -Algorithm SHA256).Hash -cne $o.Hash) { throw 'BW4b witness changed during audit.' }
    }
    if (-not $pre.SevenHistoricalEvidenceHashesUnchanged -or
        -not $post.SevenHistoricalEvidenceHashesUnchanged -or
        $post.HistoricJournalPhase -cne 'Intent' -or $result.CanDispatchWorker -or $result.CanInvokeMailMove) {
        throw 'BW4b final historical evidence check failed.'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4b.ReadOnlyPerItemReview.1'
        CandidateStatus=$result.Status
        HistoricalMatches=$result.HistoricalMatches
        PerItemEvidenceConsistent=$result.PerItemEvidenceConsistent
        IndependentOutlookReadbackVerified=$false
        SevenHistoricalEvidenceHashesUnchanged=$true
        HistoricalJournalEventCount=1
        HistoricalJournalPhase='Intent'
        HistoricalJournalChanged=$false
        HistoricRetryBlocked=$true
        WorkerDispatchAllowed=$false
        OutlookComAccessExecuted=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
} catch { throw ('BW4b STOP: '+[string]$_.Exception.Message+'. No Outlook COM, Move or journal write.') }
