#requires -Version 5.1
# BW3l. NO WRITER FOR THE ORIGINAL JOURNAL EXISTS IN THIS MODULE.
# Write targets are created under fresh OS TEMP child OPA-BW3l-Copy-{GUID N}.
# SyntheticReplica mode is ONLY for offline tests; it never proves history.
function Get-OPA265BW3lCopyPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Directory)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))
    $dir=[IO.Path]::GetFullPath($Directory).TrimEnd([char[]]@('\','/'))
    if ([IO.Path]::GetDirectoryName($dir) -ine $temp -or
        [IO.Path]::GetFileName($dir) -cnotmatch '^OPA-BW3l-Copy-[0-9a-f]{32}$' -or
        -not [IO.Directory]::Exists($dir)) {
        throw 'BW3l refuses anything except a fresh direct OS TEMP copy sandbox.'
    }
    foreach($p in @($temp,$dir)) {
        if (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'BW3l refuses reparse-point TEMP/copy sandbox.'
        }
    }
    return [pscustomobject]@{
        Directory=$dir
        JournalPath=(Join-Path $dir 'copied-original-intent.operations.jsonl')
        MarkerPath=(Join-Path $dir 'bw3l-copy-only.json')
        ClaimPath=(Join-Path $dir 'bw3l-copy-resolution.claim')
    }
}
function Assert-OPA265BW3lRegular {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not [IO.File]::Exists($Path) -or
        (([IO.File]::GetAttributes($Path)) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ('BW3l rejects missing/reparse file '+[IO.Path]::GetFileName($Path))
    }
    return $true
}
function Assert-OPA265BW3lOneIntent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [Parameter(Mandatory=$true)][string]$ExpectedSha256)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    if ($Bytes.Length -lt 2 -or $Bytes.Length -gt 1048576 -or
        $Bytes[$Bytes.Length-1] -ne 10 -or
        $ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-OPAOperationJournalSha256 -Bytes $Bytes) -cne $ExpectedSha256) {
        throw 'BW3l original/copy Intent bytes do not match the exact sealed SHA256.'
    }
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $text=$utf8.GetString($Bytes)
    $line=$text.Substring(0,$text.Length-1)
    if ($line.IndexOf([char]10) -ge 0 -or
        $line.IndexOf([char]13) -ge 0) { throw 'BW3l refuses multi-record/CR journal.' }
    $envelope=ConvertFrom-Json -InputObject $line -ErrorAction Stop
    if ([int]$envelope.V -ne 1 -or
        [string]$envelope.Sha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'BW3l invalid original envelope.'
    }
    $payload=[Convert]::FromBase64String([string]$envelope.Payload)
    if ((Get-OPAOperationJournalSha256 -Bytes $payload) -cne [string]$envelope.Sha256) {
        throw 'BW3l invalid original envelope payload hash.'
    }
    $i=ConvertFrom-Json -InputObject ($utf8.GetString($payload)) -ErrorAction Stop
    if ([string]$i.SchemaVersion -cne '1.0' -or
        [string]$i.Phase -cne 'Intent' -or [string]$i.OperationKind -cne 'MailMove' -or
        [long]$i.Sequence -ne 1 -or
        [string]$i.TransactionId -cne [string]$Pinned.RunId -or
        [string]$i.OperationId -cne [string]$Pinned.OperationId -or
        [string]::IsNullOrWhiteSpace([string]$i.SourceEntryId) -or
        [string]::IsNullOrWhiteSpace([string]$i.ArchivePst) -or
        -not [string]::IsNullOrEmpty([string]$i.ArchiveEntryId) -or
        [long]$i.Size -ne 1436 -or
        [string]$i.InternetMessageId -cne ('<opa264-live3-'+[string]$Pinned.RunId+'@example.invalid>') -or
        [string]$i.Subject -cne ('OPA264 LIVE3 synthetic '+[string]$Pinned.RunId)) {
        throw 'BW3l copied Intent must retain exact historical BW3a identities.'
    }
    return $i
}
function Assert-OPA265BW3lBw3jReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Review,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $exact=@('Schema','Status','Decision','RunId','OperationId','WorkerRequestId',
        'OriginalIntentSha256','AcceptanceRecordSha256','DestinationEntryId',
        'VerifiedHistoricalMoveViaBW3h','SevenHistoricalEvidenceHashesUnchanged',
        'SourceItemCount','ArchiveItemCount','OriginalJournalEventCount',
        'OriginalJournalPhase','ProposedJournalSequence','ProposedJournalPhase',
        'PinnedIntentSizeBytes','PinnedArchiveSizeBytes','ManuallyAcceptedSyntheticDifferenceBytes',
        'SingleSyntheticSizeAcceptanceVerified','LegacyLive6ExecuteApplicable',
        'ExistingResolutionClaimFound','FutureClaimPathReservedInDesignOnly',
        'FutureClaimCreated','FutureExclusiveJournalLockImplemented',
        'FutureJournalAppendWriterImplemented',
        'CrashGapAfterClaimBeforeAppendRequiresManualStop',
        'CrashGapAfterAppendBeforeVerifyRequiresManualStop',
        'ConcurrentAppendRequiresExclusiveLockAndFreshSHA256',
        'OriginalJournalRetentionRequired','FullMAPIContentByteEqualityVerified',
        'SizeDriftCauseEstablished','JournalReconciliationAuthorized',
        'JournalWritePermitIssued','JournalChanged','JournalCompleted','JournalReconciled',
        'OutlookMoveExecuted','AutomaticRetryAllowed','ProductionReady','NextAction')
    if ($null -eq $Review -or $Review -is [array] -or $Review -is [string] -or
        @($Review.PSObject.Properties.Name).Count -ne $exact.Count) {
        throw 'BW3l requires complete exact BW3j read-only verdict.'
    }
    foreach($f in $exact) {
        if ($Review.PSObject.Properties.Name -cnotcontains $f) { throw ('BW3l missing BW3j field '+$f) }
    }
    if ([string]$Review.Schema -cne '2.6.5-BW3j.BW3ScopedJournalResolutionDesignReadOnly.1' -or
        [string]$Review.Status -cne 'BW3ScopedResolutionDesignEvidenceVerifiedAuthorizationNotIssued' -or
        [string]$Review.Decision -cne 'DesignOnlyNoJournalAppendWithoutSeparateExplicitAuthorization' -or
        [string]$Review.RunId -cne [string]$Pinned.RunId -or
        [string]$Review.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Review.WorkerRequestId -cne [string]$Pinned.WorkerRequestId -or
        [string]$Review.OriginalIntentSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$Review.AcceptanceRecordSha256 -cne [string]$Pinned.AcceptanceFileSha256 -or
        [string]$Review.DestinationEntryId -cne [string]$Pinned.DestinationEntryId -or
        [int]$Review.SourceItemCount -ne 0 -or [int]$Review.ArchiveItemCount -ne 1 -or
        [int]$Review.OriginalJournalEventCount -ne 1 -or
        [string]$Review.OriginalJournalPhase -cne 'Intent' -or
        [int]$Review.ProposedJournalSequence -ne 2 -or
        [string]$Review.ProposedJournalPhase -cne 'Reconciled' -or
        [long]$Review.PinnedIntentSizeBytes -ne 1436 -or
        [long]$Review.PinnedArchiveSizeBytes -ne 1444 -or
        [long]$Review.ManuallyAcceptedSyntheticDifferenceBytes -ne 8 -or
        [string]$Review.NextAction -cne 'IndependentReviewOfSeparateBW3ScopedWriterDesignAndFreshOneRunUserAuthorization') {
        throw 'BW3l rejects changed BW3j identity, size, journal or decision.'
    }
    foreach($f in @('VerifiedHistoricalMoveViaBW3h','SevenHistoricalEvidenceHashesUnchanged',
        'SingleSyntheticSizeAcceptanceVerified','FutureClaimPathReservedInDesignOnly',
        'CrashGapAfterClaimBeforeAppendRequiresManualStop',
        'CrashGapAfterAppendBeforeVerifyRequiresManualStop',
        'ConcurrentAppendRequiresExclusiveLockAndFreshSHA256','OriginalJournalRetentionRequired')) {
        if ($Review.$f -isnot [bool] -or -not $Review.$f) { throw ('BW3l failed BW3j proof '+$f) }
    }
    foreach($f in @('LegacyLive6ExecuteApplicable','ExistingResolutionClaimFound',
        'FutureClaimCreated','FutureExclusiveJournalLockImplemented','FutureJournalAppendWriterImplemented',
        'FullMAPIContentByteEqualityVerified','SizeDriftCauseEstablished',
        'JournalReconciliationAuthorized','JournalWritePermitIssued','JournalChanged',
        'JournalCompleted','JournalReconciled','OutlookMoveExecuted','AutomaticRetryAllowed',
        'ProductionReady')) {
        if ($Review.$f -isnot [bool] -or $Review.$f) { throw ('BW3l forged journal authority '+$f) }
    }
    return $true
}
function New-OPA265BW3lCopySandbox {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][byte[]]$OriginalIntentBytes,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [switch]$OfflineReplicaForTests)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $sha=Get-OPAOperationJournalSha256 -Bytes $OriginalIntentBytes
    if (-not $OfflineReplicaForTests -and $sha -cne [string]$Pinned.JournalSha256) {
        throw 'BW3l historical copy MUST exactly match pinned original journal bytes.'
    }
    if ($OfflineReplicaForTests -and $sha -ceq [string]$Pinned.JournalSha256) {
        throw 'BW3l offline replica must not impersonate original journal.'
    }
    $i=Assert-OPA265BW3lOneIntent -Bytes $OriginalIntentBytes -Pinned $Pinned -ExpectedSha256 $sha
    $dir=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) ('OPA-BW3l-Copy-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    $paths=Get-OPA265BW3lCopyPaths -Directory $dir
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($paths.JournalPath,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($OriginalIntentBytes,0,$OriginalIntentBytes.Length)
        $stream.Flush($true)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    $mode=if($OfflineReplicaForTests){'OfflineReplicaNotHistoricalProof'}else{'ActualHistoricalByteCopy'}
    $marker=[pscustomobject][ordered]@{
        Schema='2.6.5-BW3l.CopyOnlyRehearsal.1'
        Mode=$mode
        RunId=[string]$Pinned.RunId
        OperationId=[string]$Pinned.OperationId
        OriginalIntentSha256=$sha
        HistoricalPinnedSha256=[string]$Pinned.JournalSha256
        AcceptanceRecordSha256=[string]$Pinned.AcceptanceFileSha256
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        ArchivePst=[string]$i.ArchivePst
        SandboxDirectory=[string]$paths.Directory
        SandboxJournalPath=[string]$paths.JournalPath
        ConsentToOriginalJournalWrite=$false
        ProductionReady=$false
    }
    $utf8=New-Object Text.UTF8Encoding($false)
    $data=$utf8.GetBytes((ConvertTo-Json -InputObject $marker -Depth 4))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($paths.MarkerPath,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($data,0,$data.Length);$stream.Flush($true)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    return [pscustomobject]@{Paths=$paths;Marker=$marker}
}
function Read-OPA265BW3lCopyMarker {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Paths,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3lRegular -Path $Paths.MarkerPath)
    $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Paths.MarkerPath)) -ErrorAction Stop
    $names=@('Schema','Mode','RunId','OperationId','OriginalIntentSha256',
        'HistoricalPinnedSha256','AcceptanceRecordSha256','DestinationEntryId','ArchivePst',
        'SandboxDirectory','SandboxJournalPath','ConsentToOriginalJournalWrite','ProductionReady')
    if (@($m.PSObject.Properties.Name).Count -ne $names.Count) {
        throw 'BW3l marker unexpected field count.'
    }
    foreach($f in $names) { if ($m.PSObject.Properties.Name -cnotcontains $f) { throw ('BW3l marker missing '+$f) } }
    if ([string]$m.Schema -cne '2.6.5-BW3l.CopyOnlyRehearsal.1' -or
        [string]$m.Mode -cnotin @('ActualHistoricalByteCopy','OfflineReplicaNotHistoricalProof') -or
        [string]$m.RunId -cne [string]$Pinned.RunId -or
        [string]$m.OperationId -cne [string]$Pinned.OperationId -or
        [string]$m.HistoricalPinnedSha256 -cne [string]$Pinned.JournalSha256 -or
        [string]$m.AcceptanceRecordSha256 -cne [string]$Pinned.AcceptanceFileSha256 -or
        [string]$m.DestinationEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$m.OriginalIntentSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        ($m.Mode -ceq 'ActualHistoricalByteCopy' -and
            [string]$m.OriginalIntentSha256 -cne [string]$Pinned.JournalSha256) -or
        ($m.Mode -ceq 'OfflineReplicaNotHistoricalProof' -and
            [string]$m.OriginalIntentSha256 -ceq [string]$Pinned.JournalSha256) -or
        [string]::IsNullOrWhiteSpace([string]$m.ArchivePst) -or
        [string]$m.SandboxDirectory -cne [string]$Paths.Directory -or
        [string]$m.SandboxJournalPath -cne [string]$Paths.JournalPath -or
        $m.ConsentToOriginalJournalWrite -isnot [bool] -or $m.ConsentToOriginalJournalWrite -or
        $m.ProductionReady -isnot [bool] -or $m.ProductionReady) {
        throw 'BW3l rejects tampered or write-authorizing copy marker.'
    }
    return $m
}
function Get-OPA265BW3lProposedReconciledBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Intent,
          [Parameter(Mandatory=$true)][object]$Marker,
          [Parameter(Mandatory=$true)][object]$Pinned)
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    if ([string]$Intent.TransactionId -cne [string]$Pinned.RunId -or
        [string]$Intent.OperationId -cne [string]$Pinned.OperationId -or
        [string]$Intent.Phase -cne 'Intent' -or
        [long]$Intent.Sequence -ne 1 -or
        [string]$Intent.ArchivePst -cne [string]$Marker.ArchivePst -or
        [string]$Marker.DestinationEntryId -cne [string]$Pinned.DestinationEntryId) {
        throw 'BW3l proposed terminal event identity mismatch.'
    }
    $payload=[ordered]@{
        SchemaVersion='1.0';Utc=[datetime]::UtcNow.ToString('o')
        TransactionId=[string]$Intent.TransactionId;OperationId=[string]$Intent.OperationId
        Sequence=2;Phase='Reconciled';OperationKind='MailMove'
        WorkerProcessId=0;FailureKind=''
        SourceEntryId=[string]$Intent.SourceEntryId
        ArchiveEntryId=[string]$Pinned.DestinationEntryId
        ArchivePst=[string]$Intent.ArchivePst
        SourceStoreId=[string]$Intent.SourceStoreId
        SourceFolderPath=[string]$Intent.SourceFolderPath
        TargetFolderPath=[string]$Intent.TargetFolderPath
        InternetMessageId=[string]$Intent.InternetMessageId
        Subject=[string]$Intent.Subject;Sender=[string]$Intent.Sender
        Size=[long]$Intent.Size
        Message='BW3l COPY-ONLY rehearsal; +8 synthetic size acceptance is not journal authorization'
    }
    $utf8=New-Object Text.UTF8Encoding($false)
    $content=$utf8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 8 -Compress))
    $envelope=[ordered]@{V=1;Payload=[Convert]::ToBase64String($content);Sha256=(Get-OPAOperationJournalSha256 -Bytes $content)}
    return ,($utf8.GetBytes((ConvertTo-Json -InputObject $envelope -Compress -Depth 4)+[char]10))
}
function Invoke-OPA265BW3lCopyOnlyRehearsal {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SandboxDirectory,
          [Parameter(Mandatory=$true)][object]$Pinned,
          [ValidateSet('None','AfterClaim','PartialAppend','AfterAppend')]
          [string]$CrashPoint='None')
    [void](Assert-OPA265BW3hPinnedIdentity -Pinned $Pinned)
    $paths=Get-OPA265BW3lCopyPaths -Directory $SandboxDirectory
    $marker=Read-OPA265BW3lCopyMarker -Paths $paths -Pinned $Pinned
    [void](Assert-OPA265BW3lRegular -Path $paths.JournalPath)
    if ([IO.File]::Exists($paths.ClaimPath) -or
        [IO.Directory]::Exists($paths.ClaimPath) -or
        (Test-Path -LiteralPath $paths.ClaimPath)) {
        throw 'BW3l copy claim exists: permanent STOP, no retry or cleanup.'
    }
    $original=[IO.File]::ReadAllBytes($paths.JournalPath)
    $preclaimIntent=Assert-OPA265BW3lOneIntent -Bytes $original -Pinned $Pinned -ExpectedSha256 $marker.OriginalIntentSha256
    # ALL copy marker-to-Intent identities MUST match before irreversible CreateNew.
    # In particular, a forged ArchivePst must never consume a claim.
    if ([string]$preclaimIntent.ArchivePst -cne [string]$marker.ArchivePst) {
        throw 'BW3l copy marker/archive identity mismatch BEFORE claim creation.'
    }
    $claim=[pscustomobject][ordered]@{
        Schema='2.6.5-BW3l.CopyOnlyResolutionClaim.1'
        RunId=[string]$Pinned.RunId;OperationId=[string]$Pinned.OperationId
        CopyOriginalSha256=[string]$marker.OriginalIntentSha256
        DestinationEntryId=[string]$Pinned.DestinationEntryId
        Scope='OS-TEMP-COPY-ONLY-NOT-ORIGINAL'
        HistoricJournalWriteAuthorized=$false
        AutomaticRetryAllowed=$false;ProductionReady=$false
    }
    $utf8=New-Object Text.UTF8Encoding($false)
    $claimBytes=$utf8.GetBytes((ConvertTo-Json -InputObject $claim -Depth 5))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($paths.ClaimPath,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($claimBytes,0,$claimBytes.Length);$stream.Flush($true)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    if ($CrashPoint -ceq 'AfterClaim') { throw 'BW3l COPY injected STOP after claim. NEVER retry.' }
    $lock=$null
    try {
        $lock=[IO.FileStream]::new($paths.JournalPath,[IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if ($lock.Length -lt 2 -or $lock.Length -gt 1048576) {
            throw 'BW3l copy journal too long/short under exclusive lock.'
        }
        $underLock=New-Object byte[] ([int]$lock.Length)
        $pos=0
        while($pos -lt $underLock.Length) {
            $read=$lock.Read($underLock,$pos,$underLock.Length-$pos)
            if($read -le 0){throw 'BW3l short read under lock.'}
            $pos+=$read
        }
        $i=Assert-OPA265BW3lOneIntent -Bytes $underLock -Pinned $Pinned -ExpectedSha256 $marker.OriginalIntentSha256
        if ([string]$i.ArchivePst -cne [string]$marker.ArchivePst) {
            throw 'BW3l copy archive PST identity changed under lock.'
        }
        $entry=Get-OPA265BW3lProposedReconciledBytes -Intent $i -Marker $marker -Pinned $Pinned
        [void]$lock.Seek(0,[IO.SeekOrigin]::End)
        if($CrashPoint -ceq 'PartialAppend') {
            $count=[Math]::Min(17,$entry.Length-1)
            $lock.Write($entry,0,$count);$lock.Flush($true)
            throw 'BW3l COPY injected torn tail. NEVER retry.'
        }
        $lock.Write($entry,0,$entry.Length);$lock.Flush($true)
    } finally { if ($null -ne $lock) {$lock.Dispose()} }
    if($CrashPoint -ceq 'AfterAppend'){throw 'BW3l COPY injected STOP after flushed append. NEVER retry.'}
    $j=Read-OPAOperationJournal -Path $paths.JournalPath
    if ([bool]$j.TrailingPartial -or @($j.Events).Count -ne 2) {
        throw 'BW3l copy replay did not preserve two complete events.'
    }
    $terminal=$j.Events[1]
    if ([string]$terminal.Phase -cne 'Reconciled' -or
        [long]$terminal.Sequence -ne 2 -or
        [string]$terminal.TransactionId -cne [string]$Pinned.RunId -or
        [string]$terminal.OperationId -cne [string]$Pinned.OperationId -or
        [string]$terminal.ArchiveEntryId -cne [string]$Pinned.DestinationEntryId -or
        [string]$terminal.ArchivePst -cne [string]$marker.ArchivePst) {
        throw 'BW3l copy terminal identity incorrect.'
    }
    $replay=Resolve-OPAOperationRecovery -Journal $j
    if (@($replay.Indeterminate).Count -ne 0 -or
        @($replay.Resolved).Count -ne 1 -or
        [string]$replay.Resolved[0].Status -cne 'Reconciled') {
        throw 'BW3l copy replay did not classify the cloned journal as resolved.'
    }
    $final=Get-OPAOperationJournalSha256 -Bytes ([IO.File]::ReadAllBytes($paths.JournalPath))
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW3l.CopyOnlyRehearsalResult.1'
        Status='OnlySandboxCopyReconciledHistoricalJournalUntouched'
        CopyMode=[string]$marker.Mode
        SandboxDirectory=[string]$paths.Directory
        OriginalIntentSha256=[string]$marker.OriginalIntentSha256
        SandboxFinalJournalSha256=$final
        CopyJournalEventCount=2
        CopyReconciled=$true
        CopyDurableClaimCreated=$true
        HistoricalJournalChanged=$false
        HistoricalJournalReconciled=$false
        HistoricalJournalWriteAuthorized=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
