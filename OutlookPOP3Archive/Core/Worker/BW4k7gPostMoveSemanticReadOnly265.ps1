#requires -Version 5.1
# BW4k7g read-only independent post-Move recipient/flag canonical witness.
# No source MailItem assumed after move. Identical ordering and UTF8 hashing as BW4k7d.
. (Join-Path $PSScriptRoot 'BW4k7gOneShotAttachmentGuard265.ps1')
function Get-OPA265BW4k7gDestinationSemantic {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,
          [Parameter(Mandatory=$true)][string]$ExpectedEntryId,
          [Parameter(Mandatory=$true)][string]$ExpectedFolderId,
          [Parameter(Mandatory=$true)][string]$ExpectedStoreId)
    if([int]$Mail.Class -ne 43 -or
       [string]$Mail.EntryID -cne $ExpectedEntryId -or
       [string]$Mail.Parent.EntryID -cne $ExpectedFolderId -or
       [string]$Mail.Parent.StoreID -cne $ExpectedStoreId){
        throw 'BW4k7g archived MailItem exact EntryID, folder, store identity required.'
    }
    $recs=$Mail.Recipients
    $count=[int]$recs.Count
    if($count -lt 1 -or $count -gt 256){throw 'BW4k7g archived recipients missing/out-of-bound.'}
    $parts=New-Object 'System.Collections.Generic.List[string]'
    $types=@(0,0,0)
    for($i=1;$i -le $count;$i++){
        $r=$recs.Item($i)
        $type=[int]$r.Type
        $name=[string]$r.Name
        $address=[string]$r.Address
        if($type -lt 1 -or $type -gt 3 -or
           [string]::IsNullOrWhiteSpace($address) -or
           $name.Length -gt 4096 -or $address.Length -gt 4096){
            throw 'BW4k7g archived recipient unavailable or malformed.'
        }
        $types[$type-1]++
        foreach($part in @([string]$i,[string]$type,$name,$address)){
            $parts.Add((Get-OPA265BW4k7dPart -Text $part))
        }
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
    $attachCount=[int]$Mail.Attachments.Count
    if($attachCount -ne 1 -or
       (($flags -band 1) -ne 0) -ne (-not $state.UnRead) -or
       (($flags -band 16) -ne 0) -ne ($attachCount -gt 0)){
        throw 'BW4k7g destination significant READ/HASATTACH bit consistency failed.'
    }
    $stateNames=@('UnRead','Categories','Importance','Sensitivity','FlagStatus',
        'FlagRequest','ReminderSet','To','CC','BCC')
    $stateParts=New-Object 'System.Collections.Generic.List[string]'
    foreach($name in $stateNames){
        $stateParts.Add((Get-OPA265BW4k7dPart -Text $name))
        $stateParts.Add((Get-OPA265BW4k7dPart -Text ([string]$state.$name)))
    }
    $stateParts.Add((Get-OPA265BW4k7dPart -Text ([string]$flags)))
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7g.DestinationRecipientsStateReadOnly.1'
        DestinationEntryId=$ExpectedEntryId
        RecipientCount=$count
        ToCount=[int]$types[0];CcCount=[int]$types[1];BccCount=[int]$types[2]
        RecipientDigestSha256=(Get-OPA265BW4k7dHash -Text ($parts -join [char]10))
        UserStateDigestSha256=(Get-OPA265BW4k7dHash -Text ($stateParts -join [char]10))
        UnRead=[bool]$state.UnRead;MapiFlags=$flags
        ReadHasAttachBits=($flags -band 17)
        AttachmentCount=$attachCount
        OutlookMoveExecuted=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7gStableDestSemantics {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$First,
          [Parameter(Mandatory=$true)][psobject]$Second)
    if([string]$First.Schema -cne '2.6.5-BW4k7g.DestinationRecipientsStateReadOnly.1' -or
       @($First.PSObject.Properties.Name).Count -ne 14 -or
       @($Second.PSObject.Properties.Name).Count -ne 14 -or
       [string]$First.RecipientDigestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$First.UserStateDigestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [int]$First.RecipientCount -lt 1 -or
       [int]$First.RecipientCount -ne ([int]$First.ToCount+[int]$First.CcCount+[int]$First.BccCount) -or
       [bool]$First.OutlookMoveExecuted -or [bool]$First.ProductionReady -or
       [bool]$Second.OutlookMoveExecuted -or [bool]$Second.ProductionReady){
        throw 'BW4k7g invalid double destination semantics shape.'
    }
    foreach($name in $First.PSObject.Properties.Name){
        if($Second.PSObject.Properties.Name -cnotcontains $name -or
           [string]$First.$name -cne [string]$Second.$name){
            throw ('BW4k7g destination semantic second read drift: '+$name)
        }
    }
    return $true
}
function Assert-OPA265BW4k7gOriginalStaticSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Record)
    if([string]$Record.Schema -cne '2.6.5-BW4k7e.ImmutableRecipientStateSourceSnapshot.1' -or
       [string]$Record.OriginalBW4k7cDecisionSha256 -cne '29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6' -or
       [string]$Record.RecipientDigestSha256 -cne '11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024' -or
       [string]$Record.UserStateDigestSha256 -cne '2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f' -or
       [int]$Record.RecipientCount -ne 1 -or [int]$Record.ToCount -ne 1 -or
       [int]$Record.CcCount -ne 0 -or [int]$Record.BccCount -ne 0 -or
       [int]$Record.MapiFlags -ne 65555 -or [int]$Record.SourceAttachmentCount -ne 1 -or
       [string]$Record.OriginalAttachmentByteSha256 -cne '8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'){
        throw 'BW4k7g immutable original semantic pre-Move snapshot differs.'
    }
    foreach($f in @('RawRecipientAddressesPersisted','FullProductionSemanticFlagCoverageProven',
        'PostMoveRecipientComparisonProven','SourceContentRebaselineAllowed',
        'WriterPermit','OutlookMoveExecuted','AttemptClaimWritten',
        'AutomaticRetryAllowed','ProductionReady')){
        if($Record.$f -isnot [bool] -or $Record.$f){
            throw ('BW4k7g forged semantic source snapshot '+$f)
        }
    }
    if($Record.PreMoveRecipientStateEvidenceCaptured -isnot [bool] -or
       -not $Record.PreMoveRecipientStateEvidenceCaptured){
        throw 'BW4k7g no original semantic pre-Move capture.'
    }
    return $true
}
