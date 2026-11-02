#requires -Version 5.1
# BW4k7b: semantic content integrity is NOT all-MAPI byte equality.
# Diagnostic, read-only only. No PST/COM mutation, consent, retry or writer permit.
. (Join-Path $PSScriptRoot 'BW4k7aAttachmentSizeDriftReadOnly265.ps1')

function Assert-OPA265BW4k7bExactReadOnlySourceDossier {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Report)
    if($Report.Schema -cne '2.6.5-BW4k7a.Attachment1KOriginalSizeDriftReadOnlyReview.1' -or
       [string]$Report.SuiteId -cne '74912f94-d523-4856-9efd-d5528a92426f' -or
       [string]$Report.TestId -cne '87e72fd0-9e77-4098-a403-cbe99870b9e7' -or
       [string]$Report.CaseName -cne 'Attachment1K' -or
       [string]$Report.OriginalSourceEvidenceSha256 -cne '0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0' -or
       [string]$Report.FiveEvidenceSetSha256 -cne 'ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3' -or
       [string]$Report.OriginalSourceEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A35A46D3C00' -or
       [string]$Report.SourceFolderEntryId -cne '00000000E1878292411BC64291BD506DCEFD2A3582800000'){
        throw 'BW4k7b original Attachment1K identity/evidence pins mismatch.'
    }
    if([int]$Report.ReadOnlyWitnessCount -ne 2 -or
       [int]$Report.SourceMapiPropertyCount -ne 15 -or
       [int]$Report.SourceMapiAvailableCount -ne 12 -or
       [long]$Report.OriginalSize -ne 8122 -or
       [long]$Report.CurrentSize -ne 8634 -or
       [long]$Report.DeltaSize -ne 512 -or
       [string]$Report.LiveMapiMessageSize -cne '8634' -or
       [string]$Report.LiveMapiMessageFlags -cne '65555'){
        throw 'BW4k7b observed exact source Size/MAPI witness changed: require fresh read-only investigation.'
    }
    if([long]$Report.OriginalAttachmentByteCount -ne 1024 -or
       [long]$Report.CurrentAttachmentByteCount -ne 1024 -or
       [string]$Report.OriginalAttachmentSha256 -cne '8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9' -or
       [string]$Report.CurrentAttachmentSha256 -cne '8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9' -or
       $Report.AttachmentByteExactMatch -isnot [bool] -or
       -not $Report.AttachmentByteExactMatch){
        throw 'BW4k7b original attachment bytes/length SHA-256 changed: STOP.'
    }
    if([string]$Report.Status -cne 'OnlySourceMailItemSizeDriftUnapproved' -or
       [int]$Report.OtherFieldMismatchCount -ne 0 -or
       @($Report.OtherFieldMismatchNames).Count -ne 0 -or
       $Report.OriginalThreeMoveClaimsUnchanged -isnot [bool] -or
       -not $Report.OriginalThreeMoveClaimsUnchanged -or
       $Report.OriginalSevenHistoricalHashesUnchanged -isnot [bool] -or
       -not $Report.OriginalSevenHistoricalHashesUnchanged -or
       $Report.OriginalWitnessUnchanged -isnot [bool] -or
       -not $Report.OriginalWitnessUnchanged){
        throw 'BW4k7b semantic source witness or immutable historical chain differs.'
    }
    foreach($falseField in @('SizeDriftAccepted','AttemptClaimWritten','OutlookMoveExecuted','CanRetryMove','ProductionReady')){
        if($Report.$falseField -isnot [bool] -or [bool]$Report.$falseField){
            throw ('BW4k7b refused mutable/approval field: '+$falseField)
        }
    }
    return $true
}

function Get-OPA265BW4k7bSourceSemanticVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][psobject]$Report)
    [void](Assert-OPA265BW4k7bExactReadOnlySourceDossier -Report $Report)
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7b.SemanticSourceEvidenceClassification.1'
        Status='ContentWitnessMatchedSourceSizeDriftStillUnapproved'
        SuiteId=[string]$Report.SuiteId
        TestId=[string]$Report.TestId
        OriginalSourceEvidenceSha256=[string]$Report.OriginalSourceEvidenceSha256
        OriginalSize=[long]$Report.OriginalSize
        CurrentSize=[long]$Report.CurrentSize
        DeltaSize=[long]$Report.DeltaSize
        AttachmentSha256=[string]$Report.CurrentAttachmentSha256
        AttachmentByteCount=[long]$Report.CurrentAttachmentByteCount
        AllCapturedContentWitnessFieldsEqual=$true
        OriginalThreeMoveClaimsUnchanged=$true
        SourceMailMoveAttempted=$false
        ContentCoverageIncludesFullRecipients=$false
        SemanticFlagMaskDefinedForProduction=$false
        CrossStoreDestinationVerified=$false
        PhysicalPstDurabilityProven=$false
        SizeDriftAccepted=$false
        NoGlobalSizeWaiver=$true
        AttemptClaimWritten=$false
        WriterPermit=$false
        OutlookMoveExecuted=$false
        CanRetryMove=$false
        ProductionReady=$false
        NextAction='Stop;NoMoveOrCapture;ReviewSemanticPolicyAndExplicitManualDecisionDesign'
    }
}

function Compare-OPA265BW4k7bSyntheticMoveContentReadOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][psobject]$Source,
        [Parameter(Mandatory=$true)][psobject]$Destination,
        [Parameter(Mandatory=$true)][psobject]$Case,
        [Parameter(Mandatory=$true)][string]$SuiteId,
        [ValidateRange(0,100)][int]$SourceMessageIdMatches,
        [ValidateRange(0,100)][int]$DestinationMessageIdMatches,
        [switch]$CompleteSourceAndDestinationScans
    )
    # Only compare known BW4j synthetic witness fields. This is NOT a production policy
    # because BW4j lacks full recipient and user-visible follow-up/flag coverage.
    [void](Assert-OPA265BW4jWitness -Witness $Source -Case $Case -SuiteId $SuiteId)
    [void](Assert-OPA265BW4jWitness -Witness $Destination -Case $Case -SuiteId $SuiteId)
    $c=Compare-OPA265BW4jWitness -Source $Source -Destination $Destination -Case $Case -SuiteId $SuiteId
    $cardinalityOk=([bool]$CompleteSourceAndDestinationScans -and
        $SourceMessageIdMatches -eq 0 -and $DestinationMessageIdMatches -eq 1)
    $contentOk=([bool]$c.SubjectMatches -and [bool]$c.SenderMatches -and
        [bool]$c.BodyMatches -and [bool]$c.HtmlBodyMatches -and
        [bool]$c.ReceivedUtcTicksMatches -and [bool]$c.AttachmentsMatch)
    $identityOk=[bool]$c.IdentityMatches
    $status=if(-not $cardinalityOk){'STOP_IncompleteOrAmbiguousSourceTargetScan'}
        elseif(-not $identityOk){'STOP_StoreOrMessageIdentityMismatch'}
        elseif(-not $contentOk){'STOP_MailContentOrAttachmentMismatch'}
        else{'CapturedSemanticContentMatchedReadOnlyNoWriterPermit'}
    [pscustomobject][ordered]@{
        Schema='2.6.5-BW4k7b.SyntheticCrossPstSemanticComparison.1'
        Status=$status
        SuiteId=$SuiteId
        TestId=[string]$Case.TestId
        SourceMessageIdMatches=$SourceMessageIdMatches
        DestinationMessageIdMatches=$DestinationMessageIdMatches
        CompleteSourceAndDestinationScans=[bool]$CompleteSourceAndDestinationScans
        IdentityMatches=$identityOk
        CapturedContentMatches=$contentOk
        AttachmentBytesMatch=[bool]$c.AttachmentsMatch
        OriginalSize=[long]$c.SourceSize
        DestinationSize=[long]$c.DestinationSize
        DeltaSize=[long]$c.DeltaSize
        SizeEqual=([long]$c.SourceSize -eq [long]$c.DestinationSize)
        BytewiseAllMapiEqualityRequired=$false
        RecipientCoverageComplete=$false
        SemanticFlagCoverageComplete=$false
        CrossStoreIdentityByteEqualityRequired=$false
        ContentOnlyEvidenceInsufficientForProduction=$true
        WriterPermit=$false
        NewMoveAttempted=$false
        AttemptClaimWritten=$false
        CanRetryMove=$false
        ProductionReady=$false
    }
}
