#requires -Version 5.1
# ARCH2d4 evidence-first forensic policy. No Outlook COM, no PST mount,
# no modification of legacy ARCH2d / ARCH2c4 immutable evidence.
. (Join-Path $PSScriptRoot '../Archive/ARCH2dBatchCore.ps1')

function Read-OPA265ARCH2d4UnanchoredJson {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not [IO.File]::Exists($Path)){throw 'ARCH2d4 immutable item evidence missing.'}
    if(([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'ARCH2d4 evidence file reparse point: manual review.'
    }
    $file=Get-Item -LiteralPath $Path -Force
    if([int64]$file.Length -le 0 -or [int64]$file.Length -gt 1048576){
        throw 'ARCH2d4 evidence empty or exceeds bounded 1MB.'
    }
    # SHA calculated from CURRENT bytes. This is internal consistency only:
    # the old ARCH2d per-item receipts have no independent external hash pin.
    $currentSha=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    $record=Read-OPA265ARCH2c4JsonSealed -Path $Path -ExpectedSha256 $currentSha
    if($null -eq $record -or $record -is [array]){
        throw 'ARCH2d4 malformed or nonobject item journal JSON.'
    }
    return [pscustomobject][ordered]@{
        Record=$record
        CurrentSha256=$currentSha
        ExternallyPinned=$false
    }
}

function Read-OPA265ARCH2d4Evidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Layout,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [Parameter(Mandatory=$true)][string]$ManifestSha256,
        [Parameter(Mandatory=$true)][string]$BatchClaimSha256
    )
    # Current operator-supplied manifest/global SHA anchors are mandatory.
    # Do not replace them with local recomputation if mismatched.
    if($ManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
       $BatchClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d4 exact operator-pinned 64-character manifest/global SHA256 required.'
    }
    $manifest=Read-OPA265ARCH2c4JsonSealed -Path ([string]$Layout.ManifestPath) -ExpectedSha256 $ManifestSha256
    [void](Assert-OPA265ARCH2dManifest -Manifest $manifest -Layout $Layout -SourcePst $SourcePst -SourceStoreId ([string]$manifest.SourceStoreId) -SourceFolderId ([string]$manifest.SourceFolderId))
    if([string]$manifest.ArchiveStoreId -cnotmatch '^.{10,}$' -or
       [string]$manifest.ArchiveFolderId -cnotmatch '^.{10,}$' -or
       [int]$manifest.PrepareOutlookProcessId -le 0 -or
       [int64]$manifest.PrepareOutlookProcessStartUtcTicks -le 0){
        throw 'ARCH2d4 manifest provider IDs/process epoch incomplete.'
    }
    $intent=Read-OPA265ARCH2c4JsonSealed -Path ([string]$Layout.IntentPath) -ExpectedSha256 ([string]$manifest.IntentSha256)
    if([string]$intent.Schema -cne '2.6.5-ARCH2d.PrepareIntent.1' -or
       [string]$intent.RunId -cne [string]$Layout.RunId -or
       [string]$intent.SourcePst -cne $SourcePst -or
       [string]$intent.DestinationPst -cne [string]$Layout.ArchivePst -or
       [string]$intent.SourceStoreId -cne [string]$manifest.SourceStoreId -or
       [string]$intent.SourceFolderId -cne [string]$manifest.SourceFolderId -or
       [int]$intent.PlannedCount -ne 10 -or
       -not [bool]$intent.NewTargetOnly -or
       [bool]$intent.AutomaticPrepareRetryAllowed -or
       @($intent.SourceEntryIds).Count -ne 10){
        throw 'ARCH2d4 original anchored preparation intent mismatch.'
    }
    for($i=0;$i -lt 10;$i++){
        if([string]$intent.SourceEntryIds[$i] -cne [string]$manifest.Items[$i].SourceEntryId){
            throw 'ARCH2d4 source order inconsistent with original sealed prepare intent.'
        }
    }
    $global=Read-OPA265ARCH2c4JsonSealed -Path ([string]$Layout.GlobalClaimPath) -ExpectedSha256 $BatchClaimSha256
    if([string]$global.Schema -cne '2.6.5-ARCH2d.BatchOnceClaim.1' -or
       [string]$global.RunId -cne [string]$Layout.RunId -or
       [string]$global.ManifestSha256 -cne $ManifestSha256 -or
       [string]$global.OriginalSourcePst -cne $SourcePst -or
       [int]$global.PlannedCount -ne 10 -or
       [int]$global.MoveProcessId -le 0 -or
       [int64]$global.MoveProcessStartUtcTicks -le 0 -or
       -not [bool]$global.OneBatchAttemptClaimedBeforeFirstComMove -or
       [bool]$global.AutomaticResumeOrRetryAllowed -or
       [bool]$global.ProductionReady){
        throw 'ARCH2d4 operator-pinned global claim inconsistent or unsafe.'
    }
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $problems=New-Object 'System.Collections.Generic.List[string]'
    $returnEntryIds=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $claimGap=$false
    $returnGap=$false
    for($i=1;$i -le 10;$i++){
        $original=$manifest.Items[$i-1]
        $claimPath=Get-OPA265ARCH2dItemClaimPath -Layout $Layout -Ordinal $i
        $returnPath=Get-OPA265ARCH2dItemClaimPath -Layout $Layout -Ordinal $i -Kind Return
        $claimExists=[IO.File]::Exists($claimPath)
        $receiptExists=[IO.File]::Exists($returnPath)
        $issues=New-Object 'System.Collections.Generic.List[string]'
        $claimStatus='Missing';$returnStatus='Missing'
        $claimSha='';$receiptSha='';$returnedId=''
        if($claimExists){
            try{
                $c=Read-OPA265ARCH2d4UnanchoredJson -Path $claimPath
                $claim=$c.Record
                $claimSha=[string]$c.CurrentSha256
                if([string]$claim.Schema -cne '2.6.5-ARCH2d.IndividualMoveClaim.1' -or
                   [string]$claim.RunId -cne [string]$Layout.RunId -or
                   [int]$claim.Ordinal -ne $i -or
                   [string]$claim.ManifestSha256 -cne $ManifestSha256 -or
                   [string]$claim.BatchClaimSha256 -cne $BatchClaimSha256 -or
                   [string]$claim.SourceEntryId -cne [string]$original.SourceEntryId -or
                   [string]$claim.SourceStoreId -cne [string]$manifest.SourceStoreId -or
                   [string]$claim.ArchiveStoreId -cne [string]$manifest.ArchiveStoreId -or
                   [string]$claim.ArchiveFolderId -cne [string]$manifest.ArchiveFolderId -or
                   -not [bool]$claim.ClaimedBeforeComMove -or
                   [bool]$claim.AutomaticRetryAllowed){
                    throw 'IndividualMoveClaim fields do not match pinned original batch.'
                }
                $claimStatus='ValidInternalLinkage'
            }catch{
                $claimStatus='Invalid'
                $issues.Add('InvalidOrTornItemClaim')|Out-Null
            }
            if($claimGap){$issues.Add('NonPrefixClaimSequence')|Out-Null}
        }else{$claimGap=$true}
        if($receiptExists){
            if(-not $claimExists){$issues.Add('ReceiptWithoutItemClaim')|Out-Null}
            if($returnGap){$issues.Add('NonPrefixReturnSequence')|Out-Null}
            try{
                $r=Read-OPA265ARCH2d4UnanchoredJson -Path $returnPath
                $receipt=$r.Record
                $receiptSha=[string]$r.CurrentSha256
                $returnedId=[string]$receipt.DestinationEntryId
                if([string]$receipt.Schema -cne '2.6.5-ARCH2d.MoveReturnObservation.1' -or
                   [string]$receipt.RunId -cne [string]$Layout.RunId -or
                   [int]$receipt.Ordinal -ne $i -or
                   [string]$receipt.ClaimSha256 -cne $claimSha -or
                   $claimStatus -cne 'ValidInternalLinkage' -or
                   $returnedId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
                   [string]$receipt.DestinationStoreId -cne [string]$manifest.ArchiveStoreId -or
                   [string]$receipt.DestinationFolderId -cne [string]$manifest.ArchiveFolderId -or
                   -not [bool]$receipt.IndependentPostRestartVerificationRequired -or
                   [bool]$receipt.ProductionReady){
                    throw 'MoveReturnObservation invalid, unlinked or claims wrong destination.'
                }
                if(-not $returnEntryIds.Add($returnedId)){
                    throw 'Two different receipts refer to the same returned destination EntryID.'
                }
                $returnStatus='ValidInternalLinkage'
            }catch{
                $returnStatus='Invalid'
                $issues.Add('InvalidOrTornReturnReceipt')|Out-Null
            }
        }else{$returnGap=$true}
        if($receiptExists -and -not $claimExists){
            $issues.Add('UnclaimedReceiptCannotAuthorizeMove')|Out-Null
        }
        $status=if($issues.Count -gt 0){'InvalidEvidenceManualReview'
        }elseif($claimStatus -ceq 'ValidInternalLinkage' -and
                 $returnStatus -ceq 'ValidInternalLinkage'){'ClaimAndReturnLinked'
        }elseif($claimStatus -ceq 'ValidInternalLinkage'){'ClaimWithoutValidReturn'
        }else{'NotClaimed'}
        foreach($issue in @($issues.ToArray())){
            $problems.Add(('Item'+('{0:D2}' -f $i)+':'+$issue))|Out-Null
        }
        $rows.Add([pscustomobject][ordered]@{
            Ordinal=$i
            SourceEntryId=[string]$original.SourceEntryId
            SemanticSignature=[string]$original.SemanticSignature
            ClaimExists=$claimExists
            ClaimStatus=$claimStatus
            ClaimCurrentSha256=$claimSha
            ReturnExists=$receiptExists
            ReturnStatus=$returnStatus
            ReturnCurrentSha256=$receiptSha
            ReturnedDestinationEntryId=$returnedId
            EvidenceStatus=$status
            IssueCodes=@($issues.ToArray())
            ClaimsOrReceiptsExternallyHashPinned=$false
        })|Out-Null
    }
    $pairs=@($rows.ToArray()|Where-Object {$_.EvidenceStatus -ceq 'ClaimAndReturnLinked'}).Count
    $claims=@($rows.ToArray()|Where-Object {$_.ClaimExists}).Count
    $receipts=@($rows.ToArray()|Where-Object {$_.ReturnExists}).Count
    $validAll=($pairs -eq 10 -and $problems.Count -eq 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d4.ReadOnlyEvidenceInventory.1'
        RunId=[string]$Layout.RunId
        Layout=$Layout
        Manifest=$manifest
        GlobalClaim=$global
        ManifestSha256=$ManifestSha256
        BatchClaimSha256=$BatchClaimSha256
        PreparationIntentHashMatched=$true
        GlobalClaimHashMatched=$true
        AnchoredManifestAndGlobalClaim=$true
        Claimed=$claims
        Receipts=$receipts
        LinkedPairs=$pairs
        Planned=10
        Issues=@($problems.ToArray())
        Items=@($rows.ToArray())
        AllTenClaimAndReturnInternallyConsistent=$validAll
        PerItemReceiptsExternallyHashPinned=$false
        AutomaticRetryAllowed=$false
        ProductionReady=$false
    }
}

function Get-OPA265ARCH2d4ItemDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$EvidenceItem,
        [ValidateSet(-1,0,1)][int]$SourcePresence,
        [ValidateRange(0,128)][int]$MatchingDestinationCount,
        [bool]$FullSemanticContentMatches=$false,
        [bool]$DestinationScanComplete=$true
    )
    $issueCodes=New-Object 'System.Collections.Generic.List[string]'
    foreach($code in @($EvidenceItem.IssueCodes)){$issueCodes.Add([string]$code)|Out-Null}
    $claim=[string]$EvidenceItem.ClaimStatus
    $receipt=[string]$EvidenceItem.ReturnStatus
    $confirmedMoved=($SourcePresence -eq 0 -and $MatchingDestinationCount -eq 1 -and
        $FullSemanticContentMatches -and $DestinationScanComplete)
    $untouched=($SourcePresence -eq 1 -and $MatchingDestinationCount -eq 0 -and
        $DestinationScanComplete)
    if($SourcePresence -eq -1){$issueCodes.Add('UnknownSourceEntryIdProvider')|Out-Null}
    if(-not $DestinationScanComplete){$issueCodes.Add('DestinationScanIncomplete')|Out-Null}
    if($MatchingDestinationCount -gt 1){$issueCodes.Add('DuplicateDestinationSignature')|Out-Null}
    if($MatchingDestinationCount -eq 1 -and -not $FullSemanticContentMatches){
        $issueCodes.Add('DestinationSemanticDifference')|Out-Null
    }
    if($SourcePresence -eq 1 -and $MatchingDestinationCount -gt 0){
        $issueCodes.Add('OriginalStillPresentAndDestinationMatches')|Out-Null
    }
    if($SourcePresence -eq 0 -and $MatchingDestinationCount -eq 0){
        $issueCodes.Add('OriginalMissingAndNoArchiveMatch')|Out-Null
    }
    $status='ManualReviewRequired'
    if($confirmedMoved -and $issueCodes.Count -eq 0 -and
       $claim -ceq 'ValidInternalLinkage' -and $receipt -ceq 'ValidInternalLinkage'){
        $status='MovedContentMatchedReceiptLinked'
    }elseif($confirmedMoved -and $issueCodes.Count -eq 0 -and
       $claim -ceq 'ValidInternalLinkage' -and $receipt -ceq 'Missing'){
        $status='MovedContentMatchedReceiptMissingManualReview'
        $issueCodes.Add('MoveReturnReceiptMissing')|Out-Null
    }elseif($untouched -and $issueCodes.Count -eq 0 -and
       $claim -ceq 'Missing' -and $receipt -ceq 'Missing'){
        $status='UnattemptedSourcePresentNoRetryPermit'
    }elseif($untouched -and $claim -ne 'Missing'){
        $issueCodes.Add('ClaimedButOriginalStillPresent')|Out-Null
    }elseif($confirmedMoved -and $claim -eq 'Missing'){
        $issueCodes.Add('MovedWithoutIndividualClaim')|Out-Null
    }elseif($confirmedMoved -and $receipt -eq 'Invalid'){
        $issueCodes.Add('MovedButInvalidReturnReceipt')|Out-Null
    }
    return [pscustomobject][ordered]@{
        Ordinal=[int]$EvidenceItem.Ordinal
        Status=$status
        SourceOriginalEntryIdState=$SourcePresence
        DestinationMatchCount=$MatchingDestinationCount
        FullSemanticContentMatches=$FullSemanticContentMatches
        ClaimStatus=$claim
        ReturnStatus=$receipt
        IssueCodes=@($issueCodes.ToArray())
        ConfirmedMoved=($status -ceq 'MovedContentMatchedReceiptLinked')
        ContentMatchedWithReceiptException=($status -ceq 'MovedContentMatchedReceiptMissingManualReview')
        Untouched=($status -ceq 'UnattemptedSourcePresentNoRetryPermit')
        AutomaticRetryAllowed=$false
    }
}

function Get-OPA265ARCH2d4BatchDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$ItemDecisions,
        [Parameter(Mandatory=$true)][object]$Evidence,
        [ValidateRange(0,128)][int]$DestinationCount,
        [ValidateRange(0,128)][int]$UnexpectedDestinationCount,
        [ValidateRange(0,128)][int]$DuplicateDestinationCount,
        [bool]$OutlookRestartConfirmed
    )
    if(@($ItemDecisions).Count -ne 10){throw 'ARCH2d4 exactly ten original items required for independent classification.'}
    $verified=@($ItemDecisions|Where-Object {$_.ConfirmedMoved}).Count
    $unattempted=@($ItemDecisions|Where-Object {$_.Untouched}).Count
    $receiptExceptions=@($ItemDecisions|Where-Object {$_.ContentMatchedWithReceiptException}).Count
    $manual=10-$verified-$unattempted
    $issueCount=@($ItemDecisions|Where-Object {@($_.IssueCodes).Count -gt 0}).Count
    $validEvidence=(@($Evidence.Issues).Count -eq 0 -and
        [bool]$Evidence.PreparationIntentHashMatched -and
        [bool]$Evidence.GlobalClaimHashMatched)
    $goodDestination=($UnexpectedDestinationCount -eq 0 -and $DuplicateDestinationCount -eq 0 -and
        $DestinationCount -eq ($verified+$receiptExceptions))
    $full=$validEvidence -and $OutlookRestartConfirmed -and $goodDestination -and
        $verified -eq 10 -and $manual -eq 0 -and $issueCount -eq 0
    $partial=$validEvidence -and $OutlookRestartConfirmed -and $goodDestination -and
        $verified+$unattempted -eq 10 -and $manual -eq 0 -and $issueCount -eq 0
    $status=if($full){'AllTenLiveSemanticMatchesReceiptsInternallyConsistent'
    }elseif($partial){'PartialBatchReadOnlyClassifiedNoResumePermit'
    }else{'ManualReviewRequiredNoAutomaticRetry'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d4.IndependentBatchDecision.1'
        Status=$status
        FullyVerified=$full
        VerifiedWithLinkedReceipt=$verified
        MatchedContentWithMissingReceipt=$receiptExceptions
        Unattempted=$unattempted
        RequiresManualReview=$manual
        Expected=10
        ArchiveFolderObservedCount=$DestinationCount
        UnexpectedDestinationCount=$UnexpectedDestinationCount
        DuplicateDestinationCount=$DuplicateDestinationCount
        ItemIssueCount=$issueCount
        ManifestAndGlobalClaimExternallyPinned=$true
        ClaimsAndReceiptsOnlyInternallyConsistent=$true
        ClaimsAndReceiptsExternallyHashPinned=$false
        OutlookRestartConfirmed=$OutlookRestartConfirmed
        AutomaticRetryAllowed=$false
        WriterPermit=$false
        ArchiveResumeAutoRemainClosed=$true
        ProductionReady=$false
    }
}
