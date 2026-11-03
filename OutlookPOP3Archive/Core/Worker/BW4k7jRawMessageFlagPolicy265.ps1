#requires -Version 5.1
# BW4k7j: pure, read-only PR_MESSAGE_FLAGS bit investigation.
# Microsoft [MS-OXCMSG] 2.2.1.6 documents the listed PR_MESSAGE_FLAGS bits.
# 0x00010000 is NOT identified in that table. Never infer meaning from
# identically-numbered flags in PR_STORE_SUPPORT_MASK or PR_MESSAGE_STATUS.
# No write-capable functions and no broad mask-based semantic waiver.
function Get-OPA265BW4k7jDocumentedFlagCatalog {
    [CmdletBinding()]
    param()
    @(
        [pscustomobject][ordered]@{Bit=1;Hex='0x00000001';Name='mfRead';Category='ReadState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=2;Hex='0x00000002';Name='mfUnmodified';Category='ProviderModificationState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=4;Hex='0x00000004';Name='mfSubmitted';Category='SubmissionState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=8;Hex='0x00000008';Name='mfUnsent';Category='SubmissionState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=16;Hex='0x00000010';Name='mfHasAttach';Category='AttachmentState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=32;Hex='0x00000020';Name='mfFromMe';Category='SenderContext';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=64;Hex='0x00000040';Name='mfFAI';Category='AssociatedMessageState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=128;Hex='0x00000080';Name='mfResend';Category='ResendState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=256;Hex='0x00000100';Name='mfNotifyRead';Category='ReceiptRequestState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=512;Hex='0x00000200';Name='mfNotifyUnread';Category='ReceiptRequestState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=1024;Hex='0x00000400';Name='mfEverRead';Category='ReadHistoryState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=8192;Hex='0x00002000';Name='mfInternet';Category='OriginState';Source='MS-OXCMSG:2.2.1.6'},
        [pscustomobject][ordered]@{Bit=32768;Hex='0x00008000';Name='mfUntrusted';Category='OriginState';Source='MS-OXCMSG:2.2.1.6'}
    )
}
function Get-OPA265BW4k7jFlagDifference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateRange(0,2147483647)][int]$OriginalFlags,
        [Parameter(Mandatory=$true)][ValidateRange(0,2147483647)][int]$DestinationFlags
    )
    $catalog=@(Get-OPA265BW4k7jDocumentedFlagCatalog)
    $lookup=@{}
    foreach($entry in $catalog){
        if($lookup.ContainsKey([int]$entry.Bit)){throw 'BW4k7j duplicate documented flag bit.'}
        $lookup.Add([int]$entry.Bit,$entry)
    }
    $xor=($OriginalFlags -bxor $DestinationFlags)
    $changes=New-Object 'System.Collections.Generic.List[object]'
    $undocumented=New-Object 'System.Collections.Generic.List[int]'
    $provider=0;$other=0
    for($index=0;$index -le 30;$index++){
        $bit=[int](1 -shl $index)
        if(($xor -band $bit) -eq 0){continue}
        $before=(($OriginalFlags -band $bit) -ne 0)
        $after=(($DestinationFlags -band $bit) -ne 0)
        if($lookup.ContainsKey($bit)){
            $flag=$lookup[$bit]
            $name=[string]$flag.Name;$category=[string]$flag.Category
            $source=[string]$flag.Source
            $documented=$true
            if($bit -eq 2){$provider++}else{$other++}
        }else{
            $name='UnspecifiedInReviewedMsOxcmsgTable'
            $category='UnclassifiedRawMessageFlag'
            $source='No documented name in reviewed MS-OXCMSG:2.2.1.6 table'
            $documented=$false;$undocumented.Add($bit)
        }
        $changes.Add([pscustomobject][ordered]@{
            BitDecimal=$bit
            BitHex=('0x{0:X8}' -f $bit)
            FlagName=$name
            Classification=$category
            DocumentedForPidTagMessageFlags=$documented
            SetBeforeMove=$before
            SetAfterMove=$after
            SourceReference=$source
            AutomaticallyWaived=$false
        })
    }
    $readAttachBefore=($OriginalFlags -band 17)
    $readAttachAfter=($DestinationFlags -band 17)
    $readAttachStable=($readAttachBefore -eq $readAttachAfter)
    $documentedOtherChanged=($other -gt 0)
    $onlyUnmodified=($xor -eq 2)
    $exactOriginal=($OriginalFlags -eq 65555 -and $DestinationFlags -eq 17)
    $status=if(-not $readAttachStable){
        'ReadOrAttachmentSemanticBitChangedStop'
    }elseif($documentedOtherChanged){
        'DocumentedOperationalOrIdentityFlagChangedStop'
    }elseif($undocumented.Count -gt 0){
        'DocumentedModificationBitAndUnspecifiedRawBitRequireManualReview'
    }elseif($onlyUnmodified){
        'DocumentedModificationBitChangedNeedsExplicitPolicyReview'
    }elseif($xor -eq 0){
        'IdenticalRawMessageFlagsReadOnly'
    }else{
        'UnclassifiedMessageFlagChangeStop'
    }
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7j.RawMAPIFlagClassification.1'
        Status=$status
        PropertyTag='0x0E070003'
        PropertyName='PidTagMessageFlags'
        OriginalFlags=[int]$OriginalFlags
        DestinationFlags=[int]$DestinationFlags
        OriginalFlagsHex=('0x{0:X8}' -f $OriginalFlags)
        DestinationFlagsHex=('0x{0:X8}' -f $DestinationFlags)
        ChangedMaskDecimal=[int]$xor
        ChangedMaskHex=('0x{0:X8}' -f $xor)
        ChangedBitCount=[int]$changes.Count
        ChangedBits=@($changes.ToArray())
        KnownModificationStateChangeCount=[int]$provider
        OtherDocumentedChangedBitCount=[int]$other
        UnspecifiedChangedBitCount=[int]$undocumented.Count
        UnspecifiedChangedBitValues=@($undocumented.ToArray())
        ReadAndHasAttachBitsUnchanged=[bool]$readAttachStable
        ExactOriginalBW4k7hObservation=[bool]$exactOriginal
        CrossPropertyBitValueNameReuseAccepted=$false
        StoreHtmlOk0x10000BelongsToOtherProperty=$true
        MessageStatusHighBitsAreDifferentProperty=$true
        OriginalFullRawUserStateShaMismatchAccepted=$false
        ProviderModificationBitGloballyWaived=$false
        UnspecifiedRawBitsWaived=$false
        PermanentSemanticPolicyPermit=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7jExactOriginalClassification {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Result)
    if([string]$Result.Schema -cne '2.6.5-BW4k7j.RawMAPIFlagClassification.1' -or
       [string]$Result.Status -cne 'DocumentedModificationBitAndUnspecifiedRawBitRequireManualReview' -or
       [string]$Result.PropertyTag -cne '0x0E070003' -or
       [int]$Result.OriginalFlags -ne 65555 -or
       [int]$Result.DestinationFlags -ne 17 -or
       [int]$Result.ChangedMaskDecimal -ne 65538 -or
       [string]$Result.ChangedMaskHex -cne '0x00010002' -or
       [int]$Result.ChangedBitCount -ne 2 -or
       [int]$Result.KnownModificationStateChangeCount -ne 1 -or
       [int]$Result.OtherDocumentedChangedBitCount -ne 0 -or
       [int]$Result.UnspecifiedChangedBitCount -ne 1 -or
       @($Result.UnspecifiedChangedBitValues).Count -ne 1 -or
       [int]$Result.UnspecifiedChangedBitValues[0] -ne 65536 -or
       -not [bool]$Result.ReadAndHasAttachBitsUnchanged -or
       -not [bool]$Result.ExactOriginalBW4k7hObservation -or
       [bool]$Result.CrossPropertyBitValueNameReuseAccepted -or
       -not [bool]$Result.StoreHtmlOk0x10000BelongsToOtherProperty -or
       -not [bool]$Result.MessageStatusHighBitsAreDifferentProperty){
        throw 'BW4k7j unexpected flag delta or cross-property constant name reuse.'
    }
    foreach($f in @('OriginalFullRawUserStateShaMismatchAccepted',
        'ProviderModificationBitGloballyWaived','UnspecifiedRawBitsWaived',
        'PermanentSemanticPolicyPermit','AutomaticRetryAllowed','WriterPermit','ProductionReady')){
        if($Result.$f -isnot [bool] -or $Result.$f){
            throw ('BW4k7j forbidden semantic waiver/permit: '+$f)
        }
    }
    if([int]$Result.ChangedBits[0].BitDecimal -ne 2 -or
       [string]$Result.ChangedBits[0].FlagName -cne 'mfUnmodified' -or
       -not [bool]$Result.ChangedBits[0].DocumentedForPidTagMessageFlags -or
       [int]$Result.ChangedBits[1].BitDecimal -ne 65536 -or
       [bool]$Result.ChangedBits[1].DocumentedForPidTagMessageFlags){
        throw 'BW4k7j original exact changed bit classification must remain documented 0x2 and unresolved 0x10000.'
    }
    foreach($bit in @($Result.ChangedBits)){
        if([bool]$bit.AutomaticallyWaived -or -not [bool]$bit.SetBeforeMove -or [bool]$bit.SetAfterMove){
            throw 'BW4k7j cannot auto-waive or change observed direction of raw bit delta.'
        }
    }
    return $true
}
