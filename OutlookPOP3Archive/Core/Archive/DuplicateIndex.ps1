# DuplicateIndex.ps1 -- append-only journal (schema 1.2+).
#
# Layout under OutlookPOP3Archive-Transactions\:
#   DuplicateIndex.json      legacy base, read-only, may be absent
#   DuplicateIndex.jsonl     append-only delta journal, authoritative
#
# Reads merge both files, last-wins by SourceEntryId. Writes append one
# JSON object per line. No full-file rewrite on flush, so per-move cost is
# O(1) independent of index size. Legacy .json is preserved on disk and
# never modified by this module.

function Get-OPADuplicateIndexPath {
    param([Parameter(Mandatory=$true)][string]$ArchivePst)
    $dir = Join-Path ([IO.Path]::GetDirectoryName($ArchivePst)) 'OutlookPOP3Archive-Transactions'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Join-Path $dir 'DuplicateIndex.json'
}

function Get-OPADuplicateIndexJournalPath {
    param([Parameter(Mandatory=$true)][string]$ArchivePst)
    $dir = Join-Path ([IO.Path]::GetDirectoryName($ArchivePst)) 'OutlookPOP3Archive-Transactions'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Join-Path $dir 'DuplicateIndex.jsonl'
}

# -------- journal streams --------------------------------------------------

# Process-wide map of open DuplicateIndex journal streams. Must be
# $global: for the same reason as $global:OPAStepJournalStreams:
# Pester 5/6 scopes $script: per block, so a $script: hashtable
# populated in one scope is invisible in another and the file handle
# leaks past cleanup.
$global:OPADuplicateJournalStreams = @{}

function Get-OPADuplicateJournalStream {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if ($global:OPADuplicateJournalStreams.ContainsKey($Path)) {
        $stream = $global:OPADuplicateJournalStreams[$Path]
        try { if ($stream.CanWrite) { return $stream } } catch {}
        try { $stream.Dispose() } catch {}
        $global:OPADuplicateJournalStreams.Remove($Path)
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
    $global:OPADuplicateJournalStreams[$Path] = $fs
    return $fs
}

function Sync-OPADuplicateJournalStreams {
    [CmdletBinding()]
    param()
    foreach ($key in @($global:OPADuplicateJournalStreams.Keys)) {
        $s = $global:OPADuplicateJournalStreams[$key]
        if ($null -eq $s) { continue }
        try { if ($s.CanWrite) { $s.Flush($true) } }
        catch { throw ("Failed to flush DuplicateIndex journal '{0}': {1}" -f [string]$key, $_.Exception.Message) }
    }
}

function Close-OPADuplicateJournalStreams {
    [CmdletBinding()]
    param()
    if ($global:OPADuplicateJournalStreams.Count -eq 0) { return }
    foreach ($key in @($global:OPADuplicateJournalStreams.Keys)) {
        $s = $global:OPADuplicateJournalStreams[$key]
        try { if ($null -ne $s) { $s.Flush($true); $s.Dispose() } } catch {}
    }
    # Process-wide map of open DuplicateIndex journal streams. Must be
# $global: for the same reason as $global:OPAStepJournalStreams:
# Pester 5/6 scopes $script: per block, so a $script: hashtable
# populated in one scope is invisible in another and the file handle
# leaks past cleanup.
$global:OPADuplicateJournalStreams = @{}
}

function Append-OPADuplicateEntryLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ArchivePst,
        [Parameter(Mandatory=$true)][object]$Entry
    )
    $path = Get-OPADuplicateIndexJournalPath -ArchivePst $ArchivePst
    $fs = Get-OPADuplicateJournalStream -Path $path
    # -InputObject (not pipeline) is critical on PS 5.1: piping an
    # OrderedDictionary enumerates it into DictionaryEntry values and
    # produces a JSON array per line instead of an object.
    $line = ConvertTo-Json -InputObject $Entry -Depth 6 -Compress
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8.GetBytes($line + [Environment]::NewLine)
    $fs.Write($bytes, 0, $bytes.Length)
    # Durability mode: Safe force-flushes on every append, minimizing the
    # window of journal loss on OS/power failure. Fast flushes to OS cache
    # and relies on Sync-OPADuplicateJournalStreams at batch boundaries.
    $isSafe = ($global:OPADurabilityMode -eq 'Safe')
    $fs.Flush($isSafe)
}

# -------- fast lookup ------------------------------------------------------

function Initialize-OPADuplicateSourceIdSet {
    param([Parameter(Mandatory=$true)][object]$Index)
    $sourceIdSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Index.Entries)) {
        if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.SourceEntryId)) {
            [void]$sourceIdSet.Add([string]$entry.SourceEntryId)
        }
    }
    if ($Index.PSObject.Properties.Name -contains 'SourceIdSet') {
        $Index.SourceIdSet = $sourceIdSet
    }
    else {
        $Index | Add-Member -NotePropertyName SourceIdSet -NotePropertyValue $sourceIdSet -Force
    }
    return $Index
}

# -------- load -------------------------------------------------------------

function Import-OPADuplicateIndex {
    param([Parameter(Mandatory=$true)][string]$ArchivePst)

    $legacyPath  = Get-OPADuplicateIndexPath -ArchivePst $ArchivePst
    $journalPath = Get-OPADuplicateIndexJournalPath -ArchivePst $ArchivePst

    # SourceEntryId -> entry, last-wins.
    $byId = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)

    # 1. Legacy base .json (if present).
    if (Test-Path -LiteralPath $legacyPath) {
        try {
            $legacy = Read-OPAJsonFile -Path $legacyPath
            $legacySchema = if ($legacy.PSObject.Properties.Name -contains 'SchemaVersion') {
                [string]$legacy.SchemaVersion
            } else { '1.0' }
            if ($script:OPADuplicateIndexSchemasSupported -notcontains $legacySchema) {
                throw "Unsupported DuplicateIndex schema '$legacySchema'."
            }
            foreach ($e in @($legacy.Entries)) {
                if ($null -eq $e) { continue }
                $sid = [string]$e.SourceEntryId
                if (-not [string]::IsNullOrWhiteSpace($sid)) {
                    $byId[$sid] = $e
                }
            }
        }
        catch {
            throw "Legacy DuplicateIndex is unreadable or unsupported: $legacyPath. $($_.Exception.Message)"
        }
    }

    # 2. Append-only journal on top of the base. Last line for a given
    # SourceEntryId wins, which is how enrichment entries take effect.
    if (Test-Path -LiteralPath $journalPath) {
        $entries = @(Read-OPAJsonlEntries -Path $journalPath -Context 'DuplicateIndex journal')
        foreach ($e in $entries) {
            if ($null -eq $e) { continue }
            $sid = [string]$e.SourceEntryId
            if (-not [string]::IsNullOrWhiteSpace($sid)) {
                $byId[$sid] = $e
            }
        }
    }

    $index = [pscustomobject]@{
        Version       = $script:OPADuplicateIndexSchemaVersion
        SchemaVersion = $script:OPADuplicateIndexSchemaVersion
        ArchivePst    = $ArchivePst
        Entries       = @($byId.Values)
    }
    return (Initialize-OPADuplicateSourceIdSet -Index $index)
}

# -------- write ------------------------------------------------------------

function Save-OPADuplicateIndex {
    <#
    .SYNOPSIS
        Kept for backward compatibility with the previous batched-flush
        design. Under the append-only journal every entry is written
        durably by Add-OPADuplicateEntry, so this is a no-op. It exists
        only so Save-OPAFlushDirtyIndexes and legacy test callers still
        work without changes.
    #>
    param(
        [Parameter(Mandatory=$true)][object]$Index,
        [Parameter(Mandatory=$true)][string]$ArchivePst
    )
    return
}

function Test-OPADuplicateEntry {
    param(
        [Parameter(Mandatory=$true)][object]$Index,
        [Parameter(Mandatory=$true)][string]$SourceEntryId
    )
    if ([string]::IsNullOrWhiteSpace($SourceEntryId)) { return $null }
    if ($Index.PSObject.Properties.Name -contains 'SourceIdSet' -and $null -ne $Index.SourceIdSet) {
        if (-not $Index.SourceIdSet.Contains($SourceEntryId)) { return $null }
    }
    @($Index.Entries) |
        Where-Object { [string]$_.SourceEntryId -eq $SourceEntryId } |
        Select-Object -First 1
}

function Add-OPADuplicateEntry {
    param(
        [Parameter(Mandatory=$true)][object]$Index,
        [Parameter(Mandatory=$true)][string]$SourceEntryId,
        [string]$ArchiveEntryId,
        [string]$SourceFolderPath,
        [string]$TargetFolderPath,
        [System.Nullable[datetime]]$ReceivedTime,
        [string]$Subject,
        [string]$TransactionId,
        [int]$TransactionLimit,
        [string]$ArchiveGrouping,
        [string]$SourcePst,
        [int]$OlderThanMonths,
        [string]$ArchiveCutoff,
        [string]$ArchivePst
    )

    $existing = Test-OPADuplicateEntry -Index $Index -SourceEntryId $SourceEntryId
    if ($existing) {
        # Enrich empty fields on the existing entry. This path is used when
        # recovery reconstructed a record without a destination EntryID and
        # a later pass has the real one. Append the enriched entry to the
        # journal so last-wins dedup picks it up on the next load.
        if ([string]::IsNullOrWhiteSpace([string]$existing.ArchiveEntryId) -and
            -not [string]::IsNullOrWhiteSpace($ArchiveEntryId)) {
            $existing.ArchiveEntryId = $ArchiveEntryId
            $existing.ArchivePst = $ArchivePst
            $existing.TargetFolderPath = $TargetFolderPath
            $existing.ArchivedAt = (Get-Date).ToString('o')

            try {
                $targetPst = $ArchivePst
                if ([string]::IsNullOrWhiteSpace($targetPst)) { $targetPst = [string]$Index.ArchivePst }
                if (-not [string]::IsNullOrWhiteSpace($targetPst)) {
                    Append-OPADuplicateEntryLine -ArchivePst $targetPst -Entry $existing
                }
            }
            catch {
                throw ("Failed to append enriched DuplicateIndex journal line for '{0}': {1}" -f $SourceEntryId, $_.Exception.Message)
            }
        }
        return
    }

    $entry = [pscustomobject]@{
        SourceEntryId    = $SourceEntryId
        ArchiveEntryId   = $ArchiveEntryId
        SourceFolderPath = $SourceFolderPath
        TargetFolderPath = $TargetFolderPath
        ReceivedTime     = if ($PSBoundParameters.ContainsKey('ReceivedTime') -and $null -ne $ReceivedTime) { $ReceivedTime.ToString('o') } else { $null }
        Subject          = $Subject
        TransactionId    = $TransactionId
        TransactionLimit = if ($PSBoundParameters.ContainsKey('TransactionLimit')) { $TransactionLimit } else { $null }
        ArchiveGrouping  = $ArchiveGrouping
        SourcePst        = $SourcePst
        OlderThanMonths  = if ($PSBoundParameters.ContainsKey('OlderThanMonths')) { $OlderThanMonths } else { $null }
        ArchiveCutoff    = $ArchiveCutoff
        ArchivePst       = $ArchivePst
        ArchivedAt       = (Get-Date).ToString('o')
    }

    $entries = @($Index.Entries)
    $entries += $entry
    $Index.Entries = $entries

    if ($Index.PSObject.Properties.Name -contains 'SourceIdSet' -and $null -ne $Index.SourceIdSet) {
        [void]$Index.SourceIdSet.Add($SourceEntryId)
    }
    else {
        [void](Initialize-OPADuplicateSourceIdSet -Index $Index)
    }

    # Durably append to the journal. A failure here is not fatal: the
    # caller writes the transaction step journal right after, and on the
    # next run Sync-OPADuplicateIndexFromJournal heals the gap.
    try {
        $targetPst = $ArchivePst
        if ([string]::IsNullOrWhiteSpace($targetPst)) { $targetPst = [string]$Index.ArchivePst }
        if (-not [string]::IsNullOrWhiteSpace($targetPst)) {
            Append-OPADuplicateEntryLine -ArchivePst $targetPst -Entry $entry
        }
    }
    catch {
        throw ("Failed to append DuplicateIndex journal line for '{0}': {1}" -f $SourceEntryId, $_.Exception.Message)
    }
}

function Sync-OPADuplicateIndexFromJournal {
    <#
    .SYNOPSIS
        Heal the DuplicateIndex from the transaction step journal. Under
        the append-only design, this appends any journaled Move the index
        journal has not yet seen. Idempotent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][object]$Index,
        [Parameter(Mandatory=$true)][string]$ArchivePst
    )

    $added = 0
    foreach ($step in @(Read-OPAStepJournal -Transaction $Transaction)) {
        if (-not (Test-OPAMoveCompletionStep -Step $step)) { continue }
        $sourceId = [string]$step.EntryId
        $archiveId = [string]$step.ArchiveEntryId
        if ([string]::IsNullOrWhiteSpace($sourceId) -or [string]::IsNullOrWhiteSpace($archiveId)) { continue }
        if ($null -ne (Test-OPADuplicateEntry -Index $Index -SourceEntryId $sourceId)) { continue }

        $rt = $null
        try { $rt = [datetime]$step.ReceivedTime } catch {}

        Add-OPADuplicateEntry -Index $Index `
            -SourceEntryId $sourceId -ArchiveEntryId $archiveId `
            -SourceFolderPath ([string]$step.SourceFolderPath) `
            -TargetFolderPath ([string]$step.TargetFolderPath) `
            -ReceivedTime $rt -Subject $null `
            -TransactionId ([string]$Transaction.TransactionId) `
            -TransactionLimit ([int]$Transaction.State.Limit) `
            -ArchiveGrouping ([string]$Transaction.State.ArchiveGrouping) `
            -SourcePst ([string]$Transaction.State.SourcePst) `
            -OlderThanMonths ([int]$Transaction.State.OlderThanMonths) `
            -ArchiveCutoff ([string]$Transaction.State.ArchiveCutoff) `
            -ArchivePst $(if ([string]::IsNullOrWhiteSpace([string]$step.ArchivePst)) { $ArchivePst } else { [string]$step.ArchivePst })
        $added++
    }

    if ($added -gt 0) {
        Write-Host ("Healed DuplicateIndex from step journal: +{0} entr(ies)" -f $added)
    }
    return $added
}
# Compatibility alias. New callers should use Import-OPADuplicateIndex.
Set-Alias -Name Load-OPADuplicateIndex -Value Import-OPADuplicateIndex -Scope Script
