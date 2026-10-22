# Auto recovery attempts: a persistent guard, not a transaction mutation.
# After repeated failed/interrupted Auto Resume attempts, stop Auto safely.
# Manual Resume is still allowed. Never discard a checkpoint or start a new
# archive while an ambiguous/uncompleted transaction exists.
function Get-OPAAutoRetryPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$CheckpointPath)
    return ($CheckpointPath + '.auto-retry')
}

function Get-OPAAutoRetryCount {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$CheckpointPath)
    $path = Get-OPAAutoRetryPath -CheckpointPath $CheckpointPath
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    try {
        $state = Read-OPAJsonFile -Path $path
        if ($null -eq $state -or $state.PSObject.Properties.Name -notcontains 'Attempts' -or $null -eq $state.Attempts) {
            throw 'Missing Attempts field'
        }
        $attempts = [int]$state.Attempts
        if ($attempts -lt 0) { throw 'Negative attempt counter' }
        return $attempts
    }
    catch {
        throw "Auto recovery attempt marker '$path' is unreadable. Refusing automatic retry; manual inspection required: $($_.Exception.Message)"
    }
}

function Register-OPAAutoResumeAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CheckpointPath,
        [ValidateRange(1,1000)][int]$MaxAttempts = 3
    )
    $attempts = Get-OPAAutoRetryCount -CheckpointPath $CheckpointPath
    if ($attempts -ge $MaxAttempts) {
        throw ("Auto recovery quarantined: checkpoint '{0}' has {1} automatic attempts (maximum {2}). Do not delete the checkpoint; diagnose and use -Mode Resume manually." -f $CheckpointPath,$attempts,$MaxAttempts)
    }
    $state = [ordered]@{
        Attempts = ($attempts + 1)
        LastAttemptUtc = ([datetime]::UtcNow).ToString('o')
    }
    $path = Get-OPAAutoRetryPath -CheckpointPath $CheckpointPath
    Write-OPAAtomicTextFile -Path $path -Content (ConvertTo-Json -InputObject $state -Depth 4)
    return ($attempts + 1)
}

function Clear-OPAAutoResumeAttempts {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$CheckpointPath)
    $path = Get-OPAAutoRetryPath -CheckpointPath $CheckpointPath
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

# FIX11: Auto must never start a new Archive while there is an unresolved,
# unsupported, corrupt or ambiguous transaction. This decision is pure and
# independently testable without Outlook COM.
function Resolve-OPAAutoPendingTransaction {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Candidates)

    $pending = @($Candidates | Where-Object { $null -ne $_ })
    $unsupported = @($pending | Where-Object {
        [bool]$_.IsUnsupported -or [string]$_.Status -eq 'Unsupported'
    })
    if ($unsupported.Count -gt 0) {
        $ids = @($unsupported | ForEach-Object { [string]$_.TransactionId }) -join ', '
        throw ("Auto safety: {0} unsupported transaction(s) must be inspected manually: {1}. New Archive is blocked." -f $unsupported.Count, $ids)
    }

    # VerificationFailed/Failed require manual investigation. Auto must not
    # restart a capacity breach or other failed verification automatically.
    $failed = @($pending | Where-Object { [string]$_.Status -in @('VerificationFailed','Failed') })
    if ($failed.Count -gt 0) {
        $ids = @($failed | ForEach-Object { [string]$_.TransactionId }) -join ', '
        throw ("Auto safety: {0} failed transaction(s) require manual inspection: {1}. Automatic Resume and new Archive are blocked." -f $failed.Count,$ids)
    }

    if ($pending.Count -gt 1) {
        $ids = @($pending | ForEach-Object { [string]$_.TransactionId }) -join ', '
        throw ("Auto safety: multiple unfinished transaction checkpoints exist ({0}): {1}. New Archive and automatic Resume are blocked; inspect manually." -f $pending.Count, $ids)
    }

    if ($pending.Count -eq 1) { return $pending[0] }
    return $null
}


# Orphan journals may be the only evidence of moves from a crashed run.
# Never start a new Auto Archive until an administrator reconciles them.
function Assert-OPAAutoNoOrphanJournals {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Discovery)

    $checkedDirectories = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($source in @($Discovery.Pop3Sources)) {
        $dir = Join-Path ([IO.Path]::GetDirectoryName([string]$source.FilePath)) 'OutlookPOP3Archive-Transactions'
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        if (-not $checkedDirectories.Add([IO.Path]::GetFullPath($dir))) { continue }
        foreach ($journal in @(Get-ChildItem -LiteralPath $dir -Filter '*.steps.jsonl' -File -ErrorAction Stop)) {
            $checkpoint = $journal.FullName -replace '\.steps\.jsonl$', '.json'
            if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) {
                throw ("Auto safety: orphan step journal '{0}' has no checkpoint. New Archive and automatic Resume are blocked; inspect manually." -f $journal.FullName)
            }
        }
    }
}

function Remove-OPAStaleTransactions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Discovery,
        [ValidateRange(0,3650)][int]$RetentionDays = 7,
        [switch]$WhatIf
    )

    # Statuses safe to delete after retention.
    # Only independently verified Completed transactions may be removed
    # automatically. Unsupported and VerificationFailed checkpoints are NOT
    # disposable; they may contain the only durable recovery metadata.
    # Active or unknown statuses are always kept.
    $safeStatuses   = @('Completed')
    $activeStatuses = @('Running','Planned','Created','Recovered')

    $cutoff = (Get-Date).AddDays(-1 * $RetentionDays)
    $removed = 0
    $failed  = 0
    $kept    = 0

    foreach ($source in @($Discovery.Pop3Sources)) {
        $dir = Join-Path ([IO.Path]::GetDirectoryName([string]$source.FilePath)) 'OutlookPOP3Archive-Transactions'
        if (-not (Test-Path -LiteralPath $dir)) { continue }

        foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            if ($file.Name -eq 'DuplicateIndex.json') { continue }
            if ($file.Name -like '*.bak*' -or $file.Name -like '*.backup*') { continue }

            # Age check first: cheap stat, avoids parsing recent files.
            if ($file.LastWriteTime -gt $cutoff) { $kept++; continue }

            $state = $null
            try { $state = Read-OPAJsonFile -Path $file.FullName } catch { continue }
            if ($null -eq $state) { continue }

            $status = ''
            try { $status = [string]$state.Status } catch {}
            if ($activeStatuses -contains $status) { $kept++; continue }
            if ($safeStatuses -notcontains $status) { $kept++; continue }

            $id = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            $journalPath = [IO.Path]::ChangeExtension($file.FullName, '.steps.jsonl')

            if ($WhatIf) {
                Write-Host ("  [WhatIf] Would remove: {0} [{1}]" -f $id, $status)
                $removed++
                continue
            }

            try {
                Remove-Item -LiteralPath $file.FullName -Force
                if (Test-Path -LiteralPath $journalPath) { Remove-Item -LiteralPath $journalPath -Force }
                $retryMarker = $file.FullName + '.auto-retry'
                if (Test-Path -LiteralPath $retryMarker) { Remove-Item -LiteralPath $retryMarker -Force }
                $removed++
            }
            catch {
                Write-Warning ("Failed to remove stale transaction '{0}': {1}" -f $id, $_.Exception.Message)
                $failed++
            }
        }
    }

    # Intentionally do not delete orphan step journals automatically. A
    # checkpoint can disappear or become unreadable after a power failure;
    # its journal may be the only remaining source of recovery evidence.
    # Orphan journals require explicit, reviewed maintenance.

    if ($removed -gt 0) {
        $verb = if ($WhatIf) { 'would be removed' } else { 'removed' }
        Write-Host ("Cleanup: {0} stale transaction(s) {1} (retention {2} day(s)); {3} kept." -f $removed, $verb, $RetentionDays, $kept)
    }
    if ($failed -gt 0) {
        Write-Warning ("Cleanup: {0} transaction(s) could not be removed (locked?)." -f $failed)
    }

    [pscustomobject]@{ Removed = $removed; Failed = $failed; Kept = $kept }
}
