#requires -Version 5.1
# BW4k7p - bounded POP3 PST FOLDER SCOPE and YEAR PLAN, READ ONLY.
# Names are display-only; real Sent/Inbox/Outbox identity is Store.GetDefaultFolder(5/6/4).
# A folder is NEVER classified as Sent merely because its name says "Отправленные".
# No claim, journal, PST creation, set, save, delete, move or production enablement.

function Get-OPA265BW4k7pFolderRole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$EntryId,
        [string]$InboxEntryId='',
        [string]$SentEntryId='',
        [string]$OutboxEntryId='',
        [string[]]$ExcludedSystemEntryIds=@(),
        [ValidateSet('Root','Inbox','SentItems','OutboxExcluded','SystemExcluded','UserMail','NonMailExcluded','Unresolved')]
        [string]$ParentRole='Root',
        [ValidateRange(0,20)][int]$DefaultItemType=0
    )
    if([string]::IsNullOrWhiteSpace($EntryId)){throw 'BW4k7p requires folder EntryID.'}
    # ID comparison is case-insensitive for Outlook opaque hex tokens.
    if($InboxEntryId -and $EntryId -ieq $InboxEntryId){return 'Inbox'}
    if($SentEntryId -and $EntryId -ieq $SentEntryId){return 'SentItems'}
    if($OutboxEntryId -and $EntryId -ieq $OutboxEntryId){return 'OutboxExcluded'}
    foreach($x in $ExcludedSystemEntryIds){if($x -and $EntryId -ieq $x){return 'SystemExcluded'}}
    if($ParentRole -in @('OutboxExcluded','SystemExcluded','NonMailExcluded','Unresolved')){
        return $ParentRole
    }
    if($DefaultItemType -ne 0){return 'NonMailExcluded'}
    return 'UserMail'
}
function Get-OPA265BW4k7pYear {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Item,
          [Parameter(Mandatory=$true)][ValidateSet('Inbox','SentItems','UserMail')][string]$Role)
    if([int]$Item.Class -ne 43){
        return [pscustomobject]@{IsMail=$false;Year=$null;DateField='NonMailItem';DateAvailable=$false}
    }
    $sequence=if($Role -ceq 'SentItems'){@('SentOn','ReceivedTime')}else{@('ReceivedTime','SentOn')}
    foreach($field in $sequence){
        $dt=$null
        try{$dt=[datetime]$Item.$field}catch{continue}
        if($null -ne $dt -and $dt.Year -ge 1990 -and $dt.Year -le 2100){
            return [pscustomobject]@{IsMail=$true;Year=[int]$dt.Year;DateField=$field;DateAvailable=$true}
        }
    }
    return [pscustomobject]@{IsMail=$true;Year=$null;DateField='Unknown';DateAvailable=$false}
}
function Get-OPA265BW4k7pArchivePlanName {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][ValidateRange(1990,2100)][int]$Year)
    if([IO.Path]::GetExtension($SourcePst) -ine '.pst' -or
       -not [IO.Path]::IsPathRooted($SourcePst) -or
       $SourcePst.StartsWith('\\',[StringComparison]::Ordinal)){
        throw 'BW4k7p source PST path must be absolute local .pst.'
    }
    $stem=[IO.Path]::GetFileNameWithoutExtension($SourcePst)
    if($stem -notmatch '^[^\\/:*?"<>|]{1,180}$'){throw 'BW4k7p unsafe PST stem.'}
    return ($stem+'.Archive-'+$Year+'.pst')
}
function New-OPA265BW4k7pYearPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][hashtable]$YearCounts,
          [bool]$ScanComplete=$false)
    $result=New-Object 'System.Collections.Generic.List[object]'
    foreach($k in @($YearCounts.Keys | Sort-Object)){
        $year=[int]$k
        if($year -lt 1990 -or $year -gt 2100 -or [long]$YearCounts[$k] -lt 0){
            throw 'BW4k7p invalid year/count.'
        }
        $result.Add([pscustomobject][ordered]@{
            Year=$year;ObservedMailItems=[long]$YearCounts[$k]
            ProposedArchiveName=(Get-OPA265BW4k7pArchivePlanName -SourcePst $SourcePst -Year $year)
            Coverage=if($ScanComplete){'CompleteObservedMailItems'}else{'PartialObservedOnly'}
            ArchivePstCreated=$false
            ArchivePstCapacityValidated=$false
            RolloverSegmentDecided=$false
        })
    }
    return @($result.ToArray())
}
function Assert-OPA265BW4k7pReadOnlyLimits {
    [CmdletBinding()]
    param([ValidateRange(1,20000)][int]$MaxFolders=5000,
          [ValidateRange(1,1000000)][int]$MaxTotalItems=5000,
          [ValidateRange(1,1000000)][int]$MaxItemsPerFolder=5000,
          [ValidateRange(1,200)][int]$MaxAttachmentsPerMail=50)
    return [pscustomobject]@{
        MaxFolders=$MaxFolders
        MaxTotalItems=$MaxTotalItems
        MaxItemsPerFolder=$MaxItemsPerFolder
        MaxAttachmentsPerMail=$MaxAttachmentsPerMail
    }
}
function Get-OPA265BW4k7pDefaultFolderMap {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Store)
    $storeId=[string]$Store.StoreID
    if([string]::IsNullOrWhiteSpace($storeId)){throw 'BW4k7p missing source store identity.'}
    $ids=[ordered]@{Inbox='';SentItems='';Outbox='';SystemExcluded=@()}
    foreach($t in @(
        @('Inbox',6),@('SentItems',5),@('Outbox',4),
        @('SystemExcluded',3),@('SystemExcluded',16),@('SystemExcluded',23),
        @('SystemExcluded',9),@('SystemExcluded',10),@('SystemExcluded',11),
        @('SystemExcluded',12),@('SystemExcluded',13),@('SystemExcluded',20),
        @('SystemExcluded',25),@('SystemExcluded',28))){
        $folder=$null
        try{$folder=$Store.GetDefaultFolder([int]$t[1])}
        catch{
            # Non-required defaults may be missing; they are NEVER guessed by localized names.
            if($t[0] -in @('Inbox','SentItems')){throw ('BW4k7p required POP3 '+$t[0]+' resolution failed: '+$_.Exception.Message)}
            continue
        }
        if($null -eq $folder){
            if($t[0] -eq 'Inbox'){throw 'BW4k7p POP3 Inbox default is not available.'}
            continue
        }
        if([string]$folder.StoreID -cne $storeId -or
           [string]::IsNullOrWhiteSpace([string]$folder.EntryID)){
            if($t[0] -in @('Inbox','SentItems','Outbox')){
                throw ('BW4k7p '+$t[0]+' default folder belongs to another Outlook store; STOP.')
            }
            continue
        }
        $fid=[string]$folder.EntryID
        if($t[0] -eq 'SystemExcluded'){$ids.SystemExcluded+=@($fid)}
        else{$ids[$t[0]]=$fid}
    }
    if($ids.Inbox -and $ids.SentItems -and $ids.Inbox -ieq $ids.SentItems){
        throw 'BW4k7p POP3 Inbox and Sent resolve to same folder.'
    }
    if($ids.SentItems -and $ids.Outbox -and $ids.SentItems -ieq $ids.Outbox){
        throw 'BW4k7p Sent and Outbox must never be the same store folder.'
    }
    return [pscustomobject]$ids
}
function Get-OPA265BW4k7pFolderItems {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Folder,
          [Parameter(Mandatory=$true)][ValidateSet('Inbox','SentItems','UserMail')][string]$Role,
          [Parameter(Mandatory=$true)][ValidateRange(1,1000000)][int]$MaxItems,
          [ValidateRange(1,200)][int]$MaxAttachmentsPerMail=50,
          [switch]$InspectAttachments)
    $items=$Folder.Items
    $start=[int]$items.Count
    if($start -lt 0){throw 'BW4k7p negative folder item count.'}
    $limit=[Math]::Min($start,$MaxItems)
    $buckets=@{};$nonMail=0;$undated=0;$fallback=0;$withAttach=0;$attachCount=0L
    $sizeSum=0L;$approxAttBytes=0L;$attachmentsIncomplete=$false
    $item=$null
    if($limit -gt 0){$item=$items.GetFirst()}
    for($i=0;$i -lt $limit;$i++){
        if($null -eq $item){throw 'BW4k7p Outlook enumeration ended before capped item count.'}
        $date=Get-OPA265BW4k7pYear -Item $item -Role $Role
        if(-not $date.IsMail){$nonMail++}
        else{
            if(-not $date.DateAvailable){$undated++}
            else {
                $key=[string]$date.Year
                if(-not $buckets.ContainsKey($key)){$buckets[$key]=0L}
                $buckets[$key]=[long]$buckets[$key]+1
                if(($Role -eq 'SentItems' -and $date.DateField -ne 'SentOn') -or
                   ($Role -ne 'SentItems' -and $date.DateField -ne 'ReceivedTime')){$fallback++}
            }
            $sz=[long]$item.Size
            if($sz -lt 0 -or $sz -gt 2147483648){throw 'BW4k7p mail size out of safe metadata range.'}
            $sizeSum=[long]$sizeSum+$sz
            if($InspectAttachments){
                $a=$item.Attachments
                $n=[int]$a.Count
                if($n -lt 0){throw 'BW4k7p negative attachment count.'}
                if($n -gt 0){$withAttach++}
                $attachCount=[long]$attachCount+[long]$n
                if($n -gt $MaxAttachmentsPerMail){$attachmentsIncomplete=$true}
                else {
                    for($j=1;$j -le $n;$j++){
                        $att=$a.Item($j)
                        $attSize=[long]$att.Size
                        if($attSize -lt 0 -or $attSize -gt 2147483648){
                            throw 'BW4k7p attachment metadata size out of safe range.'
                        }
                        $approxAttBytes+=$attSize
                    }
                }
            }
        }
        if($i -lt $limit-1){$item=$items.GetNext()}
    }
    $end=[int]$items.Count
    if($end -ne $start){throw 'BW4k7p folder items changed during read-only scan. Counts no longer stable.'}
    return [pscustomobject][ordered]@{
        ObservedFolderItemCount=$start
        ScannedItems=$limit
        FullyScanned=($limit -eq $start)
        PartialReason=if($limit -lt $start){'BoundedLimitReached'}else{'None'}
        NonMailObserved=$nonMail
        MailDateUnavailableObserved=$undated
        SentOrReceivedFallbackObserved=$fallback
        YearCounts=$buckets
        MailSizeObservedBytes=$sizeSum
        AttachmentMetadataInspected=[bool]$InspectAttachments
        MailWithAttachmentsObserved=if($InspectAttachments){$withAttach}else{$null}
        AttachmentCountObserved=if($InspectAttachments){$attachCount}else{$null}
        AttachmentSizeObservedBytes=if($InspectAttachments){$approxAttBytes}else{$null}
        AttachmentSizeEvidenceComplete=([bool]$InspectAttachments -and -not $attachmentsIncomplete -and $limit -eq $start)
        MessageBodiesOrAttachmentPayloadsRead=$false
    }
}
