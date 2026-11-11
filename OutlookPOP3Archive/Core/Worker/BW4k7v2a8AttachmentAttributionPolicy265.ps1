#requires -Version 5.1
# BW4k7v2a8 pure read-only classification of original one-shot flags and attachment observations.
function Test-OPA265BW4k7v2a8FlagsAndAttachments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Snapshot,
        [Parameter(Mandatory=$true)][object]$Manifest,
        [Parameter(Mandatory=$true)][object]$Claim
    )
    $issues=New-Object 'System.Collections.Generic.List[string]'
    if([string]$Manifest.SuiteId -cne [string]$Claim.SuiteId -or
       [string]$Manifest.SourceEntryId -cne [string]$Claim.SourceEntryId -or
       [string]$Manifest.TargetStoreId -cne [string]$Claim.TargetStoreId -or
       [string]$Manifest.TargetFolderId -cne [string]$Claim.TargetFolderId){
        $issues.Add('ClaimAndManifestIdentityMismatch')
    }
    if(-not [bool]$Snapshot.OutlookRestartConfirmed){$issues.Add('NewOutlookProcessNotConfirmed')}
    if([int]$Snapshot.SourceMatches -ne 0 -or [int]$Snapshot.DestinationMatches -ne 1){
        $issues.Add('OriginalSourceZeroDestinationOneNotVerified')
    }
    if(-not [bool]$Snapshot.DestinationIdentityMatchesPinned){
        $issues.Add('DestinationEntryIdOrFolderMismatch')
    }
    if(-not [bool]$Snapshot.SemanticSha256MatchesManifest){
        $issues.Add('SyntheticSemanticContentChanged')
    }
    $sourceFlags=[long]$Manifest.SourceRawMapiFlags
    $destFlags=[long]$Snapshot.DestinationRawMapiFlags
    $xor=($sourceFlags -bxor $destFlags)
    $expectedBit=([long]0x10)
    $isExactHasAttachDelta=($sourceFlags -eq 9 -and $destFlags -eq 25 -and $xor -eq $expectedBit)
    if(-not $isExactHasAttachDelta){$issues.Add('OperatorObservedFlagDeltaNotStable')}
    $delta=[long]$Snapshot.DestinationSizeBytes - [long]$Manifest.SourceSizeBytes
    if([long]$Manifest.SourceSizeBytes -ne 1952 -or
       [long]$Snapshot.DestinationSizeBytes -ne 2076 -or
       $delta -ne 124){$issues.Add('OperatorObservedSizeDeltaNotStable')}
    if(-not [bool]$Snapshot.AttachmentCountReadComplete -or
       [int]$Snapshot.DestinationAttachmentsCount -lt 0 -or
       [int]$Snapshot.DestinationAttachmentsCount -gt 16){
        $issues.Add('AttachmentCountNotVerified')
    }
    if([int]$Snapshot.DestinationAttachmentsCount -ne
       @($Snapshot.AttachmentSummaries).Count){$issues.Add('AttachmentMetadataIncomplete')}
    $prAvailable=[bool]$Snapshot.PrHasAttachAvailable
    $prValue=$false
    if($prAvailable){$prValue=[bool]$Snapshot.PrHasAttach}
    if(-not $prAvailable){$issues.Add('PrHasAttachUnavailable')}
    $flagHasAttach=(($destFlags -band $expectedBit) -ne 0)
    if($prAvailable -and $prValue -ne $flagHasAttach){
        $issues.Add('PrHasAttachDisagreesWithMessageFlag')
    }
    if($prAvailable -and [bool]$Snapshot.AttachmentCountReadComplete -and
       $prValue -ne ([int]$Snapshot.DestinationAttachmentsCount -gt 0)){
        $issues.Add('PrHasAttachDisagreesWithAttachmentCount')
    }
    $kind='AttachmentStateUnknownRequiresManualReview'
    if([bool]$Snapshot.AttachmentCountReadComplete -and
       [int]$Snapshot.DestinationAttachmentsCount -eq 0 -and
       $flagHasAttach){
        $kind='HasAttachBitSetButNoAttachmentObjectsVisible'
    }elseif([bool]$Snapshot.AttachmentCountReadComplete -and
           [int]$Snapshot.DestinationAttachmentsCount -gt 0 -and $flagHasAttach){
        $kind='DestinationAttachmentObjectsExistOriginalPreMoveCountUnknown'
    }elseif([bool]$Snapshot.AttachmentCountReadComplete -and
           [int]$Snapshot.DestinationAttachmentsCount -gt 0 -and -not $flagHasAttach){
        $kind='DestinationAttachmentsWithoutHasAttachFlag'
    }
    $status='ManualReviewRequiredOriginalSEM001StillBlocked'
    if($issues.Count -gt 0){$status='ObservedMismatchOrIncompleteReadRequiresManualReview'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7v2a8.AttachmentAttribution.1'
        Status=$status
        Attribution=$kind
        Reasons=@($issues.ToArray())
        OriginalRawMapiFlags=$sourceFlags
        DestinationRawMapiFlags=$destFlags
        ChangedFlagsXor=$xor
        HasAttachBitIntroduced=$isExactHasAttachDelta
        DestinationFlagHasAttach=$flagHasAttach
        DestinationPrHasAttachAvailable=$prAvailable
        DestinationPrHasAttach=if($prAvailable){$prValue}else{$null}
        DestinationAttachmentsCount=[int]$Snapshot.DestinationAttachmentsCount
        OriginalPreMoveAttachmentCountKnown=$false
        OriginalSizeBytes=[long]$Manifest.SourceSizeBytes
        DestinationSizeBytes=[long]$Snapshot.DestinationSizeBytes
        ObservedSizeDeltaBytes=$delta
        SizeDeltaRootCauseProven=$false
        SemanticContentPreservedByCurrentWitness=[bool]$Snapshot.SemanticSha256MatchesManifest
        PureReadOnlyOneDestinationMessage=$true
        OldMoveMayBeRetried=$false
        AnyMapiFlagDriftWaived=$false
        SEM001ProductionIntegrityProven=$false
        WriterPermit=$false;ProductionReady=$false
    }
}
