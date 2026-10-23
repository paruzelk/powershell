#requires -Version 5.1
# 2.6.4-F: pure diagnostic audit, NOT a MailMove authorization mechanism.
# No COM, process launch, file writes, journal mutation or automatic replay.

function Assert-OPA264AuditRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Recovery,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$OperationId)
    if ($null -eq $Recovery -or $Recovery -is [string] -or
        [string]$Recovery.Schema -cne '2.6.4-D.1' -or
        [string]$Recovery.RunId -cne $RunId -or
        [string]$Recovery.OperationId -cne $OperationId) {
        throw 'Recovery audit schema or RunId/OperationId correlation mismatch.'
    }
    $allowed=@('SourceOnly','DestinationCandidate','BothPresent','Ambiguous',
        'MissingBoth','ScopeMismatch','IdentityConflict','IncompleteScan',
        'UntrustedJournal','InsufficientEvidence','AlreadyTerminal')
    if ([string]$Recovery.Status -cnotin $allowed -or
        $null -eq $Recovery.Artifacts) {
        throw 'Recovery audit status or artifacts are invalid.'
    }
    foreach ($field in @('ProvenMoved','AutomaticRetryAllowed','JournalWriteAllowed','MailMoveAllowed')) {
        if ($Recovery.PSObject.Properties.Name -cnotcontains $field -or
            $Recovery.$field -isnot [bool] -or [bool]$Recovery.$field) {
            throw "Recovery audit forbids positive or missing $field."
        }
    }
    if ($Recovery.PSObject.Properties.Name -cnotcontains 'RequiresManualReview' -or
        $Recovery.RequiresManualReview -isnot [bool] -or
        -not [bool]$Recovery.RequiresManualReview -or
        [string]$Recovery.Disposition -cne 'StopAndPreserveEvidence') {
        throw 'Recovery audit must require manual evidence review.'
    }
    foreach ($field in @('SourceScanComplete','DestinationScanComplete','JournalTrailingPartial')) {
        if ($Recovery.PSObject.Properties.Name -cnotcontains $field -or
            $Recovery.$field -isnot [bool]) {
            throw "Recovery audit boolean missing: $field."
        }
    }
    foreach ($field in @('SourceMatches','DestinationMatches','JournalLastSequence')) {
        if ($Recovery.PSObject.Properties.Name -cnotcontains $field -or
            [long]$Recovery.$field -lt 0) {
            throw "Recovery audit numeric evidence invalid: $field."
        }
    }
    if ([long]$Recovery.JournalLastSequence -lt 1 -or
        [long]$Recovery.SourceMatches -gt 1000000 -or
        [long]$Recovery.DestinationMatches -gt 1000000) {
        throw 'Recovery audit invalid journal sequence or unreasonable candidate count.'
    }
    foreach ($field in @('ControllerDispatchClaimPresent','WorkerMoveClaimPresent',
            'WorkerResponsePresent','ControllerResultPresent')) {
        if ($Recovery.Artifacts.PSObject.Properties.Name -cnotcontains $field -or
            $Recovery.Artifacts.$field -isnot [bool]) {
            throw "Recovery artifact missing boolean: $field."
        }
    }
    $barrier=[string]$Recovery.Artifacts.CrashBarrier
    if ($barrier -cnotin @('NotRecorded','AfterIntentBeforeDispatch','WorkerStartedBeforeMove',
        'AfterMoveBeforeResponse','AfterResponseBeforeTerminal')) {
        throw 'Recovery crash barrier name is unrecognized.'
    }
    if ($barrier -in @('AfterMoveBeforeResponse','AfterResponseBeforeTerminal') -and
        -not [bool]$Recovery.Artifacts.WorkerMoveClaimPresent) {
        throw 'Post-Move barrier requires durable one-shot Move claim.'
    }
    # An internally inconsistent self-reported recovery record is rejected
    # before it can be rendered as a machine-readable result.
    if (([string]$Recovery.Status -ceq 'SourceOnly' -and
            ([long]$Recovery.SourceMatches -ne 1 -or [long]$Recovery.DestinationMatches -ne 0)) -or
        ([string]$Recovery.Status -ceq 'DestinationCandidate' -and
            ([long]$Recovery.SourceMatches -ne 0 -or [long]$Recovery.DestinationMatches -ne 1)) -or
        ([string]$Recovery.Status -ceq 'BothPresent' -and
            ([long]$Recovery.SourceMatches -ne 1 -or [long]$Recovery.DestinationMatches -ne 1)) -or
        ([string]$Recovery.Status -ceq 'MissingBoth' -and
            ([long]$Recovery.SourceMatches -ne 0 -or [long]$Recovery.DestinationMatches -ne 0))) {
        throw 'Recovery status contradicts observed fingerprint match counts.'
    }
    return $true
}

function Assert-OPA264AuditIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Identity,
          [Parameter(Mandatory=$true)][string]$RunId)
    if ($null -eq $Identity -or $Identity -is [string] -or
        [string]$Identity.Schema -cne '2.6.4-E.1' -or
        [string]$Identity.RunId -cne $RunId -or
        [string]$Identity.Status -cnotin @('Stable','StoreIdChanged',
            'FolderIdentityChanged','MailEntryIdChanged','LocationChanged')) {
        throw 'Identity audit schema/RunId/status mismatch.'
    }
    foreach ($field in @('AutomaticRetryAllowed','MailMoveAllowed','JournalWriteAllowed',
            'AutomaticCompletionAllowed','ProvenMoved')) {
        if ($Identity.PSObject.Properties.Name -cnotcontains $field -or
            $Identity.$field -isnot [bool] -or [bool]$Identity.$field) {
            throw "Identity audit forbids positive or missing $field."
        }
    }
    if ($Identity.PSObject.Properties.Name -cnotcontains 'RequiresManualReview' -or
        $Identity.RequiresManualReview -isnot [bool] -or
        -not [bool]$Identity.RequiresManualReview -or
        [string]$Identity.Disposition -cne 'StopAndPreserveEvidence') {
        throw 'Identity audit must preserve evidence for manual review.'
    }
    foreach ($field in @('StoreIdChanged','FolderIdentityChanged',
            'MailEntryIdChanged','MessageLocationChanged')) {
        if ($Identity.PSObject.Properties.Name -cnotcontains $field -or
            $Identity.$field -isnot [bool]) {
            throw "Identity audit missing boolean: $field."
        }
    }
    if ([string]$Identity.Status -ceq 'Stable' -and
        ([bool]$Identity.StoreIdChanged -or [bool]$Identity.FolderIdentityChanged -or
            [bool]$Identity.MailEntryIdChanged -or [bool]$Identity.MessageLocationChanged)) {
        throw 'Stable identity verdict contradicts recorded identity changes.'
    }
    foreach ($field in @('SourceMatchesBefore','SourceMatchesAfter',
            'ArchiveMatchesBefore','ArchiveMatchesAfter')) {
        if ($Identity.PSObject.Properties.Name -cnotcontains $field -or
            [long]$Identity.$field -lt 0 -or [long]$Identity.$field -gt 1) {
            throw "Identity audit invalid candidate count: $field."
        }
    }
    return $true
}

function New-OPA264EvidenceAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Recovery,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$OperationId,
          [ValidateSet('None','AfterIntentBeforeDispatch','WorkerStartedBeforeMove',
              'AfterMoveBeforeResponse','AfterResponseBeforeTerminal')]
          [string]$ExpectedCrashWindow='None',
          [AllowNull()][object]$Identity=$null)
    [void](Assert-OPA264AuditRecovery -Recovery $Recovery -RunId $RunId -OperationId $OperationId)
    if ($null -ne $Identity) {
        [void](Assert-OPA264AuditIdentity -Identity $Identity -RunId $RunId)
    }
    $barrier=[string]$Recovery.Artifacts.CrashBarrier
    $scenario='NoCrashScenarioRequested'
    if ($ExpectedCrashWindow -cne 'None') {
        $scenario=if ($barrier -ceq $ExpectedCrashWindow) { 'BarrierRecorded' }
                  elseif ($barrier -ceq 'NotRecorded') { 'BarrierMissing' }
                  else { 'BarrierMismatch' }
    }
    elseif ($barrier -cne 'NotRecorded') {
        # A barrier is meaningful diagnostic evidence, even if the caller
        # did not specify an expected window. Never silently discard it.
        $scenario='UnexpectedBarrier'
    }
    $scanComplete=([bool]$Recovery.SourceScanComplete -and
        [bool]$Recovery.DestinationScanComplete -and
        -not [bool]$Recovery.JournalTrailingPartial)
    $classification='ReviewRequired'
    if (-not $scanComplete -or [string]$Recovery.Status -in @(
            'IncompleteScan','UntrustedJournal','InsufficientEvidence')) {
        $classification='IncompleteEvidence'
    }
    elseif ([string]$Recovery.Status -in @('ScopeMismatch','IdentityConflict',
            'Ambiguous','BothPresent','MissingBoth')) {
        $classification='ConflictingEvidence'
    }
    elseif ([string]$Recovery.Status -eq 'DestinationCandidate') {
        $classification='CandidateObserved'
    }
    if ($scenario -in @('BarrierMissing','BarrierMismatch','UnexpectedBarrier')) {
        $classification='EvidenceConflict'
    }
    if ($null -ne $Identity -and [string]$Identity.Status -cne 'Stable') {
        $classification='IdentityChanged'
    }
    # A synthetic matching candidate, a stable PST identity and a user-
    # supplied CI line do NOT prove production crash consistency.
    $identityStatus='NotCollected'
    if ($null -ne $Identity) { $identityStatus=[string]$Identity.Status }
    return [pscustomobject]@{
        Schema='2.6.4-F.1'
        RunId=$RunId
        OperationId=$OperationId
        ExpectedCrashWindow=$ExpectedCrashWindow
        ObservedCrashBarrier=$barrier
        ScenarioEvidence=$scenario
        RecoveryStatus=[string]$Recovery.Status
        SourceMatches=[int]$Recovery.SourceMatches
        DestinationMatches=[int]$Recovery.DestinationMatches
        ScansComplete=$scanComplete
        WorkerMoveClaimPresent=[bool]$Recovery.Artifacts.WorkerMoveClaimPresent
        WorkerResponsePresent=[bool]$Recovery.Artifacts.WorkerResponsePresent
        IdentityEvidence=$identityStatus
        Classification=$classification
        IndependentMoveProof=$false
        AutomaticRetryAllowed=$false
        AutomaticCompletionAllowed=$false
        JournalWriteAllowed=$false
        MailMoveAllowed=$false
        ProductionReady=$false
        ManualReviewRequired=$true
        TrustLevel='UnauthenticatedDiagnosticObservation'
        Disposition='StopAndPreserveEvidence'
    }
}

function Get-OPA264EvidenceCoverage {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Reports=@())
    $windows=@('AfterIntentBeforeDispatch','WorkerStartedBeforeMove',
        'AfterMoveBeforeResponse','AfterResponseBeforeTerminal')
    $seen=New-Object 'System.Collections.Generic.List[string]'
    $invalid=0
    foreach ($r in @($Reports)) {
        if ($null -eq $r -or [string]$r.Schema -cne '2.6.4-F.1' -or
            [bool]$r.ProductionReady -or [bool]$r.AutomaticRetryAllowed -or
            [bool]$r.AutomaticCompletionAllowed -or
            [string]$r.Disposition -cne 'StopAndPreserveEvidence' -or
            [string]$r.TrustLevel -cne 'UnauthenticatedDiagnosticObservation') {
            $invalid++
            continue
        }
        if ([string]$r.ExpectedCrashWindow -in $windows -and
            [string]$r.ScenarioEvidence -ceq 'BarrierRecorded' -and
            -not $seen.Contains([string]$r.ExpectedCrashWindow)) {
            [void]$seen.Add([string]$r.ExpectedCrashWindow)
        }
    }
    return [pscustomobject]@{
        Schema='2.6.4-F.Coverage.1'
        RequiredCrashWindows=$windows
        ObservedBarrierWindows=$seen.ToArray()
        MissingCrashWindows=@($windows | Where-Object { -not $seen.Contains($_) })
        InvalidReports=$invalid
        CheckedReports=@($Reports).Count
        AutomatedCoverageIsNotCrashSafetyProof=$true
        ProductionReady=$false
        Readiness='BlockedPendingRealOutlookTestsAndManualReview'
    }
}
