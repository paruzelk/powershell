#requires -Version 5.1
# BW4k7h: independent post-Move full user-state SHA discrepancy attribution.
# No Outlook/PST mutation, claim changes, source rebaseline, flag waivers or Move.
. (Join-Path $PSScriptRoot 'BW4k7gPostMoveSemanticReadOnly265.ps1')

function Get-OPA265BW4k7hStateFieldsReadOnly {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail)
    if([int]$Mail.Class -ne 43){
        throw 'BW4k7h requires a MailItem, not another Outlook class.'
    }
    [pscustomobject][ordered]@{
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
}

function Get-OPA265BW4k7hCanonicalStateSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$State,
        [Parameter(Mandatory=$true)][ValidateRange(0,2147483647)][int]$MapiFlags
    )
    $names=@('UnRead','Categories','Importance','Sensitivity','FlagStatus',
        'FlagRequest','ReminderSet','To','CC','BCC')
    if(@($State.PSObject.Properties.Name).Count -ne $names.Count){
        throw 'BW4k7h Outlook user-state field count differs from original canonical serialization.'
    }
    foreach($field in $names){
        if($State.PSObject.Properties.Name -cnotcontains $field){
            throw ('BW4k7h missing user-state field '+$field)
        }
    }
    foreach($flag in @('UnRead','ReminderSet')){
        if($State.$flag -isnot [bool]){throw ('BW4k7h invalid boolean '+$flag)}
    }
    foreach($enum in @('Importance','Sensitivity','FlagStatus')){
        if($State.$enum -isnot [int] -or [int]$State.$enum -lt 0 -or
            [int]$State.$enum -gt 10){
            throw ('BW4k7h invalid bounded user-state enum '+$enum)
        }
    }
    $parts=New-Object 'System.Collections.Generic.List[string]'
    foreach($field in $names){
        $parts.Add((Get-OPA265BW4k7dPart -Text $field))
        $parts.Add((Get-OPA265BW4k7dPart -Text ([string]$State.$field)))
    }
    $parts.Add((Get-OPA265BW4k7dPart -Text ([string]$MapiFlags)))
    return Get-OPA265BW4k7dHash -Text ($parts -join [char]10)
}

function Compare-OPA265BW4k7hRawFlagAttribution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$DestinationState,
        [Parameter(Mandatory=$true)][ValidateRange(0,2147483647)][int]$DestinationFlags,
        [Parameter(Mandatory=$true)][ValidateRange(0,2147483647)][int]$OriginalFlags,
        [Parameter(Mandatory=$true)][string]$OriginalUserStateSha256,
        [Parameter(Mandatory=$true)][string]$ObservedDestinationUserStateSha256
    )
    if($OriginalUserStateSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $ObservedDestinationUserStateSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'BW4k7h SHA-256 inputs must be exact lower-case digests.'
    }
    $actualHash=Get-OPA265BW4k7hCanonicalStateSha256 -State $DestinationState -MapiFlags $DestinationFlags
    if($actualHash -cne $ObservedDestinationUserStateSha256){
        throw 'BW4k7h independent destination serialization does not match prior BW4k7g destination digest.'
    }
    $virtualOriginalFlagsHash=Get-OPA265BW4k7hCanonicalStateSha256 -State $DestinationState -MapiFlags $OriginalFlags
    $xor=($OriginalFlags -bxor $DestinationFlags)
    $readAndAttachPreserved=(($OriginalFlags -band 17) -eq 17 -and
        ($DestinationFlags -band 17) -eq 17 -and -not $DestinationState.UnRead)
    $onlyFlags=($xor -ne 0 -and
        $virtualOriginalFlagsHash -ceq $OriginalUserStateSha256 -and
        $readAndAttachPreserved)
    $alreadyExact=($xor -eq 0 -and $actualHash -ceq $OriginalUserStateSha256)
    $status=if($onlyFlags){'OnlyRawPrMessageFlagsChangedAllCapturedUserFieldsMatch'}
        elseif($alreadyExact){'FullUserStateShaNowMatchesOriginal'}
        elseif(-not $readAndAttachPreserved){'ReadOrAttachmentSemanticBitsChangedNeedsManualReview'}
        else{'CapturedUserFieldOrCanonicalizationDifferenceUnresolved'}
    $bitList=New-Object 'System.Collections.Generic.List[int]'
    for($i=0;$i -le 30;$i++){
        $bit=(1 -shl $i)
        if(($xor -band $bit) -ne 0){$bitList.Add([int]$bit)}
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7h.RawFlagDifferenceAttribution.1'
        Status=$status
        OriginalMapiFlags=[int]$OriginalFlags
        DestinationMapiFlags=[int]$DestinationFlags
        OriginalMapiFlagsHex=('0x{0:X8}' -f $OriginalFlags)
        DestinationMapiFlagsHex=('0x{0:X8}' -f $DestinationFlags)
        ChangedMapiFlagsXor=[int]$xor
        ChangedMapiFlagsXorHex=('0x{0:X8}' -f $xor)
        ChangedFlagBitValues=@($bitList.ToArray())
        SignificantReadAttachBitsMatch=[bool]$readAndAttachPreserved
        DestinationUserStateSha256=$actualHash
        ReconstructedOriginalFlagsUserStateSha256=$virtualOriginalFlagsHash
        OriginalUserStateSha256=$OriginalUserStateSha256
        CapturedOutlookUserFieldsMatchExcludingRawMapiFlags=[bool]($virtualOriginalFlagsHash -ceq $OriginalUserStateSha256)
        OnlyRawMapiFlagsChanged=[bool]$onlyFlags
        ChangedRawFlagBitsSemanticallyClassified=$false
        AdditionalUserFieldDriftRuledOut=[bool]$onlyFlags
        PriorObservedMismatchMayBeReclassifiedAutomatically=$false
        RawRecipientAddressesExposed=$false
        OriginalEvidenceRewritten=$false
        OutlookMoveExecuted=$false
        WriterPermit=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}

function Assert-OPA265BW4k7hStableAttribution {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$First,
          [Parameter(Mandatory=$true)][psobject]$Second)
    if([string]$First.Schema -cne '2.6.5-BW4k7h.RawFlagDifferenceAttribution.1' -or
       @($First.PSObject.Properties.Name).Count -ne @($Second.PSObject.Properties.Name).Count){
        throw 'BW4k7h inconsistent evidence schema.'
    }
    foreach($p in $First.PSObject.Properties.Name){
        if($Second.PSObject.Properties.Name -cnotcontains $p){
            throw ('BW4k7h missing second independent field '+$p)
        }
        if($p -ceq 'ChangedFlagBitValues'){
            if((@($First.ChangedFlagBitValues) -join ',') -cne
               (@($Second.ChangedFlagBitValues) -join ',')){
                throw 'BW4k7h changed raw MAPI flag bits between independent reads.'
            }
        }elseif([string]$First.$p -cne [string]$Second.$p){
            throw ('BW4k7h state drift between independent reads: '+$p)
        }
    }
    return $true
}
