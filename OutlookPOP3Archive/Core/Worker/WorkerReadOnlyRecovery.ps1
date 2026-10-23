#requires -Version 5.1
# 2.6.4-D diagnostic-only, read-only recovery; no PST mounts, mail mutation,
# process management, journal writes or automatic retries.
. (Join-Path $PSScriptRoot 'WorkerTestMove.ps1')
. (Join-Path $PSScriptRoot 'WorkerCrashInjection.ps1')
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Archive/MoveReconciliation.ps1')

function Assert-OPA264RecoveryFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][string]$RunId)
    $paths=Get-OPA264TestPaths -RunId $RunId
    if ($null -eq $Request -or $Request -is [string] -or
        [string]$Request.RunId -cne $paths.RunId) {
        throw 'Recovery RunId or request object mismatch.'
    }
    foreach ($field in @('OperationId','SourcePst','ArchivePst','JournalPath',
        'SourceStoreId','ArchiveStoreId','SourceFolderEntryId',
        'ArchiveFolderEntryId','SourceFolderPath','ArchiveFolderPath','SourceEntryId')) {
        if ($Request.PSObject.Properties.Name -cnotcontains $field -or
            [string]::IsNullOrWhiteSpace([string]$Request.$field)) {
            throw "Recovery request missing $field."
        }
    }
    $operation=[guid]::Empty
    if (-not [guid]::TryParse([string]$Request.OperationId,[ref]$operation) -or
        $operation -eq [guid]::Empty) {
        throw 'Recovery OperationId must be a nonempty GUID.'
    }
    if ([string]$Request.SourceStoreId -ceq [string]$Request.ArchiveStoreId -or
        [string]$Request.SourceFolderEntryId -ceq [string]$Request.ArchiveFolderEntryId) {
        throw 'Recovery requires two distinct disposable stores and folders.'
    }
    foreach ($field in @('SourcePst','ArchivePst','JournalPath')) {
        if (-not [string]::Equals([string]$Request.$field,[string]$paths.$field,
            [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Recovery request path escapes disposable fixture.'
        }
    }
    foreach ($p in @($paths.Directory,$paths.SourcePst,$paths.ArchivePst,
            $paths.JournalPath,$paths.MarkerPath,$paths.RequestPath)) {
        [void](Assert-OPA264TestPath -Actual $p -Expected $p -Label 'recovery evidence')
    }
    $marker=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($paths.MarkerPath)) -ErrorAction Stop
    if ([string]$marker.Purpose -cne 'OPA264-Disposable-Pst-Pair' -or
        [string]$marker.RunId -cne $paths.RunId -or
        [string]$marker.SourcePst -cne $paths.SourcePst -or
        [string]$marker.ArchivePst -cne $paths.ArchivePst) {
        throw 'Recovery disposable scope marker mismatch.'
    }
    # Pre-dispatch guard cannot be reused here: existing one-shot Move claims
    # are precisely the evidence we must preserve and review.
    [void](Assert-OPA264TestMoveIntent -Request $Request -Paths $paths)
    return $paths
}

function Get-OPA264RecoveryArtifactEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$Paths)
    $controllerClaim=Join-Path $Paths.Directory 'controller-dispatch.claim'
    $workerClaim=$Paths.ClaimPath
    foreach ($path in @($controllerClaim,$workerClaim)) {
        if ([IO.File]::Exists($path)) {
            [void](Assert-OPA264TestPath -Actual $path -Expected $path -Label 'one-shot claim')
            if ([string]([IO.File]::ReadAllText($path)).Trim() -cne [string]$Request.OperationId) {
                throw 'Recovery one-shot claim OperationId mismatch.'
            }
        }
    }
    $barrierPath=Get-OPA264CrashBarrierPath -RunId ([string]$Request.RunId)
    $barrierName='NotRecorded'
    if ([IO.File]::Exists($barrierPath)) {
        [void](Assert-OPA264TestPath -Actual $barrierPath -Expected $barrierPath -Label 'crash barrier')
        $barrier=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($barrierPath)) -ErrorAction Stop
        if ([int]$barrier.ProcessId -le 0) { throw 'Recovery crash barrier PID invalid.' }
        [void](Assert-OPA264CrashBarrier -Record $barrier -Request $Request -ExpectedWindow ([string]$barrier.CrashWindow) -ExpectedProcessId ([int]$barrier.ProcessId))
        if ([string]$barrier.CrashWindow -in @('AfterMoveBeforeResponse','AfterResponseBeforeTerminal') -and
            -not [IO.File]::Exists($workerClaim)) {
            throw 'Post-Move barrier lacks the original durable one-shot Move claim.'
        }
        # Reconstructed PID correlation is not proof of process ownership.
        $barrierName=[string]$barrier.CrashWindow
    }
    $responseExists=[IO.File]::Exists($Paths.ResponsePath)
    if ($responseExists) {
        [void](Assert-OPA264TestPath -Actual $Paths.ResponsePath -Expected $Paths.ResponsePath -Label 'Worker response')
        $response=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Paths.ResponsePath)) -ErrorAction Stop
        if ([string]$response.RunId -cne [string]$Request.RunId -or
            [string]$response.OperationId -cne [string]$Request.OperationId -or
            [bool]$response.AutomaticRetryAllowed -or [bool]$response.JournalCompleted -or
            -not [bool]$response.RequiresIndependentReconciliation) {
            throw 'Recovery Worker response identity/safety mismatch.'
        }
    }
    $controllerPath=Join-Path $Paths.Directory 'controller-result.json'
    $controllerExists=[IO.File]::Exists($controllerPath)
    if ($controllerExists) {
        [void](Assert-OPA264TestPath -Actual $controllerPath -Expected $controllerPath -Label 'controller result')
        $controller=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($controllerPath)) -ErrorAction Stop
        if ([string]$controller.RunId -cne [string]$Request.RunId -or
            [string]$controller.OperationId -cne [string]$Request.OperationId -or
            [bool]$controller.AutomaticRetryAllowed -or [bool]$controller.JournalCompleted -or
            -not [bool]$controller.RequiresIndependentReconciliation) {
            throw 'Recovery controller result identity/safety mismatch.'
        }
    }
    return [pscustomobject]@{
        ControllerDispatchClaimPresent=[IO.File]::Exists($controllerClaim)
        WorkerMoveClaimPresent=[IO.File]::Exists($workerClaim)
        CrashBarrier=$barrierName
        WorkerResponsePresent=$responseExists
        ControllerResultPresent=$controllerExists
    }
}

function Resolve-OPA264ReadOnlyRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request,
          [Parameter(Mandatory=$true)][object]$SourceSnapshot,
          [Parameter(Mandatory=$true)][object]$DestinationSnapshot)
    $paths=Assert-OPA264RecoveryFixture -Request $Request -RunId ([string]$Request.RunId)
    $artifacts=Get-OPA264RecoveryArtifactEvidence -Request $Request -Paths $paths
    if ([string]$SourceSnapshot.Role -cne 'Source' -or
        [string]$DestinationSnapshot.Role -cne 'Destination' -or
        [string]$SourceSnapshot.StoreIdentity -cne [string]$Request.SourceStoreId -or
        [string]$DestinationSnapshot.StoreIdentity -cne [string]$Request.ArchiveStoreId -or
        [string]$SourceSnapshot.FolderPath -cne [string]$Request.SourceFolderPath -or
        [string]$DestinationSnapshot.FolderPath -cne [string]$Request.ArchiveFolderPath -or
        -not [string]::Equals([string]$DestinationSnapshot.ArchivePst,
            [string]$paths.ArchivePst,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Recovery snapshot StoreID, folder or PST scope mismatch.'
    }
    $journal=Read-OPAOperationJournal -Path $paths.JournalPath
    $review=Resolve-OPAInterruptedMoveEvidence -Journal $journal -OperationId ([string]$Request.OperationId) -SourceSnapshot $SourceSnapshot -DestinationSnapshot $DestinationSnapshot
    return [pscustomobject]@{
        Schema='2.6.4-D.1'
        RunId=$paths.RunId
        OperationId=[string]$Request.OperationId
        Status=[string]$review.Status
        SourceMatches=[int]$review.SourceMatches
        DestinationMatches=[int]$review.DestinationMatches
        SourceScanComplete=[bool]$SourceSnapshot.ScanComplete
        DestinationScanComplete=[bool]$DestinationSnapshot.ScanComplete
        JournalTrailingPartial=[bool]$review.JournalTrailingPartial
        JournalLastSequence=[long]$review.JournalLastSequence
        Artifacts=$artifacts
        ProvenMoved=$false
        AutomaticRetryAllowed=$false
        JournalWriteAllowed=$false
        MailMoveAllowed=$false
        RequiresManualReview=$true
        Disposition='StopAndPreserveEvidence'
    }
}
