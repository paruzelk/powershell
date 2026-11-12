#requires -Version 5.1
# ARCH2d4: independent, read-only inspection of existing Outlook sessions.
# No Outlook Save, Move, Copy, Delete, AddStoreEx, PST mount or journal write.
# ARCH2b attachment hashing uses temporary protected by-value SaveAsFile
# copies (cleaned by ARCH2c2), never saves back to a mailbox.
. (Join-Path $PSScriptRoot 'ARCH2d4EvidencePolicy.ps1')

function Get-OPA265ARCH2d4PublicEvidenceReport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Evidence)
    $issues=@($Evidence.Issues)
    $status=if($issues.Count -gt 0){'EvidenceInconsistentManualReview'
    }elseif([bool]$Evidence.AllTenClaimAndReturnInternallyConsistent){
        'TenClaimsAndReceiptsInternallyConsistentNoLiveVerification'
    }else{'PartialEvidenceInventoryNoRetryPermit'}
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2d4.EvidenceReport.1'
        Status=$status
        RunId=[string]$Evidence.RunId
        ManifestSha256=[string]$Evidence.ManifestSha256
        BatchClaimSha256=[string]$Evidence.BatchClaimSha256
        ManifestAndGlobalClaimHashMatched=$true
        PreparationIntentHashMatched=$true
        Planned=10
        Claimed=[int]$Evidence.Claimed
        Receipts=[int]$Evidence.Receipts
        LinkedPairs=[int]$Evidence.LinkedPairs
        IssueCodes=$issues
        PerItemReceiptsExternallyHashPinned=$false
        Items=@($Evidence.Items)
        OutlookContacted=$false
        SourceOrArchivePstOpenedByTool=$false
        JournalOrPstWritesPerformedByTool=$false
        AutomaticRetryAllowed=$false
        ArchiveResumeAutoRemainClosed=$true
        ProductionReady=$false
    }
}

function Invoke-OPA265ARCH2d4Audit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Plan','Evidence','LiveAudit')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [string]$ManifestSha256='',
        [string]$BatchClaimSha256=''
    )
    $layout=Get-OPA265ARCH2dLayout -RunId $RunId -LocalAppData $env:LOCALAPPDATA
    [void](Assert-OPA265ARCH2dLayout -Layout $layout)
    $source=[IO.Path]::GetFullPath($SourcePst)
    if([IO.Path]::GetFileName($source) -cne 'info@stios.ru.pst' -or
       $source.StartsWith('\\')){
        throw 'ARCH2d4 only accepts canonical original POP3 PST filename.'
    }
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d4.Plan.1'
            Status='ReadOnlyExistingTenMessageForensicPlanNoOutlookNoDiskWrites'
            RunId=$RunId;SourcePst=$source
            ArchivePst=[string]$layout.ArchivePst
            EvidenceModeUsesOutlook=$false
            LiveAuditRequiresExistingOutlookAndAttachedArchive=$true
            HistoricClaimCanBeRetried=$false
            AutomaticRetryAllowed=$false
            ArchiveResumeAutoRemainClosed=$true
            ProductionReady=$false
        }
    }
    $evidence=Read-OPA265ARCH2d4Evidence -Layout $layout -SourcePst $source -ManifestSha256 $ManifestSha256 -BatchClaimSha256 $BatchClaimSha256
    if($Mode -ceq 'Evidence'){
        return (Get-OPA265ARCH2d4PublicEvidenceReport -Evidence $evidence)
    }

    # Only AFTER the operator-pinned evidence has been verified is existing
    # Outlook attached. No AddStoreEx; archive PST MUST already be attached.
    $source=Assert-OPA265ARCH2c4SourcePst -SourcePst $source -Layout $layout
    if(-not [IO.File]::Exists([string]$layout.ArchivePst)){
        throw 'ARCH2d4 destination PST missing; never recreate or attach in LiveAudit.'
    }
    $session=$null;$target=$null;$items=$null
    try{
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst $source
        if($null -eq $session.ArchiveStore){
            throw 'ARCH2d4 archive must ALREADY be attached in Outlook; no mounting permitted.'
        }
        if([string]$session.SourceStore.StoreID -cne [string]$evidence.Manifest.SourceStoreId -or
           [string]$session.Inbox.EntryID -cne [string]$evidence.Manifest.SourceFolderId){
            throw 'ARCH2d4 live source store/Inbox ID differs from externally anchored manifest.'
        }
        $target=Get-OPA265ARCH2dTargetFolder -Session $session -Layout $layout -Manifest $evidence.Manifest
        $restart=([int]$session.OutlookProcessId -ne [int]$evidence.GlobalClaim.MoveProcessId -and
            [int64]$session.OutlookProcessStartUtcTicks -ne [int64]$evidence.GlobalClaim.MoveProcessStartUtcTicks)
        if(-not $restart){
            throw 'ARCH2d4 forensic LiveAudit requires confirmed fresh Outlook process after original batch claim.'
        }
        # One complete bounded scan of target folder, no search order assumptions
        # and no use of MailItem.Size as integrity proof.
        $items=$target.Items
        $targetCount=[int]$items.Count
        if($targetCount -lt 0 -or $targetCount -gt 128){
            throw 'ARCH2d4 destination folder count out of safe diagnostic bound.'
        }
        $manifestSignatures=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($m in @($evidence.Manifest.Items)){
            [void]$manifestSignatures.Add([string]$m.SemanticSignature)
        }
        $found=@{}
        $unexpected=0;$duplicate=0
        for($i=1;$i -le $targetCount;$i++){
            $d=$null
            try{
                $d=$items.Item($i)
                if($null -eq $d -or [int]$d.Class -ne 43){
                    $unexpected++
                    continue
                }
                # Full semantic capture: Body, HTML, ordered recipients, flags
                # and SHA256 of real attachment bytes via protected TEMP copies.
                $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $d
                $sig=Get-OPA265ARCH2dSemanticSignature -Witness $w
                if(-not $manifestSignatures.Contains($sig)){
                    $unexpected++
                }elseif($found.ContainsKey($sig)){
                    $duplicate++
                    $found[$sig].Count=[int]$found[$sig].Count+1
                }else{
                    $found[$sig]=[pscustomobject]@{
                        Count=1
                        Witness=$w
                        CurrentEntryId=[string]$d.EntryID
                    }
                }
            }finally{Release-OPA265ARCH2c4Com -Object $d}
        }
        $decisions=New-Object 'System.Collections.Generic.List[object]'
        for($i=0;$i -lt 10;$i++){
            $m=$evidence.Manifest.Items[$i]
            $ev=$evidence.Items[$i]
            $presence=Get-OPA265ARCH2dSourcePresence -Namespace $session.Namespace -EntryId ([string]$m.SourceEntryId) -StoreId ([string]$evidence.Manifest.SourceStoreId) -FolderId ([string]$evidence.Manifest.SourceFolderId)
            $matching=0;$matches=$false;$returnedIdStillMatches=$null
            if($found.ContainsKey([string]$m.SemanticSignature)){
                $f=$found[[string]$m.SemanticSignature]
                $matching=[int]$f.Count
                # Full original pre-move witness comparison, not only selector.
                $comparison=Compare-OPA265ARCH2bMailSemanticWitness -Source $m.SourceSemanticWitness -Destination $f.Witness
                $matches=[bool]$comparison.CriticalContentMatches
                if([string]$ev.ReturnStatus -ceq 'ValidInternalLinkage'){
                    $returnedIdStillMatches=([string]$ev.ReturnedDestinationEntryId -ceq [string]$f.CurrentEntryId)
                    # Not an integrity gate: cross-PST EntryID may change on
                    # reopening. Full semantic identity + folder are normative.
                }
            }
            $itemResult=Get-OPA265ARCH2d4ItemDecision -EvidenceItem $ev -SourcePresence $presence -MatchingDestinationCount $matching -FullSemanticContentMatches $matches -DestinationScanComplete $true
            $decisions.Add([pscustomobject][ordered]@{
                Ordinal=[int]$ev.Ordinal
                Status=[string]$itemResult.Status
                SourceEntryId=[string]$m.SourceEntryId
                SourceOriginalEntryIdState=$presence
                MatchingArchiveItems=$matching
                FullSemanticContentMatches=$matches
                ClaimStatus=[string]$ev.ClaimStatus
                ReturnStatus=[string]$ev.ReturnStatus
                ClaimCurrentSha256=[string]$ev.ClaimCurrentSha256
                ReturnCurrentSha256=[string]$ev.ReturnCurrentSha256
                ReturnedEntryIdStillMatchesAfterRestart=$returnedIdStillMatches
                IssueCodes=@($itemResult.IssueCodes)
                ConfirmedMoved=[bool]$itemResult.ConfirmedMoved
                Untouched=[bool]$itemResult.Untouched
                AutomaticRetryAllowed=$false
            })|Out-Null
        }
        $decision=Get-OPA265ARCH2d4BatchDecision -ItemDecisions @($decisions.ToArray()) -Evidence $evidence -DestinationCount $targetCount -UnexpectedDestinationCount $unexpected -DuplicateDestinationCount $duplicate -OutlookRestartConfirmed $restart
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d4.RealReadOnlyForensicReport.1'
            Status=[string]$decision.Status
            RunId=$RunId
            ManifestSha256=$ManifestSha256
            BatchClaimSha256=$BatchClaimSha256
            ArchivePst=[string]$layout.ArchivePst
            VerifiedWithLinkedReceipt=[int]$decision.VerifiedWithLinkedReceipt
            MatchedContentWithMissingReceipt=[int]$decision.MatchedContentWithMissingReceipt
            Unattempted=[int]$decision.Unattempted
            RequiresManualReview=[int]$decision.RequiresManualReview
            Planned=10
            ArchiveFolderObservedCount=$targetCount
            UnexpectedDestinationCount=$unexpected
            DuplicateDestinationCount=$duplicate
            OutlookRestartConfirmed=$restart
            ManifestAndGlobalClaimExternallyPinned=$true
            PerItemReceiptsExternallyHashPinned=$false
            PerItemReceiptsInternallyLinkedBySha256=$true
            ImportantNote='Item receipts have no original independent SHA256 anchor. Current SHA256 and field linkage prove internal consistency only, not historical immutability.'
            Items=@($decisions.ToArray())
            SourceOrArchivePstModifiedByExplicitToolOperation=$false
            HistoricalEvidenceWrittenByTool=$false
            AttachmentHashesUseTransientProtectedTempCopies=$true
            OriginalMoveMayBeRetried=$false
            AutomaticRetryAllowed=$false
            WriterPermit=$false
            ArchiveResumeAutoRemainClosed=$true
            ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $items
        Release-OPA265ARCH2c4Com -Object $target
        Close-OPA265ARCH2dSession -Session $session
    }
}
