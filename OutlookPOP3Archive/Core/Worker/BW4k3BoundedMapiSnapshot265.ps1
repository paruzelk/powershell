#requires -Version 5.1
# BW4k3 bounded MAPI metadata snapshot for one already witnessed synthetic mail.
# Hashes only, never raw mail fields. No MailItem mutation or archival permit.
. (Join-Path $PSScriptRoot 'BW4k1RealOneShotGuards265.ps1')

function Get-OPA265BW4k3PropertySpecs {
    [CmdletBinding()]
    param()
    # Fixed DASL property set. No unbounded named-property discovery.
    @(
        [pscustomobject]@{Name='PR_MESSAGE_SIZE';Tag='0x0E080003'}
        [pscustomobject]@{Name='PR_MESSAGE_FLAGS';Tag='0x0E070003'}
        [pscustomobject]@{Name='PR_HASATTACH';Tag='0x0E1B000B'}
        [pscustomobject]@{Name='PR_MESSAGE_CLASS';Tag='0x001A001F'}
        [pscustomobject]@{Name='PR_SEARCH_KEY';Tag='0x300B0102'}
        [pscustomobject]@{Name='PR_RECORD_KEY';Tag='0x0FF90102'}
        [pscustomobject]@{Name='PR_SOURCE_KEY';Tag='0x65E00102'}
        [pscustomobject]@{Name='PR_CHANGE_KEY';Tag='0x65E20102'}
        [pscustomobject]@{Name='PR_CREATION_TIME';Tag='0x30070040'}
        [pscustomobject]@{Name='PR_LAST_MODIFICATION_TIME';Tag='0x30080040'}
        [pscustomobject]@{Name='PR_MESSAGE_DELIVERY_TIME';Tag='0x0E060040'}
        [pscustomobject]@{Name='PR_CLIENT_SUBMIT_TIME';Tag='0x00390040'}
        [pscustomobject]@{Name='PR_INTERNET_MESSAGE_ID';Tag='0x1035001F'}
        [pscustomobject]@{Name='PR_TRANSPORT_HEADERS';Tag='0x007D001F'}
        [pscustomobject]@{Name='PR_HTML';Tag='0x10130102'}
    )
}
function ConvertTo-OPA265BW4k3HashedValue {
    [CmdletBinding()]
    param([AllowNull()][object]$Value,
          [ValidateRange(64,2097152)][int]$MaxBytes=1048576)
    if($null -eq $Value){
        return [pscustomobject]@{Kind='Null';ByteCount=0;Sha256='';Scalar=''}
    }
    $kind=''
    $bytes=$null
    $scalar=''
    if($Value -is [byte[]]){
        $kind='Binary'
        $bytes=[byte[]]$Value
    } elseif($Value -is [datetime]){
        $kind='DateTimeUtcTicks'
        $scalar=([datetime]$Value).ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
        $bytes=[Text.Encoding]::UTF8.GetBytes($scalar)
    } elseif($Value -is [bool]){
        $kind='Boolean'
        $scalar=if([bool]$Value){'True'}else{'False'}
        $bytes=[Text.Encoding]::UTF8.GetBytes($scalar)
    } elseif($Value -is [string]){
        $kind='UnicodeText'
        $bytes=[Text.Encoding]::UTF8.GetBytes([string]$Value)
    } elseif($Value -is [int] -or $Value -is [long] -or $Value -is [int16]){
        $kind='SignedInteger'
        $scalar=[Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture)
        $bytes=[Text.Encoding]::UTF8.GetBytes($scalar)
    } else {
        throw ('BW4k3 unsafe or unsupported MAPI value type: '+$Value.GetType().FullName)
    }
    if($bytes.Length -gt $MaxBytes){
        throw ('BW4k3 bounded property exceeds '+$MaxBytes+' bytes.')
    }
    [pscustomobject][ordered]@{
        Kind=$kind
        ByteCount=[int]$bytes.Length
        Sha256=(Get-OPA265BW4jSha256 -Bytes $bytes)
        Scalar=$scalar
    }
}
function Get-OPA265BW4k3MapiSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,
          [Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [Parameter(Mandatory=$true)][string]$ExpectedEntryId,
          [Parameter(Mandatory=$true)][string]$ExpectedFolderEntryId,
          [Parameter(Mandatory=$true)][string]$ExpectedStoreId)
    if([int]$Mail.Class -ne 43 -or
       [string]$Mail.EntryID -cne $ExpectedEntryId -or
       [string]$Mail.Parent.EntryID -cne $ExpectedFolderEntryId -or
       [string]$Mail.Parent.StoreID -cne $ExpectedStoreId){
        throw 'BW4k3 selected source MailItem/Folder/Store ID changed.'
    }
    $reader=$Mail.PropertyAccessor
    if($null -eq $reader){throw 'BW4k3 MAPI PropertyAccessor unavailable.'}
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($spec in @(Get-OPA265BW4k3PropertySpecs)){
        $v=$null
        $available=$false
        try{
            $v=$reader.GetProperty('http://schemas.microsoft.com/mapi/proptag/'+$spec.Tag)
            $available=$true
        }catch{
            # Some MAPI properties are optional or unavailable in a PST.
            # Never infer that an unavailable property is absent.
            $available=$false
        }
        $hashed=if($available){
            ConvertTo-OPA265BW4k3HashedValue -Value $v
        }else{
            [pscustomobject]@{Kind='UnavailableOrError';ByteCount=0;Sha256='';Scalar=''}
        }
        $rows.Add([pscustomobject][ordered]@{
            Name=[string]$spec.Name;Tag=[string]$spec.Tag
            Kind=[string]$hashed.Kind
            Available=[bool]$available
            ByteCount=[int]$hashed.ByteCount
            Sha256=[string]$hashed.Sha256
            Scalar=[string]$hashed.Scalar
        })
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k3.BoundedReadOnlyMapiPropertySnapshot.1'
        SuiteId=$SuiteId;TestId=$TestId
        EntryId=$ExpectedEntryId
        FolderEntryId=$ExpectedFolderEntryId
        StoreIdSha256=(Get-OPA265BW4jTextHash -Value $ExpectedStoreId)
        Rows=@($rows.ToArray())
        PropertyCount=[int]$rows.Count
        AvailableCount=[int]@($rows.ToArray()|Where-Object {$_.Available}).Count
        OutlookMoveExecuted=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k3StableSnapshots {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$First,
          [Parameter(Mandatory=$true)][object]$Second)
    $specs=@(Get-OPA265BW4k3PropertySpecs)
    foreach($s in @($First,$Second)){
        if([string]$s.Schema -cne '2.6.5-BW4k3.BoundedReadOnlyMapiPropertySnapshot.1' -or
           [int]$s.PropertyCount -ne $specs.Count -or
           @($s.Rows).Count -ne $specs.Count -or
           [bool]$s.OutlookMoveExecuted -or [bool]$s.ProductionReady){
            throw 'BW4k3 invalid bounded MAPI snapshot structure/capability.'
        }
        for($i=0;$i -lt $specs.Count;$i++){
            if([string]$s.Rows[$i].Name -cne $specs[$i].Name -or
               [string]$s.Rows[$i].Tag -cne $specs[$i].Tag){
                throw 'BW4k3 MAPI property spec order or tags differ.'
            }
        }
    }
    $a=(ConvertTo-Json -InputObject $First -Depth 7 -Compress)
    $b=(ConvertTo-Json -InputObject $Second -Depth 7 -Compress)
    if($a -cne $b){throw 'BW4k3 two consecutive read-only MAPI snapshots disagree.'}
    return $true
}
function Get-OPA265BW4k3SnapshotPath {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SuiteId,
          [Parameter(Mandatory=$true)][string]$TestId,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $null=Get-OPA265BW4k1ClaimPath -SuiteId $SuiteId -TestId $TestId -LocalAppData $LocalAppData
    Join-Path (Join-Path (Join-Path $LocalAppData 'OutlookPOP3Archive-BW4k3-SourceSnapshots') ('suite-'+$SuiteId)) ('fixture-'+$TestId+'.json')
}
function Write-OPA265BW4k3SnapshotOnce {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Snapshot,
          [Parameter(Mandatory=$true)][string]$Path,
          [string]$LocalAppData=$env:LOCALAPPDATA)
    $expected=Get-OPA265BW4k3SnapshotPath -SuiteId ([string]$Snapshot.SuiteId) -TestId ([string]$Snapshot.TestId) -LocalAppData $LocalAppData
    if(-not [string]::Equals([IO.Path]::GetFullPath($Path),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){
        throw 'BW4k3 immutable evidence output path cannot be redirected.'
    }
    if([string]$Snapshot.Schema -cne '2.6.5-BW4k3.ImmutableSourceMapiEvidence.1' -or
       [string]$Snapshot.PlanSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Snapshot.OriginalEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$Snapshot.FiveEvidenceSetSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $Snapshot.OutlookMoveExecuted -isnot [bool] -or $Snapshot.OutlookMoveExecuted -or
       $Snapshot.ProductionReady -isnot [bool] -or $Snapshot.ProductionReady){
        throw 'BW4k3 unsafe immutable snapshot payload.'
    }
    $parent=[IO.Path]::GetDirectoryName($expected)
    $root=[IO.Path]::GetDirectoryName($parent)
    if(-not [IO.Directory]::Exists($root)){[void][IO.Directory]::CreateDirectory($root)}
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k3 snapshot root reparse point forbidden.'
    }
    if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
    if(([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'BW4k3 snapshot parent reparse point forbidden.'
    }
    # Existing BW4j writer uses CreateNew + Flush(true), UTF8 BOM and never overwrites.
    $written=Write-OPA265BW4jOnce -Object $Snapshot -Path $expected
    return [pscustomobject]@{
        EvidencePath=$written
        EvidenceSha256=(Get-FileHash -LiteralPath $written -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
