#requires -Version 5.1
# OutlookPOP3Archive 2.6.2: durable, append-only per-message operation journal.
# Remains isolated from MailMover; 2.6.1 base has been merged.
# A caller MUST flush Intent before Outlook Move(), and MUST NOT retry an
# unresolved Intent automatically. Journal and PST reconciliation are separate.

function Get-OPAOperationJournalSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Write-OPAOperationJournalEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$TransactionId,
        [Parameter(Mandatory=$true)][string]$OperationId,
        [Parameter(Mandatory=$true)][ValidateRange(1,9223372036854775807)][long]$Sequence,
        [Parameter(Mandatory=$true)][ValidateSet('Intent','Completed','Reconciled','Indeterminate','WorkerSucceeded','WorkerFailed')][string]$Phase,
        [ValidateSet('MailMove','WorkerDiagnostic')][string]$OperationKind = 'MailMove',
        [int]$WorkerProcessId = 0,
        [string]$FailureKind = '',
        [string]$SourceEntryId = '',
        [string]$ArchiveEntryId = '',
        [string]$ArchivePst = '',
        # 2.6.3 read-only reconciliation evidence, preserved with Intent.
        [string]$SourceStoreId = '',
        [string]$SourceFolderPath = '',
        [string]$TargetFolderPath = '',
        [string]$InternetMessageId = '',
        [string]$Subject = '',
        [string]$Sender = '',
        [long]$Size = 0,
        [string]$Message = ''
    )

    if ([string]::IsNullOrWhiteSpace($TransactionId) -or [string]::IsNullOrWhiteSpace($OperationId)) {
        throw 'TransactionId and OperationId must not be blank.'
    }
    if ($Phase -eq 'Intent' -and $OperationKind -eq 'MailMove' -and [string]::IsNullOrWhiteSpace($SourceEntryId)) {
        throw 'Intent must record SourceEntryId before Outlook Move().'
    }
    if ($OperationKind -eq 'MailMove' -and $Phase -in @('Completed','Reconciled') -and [string]::IsNullOrWhiteSpace($ArchiveEntryId)) {
        throw 'Completed/Reconciled must record ArchiveEntryId.'
    }

    if ($Phase -in @('WorkerSucceeded','WorkerFailed') -and $OperationKind -ne 'WorkerDiagnostic') {
        throw 'Worker-only outcomes cannot prove completion of a MailMove.'
    }
    if ($Phase -eq 'WorkerSucceeded' -and $WorkerProcessId -le 0) {
        throw 'WorkerSucceeded must record a verified positive worker PID.'
    }
    $payload = [ordered]@{
        SchemaVersion = '1.0'
        Utc           = [datetime]::UtcNow.ToString('o')
        TransactionId = $TransactionId
        OperationId   = $OperationId
        Sequence      = $Sequence
        Phase         = $Phase
        OperationKind = $OperationKind
        WorkerProcessId = $WorkerProcessId
        FailureKind   = $FailureKind
        SourceEntryId = $SourceEntryId
        ArchiveEntryId= $ArchiveEntryId
        ArchivePst    = $ArchivePst
        SourceStoreId = $SourceStoreId
        SourceFolderPath = $SourceFolderPath
        TargetFolderPath = $TargetFolderPath
        InternetMessageId = $InternetMessageId
        Subject       = $Subject
        Sender        = $Sender
        Size          = $Size
        Message       = $Message
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $json = ConvertTo-Json -InputObject $payload -Depth 8 -Compress
    $bytes = $utf8.GetBytes($json)
    # Hash the original byte sequence, not JSON after a lossy deserialize.
    $envelope = [ordered]@{
        V       = 1
        Payload = [Convert]::ToBase64String($bytes)
        Sha256  = Get-OPAOperationJournalSha256 -Bytes $bytes
    }
    $record = (ConvertTo-Json -InputObject $envelope -Depth 4 -Compress) + "`n"
    $encoded = $utf8.GetBytes($record)

    $dir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }

    $stream = $null
    try {
        # Single writer; readers may inspect completed, flushed lines.
        $stream = [IO.FileStream]::new($Path, [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        if ($stream.Length -gt 0) {
            [void]$stream.Seek(-1, [IO.SeekOrigin]::End)
            $last = $stream.ReadByte()
            if ($last -ne 10) {
                throw "Journal has an uncommitted/truncated tail. Preserve it and reconcile manually: $Path"
            }
        }
        [void]$stream.Seek(0, [IO.SeekOrigin]::End)
        $stream.Write($encoded, 0, $encoded.Length)
        # Flush OS file buffers before returning control to the COM caller.
        $stream.Flush($true)
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
    return [pscustomobject]$payload
}

function Read-OPAOperationJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not [IO.File]::Exists($Path)) { throw "Operation journal not found: $Path" }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $events = New-Object 'System.Collections.Generic.List[object]'
    $stream = $null; $reader = $null
    $partial = $false
    try {
        $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $hasFinalNewline = $true
        if ($stream.Length -gt 0) {
            [void]$stream.Seek(-1, [IO.SeekOrigin]::End)
            $hasFinalNewline = ($stream.ReadByte() -eq 10)
            [void]$stream.Seek(0, [IO.SeekOrigin]::Begin)
        }
        $reader = [IO.StreamReader]::new($stream, $utf8, $true, 4096, $true)
        $lineNo = 0
        while ($null -ne ($line = $reader.ReadLine())) {
            $lineNo++
            if ($reader.EndOfStream -and -not $hasFinalNewline) {
                # Incomplete final write: neither trust nor delete it.
                $partial = $true
                break
            }
            if ([string]::IsNullOrWhiteSpace($line)) {
                throw "Empty operation journal record at line $lineNo."
            }
            try {
                $envelope = ConvertFrom-Json -InputObject $line
                if ([int]$envelope.V -ne 1 -or
                    [string]::IsNullOrWhiteSpace([string]$envelope.Payload) -or
                    [string]::IsNullOrWhiteSpace([string]$envelope.Sha256)) {
                    throw 'Invalid envelope'
                }
                $payloadBytes = [Convert]::FromBase64String([string]$envelope.Payload)
                $actual = Get-OPAOperationJournalSha256 -Bytes $payloadBytes
                if ($actual -cne [string]$envelope.Sha256) { throw 'SHA256 mismatch' }
                $item = ConvertFrom-Json -InputObject ($utf8.GetString($payloadBytes))
                if ([string]$item.SchemaVersion -cne '1.0') { throw 'Unsupported schema' }
                if ([string]::IsNullOrWhiteSpace([string]$item.TransactionId) -or
                    [string]::IsNullOrWhiteSpace([string]$item.OperationId) -or
                    [string]$item.Phase -notin @('Intent','Completed','Reconciled','Indeterminate','WorkerSucceeded','WorkerFailed') -or
                    [long]$item.Sequence -lt 1) {
                    throw 'Invalid event fields'
                }
                $kind = if ($item.PSObject.Properties.Name -contains 'OperationKind') { [string]$item.OperationKind } else { 'MailMove' }
                if ($kind -notin @('MailMove','WorkerDiagnostic')) { throw 'Unknown operation kind' }
                if ($kind -eq 'MailMove' -and [string]$item.Phase -in @('WorkerSucceeded','WorkerFailed')) { throw 'Invalid MailMove worker outcome' }
                if ($kind -eq 'MailMove' -and [string]$item.Phase -eq 'Intent' -and
                    [string]::IsNullOrWhiteSpace([string]$item.SourceEntryId)) { throw 'MailMove Intent missing source EntryId' }
                if ($kind -eq 'MailMove' -and [string]$item.Phase -in @('Completed','Reconciled') -and
                    [string]::IsNullOrWhiteSpace([string]$item.ArchiveEntryId)) { throw 'MailMove completion missing archive EntryId' }
                if ([string]$item.Phase -eq 'WorkerSucceeded' -and [int]$item.WorkerProcessId -le 0) {
                    throw 'WorkerSucceeded missing verified PID'
                }
                [void]$events.Add($item)
            }
            catch {
                throw "Operation journal corrupted at line $lineNo in '$Path': $($_.Exception.Message)"
            }
        }
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
    return [pscustomobject]@{
        Events         = $events.ToArray()
        TrailingPartial= $partial
        Path           = $Path
    }
}

function Resolve-OPAOperationRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Journal)

    $states = @{}
    $lastSeq = [long]0
    $transactionId = $null
    foreach ($event in @($Journal.Events)) {
        $seq = [long]$event.Sequence
        if ($seq -le $lastSeq) { throw 'Operation journal sequence is not strictly increasing.' }
        $lastSeq = $seq
        if ($null -eq $transactionId) { $transactionId = [string]$event.TransactionId }
        if ([string]$event.TransactionId -cne $transactionId) {
            throw 'Operation journal mixes transaction IDs.'
        }
        $id = [string]$event.OperationId
        $phase = [string]$event.Phase
        if (-not $states.ContainsKey($id)) {
            if ($phase -ne 'Intent') { throw "Operation '$id' has no durable Intent." }
            $states[$id] = [pscustomobject]@{
                OperationId   = $id
                SourceEntryId = [string]$event.SourceEntryId
                ArchiveEntryId= ''
                ArchivePst    = [string]$event.ArchivePst
                SourceStoreId = [string]$event.SourceStoreId
                SourceFolderPath = [string]$event.SourceFolderPath
                TargetFolderPath = [string]$event.TargetFolderPath
                InternetMessageId = [string]$event.InternetMessageId
                Subject       = [string]$event.Subject
                Sender        = [string]$event.Sender
                Size          = [long]$event.Size
                Status        = 'Indeterminate'
                OperationKind = $(if ($event.PSObject.Properties.Name -contains 'OperationKind') { [string]$event.OperationKind } else { 'MailMove' })
                ExplicitIndeterminate = $false
            }
            continue
        }
        $item = $states[$id]
        $eventKind = if ($event.PSObject.Properties.Name -contains 'OperationKind') { [string]$event.OperationKind } else { 'MailMove' }
        if ($eventKind -cne $item.OperationKind) { throw "Operation '$id' changed kind during replay." }
        if ($item.ExplicitIndeterminate -and $phase -ne 'Reconciled') {
            throw "Operation '$id' is indeterminate; only independently proven Reconciled may follow."
        }
        if ($item.Status -ne 'Indeterminate' -or $phase -eq 'Intent') {
            throw "Conflicting/duplicate terminal event for operation '$id'."
        }
        if ($phase -eq 'Completed' -and $item.OperationKind -eq 'WorkerDiagnostic') {
            throw 'WorkerDiagnostic cannot be marked as MailMove Completed.'
        }
        if ($phase -eq 'Indeterminate') { $item.ExplicitIndeterminate = $true }
        if ($phase -in @('Completed','Reconciled')) {
            if ($item.OperationKind -eq 'MailMove' -and [string]::IsNullOrWhiteSpace([string]$event.ArchiveEntryId)) {
                throw "Terminal event for operation '$id' lacks ArchiveEntryId."
            }
            $item.ArchiveEntryId = [string]$event.ArchiveEntryId
            $item.Status = $phase
        }
        if ($phase -in @('WorkerSucceeded','WorkerFailed')) {
            if ($item.OperationKind -ne 'WorkerDiagnostic') { throw 'Worker outcome cannot finalize a MailMove.' }
            $item.Status = $phase
        }
        # An explicit Indeterminate event remains unresolved. Manual reconciliation
        # may later append Reconciled for the same operation after independent proof.
    }
    $resolved = @($states.Values | Where-Object { $_.Status -ne 'Indeterminate' })
    $unresolved = @($states.Values | Where-Object { $_.Status -eq 'Indeterminate' })
    $failed = @($states.Values | Where-Object { $_.Status -eq 'WorkerFailed' })
    $blocked = ($unresolved.Count -gt 0 -or $failed.Count -gt 0 -or [bool]$Journal.TrailingPartial)
    return [pscustomobject]@{
        TransactionId            = $transactionId
        LastSequence             = $lastSeq
        Resolved                 = $resolved
        Indeterminate            = $unresolved
        Failed                   = $failed
        TrailingPartial          = [bool]$Journal.TrailingPartial
        BlockAutomaticRetry      = $blocked
        # A diagnostic Worker crash requires an audit/recovery decision, but
        # cannot by itself require comparing Outlook PST contents.
        # A torn tail remains conservative: its unknown event might be MailMove.
        RequiresPstReconciliation= (@($unresolved | Where-Object { $_.OperationKind -eq 'MailMove' }).Count -gt 0 -or [bool]$Journal.TrailingPartial)
    }
}
