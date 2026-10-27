#requires -Version 5.1
# BW3g separately records an explicit historic +8 byte synthetic size decision.
# Record mode writes ONLY new bw3g-manual-size-acceptance.json (CreateNew).
# Review mode never writes. Neither mode reconciles journal or moves mail.
[CmdletBinding(DefaultParameterSetName='Review')]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [Parameter(ParameterSetName='Review',Mandatory=$true)][switch]$Review,
    [Parameter(ParameterSetName='Record',Mandatory=$true)][switch]$Record,
    [Parameter(ParameterSetName='Record',Mandatory=$true)][string]$ExactSizeAcceptance
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW3g needs native Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3eSyntheticBodyTailEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3gManualSizeAcceptance265.ps1')
$pinned=Get-OPA265BW3gPinnedAcceptance
if ($RunId -cne [string]$pinned.RunId -or
    $SourcePst -cne [string]$pinned.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$pinned.JournalSha256) {
    throw 'BW3g is limited to exact one previously accepted synthetic RunId/PST/Intent.'
}
if ($Record -and $ExactSizeAcceptance -cne [string]$pinned.ExactAcknowledgment) {
    throw 'BW3g requires exact one-run explicit manual +8 byte acceptance text.'
}
$stage='Verify original evidence and existing manual acceptance state'
try {
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $path=Get-OPA265BW3gRecordPath -Paths $paths
    # In record mode an existing file (even partial) is an irreversible
    # fence. Stop BEFORE any Outlook COM access. Never overwrite/retry.
    if ($Record -and ([IO.File]::Exists($path) -or [IO.Directory]::Exists($path))) {
        throw 'BW3g approval record already exists. Never overwrite or retry.'
    }
    $before=Get-OPA265BW3gEvidenceFileHashes -Paths $paths -Extra $extra
    $stage='Rerun independent BW3f through BW3e, BW3d and BW3b (READ ONLY)'
    $dossier=& (Join-Path $PSScriptRoot 'Test-OPA265BW3fManualSizeDecisionDossier.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
    [void](Assert-OPA265BW3gReviewDossier -Dossier $dossier -Pinned $pinned)
    $fingerprint=Get-OPA265BW3gDossierFingerprint -Dossier $dossier -Pinned $pinned
    $stage='Verify original six evidence files unchanged after independent audits'
    $current=Get-OPA265BW3gEvidenceFileHashes -Paths $paths -Extra $extra
    [void](Assert-OPA265BW3gHashesUnchanged -Previous $before -Current $current)
    if ($Review) {
        $stage='Inspect optional existing independent acceptance JSON (READ ONLY)'
        $existing=Read-OPA265BW3gOriginalRecord -Paths $paths -Pinned $pinned -EvidenceHashes $current -DossierFingerprint $fingerprint
        if ($null -eq $existing) {
            Write-Output ([pscustomobject]@{
                Schema='2.6.5-BW3g.ManualSizeAcceptanceStatus.1'
                Status='ManualSizeAcceptanceNotYetPersisted'
                Decision='ManualOperatorRecordInvocationRequired'
                RunId=[string]$pinned.RunId
                JournalSha256=[string]$pinned.JournalSha256
                AcceptanceRecordPath=$path
                AcceptedDifferenceBytes=8L
                ManualSizeAcceptancePersisted=$false
                JournalReconciliationAuthorized=$false
                JournalChanged=$false
                JournalReconciled=$false
                MailMoveExecuted=$false
                AutomaticRetryAllowed=$false
                ProductionReady=$false
            })
        } else {
            Write-Output ([pscustomobject]@{
                Schema='2.6.5-BW3g.ManualSizeAcceptanceStatus.1'
                Status='HistoricalSyntheticSizeAcceptanceRecordVerified'
                Decision='OnlyEightByteSyntheticSizeDeviationRecorded'
                RunId=[string]$pinned.RunId
                JournalSha256=[string]$pinned.JournalSha256
                AcceptanceRecordPath=$existing.Path
                AcceptanceRecordSha256=$existing.Sha256
                AcceptedDifferenceBytes=8L
                ManualSizeAcceptancePersisted=$true
                JournalReconciliationAuthorized=$false
                JournalChanged=$false
                JournalReconciled=$false
                MailMoveExecuted=$false
                AutomaticRetryAllowed=$false
                ProductionReady=$false
            })
        }
        return
    }
    $stage='Create exactly one independent explicit acceptance record'
    $sizeAcceptanceEntry=New-OPA265BW3gManualAcceptance -Dossier $dossier -Pinned $pinned -EvidenceHashes $current -Acknowledgment $ExactSizeAcceptance
    $sha=Get-OPA265BW3gDossierFingerprint -Dossier $dossier -Pinned $pinned
    [void](Assert-OPA265BW3gManualAcceptance -Record $sizeAcceptanceEntry -Pinned $pinned -EvidenceHashes $current -DossierFingerprint $sha)
    # There is only ONE irreversible write: FileMode.CreateNew at fixed path.
    $written=Write-OPA265BW3gCreateNewRecord -Paths $paths -Record $sizeAcceptanceEntry
    $stage='Verify original journal and claim hashes unchanged after separate record write'
    $after=Get-OPA265BW3gEvidenceFileHashes -Paths $paths -Extra $extra
    [void](Assert-OPA265BW3gHashesUnchanged -Previous $current -Current $after)
    $stage='Read back and validate the newly created independent consent record'
    $readback=Read-OPA265BW3gOriginalRecord -Paths $paths -Pinned $pinned -EvidenceHashes $after -DossierFingerprint $fingerprint
    if ($null -eq $readback -or [string]$readback.Sha256 -cne [string]$written.Sha256) {
        throw 'BW3g readback failed: preserve record; no second write.'
    }
    Write-Output ([pscustomobject]@{
        Schema='2.6.5-BW3g.ManualSizeAcceptanceStatus.1'
        Status='HistoricalSyntheticSizeAcceptanceRecorded'
        Decision='OnlyEightByteSyntheticSizeDeviationRecorded'
        RunId=[string]$pinned.RunId
        JournalSha256=[string]$pinned.JournalSha256
        AcceptanceRecordPath=[string]$readback.Path
        AcceptanceRecordSha256=[string]$readback.Sha256
        AcceptedDifferenceBytes=8L
        ManualSizeAcceptancePersisted=$true
        JournalReconciliationAuthorized=$false
        JournalChanged=$false
        JournalCompleted=$false
        JournalReconciled=$false
        MailMoveExecuted=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
        NextAction='StopBeforeAnySeparatelyAuthorizedJournalDecision'
    })
} catch {
    throw ('BW3g STOP at [{0}]: {1}. No Move or journal write. If the acceptance file exists, preserve it without retry.' -f $stage,[string]$_.Exception.Message)
}
