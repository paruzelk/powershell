#requires -Version 5.1
# 2.6.5 DEV canary. No COM and no journal/PST writes.
# Archive/Resume mail Move routing is NOT activated. Only bounded Ping is allowed.
function Assert-OPA265WorkerPilotGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Archive','Resume','Auto','Analyze','Plan')][string]$Mode,
        [bool]$PilotRequested=$false,
        [bool]$ExplicitConsent=$false,
        [bool]$WhatIfEnabled=$false,
        [int]$Limit=0,
        [string]$ProfileName='',
        [string]$Transaction='',
        [int]$MaxOperations=1,
        [int]$TimeoutSeconds=10,
        [bool]$OtherPilotOptionsSpecified=$false
    )
    if (-not $PilotRequested) {
        if ($ExplicitConsent -or $OtherPilotOptionsSpecified) {
            throw '2.6.5: pilot-only options without -WorkerPilot are forbidden; do not fall through to FIX13b.'
        }
        return [pscustomobject]@{
            Schema='2.6.5.BoundedWorkerRoute.1'
            Route='FIX13b'
            WorkerOperation='None'
            RealMailMoveViaWorker=$false
            ProductionReady=$false
        }
    }
    if ($Mode -cnotin @('Archive','Resume')) {
        throw '2.6.5: WorkerPilot is permitted only with explicit Archive or Resume mode; Auto is blocked.'
    }
    if (-not $ExplicitConsent -or -not $WhatIfEnabled) {
        throw '2.6.5: WorkerPilot requires BOTH -ConfirmDevWorkerPilot and -WhatIf.'
    }
    if ($Limit -ne 1 -or $MaxOperations -ne 1) {
        throw '2.6.5: WorkerPilot is bounded to precisely one read-only operation and -Limit 1.'
    }
    if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 30) {
        throw '2.6.5: WorkerPilot timeout must be 1..30 seconds.'
    }
    if ($ProfileName -cne 'Outlook') {
        throw '2.6.5: WorkerPilot requires explicitly approved TEST profile name Outlook.'
    }
    if ($Mode -ceq 'Resume') {
        $guid=[guid]::Empty
        if (-not [guid]::TryParse($Transaction,[ref]$guid) -or $guid -eq [guid]::Empty) {
            throw '2.6.5: Resume WorkerPilot requires an explicit nonzero GUID -Transaction; it will not execute Resume.'
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($Transaction)) {
        throw '2.6.5: Archive WorkerPilot cannot take -Transaction.'
    }
    return [pscustomobject]@{
        Schema='2.6.5.BoundedWorkerRoute.1'
        Route='ReadOnlyCanary'
        WorkerOperation='Ping'
        Mode=$Mode
        MaxOperations=1
        TimeoutSeconds=$TimeoutSeconds
        ProfileName=$ProfileName
        Transaction=$Transaction
        AutomaticRetryAllowed=$false
        DurableIntentRequired=$false
        RealMailMoveViaWorker=$false
        ProductionReady=$false
    }
}

function Assert-OPA265WorkerPilotOutcome {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Outcome)
    if ([string]$Outcome.Status -cne 'Succeeded' -or
        [string]$Outcome.Operation -cne 'Ping' -or
        [string]$Outcome.FailureKind -cne 'None' -or
        [int]$Outcome.WorkerProcessId -le 0 -or
        [bool]$Outcome.RequiresReconciliation -or
        [string]::IsNullOrWhiteSpace([string]$Outcome.RequestId) -or
        $null -eq $Outcome.Response -or
        [string]$Outcome.Response.Status -cne 'Succeeded' -or
        [string]$Outcome.Response.Operation -cne 'Ping' -or
        [string]$Outcome.Response.RequestId -cne [string]$Outcome.RequestId -or
        [int]$Outcome.Response.WorkerProcessId -ne [int]$Outcome.WorkerProcessId -or
        [string]$Outcome.Response.ApartmentState -cne 'STA' -or
        -not [bool]$Outcome.Response.Result.Alive) {
        throw '2.6.5: canary Worker outcome not independently validated; fail closed; no automatic retry.'
    }
    $id=[guid]::Empty
    if (-not [guid]::TryParse([string]$Outcome.RequestId,[ref]$id) -or $id -eq [guid]::Empty) {
        throw '2.6.5: canary response RequestId is not a valid nonempty GUID.'
    }
    return $true
}

function Invoke-OPA265BoundedWorkerCanary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Gate, [switch]$KeepArtifacts)
    if ([string]$Gate.Schema -cne '2.6.5.BoundedWorkerRoute.1' -or
        [string]$Gate.Route -cne 'ReadOnlyCanary' -or
        [string]$Gate.WorkerOperation -cne 'Ping' -or
        [int]$Gate.MaxOperations -ne 1 -or
        [int]$Gate.TimeoutSeconds -lt 1 -or
        [int]$Gate.TimeoutSeconds -gt 30 -or
        [bool]$Gate.AutomaticRetryAllowed -or
        [bool]$Gate.RealMailMoveViaWorker -or
        [bool]$Gate.ProductionReady) {
        throw '2.6.5: canary rejected an unsafe or non-pilot route; no Worker started.'
    }
    # Exactly ONE operation; no loops, no fallback to MailMover/Archive/Resume.
    $payload=[pscustomobject]@{Schema='2.6.5.ReadOnlyCanary.1';Mode=[string]$Gate.Mode;MaxOperations=1}
    $outcome=Invoke-OPAWorkerControlledOperation -Operation 'Ping' -Payload $payload -TimeoutSeconds ([int]$Gate.TimeoutSeconds) -KeepArtifacts:$KeepArtifacts
    [void](Assert-OPA265WorkerPilotOutcome -Outcome $outcome)
    return [pscustomobject]@{
        Schema='2.6.5.BoundedWorkerCanaryResult.1'
        Status='ReadOnlyCanaryPassed'
        Mode=[string]$Gate.Mode
        Route='ReadOnlyCanary'
        WorkerOperation='Ping'
        OperationsExecuted=1
        WorkerProcessId=[int]$outcome.WorkerProcessId
        RequestId=[string]$outcome.RequestId
        WorkerApartmentState=[string]$outcome.Response.ApartmentState
        ArtifactDirectory=[string]$outcome.ArtifactDirectory
        OutlookComAccessExecuted=$false
        OutlookMoveExecuted=$false
        ArchiveTransactionCreated=$false
        JournalChanged=$false
        RealMailMoveViaWorker=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='StopBeforeArchiveOrResume'
    }
}
