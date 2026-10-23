#requires -Version 5.1
# 2.6.4-B DEV. Separate diagnostic-only one-shot move fence.
# Never imported by production Archive, Resume, Auto, WorkerProtocol or WorkerHost.
# This module never mounts PSTs, starts Outlook, changes journals or retries a Move.

function Get-OPA264TestPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId)

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($RunId,[ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw '2.6.4 test RunId must be a nonempty GUID.'
    }
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('OPA264-Test-' + $parsed.ToString('N'))
    return [pscustomobject]@{
        RunId = $parsed.ToString('D')
        Directory = [IO.Path]::GetFullPath($directory)
        SourcePst = Join-Path $directory 'Source.pst'
        ArchivePst = Join-Path $directory 'Archive.pst'
        MarkerPath = Join-Path $directory 'scope.json'
        JournalPath = Join-Path $directory 'move.operations.jsonl'
        RequestPath = Join-Path $directory 'request.json'
        ResponsePath = Join-Path $directory 'response.json'
        ClaimPath = Join-Path $directory 'move-attempt.claim'
    }
}

function Assert-OPA264TestPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Actual,
          [Parameter(Mandatory=$true)][string]$Expected,
          [Parameter(Mandatory=$true)][string]$Label)
    # Require the exact canonical spelling. ResolvePath would follow symlinks.
    if (-not [string]::Equals($Actual, [IO.Path]::GetFullPath($Expected),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "2.6.4 test scope: $Label is outside the run-unique disposable scope."
    }
    if (-not (Test-Path -LiteralPath $Expected)) {
        throw "2.6.4 test scope: $Label does not exist."
    }
    $info = Get-Item -LiteralPath $Expected -Force -ErrorAction Stop
    if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "2.6.4 test scope: $Label is a reparse point."
    }
    return $true
}

function Assert-OPA264TestMoveScope {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request)

    $required = @('RunId','OperationId','SourcePst','ArchivePst','JournalPath',
        'SourceStoreId','ArchiveStoreId','SourceFolderEntryId','ArchiveFolderEntryId',
        'SourceFolderPath','ArchiveFolderPath','SourceEntryId')
    if ($null -eq $Request -or $Request -is [string]) { throw 'Test move request must be an object.' }
    foreach ($field in $required) {
        if ($Request.PSObject.Properties.Name -cnotcontains $field -or
            [string]::IsNullOrWhiteSpace([string]$Request.$field)) {
            throw "Test move request missing $field."
        }
    }
    $operationId = [guid]::Empty
    if (-not [guid]::TryParse([string]$Request.OperationId,[ref]$operationId) -or
        $operationId -eq [guid]::Empty) {
        throw 'Test move OperationId must be a nonempty GUID.'
    }
    $paths = Get-OPA264TestPaths -RunId ([string]$Request.RunId)
    [void](Assert-OPA264TestPath -Actual $paths.Directory -Expected $paths.Directory -Label 'directory')
    foreach ($part in @(
        @('SourcePst','SourcePst'),@('ArchivePst','ArchivePst'),@('JournalPath','JournalPath')
    )) {
        [void](Assert-OPA264TestPath -Actual ([string]$Request.($part[0])) -Expected ([string]$paths.($part[1])) -Label ([string]$part[0]))
    }
    [void](Assert-OPA264TestPath -Actual $paths.MarkerPath -Expected $paths.MarkerPath -Label 'scope marker')
    if ([string]::Equals([string]$Request.SourceStoreId,[string]$Request.ArchiveStoreId,
            [StringComparison]::Ordinal)) { throw 'Source and archive StoreID must differ.' }
    if ([string]::Equals([string]$Request.SourceFolderEntryId,[string]$Request.ArchiveFolderEntryId,
            [StringComparison]::Ordinal)) { throw 'Source and archive folder IDs must differ.' }
    $marker = $null
    try { $marker = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($paths.MarkerPath)) -ErrorAction Stop }
    catch { throw 'Malformed disposable-PST scope marker.' }
    if ([string]$marker.Purpose -cne 'OPA264-Disposable-Pst-Pair' -or
        [string]$marker.RunId -cne $paths.RunId -or
        [string]$marker.SourcePst -cne $paths.SourcePst -or
        [string]$marker.ArchivePst -cne $paths.ArchivePst) {
        throw 'Disposable-PST scope marker does not match the exact test run.'
    }
    if ([IO.File]::Exists($paths.ClaimPath) -or [IO.File]::Exists($paths.ResponsePath)) {
        throw 'Test Move already claimed or has a response; never replay.'
    }
    return $paths
}

function Assert-OPA264TestMoveIntent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Paths)
    # Read and verify independently; no mutation of the operation journal.
    if (-not (Get-Command Read-OPAOperationJournal -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
    }
    $journal = Read-OPAOperationJournal -Path ([string]$Paths.JournalPath)
    if ($journal.TrailingPartial -or @($journal.Events).Count -ne 1) {
        throw 'A test Move requires exactly one complete durable Intent.'
    }
    $intent = $journal.Events[0]
    if ([string]$intent.Phase -cne 'Intent' -or
        [string]$intent.OperationKind -cne 'MailMove' -or
        [long]$intent.Sequence -ne 1 -or
        [string]$intent.TransactionId -cne [string]$Paths.RunId -or
        [string]$intent.OperationId -cne [string]$Request.OperationId -or
        [string]$intent.SourceEntryId -cne [string]$Request.SourceEntryId -or
        [string]$intent.SourceStoreId -cne [string]$Request.SourceStoreId -or
        [string]$intent.SourceFolderPath -cne [string]$Request.SourceFolderPath -or
        [string]$intent.TargetFolderPath -cne [string]$Request.ArchiveFolderPath -or
        [string]$intent.ArchivePst -cne [string]$Paths.ArchivePst) {
        throw 'Durable test Move Intent conflicts with the request or scope.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$intent.InternetMessageId) -or
        [string]::IsNullOrWhiteSpace([string]$intent.Subject) -or
        [string]::IsNullOrWhiteSpace([string]$intent.Sender) -or
        [long]$intent.Size -le 0) {
        throw 'Durable test Move Intent lacks a complete fingerprint.'
    }
    return $intent
}

function Assert-OPA264TestStore {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][string]$StoreId,
          [Parameter(Mandatory=$true)][string]$PstPath)
    $matched = 0
    foreach ($store in @($Namespace.Stores)) {
        if ([string]::Equals([string]$store.StoreID,$StoreId,[StringComparison]::Ordinal)) {
            if (-not [string]::Equals([string]$store.FilePath,$PstPath,
                [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Outlook StoreID points to a different PST path.'
            }
            $matched++
        }
    }
    if ($matched -ne 1) { throw 'Exact test PST store is not uniquely mounted.' }
    return $true
}

function Invoke-OPA264TestOneShotMove {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Namespace)
    # No caller-controlled path roots or arbitrary COM methods.
    $paths = Assert-OPA264TestMoveScope -Request $Request
    $intent = Assert-OPA264TestMoveIntent -Request $Request -Paths $paths
    [void](Assert-OPA264TestStore -Namespace $Namespace -StoreId ([string]$Request.SourceStoreId) -PstPath $paths.SourcePst)
    [void](Assert-OPA264TestStore -Namespace $Namespace -StoreId ([string]$Request.ArchiveStoreId) -PstPath $paths.ArchivePst)
    $sourceFolder = $Namespace.GetFolderFromID([string]$Request.SourceFolderEntryId,[string]$Request.SourceStoreId)
    $targetFolder = $Namespace.GetFolderFromID([string]$Request.ArchiveFolderEntryId,[string]$Request.ArchiveStoreId)
    if ($null -eq $sourceFolder -or $null -eq $targetFolder -or
        [string]$sourceFolder.StoreID -cne [string]$Request.SourceStoreId -or
        [string]$targetFolder.StoreID -cne [string]$Request.ArchiveStoreId -or
        [string]$sourceFolder.FolderPath -cne [string]$Request.SourceFolderPath -or
        [string]$targetFolder.FolderPath -cne [string]$Request.ArchiveFolderPath) {
        throw 'Test folder identity does not match the disposable PST request.'
    }
    $mail = $Namespace.GetItemFromID([string]$Request.SourceEntryId,[string]$Request.SourceStoreId)
    if ($null -eq $mail -or [int]$mail.Class -ne 43 -or
        [string]$mail.EntryID -cne [string]$Request.SourceEntryId -or
        [string]$mail.Parent.StoreID -cne [string]$Request.SourceStoreId -or
        [string]$mail.Parent.FolderPath -cne [string]$Request.SourceFolderPath) {
        throw 'Test source message identity or folder does not match.'
    }
    $internetId = [string]$mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x1035001F')
    if ($internetId -cne [string]$intent.InternetMessageId -or
        [string]$mail.Subject -cne [string]$intent.Subject -or
        [string]$mail.SenderEmailAddress -ine [string]$intent.Sender -or
        [long]$mail.Size -ne [long]$intent.Size) {
        throw 'Test source MailItem fingerprint does not match durable Intent.'
    }
    # Atomic, durable one-shot claim: a failed/crashed attempt is NEVER retried.
    # Does not certify a successful Move and is NOT a journal completion.
    $file = $null
    try {
        $file = [IO.FileStream]::new($paths.ClaimPath,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $record = [Text.Encoding]::UTF8.GetBytes(([string]$Request.OperationId + [char]10))
        $file.Write($record,0,$record.Length)
        $file.Flush($true)
    }
    finally { if ($null -ne $file) { $file.Dispose() } }
    $moved = $mail.Move($targetFolder)
    if ($null -eq $moved) { throw 'COM MailItem.Move returned no destination item; evidence is indeterminate.' }
    return [pscustomobject]@{
        RunId = $paths.RunId
        OperationId = [string]$Request.OperationId
        MoveReturned = $true
        DestinationEntryId = [string]$moved.EntryID
        JournalCompleted = $false
        AutomaticRetryAllowed = $false
        RequiresIndependentReconciliation = $true
    }
}
