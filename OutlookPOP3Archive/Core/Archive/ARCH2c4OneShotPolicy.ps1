#requires -Version 5.1
# ARCH2c4: operator-authorized ONE real POP3 message pilot, pure policy and
# sealed evidence helpers. Never opens Outlook or modifies a PST by itself.
function Get-OPA265ARCH2c4Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$LocalAppData)
    $g=[guid]::Empty
    if(-not [guid]::TryParse($RunId,[ref]$g) -or $g -eq [guid]::Empty -or
       $g.ToString('D') -cne $RunId){
        throw 'ARCH2c4 requires a fresh canonical lowercase RunId GUID.'
    }
    $local=[IO.Path]::GetFullPath($LocalAppData)
    if(-not [IO.Directory]::Exists($local) -or $local.StartsWith('\\') -or
       (([IO.File]::GetAttributes($local) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH2c4 requires existing non-reparse local APPDATA directory.'
    }
    $root=Join-Path $local 'OutlookPOP3Archive-ARCH2c4-RealPilot'
    $run=Join-Path $root ('run-'+$RunId)
    $base='OPA265-ARCH2c4-'+$RunId
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2c4.Layout.1'
        RunId=$RunId
        Root=$root;RunDirectory=$run
        ArchivePst=(Join-Path $run ($base+'.pst'))
        ArchiveFolder=$base
        IntentPath=(Join-Path $run 'prepare-intent.json')
        ManifestPath=(Join-Path $run 'pre-move-manifest.json')
        ClaimPath=(Join-Path $run 'move-claim.json')
        ReturnPath=(Join-Path $run 'move-return.json')
        GlobalClaimPath=(Join-Path $root 'ARCH2c4-ONE-ATTEMPT-CLAIM.json')
        AccountEmail='info@stios.ru'
        ProfileName='Outlook'
        WriterPermit=$false;ProductionReady=$false
    }
}
function Assert-OPA265ARCH2c4SourcePst {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][object]$Layout)
    $p=[IO.Path]::GetFullPath($SourcePst)
    if($p.StartsWith('\\') -or -not [IO.File]::Exists($p) -or
       [IO.Path]::GetFileName($p) -ine 'info@stios.ru.pst' -or
       ([string]::Equals($p,[string]$Layout.ArchivePst,
            [StringComparison]::OrdinalIgnoreCase))){
        throw 'ARCH2c4 source must be the existing local info@stios.ru.pst, never a prior fixture/archive.'
    }
    if(([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'ARCH2c4 source PST is a reparse point.'
    }
    return $p
}
function Assert-OPA265ARCH2c4Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout)
    $e=Get-OPA265ARCH2c4Layout -RunId ([string]$Layout.RunId) -LocalAppData $env:LOCALAPPDATA
    foreach($k in @('Root','RunDirectory','ArchivePst','ArchiveFolder','IntentPath',
        'ManifestPath','ClaimPath','ReturnPath','GlobalClaimPath','ProfileName','AccountEmail')){
        if([string]$e.$k -cne [string]$Layout.$k){
            throw ('ARCH2c4 forged layout path or identity: '+$k)
        }
    }
    foreach($p in @($e.Root,$e.RunDirectory,$e.ArchivePst,$e.GlobalClaimPath)){
        if(([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)) -and
           (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH2c4 reparse artifact forbidden.'
        }
    }
    return $true
}
function Test-OPA265ARCH2c4Pop3StoreScope {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$CurrentProfileName,
          [Parameter(Mandatory=$true)][string]$DefaultStoreId,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Stores,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Accounts)
    $issues=New-Object 'System.Collections.Generic.List[string]'
    if($CurrentProfileName -cne 'Outlook'){$issues.Add('WrongProfile')|Out-Null}
    if($Stores.Count -lt 1 -or $Stores.Count -gt 32){$issues.Add('UnboundedStoreCount')|Out-Null}
    if($Accounts.Count -lt 1 -or $Accounts.Count -gt 64){$issues.Add('UnboundedAccountCount')|Out-Null}
    $matches=@($Stores|Where-Object {
        $p=[string]$_.FilePath
        -not [string]::IsNullOrWhiteSpace($p) -and
        [string]::Equals([IO.Path]::GetFullPath($p),$SourcePst,
            [StringComparison]::OrdinalIgnoreCase)
    })
    if($matches.Count -ne 1){$issues.Add('SourceStoreNotUnique')|Out-Null}
    $sourceId=if($matches.Count -eq 1){[string]$matches[0].StoreId}else{''}
    if(-not $sourceId){$issues.Add('SourceStoreIdMissing')|Out-Null}
    if($sourceId -and $sourceId -ceq $DefaultStoreId){$issues.Add('SourceIsDefaultStore')|Out-Null}
    $pop3=@($Accounts|Where-Object {
        [string]$_.SmtpAddress -ieq [string]$Layout.AccountEmail -and
        [int]$_.AccountType -eq 2
    })
    if($pop3.Count -ne 1){$issues.Add('Pop3AccountNotUnique')|Out-Null}
    if($pop3.Count -eq 1 -and $sourceId -and
       [string]$pop3[0].DeliveryStoreId -cne $sourceId){
        $issues.Add('Pop3AccountNotDeliveringToSource')|Out-Null
    }
    $archiveMatches=@($Stores|Where-Object {
        $p=[string]$_.FilePath
        -not [string]::IsNullOrWhiteSpace($p) -and
        [string]::Equals([IO.Path]::GetFullPath($p),[string]$Layout.ArchivePst,
            [StringComparison]::OrdinalIgnoreCase)
    })
    if($archiveMatches.Count -gt 1){$issues.Add('ArchiveStoreAmbiguous')|Out-Null}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2c4.Pop3Scope.1'
        Approved=($issues.Count -eq 0)
        ReasonCodes=@($issues.ToArray())
        SourceStoreId=$sourceId
        ArchiveStoreId=if($archiveMatches.Count -eq 1){[string]$archiveMatches[0].StoreId}else{''}
        ArchiveAlreadyAttached=($archiveMatches.Count -eq 1)
        WriterPermit=$false;ProductionReady=$false
    }
}
function Write-OPA265ARCH2c4JsonOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][object]$Value)
    if([IO.File]::Exists($Path)){throw 'ARCH2c4 immutable evidence exists. No overwrite or retry.'}
    $json=ConvertTo-Json -InputObject $Value -Depth 16 -Compress
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($json+[char]10)
    $stream=$null
    try {
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,[IO.FileShare]::None)
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Flush($true)
    } finally {if($null -ne $stream){$stream.Dispose()}}
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-OPA265ARCH2c4JsonSealed {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][string]$ExpectedSha256)
    if($ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       -not [IO.File]::Exists($Path) -or
       (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       [int64](Get-Item -LiteralPath $Path).Length -gt 1048576){
        throw 'ARCH2c4 missing/unsafe evidence or noncanonical expected SHA256.'
    }
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -cne $ExpectedSha256){throw 'ARCH2c4 immutable evidence SHA256 mismatch; STOP.'}
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)
}
function Assert-OPA265ARCH2c4OneShotApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Prepare','Move')][string]$Action,
          [Parameter(Mandatory=$true)][string]$RunId,
          [Parameter(Mandatory=$true)][string]$ApprovalText,
          [Parameter(Mandatory=$true)][bool]$Confirmed)
    $expected=$Action.ToUpperInvariant()+' ARCH2C4 '+$RunId
    if(-not $Confirmed -or $ApprovalText -cne $expected){
        throw ('ARCH2c4 explicit one-shot approval required: '+$expected)
    }
    return $true
}
function Test-OPA265ARCH2c4Reconciliation {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][int]$SourceCount,
          [Parameter(Mandatory=$true)][int]$DestinationCount,
          [Parameter(Mandatory=$true)][bool]$SemanticContentMatches,
          [Parameter(Mandatory=$true)][bool]$RestartConfirmed)
    $ok=$RestartConfirmed -and $SourceCount -eq 0 -and
        $DestinationCount -eq 1 -and $SemanticContentMatches
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2c4.IndependentReconciliation.1'
        Status=if($ok){'IndependentPostRestartSourceZeroArchiveOneSemanticMatch'}else{'ManualReviewRequiredNoAutomaticRetry'}
        IndependentlyMatched=$ok
        SourceMatches=$SourceCount;DestinationMatches=$DestinationCount
        SemanticContentMatches=$SemanticContentMatches
        AutomaticMoveRetryAllowed=$false
        ProductionReady=$false
    }
}
