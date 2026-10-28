#requires -Version 5.1
# BW3k: TEST-ONLY journal append, never accepts historical BW3a RunId,
# PST, Outlook COM, production paths or operator journal consent.
# CreateNew claim is permanent: even an injected crash is NEVER retried.
function Get-OPA265BW3kSandboxPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Directory)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
    if ([IO.Path]::GetDirectoryName($full) -ine $temp -or
        [IO.Path]::GetFileName($full) -cnotmatch '^OPA-BW3k-Sandbox-[0-9a-f]{32}$' -or
        -not [IO.Directory]::Exists($full)) {
        throw 'BW3k accepts only existing immediate TEMP child OPA-BW3k-Sandbox-{32hex}.'
    }
    foreach($d in @($temp,$full)) {
        if (([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'BW3k rejects reparse-point temporary directory.'
        }
    }
    return [pscustomobject]@{
        Directory=$full
        MarkerPath=(Join-Path $full 'bw3k-test-only.marker.json')
        JournalPath=(Join-Path $full 'isolated.operations.jsonl')
        ClaimPath=(Join-Path $full 'bw3k-resolution.claim')
    }
}
function Assert-OPA265BW3kRegularFile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not [IO.File]::Exists($Path) -or
        (([IO.File]::GetAttributes($Path)) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ('BW3k absent or reparse-point file '+[IO.Path]::GetFileName($Path))
    }
    return $true
}
function Read-OPA265BW3kMarker {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths)
    [void](Assert-OPA265BW3kRegularFile -Path ([string]$Paths.MarkerPath))
    $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText([string]$Paths.MarkerPath)) -ErrorAction Stop
    $fields=@('Schema','Purpose','RunId','OperationId','SandboxDirectory',
        'JournalPath','OriginalJournalSha256','SourceEntryId','ArchiveEntryId',
        'ArchivePst','IntentSizeBytes','ArchiveSizeBytes',
        'OperatorJournalConsent','AutomaticRetryAllowed','ProductionReady')
    if (@($m.PSObject.Properties.Name).Count -ne $fields.Count) {
        throw 'BW3k marker field count mismatch.'
    }
    foreach($f in $fields) {
        if ($m.PSObject.Properties.Name -cnotcontains $f) { throw ('BW3k marker missing '+$f) }
    }
    $run=[guid]::Empty;$op=[guid]::Empty
    if ([string]$m.Schema -cne '2.6.5-BW3k.IsolatedSyntheticJournalFixture.1' -or
        [string]$m.Purpose -cne 'SyntheticTemporaryJournalOnlyNeverOriginalBW3a' -or
        -not [guid]::TryParse([string]$m.RunId,[ref]$run) -or $run -eq [guid]::Empty -or
        -not [guid]::TryParse([string]$m.OperationId,[ref]$op) -or $op -eq [guid]::Empty -or
        [string]$m.RunId -cne $run.ToString('D') -or
        [string]$m.OperationId -cne $op.ToString('D') -or
        [string]$m.RunId -ceq 'a7b51427-7494-43f4-bc96-64915f6bee7e' -or
        [string]$m.OperationId -ceq '9bd83da2-d47e-404f-a4fd-792852b58dec' -or
        [string]$m.SandboxDirectory -cne [string]$Paths.Directory -or
        [string]$m.JournalPath -cne [string]$Paths.JournalPath -or
        [string]$m.OriginalJournalSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$m.OriginalJournalSha256 -ceq '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648' -or
        [string]$m.SourceEntryId -cne ('BW3K-ONLY-SRC-'+[string]$m.RunId) -or
        [string]$m.ArchiveEntryId -cne ('BW3K-ONLY-DST-'+[string]$m.RunId) -or
        [string]$m.ArchivePst -cne 'BW3K-SANDBOX-NO-PST' -or
        [long]$m.IntentSizeBytes -ne 1436 -or
        [long]$m.ArchiveSizeBytes -ne 1444 -or
        $m.OperatorJournalConsent -isnot [bool] -or $m.OperatorJournalConsent -or
        $m.AutomaticRetryAllowed -isnot [bool] -or $m.AutomaticRetryAllowed -or
        $m.ProductionReady -isnot [bool] -or $m.ProductionReady) {
        throw 'BW3k rejects modified, real or non-test marker.'
    }
    return $m
}
function Assert-OPA265BW3kClaimAbsent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths)
    $p=[string]$Paths.ClaimPath
    if ([IO.File]::Exists($p) -or [IO.Directory]::Exists($p) -or
        (Test-Path -LiteralPath $p)) {
        throw 'BW3k resolution claim exists (including partial): STOP, never retry.'
    }
    return $true
}
function Assert-OPA265BW3kOneIntentBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][object]$Marker)
    if ($Bytes.Length -lt 2 -or $Bytes.Length -gt 1048576 -or
        $Bytes[$Bytes.Length-1] -ne 10) {
        throw 'BW3k original journal truncated or too large.'
    }
    $utf8=New-Object System.Text.UTF8Encoding($false,$true)
    $value=$utf8.GetString($Bytes)
    $line=$value.Substring(0,$value.Length-1)
    if ([string]::IsNullOrWhiteSpace($line) -or
        $line.IndexOf([char]10) -ge 0 -or $line.IndexOf([char]13) -ge 0) {
        throw 'BW3k original journal is not exactly one LF-terminated Intent.'
    }
    if ((Get-OPAOperationJournalSha256 -Bytes $Bytes) -cne [string]$Marker.OriginalJournalSha256) {
        throw 'BW3k original journal SHA256 differs from fixture marker.'
    }
    $envelope=ConvertFrom-Json -InputObject $line -ErrorAction Stop
    if ([string]$envelope.V -cne '1' -or [string]$envelope.Sha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'BW3k original journal envelope mismatch.'
    }
    $payload=[Convert]::FromBase64String([string]$envelope.Payload)
    if ((Get-OPAOperationJournalSha256 -Bytes $payload) -cne [string]$envelope.Sha256) {
        throw 'BW3k original envelope payload hash invalid.'
    }
    $intent=ConvertFrom-Json -InputObject ($utf8.GetString($payload)) -ErrorAction Stop
    if ([string]$intent.SchemaVersion -cne '1.0' -or
        [string]$intent.TransactionId -cne [string]$Marker.RunId -or
        [string]$intent.OperationId -cne [string]$Marker.OperationId -or
        [long]$intent.Sequence -ne 1 -or
        [string]$intent.Phase -cne 'Intent' -or
        [string]$intent.OperationKind -cne 'MailMove' -or
        [string]$intent.SourceEntryId -cne [string]$Marker.SourceEntryId -or
        [string]$intent.ArchiveEntryId -cne '' -or
        [string]$intent.ArchivePst -cne [string]$Marker.ArchivePst -or
        [long]$intent.Size -ne 1436 -or
        [string]$intent.InternetMessageId -cne ('<bw3k-'+[string]$Marker.RunId+'@example.invalid>') -or
        [string]$intent.Subject -cne ('BW3k sandbox synthetic '+[string]$Marker.RunId)) {
        throw 'BW3k original Intent is not exact synthetic sandbox record.'
    }
    return $intent
}
function New-OPA265BW3kIsolatedFixture {
    [CmdletBinding()]
    param()
    $run=[guid]::NewGuid().ToString('D')
    $op=[guid]::NewGuid().ToString('D')
    $dir=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) ('OPA-BW3k-Sandbox-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    $paths=Get-OPA265BW3kSandboxPaths -Directory $dir
    # A fake ArchivePst string, NO PST files, Outlook or real email.
    $evt=@{
        Path=$paths.JournalPath; TransactionId=$run; OperationId=$op
        Sequence=1; Phase='Intent'; OperationKind='MailMove'
        SourceEntryId=('BW3K-ONLY-SRC-'+$run); ArchivePst='BW3K-SANDBOX-NO-PST'
        InternetMessageId=('<bw3k-'+$run+'@example.invalid>')
        Subject=('BW3k sandbox synthetic '+$run); Size=1436
    }
    [void](Write-OPAOperationJournalEvent @evt)
    $sha=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $mark=[pscustomobject][ordered]@{
        Schema='2.6.5-BW3k.IsolatedSyntheticJournalFixture.1'
        Purpose='SyntheticTemporaryJournalOnlyNeverOriginalBW3a'
        RunId=$run
        OperationId=$op
        SandboxDirectory=$paths.Directory
        JournalPath=$paths.JournalPath
        OriginalJournalSha256=$sha
        SourceEntryId=('BW3K-ONLY-SRC-'+$run)
        ArchiveEntryId=('BW3K-ONLY-DST-'+$run)
        ArchivePst='BW3K-SANDBOX-NO-PST'
        IntentSizeBytes=1436L
        ArchiveSizeBytes=1444L
        OperatorJournalConsent=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
    $utf8=New-Object System.Text.UTF8Encoding($false)
    $data=$utf8.GetBytes((ConvertTo-Json -InputObject $mark -Depth 5))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($paths.MarkerPath,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($data,0,$data.Length)
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    [void](Read-OPA265BW3kMarker -Paths $paths)
    return [pscustomobject]@{Paths=$paths;Marker=$mark}
}
function Get-OPA265BW3kTerminalBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Intent,
          [Parameter(Mandatory=$true)][object]$Marker)
    $payload=[ordered]@{
        SchemaVersion='1.0';Utc=[datetime]::UtcNow.ToString('o')
        TransactionId=[string]$Marker.RunId;OperationId=[string]$Marker.OperationId
        Sequence=2;Phase='Reconciled';OperationKind='MailMove'
        WorkerProcessId=0;FailureKind='';SourceEntryId=[string]$Intent.SourceEntryId
        ArchiveEntryId=[string]$Marker.ArchiveEntryId;ArchivePst=[string]$Marker.ArchivePst
        SourceStoreId=[string]$Intent.SourceStoreId
        SourceFolderPath=[string]$Intent.SourceFolderPath
        TargetFolderPath=[string]$Intent.TargetFolderPath
        InternetMessageId=[string]$Intent.InternetMessageId
        Subject=[string]$Intent.Subject;Sender=[string]$Intent.Sender
        Size=[long]$Intent.Size
        Message='BW3k TEST-ONLY synthetic journal append, NO Outlook Move'
    }
    $utf8=New-Object System.Text.UTF8Encoding($false)
    $bytes=$utf8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 8 -Compress))
    $envelope=[ordered]@{
        V=1;Payload=[Convert]::ToBase64String($bytes)
        Sha256=Get-OPAOperationJournalSha256 -Bytes $bytes
    }
    return ,($utf8.GetBytes((ConvertTo-Json -InputObject $envelope -Depth 4 -Compress)+[char]10))
}
function Assert-OPA265BW3kTerminalReplay {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Journal,
          [Parameter(Mandatory=$true)][object]$Marker)
    if ([bool]$Journal.TrailingPartial -or @($Journal.Events).Count -ne 2) {
        throw 'BW3k terminal journal must contain exactly two complete records.'
    }
    $last=$Journal.Events[1]
    if ([string]$last.Phase -cne 'Reconciled' -or
        [string]$last.OperationKind -cne 'MailMove' -or
        [long]$last.Sequence -ne 2 -or
        [string]$last.TransactionId -cne [string]$Marker.RunId -or
        [string]$last.OperationId -cne [string]$Marker.OperationId -or
        [string]$last.ArchiveEntryId -cne [string]$Marker.ArchiveEntryId -or
        [string]$last.ArchivePst -cne [string]$Marker.ArchivePst) {
        throw 'BW3k terminal journal fields mismatch.'
    }
    $replay=Resolve-OPAOperationRecovery -Journal $Journal
    if ([string]$replay.TransactionId -cne [string]$Marker.RunId -or
        [long]$replay.LastSequence -ne 2 -or
        @($replay.Indeterminate).Count -ne 0 -or
        @($replay.Resolved).Count -ne 1 -or
        [string]$replay.Resolved[0].Status -cne 'Reconciled' -or
        [string]$replay.Resolved[0].ArchiveEntryId -cne [string]$Marker.ArchiveEntryId) {
        throw 'BW3k original recovery replay failed after synthetic append.'
    }
    return $true
}
function Invoke-OPA265BW3kSandboxAppend {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxDirectory,
          [ValidateSet('None','AfterClaim','PartialAppend','AfterAppend')]
          [string]$CrashPoint='None')
    $paths=Get-OPA265BW3kSandboxPaths -Directory $SandboxDirectory
    $mark=Read-OPA265BW3kMarker -Paths $paths
    [void](Assert-OPA265BW3kClaimAbsent -Paths $paths)
    [void](Assert-OPA265BW3kRegularFile -Path ([string]$paths.JournalPath))
    $before=[IO.File]::ReadAllBytes([string]$paths.JournalPath)
    [void](Assert-OPA265BW3kOneIntentBytes -Bytes $before -Marker $mark)
    $claim=[pscustomobject][ordered]@{
        Schema='2.6.5-BW3k.SandboxResolutionClaim.1'
        RunId=[string]$mark.RunId;OperationId=[string]$mark.OperationId
        PreviousJournalSha256=[string]$mark.OriginalJournalSha256
        DestinationEntryId=[string]$mark.ArchiveEntryId
        Scope='TemporarySyntheticJournalOnlyNoPst'
        AutomaticRetryAllowed=$false;ProductionReady=$false
    }
    $utf8=New-Object System.Text.UTF8Encoding($false)
    $data=$utf8.GetBytes((ConvertTo-Json -InputObject $claim -Depth 5))
    $claimStream=$null
    try {
        $claimStream=[IO.FileStream]::new($paths.ClaimPath,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $claimStream.Write($data,0,$data.Length)
        $claimStream.Flush($true)
    } finally { if ($null -ne $claimStream) { $claimStream.Dispose() } }
    if ($CrashPoint -ceq 'AfterClaim') {
        throw 'BW3k INJECTED STOP: claim persisted before append. NEVER retry.'
    }
    $lockedStream=$null
    try {
        $lockedStream=[IO.FileStream]::new($paths.JournalPath,[IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if ($lockedStream.Length -lt 2 -or $lockedStream.Length -gt 1048576) {
            throw 'BW3k journal outside one-Intent bounds while locked.'
        }
        $locked=New-Object byte[] ([int]$lockedStream.Length)
        $offset=0
        while ($offset -lt $locked.Length) {
            $n=$lockedStream.Read($locked,$offset,$locked.Length-$offset)
            if ($n -le 0) { throw 'BW3k short locked journal read.' }
            $offset+=$n
        }
        $intent=Assert-OPA265BW3kOneIntentBytes -Bytes $locked -Marker $mark
        $entry=Get-OPA265BW3kTerminalBytes -Intent $intent -Marker $mark
        [void]$lockedStream.Seek(0,[IO.SeekOrigin]::End)
        if ($CrashPoint -ceq 'PartialAppend') {
            $count=[Math]::Min(17,$entry.Length-1)
            $lockedStream.Write($entry,0,$count)
            $lockedStream.Flush($true)
            throw 'BW3k INJECTED STOP: torn synthetic journal tail. NEVER retry.'
        }
        $lockedStream.Write($entry,0,$entry.Length)
        $lockedStream.Flush($true)
    } finally {
        if ($null -ne $lockedStream) { $lockedStream.Dispose() }
    }
    if ($CrashPoint -ceq 'AfterAppend') {
        throw 'BW3k INJECTED STOP: flushed terminal before verification. NEVER retry.'
    }
    $journal=Read-OPAOperationJournal -Path $paths.JournalPath
    [void](Assert-OPA265BW3kTerminalReplay -Journal $journal -Marker $mark)
    $finalSha=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($finalSha -ceq [string]$mark.OriginalJournalSha256) {
        throw 'BW3k synthetic append failed to alter journal.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3k.IsolatedSyntheticJournalAppendResult.1'
        Status='SandboxJournalReconciledNotHistorical'
        SandboxDirectory=[string]$paths.Directory
        RunId=[string]$mark.RunId
        OriginalJournalSha256=[string]$mark.OriginalJournalSha256
        SandboxFinalJournalSha256=$finalSha
        JournalEventCount=2
        JournalReconciledInSandbox=$true
        HistoricalJournalChanged=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
