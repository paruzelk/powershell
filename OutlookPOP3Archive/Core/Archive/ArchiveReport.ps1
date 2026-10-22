function Write-OPAArchiveReport {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][object]$Transaction,
        [object]$PhaseStartedAt
    )

    # Counters:
    #   Planned / Executed / Skipped / Verified - see inline docs below.
    # PhaseStartedAt: timestamp for THIS phase only. For an Archive run it
    # is the transaction creation time. For a Resume it is the moment the
    # resume branch started, so the report shows resume duration rather than
    # the total age of the checkpoint file.
    Write-Host ""
    Write-Host "## Archive Report"
    Write-Host ("Transaction : {0}" -f $Transaction.TransactionId)
    Write-Host ("Planned     : {0} (target)" -f $Transaction.State.Planned)
    Write-Host ("Executed    : {0}" -f $Transaction.State.Executed)
    Write-Host ("Skipped     : {0}" -f $Transaction.State.Skipped)
    Write-Host ("Verified    : {0}" -f $Transaction.State.Verified)
    Write-Host ("Source left : {0}" -f $Result.SourceRemaining)
    Write-Host ("Archive cnt : {0}" -f $Result.TargetCount)
    Write-Host ("Verified    : {0}" -f $Result.Verified)
    Write-Host 'Verify mode : Independent Outlook source + archive item check'
    Write-Host ("Checkpoint  : {0}" -f $Transaction.Path)
    $durMode = 'Fast (default)'
    if (Test-OPAStateHasKey -State $Transaction.State -Name 'DurabilityMode') {
        $storedDurabilityMode = [string]$Transaction.State.DurabilityMode
        if ($storedDurabilityMode -in @('Fast','Safe')) { $durMode = $storedDurabilityMode }
    }
    Write-Host ("Durability  : {0}" -f $durMode)
    Write-Host ("Logical freed: {0:N2} MB" -f ([double]$Transaction.State.LogicalFreedBytes / 1MB))
    Write-Host ("Source PST   : {0:N2} GB -> {1:N2} GB" -f ([double]$Transaction.State.SourcePstSizeBeforeBytes / 1GB),([double]$Transaction.State.SourcePstSizeAfterBytes / 1GB))

    $reclaim = Get-OPAStorageReclaimEstimate `
        -PhysicalBeforeBytes ([int64]$Transaction.State.SourcePstSizeBeforeBytes) `
        -PhysicalAfterBytes ([int64]$Transaction.State.SourcePstSizeAfterBytes) `
        -LogicalFreedBytes ([int64]$Transaction.State.LogicalFreedBytes)
    Write-Host ("Physical reclaimed : {0:N2} MB" -f ([double]$reclaim.PhysicalReductionBytes / 1MB))
    Write-Host ("Physical growth    : {0:N2} MB" -f ([double]$reclaim.PhysicalGrowthBytes / 1MB))
    if ($reclaim.CompactAssessment -eq 'ReviewRecommended') {
        Write-Host ("Compact review: logical removal {0:N2} MB exceeds physical shrink {1:N2} MB." -f `
            ([double]$reclaim.LogicalFreedBytes/1MB),([double]$reclaim.PhysicalReductionBytes/1MB)) -ForegroundColor Yellow
        Write-Host ("Logical reduction not reflected in file shrink: {0:N2} MB (not a Compact size prediction)." -f `
            ([double]$reclaim.UnmatchedLogicalReductionBytes/1MB)) -ForegroundColor Yellow
        Write-Host 'No automatic Compact. Review PST health, backup and Outlook maintenance procedure.' -ForegroundColor Yellow
    }

    $missingIds = @()
    $warningIds = @()
    if ($Result.PSObject.Properties.Name -contains 'MissingEntryIds') { $missingIds = @($Result.MissingEntryIds) }
    if ($Result.PSObject.Properties.Name -contains 'WarningEntryIds') { $warningIds = @($Result.WarningEntryIds) }
    if ($missingIds.Count -gt 0) {
        Write-Host ''
        Write-Host ("## Missing IDs ({0})" -f $missingIds.Count)
        foreach ($mid in $missingIds) { Write-Host ("  {0}" -f $mid) }
    }
    if ($warningIds.Count -gt 0) {
        Write-Host ''
        Write-Host ("## Warnings ({0} - stale PST EntryIDs, not failures)" -f $warningIds.Count)
        foreach ($wid in $warningIds) { Write-Host ("  {0}" -f $wid) }
    }
    if ([int]$Transaction.State.Skipped -gt 0) {
        Write-Host ""
        Write-Host ("## Skipped items ({0})" -f $Transaction.State.Skipped)
        foreach ($s in @($Transaction.State.SkippedItems)) {
            Write-Host ("  [{0}] {1} | {2}" -f $s.Reason, $s.EntryId, $s.Message)
        }
    }

    $phaseStart = $null
    if ($PSBoundParameters.ContainsKey('PhaseStartedAt') -and $null -ne $PhaseStartedAt) {
        $phaseStart = $PhaseStartedAt
    }
    else {
        try { $phaseStart = [datetime]$Transaction.State.Started } catch {}
    }
    $phaseEnd = $null
    try { $phaseEnd = [datetime]$Transaction.State.Updated } catch {}

    if ($phaseStart -and $phaseEnd -and $phaseEnd -ge $phaseStart) {
        $seconds = [math]::Max(0,($phaseEnd - $phaseStart).TotalSeconds)
        # Throughput against the phase duration only. For a Resume phase
        # that moved no items (Remaining=0), show "n/a" instead of a rate
        # derived from a resumed count that was set during an earlier run.
        # $Transaction.State.Performance is an [ordered]@{} (OrderedDictionary).
        # PSObject.Properties.Name on an OrderedDictionary returns the
        # collection's intrinsic members on Windows PowerShell 5.1, not the
        # user-visible keys -- same trap already fixed for TransactionState.
        # Read counters via the IDictionary interface when available.
        $movedThisPhase = 0
        if ($null -ne $Transaction.State.Performance) {
            $perf = $Transaction.State.Performance
            $perfIsDict = ($perf -is [System.Collections.IDictionary])
            foreach ($key in @('ResumeMovedNow','MovesThisRun','SelectedItems','Selected')) {
                $v = $null
                try {
                    if ($perfIsDict) {
                        if ($perf.Contains($key)) { $v = $perf[$key] }
                    }
                    else {
                        if ($perf.PSObject.Properties.Name -contains $key) { $v = $perf.$key }
                    }
                }
                catch {}
                if ($null -ne $v) {
                    try { $iv = [int]$v } catch { $iv = 0 }
                    if ($iv -gt 0) { $movedThisPhase = $iv; break }
                }
            }
        }

        if ($movedThisPhase -le 0 -and -not $PSBoundParameters.ContainsKey('PhaseStartedAt')) {
                try { $movedThisPhase = [int]$Transaction.State.Executed } catch {}
            }
            $rate = if ($seconds -gt 0 -and $movedThisPhase -gt 0) { [double]$movedThisPhase / $seconds } else { $null }

        Write-Host ""
        Write-Host "## Performance"
        Write-Host ("Phase start : {0:yyyy-MM-dd HH:mm:ss}" -f $phaseStart)
        Write-Host ("Phase end   : {0:yyyy-MM-dd HH:mm:ss}" -f $phaseEnd)
        Write-Host ("Duration    : {0:N1} sec" -f $seconds)
        if ($null -ne $Transaction.State.Performance) {
            $perf = $Transaction.State.Performance
            $recovered = 0; $newComMoves = 0
            if (Test-OPAStateHasKey -State $perf -Name 'RecoveredMovesThisRun') { $recovered = [int]$perf.RecoveredMovesThisRun }
            if (Test-OPAStateHasKey -State $perf -Name 'NewMovesThisRun') { $newComMoves = [int]$perf.NewMovesThisRun }
            Write-Host ("New COM moves : {0}" -f $newComMoves)
            Write-Host ("Recovered moves: {0}" -f $recovered)
        }
        if ($null -ne $rate) {
            Write-Host ("Throughput  : {0:N2} items/sec (phase)" -f $rate)
        }
        else {
            Write-Host "Throughput  : n/a (no moves this phase)"
        }
    }

    Write-Host ""
    Write-Host "Archive PST telemetry:"
    foreach ($ap in @($Transaction.State.ArchivePsts)) {
        Write-Host ("  {0}" -f [string]$ap.Path)
        Write-Host ("    Physical : {0:N2} MB -> {1:N2} MB (growth {2:N2} MB)" -f ([double]$ap.PhysicalSizeBeforeBytes/1MB),([double]$ap.PhysicalSizeAfterBytes/1MB),([double]$ap.PhysicalGrowthBytes/1MB))
        Write-Host ("    Logical  : {0:N2} MB" -f ([double]$ap.LogicalAddedBytes/1MB))
    }
}