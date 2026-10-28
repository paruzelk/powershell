# Step persistence model (schema 2.5.4 / build 2.5.7):
#   - Every step is appended to an append-only journal file
#     (<TransactionId>.steps.jsonl) — cheap, durable, survives a crash.
#   - The checkpoint JSON keeps only a sliding window of the newest
#     $script:OPAStepsInlineLimit steps, so checkpoint size stays bounded and
#     no O(n^2) full-state rewrite happens per move.
#   - Get-OPAArchiveTransaction merges journal tail + window; readers always
#     see the complete history.

$script:OPAStepsInlineLimit = 200
$script:OPASkippedInlineLimit = 200

function Test-OPAStateHasKey {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$State,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($null -eq $State) { return $false }
    # New transactions use [ordered]@{} / OrderedDictionary, while loaded
    # checkpoints may be PSCustomObjects. PSObject.Properties does not expose
    # dictionary keys as properties, so support both representations explicitly.
    if ($State -is [System.Collections.IDictionary]) {
        return [bool]$State.Contains($Name)
    }
    return (@($State.PSObject.Properties.Name) -contains $Name)
}

function Ensure-OPATransactionPerformance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$TransactionState
    )

    $performance = $null
    if ($TransactionState -is [System.Collections.IDictionary]) {
        if ($TransactionState.Contains('Performance')) {
            $performance = $TransactionState['Performance']
        }
        if ($null -eq $performance) {
            $performance = [ordered]@{}
            $TransactionState['Performance'] = $performance
        }
    }
    else {
        if ($TransactionState.PSObject.Properties.Name -contains 'Performance') {
            $performance = $TransactionState.Performance
        }
        if ($null -eq $performance) {
            $performance = [ordered]@{}
            $TransactionState | Add-Member -NotePropertyName Performance -NotePropertyValue $performance -Force
        }
    }

    return $performance
}

function Set-OPAPerformanceValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Performance,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$Value
    )
    if ($Performance -is [System.Collections.IDictionary]) {
        $Performance[$Name] = $Value
    }
    else {
        $Performance | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Test-OPAMoveCompletionStep {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Step)

    if ($null -eq $Step) { return $false }
    $name = [string]$Step.Step
    # 2.5.7 explicitly distinguishes Move Started from a completed move.
    # Keep compatibility with the legacy 2.5.4/2.5.6 'Move n/n' entries.
    if ($name -eq 'Move Completed' -or $name -eq 'Move Reconciled') { return $true }
    return ($name -match '^Move \d+/\d+$')
}

function Test-OPAArchiveTransactionSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$TransactionState
    )

    if ($null -eq $TransactionState) {
        throw 'Transaction checkpoint is null.'
    }

    # The validator runs against two shapes:
    #   - fresh in-memory state from [ordered]@{} (OrderedDictionary)
    #   - reloaded state from ConvertFrom-Json (PSCustomObject)
    # PSObject.Properties.Name on an OrderedDictionary returns the
    # collection's intrinsic members on Windows PowerShell 5.1, not the
    # user-visible keys, so read Keys directly for IDictionary.
    $availableNames = @()
    if ($TransactionState -is [System.Collections.IDictionary]) {
        foreach ($key in $TransactionState.Keys) { $availableNames += [string]$key }
    }
    else {
        $availableNames = @($TransactionState.PSObject.Properties.Name)
    }

    $required = @(
        'TransactionId','SourcePst','ArchivePst','Status','Limit',
        'Planned','Executed','Verified','PlannedItems','Steps',
        'ArchivePsts','CurrentArchivePst','LogicalFreedBytes','AccountEmail',
        'SourcePstSizeBeforeBytes','SourcePstSizeAfterBytes','Skipped','SkippedItems',
        'JournalOffsetBytes','SkippedEntryIds'
    )

    foreach ($name in $required) {
        if ($availableNames -notcontains $name) {
            throw "Transaction checkpoint is missing required field '$name'."
        }
    }

    $version = if ($availableNames -contains 'Version') {
        [string]$TransactionState.Version
    }
    else { '' }

    $schemaVersion = if ($availableNames -contains 'SchemaVersion') {
        [string]$TransactionState.SchemaVersion
    }
    else { $version }

    if ($script:OPATransactionSchemaSupported -notcontains $schemaVersion) {
        throw "Unsupported transaction schema version '$schemaVersion'. Supported versions: $($script:OPATransactionSchemaSupported -join ', ')."
    }

    if ($version -and $script:OPATransactionSchemaSupported -notcontains $version) {
        throw "Unsupported transaction version '$version'. Supported versions: $($script:OPATransactionSchemaSupported -join ', ')."
    }

    if ([string]::IsNullOrWhiteSpace([string]$TransactionState.TransactionId)) {
        throw 'Transaction checkpoint has an empty TransactionId.'
    }

    if ([string]::IsNullOrWhiteSpace([string]$TransactionState.SourcePst)) {
        throw 'Transaction checkpoint has an empty SourcePst.'
    }

    $archivePst = [string]$TransactionState.ArchivePst
    $archivePstsCount = @($TransactionState.ArchivePsts).Count
    $currentArchivePst = [string]$TransactionState.CurrentArchivePst
    if ([string]::IsNullOrWhiteSpace($archivePst)) {
        # The first archive PST is selected lazily by MailMover. An empty
        # ArchivePst is valid only before the first archive PST is registered.
        if ($archivePstsCount -gt 0 -or -not [string]::IsNullOrWhiteSpace($currentArchivePst)) {
            throw 'Transaction checkpoint has an inconsistent empty ArchivePst.'
        }
    }

    if ([int]$TransactionState.Limit -le 0) {
        throw 'Transaction checkpoint has no valid positive Limit.'
    }

    return $true
}

function Repair-OPAArchiveTransactionStepsFromDuplicateIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object]$DuplicateIndex
    )

    $existingIds = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($step in @($Transaction.State.Steps)) {
        if ($step -and $step.EntryId -and (Test-OPAMoveCompletionStep -Step $step)) {
            [void]$existingIds.Add([string]$step.EntryId)
        }
    }

    $repaired = 0
    $steps = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($Transaction.State.Steps)) { $steps.Add($s) | Out-Null }

    $entries = @(
        $DuplicateIndex.Entries |
            Where-Object { [string]$_.TransactionId -eq [string]$Transaction.TransactionId }
    )

    foreach ($entry in $entries) {
        $sourceId = [string]$entry.SourceEntryId
        if ([string]::IsNullOrWhiteSpace($sourceId)) { continue }
        if ($existingIds.Contains($sourceId)) { continue }

        $steps.Add([ordered]@{
            Time             = (Get-Date).ToString('o')
            Step             = 'Move Reconciled'
            Message          = 'Recovered Move journal entry from DuplicateIndex after checkpoint lag'
            EntryId          = $sourceId
            ArchiveEntryId   = [string]$entry.ArchiveEntryId
            TargetFolderPath = [string]$entry.TargetFolderPath
            ReceivedTime     = [string]$entry.ReceivedTime
        }) | Out-Null

        [void]$existingIds.Add($sourceId)
        $repaired++
    }

    if ($repaired -gt 0) {
        $window = @($steps | Select-Object -Last $script:OPAStepsInlineLimit)
        $Transaction.State.Steps = $window
        $Transaction.State.Updated = (Get-Date).ToString('o')
        # Persistence model (schema 2.5.x):
        #   This function only mutates the in-memory window. The repaired
        #   steps will be flushed by the next Save-OPAArchiveTransaction
        #   call at a terminal status or via -WriteCheckpoint. If the
        #   process dies before that flush, the next run recomputes the same
        #   repair from DuplicateIndex - the operation is idempotent, so the
        #   transient window loss is safe. Do NOT add an unconditional write
        #   here: it would double the checkpoint cost on the resume path.
    }

    return $repaired
}

function Get-OPAResumeCompletionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object]$DuplicateIndex
    )

    $plannedById = @{}
    foreach ($item in @($Transaction.State.PlannedItems)) {
        $id = [string]$item.EntryId
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $plannedById[$id] = $item
        }
    }

    $completed = @{}

    # Transaction Move steps are the normal journal. Keep the newest useful
    # destination EntryID for each source EntryID.
    foreach ($step in @($Transaction.State.Steps)) {
        if (-not $step -or -not (Test-OPAMoveCompletionStep -Step $step)) { continue }

        $sourceId = [string]$step.EntryId
        $archiveId = [string]$step.ArchiveEntryId
        if ([string]::IsNullOrWhiteSpace($sourceId) -or -not $plannedById.ContainsKey($sourceId)) { continue }

        if (-not $completed.ContainsKey($sourceId) -or
            [string]::IsNullOrWhiteSpace([string]$completed[$sourceId].ArchiveEntryId)) {
            $completed[$sourceId] = [pscustomobject]@{
                SourceEntryId  = $sourceId
                ArchiveEntryId = $archiveId
            }
        }
    }

    # DuplicateIndex is authoritative when a Move completed before its
    # transaction step was persisted, including ReconciledFromArchive paths.
    foreach ($entry in @($DuplicateIndex.Entries)) {
        if ([string]$entry.TransactionId -ne [string]$Transaction.TransactionId) { continue }

        $sourceId = [string]$entry.SourceEntryId
        if ([string]::IsNullOrWhiteSpace($sourceId) -or -not $plannedById.ContainsKey($sourceId)) { continue }

        $archiveId = [string]$entry.ArchiveEntryId
        if (-not $completed.ContainsKey($sourceId)) {
            $completed[$sourceId] = [pscustomobject]@{
                SourceEntryId  = $sourceId
                ArchiveEntryId = $archiveId
            }
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$completed[$sourceId].ArchiveEntryId) -and
                -not [string]::IsNullOrWhiteSpace($archiveId)) {
            $completed[$sourceId].ArchiveEntryId = $archiveId
        }
    }

    $sourceIds = @($completed.Keys | Sort-Object)
    $archiveIds = @(
        $sourceIds |
            ForEach-Object { [string]$completed[$_].ArchiveEntryId } |
            Where-Object { $_ } |
            Select-Object -Unique
    )

    [pscustomobject]@{
        CompletedCount   = $sourceIds.Count
        SourceEntryIds   = $sourceIds
        ArchiveEntryIds  = $archiveIds
        CompletedEntries = @($sourceIds | ForEach-Object { $completed[$_] })
        PlannedCount     = $plannedById.Count
    }
}

function Write-OPAAtomicTextFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $tmp = "$Path.tmp.$([guid]::NewGuid().ToString('N'))"

    try {
        $utf8 = New-Object System.Text.UTF8Encoding($true)
        [IO.File]::WriteAllText($tmp, $Content, $utf8)

        if (Test-Path -LiteralPath $Path) {
            try {
                [IO.File]::Replace($tmp, $Path, $null, $true)
            }
            catch {
                Move-Item -LiteralPath $tmp -Destination $Path -Force
            }
        }
        else {
            Move-Item -LiteralPath $tmp -Destination $Path -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-OPAStepJournalPath {
    param([Parameter(Mandatory=$true)][object]$Transaction)
    if ([string]$Transaction.Path -match '\.json$') {
        return ([string]$Transaction.Path -replace '\.json$', '.steps.jsonl')
    }
    return "$($Transaction.Path).steps.jsonl"
}

# --- Step journal streams ----------------------------------------------------
# A fresh [IO.File]::AppendAllText per move opens+closes the file 500+ times
# per batch, which is measurably slow under AV real-time scanning. Keeping a
# FileStream open for the lifetime of the run removes that overhead. Normal
# event writes use Flush(false); Flush(true) is reserved for durability boundaries.
# Process-wide map of open step-journal FileStreams. Must be $global: (not
# $script:) because PowerShell's $script: scope differs between a script's
# top-level and Pester's BeforeAll/It/AfterAll blocks — a $script: hashtable
# populated from one scope is invisible from another, and the resulting
# leak keeps the file locked until process exit.
$global:OPAStepJournalStreams = @{}

function Get-OPAStepJournalStream {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

        if ($global:OPAStepJournalStreams.ContainsKey($Path)) {
        $stream = $global:OPAStepJournalStreams[$Path]
        try { if ($stream.CanWrite) { return $stream } } catch {}
        try { $stream.Dispose() } catch {}
        $global:OPAStepJournalStreams.Remove($Path)
    }

    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $fs = New-Object System.IO.FileStream(
        $Path,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::ReadWrite
    )
    $fs.Position = $fs.Length

    # Preserve valid unterminated JSON; quarantine and trim only a broken tail.
    # Never turn a partial record into a malformed middle record.
    if ($fs.Length -gt 0) {
        $fs.Position = $fs.Length - 1
        $lastByte = $fs.ReadByte()
        if ($lastByte -ne 10 -and $lastByte -ne 13) {
            $start = [long]0
            $pos = $fs.Length - 1
            while ($pos -ge 0) {
                $fs.Position = $pos
                $b = $fs.ReadByte()
                if ($b -eq 10 -or $b -eq 13) { $start = $pos + 1; break }
                $pos--
            }
            $tailSize = [int]($fs.Length - $start)
            $tailBytes = New-Object byte[] $tailSize
            $fs.Position = $start
            [void]$fs.Read($tailBytes, 0, $tailBytes.Length)
            $raw = [System.Text.Encoding]::UTF8.GetString($tailBytes)
            $valid = $false
            try {
                $parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
                $valid = ($null -ne $parsed)
            } catch {}
            if ($valid) {
                $nl = [byte[]]@(10)
                $fs.Position = $fs.Length
                $fs.Write($nl, 0, $nl.Length)
                $fs.Flush($true)
            }
            else {
                $backup = '{0}.corrupt-{1}-{2}.bin' -f $Path, (Get-Date -Format 'yyyyMMddHHmmss'), [guid]::NewGuid().ToString('N').Substring(0,8)
                [IO.File]::WriteAllBytes($backup, $tailBytes)
                $fs.SetLength($start)
                $fs.Flush($true)
                Write-Warning ("Quarantined truncated JSONL tail ({0} bytes) to '{1}'." -f $tailSize, $backup)
            }
        }
    }
    $fs.Position = $fs.Length
    $global:OPAStepJournalStreams[$Path] = $fs
    return $fs
}

function Add-OPAStepJournalEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object]$Step
    )

    $path = Get-OPAStepJournalPath -Transaction $Transaction
    $fs = Get-OPAStepJournalStream -Path $path
    # -InputObject (not pipeline) is critical: piping an OrderedDictionary
    # enumerates it into DictionaryEntry values on Windows PowerShell 5.1,
    # producing a JSON *array* per line instead of a JSON object. That array
    # shape then propagates into Read-OPAStepJournal as Object[] elements,
    # which in turn breaks @() on the mixed-type List[object].
    $line = ConvertTo-Json -InputObject $Step -Depth 6 -Compress
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8.GetBytes($line + [Environment]::NewLine)
    $fs.Write($bytes, 0, $bytes.Length)
    # Durability mode: Safe force-flushes every line, minimizing the window
    # of journal loss on OS/power failure. Fast flushes to OS cache only and
    # relies on the batch-boundary Sync-OPAStepJournalStreams call (default,
    # fastest). Safe is slower on storage where FlushFileBuffers is costly.
    $isSafe = ($global:OPADurabilityMode -eq 'Safe')
    $fs.Flush($isSafe)
}

function Close-OPAStepJournalStreams {
    [CmdletBinding()]
    param()

    if ($null -eq $global:OPAStepJournalStreams -or $global:OPAStepJournalStreams.Count -eq 0) { return }
    foreach ($key in @($global:OPAStepJournalStreams.Keys)) {
        $s = $global:OPAStepJournalStreams[$key]
        try { $s.Flush($true); $s.Dispose() } catch {}
    }
    $global:OPAStepJournalStreams = @{}
}

function Sync-OPAStepJournalStreams {
    [CmdletBinding()]
    param()

    foreach ($key in @($global:OPAStepJournalStreams.Keys)) {
        $stream = $global:OPAStepJournalStreams[$key]
        if ($null -eq $stream) { continue }
        try {
            if ($stream.CanWrite) { $stream.Flush($true) }
        }
        catch {
            throw ("Failed to flush step journal '{0}' before checkpoint: {1}" -f [string]$key, $_.Exception.Message)
        }
    }

    # The DuplicateIndex append-only journal is a parallel durability stream.
    # It shares the same sync points as the step journal, so flush it here.
    if (Get-Command -Name 'Sync-OPADuplicateJournalStreams' -ErrorAction SilentlyContinue) {
        Sync-OPADuplicateJournalStreams
    }
}

function Read-OPAJsonlLocal {
    # Self-contained JSONL reader used by the step journal. Streaming: at
    # most two lines are held in memory at once; the next line is read only
    # to decide whether the current one is the last. Tail mode keeps a
    # bounded ring instead of the full set. Malformed last line is a
    # tolerated crash fragment; malformed middle line is a hard error.
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [long]$FromOffset = 0,
        [int]$TailCount = 0,
        [string]$Context = 'Step journal'
    )

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    $fs = $null; $reader = $null
    try {
        $fs = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        if ($FromOffset -gt 0 -and $FromOffset -lt $fs.Length) { $fs.Position = $FromOffset }
        $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)

        $list = $null
        $ring = $null
        if ($TailCount -gt 0) {
            $ring = New-Object 'System.Collections.Generic.Queue[object]'
        }
        else {
            $list = New-Object System.Collections.Generic.List[object]
        }

        $lineNo = 0
        $pending = $reader.ReadLine()
        while ($null -ne $pending) {
            $lineNo++
            $next = $reader.ReadLine()
            $isLast = ($null -eq $next)

            $raw = $pending
            $pending = $next

            if ([string]::IsNullOrWhiteSpace($raw)) { continue }

            $parsed = $null
            try { $parsed = ConvertFrom-Json -InputObject $raw }
            catch {
                if ($isLast) {
                    Write-Warning ("{0} '{1}': last line is malformed ({2} chars), skipping." -f $Context, $Path, $raw.Length)
                    continue
                }
                $preview = if ($raw.Length -gt 120) { $raw.Substring(0,120) + '...' } else { $raw }
                throw ("{0} '{1}' is corrupted at line {2}. Malformed JSON: {3}" -f $Context, $Path, $lineNo, $preview)
            }
            if ($null -eq $parsed) { continue }

            if ($null -ne $ring) {
                foreach ($el in @($parsed)) {
                    if ($null -ne $el) { [void]$ring.Enqueue($el) }
                    while ($ring.Count -gt $TailCount) { [void]$ring.Dequeue() }
                }
            }
            else {
                if ($parsed -is [System.Array]) {
                    foreach ($el in $parsed) { if ($null -ne $el) { $list.Add($el) | Out-Null } }
                }
                else {
                    $list.Add($parsed) | Out-Null
                }
            }
        }

        if ($null -ne $ring) {
            $arr = New-Object System.Collections.Generic.List[object]
            foreach ($el in $ring) { $arr.Add($el) | Out-Null }
            return $arr.ToArray()
        }
        return $list.ToArray()
    }
    finally {
        if ($reader) { try { $reader.Dispose() } catch {} }
        if ($fs)     { try { $fs.Dispose() } catch {} }
    }
}

function Read-OPAStepJournal {
    param([Parameter(Mandatory=$true)][object]$Transaction)
    $path = Get-OPAStepJournalPath -Transaction $Transaction
    return Read-OPAJsonlLocal -Path $path -Context 'Step journal'
}

function Read-OPAStepJournalFrom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [long]$FromOffset = 0
    )
    return Read-OPAJsonlLocal -Path $Path -FromOffset $FromOffset -Context 'Step journal'
}

function Read-OPAStepJournalTail {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$TailCount = 200
    )
    return Read-OPAJsonlLocal -Path $Path -TailCount $TailCount -Context 'Step journal'
}



function New-OPAArchiveTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$ArchivePst,
        [int]$Limit = 0,
        [string]$FolderPath,
        [string]$ArchiveGrouping = 'YearQuarter',
        [int]$OlderThanMonths = 12,
        [object]$ArchiveCutoff,
        [int64]$SourcePstSizeBeforeBytes = 0,
        [string]$AccountEmail,
        [bool]$ArchiveDeletedItems = $false,
        [bool]$ArchiveDrafts = $false,
        [bool]$ArchiveJunk = $false,
        [ValidateSet('Fast','Safe')]
        [string]$DurabilityMode = 'Fast'
    )

    $id = '{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $base = Join-Path ([IO.Path]::GetDirectoryName($SourcePst)) 'OutlookPOP3Archive-Transactions'

    if (-not (Test-Path -LiteralPath $base)) {
        New-Item -ItemType Directory -Path $base -Force | Out-Null
    }

    $path = Join-Path $base "$id.json"
    $state = [ordered]@{
        TransactionId      = $id
        Version            = $script:OPATransactionSchemaVersion
        SchemaVersion      = $script:OPATransactionSchemaVersion
        ApplicationVersion = $script:OPAApplicationVersion
        Status             = 'Created'
        Started            = (Get-Date).ToString('o')
        Updated            = (Get-Date).ToString('o')
        SourcePst          = $SourcePst
        AccountEmail       = $AccountEmail
        DurabilityMode     = $DurabilityMode
        ArchiveDeletedItems = $ArchiveDeletedItems
        ArchiveDrafts       = $ArchiveDrafts
        ArchiveJunk         = $ArchiveJunk
        ArchivePst         = $ArchivePst
        ArchivePsts        = @()
        CurrentArchivePst  = $ArchivePst
        LogicalFreedBytes  = [int64]0
        SourcePstSizeBeforeBytes = [int64]$SourcePstSizeBeforeBytes
        SourcePstSizeAfterBytes  = [int64]$SourcePstSizeBeforeBytes
        FolderPath         = $FolderPath
        Limit              = $Limit
        ArchiveGrouping    = $ArchiveGrouping
        OlderThanMonths    = $OlderThanMonths
        ArchiveCutoff      = if($null -ne $ArchiveCutoff){$ArchiveCutoff.ToString('o')}else{$null}
        Planned            = 0
        Executed           = 0
        Verified           = 0
        Skipped            = 0
        SkippedItems       = @()
        SkippedEntryIds    = @()
        Performance       = [ordered]@{ MovesThisRun = 0; ResumeMovedNow = 0 }
        JournalOffsetBytes = [int64]0
        PlannedItems       = @()
        Steps              = @()
    }

    $json = ConvertTo-Json -InputObject $state -Depth 12
    Write-OPAAtomicTextFile -Path $path -Content $json

    [pscustomobject]@{
        TransactionId = $id
        Path          = $path
        State         = $state
    }
}

function Register-OPAArchivePstInTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][string]$ArchivePst,
        [int]$Year = 0,
        [int]$Part = 1,
        [int64]$PhysicalSizeBeforeBytes = 0
    )

    $state = $Transaction.State
    $list = @($state.ArchivePsts)
    $existing = @($list | Where-Object { [string]$_.Path -ieq $ArchivePst } | Select-Object -First 1)
    if ($existing.Count -eq 0) {
        $list += [pscustomobject]@{
            Path = $ArchivePst
            Year = $Year
            Part = $Part
            CreatedAt = (Get-Date).ToString('o')
            PhysicalSizeBeforeBytes = [int64]$PhysicalSizeBeforeBytes
            PhysicalSizeAfterBytes = [int64]$PhysicalSizeBeforeBytes
            PhysicalGrowthBytes = [int64]0
            LogicalAddedBytes = [int64]0
            LastMeasuredAt = $null
            PhysicalSizeBaselineCaptured = $true
        }
    }
    else {
        # Keep metadata authoritative when an existing PST is revisited.
        foreach ($entry in @($list)) {
            if ([string]$entry.Path -ieq [string]$ArchivePst) {
                $entry.Year = $Year
                $entry.Part = $Part
                break
            }
        }
    }

    foreach ($entry in @($list)) {
        if ($entry.PSObject.Properties.Name -notcontains 'PhysicalSizeBeforeBytes') { $entry | Add-Member -NotePropertyName PhysicalSizeBeforeBytes -NotePropertyValue ([int64]0) -Force }
        if ($entry.PSObject.Properties.Name -notcontains 'PhysicalSizeAfterBytes') { $entry | Add-Member -NotePropertyName PhysicalSizeAfterBytes -NotePropertyValue ([int64]0) -Force }
        if ($entry.PSObject.Properties.Name -notcontains 'PhysicalGrowthBytes') { $entry | Add-Member -NotePropertyName PhysicalGrowthBytes -NotePropertyValue ([int64]0) -Force }
        if ($entry.PSObject.Properties.Name -notcontains 'LogicalAddedBytes') { $entry | Add-Member -NotePropertyName LogicalAddedBytes -NotePropertyValue ([int64]0) -Force }
        if ($entry.PSObject.Properties.Name -notcontains 'LastMeasuredAt') { $entry | Add-Member -NotePropertyName LastMeasuredAt -NotePropertyValue $null -Force }
        if ($entry.PSObject.Properties.Name -notcontains 'PhysicalSizeBaselineCaptured') { $entry | Add-Member -NotePropertyName PhysicalSizeBaselineCaptured -NotePropertyValue $false -Force }
    }
    $state.ArchivePsts = @($list)
    $state.ArchivePst = $ArchivePst
    $state.CurrentArchivePst = $ArchivePst
    $state.Updated = (Get-Date).ToString('o')
}

function Update-OPAArchivePstTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][string]$ArchivePst,
        [Parameter(Mandatory=$true)][int64]$PhysicalSizeBytes,
        [int64]$LogicalAddedBytes = 0
    )

    $entry = @($Transaction.State.ArchivePsts | Where-Object { [string]$_.Path -ieq $ArchivePst } | Select-Object -First 1)
    if ($entry.Count -eq 0) {
        throw "Archive PST '$ArchivePst' is not registered in the transaction."
    }

    $e = $entry[0]
    if ($e.PSObject.Properties.Name -notcontains 'PhysicalSizeBeforeBytes') { $e | Add-Member -NotePropertyName PhysicalSizeBeforeBytes -NotePropertyValue ([int64]0) -Force }
    if ($e.PSObject.Properties.Name -notcontains 'PhysicalSizeAfterBytes') { $e | Add-Member -NotePropertyName PhysicalSizeAfterBytes -NotePropertyValue ([int64]0) -Force }
    if ($e.PSObject.Properties.Name -notcontains 'PhysicalGrowthBytes') { $e | Add-Member -NotePropertyName PhysicalGrowthBytes -NotePropertyValue ([int64]0) -Force }
    if ($e.PSObject.Properties.Name -notcontains 'LogicalAddedBytes') { $e | Add-Member -NotePropertyName LogicalAddedBytes -NotePropertyValue ([int64]0) -Force }
    if ($e.PSObject.Properties.Name -notcontains 'LastMeasuredAt') { $e | Add-Member -NotePropertyName LastMeasuredAt -NotePropertyValue $null -Force }
    if ($e.PSObject.Properties.Name -notcontains 'PhysicalSizeBaselineCaptured') { $e | Add-Member -NotePropertyName PhysicalSizeBaselineCaptured -NotePropertyValue $false -Force }

    $physical = [Math]::Max([int64]0, [int64]$PhysicalSizeBytes)
    if (-not [bool]$e.PhysicalSizeBaselineCaptured) {
        $e.PhysicalSizeBeforeBytes = $physical
        $e.PhysicalSizeBaselineCaptured = $true
    }
    $e.PhysicalSizeAfterBytes = $physical
    $e.PhysicalGrowthBytes = [Math]::Max([int64]0, ([int64]$physical - [int64]$e.PhysicalSizeBeforeBytes))
    if ($LogicalAddedBytes -ne 0) {
        $e.LogicalAddedBytes = [int64]$e.LogicalAddedBytes + [int64]$LogicalAddedBytes
    }
    $e.LastMeasuredAt = (Get-Date).ToString('o')
    $Transaction.State.Updated = (Get-Date).ToString('o')
}

function Set-OPAArchiveTransactionStorageStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [int64]$LogicalFreedBytes = 0,
        [int64]$SourcePstSizeBeforeBytes = 0,
        [int64]$SourcePstSizeAfterBytes = 0
    )

    $state = $Transaction.State

    # Update only the storage fields explicitly supplied by the caller.
    # This is important during normal archive execution: MailMover updates
    # LogicalFreedBytes and SourcePstSizeAfterBytes after each move, but it
    # must not reset the already persisted SourcePstSizeBeforeBytes to 0.
    if ($PSBoundParameters.ContainsKey('LogicalFreedBytes')) {
        $state.LogicalFreedBytes = [int64]$LogicalFreedBytes
    }
    if ($PSBoundParameters.ContainsKey('SourcePstSizeBeforeBytes')) {
        $state.SourcePstSizeBeforeBytes = [int64]$SourcePstSizeBeforeBytes
    }
    if ($PSBoundParameters.ContainsKey('SourcePstSizeAfterBytes')) {
        $state.SourcePstSizeAfterBytes = [int64]$SourcePstSizeAfterBytes
    }
    $state.Updated = (Get-Date).ToString('o')
}

function Save-OPAArchiveTransaction {
    <#
    .SYNOPSIS
        Appends a step to the durable append-only journal on EVERY call and
        keeps the in-memory sliding window in sync. The checkpoint JSON is
        rewritten only when required (terminal statuses, 'Planned', or an
        explicit -WriteCheckpoint), which removes the O(n^2) full-state
        serialization per move. Callers that need the checkpoint durable
        after this call must pass -WriteCheckpoint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][string]$Status,
        [string]$Step,
        [string]$Message,
        [string]$EntryId,
        [datetime]$ReceivedTime,
        [string]$ArchiveEntryId,
        [string]$ArchivePst,
        [string]$TargetFolderPath,
        [string]$SourceFolderPath,
        [switch]$WriteCheckpoint
    )

    $s = $Transaction.State
    $s.Status = $Status
    if (-not [string]::IsNullOrWhiteSpace($ArchivePst)) { $s.ArchivePst = $ArchivePst; $s.CurrentArchivePst = $ArchivePst }
    $s.Updated = (Get-Date).ToString('o')

    $stepEntry = [ordered]@{
        Time             = $s.Updated
        Step             = $Step
        Message          = $Message
        EntryId          = $EntryId
        ArchiveEntryId   = $ArchiveEntryId
        ArchivePst       = $ArchivePst
        TargetFolderPath = $TargetFolderPath
        SourceFolderPath = $SourceFolderPath
        ReceivedTime     = if ($PSBoundParameters.ContainsKey('ReceivedTime')) { $ReceivedTime.ToString('o') } else { $null }
    }

    # 1. Durable append (cheap) — survives a crash even when the checkpoint
    #    is not rewritten below.
    Add-OPAStepJournalEntry -Transaction $Transaction -Step $stepEntry

    # 2. Sliding window of the newest steps in the in-memory state.
    $window = @($s.Steps) + [pscustomobject]$stepEntry
    if ($window.Count -gt $script:OPAStepsInlineLimit) {
        $window = @($window | Select-Object -Last $script:OPAStepsInlineLimit)
    }
    $s.Steps = $window

    # 3. Checkpoint rewrite only when necessary.
    $mustWrite = [bool]$WriteCheckpoint -or ($Status -in @('Completed','VerificationFailed','Failed','Recovered','Planned','Created'))
    if (-not $mustWrite) { return }

    if (@($s.SkippedItems).Count -gt $script:OPASkippedInlineLimit) {
        $s.SkippedItems = @($s.SkippedItems | Select-Object -Last $script:OPASkippedInlineLimit)
    }
    $journalPath = Get-OPAStepJournalPath -Transaction $Transaction
    if (Test-Path -LiteralPath $journalPath) {
        try { $s.JournalOffsetBytes = [int64](Get-Item -LiteralPath $journalPath).Length } catch {}
    }
    $json = ConvertTo-Json -InputObject $s -Depth 12
    Write-OPAAtomicTextFile -Path $Transaction.Path -Content $json
}

function Set-OPAArchiveTransactionCount {
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [int]$Planned,
        [int]$Executed,
        [int]$Verified
    )

    $s = $Transaction.State
    $s.Planned = $Planned
    $s.Executed = $Executed
    $s.Verified = $Verified
    if ($s.PSObject.Properties.Name -contains 'Skipped') {
        $s.Skipped = [int]$s.Skipped
    }
    $s.Updated = (Get-Date).ToString('o')
}

function Get-OPAArchiveTransaction {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [string]$TransactionId
    )
    $dir = Join-Path ([IO.Path]::GetDirectoryName($SourcePst)) 'OutlookPOP3Archive-Transactions'
    if ($TransactionId) { $path = Join-Path $dir "$TransactionId.json" }
    else {
        $path = Get-ChildItem -LiteralPath $dir -Filter '*.json' -File |
            Where-Object { $_.Name -ne 'DuplicateIndex.json' } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { throw 'Transaction checkpoint was not found.' }
    try {
        $state = Read-OPAJsonFile -Path $path
        if ($state.PSObject.Properties.Name -notcontains 'JournalOffsetBytes') {
            $state | Add-Member -NotePropertyName JournalOffsetBytes -NotePropertyValue ([int64]0) -Force
        }
        if ($state.PSObject.Properties.Name -notcontains 'SkippedEntryIds') {
            $ids = New-Object System.Collections.Generic.List[string]
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($item in @($state.SkippedItems)) {
                if ($item) { $id=[string]$item.EntryId; if ($id -and $seen.Add($id)) { $ids.Add($id) | Out-Null } }
            }
            $state | Add-Member -NotePropertyName SkippedEntryIds -NotePropertyValue ($ids.ToArray()) -Force
        }
        Test-OPAArchiveTransactionSchema -TransactionState $state | Out-Null
        $txStub = [pscustomobject]@{ Path = $path }
        $journalPath = Get-OPAStepJournalPath -Transaction $txStub
        if (Test-Path -LiteralPath $journalPath) {
            $tailSteps = @(Read-OPAStepJournalTail -Path $journalPath -TailCount $script:OPAStepsInlineLimit)
            if ($tailSteps.Count -gt 0) { $state.Steps = $tailSteps }
            $newSteps = @(Read-OPAStepJournalFrom -Path $journalPath -FromOffset ([int64]$state.JournalOffsetBytes))
            if ($newSteps.Count -gt 0) {
                $idSet = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
                foreach ($id in @($state.SkippedEntryIds)) { if ($id) { [void]$idSet.Add([string]$id) } }
                $window = New-Object System.Collections.Generic.List[object]
                foreach ($item in @($state.SkippedItems)) { if ($item) { $window.Add($item) | Out-Null } }
                foreach ($step in $newSteps) {
                    if ([string]$step.Step -ne 'Skipped') { continue }
                    $id=[string]$step.EntryId
                    if (-not $id -or $idSet.Contains($id)) { continue }
                    [void]$idSet.Add($id)
                    $window.Add([pscustomobject]@{EntryId=$id;SourceFolderPath=[string]$step.SourceFolderPath;Reason='JournalRecovered';Message=[string]$step.Message;Time=[string]$step.Time}) | Out-Null
                }
                if ($window.Count -gt $script:OPASkippedInlineLimit) { $state.SkippedItems=@($window | Select-Object -Last $script:OPASkippedInlineLimit) } else { $state.SkippedItems=$window.ToArray() }
                $state.SkippedEntryIds=@($idSet)
                $state.Skipped=$idSet.Count
            }
            try { $state.JournalOffsetBytes=[int64](Get-Item -LiteralPath $journalPath).Length } catch {}
        }
    }
    catch { throw "Transaction checkpoint is invalid or unsupported: $path. $($_.Exception.Message)" }
    [pscustomobject]@{ TransactionId=$state.TransactionId; Path=$path; State=$state }
}
