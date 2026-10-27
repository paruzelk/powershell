#requires -Version 5.1
# BW3f: read-only evidence aggregation and manual size-decision dossier.
# No Move, journal completion, claim creation or file write.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ExpectedJournalSha256,
    [switch]$Review
)
$ErrorActionPreference='Stop'
if (-not $Review -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA') {
    throw 'BW3f requires explicit read-only -Review under Windows PowerShell 5.1 STA.'
}
. (Join-Path $PSScriptRoot '../Worker/Live3SyntheticScope.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3OneShotProtocol265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3bIndependentAudit265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3dSyntheticSizeEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3eSyntheticBodyTailEvidence265.ps1')
. (Join-Path $PSScriptRoot '../Worker/BW3fManualSizeDossier265.ps1')
$pinned=Get-OPA265BW3ePinnedTailEvidence
if ($RunId -cne [string]$pinned.RunId -or
    $SourcePst -cne [string]$pinned.SourcePst -or
    $ExpectedJournalSha256 -cne [string]$pinned.JournalSha256) {
    throw 'BW3f is strictly limited to one approved historical synthetic fixture.'
}
$stage='Fingerprint existing original fixture evidence'
try {
    $paths=Get-OPA264Live3Paths -RunId $RunId -SourcePst $SourcePst
    $extra=Get-OPA265BW3Paths -FixturePaths $paths
    $fileList=@($paths.JournalPath,$paths.RequestPath,$paths.ScopePath,
        $paths.ClaimPath,$extra.DispatchClaimPath,$extra.ControllerResultPath)
    $before=@{}
    foreach($file in $fileList) {
        if (-not [IO.File]::Exists($file) -or
            ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'BW3f requires all six original regular journal/fixture/claim evidence files.'
        }
        $before[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if ([string]$before[$paths.JournalPath] -cne [string]$pinned.JournalSha256) {
        throw 'BW3f original durable Intent does not match pinned journal SHA256.'
    }
    $stage='Rerun existing independent BW3e, BW3d and BW3b read-only audits'
    # BW3e invokes BW3d which invokes BW3b. Each stage independently
    # checks previously established synthetic Outlook evidence.
    $audit=& (Join-Path $PSScriptRoot 'Test-OPA265BW3eSyntheticBodyTailAudit.ps1') -RunId $RunId -SourcePst $SourcePst -ExpectedJournalSha256 $ExpectedJournalSha256 -Review
    $stage='Strictly validate one historical BW3e audit verdict'
    [void](Assert-OPA265BW3fHistoricalAudit -Audit $audit -Pinned $pinned)
    $stage='Verify original journal and claims unchanged after audit chain'
    foreach($file in $fileList) {
        $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne [string]$before[$file]) {
            throw 'BW3f original durable fixture or claim evidence changed during audit.'
        }
    }
    $stage='Prepare read-only human decision dossier (NO CONSENT)'
    Write-Output (Get-OPA265BW3fDecisionDossier -Audit $audit -Pinned $pinned)
} catch {
    throw ('BW3f dossier STOP at [{0}]: {1}. Original Intent and claims preserved; NO MOVE, APPROVAL, RETRY or RECONCILED.' -f
        $stage,[string]$_.Exception.Message)
}
