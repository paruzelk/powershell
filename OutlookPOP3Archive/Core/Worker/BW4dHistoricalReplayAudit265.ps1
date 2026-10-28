#requires -Version 5.1
# BW4d read-only history catalog; source PST and historical journals are NEVER modified.
function Get-OPA265BW4dHistoryCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$HistoryRoot,
        [ValidateRange(1,512)][int]$MaxRunDirectories=256,
        [ValidateRange(4096,16777216)][int]$MaxJournalBytes=4194304
    )
    if (-not [IO.Path]::IsPathRooted($HistoryRoot) -or
        $HistoryRoot.StartsWith('\\',[StringComparison]::Ordinal) -or
        -not [IO.Directory]::Exists($HistoryRoot) -or
        (([IO.File]::GetAttributes($HistoryRoot) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'BW4d requires existing local absolute, non-reparse history root.'
    }
    $root=[IO.Path]::GetFullPath($HistoryRoot)
    $dirs=@(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop |
        Where-Object { $_.Name -match '^OPA264-LIVE3-[0-9a-fA-F]{32}$' } | Sort-Object FullName)
    if ($dirs.Count -gt $MaxRunDirectories) { throw 'BW4d history root exceeds maximum run count.' }
    $events=New-Object 'System.Collections.Generic.List[object]'
    $entries=New-Object 'System.Collections.Generic.List[string]'
    $journalCount=0
    $claimOnly=0
    $names=@('move.operations.jsonl','move-attempt.claim','controller-dispatch.claim',
        'controller-result.json','response.json','crash-barrier.json','request.json','scope.json')
    foreach($dir in $dirs) {
        if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'BW4d refuses symlinked test-run directory.'
        }
        $journal=Join-Path $dir.FullName 'move.operations.jsonl'
        $hasClaim=$false
        foreach($name in $names) {
            $file=Join-Path $dir.FullName $name
            if (-not (Test-Path -LiteralPath $file)) {
                [void]$entries.Add(($dir.Name+'/'+$name+'=MISSING'))
                continue
            }
            $item=Get-Item -LiteralPath $file -Force -ErrorAction Stop
            if ($item.PSIsContainer -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                $item.Length -gt $MaxJournalBytes) {
                throw ('BW4d refuses non-regular/oversized evidence: '+$name)
            }
            if ($name -in @('move-attempt.claim','controller-dispatch.claim')) { $hasClaim=$true }
            $digest=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$entries.Add(($dir.Name+'/'+$name+'='+$digest))
        }
        if (-not [IO.File]::Exists($journal)) {
            if ($hasClaim) { $claimOnly++ }
            continue
        }
        $journalCount++
        if ((Get-Item -LiteralPath $journal).Length -lt 1) {
            throw 'BW4d refuses empty historical operation journal.'
        }
        $read=Read-OPAOperationJournal -Path $journal
        if ([bool]$read.TrailingPartial -or @($read.Events).Count -lt 1 -or
            @($read.Events).Count -gt 10000) {
            throw 'BW4d refuses truncated, empty or unbounded history events.'
        }
        foreach($ev in @($read.Events)) {
            [void]$events.Add([pscustomobject]@{
                RunDirectory=$dir.Name;TransactionId=[string]$ev.TransactionId
                OperationId=[string]$ev.OperationId;Phase=[string]$ev.Phase
                OperationKind=[string]$ev.OperationKind;SourceEntryId=[string]$ev.SourceEntryId
                ArchiveEntryId=[string]$ev.ArchiveEntryId
                InternetMessageId=[string]$ev.InternetMessageId
                SourceStoreId=[string]$ev.SourceStoreId
            })
        }
    }
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $joined=[string]::Join([char]10,@($entries.ToArray()))
        $snapshot=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($joined))).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4d.VisibleHistoryCatalog.1'
        HistoryRoot=$root
        RunDirectoriesScanned=$dirs.Count
        JournalsScanned=$journalCount
        ClaimOnlyDirectories=$claimOnly
        Events=$events.ToArray()
        EvidenceSnapshotSha256=$snapshot
        CatalogComplete=$false
        HistoryReadOnly=$true
        ProductionReady=$false
    }
}
function Get-OPA265BW4dReplayDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Bw4cReview,
          [Parameter(Mandatory=$true)][object]$History)
    if ([string]$Bw4cReview.Schema -cne '2.6.5-BW4c.OutlookDualPathPerItemReadOnly.1' -or
        [string]$Bw4cReview.Status -cne 'OutlookReadOnlyDualPathEvidenceReviewedNoWorkerDispatch' -or
        [string]$Bw4cReview.CandidateStatus -cne 'PerItemEvidenceConsistentDesignOnlyNoWorkerDispatch' -or
        $Bw4cReview.SevenHistoricalEvidenceHashesUnchanged -isnot [bool] -or
        -not $Bw4cReview.SevenHistoricalEvidenceHashesUnchanged -or
        [int]$Bw4cReview.HistoricJournalEventCount -ne 1 -or
        [string]$Bw4cReview.HistoricJournalPhase -cne 'Intent' -or
        $Bw4cReview.OutlookMoveExecuted -isnot [bool] -or
        $Bw4cReview.OutlookMoveExecuted -or
        $Bw4cReview.WorkerDispatchAllowed -isnot [bool] -or $Bw4cReview.WorkerDispatchAllowed -or
        [string]$History.Schema -cne '2.6.5-BW4d.VisibleHistoryCatalog.1' -or
        $History.HistoryReadOnly -isnot [bool] -or -not $History.HistoryReadOnly -or
        $History.CatalogComplete -isnot [bool] -or $History.CatalogComplete) {
        throw 'BW4d refuses modified historical evidence or falsely trusted input.'
    }
    foreach($f in @('CandidateEntryId','InternetMessageId','SourceStoreId')) {
        if ([string]::IsNullOrWhiteSpace([string]$Bw4cReview.$f)) {
            throw ('BW4d requires observed identity: '+$f)
        }
    }
    $matches=New-Object 'System.Collections.Generic.List[string]'
    $entryId=[string]$Bw4cReview.CandidateEntryId
    $messageId=[string]$Bw4cReview.InternetMessageId
    foreach($e in @($History.Events)) {
        $related=(([string]$e.SourceEntryId -cne '' -and
            [string]$e.SourceEntryId -ceq $entryId) -or
            ([string]$e.ArchiveEntryId -cne '' -and
            [string]$e.ArchiveEntryId -ceq $entryId) -or
            ([string]$e.InternetMessageId -cne '' -and
            [string]::Equals([string]$e.InternetMessageId,$messageId,[StringComparison]::OrdinalIgnoreCase)))
        if ($related) {
            $key=[string]$e.RunDirectory+':'+[string]$e.OperationId+':'+[string]$e.Phase
            if (-not $matches.Contains($key)) { [void]$matches.Add($key) }
        }
    }
    # Live3/Live4 synthetic messages are NOT replay-clear if records disappear or moved.
    $synthetic=($messageId -match '^<opa264-live3-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}@example\.invalid>$')
    $status=if ($matches.Count -gt 0) {
        'BlockedKnownPriorLive3Live4OperationEvidence'
    } elseif ($synthetic) {
        'BlockedSyntheticLive3OriginCannotProveNoEarlierMove'
    } else {
        'NoMatchingEventInVisibleHistoryCatalogStillNotReplayClearance'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4d.HistoryReplayFenceDecision.1'
        Status=$status
        HistoricalOperationMatches=$matches.ToArray()
        SyntheticLive3Identity=[bool]$synthetic
        JournalsScanned=[int]$History.JournalsScanned
        RunDirectoriesScanned=[int]$History.RunDirectoriesScanned
        ClaimOnlyDirectories=[int]$History.ClaimOnlyDirectories
        CatalogComplete=$false
        IndependentJournalFileEvidenceReviewed=$true
        IndependentExternalMAPIContentProof=$false
        ReplaySafetyProven=$false
        HistoricalIntentUnchanged=$true
        CanRetryPreviousMove=$false
        CanDispatchWorker=$false
        CanInvokeMailMove=$false
        CanWriteHistoricalJournal=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='NoMove;UseFreshSyntheticItemAndIndependentEvidence'
    }
}
