#requires -Version 5.1
# BW4k7r - pure in-memory per-year POP3 metadata accumulation and capacity FORECAST.
# Callers must separately verify store, exact BW4k7q folder scope and bounded COM reads.
# No CreatePst, Move, Save, SetProperty, body/attachment reads, Claim or journal writes.

function New-OPA265BW4k7rYearAccumulator {
    [CmdletBinding()]
    param()
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7r.InMemoryYearAccumulator.1'
        Buckets=@{}
        ItemsExamined=[long]0
        MailItemsObserved=[long]0
        DatedMailObserved=[long]0
        UndatedMailObserved=[long]0
        NonMailObserved=[long]0
        FallbackDateObserved=[long]0
        MailItemSizeObservedBytes=[long]0
        LargestMailItemSizeObservedBytes=[long]0
        MutatedPst=$false
    }
}
function Add-OPA265BW4k7rItemObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Accumulator,
        [Parameter(Mandatory=$true)][ValidateSet('Inbox','SentItems','UserMail')][string]$Role,
        [Parameter(Mandatory=$true)][int]$ItemClass,
        [Nullable[int]]$Year=$null,
        [ValidateSet('ReceivedTime','SentOn','Unknown','NonMailItem')][string]$DateField='Unknown',
        [long]$ItemSizeBytes=0
    )
    if($Accumulator.Schema -cne '2.6.5-BW4k7r.InMemoryYearAccumulator.1'){
        throw 'BW4k7r invalid accumulation schema.'
    }
    if($ItemSizeBytes -lt 0 -or $ItemSizeBytes -gt 2147483647){
        throw 'BW4k7r invalid single MailItem.Size metadata.'
    }
    $Accumulator.ItemsExamined=[long]$Accumulator.ItemsExamined+1L
    if($ItemClass -ne 43){
        if($null -ne $Year -or $DateField -cne 'NonMailItem'){
            throw 'BW4k7r non-mail cannot report a mail year.'
        }
        $Accumulator.NonMailObserved=[long]$Accumulator.NonMailObserved+1L
        return
    }
    $Accumulator.MailItemsObserved=[long]$Accumulator.MailItemsObserved+1L
    $Accumulator.MailItemSizeObservedBytes=[long]$Accumulator.MailItemSizeObservedBytes+$ItemSizeBytes
    if($ItemSizeBytes -gt [long]$Accumulator.LargestMailItemSizeObservedBytes){
        $Accumulator.LargestMailItemSizeObservedBytes=[long]$ItemSizeBytes
    }
    if($null -eq $Year){
        if($DateField -cne 'Unknown'){throw 'BW4k7r undated mail requires Unknown date field.'}
        $Accumulator.UndatedMailObserved=[long]$Accumulator.UndatedMailObserved+1L
        return
    }
    if([int]$Year -lt 1990 -or [int]$Year -gt 2100 -or
       $DateField -cnotin @('ReceivedTime','SentOn')){
        throw 'BW4k7r invalid year/date source.'
    }
    if(($Role -ceq 'SentItems' -and $DateField -cne 'SentOn') -or
       ($Role -cne 'SentItems' -and $DateField -cne 'ReceivedTime')){
        $Accumulator.FallbackDateObserved=[long]$Accumulator.FallbackDateObserved+1L
    }
    $key=[string]$Year
    if(-not $Accumulator.Buckets.ContainsKey($key)){
        $Accumulator.Buckets[$key]=[pscustomobject][ordered]@{
            Year=[int]$Year
            InboxMailItems=[long]0
            SentItemsMailItems=[long]0
            UserFolderMailItems=[long]0
            InboxSizeBytes=[long]0
            SentItemsSizeBytes=[long]0
            UserFolderSizeBytes=[long]0
            LargestObservedItemBytes=[long]0
        }
    }
    $b=$Accumulator.Buckets[$key]
    switch($Role){
        'Inbox'{
            $b.InboxMailItems=[long]$b.InboxMailItems+1L
            $b.InboxSizeBytes=[long]$b.InboxSizeBytes+$ItemSizeBytes
        }
        'SentItems'{
            $b.SentItemsMailItems=[long]$b.SentItemsMailItems+1L
            $b.SentItemsSizeBytes=[long]$b.SentItemsSizeBytes+$ItemSizeBytes
        }
        'UserMail'{
            $b.UserFolderMailItems=[long]$b.UserFolderMailItems+1L
            $b.UserFolderSizeBytes=[long]$b.UserFolderSizeBytes+$ItemSizeBytes
        }
    }
    if($ItemSizeBytes -gt [long]$b.LargestObservedItemBytes){
        $b.LargestObservedItemBytes=[long]$ItemSizeBytes
    }
    $Accumulator.DatedMailObserved=[long]$Accumulator.DatedMailObserved+1L
}
function Get-OPA265BW4k7rSafeCapacity {
    [CmdletBinding()]
    param(
        [ValidateRange(104857600,1099511627776)][long]$MaxArchivePstSizeBytes=45000000000,
        [ValidateRange(0,1099511627775)][long]$SafetyMarginBytes=3000000000,
        [ValidateRange(0,200)][int]$EstimatedExpansionPct=25,
        [ValidateRange(0,1048576)][long]$PerMessageOverheadBytes=65536
    )
    if($SafetyMarginBytes -ge $MaxArchivePstSizeBytes){
        throw 'BW4k7r safety margin must be smaller than MaxArchivePstSize.'
    }
    $usable=[long]($MaxArchivePstSizeBytes-$SafetyMarginBytes)
    if($usable -lt 10485760){throw 'BW4k7r usable archive segment is too small.'}
    return [pscustomobject][ordered]@{
        MaxArchivePstSizeBytes=[long]$MaxArchivePstSizeBytes
        SafetyMarginBytes=[long]$SafetyMarginBytes
        UsableEstimatedPayloadBytes=$usable
        EstimatedExpansionPct=[int]$EstimatedExpansionPct
        PerMessageOverheadBytes=[long]$PerMessageOverheadBytes
        RealArchivePstLimitOrRegistryVerified=$false
        PhysicalDestinationPstGrowthProven=$false
        NoMaxPstLimitDisabledOrRegistryWritten=$true
    }
}
function Get-OPA265BW4k7rCapacityPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Accumulator,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][psobject]$Capacity,
        [ValidateRange(1990,2101)][int]$ArchiveBeforeYear=2026,
        [bool]$ScanComplete=$false
    )
    if($Accumulator.Schema -cne '2.6.5-BW4k7r.InMemoryYearAccumulator.1'){
        throw 'BW4k7r invalid accumulation schema for capacity forecast.'
    }
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach($key in @($Accumulator.Buckets.Keys | Sort-Object {[int]$_})){
        $b=$Accumulator.Buckets[$key];$year=[int]$key
        if($year -lt 1990 -or $year -gt 2100){throw 'BW4k7r unexpected year bucket.'}
        $count=[long]$b.InboxMailItems+[long]$b.SentItemsMailItems+[long]$b.UserFolderMailItems
        $observed=[long]$b.InboxSizeBytes+[long]$b.SentItemsSizeBytes+[long]$b.UserFolderSizeBytes
        if($count -lt 1 -or $observed -lt 0){throw 'BW4k7r invalid yearly counter/size.'}
        $projection=[decimal]::Ceiling(([decimal]$observed *
            ([decimal]100+[decimal]$Capacity.EstimatedExpansionPct))/[decimal]100)
        $projection+=[decimal]$count*[decimal]$Capacity.PerMessageOverheadBytes
        if($projection -gt [decimal][long]::MaxValue){throw 'BW4k7r projected yearly bytes overflow.'}
        $forecast=[long]$projection
        $usable=[long]$Capacity.UsableEstimatedPayloadBytes
        $segmentsDecimal=[decimal]::Ceiling([decimal]$forecast/[decimal]$usable)
        if($segmentsDecimal -gt 1000000){throw 'BW4k7r forecast exceeds segment cap.'}
        $segments=[int]$segmentsDecimal
        if($segments -lt 1){$segments=1}
        $largest=[decimal]::Ceiling([decimal][long]$b.LargestObservedItemBytes *
              ([decimal]100+[decimal]$Capacity.EstimatedExpansionPct)/[decimal]100)
        $largest+=[decimal]$Capacity.PerMessageOverheadBytes
        $base=Get-OPA265BW4k7pArchivePlanName -SourcePst $SourcePst -Year $year
        $first=[string]$base
        $second=if($segments -gt 1){
            $base.Substring(0,$base.Length-4)+'-02.pst'
        }else{$null}
        $rows.Add([pscustomobject][ordered]@{
            Year=$year
            InboxMailItems=[long]$b.InboxMailItems
            SentItemsMailItems=[long]$b.SentItemsMailItems
            UserFolderMailItems=[long]$b.UserFolderMailItems
            TotalMailItems=$count
            ObservedMailItemSizeBytes=$observed
            ForecastRequiredBytes=$forecast
            LargestSingleObservedItemSizeBytes=[long]$b.LargestObservedItemBytes
            EstimatedLargestMessageFitsSegment=($largest -le [decimal]$usable)
            ForecastMinimumSegmentsForObservedBytes=$segments
            FirstPlannedArchivePst=$first
            SecondNameIfRolloverEstimated=$second
            ArchiveYearEligible=($year -lt $ArchiveBeforeYear)
            Coverage=if($ScanComplete){'FullyEnumeratedObservedMetadata'}else{'PartialLowerBoundOnly'}
            SegmentCountIsOnlyForecast=$true
            NoArchiveFileCreated=$true
            NoRolloverAllocationCommitted=$true
        })
    }
    return @($rows.ToArray())
}
function Assert-OPA265BW4k7rPlanIntegrity {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Accumulator,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$YearPlan)
    $count=0L;$size=0L
    foreach($row in $YearPlan){
        $count+=[long]$row.TotalMailItems
        $size+=[long]$row.ObservedMailItemSizeBytes
        if(-not $row.NoArchiveFileCreated -or -not $row.SegmentCountIsOnlyForecast){
            throw 'BW4k7r year plan must remain non-writer forecast.'
        }
    }
    if($count -ne [long]$Accumulator.DatedMailObserved -or
       $size -gt [long]$Accumulator.MailItemSizeObservedBytes -or
       [long]$Accumulator.ItemsExamined -ne
         ([long]$Accumulator.MailItemsObserved+[long]$Accumulator.NonMailObserved) -or
       [long]$Accumulator.MailItemsObserved -ne
         ([long]$Accumulator.DatedMailObserved+[long]$Accumulator.UndatedMailObserved)){
        throw 'BW4k7r year/size/undated/non-mail totals do not reconcile.'
    }
    return $true
}
