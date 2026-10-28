#requires -Version 5.1
# BW3k: SELF-CONTAINED synthetic temporary journal test.
# No path, PST, RunId, journal hash, -Execute or -Record parameters accepted.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
if (-not $SelfTest -or $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5) {
    throw 'BW3k only accepts -SelfTest under native Windows PowerShell 5.1.'
}
. (Join-Path $PSScriptRoot '../Archive/OperationJournal.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3kSandboxJournalWriter265.ps1')
$fixture=New-OPA265BW3kIsolatedFixture
$paths=$fixture.Paths
$marker=$fixture.Marker
$before=(Get-FileHash -LiteralPath $paths.JournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($before -cne [string]$marker.OriginalJournalSha256) {
    throw 'BW3k generated fixture journal did not match marker.'
}
$report=Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $paths.Directory
$last=Read-OPAOperationJournal -Path $paths.JournalPath
[void](Assert-OPA265BW3kTerminalReplay -Journal $last -Marker $marker)
if (-not [IO.File]::Exists($paths.ClaimPath)) {
    throw 'BW3k durable sandbox claim was not created.'
}
$blocked=$false
try {
    $null=Invoke-OPA265BW3kSandboxAppend -SandboxDirectory $paths.Directory
} catch {
    if ([string]$_.Exception.Message -notmatch 'claim exists') { throw }
    $blocked=$true
}
if (-not $blocked) { throw 'BW3k unexpectedly accepted a second append.' }
Write-Output ([pscustomobject][ordered]@{
    Schema='2.6.5-BW3k.IsolatedSyntheticSelfTest.1'
    Status='IsolatedSyntheticAppendAndReplayVerified'
    SandboxDirectory=[string]$paths.Directory
    SandboxOriginalSha256=$before
    SandboxFinalSha256=[string]$report.SandboxFinalJournalSha256
    SingleIntentThenReconciled=$true
    JournalEventCount=2
    RepeatedAppendBlocked=$true
    DurableClaimCreatedInSandbox=$true
    HistoricBw3aJournalTouched=$false
    OutlookComAccessExecuted=$false
    MailMoveExecuted=$false
    ProductionReady=$false
    NextAction='OnlyIndependentSandboxTestsAndReviewBeforeAnyHistoricalApproval'
})
