#requires -Version 5.1
# BW4k4: read-only comparison helpers. No one-shot claims, no writer or Move.
. (Join-Path $PSScriptRoot 'BW4k3BoundedMapiSnapshot265.ps1')
. (Join-Path $PSScriptRoot 'BW4k2IndependentRealMoveAudit265.ps1')

function Assert-OPA265BW4k4OriginalMapiEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Record,
          [Parameter(Mandatory=$true)][object]$Original,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [Parameter(Mandatory=$true)][string]$PlanSha256,
          [Parameter(Mandatory=$true)][string]$FiveEvidenceSetSha256,
          [Parameter(Mandatory=$true)][string]$SourceEvidenceSha256)
    $fields=@('Schema','SuiteId','TestId','CaseName','PlanSha256',
        'OriginalEvidenceSha256','FiveEvidenceSetSha256','SourceEntryId',
        'SourceFolderEntryId','SourceStoreIdSha256','SourceSize',
        'CapturedUtc','Snapshot','OutlookMoveExecuted','ProductionReady')
    if(@($Record.PSObject.Properties.Name).Count -ne $fields.Count){
        throw 'BW4k4 exact immutable MAPI evidence schema cardinality changed.'
    }
    foreach($f in $fields){
        if($Record.PSObject.Properties.Name -cnotcontains $f){
            throw ('BW4k4 immutable MAPI evidence field missing: '+$f)
        }
    }
    $pins=@{
        Schema='2.6.5-BW4k3.ImmutableSourceMapiEvidence.1'
        SuiteId=$SuiteId;TestId=$TestId;CaseName='UnicodePlain'
        PlanSha256=$PlanSha256
        OriginalEvidenceSha256=$SourceEvidenceSha256
        FiveEvidenceSetSha256=$FiveEvidenceSetSha256
        SourceEntryId=[string]$Original.EntryId
        SourceFolderEntryId=[string]$Original.FolderEntryId
        SourceStoreIdSha256=(Get-OPA265BW4jTextHash -Value ([string]$Original.StoreId))
        SourceSize=[string][long]$Original.Size
    }
    foreach($f in $pins.Keys){
        if([string]$Record.$f -cne [string]$pins[$f]){
            throw ('BW4k4 immutable MAPI evidence pin differs: '+$f)
        }
    }
    if($Record.OutlookMoveExecuted -isnot [bool] -or $Record.OutlookMoveExecuted -or
       $Record.ProductionReady -isnot [bool] -or $Record.ProductionReady){
        throw 'BW4k4 immutable MAPI evidence wrongly claims move or production.'
    }
    $dt=[datetimeoffset]::MinValue
    if(-not [datetimeoffset]::TryParse([string]$Record.CapturedUtc,[ref]$dt)){
        throw 'BW4k4 invalid immutable source evidence timestamp.'
    }
    $s=$Record.Snapshot
    if($null -eq $s -or
       [string]$s.SuiteId -cne $SuiteId -or
       [string]$s.TestId -cne $TestId -or
       [string]$s.EntryId -cne [string]$Original.EntryId -or
       [string]$s.FolderEntryId -cne [string]$Original.FolderEntryId -or
       [string]$s.StoreIdSha256 -cne [string]$pins.SourceStoreIdSha256){
        throw 'BW4k4 MAPI snapshot embedded source identity differs.'
    }
    [void](Assert-OPA265BW4k3StableSnapshots -First $s -Second $s)
    $available=0
    foreach($row in @($s.Rows)){
        if($row.Available -isnot [bool]){
            throw 'BW4k4 invalid property availability type.'
        }
        if($row.Available){
            $available++
            if([string]$row.Kind -cnotin @('Binary','DateTimeUtcTicks','Boolean','UnicodeText','SignedInteger','Null') -or
               [string]$row.Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
               [int]$row.ByteCount -lt 0 -or [int]$row.ByteCount -gt 1048576){
                throw 'BW4k4 invalid bounded available MAPI row.'
            }
        } elseif([string]$row.Kind -cne 'UnavailableOrError' -or
                 [string]$row.Sha256 -cne '' -or [string]$row.Scalar -cne ''){
            throw 'BW4k4 invalid unavailable MAPI row.'
        }
    }
    if([int]$s.AvailableCount -ne $available){
        throw 'BW4k4 MAPI availability count differs.'
    }
    return $true
}
function Compare-OPA265BW4k4MapiSnapshots {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Original,
          [Parameter(Mandatory=$true)][object]$Destination)
    [void](Assert-OPA265BW4k3StableSnapshots -First $Original -Second $Original)
    [void](Assert-OPA265BW4k3StableSnapshots -First $Destination -Second $Destination)
    if([string]$Original.SuiteId -cne [string]$Destination.SuiteId -or
       [string]$Original.TestId -cne [string]$Destination.TestId -or
       [string]$Original.EntryId -ceq [string]$Destination.EntryId -or
       [string]$Original.StoreIdSha256 -ceq [string]$Destination.StoreIdSha256){
        throw 'BW4k4 MAPI cross-PST source/destination identity not distinct or mismatched.'
    }
    $out=New-Object 'System.Collections.Generic.List[object]'
    $match=0;$changed=0;$availability=0
    $before=@($Original.Rows);$after=@($Destination.Rows)
    for($i=0;$i -lt $before.Count;$i++){
        $a=$before[$i];$b=$after[$i]
        $state=if([bool]$a.Available -ne [bool]$b.Available){'AvailabilityChanged'}
            elseif(-not [bool]$a.Available){'BothUnavailableOrError'}
            elseif([string]$a.Kind -cne [string]$b.Kind -or
                   [string]$a.Sha256 -cne [string]$b.Sha256 -or
                   [int]$a.ByteCount -ne [int]$b.ByteCount){'Changed'}
            else{'Matched'}
        switch($state){
            'Matched' {$match++}
            'Changed' {$changed++}
            'AvailabilityChanged' {$availability++}
        }
        $out.Add([pscustomobject][ordered]@{
            Name=[string]$a.Name
            Tag=[string]$a.Tag
            Status=$state
            SourceAvailable=[bool]$a.Available
            DestinationAvailable=[bool]$b.Available
            SourceKind=[string]$a.Kind;DestinationKind=[string]$b.Kind
            SourceByteCount=[int]$a.ByteCount;DestinationByteCount=[int]$b.ByteCount
            SourceSha256=[string]$a.Sha256;DestinationSha256=[string]$b.Sha256
            SourceScalar=[string]$a.Scalar;DestinationScalar=[string]$b.Scalar
        })
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k4.BoundedPrePostMapiDifference.1'
        PropertyCount=[int]$out.Count
        MatchedCount=[int]$match
        ChangedCount=[int]$changed
        AvailabilityChangedCount=[int]$availability
        PropertyRows=@($out.ToArray())
        MAPI38ByteCauseProven=$false
        DeltaSizeAccepted=$false
        FullMAPIByteEqualityProven=$false
        ProductionReady=$false
    }
}
