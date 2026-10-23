#requires -Version 5.1
# 2.6.4-F independent diagnostic ONLY. No PST mount, MailMove, journal write,
# automatic retry, Worker dispatch or process kill.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [switch]$Review,
    [ValidateSet('None','AfterIntentBeforeDispatch','WorkerStartedBeforeMove',
        'AfterMoveBeforeResponse','AfterResponseBeforeTerminal')]
    [string]$ExpectedCrashWindow='None'
)
$ErrorActionPreference='Stop'
if (-not $Review) { throw '2.6.4-F audit requires explicit -Review.' }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw '2.6.4-F audit requires Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/WorkerTestMove.ps1')
. (Join-Path $PSScriptRoot '../Worker/WorkerEvidenceAudit.ps1')
$paths=Get-OPA264TestPaths -RunId $RunId
$recoveryScript=Join-Path $PSScriptRoot 'Invoke-OPA264ReadOnlyRecovery.ps1'
# D CLI independently verifies exact mounted disposable stores, folder
# identities, durable Intent, and performs full read-only Outlook scans.
$raw=@(& $recoveryScript -RunId $paths.RunId -Review)
if ($raw.Count -eq 0) { throw 'Independent recovery returned no evidence.' }
try { $recovery=ConvertFrom-Json -InputObject ($raw -join [Environment]::NewLine) -ErrorAction Stop }
catch { throw 'Independent recovery returned malformed JSON.' }
[void](Assert-OPA264TestPath -Actual $paths.RequestPath -Expected $paths.RequestPath -Label 'audit request')
$request=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($paths.RequestPath)) -ErrorAction Stop
$identityPath=Join-Path $paths.Directory 'identity-report.json'
$identity=$null
if ([IO.File]::Exists($identityPath)) {
    [void](Assert-OPA264TestPath -Actual $identityPath -Expected $identityPath -Label 'identity report')
    $identity=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($identityPath)) -ErrorAction Stop
    if ([bool]$recovery.Artifacts.WorkerMoveClaimPresent -or
        [bool]$recovery.Artifacts.ControllerDispatchClaimPresent) {
        throw 'Identity probe and Worker dispatch cannot coexist for the same disposable RunId.'
    }
}
$params=@{
    Recovery=$recovery
    RunId=$paths.RunId
    OperationId=[string]$request.OperationId
    ExpectedCrashWindow=$ExpectedCrashWindow
    Identity=$identity
}
$audit=New-OPA264EvidenceAudit @params
# Privacy-limited report. Never print message subjects, senders, EntryIDs,
# message bodies or raw PST content. A report is NOT Move completion proof.
Write-Output (ConvertTo-Json -InputObject $audit -Depth 8)
