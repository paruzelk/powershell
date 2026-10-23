#requires -Version 5.1
# 2.6.4-A: pure, non-mutating diagnostic crash-window policy.
# No Worker launch/termination, Outlook COM, PST or journal I/O.
# NOT imported by production Archive, Resume or Auto.

function Get-OPACrashWindowMatrix {
    [CmdletBinding()]
    param()

    # MayHaveMoved is a possibility, not proof of any MailItem.Move side effect.
    # DeterministicBarrier describes a potential future test-only hook.
    $windows = @(
        @('BeforeIntentFlush',             'Controller', $true,  $false, $false, $false, 'RefuseDispatch'),
        @('AfterIntentBeforeDispatch',      'Controller', $true,  $true,  $false, $false, 'ReviewIntent'),
        @('WorkerStartedBeforeMove',        'Worker',     $true,  $true,  $true,  $false, 'ReviewWorkerEvidence'),
        @('DuringMove',                     'Worker',     $false, $true,  $true,  $true,  'ReadOnlyReconciliation'),
        @('AfterMoveBeforeResponse',        'Worker',     $true,  $true,  $true,  $true,  'ReadOnlyReconciliation'),
        @('AfterResponseBeforeTerminal',    'Controller', $true,  $true,  $true,  $true,  'ReadOnlyReconciliation'),
        @('WorkerTimeoutOrMissingResponse', 'Controller', $false, $true,  $true,  $true,  'ReadOnlyReconciliation'),
        @('OutlookUnavailable',             'Worker',     $false, $true,  $true,  $true,  'ReadOnlyReconciliation')
    )

    foreach ($row in $windows) {
        [pscustomobject]@{
            Name = [string]$row[0]
            InjectionOwner = [string]$row[1]
            DeterministicBarrier = [bool]$row[2]
            DurableIntentExpected = [bool]$row[3]
            WorkerMayHaveStarted = [bool]$row[4]
            ComMoveMayHaveExecuted = [bool]$row[5]
            RecoveryPolicy = [string]$row[6]
            RequiredDataScope = 'RunUniqueDisposablePstPair'
            TerminationTarget = 'OwnedChildWorkerProcessOnly'
            FaultInjectionEnabled = $false
            MailMoveEnabled = $false
            AutomaticRetryAllowed = $false
            AutomaticCompletionAllowed = $false
            RequiresManualReview = $true
        }
    }
}

function Get-OPACrashWindowDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name)

    $matches = @(Get-OPACrashWindowMatrix | Where-Object { $_.Name -ceq $Name })
    if ($matches.Count -ne 1) { throw "Unknown 2.6.4 crash window: '$Name'." }
    return $matches[0]
}

function New-OPACrashTestPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CrashWindow,
        [string]$RunId = ''
    )

    $definition = Get-OPACrashWindowDefinition -Name $CrashWindow
    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = [guid]::NewGuid().ToString('D') }
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($RunId,[ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw 'Crash test RunId must be a non-empty GUID.'
    }

    return [pscustomobject]@{
        ProtocolVersion = '2.6.4-A.1'
        RunId = $parsed.ToString('D')
        CrashWindow = $definition.Name
        InjectionOwner = $definition.InjectionOwner
        DeterministicBarrier = $definition.DeterministicBarrier
        IntentExpected = $definition.DurableIntentExpected
        ComMoveMayHaveExecuted = $definition.ComMoveMayHaveExecuted
        RecoveryPolicy = $definition.RecoveryPolicy
        RequiredDataScope = $definition.RequiredDataScope
        TerminationTarget = $definition.TerminationTarget
        RequiresExplicitTestApproval = $true
        # Stage A only: no executable actions, no overridable enable flags.
        FaultInjectionEnabled = $false
        OutlookComEnabled = $false
        WorkerLaunchEnabled = $false
        WorkerTerminationEnabled = $false
        MailMoveEnabled = $false
        AutomaticRetryAllowed = $false
        AutomaticCompletionAllowed = $false
        RequiresManualReview = $true
    }
}

function Assert-OPACrashTimeline {
    [CmdletBinding()]
    param(
        [switch]$IntentFlushed,
        [switch]$WorkerStarted,
        [switch]$MoveStarted,
        [switch]$MoveReturned,
        [switch]$ResponseValidated,
        [switch]$TerminalFlushed
    )

    if ($WorkerStarted -and -not $IntentFlushed) {
        throw 'Invalid crash timeline: Worker started before durable Intent.'
    }
    if ($MoveStarted -and -not $WorkerStarted) {
        throw 'Invalid crash timeline: MailMove started without owned Worker.'
    }
    if ($MoveReturned -and -not $MoveStarted) {
        throw 'Invalid crash timeline: COM Move returned without Move started.'
    }
    if ($ResponseValidated -and -not $WorkerStarted) {
        throw 'Invalid crash timeline: response without Worker start.'
    }
    if ($TerminalFlushed -and -not $IntentFlushed) {
        throw 'Invalid crash timeline: terminal journal event without durable Intent.'
    }
    return $true
}

function Get-OPACrashReplayDirective {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CrashWindow,
        [Parameter(Mandatory=$true)]
        [ValidateSet('Trusted','Missing','Truncated','Corrupt')][string]$JournalTrust,
        [ValidateSet('NotScanned','SourceOnly','DestinationCandidate','BothPresent',
            'MissingBoth','Ambiguous','ScopeMismatch','IdentityConflict',
            'IncompleteScan','UntrustedJournal','InsufficientEvidence',
            'AlreadyTerminal')][string]$MailEvidence = 'NotScanned'
    )

    $definition = Get-OPACrashWindowDefinition -Name $CrashWindow
    $classification = 'NeedsManualReview'
    $needsScan = $false

    if ($JournalTrust -ne 'Trusted') {
        $classification = 'UntrustedOrAbsentJournal'
    }
    elseif (-not $definition.DurableIntentExpected) {
        $classification = 'NoDurableIntent'
    }
    elseif ($MailEvidence -eq 'NotScanned') {
        $classification = 'NeedsIndependentSnapshot'
        $needsScan = $true
    }
    elseif ($MailEvidence -in @('ScopeMismatch','IdentityConflict',
        'IncompleteScan','UntrustedJournal','InsufficientEvidence')) {
        $classification = 'EvidenceConflict'
    }
    elseif ($MailEvidence -eq 'AlreadyTerminal') {
        # A terminal event label is not independent MailMove proof.
        $classification = 'TerminalNeedsAudit'
    }
    else {
        $classification = 'ReviewObservedEvidence'
    }

    return [pscustomobject]@{
        CrashWindow = $definition.Name
        JournalTrust = $JournalTrust
        MailEvidence = $MailEvidence
        Classification = $classification
        ReadOnlyScanRequired = $needsScan
        ComMoveMayHaveExecuted = $definition.ComMoveMayHaveExecuted
        AutomaticRetryAllowed = $false
        AutomaticCompletionAllowed = $false
        JournalWriteAllowed = $false
        MailMoveAllowed = $false
        WorkerTerminationAllowed = $false
        RequiresManualReview = $true
        Disposition = 'StopAndPreserveEvidence'
    }
}
