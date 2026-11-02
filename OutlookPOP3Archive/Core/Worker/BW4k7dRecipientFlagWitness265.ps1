#requires -Version 5.1
# BW4k7d: read-only bounded recipient and user-state semantic evidence.
. (Join-Path $PSScriptRoot 'BW4k7cExactSourceSizeDecision265.ps1')
function Get-OPA265BW4k7dHash {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    $h=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $h.Dispose() }
}
function Get-OPA265BW4k7dPart {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    if($Text.Length -gt 32768){throw 'BW4k7d semantic field too large.'}
    ([string]$Text.Length)+':'+$Text
}
function Get-OPA265BW4k7dWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Recipients,
        [Parameter(Mandatory=$true)][psobject]$State,
        [Parameter(Mandatory=$true)][int]$MapiFlags,
        [Parameter(Mandatory=$true)][ValidateRange(0,256)][int]$AttachmentCount,
        [Parameter(Mandatory=$true)][string]$SuiteId,
        [Parameter(Mandatory=$true)][string]$TestId,
        [Parameter(Mandatory=$true)][string]$SourceEntryId
    )
    if($SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       $TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       $SourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'){
        throw 'BW4k7d exact original Attachment1K identity required.'
    }
    if($Recipients.Count -lt 1 -or $Recipients.Count -gt 256){
        throw 'BW4k7d recipient count missing or unbounded.'
    }
    $parts=New-Object 'System.Collections.Generic.List[string]'
    $types=@(0,0,0)
    $i=0
    foreach($r in $Recipients){
        $i++
        if($null -eq $r -or @($r.PSObject.Properties.Name).Count -ne 4 -or
           $r.PSObject.Properties.Name -cnotcontains 'Index' -or
           $r.PSObject.Properties.Name -cnotcontains 'Type' -or
           $r.PSObject.Properties.Name -cnotcontains 'Name' -or
           $r.PSObject.Properties.Name -cnotcontains 'Address' -or
           [int]$r.Index -ne $i -or [int]$r.Type -lt 1 -or [int]$r.Type -gt 3){
            throw 'BW4k7d recipient order, type or shape differs.'
        }
        $name=[string]$r.Name; $address=[string]$r.Address
        if([string]::IsNullOrWhiteSpace($address) -or
           $name.Length -gt 4096 -or $address.Length -gt 4096){
            throw 'BW4k7d required recipient Address missing or oversized.'
        }
        $types[[int]$r.Type-1]++
        foreach($part in @([string]$i,[string]$r.Type,$name,$address)){
            $parts.Add((Get-OPA265BW4k7dPart -Text $part))
        }
    }
    $names=@('UnRead','Categories','Importance','Sensitivity',
        'FlagStatus','FlagRequest','ReminderSet','To','CC','BCC')
    if(@($State.PSObject.Properties.Name).Count -ne $names.Count){
        throw 'BW4k7d complete user-state schema required.'
    }
    foreach($name in $names){
        if($State.PSObject.Properties.Name -cnotcontains $name){
            throw ('BW4k7d unavailable state field '+$name)
        }
    }
    foreach($name in @('UnRead','ReminderSet')){
        if($State.$name -isnot [bool]){throw ('BW4k7d boolean state invalid '+$name)}
    }
    foreach($name in @('Importance','Sensitivity','FlagStatus')){
        if($State.$name -isnot [int] -or [int]$State.$name -lt 0 -or
           [int]$State.$name -gt 10){
            throw ('BW4k7d enum state invalid '+$name)
        }
    }
    if($MapiFlags -lt 0){throw 'BW4k7d invalid MAPI flags.'}
    $readBit=(($MapiFlags -band 1) -ne 0)
    $attachmentBit=(($MapiFlags -band 16) -ne 0)
    if($readBit -ne (-not [bool]$State.UnRead) -or
       $attachmentBit -ne ($AttachmentCount -gt 0)){
        throw 'BW4k7d read/attachment MAPI semantic mask disagrees with COM.'
    }
    $stateParts=New-Object 'System.Collections.Generic.List[string]'
    foreach($name in $names){
        $stateParts.Add((Get-OPA265BW4k7dPart -Text $name))
        $stateParts.Add((Get-OPA265BW4k7dPart -Text ([string]$State.$name)))
    }
    $stateParts.Add((Get-OPA265BW4k7dPart -Text ([string]$MapiFlags)))
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7d.RecipientsFlagsReadOnly.1'
        SuiteId=$SuiteId;TestId=$TestId;SourceEntryId=$SourceEntryId
        RecipientCount=[int]$Recipients.Count
        ToCount=[int]$types[0];CcCount=[int]$types[1];BccCount=[int]$types[2]
        RecipientDigestSha256=(Get-OPA265BW4k7dHash -Text ($parts -join [char]10))
        UserStateDigestSha256=(Get-OPA265BW4k7dHash -Text ($stateParts -join [char]10))
        UnRead=[bool]$State.UnRead
        HasAttachment=$attachmentBit
        AttachmentCount=$AttachmentCount
        MapiFlags=$MapiFlags;SignificantReadAndAttachMask=17
        CompleteRecipientEnumeration=$true
        PreMoveSemanticSnapshotPersisted=$false
        ProductionSignificantFlagCoverageProven=$false
        PostMoveRecipientsCompared=$false
        WriterPermit=$false;OutlookMoveExecuted=$false;ProductionReady=$false
    }
}
function Get-OPA265BW4k7dLiveWitness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Mail,
        [Parameter(Mandatory=$true)][string]$SuiteId,
        [Parameter(Mandatory=$true)][string]$TestId,
        [Parameter(Mandatory=$true)][string]$SourceEntryId
    )
    if([int]$Mail.Class -ne 43 -or [string]$Mail.EntryID -cne $SourceEntryId){
        throw 'BW4k7d original MailItem changed.'
    }
    $rc=$Mail.Recipients; $count=[int]$rc.Count
    if($count -lt 1 -or $count -gt 256){throw 'BW4k7d COM recipient count out of bound.'}
    $rows=New-Object 'System.Collections.Generic.List[object]'
    for($i=1;$i -le $count;$i++){
        $r=$rc.Item($i)
        $rows.Add([pscustomobject][ordered]@{
            Index=[int]$i;Type=[int]$r.Type;Name=[string]$r.Name;Address=[string]$r.Address
        })
    }
    $state=[pscustomobject][ordered]@{
        UnRead=[bool]$Mail.UnRead
        Categories=[string]$Mail.Categories
        Importance=[int]$Mail.Importance
        Sensitivity=[int]$Mail.Sensitivity
        FlagStatus=[int]$Mail.FlagStatus
        FlagRequest=[string]$Mail.FlagRequest
        ReminderSet=[bool]$Mail.ReminderSet
        To=[string]$Mail.To
        CC=[string]$Mail.CC
        BCC=[string]$Mail.BCC
    }
    $flags=[int]$Mail.PropertyAccessor.GetProperty('http://schemas.microsoft.com/mapi/proptag/0x0E070003')
    $opts=@{
        Recipients=$rows.ToArray();State=$state;MapiFlags=$flags
        AttachmentCount=[int]$Mail.Attachments.Count
        SuiteId=$SuiteId;TestId=$TestId;SourceEntryId=$SourceEntryId
    }
    Get-OPA265BW4k7dWitness @opts
}
function Assert-OPA265BW4k7dStableWitness {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$First,
          [Parameter(Mandatory=$true)][psobject]$Second)
    $fields=@('Schema','SuiteId','TestId','SourceEntryId','RecipientCount',
        'ToCount','CcCount','BccCount','RecipientDigestSha256','UserStateDigestSha256',
        'UnRead','HasAttachment','AttachmentCount','MapiFlags',
        'SignificantReadAndAttachMask','CompleteRecipientEnumeration',
        'PreMoveSemanticSnapshotPersisted','ProductionSignificantFlagCoverageProven',
        'PostMoveRecipientsCompared','WriterPermit','OutlookMoveExecuted','ProductionReady')
    foreach($r in @($First,$Second)){
        if(@($r.PSObject.Properties.Name).Count -ne $fields.Count -or
           [string]$r.Schema -cne '2.6.5-BW4k7d.RecipientsFlagsReadOnly.1' -or
           [string]$r.RecipientDigestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [string]$r.UserStateDigestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           [int]$r.RecipientCount -lt 1 -or
           [int]$r.RecipientCount -ne ([int]$r.ToCount+[int]$r.CcCount+[int]$r.BccCount)){
            throw 'BW4k7d incomplete read-only evidence.'
        }
        foreach($name in $fields){
            if($r.PSObject.Properties.Name -cnotcontains $name){
                throw ('BW4k7d missing field '+$name)
            }
        }
        if($r.CompleteRecipientEnumeration -isnot [bool] -or -not $r.CompleteRecipientEnumeration){
            throw 'BW4k7d incomplete recipients.'
        }
        foreach($name in @('PreMoveSemanticSnapshotPersisted',
            'ProductionSignificantFlagCoverageProven','PostMoveRecipientsCompared',
            'WriterPermit','OutlookMoveExecuted','ProductionReady')){
            if($r.$name -isnot [bool] -or $r.$name){
                throw ('BW4k7d unauthorized elevation '+$name)
            }
        }
    }
    foreach($name in $fields){
        if([string]$First.$name -cne [string]$Second.$name){
            throw ('BW4k7d two live reads differ: '+$name)
        }
    }
    return $true
}
