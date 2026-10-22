# Requires Core/Runtime/JsonSupport.ps1 to be loaded first
# (Read-OPAJsonFile provides retry/backoff for AV-locked files).
function Convert-OPAStoragePolicyGBToBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double]$Gigabytes
    )

    if ($Gigabytes -lt 0) {
        throw "Storage policy size cannot be negative: $Gigabytes GB."
    }

    return [int64][math]::Round($Gigabytes * 1GB, 0, [MidpointRounding]::AwayFromZero)
}

function Get-OPAPstFileSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PstPath
    )

    if ([string]::IsNullOrWhiteSpace($PstPath)) {
        throw 'PST path is empty.'
    }

    if (-not (Test-Path -LiteralPath $PstPath -PathType Leaf)) {
        throw "PST file was not found: $PstPath"
    }

    $file = Get-Item -LiteralPath $PstPath -ErrorAction Stop

    [pscustomobject]@{
        Path      = $file.FullName
        SizeBytes = [int64]$file.Length
        SizeGB    = [math]::Round(([double]$file.Length / 1GB), 2)
    }
}

function Test-OPAStoragePolicyConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double]$HighWatermarkGB,

        [Parameter(Mandatory=$true)]
        [double]$TargetSizeGB,

        [Parameter(Mandatory=$true)]
        [int]$OlderThanMonths,

        [Parameter(Mandatory=$true)]
        [int]$BatchLimit
    )

    if ($HighWatermarkGB -le 0) {
        throw "Source PST high watermark must be greater than 0 GB. Current value: $HighWatermarkGB."
    }

    if ($TargetSizeGB -le 0) {
        throw "Source PST target size must be greater than 0 GB. Current value: $TargetSizeGB."
    }

    if ($TargetSizeGB -ge $HighWatermarkGB) {
        throw "Source PST target size ($TargetSizeGB GB) must be smaller than high watermark ($HighWatermarkGB GB)."
    }

    if ($OlderThanMonths -lt 0) {
        throw "OlderThanMonths cannot be negative. Current value: $OlderThanMonths."
    }

    if ($BatchLimit -le 0) {
        throw "Storage policy batch limit must be greater than 0. Current value: $BatchLimit."
    }

    $true
}

function Get-OPAAverageMessageSize {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst)

    # Default for unknown sources: 100 KB is a reasonable middle ground for
    # typical corporate email (no attachments, HTML body).
    $default = [int64](100 * 1KB)

    $dir = Join-Path ([IO.Path]::GetDirectoryName($SourcePst)) 'OutlookPOP3Archive-Transactions'
    if (-not (Test-Path -LiteralPath $dir)) { return $default }

    # Use the last few completed transactions for a stable estimate.
    $latest = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'DuplicateIndex.json' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5)

    $sumBytes = [int64]0
    $sumCount = [int64]0
    foreach ($f in $latest) {
        try {
            $s = Read-OPAJsonFile -Path $f.FullName
            if ([string]$s.Status -ne 'Completed') { continue }
            $exec  = if ($s.PSObject.Properties.Name -contains 'Executed')         { [int64]$s.Executed }         else { 0 }
            $freed = if ($s.PSObject.Properties.Name -contains 'LogicalFreedBytes') { [int64]$s.LogicalFreedBytes } else { 0 }
            if ($exec -gt 0 -and $freed -gt 0) {
                $sumBytes += $freed
                $sumCount += $exec
            }
        } catch { }
    }

    if ($sumCount -le 0) { return $default }
    return [int64]($sumBytes / $sumCount)
}

function Get-OPASourceCumulativeLogicalFreedBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst)

    $dir = Join-Path ([IO.Path]::GetDirectoryName($SourcePst)) 'OutlookPOP3Archive-Transactions'
    if (-not (Test-Path -LiteralPath $dir)) { return [int64]0 }

    $total = [int64]0
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -eq 'DuplicateIndex.json') { continue }
        try {
            $s = Read-OPAJsonFile -Path $f.FullName
            if ([string]$s.Status -ne 'Completed') { continue }
            if ($s.PSObject.Properties.Name -contains 'LogicalFreedBytes') {
                $total += [int64]$s.LogicalFreedBytes
            }
        } catch { }
    }
    return $total
}

# FIX13: an Auto-only storage-progress sidecar is kept separately from the
# transaction checkpoints and journals. It must NEVER be deleted by the
# Completed-checkpoint retention policy. The .state extension deliberately
# avoids checkpoint discovery (*.json) and step journal discovery (*.jsonl).
function Get-OPAAutoStorageProgressPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst)
    $full = [IO.Path]::GetFullPath($SourcePst)
    $dir = Join-Path ([IO.Path]::GetDirectoryName($full)) 'OutlookPOP3Archive-Transactions'
    return (Join-Path $dir ([IO.Path]::GetFileName($full) + '.auto-storage.state'))
}

function Get-OPAAutoStorageProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][ValidateRange(0,9223372036854775807)][int64]$CurrentPhysicalBytes
    )
    $path = Get-OPAAutoStorageProgressPath -SourcePst $SourcePst
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    # Corrupted or foreign sidecars are safety errors. Never reset silently,
    # because doing so could silently restart removal of old mail.
    $state = Read-OPAJsonFile -Path $path
    $properties = @($state.PSObject.Properties.Name)
    foreach ($key in @('Version','SourcePst','BaselinePhysicalBytes',
                      'LastPhysicalBytes','CumulativeLogicalFreedBytes',
                      'EmptyBatchCount','CompletedBatches','CompletedTransactionIds')) {
        if ($properties -notcontains $key) {
            throw "Auto Storage Progress: missing field '$key' in '$path'; manual review required."
        }
    }
    if ([int]$state.Version -ne 1 -or
        -not ([IO.Path]::GetFullPath([string]$state.SourcePst) -ieq [IO.Path]::GetFullPath($SourcePst))) {
        throw "Auto Storage Progress: version or source PST mismatch for '$path'; manual review required."
    }
    foreach ($key in @('BaselinePhysicalBytes','LastPhysicalBytes',
                      'CumulativeLogicalFreedBytes','EmptyBatchCount','CompletedBatches')) {
        if ([int64]$state.$key -lt 0) {
            throw "Auto Storage Progress: invalid negative '$key' in '$path'."
        }
    }
    if ([int64]$state.CumulativeLogicalFreedBytes -gt [int64]::MaxValue / 2) {
        throw "Auto Storage Progress: invalid cumulative bytes in '$path'."
    }
    $knownIds = @($state.CompletedTransactionIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ([int64]$state.CompletedBatches -gt 0 -and $knownIds.Count -eq 0) {
        throw "Auto Storage Progress: missing transaction IDs in '$path'."
    }
    # A real physical shrink (for example after Compact) invalidates this
    # accounting epoch. The next successful Auto batch writes a new baseline;
    # reads remain side-effect free, including Plan and Auto -WhatIf.
    if (([double]$state.LastPhysicalBytes - [double]$CurrentPhysicalBytes) -gt 1MB) {
        return $null
    }
    return $state
}

function Register-OPAAutoStorageProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        # Called only after independent Outlook verification and before the
        # Completed checkpoint is committed. If this write fails, the old
        # checkpoint stays pending and Auto must Resume, not start a new batch.
        [switch]$ConfirmedVerifiedCompletion
    )
    $tx = $Transaction.State
    if ([string]$tx.Status -ne 'Completed' -and -not $ConfirmedVerifiedCompletion) {
        throw 'Auto Storage Progress: only Completed transactions can be credited.'
    }
    if ([int]$tx.Executed -lt [int]$tx.Planned) {
        throw 'Auto Storage Progress: cannot pre-credit an incomplete batch.'
    }
    if ([int]$tx.Executed -ne [int]$tx.Verified) {
        throw 'Auto Storage Progress: transaction has not been independently verified.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$tx.SourcePst)) {
        throw 'Auto Storage Progress: missing source PST.'
    }
    $source = [IO.Path]::GetFullPath([string]$tx.SourcePst)
    $physical = Get-OPAPstFileSize -PstPath $source
    $now = [int64]$physical.SizeBytes
    $existing = Get-OPAAutoStorageProgress -SourcePst $source -CurrentPhysicalBytes $now
    $txId = [string]$Transaction.TransactionId
    if ([string]::IsNullOrWhiteSpace($txId)) { throw 'Auto Storage Progress: missing transaction ID.' }
    if ($null -ne $existing -and
        @($existing.CompletedTransactionIds | Where-Object { [string]$_ -ceq $txId }).Count -gt 0) {
        return $existing
    }

    $initial = [int64]$tx.SourcePstSizeBeforeBytes
    if ($initial -le 0) { $initial = $now }
    $logical = [int64]$tx.LogicalFreedBytes
    if ($logical -lt 0) { throw 'Auto Storage Progress: logical freed bytes cannot be negative.' }
    $ids = @()
    $base = $initial
    $total = [int64]0
    $empty = 0
    $completed = 0
    if ($null -ne $existing) {
        $ids = @($existing.CompletedTransactionIds | ForEach-Object { [string]$_ })
        $base = [int64]$existing.BaselinePhysicalBytes
        $total = [int64]$existing.CumulativeLogicalFreedBytes
        $empty = [int]$existing.EmptyBatchCount
        $completed = [int]$existing.CompletedBatches
    }
    if ($logical -gt ([int64]::MaxValue - $total)) {
        throw 'Auto Storage Progress: logical counter overflow.'
    }
    $total += $logical
    if ($logical -le 0 -or [int]$tx.Executed -le 0) { $empty++ } else { $empty = 0 }
    $completed++
    # Keep a bounded idempotency window in the sidecar.
    $ids = @($ids + @($txId) | Select-Object -Last 256)
    $next = [pscustomobject]@{
        Version = 1
        SourcePst = $source
        BaselinePhysicalBytes = [int64]$base
        LastPhysicalBytes = [int64]$now
        CumulativeLogicalFreedBytes = [int64]$total
        EmptyBatchCount = [int]$empty
        CompletedBatches = [int]$completed
        CompletedTransactionIds = @($ids)
        UpdatedAt = (Get-Date).ToString('o')
    }
    $path = Get-OPAAutoStorageProgressPath -SourcePst $source
    $json = ConvertTo-Json -InputObject $next -Depth 6
    Write-OPAAtomicTextFile -Path $path -Content $json
    return $next
}

# Read-only diagnostic: physical allocation and logical content removal are
# different quantities. Do not promise exact Compact gains from this estimate.
function Get-OPAStorageReclaimEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateRange(0,9223372036854775807)][int64]$PhysicalBeforeBytes,
        [Parameter(Mandatory=$true)][ValidateRange(0,9223372036854775807)][int64]$PhysicalAfterBytes,
        [Parameter(Mandatory=$true)][ValidateRange(0,9223372036854775807)][int64]$LogicalFreedBytes
    )
    # Math.Max(0, <large number>) binds to the Int32 overload on Windows
    # PowerShell 5.1 and can throw even when the result should be zero.
    # Byte counts are Int64 throughout; avoid Double rounding as well.
    $physicalReduction = [Math]::Max([int64]0, ([int64]$PhysicalBeforeBytes - [int64]$PhysicalAfterBytes))
    $physicalGrowth = [Math]::Max([int64]0, ([int64]$PhysicalAfterBytes - [int64]$PhysicalBeforeBytes))
    [pscustomobject]@{
        PhysicalReductionBytes = $physicalReduction
        PhysicalGrowthBytes = $physicalGrowth
        LogicalFreedBytes = $LogicalFreedBytes
        UnmatchedLogicalReductionBytes = [Math]::Max([int64]0, ([int64]$LogicalFreedBytes - [int64]$physicalReduction))
        CompactAssessment = if ($LogicalFreedBytes -gt 0 -and $physicalReduction -lt $LogicalFreedBytes) { 'ReviewRecommended' } else { 'NotIndicated' }
    }
}

function Get-OPAStoragePolicyDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePst,

        [Parameter(Mandatory=$true)]
        [double]$HighWatermarkGB,

        [Parameter(Mandatory=$true)]
        [double]$TargetSizeGB,

        [Parameter(Mandatory=$true)]
        [int]$OlderThanMonths,

        [Parameter(Mandatory=$true)]
        [int]$BatchLimit,

        [ValidateRange(1,1000)]
        [int]$AutoMaxEmptyBatches = 2
    )

    Test-OPAStoragePolicyConfiguration `
        -HighWatermarkGB $HighWatermarkGB `
        -TargetSizeGB $TargetSizeGB `
        -OlderThanMonths $OlderThanMonths `
        -BatchLimit $BatchLimit | Out-Null

    $size = Get-OPAPstFileSize -PstPath $SourcePst
    $highBytes = Convert-OPAStoragePolicyGBToBytes -Gigabytes $HighWatermarkGB
    $targetBytes = Convert-OPAStoragePolicyGBToBytes -Gigabytes $TargetSizeGB

    $progress = Get-OPAAutoStorageProgress -SourcePst $size.Path -CurrentPhysicalBytes $size.SizeBytes
    $logical = [int64]0
    $emptyBatches = 0
    $batches = 0
    if ($null -ne $progress) {
        $logical = [int64]$progress.CumulativeLogicalFreedBytes
        $emptyBatches = [int]$progress.EmptyBatchCount
        $batches = [int]$progress.CompletedBatches
    }
    # FIX13b: use the Int64 overload explicitly. With the default
    # 40/35 GB thresholds and a 7 GB source, the negative difference
    # is below Int32.MinValue and an untyped 0 causes a binding error.
    $physicalOverTarget = [Math]::Max([int64]0, ([int64]$size.SizeBytes - [int64]$targetBytes))
    $logicalStillNeeded = [Math]::Max([int64]0, ([int64]$physicalOverTarget - [int64]$logical))
    $decision = 'NoAction'
    $reason = "Source PST size $($size.SizeGB) GB is at or below high watermark $HighWatermarkGB GB."
    if ($size.SizeBytes -gt $highBytes) {
        if ($logicalStillNeeded -eq 0 -and $logical -gt 0) {
            $decision = 'CompactRequired'
            $reason = 'Logical archive reduction has met the target, but PST physical allocation is still above the high watermark. Do not archive more mail automatically; review Compact.'
        }
        elseif ($emptyBatches -ge $AutoMaxEmptyBatches) {
            $decision = 'AutoPaused'
            $reason = "No logical progress in $emptyBatches consecutive verified Auto batches. Further automatic removal is paused."
        }
        else {
            $decision = 'ArchiveRequired'
            $reason = "Source PST size $($size.SizeGB) GB is above high watermark $HighWatermarkGB GB; logical reduction still required."
        }
    }
    return [pscustomobject]@{
        Decision = $decision
        SourcePst = $size.Path
        SourceSizeBytes = $size.SizeBytes
        SourceSizeGB = $size.SizeGB
        HighWatermarkGB = $HighWatermarkGB
        TargetSizeGB = $TargetSizeGB
        PhysicalBytesAboveTarget = $physicalOverTarget
        RequiredReductionBytes = if ($decision -eq 'ArchiveRequired') { $logicalStillNeeded } else { [int64]0 }
        RequiredReductionGB = if ($decision -eq 'ArchiveRequired') { [Math]::Round(([double]$logicalStillNeeded / 1GB),2) } else { 0 }
        CumulativeLogicalFreedBytes = $logical
        RemainingLogicalTargetBytes = $logicalStillNeeded
        CompletedAutoBatches = $batches
        EmptyAutoBatches = $emptyBatches
        CompactRecommended = ($decision -eq 'CompactRequired')
        OlderThanMonths = $OlderThanMonths
        BatchLimit = $BatchLimit
        Reason = $reason
    }
}

function Write-OPAStoragePolicyDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Decision
    )

    Write-Host ''
    Write-Host '## Storage Policy'
    Write-Host ("Source PST       : {0}" -f $Decision.SourcePst)
    Write-Host ("Current size     : {0} GB (physical)" -f $Decision.SourceSizeGB)
    Write-Host ("High watermark   : {0} GB" -f $Decision.HighWatermarkGB)
    Write-Host ("Target size      : {0} GB" -f $Decision.TargetSizeGB)
    Write-Host ("Older than       : {0}" -f $(if ($Decision.OlderThanMonths -gt 0) { "$($Decision.OlderThanMonths) months" } else { 'Disabled' }))
    Write-Host ("Batch limit      : {0}" -f $Decision.BatchLimit)
    Write-Host ("Decision         : {0}" -f $Decision.Decision)

    if ($Decision.Decision -ne 'NoAction') {
        Write-Host ("Physical bytes above target : {0:N2} MB" -f ([double]$Decision.PhysicalBytesAboveTarget / 1MB))
        Write-Host ("Credited logical removal    : {0:N2} MB" -f ([double]$Decision.CumulativeLogicalFreedBytes / 1MB))
        Write-Host ("Remaining logical objective : {0:N2} MB" -f ([double]$Decision.RemainingLogicalTargetBytes / 1MB))
        Write-Host ("Verified Auto batches       : {0} (empty in a row: {1})" -f $Decision.CompletedAutoBatches,$Decision.EmptyAutoBatches)
    }
    if ($Decision.Decision -in @('CompactRequired','AutoPaused')) {
        Write-Host 'Auto paused: no additional mail will be removed automatically.' -ForegroundColor Yellow
        Write-Host 'Compact is assessment-only; use Outlook maintenance after backup and integrity verification.' -ForegroundColor Yellow
    }

    Write-Host ("Reason           : {0}" -f $Decision.Reason)
}
