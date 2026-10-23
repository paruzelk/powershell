#requires -Version 5.1
# 2.6.4-B2: pure contract for a NEW, disposable, user-approved PST pair.
# No Outlook COM, PST mounting, mail mutation, subprocess or journal writes.
. (Join-Path $PSScriptRoot 'WorkerTestMove.ps1')

function New-OPA264FixturePlan {
    [CmdletBinding()]
    param([string]$RunId = '')

    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = [guid]::NewGuid().ToString('D') }
    $paths = Get-OPA264TestPaths -RunId $RunId
    return [pscustomobject]@{
        RunId = $paths.RunId
        OperationId = [guid]::NewGuid().ToString('D')
        Paths = $paths
        ScopeMarkerPurpose = 'OPA264-Disposable-Pst-Pair'
        SourceFolderName = 'OPA264-TestSource'
        ArchiveFolderName = 'OPA264-TestArchive'
        RequiresExplicitApproval = $true
        AllowsProductionPst = $false
        AllowsExistingPst = $false
        AllowsWorkerAutoRetry = $false
        AllowsWorkerAutoDispatch = $false
        MustPreserveTestEvidence = $true
    }
}

function Assert-OPA264FreshFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Plan)
    if ($null -eq $Plan -or $null -eq $Plan.Paths -or
        [string]$Plan.RunId -cne [string]$Plan.Paths.RunId) {
        throw 'Fixture plan and RunId mismatch.'
    }
    $derived = Get-OPA264TestPaths -RunId ([string]$Plan.RunId)
    if (-not [string]::Equals([string]$derived.Directory, [string]$Plan.Paths.Directory,
            [StringComparison]::Ordinal) -or
        -not [string]::Equals([string]$derived.SourcePst, [string]$Plan.Paths.SourcePst,
            [StringComparison]::Ordinal) -or
        -not [string]::Equals([string]$derived.ArchivePst, [string]$Plan.Paths.ArchivePst,
            [StringComparison]::Ordinal)) {
        throw 'Fixture paths must be derived only from the RunId.'
    }
    if (Test-Path -LiteralPath $derived.Directory) {
        throw 'Fixture RunId already exists: refusing reuse or cleanup.'
    }
    foreach ($path in @($derived.SourcePst,$derived.ArchivePst,
        $derived.JournalPath,$derived.MarkerPath,$derived.RequestPath,
        $derived.ResponsePath,$derived.ClaimPath,
        (Join-Path $derived.Directory 'controller-dispatch.claim'))) {
        if (Test-Path -LiteralPath $path) {
            throw 'Fixture target already exists: refusing overwrite.'
        }
    }
    return $derived
}

function Get-OPA264FixtureContract {
    [CmdletBinding()]
    param()
    return [pscustomobject]@{
        Purpose = 'Disposable cross-PST Move diagnostic only'
        AllowedStoreCount = 2
        AllowedMailMoveCount = 1
        ExistingStoresAllowed = $false
        ProductionModeEnabled = $false
        TestControllerAutoLaunch = $false
        OutlookProcessTerminationAllowed = $false
        AutomaticRetryAllowed = $false
        AutomaticJournalCompletionAllowed = $false
        PreserveArtifactsOnFailure = $true
    }
}
