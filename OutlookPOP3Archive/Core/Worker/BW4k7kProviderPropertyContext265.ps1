#requires -Version 5.1
# BW4k7k: pure comparison of separately tagged Outlook MAPI property samples.
# It never grants any flag waiver or writer permission. No COM/file operation.
function Assert-OPA265BW4k7kPropertySample {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Sample)
    if([string]$Sample.Schema -cne '2.6.5-BW4k7k.RawProviderPropertySample.1' -or
       [string]$Sample.MessageFlagsTag -cne '0x0E070003' -or
       [string]$Sample.MessageStatusTag -cne '0x0E170003' -or
       [string]$Sample.HasAttachmentsTag -cne '0x0E1B000B' -or
       [int]$Sample.MessageFlags -ne 17 -or
       $Sample.HasAttachments -isnot [bool] -or
       -not $Sample.HasAttachments -or
       [int]$Sample.AttachmentCount -ne 1 -or
       $Sample.UnRead -isnot [bool] -or $Sample.UnRead -or
       $Sample.MessageStatusAvailable -isnot [bool] -or
       $Sample.PstStorePathMatched -isnot [bool] -or
       -not $Sample.PstStorePathMatched -or
       $Sample.ExactDestinationEntryIdMatched -isnot [bool] -or
       -not $Sample.ExactDestinationEntryIdMatched -or
       [string]$Sample.PropertyOrigin -cne 'ArchivedMailItem.PropertyAccessor'){
        throw 'BW4k7k required archived message identity, READ/HASATTACH or property tag mismatch.'
    }
    if([bool]$Sample.MessageStatusAvailable){
        if($null -eq $Sample.MessageStatus -or
           $Sample.MessageStatus -isnot [int]){
            throw 'BW4k7k PR_MESSAGE_STATUS available but not Int32.'
        }
    }elseif($null -ne $Sample.MessageStatus){
        throw 'BW4k7k unavailable PR_MESSAGE_STATUS must not be treated as observed.'
    }
    return $true
}
function Compare-OPA265BW4k7kPropertySamples {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$First,
        [Parameter(Mandatory=$true)][psobject]$Second
    )
    [void](Assert-OPA265BW4k7kPropertySample -Sample $First)
    [void](Assert-OPA265BW4k7kPropertySample -Sample $Second)
    foreach($name in @('MessageFlags','HasAttachments','AttachmentCount','UnRead',
        'MessageStatusAvailable','MessageStatus','PstStorePathMatched',
        'ExactDestinationEntryIdMatched','PropertyOrigin')){
        $a=$First.$name
        $b=$Second.$name
        if($null -eq $a -and $null -eq $b){continue}
        if($null -eq $a -or $null -eq $b -or $a -cne $b){
            throw ('BW4k7k raw property changed across read-only reads: '+$name)
        }
    }
    # Historical source PR_MESSAGE_STATUS was NOT captured. A current
    # destination-only read cannot establish pre/post semantic equivalence.
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7k.ProviderContextClassification.1'
        Status='ArchivedPstRawPropertiesStableUnknown0x00010000StillBlocked'
        MessageFlagsTag='0x0E070003'
        RawDestinationMessageFlags=17
        OriginalMessageFlagsFromImmutableWitness=65555
        ChangedMaskHex='0x00010002'
        ReadAndHasAttachBitsUnchanged=$true
        MessageStatusTag='0x0E170003'
        DestinationMessageStatusAvailable=[bool]$Second.MessageStatusAvailable
        DestinationMessageStatus=$(if([bool]$Second.MessageStatusAvailable){[int]$Second.MessageStatus}else{$null})
        OriginalMessageStatusCapturedBeforeMove=$false
        MessageStatusComparedToOriginal=$false
        HasAttachmentsTag='0x0E1B000B'
        DestinationHasAttachments=$true
        IndependentlySampledPropertyCount=2
        Original0x00010000MeaningEstablished=$false
        CrossPropertyFlagEquivalenceAssumed=$false
        ProviderSpecificFlagWaiver=$false
        HistoricalRawUserStateHashMismatchReclassified=$false
        OriginalClaimRewritten=$false
        OriginalEvidenceRewritten=$false
        OutlookMoveExecuted=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='PreserveOriginalEvidence;CollectIndependentPstProviderDocumentationOrControlledFreshFixtureEvidence;NoRetry'
    }
}
