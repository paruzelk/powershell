#requires -Version 5.1
# BW3: DEV synthetic-only one-shot controller contract and durable fences.
# No Outlook COM in this module. No production Archive/Resume/Auto integration.
function Get-OPA265BW3Paths {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$FixturePaths)
    return [pscustomobject]@{
        DispatchClaimPath=(Join-Path ([string]$FixturePaths.Directory) 'bw3-dispatch.claim')
        ControllerResultPath=(Join-Path ([string]$FixturePaths.Directory) 'bw3-controller-result.json')
    }
}
function Get-OPA265BW3Preflight {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [string]$ExpectedJournalSha256='',
          [switch]$ForDispatchedWorker)
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $request=Read-OPAWorkerJson -Path $paths.RequestPath
    if ([string]$request.RunId -cne [string]$paths.RunId -or
        [string]$request.SourcePst -cne [string]$paths.SourcePst) {
        throw 'BW3 durable request differs from explicitly selected fixture.'
    }
    $paths=Assert-OPA264Live3Request -Request $request -BeforeMove
    $intent=Assert-OPA264Live3Intent -Request $request -Paths $paths
    $journal=Read-OPAOperationJournal -Path $paths.JournalPath
    if ([bool]$journal.TrailingPartial -or @($journal.Events).Count -ne 1 -or
        [string]$journal.Events[0].Phase -cne 'Intent') {
        throw 'BW3 requires exactly one complete durable Intent.'
    }
    $sha=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($ExpectedJournalSha256) -and
        $sha -cne $ExpectedJournalSha256) {
        throw 'BW3 durable Intent SHA256 differs from operator-pinned journal.'
    }
    if ($sha -cnotmatch '^[a-f0-9]{64}$' -or
        [long]$intent.Size -le 0) {
        throw 'BW3 Intent SHA256/Size invalid for an executable synthetic Move.'
    }
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $legacyController=Join-Path $paths.Directory 'controller-dispatch.claim'
    $live6=Join-Path $paths.Directory 'live6-resolution.claim'
    $blocked=@($paths.ClaimPath,$paths.ResponsePath,
        $extra.ControllerResultPath,$legacyController,$live6,
        (Join-Path $paths.Directory 'crash-barrier.json'))
    if (-not $ForDispatchedWorker) {$blocked+= $extra.DispatchClaimPath}
    foreach ($p in $blocked) {
        if ([IO.File]::Exists([string]$p)) {
            throw 'BW3 RunId has an attempt, dispatch, crash, resolution or response artifact: NEVER retry or reuse.'
        }
    }
    return [pscustomobject]@{
        Schema='2.6.5-BW3.Preflight.1'
        RunId=[string]$paths.RunId
        OperationId=[string]$request.OperationId
        SourcePst=[string]$paths.SourcePst
        ArchivePst=[string]$paths.ArchivePst
        JournalSha256=$sha
        IntentSizeBytes=[long]$intent.Size
        Paths=$paths
        Request=$request
        Intent=$intent
        Extra=$extra
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW3DispatchClaim {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Claim,
          [Parameter(Mandatory=$true)][object]$Preflight,
          [Parameter(Mandatory=$true)][string]$RequestId)
    $id=[guid]::Empty
    if (-not [guid]::TryParse($RequestId,[ref]$id) -or $id -eq [guid]::Empty -or
        [string]$Claim.Schema -cne '2.6.5-BW3.DispatchClaim.1' -or
        [string]$Claim.RunId -cne [string]$Preflight.RunId -or
        [string]$Claim.OperationId -cne [string]$Preflight.OperationId -or
        [string]$Claim.WorkerRequestId -cne $RequestId -or
        [string]$Claim.JournalSha256 -cne [string]$Preflight.JournalSha256 -or
        [string]$Claim.SourcePst -cne [string]$Preflight.SourcePst -or
        [bool]$Claim.AutomaticRetryAllowed -or
        [bool]$Claim.ProductionReady -or
        [bool]$Claim.JournalCompleted -or
        [bool]$Claim.PstReconciliationComplete) {
        throw 'BW3 durable dispatch claim correlation failed.'
    }
    return $true
}
function Write-OPA265BW3DurableDispatchClaim {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Preflight,
          [Parameter(Mandatory=$true)][string]$RequestId)
    $claim=[pscustomobject]@{
        Schema='2.6.5-BW3.DispatchClaim.1'
        RunId=[string]$Preflight.RunId
        OperationId=[string]$Preflight.OperationId
        WorkerRequestId=$RequestId
        JournalSha256=[string]$Preflight.JournalSha256
        SourcePst=[string]$Preflight.SourcePst
        Utc=[datetime]::UtcNow.ToString('o')
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        JournalCompleted=$false
        PstReconciliationComplete=$false
    }
    [void](Assert-OPA265BW3DispatchClaim -Claim $claim -Preflight $Preflight -RequestId $RequestId)
    # Filename creation is irreversible for this operation. If write/flush
    # fails, evidence must be preserved; never recover by deleting it.
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes(
        (ConvertTo-Json -InputObject $claim -Depth 5))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new([string]$Preflight.Extra.DispatchClaimPath,
            [IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {
        if ($null -ne $stream) {$stream.Dispose()}
    }
    return $claim
}
function Assert-OPA265BW3Payload {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Payload)
    $fields=@($Payload.PSObject.Properties.Name)
    if ($fields.Count -ne 7 -or
        [string]$Payload.Schema -cne '2.6.5-BW3.SyntheticOneShot.1' -or
        [string]$Payload.ExecutionPurpose -cne 'OperatorApprovedSingleSyntheticMove' -or
        [string]$Payload.JournalSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'BW3 payload schema/length/identity invalid.'
    }
    foreach($field in @('Schema','ExecutionPurpose','RunId','SourcePst',
        'OperationId','JournalSha256','WorkerRequestId')) {
        if ($fields -cnotcontains $field) {throw ('BW3 payload missing '+$field)}
    }
    foreach($field in @('RunId','OperationId','WorkerRequestId')) {
        $id=[guid]::Empty
        if (-not [guid]::TryParse([string]$Payload.$field,[ref]$id) -or
            $id -eq [guid]::Empty -or
            $id.ToString('D') -cne [string]$Payload.$field) {
            throw ('BW3 payload requires exact nonempty GUID: '+$field)
        }
    }
    return $true
}
function Assert-OPA265BW3Outcome {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Outcome,
          [Parameter(Mandatory=$true)][object]$Preflight,
          [Parameter(Mandatory=$true)][string]$RequestId)
    if ([string]$Outcome.Status -cne 'Succeeded' -or
        [string]$Outcome.Operation -cne 'BW3SyntheticOneShotMove' -or
        [string]$Outcome.RequestId -cne $RequestId -or
        [string]$Outcome.FailureKind -cne 'None' -or
        [int]$Outcome.WorkerProcessId -le 0 -or
        [bool]$Outcome.RequiresReconciliation -or
        $null -eq $Outcome.Response -or
        [string]$Outcome.Response.Operation -cne 'BW3SyntheticOneShotMove' -or
        [string]$Outcome.Response.Status -cne 'Succeeded' -or
        [string]$Outcome.Response.RequestId -cne $RequestId -or
        [int]$Outcome.Response.WorkerProcessId -ne [int]$Outcome.WorkerProcessId -or
        [string]$Outcome.Response.ApartmentState -cne 'STA' -or
        $null -eq $Outcome.Response.Result) {
        throw 'BW3 Worker outcome missing/failed/indeterminate: preserve evidence, NO AUTO RETRY.'
    }
    $r=$Outcome.Response.Result
    if ([string]$r.Schema -cne '2.6.5-BW3.MoveReturned.1' -or
        [string]$r.RunId -cne [string]$Preflight.RunId -or
        [string]$r.OperationId -cne [string]$Preflight.OperationId -or
        [string]$r.JournalSha256 -cne [string]$Preflight.JournalSha256 -or
        -not [bool]$r.MoveReturned -or
        [int]$r.MovesAttempted -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$r.DestinationEntryId) -or
        [bool]$r.JournalCompleted -or
        [bool]$r.AutomaticRetryAllowed -or
        -not [bool]$r.RequiresIndependentReconciliation -or
        [bool]$r.ProductionReady) {
        throw 'BW3 Worker returned an untrusted/mismatched Move result; NO AUTO RETRY.'
    }
    return $true
}
