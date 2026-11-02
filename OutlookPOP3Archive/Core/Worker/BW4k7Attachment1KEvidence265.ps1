#requires -Version 5.1
# BW4k7: exact Attachment1K synthetic MailItem MAPI evidence ONLY.
# No Move, Save, PST creation, journal edits, claim replay, or size waiver.
. (Join-Path $PSScriptRoot 'BW4k5HtmlEvidence265.ps1')

function Get-OPA265BW4k7Attachment1KSnapshotPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $null=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId -LocalAppData $LocalAppData
    if($TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7'){
        throw 'BW4k7 only original Attachment1K fixture.'
    }
    Join-Path (Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k7-SourceSnapshots') ('suite-'+$SuiteId)) ('fixture-'+$TestId+'.json')
}
function Assert-OPA265BW4k7HistoricCompletedMoves {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f'){
        throw 'BW4k7 prior-move chain belongs to one exact suite only.'
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
        [pscustomobject]@{
            TestId='42db9da2-0596-4e17-aad7-52eeab0e4601'
            ClaimSha256='e22cad1372eaaed4734565c77c3ac27687fea9d2c1cc760f7eedbed91812ac02'
        }
    )
    foreach($pin in $prior){
        $path=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $pin.TestId -LocalAppData $LocalAppData
        if(-not [IO.File]::Exists($path) -or
           (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
           (Get-Item -LiteralPath $path -Force).Length -gt 16384 -or
           (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pin.ClaimSha256){
            throw ('BW4k7 STOP: immutable historical BW4k1 claim changed: '+$pin.TestId)
        }
    }
    $unicode=Get-OPA265BW4k3SnapshotPath -SuiteId $SuiteId -TestId '32cf8351-1f58-408d-a5e7-befd1c6c43e0' -LocalAppData $LocalAppData
    if(-not [IO.File]::Exists($unicode) -or
       (([IO.File]::GetAttributes($unicode) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-FileHash -LiteralPath $unicode -Algorithm SHA256).Hash.ToLowerInvariant() -cne '5703ed3a8fa2c8b91933c8090cb3bbd4e9a6092320e6f75319169d9346bf84c2'){
        throw 'BW4k7 STOP: original immutable UnicodePlain pre-Move MAPI snapshot changed.'
    }
    $html=Get-OPA265BW4k5HtmlSnapshotPath -SuiteId $SuiteId -TestId '42db9da2-0596-4e17-aad7-52eeab0e4601' -LocalAppData $LocalAppData
    if(-not [IO.File]::Exists($html) -or
       (([IO.File]::GetAttributes($html) -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
       (Get-FileHash -LiteralPath $html -Algorithm SHA256).Hash.ToLowerInvariant() -cne '755242f7ea0c270e12236f20a2b578a9b43dc648b105ae6c5c0ccce5caada3be'){
        throw 'BW4k7 STOP: original immutable HtmlBody pre-Move MAPI evidence changed.'
    }
    return $true
}
function Assert-OPA265BW4k7Attachment1KRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Record,
          [Parameter(Mandatory=$true)][psobject]$Original,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [Parameter(Mandatory=$true)][string]$OriginalEvidenceSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedPlanSha256,
          [Parameter(Mandatory=$true)][string]$ExpectedFiveEvidenceSetSha256)
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7'){
        throw 'BW4k7 unexpected fixed Attachment1K suite or TestId.'
    }
    if(@($Original.Attachments).Count -ne 1 -or
       [long]$Original.Attachments[0].ByteCount -lt 1024 -or
       [string]$Original.Attachments[0].Sha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4k7 original by-value Attachment1K witness missing or invalid.'
    }
    $names=@('Schema','SuiteId','TestId','CaseName','PlanSha256',
        'OriginalEvidenceSha256','FiveEvidenceSetSha256','SourceEntryId',
        'SourceFolderEntryId','SourceStoreIdSha256','SourceSize',
        'CapturedUtc','Snapshot','OutlookMoveExecuted','ProductionReady')
    if(@($Record.PSObject.Properties.Name).Count -ne $names.Count){
        throw 'BW4k7 original metadata schema property count mismatch.'
    }
    foreach($n in $names){if($Record.PSObject.Properties.Name -cnotcontains $n){throw ('BW4k7 original metadata missing '+$n)}}
    $pins=@{
        Schema='2.6.5-BW4k7.ImmutableAttachment1KSourceMapiEvidence.1'
        SuiteId=$SuiteId;TestId=$TestId;CaseName='Attachment1K'
        PlanSha256=$ExpectedPlanSha256
        OriginalEvidenceSha256=$OriginalEvidenceSha256
        FiveEvidenceSetSha256=$ExpectedFiveEvidenceSetSha256
        SourceEntryId=[string]$Original.EntryId
        SourceFolderEntryId=[string]$Original.FolderEntryId
        SourceStoreIdSha256=(Get-OPA265BW4jTextHash -Value ([string]$Original.StoreId))
        SourceSize=[string][long]$Original.Size
    }
    foreach($p in $pins.Keys){
        if([string]$Record.$p -cne [string]$pins[$p]){throw ('BW4k7 original metadata pin mismatch: '+$p)}
    }
    if($Record.OutlookMoveExecuted -isnot [bool] -or $Record.OutlookMoveExecuted -or
       $Record.ProductionReady -isnot [bool] -or $Record.ProductionReady){
        throw 'BW4k7 original metadata cannot claim Move or production readiness.'
    }
    $when=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Record.CapturedUtc,[ref]$when)){
        throw 'BW4k7 invalid metadata capture timestamp.'
    }
    $snapshot=$Record.Snapshot
    if($null -eq $snapshot -or
       [string]$snapshot.SuiteId -cne $SuiteId -or
       [string]$snapshot.TestId -cne $TestId -or
       [string]$snapshot.EntryId -cne [string]$Original.EntryId -or
       [string]$snapshot.FolderEntryId -cne [string]$Original.FolderEntryId -or
       [string]$snapshot.StoreIdSha256 -cne [string]$pins.SourceStoreIdSha256){
        throw 'BW4k7 embedded original MAPI snapshot identity differs.'
    }
    [void](Assert-OPA265BW4k3StableSnapshots -First $snapshot -Second $snapshot)
    $available=0
    foreach($row in @($snapshot.Rows)){
        if($row.Available -isnot [bool]){throw 'BW4k7 invalid MAPI availability type.'}
        if($row.Available){
            $available++
            if([string]$row.Kind -cnotin @('Binary','DateTimeUtcTicks','Boolean','UnicodeText','SignedInteger') -or
               [string]$row.Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
               [int]$row.ByteCount -lt 0 -or [int]$row.ByteCount -gt 1048576){
                throw 'BW4k7 invalid available bounded property digest.'
            }
        }elseif([string]$row.Kind -cne 'UnavailableOrError' -or
                [string]$row.Sha256 -cne '' -or
                [string]$row.Scalar -cne ''){
            throw 'BW4k7 unavailable property must not fabricate a digest.'
        }
    }
    if([int]$snapshot.AvailableCount -ne $available){
        throw 'BW4k7 bounded available property count mismatch.'
    }
    return $true
}
function Write-OPA265BW4k7Attachment1KSnapshotOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Record,
          [Parameter(Mandatory=$true)][string]$Path,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $expected=Get-OPA265BW4k7Attachment1KSnapshotPath -SuiteId ([string]$Record.SuiteId) -TestId ([string]$Record.TestId) -LocalAppData $LocalAppData
    if(-not [string]::Equals([IO.Path]::GetFullPath($Path),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k7 snapshot path cannot be redirected.'
    }
    if([string]$Record.Schema -cne '2.6.5-BW4k7.ImmutableAttachment1KSourceMapiEvidence.1' -or
       [string]$Record.PlanSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Record.OriginalEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Record.FiveEvidenceSetSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $Record.OutlookMoveExecuted -isnot [bool] -or $Record.OutlookMoveExecuted -or
       $Record.ProductionReady -isnot [bool] -or $Record.ProductionReady){
        throw 'BW4k7 unsafe source snapshot payload.'
    }
    $parent=[IO.Path]::GetDirectoryName($expected)
    $root=[IO.Path]::GetDirectoryName($parent)
    if(-not [IO.Directory]::Exists($root)){[void][IO.Directory]::CreateDirectory($root)}
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7 source snapshot root cannot be reparse point.'
    }
    if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
    if(([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k7 source snapshot parent cannot be reparse point.'
    }
    # Existing bounded witness writer uses CreateNew, Flush(true) and UTF-8 BOM.
    $written=Write-OPA265BW4jOnce -Object $Record -Path $expected
    return [pscustomobject][ordered]@{
        SnapshotPath=$written
        SnapshotSha256=(Get-FileHash -LiteralPath $written -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
