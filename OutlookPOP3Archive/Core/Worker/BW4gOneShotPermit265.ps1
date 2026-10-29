#requires -Version 5.1
# BW4g dev-only explicit disposable fixture Move; absolute no retry, no production integration.
function Assert-OPA265BW4gReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Review,
        [Parameter(Mandatory=$true)][string]$TestId,
        [Parameter(Mandatory=$true)][string]$CandidateEntryId,
        [Parameter(Mandatory=$true)][string]$InternetMessageId
    )
    $id=[guid]::Empty
    if (-not [guid]::TryParse($TestId,[ref]$id) -or
        $id -eq [guid]::Empty -or $TestId -cne $id.ToString('D') -or
        [string]$Review.Schema -cne '2.6.5-BW4f.DisposableFixtureScopeReadOnly.1' -or
        [string]$Review.Status -cne 'DisposableFixtureScopeConsistentButNoMovePermit' -or
        [string]$Review.TestId -cne $TestId -or
        -not (Test-OPA265BW4cOpaqueIdMatch -Observed ([string]$Review.CandidateEntryId) -Expected $CandidateEntryId) -or
        [string]$Review.InternetMessageId -cne $InternetMessageId -or
        $Review.IsExactOperatorFixture -isnot [bool] -or -not $Review.IsExactOperatorFixture -or
        $Review.TargetedMessageIdReadOnlyUsed -isnot [bool] -or -not $Review.TargetedMessageIdReadOnlyUsed -or
        $Review.SevenHistoricalEvidenceHashesUnchanged -isnot [bool] -or -not $Review.SevenHistoricalEvidenceHashesUnchanged -or
        $Review.HistoricalEvidenceFilesUnchanged -isnot [bool] -or -not $Review.HistoricalEvidenceFilesUnchanged -or
        [string]$Review.HistoricJournalPhase -cne 'Intent' -or
        [int]$Review.HistoricJournalEventCount -ne 1 -or
        $Review.WorkerDispatchAllowed -isnot [bool] -or $Review.WorkerDispatchAllowed -or
        $Review.OutlookMoveExecuted -isnot [bool] -or $Review.OutlookMoveExecuted -or
        $Review.CanRetryPreviousMove -isnot [bool] -or $Review.CanRetryPreviousMove -or
        $Review.CanInvokeMailMove -isnot [bool] -or $Review.CanInvokeMailMove -or
        $Review.AutomaticRetryAllowed -isnot [bool] -or $Review.AutomaticRetryAllowed -or
        $Review.ProductionReady -isnot [bool] -or $Review.ProductionReady) {
        throw 'BW4g DENIED: exact BW4f disposable fixture and historical fence must pass; read-only status never itself grants Move.'
    }
    return $true
}
function Get-OPA265BW4gClaimPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $id=[guid]::Empty
    if (-not [guid]::TryParse($TestId,[ref]$id) -or
        $id -eq [guid]::Empty -or $TestId -cne $id.ToString('D')) {
        throw 'BW4g claim requires exact canonical nonempty GUID.'
    }
    if ([string]::IsNullOrWhiteSpace($LocalAppData) -or
        -not [IO.Path]::IsPathRooted($LocalAppData)) {
        throw 'BW4g claim requires local per-user Windows AppData.'
    }
    return (Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4g-Claims') ('fixture-'+$TestId+'.json'))
}
function Write-OPA265BW4gOneShotClaim {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ClaimPath,
          [Parameter(Mandatory=$true)][object]$Claim)
    if ([string]$Claim.Schema -cne '2.6.5-BW4g.ImmutableOneShotClaim.1' -or
        [string]$Claim.TestId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
        [bool]$Claim.AutomaticRetryAllowed -or
        [bool]$Claim.ProductionReady) { throw 'BW4g claim payload invalid.' }
    $expected=Get-OPA265BW4gClaimPath -TestId ([string]$Claim.TestId)
    if (-not [string]::Equals([IO.Path]::GetFullPath($ClaimPath),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'BW4g claim path cannot be redirected.'
    }
    $dir=[IO.Path]::GetDirectoryName($expected)
    if (-not [IO.Directory]::Exists($dir)){[void][IO.Directory]::CreateDirectory($dir)}
    $attrs=[IO.File]::GetAttributes($dir)
    if (($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'BW4g claim directory is a reparse point, denied.'
    }
    # Claim is durable BEFORE the ONE and ONLY Outlook Move. Do not delete
    # it if the caller crashes, COM hangs or Move gives an ambiguous result.
    $bytes=(New-Object Text.UTF8Encoding($true)).GetBytes(
        (ConvertTo-Json -InputObject $Claim -Depth 5))
    $stream=$null
    try {
        $stream=[IO.FileStream]::new($expected,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {if ($null -ne $stream){$stream.Dispose()}}
    return $expected
}
