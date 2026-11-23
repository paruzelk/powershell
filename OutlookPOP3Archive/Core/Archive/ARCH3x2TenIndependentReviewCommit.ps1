#requires -Version 5.1
# ARCH3x2: independent postrestart ORIGINAL ArchiveVerifier for ten real
# x1b MoveReturned messages, then separate original journal and shared index
# commit (explicit, no live Move). Prepared ARCH3w1 Intent journal immutable.
# Repair can NEVER replay Move, only finish journal/index after fresh verifier.
. (Join-Path $PSScriptRoot 'ARCH3x1RealTenOriginalMailMover.ps1')
. (Join-Path $PSScriptRoot 'ARCH3pIndependentPostRestartOriginalVerifier.ps1')

function Get-OPA265ARCH3x2Layout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunId)
    $l=Get-OPA265ARCH3x1Layout -RunId $RunId
    $root=Join-Path $env:LOCALAPPDATA ('OPA265-ARCH3x2-'+$RunId)
    return [pscustomobject][ordered]@{
        Root=$root;RunId=$RunId;WriterRoot=[string]$l.Root
        ReviewSealPath=(Join-Path $root 'verified-ten-restart.json')
        CommitClaimPath=(Join-Path $root 'journal-index-commit-claim.json')
        CommitJournalPath=(Join-Path $root 'verified-original-operation-journal.jsonl')
        CommitSealPath=(Join-Path $root 'journal-index-final-seal.json')
    }
}

function Get-OPA265ARCH3x2PinnedReturned {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$SealSha256,
          [Parameter(Mandatory=$true)][string]$ManifestSha256,
          [Parameter(Mandatory=$true)][string]$JournalSha256)
    $prepared=Get-OPA265ARCH3x1PinnedPrepared -RunId ([string]$Layout.RunId) -SealSha256 $SealSha256 -ManifestSha256 $ManifestSha256 -JournalSha256 $JournalSha256
    $x1layout=Get-OPA265ARCH3x1Layout -RunId ([string]$Layout.RunId)
    $status=Get-OPA265ARCH3x1ReadOnlyStatus -Layout $x1layout
    if(-not [bool]$status.WriterEntryPresent -or
       [int]$status.Claims -ne 10 -or [int]$status.Invocations -ne 10 -or
       [int]$status.MoveReturns -ne 10){
        throw 'ARCH3x2 requires all ten original durable MoveReturned receipts. Partial/unknown state: NO REPLAY.'
    }
    $sha=[string]$status.WriterEntrySha256
    $writer=Read-OPA265ARCH3cPinnedJson -Path ([string]$x1layout.WriterEntryPath) -ExpectedSha256 $sha
    if([string]$writer.PreparedManifestSha256 -cne $ManifestSha256 -or
       [string]$writer.PreparedJournalSha256 -cne $JournalSha256 -or
       [string]$writer.SealSha256 -cne $SealSha256 -or
       [string]$writer.SourcePst -cne [string]$prepared.Manifest.SourcePst -or
       [string]$writer.TargetPst -cne [string]$prepared.Manifest.TargetPstPreview -or
       [int]$writer.OutlookProcessId -le 0 -or
       [long]$writer.OutlookProcessStartUtcTicks -le 0){
        throw 'ARCH3x2 original protected batch writer identity changed.'
    }
    $receipts=New-Object 'System.Collections.Generic.List[object]'
    $prior=''
    for($i=1;$i -le 10;$i++){
        $stem=('{0:00}' -f $i)
        $claimPath=Join-Path $x1layout.Root ($stem+'-claim.json')
        $invPath=Join-Path $x1layout.Root ($stem+'-invocation.json')
        $receiptPath=Join-Path $x1layout.Root ($stem+'-returned.json')
        $claimSha=(Get-FileHash -LiteralPath $claimPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $invSha=(Get-FileHash -LiteralPath $invPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $receiptSha=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $c=Read-OPA265ARCH3cPinnedJson -Path $claimPath -ExpectedSha256 $claimSha
        $inv=Read-OPA265ARCH3cPinnedJson -Path $invPath -ExpectedSha256 $invSha
        $r=Read-OPA265ARCH3cPinnedJson -Path $receiptPath -ExpectedSha256 $receiptSha
        $m=$prepared.Manifest.Rows[$i-1]
        if([int]$c.Ordinal -ne $i -or [int]$inv.Ordinal -ne $i -or
           [int]$r.Ordinal -ne $i -or
           [string]$c.WriterEntrySha256 -cne $sha -or
           [string]$c.PreparedManifestSha256 -cne $ManifestSha256 -or
           [string]$c.PreparedJournalSha256 -cne $JournalSha256 -or
           [string]$c.PreviousMoveReceiptSha256 -cne $prior -or
           [string]$r.PreviousMoveReceiptSha256 -cne $prior -or
           [string]$c.SourceEntryId -cne [string]$m.SourceEntryId -or
           [string]$r.SourceEntryId -cne [string]$m.SourceEntryId -or
           [string]$c.OriginalOperationId -cne [string]$m.OriginalOperationId -or
           [string]$c.FullOriginalWitnessSha256 -cne [string]$m.FullOriginalWitnessSha256 -or
           [string]$r.FullOriginalWitnessSha256 -cne [string]$m.FullOriginalWitnessSha256 -or
           [string]$inv.ClaimSha256 -cne $claimSha -or
           [string]$r.ClaimSha256 -cne $claimSha -or
           [string]$r.ProviderInvocationSha256 -cne $invSha -or
           [string]$c.DestinationStoreId -cne [string]$r.DestinationStoreId -or
           [string]$c.DestinationFolderEntryId -cne [string]$r.DestinationFolderEntryId -or
           [string]$r.ArchiveEntryId -cnotmatch '^[0-9a-fA-F]{16,1024}$' -or
           [bool]$r.OriginalJournalReconciled -or [bool]$r.OriginalDuplicateIndexWritten){
            throw ('ARCH3x2 ten original claim/invocation/return SHA chain broken at '+$i)
        }
        [void]$receipts.Add($r)
        $prior=$receiptSha
    }
    return [pscustomobject]@{
        Prepared=$prepared;Writer=$writer;WriterSha256=$sha
        Status=$status;Receipts=@($receipts.ToArray())
        LastReceiptSha256=$prior
    }
}

function Invoke-OPA265ARCH3x2IndependentTenReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Bundle)
    if([Threading.Thread]::CurrentThread.GetApartmentState().ToString() -cne 'STA'){
        throw 'ARCH3x2 independent original verifier requires native PowerShell 5.1 STA.'
    }
    $m=$Bundle.Prepared.Manifest;$v=$Bundle.Prepared.Seal;$w=$Bundle.Writer
    if(-not [IO.File]::Exists([string]$m.TargetPstPreview)){
        throw 'ARCH3x2 destination Part3 missing after claimed ten original Move.'
    }
    $session=$null;$archive=$null;$root=$null;$folder=$null
    try{
        $session=Open-OPA265ARCH2dSession -Layout (Get-OPA265ARCH2dLayout -RunId ([string]$m.RunId) -LocalAppData $env:LOCALAPPDATA) -SourcePst ([string]$m.SourcePst)
        if(-not [bool]$session.Scope.Approved -or
           [string]$session.Namespace.CurrentProfileName -cne 'Outlook' -or
           (Get-OPA265ARCH2bTextSha256 -Text ([string]$session.SourceStore.StoreID)) -cne [string]$m.SourceStoreIdSha256 -or
           [int]$session.OutlookProcessId -eq [int]$w.OutlookProcessId -or
           [long]$session.OutlookProcessStartUtcTicks -le [long]$w.OutlookProcessStartUtcTicks){
            throw 'ARCH3x2 independent new Outlook process with original POP3 StoreID NOT confirmed.'
        }
        $archive=Get-OPA265ARCH3pMountedPart2 -Namespace $session.Namespace -Part2 ([string]$m.TargetPstPreview) -StoreId ([string]$Bundle.Receipts[0].DestinationStoreId)
        if([string]$archive.StoreID -ceq [string]$session.SourceStore.StoreID -or
           [string]$archive.StoreID -ceq [string]$session.DefaultStoreId){
            throw 'ARCH3x2 archive store is source/default.'
        }
        foreach($account in @($session.Accounts)){
            if([string]$account.DeliveryStoreId -ceq [string]$archive.StoreID){
                throw 'ARCH3x2 destination is an account delivery store.'
            }
        }
        $root=$archive.GetRootFolder()
        $folder=Get-OPAFolderByPath -Root $root -RelativePath '2020\Входящие'
        if($null -eq $folder -or [string]$folder.StoreID -cne [string]$archive.StoreID -or
           [string]$folder.EntryID -cne [string]$Bundle.Receipts[0].DestinationFolderEntryId -or
           [int]$folder.Items.Count -ne 10){
            throw 'ARCH3x2 original destination Part3 folder not exactly ten claimed messages.'
        }
        $expected=New-Object 'System.Collections.Generic.List[object]'
        $resultRows=New-Object 'System.Collections.Generic.List[object]'
        for($i=0;$i -lt 10;$i++){
            $r=$Bundle.Receipts[$i];$sourceRow=$v.Rows[$i];$intent=$m.Rows[$i]
            $item=$null;$parent=$null
            try{
                $item=$session.Namespace.GetItemFromID([string]$r.ArchiveEntryId,[string]$archive.StoreID)
                if($null -eq $item -or [int]$item.Class -ne 43 -or
                   [string]$item.EntryID -cne [string]$r.ArchiveEntryId){
                    throw ('ARCH3x2 destination archived EntryID missing at ordinal '+($i+1))
                }
                $parent=$item.Parent
                if($null -eq $parent -or
                   [string]$parent.EntryID -cne [string]$folder.EntryID -or
                   [string]$parent.StoreID -cne [string]$archive.StoreID){
                    throw ('ARCH3x2 destination item not in pinned Year2020 Inbox at '+($i+1))
                }
                [void](Assert-OPA265ARCH3iFullWitnessPinned -Witness $sourceRow.OriginalWitness -ExpectedOriginalWitnessSha256 ([string]$intent.FullOriginalWitnessSha256))
                $witness=Get-OPA265ARCH2bMailSemanticWitness -Mail $item
                $compare=Compare-OPA265ARCH2bMailSemanticWitness -Source $sourceRow.OriginalWitness -Destination $witness
                if(-not [bool]$compare.CriticalContentMatches -or @($compare.IssueCodes).Count -ne 0){
                    throw ('ARCH3x2 archived Body/HTML/recipients/user-state/attachment bytes differ at '+($i+1))
                }
                [void]$expected.Add([pscustomobject]@{
                    SourceEntryId=[string]$intent.SourceEntryId
                    ArchiveEntryId=[string]$r.ArchiveEntryId
                    ArchivePst=[string]$m.TargetPstPreview
                    TargetFolderPath=[string]$folder.FolderPath
                    SourceFolderPath=[string]$session.Inbox.FolderPath
                    InternetMessageId=[string](Get-OPAInternetMessageId -Item $item)
                    Subject=[string]$item.Subject
                    Sender='';Size=$null
                    SourceSemanticWitness=$sourceRow.OriginalWitness
                })
                [void]$resultRows.Add([pscustomobject][ordered]@{
                    Ordinal=$i+1;SourceEntryId=[string]$intent.SourceEntryId
                    ArchiveEntryId=[string]$r.ArchiveEntryId
                    FullOriginalWitnessSha256=[string]$intent.FullOriginalWitnessSha256
                })
            }finally{
                Release-OPA265ARCH2c4Com -Object $parent
                Release-OPA265ARCH2c4Com -Object $item
            }
        }
        # ORIGINAL verifier observes the current Inbox; its total MAY CHANGE.
        # It requires only that all ten original SourceEntryIds are absent
        # and each archived destination preserves the full original witness.
        $verified=Test-OPAArchiveMoves -Namespace $session.Namespace -SourceFolder @($session.Inbox) -ArchiveStores @($archive) -ExpectedMoved 10 -ExpectedMoves @($expected.ToArray()) -RequireSemanticWitness
        if(-not [bool]$verified.Verified -or
           -not [bool]$verified.EntryIdsVerified -or
           -not [bool]$verified.SemanticWitnessRequired -or
           -not [bool]$verified.AllRequiredOriginalSemanticWitnessesPresent -or
           [int]$verified.ExpectedMoved -ne 10 -or
           [int]$verified.ExpectedEntryIdsChecked -ne 10 -or
           [int]$verified.TargetCount -ne 10 -or
           @($verified.MissingEntryIds).Count -ne 0){
            throw 'ARCH3x2 original postrestart ArchiveVerifier did not independently verify all ten messages.'
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x2.IndependentOriginalTenReview.1'
            Status='TenOriginalMovesIndependentlyVerifiedAfterNewOutlookProcess'
            RunId=[string]$m.RunId
            OriginalTenFullSemanticMatches=10
            OriginalArchiveVerifierUsed=$true
            TotalOriginalAttachments=12
            OriginalSourceEntryIdsAbsent=$true
            OriginalDestinationCount=10
            ArchiveFolderPath=[string]$folder.FolderPath
            CurrentInboxCount=[long]$verified.ObservedSourceCount
            ReopenedOutlookProcessId=[int]$session.OutlookProcessId
            ReopenedOutlookProcessStartUtcTicks=[long]$session.OutlookProcessStartUtcTicks
            OriginalMoveProcessId=[int]$w.OutlookProcessId
            OriginalMoveProcessStartUtcTicks=[long]$w.OutlookProcessStartUtcTicks
            LastOriginalMoveReceiptSha256=[string]$Bundle.LastReceiptSha256
            Rows=@($resultRows.ToArray())
            OriginalIndexWritten=$false;OriginalJournalReconciled=$false
            AutomaticMoveRetryAllowed=$false;ProductionReady=$false
        }
    }finally{
        Release-OPA265ARCH2c4Com -Object $folder
        Release-OPA265ARCH2c4Com -Object $root
        Release-OPA265ARCH2c4Com -Object $archive
        Close-OPA265ARCH2dSession -Session $session
    }
}

function Get-OPA265ARCH3x2IndexState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Bundle,
          [switch]$AllowPreviouslyCommitted)
    $m=$Bundle.Prepared.Manifest
    $index=Get-OPA265ARCH3uSharedIndexReadOnly -SourcePst ([string]$m.SourcePst)
    if(-not $AllowPreviouslyCommitted -and
       [string]$index.OriginalIndexSha256 -cne [string]$m.OriginalIndexSha256){
        throw 'ARCH3x2 shared index changed before protected postrestart commit.'
    }
    if($index.OriginalIndexEntryCount -lt 501 -or
       $index.OriginalIndexEntryCount -gt 511){
        throw 'ARCH3x2 shared index outside original 501..511 limit.'
    }
    $present=0
    for($i=0;$i -lt 10;$i++){
        $r=$Bundle.Receipts[$i];$entry=Test-OPADuplicateEntry -Index $index.Index -SourceEntryId ([string]$r.SourceEntryId)
        if($null -ne $entry){
            if([string]$entry.ArchiveEntryId -cne [string]$r.ArchiveEntryId -or
               [string]$entry.ArchivePst -cne [string]$m.TargetPstPreview -or
               [string]$entry.TransactionId -cne ('ARCH3x2-'+[string]$m.RunId)){
                throw 'ARCH3x2 source already indexed under different/ambiguous archive.'
            }
            $present++
        }
    }
    if([int]$index.OriginalIndexEntryCount -ne (501+$present)){
        throw 'ARCH3x2 unexpected concurrent shared index entries or index drift.'
    }
    return [pscustomobject]@{Index=$index.Index;Present=$present;CurrentSha256=[string]$index.OriginalIndexSha256}
}

function Get-OPA265ARCH3x2CommitJournalState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Bundle,
          [Parameter(Mandatory=$true)][object]$Layout)
    if(-not [IO.File]::Exists([string]$Layout.CommitJournalPath)){
        return [pscustomobject]@{Intents=0;Reconciled=0}
    }
    if((([IO.File]::GetAttributes([string]$Layout.CommitJournalPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH3x2 commit journal is redirected.'
    }
    $j=Read-OPAOperationJournal -Path $Layout.CommitJournalPath
    if([bool]$j.TrailingPartial -or @($j.Events).Count -gt 20){
        throw 'ARCH3x2 partial/corrupt journal tail; manual forensic review.'
    }
    $intents=0;$reconciled=0;$m=$Bundle.Prepared.Manifest
    foreach($e in @($j.Events)){
        if([string]$e.TransactionId -cne ('ARCH3x2-'+[string]$m.RunId)){
            throw 'ARCH3x2 foreign event in protected commit journal.'
        }
        if([string]$e.Phase -ceq 'Intent'){
            $i=$intents
            if($i -gt 9 -or [long]$e.Sequence -ne ($i+1) -or
               [string]$e.SourceEntryId -cne [string]$m.Rows[$i].SourceEntryId -or
               [string]$e.OperationId -cne [string]$m.Rows[$i].OriginalOperationId){
                throw 'ARCH3x2 commit journal Intent prefix invalid.'
            }
            $intents++
        }elseif([string]$e.Phase -ceq 'Reconciled'){
            $i=$reconciled
            if($intents -ne 10 -or $i -gt 9 -or [long]$e.Sequence -ne (11+$i) -or
               [string]$e.SourceEntryId -cne [string]$m.Rows[$i].SourceEntryId -or
               [string]$e.OperationId -cne [string]$m.Rows[$i].OriginalOperationId -or
               [string]$e.ArchiveEntryId -cne [string]$Bundle.Receipts[$i].ArchiveEntryId){
                throw 'ARCH3x2 commit journal Reconciled prefix invalid.'
            }
            $reconciled++
        }else{
            throw 'ARCH3x2 unexpected event phase in verified commit journal.'
        }
    }
    return [pscustomobject]@{Intents=$intents;Reconciled=$reconciled}
}

function Invoke-OPA265ARCH3x2FinishIndexAndJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Bundle,
          [Parameter(Mandatory=$true)][object]$Layout,
          [Parameter(Mandatory=$true)][string]$ReviewSha256,
          [switch]$Recovery)
    $m=$Bundle.Prepared.Manifest;$v=$Bundle.Prepared.Seal
    $state=Get-OPA265ARCH3x2CommitJournalState -Bundle $Bundle -Layout $Layout
    if($state.Reconciled -gt 0 -and $state.Intents -ne 10){
        throw 'ARCH3x2 cannot reconcile before all original Intent rows.'
    }
    $transaction='ARCH3x2-'+[string]$m.RunId
    $original=Read-OPAOperationJournal -Path ([string]$Bundle.Prepared.Layout.JournalPath)
    if([bool]$original.TrailingPartial -or @($original.Events).Count -ne 10){
        throw 'ARCH3x2 original immutable ARCH3w1 ten Intent evidence corrupted.'
    }
    $indexBefore=Get-OPA265ARCH3x2IndexState -Bundle $Bundle -AllowPreviouslyCommitted:$Recovery.IsPresent
    $review=Read-OPA265ARCH3cPinnedJson -Path $Layout.ReviewSealPath -ExpectedSha256 $ReviewSha256
    if([string]$review.Review.ArchiveFolderPath -cnotmatch '\\2020\\Входящие$' -or
       [int]$review.Review.OriginalTenFullSemanticMatches -ne 10){
        throw 'ARCH3x2 sealed independent verified target folder invalid.'
    }
    # At first COMMIT there can be no x2 index entries. During Recovery,
    # only the *previously verified same* source/target entries are accepted.
    for($i=$state.Intents;$i -lt 10;$i++){
        $e=$original.Events[$i]
        [void](Write-OPAOperationJournalEvent -Path $Layout.CommitJournalPath -TransactionId $transaction -OperationId ([string]$m.Rows[$i].OriginalOperationId) -Sequence ([long]($i+1)) -Phase Intent -SourceEntryId ([string]$m.Rows[$i].SourceEntryId) -SourceStoreId ([string]$e.SourceStoreId) -SourceFolderPath ([string]$e.SourceFolderPath) -TargetFolderPath ([string]$m.Rows[$i].TargetFolderPath) -ArchivePst ([string]$m.TargetPstPreview) -Message ('ARCH3x2 SHA-pinned original prepared Journal='+[string]$Bundle.Writer.PreparedJournalSha256+'; Review='+$ReviewSha256))
    }
    $state=Get-OPA265ARCH3x2CommitJournalState -Bundle $Bundle -Layout $Layout
    if($state.Intents -ne 10){throw 'ARCH3x2 original ten Intent journal mirror not verified.'}
    for($i=$state.Reconciled;$i -lt 10;$i++){
        $e=$original.Events[$i]
        [void](Write-OPAOperationJournalEvent -Path $Layout.CommitJournalPath -TransactionId $transaction -OperationId ([string]$m.Rows[$i].OriginalOperationId) -Sequence ([long]($i+11)) -Phase Reconciled -SourceEntryId ([string]$m.Rows[$i].SourceEntryId) -ArchiveEntryId ([string]$Bundle.Receipts[$i].ArchiveEntryId) -SourceStoreId ([string]$e.SourceStoreId) -SourceFolderPath ([string]$e.SourceFolderPath) -TargetFolderPath ([string]$m.Rows[$i].TargetFolderPath) -ArchivePst ([string]$m.TargetPstPreview) -Message ('ARCH3x2 all ten independent original ArchiveVerifier PASS; Review='+$ReviewSha256))
    }
    $state=Get-OPA265ARCH3x2CommitJournalState -Bundle $Bundle -Layout $Layout
    if($state.Reconciled -ne 10){throw 'ARCH3x2 original verified Reconciled journal not complete.'}
    $index=Get-OPA265ARCH3x2IndexState -Bundle $Bundle -AllowPreviouslyCommitted:$Recovery.IsPresent
    $old=$global:OPADurabilityMode
    try{
        $global:OPADurabilityMode='Safe'
        for($i=0;$i -lt 10;$i++){
            $intent=$m.Rows[$i];$r=$Bundle.Receipts[$i]
            if($null -ne (Test-OPADuplicateEntry -Index $index.Index -SourceEntryId ([string]$intent.SourceEntryId))){continue}
            Add-OPADuplicateEntry -Index $index.Index -SourceEntryId ([string]$intent.SourceEntryId) -ArchiveEntryId ([string]$r.ArchiveEntryId) -SourceFolderPath '\\info@stios.ru\Входящие' -TargetFolderPath ([string]$review.Review.ArchiveFolderPath) -ReceivedTime ([datetime]::new([long]$v.Rows[$i].ArchiveDateLocalTicks)) -Subject '' -TransactionId $transaction -TransactionLimit 10 -ArchiveGrouping Year -SourcePst ([string]$m.SourcePst) -ArchivePst ([string]$m.TargetPstPreview)
            Sync-OPADuplicateJournalStreams
        }
    }finally{
        Close-OPADuplicateJournalStreams
        $global:OPADurabilityMode=$old
    }
    $after=Get-OPA265ARCH3x2IndexState -Bundle $Bundle -AllowPreviouslyCommitted
    if($after.Present -ne 10){throw 'ARCH3x2 independent original index after verified ten commit incomplete.'}
    $journalSha=(Get-FileHash -LiteralPath $Layout.CommitJournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $seal=[pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x2.VerifiedTenJournalIndexCommit.1'
        RunId=[string]$m.RunId
        ReviewSha256=$ReviewSha256
        CommitClaimSha256=(Get-FileHash -LiteralPath $Layout.CommitClaimPath -Algorithm SHA256).Hash.ToLowerInvariant()
        OriginalPreparedJournalSha256=[string]$Bundle.Writer.PreparedJournalSha256
        VerifiedCommitJournalSha256=$journalSha
        OriginalSharedIndexSha256=[string]$after.CurrentSha256
        OriginalIndexAdded=10
        IndependentPostRestartVerified=$true
        OriginalArchiveVerifierUsed=$true
        AllTenReconciled=$true
        AutomaticMoveRetryAllowed=$false;ProductionReady=$false
    }
    $sha=Write-OPA265ARCH3cJsonOnce -Path $Layout.CommitSealPath -Record $seal
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH3x2.FinalVerifiedTenCommit.1'
        Status='TenOriginalPostRestartVerifiedReconciledAndIndexed'
        RunId=[string]$m.RunId;Verified=10;Reconciled=10;Indexed=10
        ReviewSha256=$ReviewSha256;FinalSealSha256=$sha
        OriginalIndexSha256=[string]$after.CurrentSha256
        OriginalCommitJournalSha256=$journalSha
        Recovered=[bool]$Recovery
        AutomaticMoveRetryAllowed=$false;ProductionReady=$false
    }
}

function Invoke-OPA265ARCH3x2RealTen {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Status','Plan','Review','Seal','Commit','Recover')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$RunId,
        [string]$SealSha256='',
        [string]$ManifestSha256='',
        [string]$JournalSha256='',
        [string]$ReviewSha256='',
        [switch]$ConfirmReviewSeal,
        [switch]$ConfirmVerifiedCommit,
        [switch]$ConfirmRecovery
    )
    $l=Get-OPA265ARCH3x2Layout -RunId $RunId
    if($Mode -ceq 'Status'){
        if([IO.Directory]::Exists($l.Root)){
            if((([IO.File]::GetAttributes($l.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
                throw 'ARCH3x2 protected review directory redirected.'
            }
            [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $l.Root)
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x2.Status.1';RunId=$RunId
            ReviewSealed=[IO.File]::Exists($l.ReviewSealPath)
            CommitClaimed=[IO.File]::Exists($l.CommitClaimPath)
            CommitJournalPresent=[IO.File]::Exists($l.CommitJournalPath)
            CommitComplete=[IO.File]::Exists($l.CommitSealPath)
            LiveOutlookContacted=$false
            AutomaticMoveRetryAllowed=$false;ProductionReady=$false
        }
    }
    $b=Get-OPA265ARCH3x2PinnedReturned -Layout $l -SealSha256 $SealSha256 -ManifestSha256 $ManifestSha256 -JournalSha256 $JournalSha256
    if($Mode -ceq 'Plan'){
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3x2.Plan.1'
            Status='OriginalTenMoveReturnedIndependentRestartVerifierPlanned'
            PreparedTen=10;ReturnedTen=10
            OriginalOutlookProcessId=[int]$b.Writer.OutlookProcessId
            LiveOutlookContacted=$false;AutomaticMoveRetryAllowed=$false;ProductionReady=$false
        }
    }
    if($Mode -ceq 'Review'){
        return (Invoke-OPA265ARCH3x2IndependentTenReview -Bundle $b)
    }
    if($Mode -ceq 'Seal'){
        if(-not $ConfirmReviewSeal -or
           [IO.Directory]::Exists($l.Root) -or [IO.File]::Exists($l.Root)){
            throw 'ARCH3x2 independent review can be sealed only ONCE, explicit operator authorization required.'
        }
        if(-not $PSCmdlet.ShouldProcess($l.ReviewSealPath,'Persist full ten ORIGINAL ArchiveVerifier postrestart evidence only')){
            return [pscustomobject]@{Schema='2.6.5-ARCH3x2.WhatIf.1';Mode='Seal';NoWrites=$true}
        }
        $index=Get-OPA265ARCH3x2IndexState -Bundle $b
        if($index.Present -ne 0){throw 'ARCH3x2 shared index already modified before independent review seal.'}
        $review=Invoke-OPA265ARCH3x2IndependentTenReview -Bundle $b
        if([int]$review.OriginalTenFullSemanticMatches -ne 10 -or -not [bool]$review.OriginalArchiveVerifierUsed){throw 'ARCH3x2 original verifier not complete.'}
        $evidence=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH3x2.TenOriginalRestartReviewSeal.1'
            RunId=$RunId;OriginalSealSha256=$SealSha256
            PreparedManifestSha256=$ManifestSha256;PreparedJournalSha256=$JournalSha256
            WriterEntrySha256=[string]$b.WriterSha256
            LastMoveReceiptSha256=[string]$b.LastReceiptSha256
            OriginalIndexBeforeSha256=[string]$index.CurrentSha256
            Review=$review
            AutomaticMoveRetryAllowed=$false;ProductionReady=$false
        }
        New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $l
        $sha=Write-OPA265ARCH3cJsonOnce -Path $l.ReviewSealPath -Record $evidence
        return [pscustomobject]@{
            Schema='2.6.5-ARCH3x2.ReviewSealed.1'
            Status='IndependentTenOriginalRestartVerifierSealedNoIndexOrJournalCommit'
            RunId=$RunId;ReviewSha256=$sha;Verified=10
            AutomaticMoveRetryAllowed=$false;ProductionReady=$false
        }
    }
    if($Mode -cin @('Commit','Recover')){
        if($ReviewSha256 -cnotmatch '^[a-f0-9]{64}$' -or
           -not [IO.Directory]::Exists($l.Root) -or
           (([IO.File]::GetAttributes($l.Root) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'ARCH3x2 exact pinned protected independent ReviewSeal required.'
        }
        [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $l.Root)
        $proof=Read-OPA265ARCH3cPinnedJson -Path $l.ReviewSealPath -ExpectedSha256 $ReviewSha256
        if([string]$proof.Schema -cne '2.6.5-ARCH3x2.TenOriginalRestartReviewSeal.1' -or
           [string]$proof.RunId -cne $RunId -or
           [string]$proof.PreparedManifestSha256 -cne $ManifestSha256 -or
           [string]$proof.PreparedJournalSha256 -cne $JournalSha256 -or
           [string]$proof.LastMoveReceiptSha256 -cne [string]$b.LastReceiptSha256 -or
           [int]$proof.Review.OriginalTenFullSemanticMatches -ne 10 -or
           -not [bool]$proof.Review.OriginalArchiveVerifierUsed){
            throw 'ARCH3x2 independent sealed ten review provenance invalid.'
        }
        if([IO.File]::Exists($l.CommitSealPath)){throw 'ARCH3x2 already committed: use Status, no retry.'}
        if($Mode -ceq 'Commit'){
            if(-not $ConfirmVerifiedCommit -or [IO.File]::Exists($l.CommitClaimPath) -or
               [IO.File]::Exists($l.CommitJournalPath)){
                throw 'ARCH3x2 fresh verified Commit requires no prior claim/journal; use Recover for interrupted commit.'
            }
        }else{
            if(-not $ConfirmRecovery -or -not [IO.File]::Exists($l.CommitClaimPath)){
                throw 'ARCH3x2 recovery requires an existing commit claim and explicit confirmation; NO Move.'
            }
        }
        if(-not $PSCmdlet.ShouldProcess([string]$b.Prepared.Manifest.TargetPstPreview,'Original ten VERIFIED Reconciled + shared DuplicateIndex only; NEVER MailItem.Move')){
            return [pscustomobject]@{Schema='2.6.5-ARCH3x2.WhatIf.1';Mode=$Mode;NoWrites=$true}
        }
        $newReview=Invoke-OPA265ARCH3x2IndependentTenReview -Bundle $b
        if([int]$newReview.OriginalTenFullSemanticMatches -ne 10 -or
           [string]$newReview.LastOriginalMoveReceiptSha256 -cne [string]$proof.Review.LastOriginalMoveReceiptSha256){
            throw 'ARCH3x2 independent live ten verification changed before journal/index commit.'
        }
        if($Mode -ceq 'Commit'){
            $idx=Get-OPA265ARCH3x2IndexState -Bundle $b
            if($idx.Present -ne 0 -or [string]$idx.CurrentSha256 -cne [string]$proof.OriginalIndexBeforeSha256){
                throw 'ARCH3x2 shared DuplicateIndex modified since sealed independent review.'
            }
            $claim=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH3x2.VerifiedTenCommitClaim.1'
                RunId=$RunId;ReviewSha256=$ReviewSha256
                OriginalPreparedJournalSha256=$JournalSha256
                LastMoveReceiptSha256=[string]$b.LastReceiptSha256
                OriginalIndexBeforeSha256=[string]$idx.CurrentSha256
                OnlyJournalAndIndexNoMove=$true;AutomaticMoveRetryAllowed=$false;ProductionReady=$false
            }
            [void](Write-OPA265ARCH3cJsonOnce -Path $l.CommitClaimPath -Record $claim)
        }else{
            $claim=Read-OPA265ARCH3cPinnedJson -Path $l.CommitClaimPath -ExpectedSha256 (Get-FileHash -LiteralPath $l.CommitClaimPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if([string]$claim.Schema -cne '2.6.5-ARCH3x2.VerifiedTenCommitClaim.1' -or
               [string]$claim.ReviewSha256 -cne $ReviewSha256 -or
               [string]$claim.OriginalPreparedJournalSha256 -cne $JournalSha256 -or
               [string]$claim.LastMoveReceiptSha256 -cne [string]$b.LastReceiptSha256 -or
               -not [bool]$claim.OnlyJournalAndIndexNoMove){
                throw 'ARCH3x2 recovery commit claim changed.'
            }
        }
        return (Invoke-OPA265ARCH3x2FinishIndexAndJournal -Bundle $b -Layout $l -ReviewSha256 $ReviewSha256 -Recovery:($Mode -ceq 'Recover'))
    }
}
