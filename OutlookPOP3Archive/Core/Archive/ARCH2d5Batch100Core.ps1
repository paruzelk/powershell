#requires -Version 5.1
# ARCH2d5: one explicit operator-authorized batch of exactly 100 real Inbox
# MailItems from existing POP3 store. New target PST only. Durable chain and
# every cross-PST COM Move is one-shot forever. No retry/resume/production.
. (Join-Path $PSScriptRoot 'ARCH2d5Batch100Policy.ps1')

function Invoke-OPA265ARCH2d5Pilot {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Plan','Inventory','Prepare','MoveBatch','Evidence','Reconcile')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][string]$SourcePst,
        [string[]]$SourceEntryIds=@(),
        [string]$ManifestSha256='',
        [string]$BatchClaimSha256='',
        [string]$FinalSealSha256='',
        [switch]$ConfirmBatchPreparation,
        [switch]$ConfirmBatchMove,
        [string]$ApprovalText=''
    )
    $layout=Get-OPA265ARCH2d5Layout -RunId $RunId -LocalAppData $env:LOCALAPPDATA
    [void](Assert-OPA265ARCH2d5Layout -Layout $layout)
    $source=[IO.Path]::GetFullPath($SourcePst)
    if($source.StartsWith('\\') -or [IO.Path]::GetFileName($source) -cne 'info@stios.ru.pst' -or
       [string]::Equals($source,[string]$layout.ArchivePst,[StringComparison]::OrdinalIgnoreCase)){
        throw 'ARCH2d5 exact existing POP3 info@stios.ru.pst required, never archive/UNC.'
    }
    if($Mode -ceq 'Plan'){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d5.Plan.1'
            Status='OneHundredRealPop3PilotPlanNoOutlookNoDiskWrites'
            RunId=$RunId;SourcePst=$source
            ArchivePst=[string]$layout.ArchivePst
            BatchSize=100
            OldARCH2c4AndARCH2dEvidenceUntouched=$true
            AutomaticRetryAllowed=$false
            ArchiveResumeAutoRemainClosed=$true
            ProductionReady=$false
        }
    }
    if($Mode -cin @('Prepare','MoveBatch') -and $WhatIfPreference){
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d5.WhatIf.1'
            Status='WhatIfNoOutlookNoPstNoJournalWrites'
            RunId=$RunId;Mode=$Mode
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
    }
    if($Mode -ceq 'Prepare'){
        [void](Assert-OPA265ARCH2d5EntryIds -EntryIds $SourceEntryIds)
        [void](Assert-OPA265ARCH2d5Approval -Action Prepare -RunId $RunId -Confirmed ([bool]$ConfirmBatchPreparation) -ApprovalText $ApprovalText)
    }elseif($Mode -ceq 'MoveBatch'){
        [void](Assert-OPA265ARCH2d5Approval -Action MoveBatch -RunId $RunId -Confirmed ([bool]$ConfirmBatchMove) -ApprovalText $ApprovalText)
    }
    if($Mode -cin @('MoveBatch','Evidence','Reconcile') -and
       $ManifestSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d5 original anchored ManifestSha256 required.'
    }
    if($Mode -cin @('Evidence','Reconcile') -and
       $BatchClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d5 operator-received BatchClaimSha256 required for safe audit.'
    }
    if($FinalSealSha256 -and $FinalSealSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'ARCH2d5 final seal SHA256 invalid.'
    }
    if($Mode -cin @('Plan','Inventory','Evidence','Reconcile') -and (
       @($SourceEntryIds).Count -ne 0 -or $ConfirmBatchPreparation -or $ConfirmBatchMove -or
       $ApprovalText)){
        throw 'ARCH2d5 read-only stage cannot accept explicit write approval or candidate overrides.'
    }
    if($Mode -ceq 'Evidence'){
        # No Outlook COM, no file writes, no source or destination PST opened.
        $base=Read-OPA265ARCH2d5BaseEvidence -Layout $layout -SourcePst $source -ManifestSha256 $ManifestSha256 -BatchClaimSha256 $BatchClaimSha256
        $chain=Read-OPA265ARCH2d5FullChain -Layout $layout -Base $base -FinalSealSha256 $FinalSealSha256
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d5.ReadOnlyEvidence.1'
            Status=if($chain.AllHundredChainVerified){'AllHundredReceiptsExternallyAnchoredNoLiveVerification'
            }elseif(@($chain.Problems).Count -eq 0){'PartialOrUnanchoredEvidenceManualReviewNoRetry'
            }else{'JournalChainDiscrepancyManualReviewNoRetry'}
            RunId=$RunId;ManifestSha256=$ManifestSha256
            BatchClaimSha256=$BatchClaimSha256
            FinalSealSha256=[string]$chain.FinalSealSha256
            FinalSealExternallyPinned=[bool]$chain.FinalSealExternallyPinned
            Claimed=[int]$chain.Claimed
            Returned=[int]$chain.Returned
            LinkedItems=[int]$chain.LinkedItems
            CheckpointCount=[int]$chain.CheckpointCount
            Planned=100
            Problems=@($chain.Problems)
            Items=@($chain.Items)
            OutlookContacted=$false;PstOpened=$false
            JournalWritten=$false;AutomaticRetryAllowed=$false
            ProductionReady=$false
        }
    }
    # Any stage touching Outlook requires existing exact POP3 source.
    $source=Assert-OPA265ARCH2c4SourcePst -SourcePst $source -Layout $layout
    $session=$null;$target=$null;$root=$null;$items=$null;$returned=$null
    try{
        $session=Open-OPA265ARCH2dSession -Layout $layout -SourcePst $source
        if($Mode -ceq 'Inventory'){
            $items=$session.Inbox.Items
            $n=[int]$items.Count
            if($n -lt 100 -or $n -gt 500000){throw 'ARCH2d5 bounded Inbox count outside range.'}
            $items.Sort('[ReceivedTime]',$false)
            $rows=New-Object 'System.Collections.Generic.List[object]'
            $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            for($i=1;$i -le [Math]::Min($n,256) -and $rows.Count -lt 128;$i++){
                $mail=$null
                try{
                    $mail=$items.Item($i)
                    if($null -eq $mail -or [int]$mail.Class -ne 43){continue}
                    $id=[string]$mail.EntryID
                    if($id -cnotmatch '^[0-9A-Fa-f]{16,1024}$' -or -not $ids.Add($id)){continue}
                    $rows.Add([pscustomobject][ordered]@{
                        EntryId=$id
                        ReceivedUtc=[datetime]$mail.ReceivedTime
                        SubjectSha256=Get-OPA265ARCH2bTextSha256 -Text ([string]$mail.Subject)
                        AttachmentCount=[int]$mail.Attachments.Count
                    })|Out-Null
                }finally{Release-OPA265ARCH2c4Com -Object $mail}
            }
            if($rows.Count -lt 100){throw 'ARCH2d5 fewer than 100 unique eligible real Inbox messages in bounded scan.'}
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.ReadOnlyInventory.1'
                Status='AtLeastHundredRealInboxCandidatesReadOnlyNoMove'
                RunId=$RunId
                InboxCount=$n;Candidates=@($rows.ToArray())
                CandidateCount=$rows.Count;BatchSize=100
                OutlookProcessId=[int]$session.OutlookProcessId
                OutlookProcessStartUtcTicks=[int64]$session.OutlookProcessStartUtcTicks
                ProductionReady=$false
            }
        }
        if($Mode -ceq 'Prepare'){
            if([IO.Directory]::Exists([string]$layout.RunDirectory) -or
               [IO.File]::Exists([string]$layout.GlobalClaimPath) -or
               [IO.File]::Exists([string]$layout.ArchivePst) -or
               $null -ne $session.ArchiveStore){
                throw 'ARCH2d5 prior run or irreversible batch claim exists. No Prepare retry.'
            }
            $rows=New-Object 'System.Collections.Generic.List[object]'
            $sigs=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            # Capture EVERY original Body/HTML/ordered recipient/attachment byte
            # SHA256 before any PST creation. An error stops with no new PST.
            for($i=0;$i -lt 100;$i++){
                $mail=$null
                try{
                    $mail=Get-OPA265ARCH2c4ItemInInbox -Namespace $session.Namespace -SourceFolder $session.Inbox -SourceStoreId ([string]$session.SourceStore.StoreID) -EntryId ([string]$SourceEntryIds[$i])
                    $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
                    $sig=Get-OPA265ARCH2dSemanticSignature -Witness $w
                    if(-not $sigs.Add($sig)){throw ('ARCH2d5 ambiguous original semantic selector at '+($i+1)+': no PST created.')}
                    $rows.Add([pscustomobject][ordered]@{
                        Ordinal=$i+1;SourceEntryId=[string]$SourceEntryIds[$i]
                        SemanticSignature=$sig;SourceSemanticWitness=$w
                    })|Out-Null
                }finally{Release-OPA265ARCH2c4Com -Object $mail}
            }
            # Original sealed manifest Read helper caps JSON at one MiB. Fail
            # before PST creation when by-value witness array approaches cap.
            $rowsJson=ConvertTo-Json -InputObject @($rows.ToArray()) -Depth 16 -Compress
            $rowsBytes=(New-Object Text.UTF8Encoding($false)).GetByteCount($rowsJson)
            if($rowsBytes -gt 850000){throw 'ARCH2d5 witness collection exceeds 850kB safe manifest limit; no PST created.'}
            if(-not $PSCmdlet.ShouldProcess([string]$layout.ArchivePst,
                'Create one fresh archive PST solely for 100 selected EXISTING real POP3 Inbox messages')){
                throw 'ARCH2d5 operator declined Prepare.'
            }
            if(-not [IO.Directory]::Exists([string]$layout.Root)){
                [void][IO.Directory]::CreateDirectory([string]$layout.Root)
            }
            [void][IO.Directory]::CreateDirectory([string]$layout.RunDirectory)
            $intent=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.PrepareIntent.1'
                RunId=$RunId;SourcePst=$source
                SourceStoreId=[string]$session.SourceStore.StoreID
                SourceFolderId=[string]$session.Inbox.EntryID
                DestinationPst=[string]$layout.ArchivePst
                PlannedCount=100
                SourceEntryIds=@($rows.ToArray()|ForEach-Object{[string]$_.SourceEntryId})
                NewTargetOnly=$true;AutomaticPrepareRetryAllowed=$false
            }
            $intentSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.IntentPath -Value $intent
            # Durable intent precedes the only destination-PST creation.
            $session.Namespace.AddStoreEx([string]$layout.ArchivePst,2)
            if(-not [IO.File]::Exists([string]$layout.ArchivePst)){
                throw 'ARCH2d5 Outlook did not create target archive.'
            }
            $found=0
            for($i=1;$i -le [int]$session.Namespace.Stores.Count;$i++){
                $store=$null
                try{
                    $store=$session.Namespace.Stores.Item($i)
                    $fp=[string]$store.FilePath
                    if($fp -and [string]::Equals([IO.Path]::GetFullPath($fp),[string]$layout.ArchivePst,[StringComparison]::OrdinalIgnoreCase)){
                        $found++
                        if($found -eq 1){$session.ArchiveStore=$store;$store=$null}
                    }
                }finally{Release-OPA265ARCH2c4Com -Object $store}
            }
            if($found -ne 1){throw 'ARCH2d5 target store not unique after AddStoreEx.'}
            $root=$session.ArchiveStore.GetRootFolder()
            if([int]$root.Items.Count -ne 0 -or [int]$root.Folders.Count -gt 32){
                throw 'ARCH2d5 unexpected non-empty fresh archive root.'
            }
            for($i=1;$i -le [int]$root.Folders.Count;$i++){
                $f=$null
                try{
                    $f=$root.Folders.Item($i)
                    if([string]$f.Name -ceq [string]$layout.ArchiveFolder){
                        throw 'ARCH2d5 archive folder already exists.'
                    }
                }finally{Release-OPA265ARCH2c4Com -Object $f}
            }
            $target=$root.Folders.Add([string]$layout.ArchiveFolder)
            if([int]$target.Items.Count -ne 0){throw 'ARCH2d5 archive target folder not empty.'}
            $manifest=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.PreMoveManifest.1'
                RunId=$RunId;IntentSha256=$intentSha
                SourcePst=$source
                SourceStoreId=[string]$session.SourceStore.StoreID
                SourceFolderId=[string]$session.Inbox.EntryID
                ArchivePst=[string]$layout.ArchivePst
                ArchiveFolder=[string]$layout.ArchiveFolder
                ArchiveStoreId=[string]$session.ArchiveStore.StoreID
                ArchiveFolderId=[string]$target.EntryID
                PrepareOutlookProcessId=[int]$session.OutlookProcessId
                PrepareOutlookProcessStartUtcTicks=[int64]$session.OutlookProcessStartUtcTicks
                BatchSize=100;Items=@($rows.ToArray())
                WriterPermit=$false;ProductionReady=$false
            }
            [void](Assert-OPA265ARCH2d5Manifest -Manifest $manifest -Layout $layout -SourcePst $source -SourceStoreId ([string]$session.SourceStore.StoreID) -SourceFolderId ([string]$session.Inbox.EntryID))
            $manifestSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.ManifestPath -Value $manifest
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.Prepared.1'
                Status='HundredSourceSemanticWitnessesSealedNewTargetPreparedNoMove'
                RunId=$RunId;ManifestSha256=$manifestSha
                ArchivePst=[string]$layout.ArchivePst
                PreparedCount=100;MoveAlreadyAttempted=$false
                OutlookProcessId=[int]$session.OutlookProcessId
                ProductionReady=$false
            }
        }
        # MoveBatch and Reconcile consume immutable PREPARED original witnesses.
        $manifest=Read-OPA265ARCH2c4JsonSealed -Path $layout.ManifestPath -ExpectedSha256 $ManifestSha256
        [void](Assert-OPA265ARCH2d5Manifest -Manifest $manifest -Layout $layout -SourcePst $source -SourceStoreId ([string]$session.SourceStore.StoreID) -SourceFolderId ([string]$session.Inbox.EntryID))
        $intent=Read-OPA265ARCH2c4JsonSealed -Path $layout.IntentPath -ExpectedSha256 ([string]$manifest.IntentSha256)
        if([string]$intent.Schema -cne '2.6.5-ARCH2d5.PrepareIntent.1' -or
           [string]$intent.RunId -cne $RunId -or
           [string]$intent.SourceStoreId -cne [string]$manifest.SourceStoreId -or
           [string]$intent.SourceFolderId -cne [string]$manifest.SourceFolderId -or
           [string]$intent.SourcePst -cne $source -or
           [string]$intent.DestinationPst -cne [string]$layout.ArchivePst -or
           [int]$intent.PlannedCount -ne 100 -or @($intent.SourceEntryIds).Count -ne 100 -or
           -not [bool]$intent.NewTargetOnly -or [bool]$intent.AutomaticPrepareRetryAllowed){
            throw 'ARCH2d5 original Prepare intent invalid.'
        }
        for($i=0;$i -lt 100;$i++){
            if([string]$intent.SourceEntryIds[$i] -cne [string]$manifest.Items[$i].SourceEntryId){
                throw 'ARCH2d5 original selected identity/ordinal changed.'
            }
        }
        $target=Get-OPA265ARCH2dTargetFolder -Session $session -Layout $layout -Manifest $manifest
        if($Mode -ceq 'MoveBatch'){
            if([IO.File]::Exists([string]$layout.GlobalClaimPath) -or
               [IO.File]::Exists([string]$layout.FinalSealPath)){
                throw 'ARCH2d5 pilot global once claim/final seal exists. NEVER repeat MoveBatch.'
            }
            if([int]$session.OutlookProcessId -ne [int]$manifest.PrepareOutlookProcessId -or
               [int64]$session.OutlookProcessStartUtcTicks -ne [int64]$manifest.PrepareOutlookProcessStartUtcTicks){
                throw 'ARCH2d5 Outlook process restarted after Prepare. No MoveBatch.'
            }
            if([int]$target.Items.Count -ne 0){throw 'ARCH2d5 target must be EMPTY before irreversible batch.'}
            for($i=1;$i -le 100;$i++){
                if([IO.File]::Exists((Get-OPA265ARCH2d5ItemPath -Layout $layout -Ordinal $i)) -or
                   [IO.File]::Exists((Get-OPA265ARCH2d5ItemPath -Layout $layout -Ordinal $i -Kind Return))){
                    throw 'ARCH2d5 existing individual attempt evidence; no batch replay.'
                }
                if($i % 10 -eq 0 -and
                   [IO.File]::Exists((Get-OPA265ARCH2d5CheckpointPath -Layout $layout -ThroughOrdinal $i))){
                    throw 'ARCH2d5 existing checkpoint seal; no batch replay.'
                }
            }
            # FULL second semantic verification of all 100 originals.
            for($i=0;$i -lt 100;$i++){
                $mail=$null
                try{
                    $row=$manifest.Items[$i]
                    $mail=Get-OPA265ARCH2c4ItemInInbox -Namespace $session.Namespace -SourceFolder $session.Inbox -SourceStoreId ([string]$session.SourceStore.StoreID) -EntryId ([string]$row.SourceEntryId)
                    $current=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
                    $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $row.SourceSemanticWitness -Destination $current
                    if(-not [bool]$cmp.CriticalContentMatches){
                        throw ('ARCH2d5 original '+($i+1)+' changed since Prepare. No Move.')
                    }
                }finally{Release-OPA265ARCH2c4Com -Object $mail}
            }
            if(-not $PSCmdlet.ShouldProcess([string]$layout.ArchivePst,
                'Permanently move exactly 100 real POP3 Inbox letters once, 100 durable claims and ten SHA checkpoints')){
                throw 'ARCH2d5 MoveBatch declined by operator.'
            }
            # Global forever-once gate is CREATE-NEW + forced flush, BEFORE
            # any COM Move or individual claim. Fail-close across all RunIds.
            $globalClaim=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.BatchOnceClaim.1'
                RunId=$RunId;ManifestSha256=$ManifestSha256
                SourcePst=$source;PlannedCount=100
                MoveProcessId=[int]$session.OutlookProcessId
                MoveProcessStartUtcTicks=[int64]$session.OutlookProcessStartUtcTicks
                ClaimedBeforeAnyMove=$true
                AutomaticRetryAllowed=$false;ProductionReady=$false
            }
            $globalSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.GlobalClaimPath -Value $globalClaim
            $lastReturnSha='';$lastCheckpointSha=''
            $checkpoints=New-Object 'System.Collections.Generic.List[string]'
            $completed=0
            for($i=0;$i -lt 100;$i++){
                $row=$manifest.Items[$i]
                $ordinal=$i+1
                $mail=$null;$moved=$null;$parent=$null
                try{
                    $mail=Get-OPA265ARCH2c4ItemInInbox -Namespace $session.Namespace -SourceFolder $session.Inbox -SourceStoreId ([string]$manifest.SourceStoreId) -EntryId ([string]$row.SourceEntryId)
                    $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail
                    if(-not (Compare-OPA265ARCH2bMailSemanticWitness -Source $row.SourceSemanticWitness -Destination $w).CriticalContentMatches){
                        throw ('ARCH2d5 source '+$ordinal+' changed after global claim; STOP. No replay.')
                    }
                    if([int]$target.Items.Count -ne $completed){
                        throw ('ARCH2d5 unexpected target count at '+$ordinal+'; STOP. No replay.')
                    }
                    $claim=[pscustomobject][ordered]@{
                        Schema='2.6.5-ARCH2d5.IndividualClaim.1'
                        RunId=$RunId;Ordinal=$ordinal
                        ManifestSha256=$ManifestSha256
                        BatchClaimSha256=$globalSha
                        SourceEntryId=[string]$row.SourceEntryId
                        SourceStoreId=[string]$manifest.SourceStoreId
                        ArchiveStoreId=[string]$manifest.ArchiveStoreId
                        ArchiveFolderId=[string]$manifest.ArchiveFolderId
                        PreviousReceiptSha256=$lastReturnSha
                        PreviousCheckpointSha256=$lastCheckpointSha
                        ClaimedBeforeMove=$true;AutomaticRetryAllowed=$false
                    }
                    $claimSha=Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5ItemPath -Layout $layout -Ordinal $ordinal) -Value $claim
                    try {$moved=$mail.Move($target)}
                    catch {
                        throw ('ARCH2d5 OUTLOOK COM INDETERMINATE at '+$ordinal+'/100. Durable item claim '+$claimSha+
                            '. NEVER REPEAT MoveBatch or individual Move. '+$_.Exception.Message)
                    }
                    if($null -eq $moved){
                        throw 'ARCH2d5 COM Move returned null. INDETERMINATE, no retry.'
                    }
                    $parent=$moved.Parent
                    if([string]$parent.EntryID -cne [string]$manifest.ArchiveFolderId -or
                       [string]$parent.StoreID -cne [string]$manifest.ArchiveStoreId){
                        throw 'ARCH2d5 COM Move destination mismatched sealed original folder. STOP.'
                    }
                    $receipt=[pscustomobject][ordered]@{
                        Schema='2.6.5-ARCH2d5.MoveReturn.1'
                        RunId=$RunId;Ordinal=$ordinal
                        ClaimSha256=$claimSha
                        PreviousReceiptSha256=$lastReturnSha
                        DestinationEntryId=[string]$moved.EntryID
                        ArchiveStoreId=[string]$parent.StoreID
                        ArchiveFolderId=[string]$parent.EntryID
                        IndependentRestartReviewRequired=$true
                        ProductionReady=$false
                    }
                    $lastReturnSha=Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5ItemPath -Layout $layout -Ordinal $ordinal -Kind Return) -Value $receipt
                    $completed++
                    if($ordinal % 10 -eq 0){
                        $cp=[pscustomobject][ordered]@{
                            Schema='2.6.5-ARCH2d5.CheckpointSeal.1'
                            RunId=$RunId;ThroughOrdinal=$ordinal
                            ManifestSha256=$ManifestSha256
                            BatchClaimSha256=$globalSha
                            LastReceiptSha256=$lastReturnSha
                            PreviousCheckpointSha256=$lastCheckpointSha
                            SealedAfterReceipt=$true
                        }
                        $lastCheckpointSha=Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5CheckpointPath -Layout $layout -ThroughOrdinal $ordinal) -Value $cp
                        $checkpoints.Add($lastCheckpointSha)|Out-Null
                    }
                } finally {
                    Release-OPA265ARCH2c4Com -Object $parent
                    Release-OPA265ARCH2c4Com -Object $moved
                    Release-OPA265ARCH2c4Com -Object $mail
                }
            }
            if($completed -ne 100 -or $checkpoints.Count -ne 10){
                throw 'ARCH2d5 incomplete batch, no final seal or retry.'
            }
            # Externally pin FINAL SHA of 100 chained receipts/checkpoints.
            # Operator stores FinalSealSha256 from this return before restart.
            $final=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.BatchFinalSeal.1'
                RunId=$RunId;ManifestSha256=$ManifestSha256
                BatchClaimSha256=$globalSha
                CompletedCount=100
                LastReceiptSha256=$lastReturnSha
                LastCheckpointSha256=$lastCheckpointSha
                CheckpointSha256=@($checkpoints.ToArray())
                IndependentRestartReviewRequired=$true
                ProductionReady=$false
            }
            $finalSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.FinalSealPath -Value $final
            return [pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.BatchReturned.1'
                Status='HundredRealOutlookComMovesReturnedIndependentReviewRequired'
                RunId=$RunId;ManifestSha256=$ManifestSha256
                BatchClaimSha256=$globalSha;FinalSealSha256=$finalSha
                Claimed=100;MoveReturned=100;CheckpointSeals=10
                IndependentlyVerified=0;ArchivePst=[string]$layout.ArchivePst
                AutomaticRetryAllowed=$false;ProductionReady=$false
            }
        }
        # Reconcile: READ ONLY, never attach/modify/Move a PST.
        if($BatchClaimSha256 -cnotmatch '^[a-f0-9]{64}$'){
            throw 'ARCH2d5 independent review needs operator-pinned original global claim SHA256.'
        }
        $base=Read-OPA265ARCH2d5BaseEvidence -Layout $layout -SourcePst $source -ManifestSha256 $ManifestSha256 -BatchClaimSha256 $BatchClaimSha256
        $chain=Read-OPA265ARCH2d5FullChain -Layout $layout -Base $base -FinalSealSha256 $FinalSealSha256
        $restart=([int]$session.OutlookProcessId -ne [int]$base.GlobalClaim.MoveProcessId -and
            [int64]$session.OutlookProcessStartUtcTicks -ne [int64]$base.GlobalClaim.MoveProcessStartUtcTicks)
        if(-not $restart){
            throw 'ARCH2d5 Reconcile requires a different Outlook process after original MoveBatch.'
        }
        $items=$target.Items
        $archiveCount=[int]$items.Count
        if($archiveCount -lt 0 -or $archiveCount -gt 128){
            throw 'ARCH2d5 archive count outside safe bounded reconciliation range.'
        }
        $sourceSigs=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($m in @($manifest.Items)){[void]$sourceSigs.Add([string]$m.SemanticSignature)}
        $found=@{};$unknown=0;$duplicates=0
        for($i=1;$i -le $archiveCount;$i++){
            $archiveMail=$null
            try {
                $archiveMail=$items.Item($i)
                if($null -eq $archiveMail -or [int]$archiveMail.Class -ne 43){
                    $unknown++;continue
                }
                $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $archiveMail
                $sig=Get-OPA265ARCH2dSemanticSignature -Witness $w
                if(-not $sourceSigs.Contains($sig)){
                    $unknown++
                }elseif($found.ContainsKey($sig)){
                    $duplicates++
                    $found[$sig].Count=[int]$found[$sig].Count+1
                }else{
                    $found[$sig]=[pscustomobject]@{Count=1;Witness=$w}
                }
            }finally{Release-OPA265ARCH2c4Com -Object $archiveMail}
        }
        $reviews=New-Object 'System.Collections.Generic.List[object]'
        for($i=0;$i -lt 100;$i++){
            $original=$manifest.Items[$i]
            $ev=$chain.Items[$i]
            $presence=Get-OPA265ARCH2dSourcePresence -Namespace $session.Namespace -EntryId ([string]$original.SourceEntryId) -StoreId ([string]$manifest.SourceStoreId) -FolderId ([string]$manifest.SourceFolderId)
            $targetMatches=0;$contentMatches=$false
            if($found.ContainsKey([string]$original.SemanticSignature)){
                $match=$found[[string]$original.SemanticSignature]
                $targetMatches=[int]$match.Count
                $cmp=Compare-OPA265ARCH2bMailSemanticWitness -Source $original.SourceSemanticWitness -Destination $match.Witness
                $contentMatches=[bool]$cmp.CriticalContentMatches
            }
            $verified=($presence -eq 0 -and $targetMatches -eq 1 -and $contentMatches -and
                [string]$ev.EvidenceStatus -ceq 'ClaimReturnChainLinked')
            $unattempted=($presence -eq 1 -and $targetMatches -eq 0 -and
                [string]$ev.EvidenceStatus -ceq 'NotClaimed')
            $status=if($verified){'MovedSemanticallyMatchedChainLinked'
            }elseif($unattempted){'UnattemptedOriginalStillPresentNoRetryPermit'
            }else{'ManualReviewRequiredNoRetry'}
            $reviews.Add([pscustomobject][ordered]@{
                Ordinal=$i+1;Status=$status
                SourceOriginalEntryIdState=$presence
                MatchingArchiveItems=$targetMatches
                FullSemanticContentMatches=$contentMatches
                ClaimStatus=[string]$ev.ClaimStatus
                ReturnStatus=[string]$ev.ReturnStatus
                IssueCodes=@($ev.IssueCodes)
                AutomaticRetryAllowed=$false
            })|Out-Null
        }
        $verifiedCount=@($reviews.ToArray()|Where-Object{$_.Status -ceq 'MovedSemanticallyMatchedChainLinked'}).Count
        $notAttempted=@($reviews.ToArray()|Where-Object{$_.Status -ceq 'UnattemptedOriginalStillPresentNoRetryPermit'}).Count
        $full=($verifiedCount -eq 100 -and $archiveCount -eq 100 -and
            $unknown -eq 0 -and $duplicates -eq 0 -and
            [bool]$chain.AllHundredChainVerified)
        $status=if($full){'AllHundredIndependentPostRestartSemanticMatchesAndAnchoredReceipts'
        }elseif($verifiedCount+$notAttempted -eq 100 -and $archiveCount -eq $verifiedCount -and
                $unknown -eq 0 -and $duplicates -eq 0){
            'PartialHundredReadOnlyObservedButNoResumePermit'
        }else{'ManualReviewRequiredNoAutomaticRetry'}
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d5.IndependentPostRestartReconciliation.1'
            Status=$status;RunId=$RunId
            ManifestSha256=$ManifestSha256
            BatchClaimSha256=$BatchClaimSha256
            FinalSealSha256=[string]$chain.FinalSealSha256
            FinalSealExternallyPinned=[bool]$chain.FinalSealExternallyPinned
            OriginalPlanned=100
            VerifiedMoved=$verifiedCount
            NotAttempted=$notAttempted
            ManualReviewCount=100-$verifiedCount-$notAttempted
            ArchiveFolderItemCount=$archiveCount
            UnknownArchiveItems=$unknown;DuplicateSemanticSelectors=$duplicates
            LinkedReceiptCount=[int]$chain.LinkedItems
            CheckpointSealCount=[int]$chain.CheckpointCount
            JournalIssues=@($chain.Problems)
            OutlookRestartConfirmed=$restart
            Items=@($reviews.ToArray())
            OldPilotEvidenceWritten=$false
            OriginalMoveMayBeRetried=$false;AutomaticRetryAllowed=$false
            ArchiveResumeAutoRemainClosed=$true;ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $items
        Release-OPA265ARCH2c4Com -Object $target
        Release-OPA265ARCH2c4Com -Object $root
        Release-OPA265ARCH2c4Com -Object $returned
        Close-OPA265ARCH2dSession -Session $session
    }
}
