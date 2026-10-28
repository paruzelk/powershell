[CmdletBinding()]
param(
    [ValidateSet('Auto','Analyze','Plan','Archive','Resume')]
    [string]$Mode = 'Analyze',

    [string]$ProfileName,
    [string]$Transaction,
    [switch]$WhatIf,
    [switch]$VerboseItems,

    [ValidateRange(0,2147483647)]
    [int]$Limit = 0,

    [ValidateSet('None','Year','YearQuarter','YearMonth')]
    [string]$ArchiveGrouping = 'YearQuarter',

    [ValidateRange(0,1200)]
    [int]$OlderThanMonths = 12,

    [ValidateRange(0.1,1000)]
    [double]$SourcePstHighWatermarkGB = 40,

    [ValidateRange(0.1,1000)]
    [double]$SourcePstTargetSizeGB = 35,

    [switch]$DisableStoragePolicy,

    [ValidateRange(0.01,1000)]
    [double]$MaxArchivePstSizeGB = 10,

    [ValidateRange(0,100)]
    [double]$SafetyMarginGB = 0.5,

    [switch]$ArchiveDeletedItems,

    [switch]$ArchiveDrafts,

    # Junk is excluded by default. Explicit opt-in may archive junk mail.
    [switch]$ArchiveJunk,

    # Archive without a date cutoff requires an explicit acknowledgement.
    [switch]$IgnoreAge,

    [ValidateRange(1,100)][int]$AutoMaxResumeAttempts = 3,

    # Journal durability:
    #   Fast - Flush(false) per move, Flush(true) at batch boundaries (25).
    #          Fastest. A process kill is survivable; an OS/power failure may
    #          lose the last few journal writes that are still cached.
    #   Safe - Flush(true) after every journal append. Minimizes the window
    #          of journal loss on OS/power failure; does not eliminate it
    #          (loss at storage device, controller or filesystem layer is
    #          outside the application's guarantee).
    [ValidateSet('Fast','Safe')]
    [string]$DurabilityMode = 'Fast',

    # Retention for Auto-mode cleanup of stale transaction files.
    # Only Completed checkpoints older than this many days are removed.
    # Failed, unknown, corrupt and unsupported states and orphan journals
    # are retained for recovery and manual diagnosis.
    [ValidateRange(1,3650)]
    [int]$TransactionRetentionDays = 7,

    # Disable automatic transaction cleanup in Auto mode.
    [switch]$DisableTransactionCleanup,

    # Minimum batch used by Auto target-driven sizing. Kept at 50 for
    # backward-compatible behaviour; administrators can lower it when
    # physical source/target margins are tight.
    [ValidateRange(1,100000)]
    [int]$AutoTargetMinimum = 50,

    # Stop Auto after consecutive verified batches without logical removal.
    [ValidateRange(1,1000)]
    [int]$AutoMaxEmptyBatches = 2,
    # 2.6.5 read-only Archive/Resume Worker canary; exits before COM or PST changes.
    [switch]$WorkerPilot,
    [switch]$ConfirmDevWorkerPilot,
    [ValidateRange(1,1)][int]$WorkerPilotMaxOperations = 1,
    [ValidateRange(1,30)][int]$WorkerPilotTimeoutSeconds = 10,
    [switch]$WorkerPilotKeepArtifacts,
    # BW2: isolated read-only probe for ONE previously created synthetic fixture.
    [switch]$WorkerPilotProbeSynthetic,
    [string]$WorkerPilotRunId = '',
    [string]$WorkerPilotSourcePst = '',
    # BW2c: explicit size consent only for one read-only synthetic probe.
    [switch]$WorkerPilotConfirmSourceSizeDifference,
    [long]$WorkerPilotExpectedSourceSizeBytes = 0,
    # BW4a OPTION B: explicit read-only one-Intent quarantine preflight.
    [switch]$WorkerPilotReviewHistoricalFence,
    [string]$WorkerPilotExpectedHistoricalJournalSha256 = '',
    [switch]$WorkerPilotReviewPerItemFence,
    [string]$WorkerPilotPrimaryPath = '',
    [string]$WorkerPilotIndependentPath = '',
    # BW4c: explicitly attach to already-running Outlook and read one exact mail twice.
    [switch]$WorkerPilotReviewOutlookPerItem,
    [string]$WorkerPilotCandidateFolderEntryId = '',
    [string]$WorkerPilotCandidateEntryId = '',
    [ValidateRange(1,5000)][int]$WorkerPilotMaxFolderItems = 1000
)

$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($Transaction) -and $Mode -ne 'Resume') {
    throw '-Transaction can only be used with -Mode Resume. Specify -Mode Resume explicitly.'
}

# Durability mode is process-wide so the dot-sourced journal writers can read
# it without threading the option through every call. The explicit flag is
# remembered so Resume can honor the transaction's stored mode by default.
$script:OPADurabilityModeExplicit = $PSBoundParameters.ContainsKey('DurabilityMode')
$global:OPADurabilityMode = $DurabilityMode

$script:OPAAutoDefaultLimit = 500
$script:OPAAutoTargetMinimum = $AutoTargetMinimum
$script:OPAAutoSourcePstPaths = @()
$script:OPAAutoResumedCheckpoint = $null
$script:OPAAutoStorageTrackArchive = $false
$script:OPAAutoStorageTrackResume = $false
if ($Mode -in @('Archive','Plan','Auto') -and $OlderThanMonths -eq 0 -and -not $IgnoreAge) {
    throw 'OlderThanMonths=0 removes the age filter. Explicitly supply -IgnoreAge to proceed.'
}

. "$PSScriptRoot\Core\Version.ps1"
. "$PSScriptRoot\Core\Runtime\JsonSupport.ps1"
. "$PSScriptRoot\Core\Runtime\ComManager.ps1"
. "$PSScriptRoot\Core\Discovery\OutlookDiscovery.ps1"
. "$PSScriptRoot\Core\Discovery\DiscoveryDiagnostics.ps1"
. "$PSScriptRoot\Core\Archive\SystemFolders.ps1"
. "$PSScriptRoot\Core\Archive\ArchiveSelector.ps1"
. "$PSScriptRoot\Core\Archive\StoragePolicy.ps1"
. "$PSScriptRoot\Core\Archive\DuplicateIndex.ps1"
. "$PSScriptRoot\Core\Archive\ArchiveGrouping.ps1"
. "$PSScriptRoot\Core\Archive\ArchivePlanner.ps1"
. "$PSScriptRoot\Core\Archive\ArchiveTransaction.ps1"
. "$PSScriptRoot\Core\Archive\AutoRecoveryPolicy.ps1"
. "$PSScriptRoot\Core\Archive\MailMover.ps1"
. "$PSScriptRoot\Core\Archive\ArchiveVerifier.ps1"
. "$PSScriptRoot\Core\Archive\ArchiveReport.ps1"

. "$PSScriptRoot\Core\Worker\BoundedWorkerCanary265.ps1"
# Guard BEFORE New-OPAComSession, transaction creation, MailMover or any PST changes.
# FIX13b route remains unchanged when WorkerPilot is disabled.
$pilotOptionsSpecified = ($PSBoundParameters.ContainsKey('WorkerPilotMaxOperations') -or
    $PSBoundParameters.ContainsKey('WorkerPilotTimeoutSeconds') -or
    $PSBoundParameters.ContainsKey('WorkerPilotKeepArtifacts') -or
    $PSBoundParameters.ContainsKey('WorkerPilotProbeSynthetic') -or
    $PSBoundParameters.ContainsKey('WorkerPilotRunId') -or
    $PSBoundParameters.ContainsKey('WorkerPilotSourcePst') -or
    $PSBoundParameters.ContainsKey('WorkerPilotConfirmSourceSizeDifference') -or
    $PSBoundParameters.ContainsKey('WorkerPilotExpectedSourceSizeBytes') -or
    $PSBoundParameters.ContainsKey('WorkerPilotReviewHistoricalFence') -or
    $PSBoundParameters.ContainsKey('WorkerPilotExpectedHistoricalJournalSha256') -or
    $PSBoundParameters.ContainsKey('WorkerPilotReviewPerItemFence') -or
    $PSBoundParameters.ContainsKey('WorkerPilotPrimaryPath') -or
    $PSBoundParameters.ContainsKey('WorkerPilotIndependentPath') -or
    $PSBoundParameters.ContainsKey('WorkerPilotReviewOutlookPerItem') -or
    $PSBoundParameters.ContainsKey('WorkerPilotCandidateFolderEntryId') -or
    $PSBoundParameters.ContainsKey('WorkerPilotCandidateEntryId') -or
    $PSBoundParameters.ContainsKey('WorkerPilotMaxFolderItems'))
$pilotGate = Assert-OPA265WorkerPilotGate -Mode $Mode -PilotRequested ([bool]$WorkerPilot) -ExplicitConsent ([bool]$ConfirmDevWorkerPilot) -WhatIfEnabled ([bool]$WhatIf) -Limit $Limit -ProfileName $ProfileName -Transaction $Transaction -MaxOperations $WorkerPilotMaxOperations -TimeoutSeconds $WorkerPilotTimeoutSeconds -OtherPilotOptionsSpecified $pilotOptionsSpecified
if ($WorkerPilot) {
    . "$PSScriptRoot\Core\Worker\WorkerProtocol.ps1"
    . "$PSScriptRoot\Core\Worker\WorkerHost.ps1"
    . "$PSScriptRoot\Core\Worker\WorkerControl.ps1"
    if (-not $WorkerPilotReviewOutlookPerItem -and (
        $PSBoundParameters.ContainsKey('WorkerPilotCandidateFolderEntryId') -or
        $PSBoundParameters.ContainsKey('WorkerPilotCandidateEntryId') -or
        $PSBoundParameters.ContainsKey('WorkerPilotMaxFolderItems'))) {
        throw 'BW4c candidate identity and scan options require explicit BW4c read-only mode.'
    }
    if ($WorkerPilotReviewOutlookPerItem -and
        ($WorkerPilotReviewHistoricalFence -or $WorkerPilotReviewPerItemFence -or
         $WorkerPilotProbeSynthetic -or $WorkerPilotConfirmSourceSizeDifference -or
         $PSBoundParameters.ContainsKey('WorkerPilotExpectedSourceSizeBytes') -or
         $PSBoundParameters.ContainsKey('WorkerPilotPrimaryPath') -or
         $PSBoundParameters.ContainsKey('WorkerPilotIndependentPath'))) {
        throw 'BW4c cannot combine legacy pilot routes, synthetic probe, size consent or user-supplied witnesses.'
    }
    if ($WorkerPilotReviewHistoricalFence -and $WorkerPilotReviewPerItemFence) {
        throw 'BW4b conflicts with BW4a pilot review.'
    }
    if ($WorkerPilotReviewOutlookPerItem) {
        if ([string]::IsNullOrWhiteSpace($WorkerPilotRunId) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotSourcePst) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotExpectedHistoricalJournalSha256) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotCandidateFolderEntryId) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotCandidateEntryId) -or
            [string]::IsNullOrWhiteSpace($ProfileName)) {
            throw 'BW4c requires exact pinned historical evidence, Outlook profile, candidate folder and MailItem EntryID.'
        }
        $pilotResult=& "$PSScriptRoot\Core\Diagnostics\Test-OPA265BW4cOutlookPerItemReadOnly.ps1" -RunId $WorkerPilotRunId -SourcePst $WorkerPilotSourcePst -ExpectedJournalSha256 $WorkerPilotExpectedHistoricalJournalSha256 -Mode $Mode -Transaction $Transaction -FolderEntryId $WorkerPilotCandidateFolderEntryId -CandidateEntryId $WorkerPilotCandidateEntryId -ExpectedProfileName $ProfileName -MaxFolderItems $WorkerPilotMaxFolderItems -Review -ConfirmExistingOutlookReadOnly
    } elseif ($WorkerPilotReviewPerItemFence) {
        if ($WorkerPilotProbeSynthetic -or $WorkerPilotConfirmSourceSizeDifference -or
            $PSBoundParameters.ContainsKey('WorkerPilotExpectedSourceSizeBytes') -or
            [string]::IsNullOrWhiteSpace($WorkerPilotRunId) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotSourcePst) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotExpectedHistoricalJournalSha256) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotPrimaryPath) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotIndependentPath)) {
            throw 'BW4b requires pinned history and two local read-only witnesses.'
        }
        $pilotResult=& "$PSScriptRoot\Core\Diagnostics\Test-OPA265BW4bPerItemFencingReadOnly.ps1" -RunId $WorkerPilotRunId -SourcePst $WorkerPilotSourcePst -ExpectedJournalSha256 $WorkerPilotExpectedHistoricalJournalSha256 -Mode $Mode -Transaction $Transaction -PrimaryPath $WorkerPilotPrimaryPath -IndependentPath $WorkerPilotIndependentPath -Review
    } elseif ($WorkerPilotReviewHistoricalFence) {
        if ($PSBoundParameters.ContainsKey('WorkerPilotPrimaryPath') -or
            $PSBoundParameters.ContainsKey('WorkerPilotIndependentPath') -or
            $WorkerPilotConfirmSourceSizeDifference -or
            $PSBoundParameters.ContainsKey('WorkerPilotExpectedSourceSizeBytes') -or
            [string]::IsNullOrWhiteSpace($WorkerPilotRunId) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotSourcePst) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotExpectedHistoricalJournalSha256)) {
            throw 'BW4a requires exact historic RunId/PST/SHA256 and disallows synthetic probe or size consent.'
        }
        # Delegate to a self-contained read-only BW4a entrypoint; this
        # production CLI must NOT import legacy BW3 audit or writer modules.
        $pilotResult=& "$PSScriptRoot\Core\Diagnostics\Test-OPA265BW4aHistoricalIntentIsolationReadOnly.ps1" -RunId $WorkerPilotRunId -SourcePst $WorkerPilotSourcePst -ExpectedJournalSha256 $WorkerPilotExpectedHistoricalJournalSha256 -Mode $Mode -Transaction $Transaction -Review
    } elseif ($WorkerPilotProbeSynthetic) {
        if ($PSBoundParameters.ContainsKey('WorkerPilotPrimaryPath') -or
            $PSBoundParameters.ContainsKey('WorkerPilotIndependentPath') -or
            $PSBoundParameters.ContainsKey('WorkerPilotExpectedHistoricalJournalSha256')) { throw 'BW4b witnesses are not allowed in BW2 probe.' }
        if ([string]::IsNullOrWhiteSpace($WorkerPilotRunId) -or
            [string]::IsNullOrWhiteSpace($WorkerPilotSourcePst)) {
            throw 'BW2 requires exact -WorkerPilotRunId and -WorkerPilotSourcePst with -WorkerPilotProbeSynthetic.'
        }
        . "$PSScriptRoot\Core\Worker\Live3SyntheticScope.ps1"
        . "$PSScriptRoot\Core\Worker\Live5Reconciliation.ps1"
        . "$PSScriptRoot\Core\Worker\Live6JournalResolution.ps1"
        . "$PSScriptRoot\Core\Archive\OperationJournal.ps1"
        . "$PSScriptRoot\Core\Worker\SyntheticReadOnlyProbe265BW2.ps1"
        . "$PSScriptRoot\Core\Worker\BoundedWorkerProbe265BW2.ps1"
        if ([bool]$WorkerPilotConfirmSourceSizeDifference -ne
            $PSBoundParameters.ContainsKey('WorkerPilotExpectedSourceSizeBytes')) {
            throw 'BW2c: source size consent requires BOTH confirm and explicit observed bytes.'
        }
        if ($WorkerPilotConfirmSourceSizeDifference -and $WorkerPilotExpectedSourceSizeBytes -le 0) {
            throw 'BW2c: expected observed source bytes must be positive.'
        }
        $pilotResult = Invoke-OPA265BW2BoundedReadOnlyCanary -Gate $pilotGate -RunId $WorkerPilotRunId -SourcePst $WorkerPilotSourcePst -KeepArtifacts:$WorkerPilotKeepArtifacts -ConfirmSourceSizeDifference:$WorkerPilotConfirmSourceSizeDifference -ExpectedSourceSizeBytes $WorkerPilotExpectedSourceSizeBytes
    } else {
        if ($PSBoundParameters.ContainsKey('WorkerPilotExpectedHistoricalJournalSha256') -or
            $PSBoundParameters.ContainsKey('WorkerPilotPrimaryPath') -or
            $PSBoundParameters.ContainsKey('WorkerPilotIndependentPath') -or
            -not [string]::IsNullOrWhiteSpace($WorkerPilotRunId) -or
            -not [string]::IsNullOrWhiteSpace($WorkerPilotSourcePst) -or
            [bool]$WorkerPilotConfirmSourceSizeDifference -or
            $PSBoundParameters.ContainsKey('WorkerPilotExpectedSourceSizeBytes')) {
            throw 'BW2 fixture options require explicit -WorkerPilotProbeSynthetic.'
        }
        # BW1 backwards-compatible Ping-only path, still before any COM.
        $pilotResult = Invoke-OPA265BoundedWorkerCanary -Gate $pilotGate -KeepArtifacts:$WorkerPilotKeepArtifacts
    }
    Write-Output $pilotResult
    exit 0
}



Write-Host "OutlookPOP3Archive $($script:OPAApplicationVersion)"
Write-Host ("Computer : {0}" -f $env:COMPUTERNAME)
Write-Host ("User     : {0}" -f $env:USERNAME)
Write-Host ("Mode     : {0}" -f $Mode)
Write-Host ("Profile  : {0}" -f $ProfileName)
Write-Host ("Transaction: {0}" -f $Transaction)
Write-Host ("WhatIf   : {0}" -f [bool]$WhatIf)
Write-Host ("Limit    : {0}" -f $(if ($Limit -gt 0) { $Limit } else { 'Unlimited' }))
Write-Host ("Grouping : {0}" -f $ArchiveGrouping)
Write-Host ("OlderThan: {0}" -f $(if($OlderThanMonths -gt 0){"$OlderThanMonths months"}else{'Disabled'}))
Write-Host ("Storage  : {0}" -f $(if($DisableStoragePolicy){'Disabled'}else{"Source High=$SourcePstHighWatermarkGB GB / Target=$SourcePstTargetSizeGB GB"}))
$archiveSafeLimitGB = $MaxArchivePstSizeGB - $SafetyMarginGB
if ($archiveSafeLimitGB -le 0) {
    throw "MaxArchivePstSizeGB ($MaxArchivePstSizeGB GB) must be greater than SafetyMarginGB ($SafetyMarginGB GB)."
}
Write-Host ("Archive  : Max={0} GB / Safety={1} GB / Safe={2} GB" -f $MaxArchivePstSizeGB,$SafetyMarginGB,[math]::Round($archiveSafeLimitGB,4))
Write-Host ("Folders  : DeletedItems={0} / Drafts={1} / Junk={2} / Outbox=Never" -f [bool]$ArchiveDeletedItems,[bool]$ArchiveDrafts,[bool]$ArchiveJunk)
Write-Host ("Durability: {0}" -f $global:OPADurabilityMode)

function Get-OPAAutoTransactionCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Discovery
    )

    $candidates = @()

    foreach ($source in @($Discovery.Pop3Sources)) {
        $dir = Join-Path ([IO.Path]::GetDirectoryName([string]$source.FilePath)) 'OutlookPOP3Archive-Transactions'
        if (-not (Test-Path -LiteralPath $dir)) { continue }

        foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            if ($file.Name -eq 'DuplicateIndex.json' -or $file.Name -like '*.backup') { continue }

            $transactionId = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            if ([string]::IsNullOrWhiteSpace($transactionId)) { continue }

            $state = $null
            $jsonError = $null
            $schemaError = $null

            try {
                $state = Read-OPAJsonFile -Path $file.FullName
            }
            catch {
                $jsonError = $_.Exception.Message
            }

            if ($null -eq $state) {
                # Keep unreadable checkpoints visible to Auto. The Resume path
                # can reconstruct the transaction from DuplicateIndex; Auto
                # must never silently discard a damaged checkpoint and create
                # a second Archive transaction against the same PST.
                $candidates += [pscustomobject]@{
                    TransactionId = $transactionId
                    Path          = $file.FullName
                    SourcePst     = [string]$source.FilePath
                    Status        = 'Corrupt'
                    Started       = $file.LastWriteTime
                    IsCorrupt     = $true
                    IsUnsupported = $false
                    Error         = $jsonError
                }
                continue
            }

            # A readable Completed transaction must never be treated as pending,
            # even when its checkpoint uses an old schema that the current build
            # can no longer validate.
            if ([string]$state.Status -eq 'Completed') { continue }

            try {
                Test-OPAArchiveTransactionSchema -TransactionState $state | Out-Null
            }
            catch {
                $schemaError = $_.Exception.Message
                $candidates += [pscustomobject]@{
                    TransactionId = $transactionId
                    Path          = $file.FullName
                    SourcePst     = [string]$source.FilePath
                    Status        = 'Unsupported'
                    Started       = $file.LastWriteTime
                    IsCorrupt     = $false
                    IsUnsupported = $true
                    Error         = $schemaError
                }
                continue
            }

            $sourceMatches = $false
            try {
                $sourceMatches = [IO.Path]::GetFullPath([string]$state.SourcePst) -ieq [IO.Path]::GetFullPath([string]$source.FilePath)
            }
            catch {}

            if (-not $sourceMatches) { continue }

            $started = $file.LastWriteTime
            try { if ($state.Started) { $started = [datetime]$state.Started } } catch {}

            $candidates += [pscustomobject]@{
                TransactionId = $transactionId
                Path          = $file.FullName
                SourcePst     = [string]$source.FilePath
                Status        = [string]$state.Status
                Started       = $started
                IsCorrupt     = $false
                IsUnsupported = $false
                Error         = $null
            }
        }
    }

    # Auto must resume the newest unfinished transaction.
    @($candidates | Sort-Object @{Expression='Started';Descending=$true}, @{Expression='TransactionId';Descending=$true})
}

function New-OPAAutoRunMutex {
    [CmdletBinding()]
    param()

    $safeUser = (("{0}_{1}" -f [string]$env:USERDOMAIN,[string]$env:USERNAME) -replace '[^A-Za-z0-9_.-]', '_')
    $name = "Global\OutlookPOP3Archive-Auto-$safeUser"
    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($false, $name, [ref]$createdNew)

    try {
        if (-not $mutex.WaitOne(0)) {
            $mutex.Dispose()
            return $null
        }
    }
    catch [System.Threading.AbandonedMutexException] {
        # The previous owner died without releasing. WaitOne has already
        # acquired the mutex on our behalf; log and continue.
        Write-Warning 'Recovered abandoned auto-run mutex from a previous crashed run.'
    }
    catch {
        try { $mutex.Dispose() } catch {}
        throw
    }

    $mutex
}

function Close-OPAAutoRunMutex {
    param([Parameter(Mandatory=$true)][object]$Mutex)

    try { [void]$Mutex.ReleaseMutex() } catch {}
    finally { $Mutex.Dispose() }
}

function Get-OPAPop3SourceFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$StoreHandle,
        [switch]$ArchiveDeletedItems,
        [switch]$ArchiveDrafts,
        [switch]$ArchiveJunk
    )
    $root = $null
    try { $root = $StoreHandle.GetRootFolder() }
    catch { throw "Unable to open POP3 store root: $($_.Exception.Message)" }
    if ($null -eq $root) { throw 'POP3 store root folder is unavailable.' }

    $wellKnownMap = $null
    try { $wellKnownMap = Get-OPAWellKnownFolderEntryIds -Store $StoreHandle }
    catch { throw "Unable to classify POP3 system folders: $($_.Exception.Message)" }

    # FIX10a: same recursive traversal in Plan, Archive and Resume.
    # The default Sent Items folder and all nested user mail folders are
    # included. Excluded system folders are pruned with their descendants.
    @(Get-OPAEligiblePop3MailFolders -RootFolder $root `
        -WellKnownEntryIdMap $wellKnownMap `
        -ArchiveDeletedItems:$ArchiveDeletedItems `
        -ArchiveDrafts:$ArchiveDrafts -ArchiveJunk:$ArchiveJunk)
}

function Get-OPASourceByPst {
    param(
        [Parameter(Mandatory=$true)][object]$Discovery,
        [Parameter(Mandatory=$true)][string]$SourcePst
    )

    foreach ($source in @($Discovery.Pop3Sources)) {
        try {
            if ([IO.Path]::GetFullPath([string]$source.FilePath) -ieq [IO.Path]::GetFullPath($SourcePst)) {
                return $source
            }
        }
        catch {}
    }

    throw "POP3 source PST was not found in the current Outlook discovery: $SourcePst"
}

function Get-OPAArchiveCutoff {
    param([Parameter(Mandatory=$true)][int]$OlderThanMonths)
    if ($OlderThanMonths -le 0) { return $null }
    return (Get-Date).AddMonths(-$OlderThanMonths)
}

function Get-OPAArchivePstPathsForTransaction {
    param([Parameter(Mandatory=$true)][object]$Transaction)
    $paths = @()
    $paths += @($Transaction.State.ArchivePsts | ForEach-Object { if ($_.Path) { [string]$_.Path } })
    $paths += @($Transaction.State.Steps | ForEach-Object { if ($_.ArchivePst) { [string]$_.ArchivePst } })
    if (@($Transaction.State.ArchivePsts).Count -eq 0 -and $Transaction.State.ArchivePst) { $paths += [string]$Transaction.State.ArchivePst }
    @($paths | Where-Object { $_ } | Select-Object -Unique)
}

function Get-OPAArchiveStoresForTransaction {
    param(
        [Parameter(Mandatory=$true)][object]$Namespace,
        [Parameter(Mandatory=$true)][object]$Transaction
    )
    $stores = @()
    foreach ($path in @(Get-OPAArchivePstPathsForTransaction -Transaction $Transaction)) {
        $stores += New-OPAArchivePst -Namespace $Namespace -ArchivePst $path
    }
    @($stores | Sort-Object FilePath -Unique)
}

function Get-OPACombinedDuplicateIndexForTransaction {
    param([Parameter(Mandatory=$true)][object]$Transaction)

    # DuplicateIndex is stored per source directory, not per archive PST.
    # Loading it once for every archive PST would duplicate the same entries
    # in memory and can corrupt recovery counts after a multi-PST split.
    $unique = @{}
    $indexFilesSeen = @{}
    foreach ($path in @(Get-OPAArchivePstPathsForTransaction -Transaction $Transaction)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            # All archive PSTs of one source share one physical index file;
            # load each unique file exactly once.
            $indexFile = Join-Path ([IO.Path]::GetDirectoryName($path)) 'OutlookPOP3Archive-Transactions\DuplicateIndex.json'
            if ($indexFilesSeen.ContainsKey($indexFile.ToLowerInvariant())) { continue }
            $indexFilesSeen[$indexFile.ToLowerInvariant()] = $true

            $idx = Import-OPADuplicateIndex -ArchivePst $path
            foreach ($entry in @($idx.Entries)) {
                if ([string]$entry.TransactionId -ne [string]$Transaction.TransactionId) { continue }
                $key = "{0}|{1}" -f [string]$entry.SourceEntryId, [string]$entry.ArchiveEntryId
                if (-not $unique.ContainsKey($key)) { $unique[$key] = $entry }
            }
        }
        catch {
            throw "Unable to load DuplicateIndex for archive PST '$path': $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{ Version='1.1'; SchemaVersion='1.1'; Entries=@($unique.Values) }
}

function Get-OPARecoveryMetadataFromDuplicateIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$DuplicateIndex,
        [Parameter(Mandatory=$true)][string]$TransactionId,
        [int]$ExplicitLimit = 0,
        [string]$DefaultGrouping = 'YearQuarter'
    )

    $entries = @(
        $DuplicateIndex.Entries | Where-Object { [string]$_.TransactionId -eq $TransactionId }
    )

    if ($entries.Count -eq 0) {
        throw "DuplicateIndex contains no entries for transaction '$TransactionId'."
    }

    $limits = @(
        $entries |
            ForEach-Object { if ($_.PSObject.Properties.Name -contains 'TransactionLimit') { [int]$_.TransactionLimit } } |
            Where-Object { $_ -gt 0 } |
            Select-Object -Unique
    )

    if ($limits.Count -eq 1) {
        $storedLimit = [int]$limits[0]
        if ($ExplicitLimit -gt 0 -and $ExplicitLimit -ne $storedLimit) {
            throw "Recovery Limit mismatch for transaction '$TransactionId'. DuplicateIndex records original Limit=$storedLimit; supplied -Limit=$ExplicitLimit. Use the original Limit."
        }
        $recoveryLimit = $storedLimit
    }
    elseif ($ExplicitLimit -gt 0) {
        $recoveryLimit = $ExplicitLimit
    }
    else {
        throw "Transaction '$TransactionId' checkpoint is unreadable and DuplicateIndex does not contain a reliable original Limit. Resume requires -Limit <original limit>."
    }

    if ($recoveryLimit -lt $entries.Count) {
        throw "Recovery Limit $recoveryLimit is smaller than the $($entries.Count) moves already recorded in DuplicateIndex for transaction '$TransactionId'."
    }

    $groupings = @(
        $entries |
            ForEach-Object { if ($_.PSObject.Properties.Name -contains 'ArchiveGrouping' -and $_.ArchiveGrouping) { [string]$_.ArchiveGrouping } } |
            Select-Object -Unique
    )
    $recoveryGrouping = if ($groupings.Count -eq 1 -and $groupings[0] -in @('None','Year','YearQuarter','YearMonth')) { [string]$groupings[0] } else { $DefaultGrouping }

    $folderPaths = @(
        $entries | ForEach-Object { if ($_.SourceFolderPath) { [string]$_.SourceFolderPath } } | Select-Object -Unique
    )

    $agePolicies = @(
        $entries |
            ForEach-Object { if ($_.PSObject.Properties.Name -contains 'OlderThanMonths' -and $null -ne $_.OlderThanMonths) { [int]$_.OlderThanMonths } } |
            Select-Object -Unique
    )
    $cutoffs = @(
        $entries |
            ForEach-Object { if ($_.PSObject.Properties.Name -contains 'ArchiveCutoff' -and $_.ArchiveCutoff) { [string]$_.ArchiveCutoff } } |
            Select-Object -Unique
    )

    $recoveryOlderThanMonths = if ($agePolicies.Count -eq 1 -and $agePolicies[0] -ge 0) { [int]$agePolicies[0] } else { 0 }
    $recoveryCutoff = $null
    if ($cutoffs.Count -eq 1 -and $cutoffs[0]) {
        try { $recoveryCutoff = [datetime]$cutoffs[0] } catch { $recoveryCutoff = $null }
    }

    [pscustomobject]@{
        Entries         = $entries
        Limit           = $recoveryLimit
        Grouping        = $recoveryGrouping
        FolderPath      = if ($folderPaths.Count -eq 1) { $folderPaths[0] } else { $null }
        OlderThanMonths = $recoveryOlderThanMonths
        ArchiveCutoff   = $recoveryCutoff
    }
}

$session = $null
$autoMutex = $null

try {
    if ($Mode -in @('Auto','Archive','Resume')) {
        $autoMutex = New-OPAAutoRunMutex
        if ($null -eq $autoMutex) {
            # NOTE: Write-Host + exit, NOT Write-Error — with
            # $ErrorActionPreference='Stop' Write-Error would throw and the
            # catch block would convert exit code 10 into 1.
            Write-Host 'ERROR: Another OutlookPOP3Archive instance is already running for this user. Auto/Archive/Resume execution is locked.'
            exit 10
        }
    }

    $session = New-OPAComSession -ProfileName $ProfileName

    $discovery = Get-OutlookDiscovery -ComSession $session -ProfileName $ProfileName

    Write-OPADiscoverySummary -Discovery $discovery

    # Auto mode prunes stale transaction files before selection.
    # Active statuses (Running/Planned/Created/Recovered) are kept;
    # DuplicateIndex.json is never touched.
    if ($Mode -eq 'Auto' -and -not $DisableTransactionCleanup) {
        [void](Remove-OPAStaleTransactions -Discovery $discovery -RetentionDays $TransactionRetentionDays -WhatIf:$WhatIf)
    }

    if (@($discovery.Pop3Sources).Count -eq 0) {
        throw 'No POP3 PST sources were discovered. IMAP sources are intentionally excluded.'
    }

    if ($Mode -eq 'Auto') {
        Assert-OPAAutoNoOrphanJournals -Discovery $discovery
        $pending = @(Get-OPAAutoTransactionCandidates -Discovery $discovery)

        # Fail closed when any unfinished checkpoint is unsupported or when
        # several transactions compete for this PST. Never silently start a
        # new Archive after ignoring an unresolved transaction.
        $selected = Resolve-OPAAutoPendingTransaction -Candidates $pending

        if ($null -ne $selected) {
            Write-Host ''
            Write-Host '## Auto Orchestrator'
            Write-Host ("Decision : Resume transaction {0} ({1})" -f $selected.TransactionId, $selected.Status)
            if ($selected.IsCorrupt) {
                Write-Host 'Checkpoint: unreadable; Resume will enter safe recovery path.'
            }

            if ($WhatIf) {
                Write-Host 'WhatIf    : no Resume changes will be made.'
                return
            }

            $tries = Register-OPAAutoResumeAttempt -CheckpointPath ([string]$selected.Path) -MaxAttempts $AutoMaxResumeAttempts
            Write-Host ("Auto recovery attempt: {0}/{1} for {2}" -f $tries,$AutoMaxResumeAttempts,$selected.TransactionId)
            $script:OPAAutoResumedCheckpoint = [string]$selected.Path
            $script:OPAAutoStorageTrackResume = $true
            $Mode = 'Resume'
            $Transaction = $selected.TransactionId
        }
        else {
            $effectiveLimit = if ($Limit -gt 0) { $Limit } else { $script:OPAAutoDefaultLimit }

            if ($effectiveLimit -le 0) {
                throw 'Auto mode requires a positive archive limit.'
            }

            Write-Host ''
            Write-Host '## Auto Orchestrator'

            if ($DisableStoragePolicy) {
                Write-Host ("Decision : Start new Archive (Limit={0}; Storage Policy disabled)" -f $effectiveLimit)
            }
            else {
                $policyDecisions = @()
                foreach ($source in @($discovery.Pop3Sources)) {
                    $policyDecisions += Get-OPAStoragePolicyDecision `
                        -SourcePst ([string]$source.FilePath) `
                        -HighWatermarkGB $SourcePstHighWatermarkGB `
                        -TargetSizeGB $SourcePstTargetSizeGB `
                        -OlderThanMonths $OlderThanMonths `
                        -BatchLimit $effectiveLimit `
                        -AutoMaxEmptyBatches $AutoMaxEmptyBatches
                }

                foreach ($decision in $policyDecisions) {
                    Write-OPAStoragePolicyDecision -Decision $decision
                }

                $archiveRequired = @($policyDecisions | Where-Object { $_.Decision -eq 'ArchiveRequired' })
                if ($archiveRequired.Count -eq 0) {
                    $paused = @($policyDecisions | Where-Object { $_.Decision -in @('CompactRequired','AutoPaused') })
                    if ($paused.Count -gt 0) {
                        Write-Host 'Decision : Auto paused by Storage Policy. Manual Compact assessment or investigation required.' -ForegroundColor Yellow
                    }
                    else { Write-Host 'Decision : No archive required by Storage Policy.' }
                    if ($WhatIf) {
                        Write-Host 'WhatIf    : no Archive changes will be made.'
                    }
                    return
                }

                $script:OPAAutoSourcePstPaths = @(
                    $archiveRequired | ForEach-Object { [IO.Path]::GetFullPath([string]$_.SourcePst) }
                )

                # Target-driven batch sizing. RequiredReductionBytes is the
                # physical bytes we intend to logically remove; divide by the
                # observed average message size to estimate how many messages
                # that is. The batch cannot exceed BatchLimit, but if Target
                # needs fewer messages we shrink the batch accordingly so we
                # do not overshoot. If Target needs more than BatchLimit, we
                # keep BatchLimit and warn that Target will not be reached in
                # one run.
                try {
                    $totalMsgsNeeded = 0
                    $sourceDetails = New-Object System.Collections.Generic.List[string]
                    foreach ($d in $archiveRequired) {
                        if ($d.PSObject.Properties.Name -notcontains 'RequiredReductionBytes') { continue }
                        $r = [int64]$d.RequiredReductionBytes
                        if ($r -le 0) { continue }
                        $srcAvg = Get-OPAAverageMessageSize -SourcePst ([string]$d.SourcePst)
                        if ($srcAvg -le 0) { continue }
                        $srcMsgs = [int][Math]::Ceiling([double]$r / [double]$srcAvg)
                        $totalMsgsNeeded += $srcMsgs
                        $sourceDetails.Add(("{0}: {1} msgs (reduction {2:N2} GB / avg {3:N2} KB)" -f `
                            [IO.Path]::GetFileName([string]$d.SourcePst), $srcMsgs, ($r / 1GB), ($srcAvg / 1KB))) | Out-Null
                    }
                    if ($totalMsgsNeeded -gt 0) {
                        $targetLimit = [int][Math]::Min($effectiveLimit, [Math]::Max($script:OPAAutoTargetMinimum, $totalMsgsNeeded))
                        Write-Host ("Target override : {0} messages across {1} source(s) (minimum {2})" -f $targetLimit, $sourceDetails.Count, $script:OPAAutoTargetMinimum)
                        foreach ($line in $sourceDetails) { Write-Host ("  {0}" -f $line) }
                        if ($totalMsgsNeeded -gt $effectiveLimit) {
                            $runsNeeded = [int][Math]::Ceiling([double]$totalMsgsNeeded / [double]$effectiveLimit)
                            Write-Host ("Note            : Target needs ~{0} messages; this batch is capped at {1}. ~{2} run(s) required." -f `
                                $totalMsgsNeeded, $effectiveLimit, $runsNeeded) -ForegroundColor Yellow
                        }
                        $effectiveLimit = $targetLimit
                    }
                }
                catch {
                    Write-Warning ("Target-driven batch sizing skipped: {0}" -f $_.Exception.Message)
                }
                Write-Host ("Decision : Start new Archive (Limit={0}; Sources={1})" -f $effectiveLimit, $script:OPAAutoSourcePstPaths.Count)
            }

            if ($WhatIf) {
                Write-Host 'WhatIf    : no Archive changes will be made.'
                return
            }

            $script:OPAAutoStorageTrackArchive = $true
            $Mode = 'Archive'
            $Limit = $effectiveLimit
        }
    }

    if ($Mode -eq 'Analyze') {
        Write-Host ''
        Write-Host 'Analyze completed.'
    }
    elseif ($Mode -eq 'Plan') {
        $planCutoff = Get-OPAArchiveCutoff -OlderThanMonths $OlderThanMonths
        $plan = New-OPAArchivePlan `
            -Discovery $discovery `
            -Settings ([pscustomobject]@{ ArchiveGrouping = $ArchiveGrouping; OlderThanMonths = $OlderThanMonths; ArchiveCutoff = $planCutoff }) `
            -Limit $Limit `
            -OlderThanMonths $OlderThanMonths `
            -ArchiveCutoff $planCutoff `
            -ArchiveDeletedItems:$ArchiveDeletedItems `
            -ArchiveDrafts:$ArchiveDrafts `
            -ArchiveJunk:$ArchiveJunk `
            -VerboseItems:$VerboseItems

        [void](Test-OPAArchivePlan -Plan $plan)
        Write-OPAArchivePlan -Plan $plan

        if (-not $DisableStoragePolicy) {
            foreach ($source in @($discovery.Pop3Sources)) {
                $decision = Get-OPAStoragePolicyDecision `
                    -SourcePst ([string]$source.FilePath) `
                    -HighWatermarkGB $SourcePstHighWatermarkGB `
                    -TargetSizeGB $SourcePstTargetSizeGB `
                    -OlderThanMonths $OlderThanMonths `
                    -BatchLimit $(if ($Limit -gt 0) { $Limit } else { $script:OPAAutoDefaultLimit }) `
                    -AutoMaxEmptyBatches $AutoMaxEmptyBatches
                Write-OPAStoragePolicyDecision -Decision $decision
            }
        }

        Write-Host ("Plan completed. Test limit: {0}" -f $(if ($Limit -gt 0) { $Limit } else { 'Unlimited' }))
    }
    elseif ($Mode -eq 'Archive') {
        if ($WhatIf) {
            Write-Host ''
            Write-Host 'Archive WhatIf: no PST changes will be made.'
            return
        }

        if ($Limit -le 0) {
            throw 'Archive mode requires -Limit > 0. This build remains a controlled test release.'
        }

        foreach ($source in @($discovery.Pop3Sources)) {
            $sourcePathNormalized = $null
            try { $sourcePathNormalized = [IO.Path]::GetFullPath([string]$source.FilePath) } catch {}

            if (@($script:OPAAutoSourcePstPaths).Count -gt 0 -and
                -not (@($script:OPAAutoSourcePstPaths) -contains $sourcePathNormalized)) {
                Write-Host ("Storage Policy: skip source PST {0} (below high watermark)." -f $source.FilePath)
                continue
            }

            $sourceFolders = @(Get-OPAPop3SourceFolders -StoreHandle $source.StoreHandle -ArchiveDeletedItems:$ArchiveDeletedItems -ArchiveDrafts:$ArchiveDrafts -ArchiveJunk:$ArchiveJunk)
            if ($sourceFolders.Count -eq 0) {
                Write-Host ("Source PST {0}: no Outlook folders exposed; skip." -f $source.FilePath)
                continue
            }
            $sourcePst = [string]$source.FilePath
            $archivePst = ''
            $sourceItemsBefore = 0
            foreach ($sf in @($sourceFolders)) {
                try { $sourceItemsBefore += [int]$sf.Items.Count } catch {}
            }

            Write-Host ''
            Write-Host '## Controlled Archive'
            Write-Host ("Source PST : {0}" -f $sourcePst)
            Write-Host 'Archive PST: automatic (by message year/part)'
            Write-Host ("Folders    : {0}" -f $sourceFolders.Count)
            Write-Host ("Limit      : {0} moved items globally" -f $Limit)

            $sourceSizeBefore = [int64]0
            try { $sourceSizeBefore = [int64](Get-Item -LiteralPath $sourcePst).Length } catch {}

            $tx = New-OPAArchiveTransaction `
                -SourcePst $sourcePst `
                -ArchivePst $archivePst `
                -Limit $Limit `
                -FolderPath $(if($sourceFolders.Count -eq 1){[string]$sourceFolders[0].FolderPath}else{$null}) `
                -ArchiveGrouping $ArchiveGrouping `
                -OlderThanMonths $OlderThanMonths `
                -ArchiveCutoff (Get-OPAArchiveCutoff -OlderThanMonths $OlderThanMonths) `
                -SourcePstSizeBeforeBytes $sourceSizeBefore `
                -AccountEmail ([string]$source.AccountEmail) `
                -ArchiveDeletedItems ([bool]$ArchiveDeletedItems) `
                -ArchiveDrafts ([bool]$ArchiveDrafts) `
                -ArchiveJunk ([bool]$ArchiveJunk) `
                -DurabilityMode $global:OPADurabilityMode

            # Persist Auto origin so a later manual Resume can still credit
            # this verified Auto transaction if it completes recovery.
            $tx.State['AutoStorageTracked'] = [bool]$script:OPAAutoStorageTrackArchive
            Save-OPAArchiveTransaction `
                -Transaction $tx `
                -Status 'Planned' `
                -Step 'Plan' `
                -Message ("Controlled archive limit {0}" -f $Limit)

            Set-OPAArchiveTransactionCount `
                -Transaction $tx `
                -Planned 0 `
                -Executed 0 `
                -Verified 0

            Set-OPAArchiveTransactionStorageStats -Transaction $tx -SourcePstSizeBeforeBytes $sourceSizeBefore -SourcePstSizeAfterBytes $sourceSizeBefore

            Save-OPAArchiveTransaction `
                -Transaction $tx `
                -Status 'Running' `
                -Step 'ArchiveReady' `
                -Message 'Archive PSTs will be created on demand by the size/year planner.' `
                -WriteCheckpoint

            $moved = Move-OPAItemsWithLimit `
                -Namespace $session.Namespace `
                -SourceFolders $sourceFolders `
                -Transaction $tx `
                -Limit $Limit `
                -ArchiveGrouping $ArchiveGrouping `
                -OlderThanCutoff (Get-OPAArchiveCutoff -OlderThanMonths ([int]$tx.State.OlderThanMonths)) `
                -MaxArchivePstSizeGB $MaxArchivePstSizeGB `
                -SafetyMarginGB $SafetyMarginGB

            # FIX9: Build completed source->destination pairs from the complete
            # journal and DuplicateIndex. The latter is NOT verification proof.
            $verifyIndex = Get-OPACombinedDuplicateIndexForTransaction -Transaction $tx
            $expectedMoves = @(Get-OPAExpectedMovesFromTransaction -Transaction $tx -DuplicateIndex $verifyIndex)
            $archiveStores = @(Get-OPAArchiveStoresForTransaction -Namespace $session.Namespace -Transaction $tx)
            $result = Test-OPAArchiveMoves `
                -Namespace $session.Namespace `
                -SourceFolder $sourceFolders `
                -ArchiveStores $archiveStores `
                -ExpectedMoved ([int]$tx.State.Executed) `
                -ExpectedMoves $expectedMoves

            # Reconstruct physical message bytes from unique completed
            # planned items instead of trusting potentially stale checkpoint
            # increments from a terminated Move phase.
            $verifiedLogicalBytes = Get-OPACompletedLogicalBytes -Transaction $tx -CompletedMoves $expectedMoves
            Set-OPAArchiveLogicalTelemetryFromMoves -Transaction $tx -CompletedMoves $expectedMoves
            Set-OPAArchiveTransactionStorageStats -Transaction $tx `
                -LogicalFreedBytes $verifiedLogicalBytes `
                -SourcePstSizeAfterBytes ([int64](Get-Item -LiteralPath ([string]$tx.State.SourcePst)).Length)

            Set-OPAArchiveTransactionCount `
                -Transaction $tx `
                -Planned ([int]$tx.State.Planned) `
                -Executed ([int]$tx.State.Executed) `
                -Verified $(if ($result.Verified) { [int]$tx.State.Executed } else { 0 })

            $phaseComplete = ($result.Verified -and ([int]$tx.State.Executed -ge [int]$tx.State.Planned))
            $archiveStatus = if (-not $result.Verified) { 'VerificationFailed' } elseif ($phaseComplete) { 'Completed' } else { 'Running' }
            # FIX13 durability: credit the independently verified Auto batch
            # BEFORE committing Completed. If the ledger write fails or the
            # process is killed, the pending checkpoint forces Auto Resume;
            # ledger ID checks prevent double credit on retry.
            if ($script:OPAAutoStorageTrackArchive -and $archiveStatus -eq 'Completed') {
                $progress = Register-OPAAutoStorageProgress -Transaction $tx -ConfirmedVerifiedCompletion
                Write-Host ("Auto storage progress: {0:N2} MB logical credited over {1} verified batch(es)." -f `
                    ([double]$progress.CumulativeLogicalFreedBytes / 1MB), $progress.CompletedBatches)
            }
            Save-OPAArchiveTransaction `
                -Transaction $tx `
                -Status $archiveStatus `
                -Step $(if ($phaseComplete) { 'Verify' } else { 'VerifyPartial' }) `
                -Message ("Moved={0}; Target={1}; SourceRemaining={2}; Missing={3}; PhaseComplete={4}" -f $moved, $result.TargetCount, $result.SourceRemaining, $result.MissingEntryIds.Count, $phaseComplete)

            Write-OPAArchiveReport -Result $result -Transaction $tx
        }
    }
    elseif ($Mode -eq 'Resume') {
        $resumeStartedAt = Get-Date
        if ([string]::IsNullOrWhiteSpace($Transaction)) {
            throw 'Resume requires -Transaction <TransactionId>. Automatic selection of the latest transaction is disabled for safety.'
        }

        $txPath = $null

        foreach ($sourceCandidate in @($discovery.Pop3Sources)) {
            $candidateDir = Join-Path ([IO.Path]::GetDirectoryName([string]$sourceCandidate.FilePath)) 'OutlookPOP3Archive-Transactions'
            $candidate = Join-Path $candidateDir "$Transaction.json"

            if (Test-Path -LiteralPath $candidate) {
                $txPath = $candidate
                break
            }
        }

        if ($null -eq $txPath) {
            throw "Transaction '$Transaction' was not found under any discovered POP3 source."
        }

        $tx = $null
        $source = $null
        $sourcePstForTx = $null
        $entriesRecovered = @()
        $recoveryError = $null

        # First decide whether the checkpoint itself is readable. Only a
        # genuinely unreadable/empty JSON checkpoint enters DuplicateIndex
        # recovery. Semantic validation failures are fatal and are not treated
        # as corruption.
        $raw = $null
        $checkpointReadable = $true
        try {
            $raw = Read-OPAJsonFile -Path $txPath
        }
        catch {
            $checkpointReadable = $false
            $recoveryError = $_.Exception.Message
        }

        if ($checkpointReadable) {
            Test-OPAArchiveTransactionSchema -TransactionState $raw | Out-Null

            if ([string]$raw.TransactionId -ne $Transaction) {
                throw 'Transaction checkpoint has an invalid TransactionId.'
            }

            $sourcePstForTx = [string]$raw.SourcePst
            $source = Get-OPASourceByPst -Discovery $discovery -SourcePst $sourcePstForTx
            $tx = Get-OPAArchiveTransaction -SourcePst $sourcePstForTx -TransactionId $Transaction
        }
        else {
            # Recovery path: a crashed process may leave a zero-byte/corrupt
            # checkpoint. DuplicateIndex contains durable per-move metadata.
            $source = $null

            foreach ($candidateSource in @($discovery.Pop3Sources)) {
                $candidateTxDir = Join-Path ([IO.Path]::GetDirectoryName([string]$candidateSource.FilePath)) 'OutlookPOP3Archive-Transactions'
                $candidateTx = Join-Path $candidateTxDir "$Transaction.json"

                if ([IO.Path]::GetFullPath($candidateTx) -ieq [IO.Path]::GetFullPath($txPath)) {
                    $source = $candidateSource
                    break
                }
            }

            if ($null -eq $source) {
                throw "Unable to recover transaction '$Transaction': source POP3 PST is unknown."
            }

            $sourcePstForTx = [string]$source.FilePath

            # Recovery is multi-PST aware. The checkpoint itself is unreadable,
            # so ArchivePsts/Steps cannot be trusted. Reconstruct the archive
            # set from the source directory and use TransactionId inside each
            # DuplicateIndex as the authoritative filter.
            $archiveBase = [IO.Path]::GetFileNameWithoutExtension($sourcePstForTx)
            $archivePattern = "$archiveBase.Archive-*.pst"
            $archivePstRecoveredStates = @(Get-OPAArchivePstPartsOnDiskAll -SourcePst $sourcePstForTx)
            $archivePstRecoveredPaths = @($archivePstRecoveredStates | ForEach-Object { [string]$_.Path })

            if ($archivePstRecoveredPaths.Count -eq 0) {
                throw "Unable to recover transaction '$Transaction': no archive PSTs matching '$archivePattern' were found."
            }

            $recoveryEntries = @()
            foreach ($archivePath in $archivePstRecoveredPaths) {
                try {
                    $idx = Import-OPADuplicateIndex -ArchivePst $archivePath
                    $recoveryEntries += @($idx.Entries | Where-Object { [string]$_.TransactionId -eq $Transaction })
                }
                catch {
                    # An unrelated archive PST may exist without a usable index.
                    # It cannot contribute recovery data, but it must not block
                    # other transaction-scoped indexes from being used.
                }
            }

            $recoveryUnique = @{}
            foreach ($entry in @($recoveryEntries)) {
                $key = "{0}|{1}" -f [string]$entry.SourceEntryId, [string]$entry.ArchiveEntryId
                if (-not $recoveryUnique.ContainsKey($key)) { $recoveryUnique[$key] = $entry }
            }

            $indexRecovered = [pscustomobject]@{
                Version       = '1.1'
                SchemaVersion = '1.1'
                Entries       = @($recoveryUnique.Values)
            }

            $metadataRecovered = Get-OPARecoveryMetadataFromDuplicateIndex `
                -DuplicateIndex $indexRecovered `
                -TransactionId $Transaction `
                -ExplicitLimit $Limit `
                -DefaultGrouping $ArchiveGrouping

            $archivePstRecovered = if ($archivePstRecoveredStates.Count -gt 0) { [string]$archivePstRecoveredStates[0].Path } else { $null }

            $entriesRecovered = @($metadataRecovered.Entries)
            $sourceFoldersRecovered = @(Get-OPAPop3SourceFolders -StoreHandle $source.StoreHandle -ArchiveDeletedItems:$ArchiveDeletedItems -ArchiveDrafts:$ArchiveDrafts -ArchiveJunk:$ArchiveJunk)

            if ($metadataRecovered.FolderPath -and @($sourceFoldersRecovered | Where-Object { [string]$_.FolderPath -ieq [string]$metadataRecovered.FolderPath }).Count -eq 0) {
                throw "Recovered transaction source folder is no longer available. Checkpoint=$($metadataRecovered.FolderPath)"
            }

            # Rebuild a full plan up to the original transaction limit before
            # persisting the recovered checkpoint. DuplicateIndex tells us which
            # items are already completed; live candidate selection rebuilds the
            # remaining portion of the original controlled plan.
            $plannedRecoveredCompleted = @(
                $entriesRecovered |
                    ForEach-Object {
                        [pscustomobject]@{
                            EntryId          = [string]$_.SourceEntryId
                            Subject          = [string]$_.Subject
                            ReceivedTime     = [string]$_.ReceivedTime
                            ArchiveDate      = [string]$_.ReceivedTime
                            SourceFolderPath = [string]$_.SourceFolderPath
                            SourceFolderName = if($_.SourceFolderPath){[IO.Path]::GetFileName([string]$_.SourceFolderPath)}else{$null}
                        }
                    }
            )

            $plannedRecovered = @($plannedRecoveredCompleted)
            $recoveredRemainingCount = [int]$metadataRecovered.Limit - $plannedRecoveredCompleted.Count

            if ($recoveredRemainingCount -gt 0) {
                $extraRecovered = @(
                    @($sourceFoldersRecovered | ForEach-Object {
                        Get-OPAArchiveCandidates `
                            -SourceFolder $_ `
                            -Limit 2147483647 `
                            -OlderThanCutoff $metadataRecovered.ArchiveCutoff `
                            -ExcludeEntryIds @($indexRecovered.Entries | ForEach-Object { [string]$_.SourceEntryId })
                    }) | Sort-Object ArchiveDate,EntryID | Select-Object -First $recoveredRemainingCount
                )

                $plannedRecovered = @(
                    $plannedRecoveredCompleted + $extraRecovered |
                        Select-Object -First ([int]$metadataRecovered.Limit)
                )
            }

            if ($plannedRecovered.Count -ne [int]$metadataRecovered.Limit) {
                throw "Unable to reconstruct the original transaction plan safely. Original Limit=$($metadataRecovered.Limit); recovered completed=$($plannedRecoveredCompleted.Count); reconstructed plan=$($plannedRecovered.Count)."
            }

            $sourcePstSizeRecovered = [int64]0
            try { $sourcePstSizeRecovered = [int64](Get-Item -LiteralPath $sourcePstForTx).Length } catch {}
            $logicalFreedRecovered = [int64]0
            foreach ($entry in @($entriesRecovered)) {
                if ($entry.PSObject.Properties.Name -contains 'Size' -and $null -ne $entry.Size) {
                    try { $logicalFreedRecovered += [int64]$entry.Size } catch {}
                }
            }

            $stateRecovered = [ordered]@{
                TransactionId      = $Transaction
                Version            = $script:OPATransactionSchemaVersion
                SchemaVersion      = $script:OPATransactionSchemaVersion
                ApplicationVersion = $script:OPAApplicationVersion
                Status             = 'Recovered'
                Started            = (Get-Date).ToString('o')
                Updated            = (Get-Date).ToString('o')
                SourcePst          = $sourcePstForTx
                AccountEmail       = [string]$source.AccountEmail
                ArchivePst         = $archivePstRecovered
                ArchivePsts        = @($archivePstRecoveredStates | ForEach-Object {
                    [pscustomobject]@{
                        Path      = [string]$_.Path
                        Year      = [int]$_.Year
                        Part      = [int]$_.Part
                        CreatedAt = $null
                        PhysicalSizeBeforeBytes = [int64](Get-OPAArchivePstSizeBytes -Path ([string]$_.Path))
                        PhysicalSizeAfterBytes = [int64](Get-OPAArchivePstSizeBytes -Path ([string]$_.Path))
                        PhysicalGrowthBytes = [int64]0
                        LogicalAddedBytes = [int64]0
                        LastMeasuredAt = (Get-Date).ToString('o')
                        PhysicalSizeBaselineCaptured = $true
                    }
                })
                CurrentArchivePst = if ($archivePstRecoveredStates.Count -gt 0) { [string]$archivePstRecoveredStates[-1].Path } else { $null }
                LogicalFreedBytes = $logicalFreedRecovered
                SourcePstSizeBeforeBytes = $sourcePstSizeRecovered
                SourcePstSizeAfterBytes  = $sourcePstSizeRecovered
                FolderPath          = if($sourceFoldersRecovered.Count -eq 1){[string]$sourceFoldersRecovered[0].FolderPath}else{$null}
                Limit               = [int]$metadataRecovered.Limit
                ArchiveGrouping     = [string]$metadataRecovered.Grouping
                OlderThanMonths     = [int]$metadataRecovered.OlderThanMonths
                ArchiveCutoff       = if($metadataRecovered.ArchiveCutoff){$metadataRecovered.ArchiveCutoff.ToString('o')}else{$null}
                Planned             = $plannedRecovered.Count
                Executed            = $entriesRecovered.Count
                Verified            = 0
                Skipped             = 0
                SkippedItems        = @()
                PlannedItems        = $plannedRecovered
                Steps               = @()
            }

            foreach ($entry in $entriesRecovered) {
                $stateRecovered.Steps += [ordered]@{
                    Time             = (Get-Date).ToString('o')
                    Step             = 'Recovered Move'
                    Message          = 'Recovered from DuplicateIndex'
                    EntryId          = [string]$entry.SourceEntryId
                    ArchiveEntryId   = [string]$entry.ArchiveEntryId
                    ArchivePst       = [string]$entry.ArchivePst
                    TargetFolderPath = [string]$entry.TargetFolderPath
                    SourceFolderPath = [string]$entry.SourceFolderPath
                    ReceivedTime     = [string]$entry.ReceivedTime
                }
            }

            # BUGFIX (2.5.3): the reconstructed checkpoint must be persisted
            # BEFORE the reload below. The previous build reloaded straight
            # from disk, i.e. from the same corrupt file, and the recovery
            # path always failed at the reload step.
            $jsonRecovered = ConvertTo-Json -InputObject $stateRecovered -Depth 12
            Write-OPAAtomicTextFile -Path $txPath -Content $jsonRecovered

            $tx = [pscustomobject]@{
                TransactionId = $Transaction
                Path          = $txPath
                State         = $stateRecovered
            }

            Set-OPAArchiveTransactionCount `
                -Transaction $tx `
                -Planned ([int]$stateRecovered.Planned) `
                -Executed ([int]$stateRecovered.Executed) `
                -Verified 0

            # Reload the reconstructed checkpoint from disk. This makes the
            # remainder of Resume consume the same validated object shape as
            # a normal readable checkpoint.
            $tx = Get-OPAArchiveTransaction `
                -SourcePst $sourcePstForTx `
                -TransactionId $Transaction

            Save-OPAArchiveTransaction `
                -Transaction $tx `
                -Status 'Recovered' `
                -Step 'Recovered' `
                -Message ("Checkpoint rebuilt from DuplicateIndex: {0} recovered move(s); limit {1}" -f $entriesRecovered.Count, $metadataRecovered.Limit)


            Write-Host ''
            Write-Host '## Resume Recovery'
            Write-Host ("Checkpoint : unreadable/empty ({0})" -f $recoveryError)
            Write-Host ("Recovered  : {0} item(s) from DuplicateIndex" -f $entriesRecovered.Count)
            Write-Host ("Resume limit : {0}" -f $metadataRecovered.Limit)
            Write-Host ("Grouping    : {0}" -f $metadataRecovered.Grouping)
        }

        $status = [string]$tx.State.Status

        if ($status -eq 'Completed') {
            throw "Transaction '$($tx.TransactionId)' is already Completed and cannot be resumed."
        }

        Test-OPAArchiveTransactionSchema -TransactionState $tx.State | Out-Null

        # Honor the transaction's stored durability mode unless the operator
        # explicitly supplied -DurabilityMode for this Resume invocation.
        if (-not $script:OPADurabilityModeExplicit -and
            (Test-OPAStateHasKey -State $tx.State -Name 'DurabilityMode')) {
            $storedMode = [string]$tx.State.DurabilityMode
            if ($storedMode -in @('Fast','Safe') -and $storedMode -ne $global:OPADurabilityMode) {
                Write-Host ("Durability: switching to stored mode '{0}' for this transaction." -f $storedMode)
                $global:OPADurabilityMode = $storedMode
            }
        }

        $storedOlderThanMonths = 0
        if ($tx.State.PSObject.Properties.Name -contains 'OlderThanMonths' -and $null -ne $tx.State.OlderThanMonths) {
            $storedOlderThanMonths = [int]$tx.State.OlderThanMonths
        }
        $storedArchiveCutoff = $null
        if ($tx.State.PSObject.Properties.Name -contains 'ArchiveCutoff' -and $tx.State.ArchiveCutoff) {
            try { $storedArchiveCutoff = [datetime]$tx.State.ArchiveCutoff } catch { throw "Transaction '$($tx.TransactionId)' has an invalid ArchiveCutoff." }
        }
        if ($storedOlderThanMonths -gt 0 -and $null -eq $storedArchiveCutoff) {
            throw "Transaction '$($tx.TransactionId)' has OlderThanMonths=$storedOlderThanMonths but no ArchiveCutoff."
        }

        if ([int]$tx.State.Limit -le 0) {
            throw "Transaction '$($tx.TransactionId)' has no valid positive Limit and cannot be resumed safely."
        }

        if ([string]$tx.State.SourcePst -and [IO.Path]::GetFullPath([string]$tx.State.SourcePst) -ine [IO.Path]::GetFullPath($sourcePstForTx)) {
            throw 'Transaction source PST does not match its checkpoint.'
        }

        $planned = @($tx.State.PlannedItems)

        if ($planned.Count -eq 0) {
            throw "Transaction '$($tx.TransactionId)' contains no PlannedItems. Nothing can be resumed safely."
        }

        $index = Get-OPACombinedDuplicateIndexForTransaction -Transaction $tx
        $repairedSteps = Repair-OPAArchiveTransactionStepsFromDuplicateIndex `
            -Transaction $tx `
            -DuplicateIndex $index

        if ($repairedSteps -gt 0) {
            Write-Host ("Journal steps restored before Resume : {0}" -f $repairedSteps)
        }

        # Completion tracking must be restricted to this transaction's plan.
        # The inline Steps window can contain reconciled/stale entries whose
        # EntryIDs are not members of PlannedItems. Counting those IDs inflates
        # Completed items and makes Completed + Remaining exceed Planned.
        $plannedIdSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($p in @($planned)) {
            $plannedId = [string]$p.EntryId
            if (-not [string]::IsNullOrWhiteSpace($plannedId)) { [void]$plannedIdSet.Add($plannedId) }
        }

        $doneSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($step in @($tx.State.Steps)) {
            if ((Test-OPAMoveCompletionStep -Step $step) -and -not [string]::IsNullOrWhiteSpace([string]$step.EntryId)) {
                $stepId = [string]$step.EntryId
                if ($plannedIdSet.Contains($stepId)) { [void]$doneSet.Add($stepId) }
            }
        }

        $indexSourceIdSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in @($index.Entries)) {
            $sourceId = [string]$entry.SourceEntryId
            if ([string]$entry.TransactionId -eq [string]$tx.TransactionId -and
                -not [string]::IsNullOrWhiteSpace($sourceId) -and $plannedIdSet.Contains($sourceId)) {
                [void]$indexSourceIdSet.Add($sourceId)
            }
        }
        foreach ($p in @($planned)) {
            $plannedId = [string]$p.EntryId
            if ($indexSourceIdSet.Contains($plannedId)) { [void]$doneSet.Add($plannedId) }
        }

        $done = @($doneSet)
        $tx.State.Executed = $done.Count
        $remaining = @($planned | Where-Object { -not $doneSet.Contains([string]$_.EntryId) })

        if ($done.Count -gt $planned.Count) {
            throw "Resume safety invariant failed: completed items ($($done.Count)) exceed PlannedItems ($($planned.Count))."
        }

        Write-Host ''
        Write-Host '## Resume Workflow'
        Write-Host ("Transaction : {0}" -f $tx.TransactionId)
        Write-Host ("Planned     : {0}" -f $tx.State.Planned)
        Write-Host ("Executed    : {0}" -f $tx.State.Executed)
        Write-Host ("Completed items : {0}" -f $done.Count)
        Write-Host ("Remaining items : {0}" -f $remaining.Count)

        $archiveStores = @(Get-OPAArchiveStoresForTransaction -Namespace $session.Namespace -Transaction $tx)
        # Resume must use the original folder policy, not current CLI defaults.
        $resumeDeleted = if (Test-OPAStateHasKey -State $tx.State -Name 'ArchiveDeletedItems') { [bool]$tx.State.ArchiveDeletedItems } else { [bool]$ArchiveDeletedItems }
        $resumeDrafts  = if (Test-OPAStateHasKey -State $tx.State -Name 'ArchiveDrafts') { [bool]$tx.State.ArchiveDrafts } else { [bool]$ArchiveDrafts }
        $resumeJunk    = if (Test-OPAStateHasKey -State $tx.State -Name 'ArchiveJunk') { [bool]$tx.State.ArchiveJunk } else { [bool]$ArchiveJunk }
        $sourceFolders = @(Get-OPAPop3SourceFolders -StoreHandle $source.StoreHandle -ArchiveDeletedItems:$resumeDeleted -ArchiveDrafts:$resumeDrafts -ArchiveJunk:$resumeJunk)

        if ($tx.State.FolderPath -and @($sourceFolders | Where-Object { [string]$_.FolderPath -ieq [string]$tx.State.FolderPath }).Count -eq 0) {
            throw "Resume source folder is no longer available. Checkpoint=$($tx.State.FolderPath)"
        }

        # FIX9: restore cumulative logical bytes from the durable completed
        # plan before any further Move, including interrupted COM operations.
        $beforeResumeMoves = @(Get-OPAExpectedMovesFromTransaction -Transaction $tx -DuplicateIndex $index)
        $logicalBeforeResume = Get-OPACompletedLogicalBytes -Transaction $tx -CompletedMoves $beforeResumeMoves
        if ([int64]$tx.State.LogicalFreedBytes -ne $logicalBeforeResume) {
            Write-Host ("Logical accounting reconciled: {0:N2} -> {1:N2} MB" -f `
                ([double]$tx.State.LogicalFreedBytes/1MB),([double]$logicalBeforeResume/1MB))
            Set-OPAArchiveTransactionStorageStats -Transaction $tx -LogicalFreedBytes $logicalBeforeResume
        }
        $performance = Ensure-OPATransactionPerformance -TransactionState $tx.State
        Set-OPAPerformanceValue -Performance $performance -Name 'RecoveredMovesThisRun' -Value 0
        Set-OPAPerformanceValue -Performance $performance -Name 'NewMovesThisRun' -Value 0
        $movedNow = 0
        $executedBeforeResume = [int]$tx.State.Executed

        if ($remaining.Count -gt 0) {
            $movedNow = Move-OPAItemsWithLimit `
                -Namespace $session.Namespace `
                -SourceFolders $sourceFolders `
                -Transaction $tx `
                -Limit ([int]$tx.State.Limit) `
                -ArchiveGrouping ([string]$tx.State.ArchiveGrouping) `
                -OlderThanCutoff $(if($tx.State.ArchiveCutoff){[datetime]$tx.State.ArchiveCutoff}else{$null}) `
                -MaxArchivePstSizeGB $MaxArchivePstSizeGB `
                -SafetyMarginGB $SafetyMarginGB `
                -Resume
        }
        # Move-OPAItemsWithLimit returns cumulative Executed for compatibility.
        # Performance must record the delta, not the cumulative total.
        $movedNow = [Math]::Max(0, ([int]$movedNow - $executedBeforeResume))
        $performance = Ensure-OPATransactionPerformance -TransactionState $tx.State
        Set-OPAPerformanceValue -Performance $performance -Name 'ResumeMovedNow' -Value ([int]$movedNow)

        $archiveStores = @(Get-OPAArchiveStoresForTransaction -Namespace $session.Namespace -Transaction $tx)
        $postMoveIndex = Get-OPACombinedDuplicateIndexForTransaction -Transaction $tx
        $postMoveRepaired = Repair-OPAArchiveTransactionStepsFromDuplicateIndex `
            -Transaction $tx `
            -DuplicateIndex $postMoveIndex

        if ($postMoveRepaired -gt 0) {
            Write-Host ("Journal steps restored after Resume : {0}" -f $postMoveRepaired)
        }

        # Final Resume counts must be derived from the authoritative union of
        # transaction Move steps and DuplicateIndex entries for this transaction.
        # Heal the shared DuplicateIndex from the durable step journal before
        # verification. A transaction interrupted between a Move and the next
        # batched index flush has Move entries in the journal but no matching
        # records in DuplicateIndex; without this, Verify reports SOURCE:<id>
        # misses for items that were in fact moved.
        foreach ($healStore in @($archiveStores)) {
            $healPath = ''
            try { $healPath = [string]$healStore.FilePath } catch {}
            if ([string]::IsNullOrWhiteSpace($healPath)) { continue }
            if (-not (Test-Path -LiteralPath $healPath)) { continue }
            try {
                $healIndex = Import-OPADuplicateIndex -ArchivePst $healPath
                $healed = Sync-OPADuplicateIndexFromJournal -Transaction $tx -Index $healIndex -ArchivePst $healPath
                if ($healed -gt 0) {
                    Write-Host ("Healed DuplicateIndex from step journal before Verify: +{0} entr(ies)" -f $healed)
                }
            }
            catch {
                Write-Warning ("Unable to heal DuplicateIndex for '{0}': {1}" -f $healPath, $_.Exception.Message)
            }
        }
        # Reload from disk after heal so completion sees the appended
        # entries. Without this, $postMoveIndex is the snapshot loaded
        # before heal and is missing entries that Sync-...-FromJournal just
        # wrote to .jsonl. Test-OPAArchiveMoves loads the index fresh from
        # disk, so this keeps both steps of the same verification consistent.
        $postMoveIndex = Get-OPACombinedDuplicateIndexForTransaction -Transaction $tx
        $completion = Get-OPAResumeCompletionState `
            -Transaction $tx `
            -DuplicateIndex $postMoveIndex

        $expectedMoves = @(Get-OPAExpectedMovesFromTransaction -Transaction $tx -DuplicateIndex $postMoveIndex)
        $result = Test-OPAArchiveMoves `
            -Namespace $session.Namespace `
            -SourceFolder $sourceFolders `
            -ArchiveStores $archiveStores `
            -ExpectedMoved ([int]$completion.CompletedCount) `
            -ExpectedMoves $expectedMoves

        if ($completion.CompletedCount -ne $expectedMoves.Count) {
            throw "Resume completion journal is inconsistent: completed=$($completion.CompletedCount); destination pairs=$($expectedMoves.Count)."
        }
        $logicalFinal = Get-OPACompletedLogicalBytes -Transaction $tx -CompletedMoves $expectedMoves
        Set-OPAArchiveLogicalTelemetryFromMoves -Transaction $tx -CompletedMoves $expectedMoves
        Set-OPAArchiveTransactionStorageStats -Transaction $tx `
            -LogicalFreedBytes $logicalFinal `
            -SourcePstSizeAfterBytes ([int64](Get-Item -LiteralPath ([string]$tx.State.SourcePst)).Length)

        $finalExecuted = $completion.CompletedCount
        $finalVerified = if ($result.Verified) { $expectedMoves.Count } else { 0 }

        $tx.State.Executed = $finalExecuted
        $tx.State.Verified = $finalVerified

        Set-OPAArchiveTransactionCount `
            -Transaction $tx `
            -Planned ([int]$tx.State.Planned) `
            -Executed $finalExecuted `
            -Verified $finalVerified

        $resumePhaseComplete = ($result.Verified -and ([int]$tx.State.Executed -ge [int]$tx.State.Planned))
        $resumeStatus = if (-not $result.Verified) { 'VerificationFailed' } elseif ($resumePhaseComplete) { 'Completed' } else { 'Running' }
        # Credit verified Auto Resume BEFORE storing Completed, so a crash
        # cannot leave a Completed checkpoint with a missing storage ledger.
        $autoOrigin = (Test-OPAStateHasKey -State $tx.State -Name 'AutoStorageTracked') -and [bool]$tx.State.AutoStorageTracked
        if (($script:OPAAutoStorageTrackResume -or $autoOrigin) -and $resumeStatus -eq 'Completed') {
            $progress = Register-OPAAutoStorageProgress -Transaction $tx -ConfirmedVerifiedCompletion
            Write-Host ("Auto storage progress after Resume: {0:N2} MB logical credited." -f `
                ([double]$progress.CumulativeLogicalFreedBytes / 1MB))
        }
        Save-OPAArchiveTransaction `
            -Transaction $tx `
            -Status $resumeStatus `
            -Step $(if ($resumePhaseComplete) { 'ResumeVerify' } else { 'ResumeVerifyPartial' }) `
            -Message ("MovedNow={0}; Executed={1}; Planned={2}; Verified={3}; Missing={4}; PhaseComplete={5}" -f $movedNow, $tx.State.Executed, $tx.State.Planned, $result.Verified, $result.MissingEntryIds.Count, $resumePhaseComplete)

        Write-OPAArchiveReport -Result $result -Transaction $tx -PhaseStartedAt $resumeStartedAt
        if ($resumeStatus -eq 'Completed') {
            if ($script:OPAAutoResumedCheckpoint) { Clear-OPAAutoResumeAttempts -CheckpointPath $script:OPAAutoResumedCheckpoint }
        }
        elseif ($script:OPAAutoResumedCheckpoint) {
            # Do not treat an unsuccessful automatic Resume as success. The
            # retry marker stays until manual remediation or successful Resume.
            throw "Auto recovery incomplete: transaction '$($tx.TransactionId)' status=$resumeStatus. Automatic attempts are limited to $AutoMaxResumeAttempts."
        }
    }
}
catch {
    Write-Host ("ERROR: {0}" -f $_.Exception.Message)
    Write-Host ''
    Write-Host '--- ScriptStackTrace ---'
    Write-Host $_.ScriptStackTrace
    Write-Host '--- InvocationInfo ---'
    Write-Host ("  File : {0}" -f $_.InvocationInfo.ScriptName)
    Write-Host ("  Line : {0}" -f $_.InvocationInfo.ScriptLineNumber)
    try { Write-Host ("  Code : {0}" -f ($_.InvocationInfo.Line.Trim())) } catch {}
    Write-Host '--- InnerException ---'
    if ($_.Exception.InnerException) {
        Write-Host $_.Exception.InnerException.Message
        Write-Host $_.Exception.InnerException.StackTrace
    }
    exit 1
}
finally {
    if ($session) {
        Close-OPAComSession -Session $session
    }

    if ($autoMutex) {
        Close-OPAAutoRunMutex -Mutex $autoMutex
    }
}

exit 0
