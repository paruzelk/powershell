#requires -Version 5.1
# BW4k7n: exact BW4k7m post-restart archival MAPI/size forensic READ ONLY.
# PR_MESSAGE_FLAGS 0x10000 unknown; PR_STORE_SUPPORT_MASK bit with same value is unrelated.
# PR_MESSAGE_SIZE is provider-estimated, cannot prove cause of -532 without original pre-Move tag.
# No Outlook Move/Save/Delete/Send, no SetProperty, Claim, Journal or production waiver.
function Get-OPA265BW4k7nPins {
    [CmdletBinding()]
    param()
    return [pscustomobject][ordered]@{
        FixtureId='d1a68868-acf5-4c70-860d-5521e1ce2836'
        OriginalEvidenceSha256='36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29'
        IrreversibleClaimSha256='6ba71ce58605f5c53ef0051f7f10919a388357ed3ac3c9e1feab76e71facda58'
        OriginalSourceEntryId='00000000E1878292411BC64291BD506DCEFD2A3504B03C00'
        DestinationEntryId='00000000E88584FF275FEE45B531E472CF338A8A24002000'
        DestinationFolderEntryId='00000000E88584FF275FEE45B531E472CF338A8A82800000'
        OriginalFlags=65555
        ArchiveFlags=17
        OriginalMessageStatus=0
        ArchivedMessageStatus=0
        OriginalMailSize=10489
        ArchivedMailSize=9957
        HistoricalBW4k7gOriginalFlags=65555
        HistoricalBW4k7gArchivedFlags=17
        OldBW4k7gClaimSha256='325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
    }
}
function Get-OPA265BW4k7nProbePlan {
    [CmdletBinding()]
    param()
    # A fixed bounded scalar property inventory; binary RTF/HTML blobs NOT read.
    return @(
        [pscustomobject][ordered]@{Name='PrMessageFlags';Tag='0x0E070003';Kind='Int32';Required=$true;Description='PidTagMessageFlags; provider-managed bits'},
        [pscustomobject][ordered]@{Name='PrMessageStatus';Tag='0x0E170003';Kind='Int32';Required=$true;Description='PidTagMessageStatus; DIFFERENT property from MessageFlags'},
        [pscustomobject][ordered]@{Name='PrHasAttachments';Tag='0x0E1B000B';Kind='Bool';Required=$true;Description='PidTagHasAttachments'},
        [pscustomobject][ordered]@{Name='PrMessageSize';Tag='0x0E080003';Kind='Int32';Required=$false;Description='PidTagMessageSize; provider-computed total, 32-bit'},
        [pscustomobject][ordered]@{Name='PrMessageSizeExtended';Tag='0x0E080014';Kind='Int64';Required=$false;Description='PidTagMessageSizeExtended; same property ID with 64-bit type'},
        [pscustomobject][ordered]@{Name='PrNativeBody';Tag='0x10160003';Kind='Int32';Required=$false;Description='PidTagNativeBody; format classification, not body bytes'},
        [pscustomobject][ordered]@{Name='PrRtfInSync';Tag='0x0E1F000B';Kind='Bool';Required=$false;Description='PidTagRtfInSync; flag, not compressed RTF'},
        [pscustomobject][ordered]@{Name='PrInternetCodepage';Tag='0x3FDE0003';Kind='Int32';Required=$false;Description='PidTagInternetCodepage'},
        [pscustomobject][ordered]@{Name='PrMessageCodepage';Tag='0x3FFD0003';Kind='Int32';Required=$false;Description='PidTagMessageCodepage'},
        [pscustomobject][ordered]@{Name='PrLastModificationTime';Tag='0x30080040';Kind='DateTime';Required=$false;Description='PidTagLastModificationTime; timestamp only'},
        [pscustomobject][ordered]@{Name='PrCreationTime';Tag='0x30070040';Kind='DateTime';Required=$false;Description='PidTagCreationTime; timestamp only'}
    )
}
function Get-OPA265BW4k7nPropertyState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$PropertyAccessor,
          [Parameter(Mandatory=$true)][psobject]$Definition)
    if([string]$Definition.Tag -cnotmatch '^0x[A-Fa-f0-9]{8}$' -or
       [string]$Definition.Kind -cnotin @('Int32','Int64','Bool','DateTime')){
        throw 'BW4k7n invalid bounded property definition.'
    }
    $uri='http://schemas.microsoft.com/mapi/proptag/'+$Definition.Tag
    $available=$true;$raw=$null
    try{$raw=$PropertyAccessor.GetProperty($uri)}
    catch{
        $exception=$_.Exception;$notFound=$false
        while($null -ne $exception){
            if([long]$exception.HResult -eq -2147221233){$notFound=$true}
            $exception=$exception.InnerException
        }
        if(-not $notFound -or [bool]$Definition.Required){
            throw ('BW4k7n required property, provider or access error on '+$Definition.Name+': '+[string]$_.Exception.Message)
        }
        $available=$false
    }
    $v=$null
    if($available){
        if($null -eq $raw){throw ('BW4k7n null MAPI property '+$Definition.Name)}
        switch([string]$Definition.Kind){
            'Int32' {
                if($raw -isnot [int] -or [int]$raw -lt 0){throw ('BW4k7n invalid Int32 '+$Definition.Name)}
                $v=[int]$raw;break
            }
            'Int64' {
                if($raw -isnot [long] -and $raw -isnot [int]){throw ('BW4k7n invalid Int64 '+$Definition.Name)}
                if([long]$raw -lt 0){throw ('BW4k7n negative Int64 '+$Definition.Name)}
                $v=[long]$raw;break
            }
            'Bool' {
                if($raw -isnot [bool]){throw ('BW4k7n invalid Bool '+$Definition.Name)}
                $v=[bool]$raw;break
            }
            'DateTime' {
                if($raw -isnot [datetime] -or ([datetime]$raw).Year -lt 1990){
                    throw ('BW4k7n invalid DateTime '+$Definition.Name)
                }
                $v=[long]([datetime]$raw).ToUniversalTime().Ticks;break
            }
            default {throw 'BW4k7n unsupported property kind.'}
        }
    }
    return [pscustomobject][ordered]@{
        Name=[string]$Definition.Name
        Tag=[string]$Definition.Tag
        Kind=[string]$Definition.Kind
        Required=[bool]$Definition.Required
        Available=[bool]$available
        Value=$v
        Description=[string]$Definition.Description
        OriginalPreMoveValueCaptured=$false
    }
}
function Get-OPA265BW4k7nArchivedProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Mail,
          [Parameter(Mandatory=$true)][string]$StoreId,
          [Parameter(Mandatory=$true)][string]$FolderEntryId,
          [Parameter(Mandatory=$true)][string]$EntryId)
    $p=Get-OPA265BW4k7nPins
    if([int]$Mail.Class -ne 43 -or
       [string]$Mail.EntryID -cne $EntryId -or
       [string]$Mail.Parent.EntryID -cne $FolderEntryId -or
       [string]$Mail.Parent.StoreID -cne $StoreId -or
       $EntryId -cne [string]$p.DestinationEntryId -or
       $FolderEntryId -cne [string]$p.DestinationFolderEntryId){
        throw 'BW4k7n selected archive MailItem/store/folder not equal to pinned original.'
    }
    $size=[long]$Mail.Size
    if($size -lt 1 -or $size -gt 1073741824){throw 'BW4k7n archived MailItem.Size outside bounded range.'}
    $samples=New-Object 'System.Collections.Generic.List[object]'
    foreach($definition in @(Get-OPA265BW4k7nProbePlan)){
        $samples.Add((Get-OPA265BW4k7nPropertyState -PropertyAccessor $Mail.PropertyAccessor -Definition $definition))
    }
    $map=@{}
    foreach($sample in @($samples.ToArray())){
        if($map.ContainsKey([string]$sample.Name)){throw 'BW4k7n duplicate property definition.'}
        $map.Add([string]$sample.Name,$sample)
    }
    if($samples.Count -ne 11 -or
       [int]$map.PrMessageFlags.Value -ne [int]$p.ArchiveFlags -or
       [int]$map.PrMessageStatus.Value -ne [int]$p.ArchivedMessageStatus -or
       -not [bool]$map.PrHasAttachments.Value -or
       $size -ne [long]$p.ArchivedMailSize){
        throw 'BW4k7n archived properties differ from operator post-restart baseline.'
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7n.ArchivedScalarMapiProbe.1'
        FixtureId=[string]$p.FixtureId
        DestinationEntryId=$EntryId
        DestinationFolderEntryId=$FolderEntryId
        ArchiveMailItemSize=$size
        PropertyCount=[int]$samples.Count
        Properties=@($samples.ToArray())
        OutlookMoveExecuted=$false
        HistoricFlagMismatchWaived=$false
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}
function Assert-OPA265BW4k7nStableArchivedProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$First,
          [Parameter(Mandatory=$true)][psobject]$Second)
    if([string]$First.Schema -cne '2.6.5-BW4k7n.ArchivedScalarMapiProbe.1' -or
       [string]$Second.Schema -cne [string]$First.Schema -or
       [string]$Second.FixtureId -cne [string]$First.FixtureId -or
       [string]$Second.DestinationEntryId -cne [string]$First.DestinationEntryId -or
       [long]$Second.ArchiveMailItemSize -ne [long]$First.ArchiveMailItemSize -or
       [int]$First.PropertyCount -ne 11 -or
       [int]$Second.PropertyCount -ne 11 -or
       [bool]$First.OutlookMoveExecuted -or [bool]$Second.OutlookMoveExecuted -or
       [bool]$First.WriterPermit -or [bool]$Second.WriterPermit -or
       [bool]$First.ProductionReady -or [bool]$Second.ProductionReady){
        throw 'BW4k7n archive scalar samples have changed identity or unsafe permission.'
    }
    $a=@($First.Properties);$b=@($Second.Properties)
    if($a.Count -ne 11 -or $b.Count -ne 11){throw 'BW4k7n incomplete MAPI scalar read paths.'}
    for($i=0;$i -lt $a.Count;$i++){
        foreach($field in @('Name','Tag','Kind','Required','Available','Value','OriginalPreMoveValueCaptured')){
            if([string]$a[$i].$field -cne [string]$b[$i].$field){
                throw ('BW4k7n independent MAPI read paths disagree: '+$a[$i].Name+'.'+$field)
            }
        }
    }
    return $true
}
function Get-OPA265BW4k7nClassification {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$ArchivedProbe,
          [Parameter(Mandatory=$true)][psobject]$IndependentArchiveAudit)
    $pins=Get-OPA265BW4k7nPins
    if([string]$ArchivedProbe.Schema -cne '2.6.5-BW4k7n.ArchivedScalarMapiProbe.1' -or
       [string]$ArchivedProbe.FixtureId -cne [string]$pins.FixtureId -or
       [string]$IndependentArchiveAudit.Schema -cne '2.6.5-BW4k7m.IndependentRealPostMoveAudit.1' -or
       [string]$IndependentArchiveAudit.Status -cne 'ContentMatchRawPrMessageFlagsDriftUnclassifiedManualReview' -or
       [string]$IndependentArchiveAudit.VerifiedOriginalEvidenceSha256 -cne [string]$pins.OriginalEvidenceSha256 -or
       [string]$IndependentArchiveAudit.VerifiedOriginalIrreversibleClaimSha256 -cne [string]$pins.IrreversibleClaimSha256 -or
       [int]$IndependentArchiveAudit.SourceMessageIdMatches -ne 0 -or
       [int]$IndependentArchiveAudit.DestinationMessageIdMatches -ne 1 -or
       [string]$IndependentArchiveAudit.DestinationEntryId -cne [string]$pins.DestinationEntryId -or
       -not [bool]$IndependentArchiveAudit.FullSemanticContentMatch -or
       [int]$IndependentArchiveAudit.SemanticFieldMismatchCount -ne 0 -or
       [int]$IndependentArchiveAudit.SourceRawPrMessageFlags -ne [int]$pins.OriginalFlags -or
       [int]$IndependentArchiveAudit.DestinationRawPrMessageFlags -ne [int]$pins.ArchiveFlags -or
       [string]$IndependentArchiveAudit.ChangedMaskHex -cne '0x00010002' -or
       -not [bool]$IndependentArchiveAudit.Unknown0x00010000Changed -or
       -not [bool]$IndependentArchiveAudit.PrMessageStatusEqual -or
       [long]$IndependentArchiveAudit.SourceDiagnosticMessageSize -ne [long]$pins.OriginalMailSize -or
       [long]$IndependentArchiveAudit.DestinationDiagnosticMessageSize -ne [long]$pins.ArchivedMailSize -or
       [bool]$IndependentArchiveAudit.HistoricalRawStateMismatchWaived -or
       [bool]$IndependentArchiveAudit.OutlookMoveExecutedByThisAudit -or
       [bool]$IndependentArchiveAudit.ProductionReady){
        throw 'BW4k7n independent BW4k7m post-restart known observation or immutable pins changed. STOP.'
    }
    $found=@{}
    foreach($s in @($ArchivedProbe.Properties)){
        if($found.ContainsKey([string]$s.Name)){throw 'BW4k7n duplicate property in provider observation.'}
        $found.Add([string]$s.Name,$s)
    }
    if($found.Count -ne 11){throw 'BW4k7n incomplete property inventory.'}
    $size32=$found.PrMessageSize
    $size64=$found.PrMessageSizeExtended
    $size32Matches=$null;$size64Matches=$null
    if([bool]$size32.Available){$size32Matches=([long]$size32.Value -eq [long]$pins.ArchivedMailSize)}
    if([bool]$size64.Available){$size64Matches=([long]$size64.Value -eq [long]$pins.ArchivedMailSize)}
    $delta=[long]$pins.ArchivedMailSize-[long]$pins.OriginalMailSize
    $oldXor=[int]$pins.HistoricalBW4k7gOriginalFlags -bxor [int]$pins.HistoricalBW4k7gArchivedFlags
    $newXor=[int]$pins.OriginalFlags -bxor [int]$pins.ArchiveFlags
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7n.ReadOnlyProviderSizeFlagAttribution.1'
        Status='TwoFixtureFlagsReproducedSizeDeltaObservedCauseStillUnclassified'
        FixtureId=[string]$pins.FixtureId
        OriginalPreMoveEvidenceSha256=[string]$pins.OriginalEvidenceSha256
        OriginalIrreversibleClaimSha256=[string]$pins.IrreversibleClaimSha256
        OldBW4k7gClaimExpectedSha256=[string]$pins.OldBW4k7gClaimSha256
        SourceMessageIdMatches=0;DestinationMessageIdMatches=1
        FullSemanticContentMatch=$true
        SemanticFieldMismatchCount=0
        HistoricalBW4k7gChangedMaskHex=('0x{0:X8}' -f $oldXor)
        NewBW4k7mChangedMaskHex=('0x{0:X8}' -f $newXor)
        ExactFlagDeltaReproducedAcrossTwoFixtures=($oldXor -eq $newXor)
        SourceRawMessageFlags=[int]$pins.OriginalFlags
        DestinationRawMessageFlags=[int]$pins.ArchiveFlags
        KnownMfUnmodified0x00000002Changed=(($newXor -band 2) -ne 0)
        Unknown0x00010000Changed=(($newXor -band 65536) -ne 0)
        RawFlag0x00010000MeaningEstablished=$false
        CrossPropertyStoreHtmlOkEquivalenceAssumed=$false
        PrMessageStatusBeforeMove=[int]$pins.OriginalMessageStatus
        PrMessageStatusAfterMove=[int]$pins.ArchivedMessageStatus
        PrMessageStatusUnchanged=$true
        SourceMailItemSize=[long]$pins.OriginalMailSize
        DestinationMailItemSize=[long]$pins.ArchivedMailSize
        MailItemSizeDeltaBytes=$delta
        SizeDifferenceReproducedAfterOutlookRestart=($delta -eq -532)
        PrMessageSizePresent=[bool]$size32.Available
        PrMessageSizeBytes=$size32.Value
        PrMessageSizeMatchesDestinationMailItemSize=$size32Matches
        PrMessageSizeExtendedPresent=[bool]$size64.Available
        PrMessageSizeExtendedBytes=$size64.Value
        PrMessageSizeExtendedMatchesDestinationMailItemSize=$size64Matches
        OriginalPrMessageSizeCapturedBeforeMove=$false
        OriginalPrMessageSizeExtendedCapturedBeforeMove=$false
        PropertySpecificSizeDeltaCauseProven=$false
        ProviderMetadataNormalizationHypothesisOnly=$true
        SampledScalarPropertyCount=11
        ProviderPropertyInventory=@($ArchivedProbe.Properties)
        NoLargeBinaryMapiPropertiesLoaded=$true
        NoThirdMoveOrWriter=$true
        OriginalEvidenceOrClaimRewritten=$false
        AutomaticRetryAllowed=$false
        ProviderFlagWaiver=$false
        WriterPermit=$false
        ProductionReady=$false
        NextAction='PreserveAllClaimsAndEvidence;ReadOnlyOnly;DoNotInfer0x00010000Or532Cause;NoRetry'
    }
}
