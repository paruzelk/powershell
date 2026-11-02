#requires -Version 5.1
# BW4k5: exact HtmlBody synthetic MailItem MAPI evidence ONLY.
# No Move, Save, PST creation, journal edits, claim replay, or size waiver.
. (Join-Path $PSScriptRoot 'BW4k3BoundedMapiSnapshot265.ps1')

function Get-OPA265BW4k5HtmlSnapshotPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $null=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId -LocalAppData $LocalAppData
    if($TestId -cne '42db9da2-0596-4e17-aad7-52eeab0e4601'){
        throw 'BW4k5 only original HtmlBody fixture.'
    }
    Join-Path (Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k5-SourceSnapshots') ('suite-'+$SuiteId)) ('fixture-'+$TestId+'.json')
}
function Assert-OPA265BW4k5HistoricCompletedMoves {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f'){
        throw 'BW4k5 prior-move chain belongs to one exact suite only.'
    }
    $prior=@(
        [pscustomobject]@{
            TestId='d25384b5-03b7-4f79-80df-15a6d5a2e47c'
            ClaimSha256='15808a6983d8f684b6c4670d7f142467172e3a4c89021121490c330b99440494'
        }
        [pscustomobject]@{
            TestId='32cf8351-1f58-408d-a5e7-befd1c6c43e0'
            ClaimSha256='ce1de5690d4f3b5efabf4f0223289b0be5a446a360c1ec410b50f283aec318f1'
        }
    )
    foreach($pin in $prior){
        $path=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $pin.TestId -LocalAppData $LocalAppData
        if(-not [IO.File]::Exists($path) -or
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
           (Get-Item -LiteralPath $path -Force).Length -gt 16384 -or
           (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin.ClaimSha256){
            throw ('BW4k5 STOP: immutable historical BW4k1 claim changed: '+$pin.TestId)
        }
    }
    $unicode=Get-OPA265BW4k3SnapshotPath -SuiteId $SuiteId -TestId '32cf8351-1f58-408d-a5e7-befd1c6c43e0' -LocalAppData $LocalAppData
    if(-not [IO.File]::Exists($unicode) -or
       (([IO.File]::GetAttributes($unicode) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-FileHash -LiteralPath $unicode -Algorithm SHA256).Hash.ToLowerInvariant() -cne '5703ed3a8fa2c8b91933c8090cb3bbd4e9a6092320e6f75319169d9346bf84c2'){
        throw 'BW4k5 STOP: original immutable UnicodePlain pre-Move MAPI snapshot changed.'
    }
    return $true
}
function Assert-OPA265BW4k5HtmlRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Record,
          [Parameter(Mandatory=$true)][psobject]$Original,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [Parameter(Mandatory=$true)][string]$OriginalEvidenceSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256)
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '42db9da2-0596-4e17-aad7-52eeab0e4601'){
        throw 'BW4k5 unexpected fixed HtmlBody suite or TestId.'
    }
    $names=@('Schema','SuiteId','TestId','CaseName','PlanSha256',
        'OriginalEvidenceSha256','FiveEvidenceSetSha256','SourceEntryId',
        'SourceFolderEntryId','SourceStoreIdSha256','SourceSize',
        'CapturedUtc','Snapshot','OutlookMoveExecuted','ProductionReady')
    if(@($Record.PSObject.Properties.Name).Count -ne $names.Count){
        throw 'BW4k5 original metadata schema property count mismatch.'
    }
    foreach($n in $names){if($Record.PSObject.Properties.Name -cnotcontains $n){throw ('BW4k5 original metadata missing '+$n)}}
    $pins=@{
        Schema='2.6.5-BW4k5.ImmutableHtmlBodySourceMapiEvidence.1'
        SuiteId=$SuiteId;TestId=$TestId;CaseName='HtmlBody'
        PlanSha256=$ExpectedPlanSha256
        OriginalEvidenceSha256=$OriginalEvidenceSha256
        FiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        SourceEntryId=[string]$Original.EntryId
        SourceFolderEntryId=[string]$Original.FolderEntryId
        SourceStoreIdSha256=(Get-OPA265BW4jTextHash -Value ([string]$Original.StoreId))
        SourceSize=[string][long]$Original.Size
    }
    foreach($p in $pins.Keys){
        if([string]$Record.$p -cne [string]$pins[$p]){throw ('BW4k5 original metadata pin mismatch: '+$p)}
    }
    if($Record.OutlookMoveExecuted -isnot [bool] -or $Record.OutlookMoveExecuted -or
       $Record.ProductionReady -isnot [bool] -or $Record.ProductionReady){
        throw 'BW4k5 original metadata cannot claim Move or production readiness.'
    }
    $when=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Record.CapturedUtc,[ref]$when)){
        throw 'BW4k5 invalid metadata capture timestamp.'
    }
    $snapshot=$Record.Snapshot
    if($null -eq $snapshot -or
       [string]$snapshot.SuiteId -cne $SuiteId -or
       [string]$snapshot.TestId -cne $TestId -or
       [string]$snapshot.EntryId -cne [string]$Original.EntryId -or
       [string]$snapshot.FolderEntryId -cne [string]$Original.FolderEntryId -or
       [string]$snapshot.StoreIdSha256 -cne [string]$pins.SourceStoreIdSha256){
        throw 'BW4k5 embedded original MAPI snapshot identity differs.'
    }
    [void](Assert-OPA265BW4k3StableSnapshots -First $snapshot -Second $snapshot)
    $available=0
    foreach($row in @($snapshot.Rows)){
        if($row.Available -isnot [bool]){throw 'BW4k5 invalid MAPI availability type.'}
        if($row.Available){
            $available++
            if([string]$row.Kind -cnotin @('Binary','DateTimeUtcTicks','Boolean','UnicodeText','SignedInteger') -or
               [string]$row.Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
               [int]$row.ByteCount -lt 0 -or [int]$row.ByteCount -gt 1048576){
                throw 'BW4k5 invalid available bounded property digest.'
            }
        }elseif([string]$row.Kind -cne 'UnavailableOrError' -or
                [string]$row.Sha256 -cne '' -or
                [string]$row.Scalar -cne ''){
            throw 'BW4k5 unavailable property must not fabricate a digest.'
        }
    }
    if([int]$snapshot.AvailableCount -ne $available){
        throw 'BW4k5 bounded available property count mismatch.'
    }
    return $true
}
function Write-OPA265BW4k5HtmlSnapshotOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Record,
          [Parameter(Mandatory=$true)][string]$Path,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $expected=Get-OPA265BW4k5HtmlSnapshotPath -SuiteId ([string]$Record.SuiteId) -TestId ([string]$Record.TestId) -LocalAppData $LocalAppData
    if(-not [string]::Equals([IO.Path]::GetFullPath($Path),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k5 snapshot path cannot be redirected.'
    }
    if([string]$Record.Schema -cne '2.6.5-BW4k5.ImmutableHtmlBodySourceMapiEvidence.1' -or
       [string]$Record.PlanSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Record.OriginalEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Record.FiveEvidenceSetSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $Record.OutlookMoveExecuted -isnot [bool] -or $Record.OutlookMoveExecuted -or
       $Record.ProductionReady -isnot [bool] -or $Record.ProductionReady){
        throw 'BW4k5 unsafe source snapshot payload.'
    }
    $parent=[IO.Path]::GetDirectoryName($expected)
    $root=[IO.Path]::GetDirectoryName($parent)
    if(-not [IO.Directory]::Exists($root)){[void][IO.Directory]::CreateDirectory($root)}
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k5 source snapshot root cannot be reparse point.'
    }
    if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
    if(([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k5 source snapshot parent cannot be reparse point.'
    }
    # Existing bounded witness writer uses CreateNew, Flush(true) and UTF-8 BOM.
    $written=Write-OPA265BW4jOnce -Object $Record -Path $expected
    return [pscustomobject][ordered]@{
        SnapshotPath=$written
        SnapshotSha256=(Get-FileHash -LiteralPath $written -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
