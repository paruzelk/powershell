#requires -Version 5.1
# ARCH7c: recover only the proven processed prefix of a tagged live batch.
# Never fabricate a Move receipt, an Awaiting Restart marker or a new plan.

# ARCH8a3: a durable exception is not a successful archive or a Move permit.
function Get-OPAARCH8a3HoldPath {
    param([object]$Transaction)
    if($Transaction.PSObject.Properties.Name -notcontains 'Path' -or -not $Transaction.Path){return $null}
    Join-Path ([IO.Path]::GetDirectoryName([string]$Transaction.Path)) ('ARCH8a3-held-'+$Transaction.TransactionId+'.json')
}
function Get-OPAARCH8a3StateHeldRows {
    param([object]$State)
    if($State.PSObject.Properties.Name -contains 'HeldRows'){$State.HeldRows}
}
function Get-OPAARCH8a3HoldRows {
    param([object]$Transaction,[object[]]$Rows,[string]$SourceStoreId)
    $path=Get-OPAARCH8a3HoldPath -Transaction $Transaction
    if(-not $path -or -not [IO.File]::Exists($path)){return}
    if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH8a3 redirected hold ledger.'}
    $raw=[IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false,$true))
    if(-not $raw.EndsWith([string][char]10)){throw 'ARCH8a3 incomplete hold ledger.'}
    $data=ConvertFrom-Json -InputObject $raw -ErrorAction Stop
    if($data.Schema -cne '2.6.5-ARCH8a3.Held.1' -or $data.TransactionId -cne [string]$Transaction.TransactionId -or $data.SourcePst -ine [string]$Transaction.State.SourcePst -or $data.StoreId -ine $SourceStoreId -or [int]$Transaction.State.Limit -gt 500 -or [int]$Transaction.State.Limit -lt 1 -or @($data.Rows).Count -lt 1){throw 'ARCH8a3 hold ledger identity mismatch.'}
    $seen=@{}
    foreach($h in @($data.Rows)){
        $id=[string]$h.SourceEntryId
        $r=@($Rows | Where-Object {$_.SourceEntryId -ieq $id})
        if(-not $id -or $seen.ContainsKey($id) -or $r.Count -ne 1 -or $h.ArchiveEntryId -ine $r[0].ArchiveEntryId -or $h.ArchivePst -ine $r[0].ArchivePst -or $h.TargetFolderPath -ine $r[0].TargetFolderPath -or $h.SourceFolderPath -ine $r[0].SourceFolderPath -or @($h.Reasons).Count -lt 1){throw 'ARCH8a3 hold ledger receipt mismatch.'}
        foreach($reason in @($h.Reasons)){
            if($reason -cnotin @('ARCHIVE_ITEM_NOT_VERIFIED','STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT','STILL_IN_SOURCE')){throw 'ARCH8a3 invalid hold reason.'}
        }
        $seen[$id]=$true
        $h
    }
}
function Get-OPAARCH8a3ItemFailures {
    param([object]$State,[object]$Verification)
    if(-not $Verification.SemanticWitnessRequired -or -not $Verification.AllRequiredOriginalSemanticWitnessesPresent -or [int]$Verification.ExpectedMoved -ne $State.Returned -or [int]$Verification.ExpectedEntryIdsChecked -ne $State.Returned){throw 'ARCH8a3 verification scope failure; preserve pending.'}
    $byId=@{}
    foreach($code in @($Verification.MissingEntryIds)+@($Verification.WarningEntryIds)){
        if([string]$code -cnotmatch '^(ARCHIVE_ITEM_NOT_VERIFIED|STALE_ARCHIVE_ENTRYID_VERIFIED_BY_FINGERPRINT|STILL_IN_SOURCE):(.+)
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Transaction,
          [Parameter(Mandatory=$true)][object]$State,
          [Parameter(Mandatory=$true)][object[]]$Steps,[switch]$ConfirmDevLongArchive)
    $devLiveCap=if($ConfirmDevLongArchive){500}else{10}
    $cp=$Transaction.State;$plan=@($cp.PlannedItems);$rows=@($State.Rows)
    $held=@(Get-OPAARCH8a3StateHeldRows -State $State)
    if($held.Count -gt 0 -and -not $ConfirmDevLongArchive){throw 'ARCH8a3 explicit long recovery required.'}
    $verifiedCount=$State.Returned-$held.Count
    if($State.Planned -lt 0 -or $State.Planned -gt $devLiveCap -or [int]$cp.Limit -lt 1 -or [int]$cp.Limit -gt $devLiveCap -or
       $plan.Count -ne $State.Planned -or $rows.Count -ne $State.Returned -or $State.Claimed -ne $State.Returned -or
       $State.Reconciled -lt 0 -or $State.Reconciled -gt $verifiedCount -or
       $State.OperationEventCount -ne ($State.Returned+$State.Reconciled) -or
       $cp.Status -cnotin @('Running','Planned','Completed') -or [int]$cp.Executed -lt 0 -or [int]$cp.Executed -gt $State.Returned){
        throw 'ARCH7c invalid bounded checkpoint or receipt counts.'
    }
    if($cp.Status -ceq 'Completed'){
        if([int]$cp.Verified -ne $verifiedCount -or [int]$cp.Executed -ne $State.Returned -or $State.Reconciled -ne $verifiedCount){throw 'ARCH7c inconsistent completed checkpoint.'}
    }elseif([int]$cp.Verified -ne 0){throw 'ARCH7c inconsistent unfinished verification.'}
    if($Steps.Count -lt 1 -or $Steps[0].Step -cne 'ARCH4 Batch Started'){throw 'ARCH7c missing batch start.'}
    $i=1;$selected=$false
    if($i -lt $Steps.Count -and $Steps[$i].Step -ceq 'Candidates'){$selected=$true;$i++}
    if(-not $selected -and ($State.Planned -ne 0 -or $State.Returned -ne 0)){throw 'ARCH7c missing durable selection.'}
    $processed=0;$moved=0;$skipped=0
    while($i -lt $Steps.Count -and $Steps[$i].Step -cin @('Move Started','Skipped')){
        if(-not $selected -or $processed -ge $plan.Count -or [string]$Steps[$i].EntryId -ine [string]$plan[$processed].EntryId){throw 'ARCH7c processed rows must be exact planned prefix.'}
        $id=[string]$plan[$processed].EntryId
        if($Steps[$i].Step -ceq 'Skipped'){
            $skipped++;$i++
        }else{
            if($i+1 -ge $Steps.Count -or $Steps[$i+1].Step -cne 'ARCH4 Move Returned' -or
               [string]$Steps[$i+1].EntryId -ine $id -or $moved -ge $rows.Count -or [string]$rows[$moved].SourceEntryId -ine $id){throw 'ARCH7c unresolved or unordered claim; no replay.'}
            $moved++;$i+=2
        }
        $processed++
    }
    if($moved -ne $State.Returned){throw 'ARCH7c incomplete receipt coverage.'}
    $awaiting=$false
    if($i -lt $Steps.Count -and $Steps[$i].Step -ceq 'ARCH4 Awaiting Restart'){
        if(-not $selected -or $processed -ne $plan.Count){throw 'ARCH7c invalid finished selection.'}
        $awaiting=$true;$i++
    }
    if($awaiting -ne [bool]$State.AwaitingRestart){throw 'ARCH7c inconsistent finished selection.'}
    $marker=0;$completion=0
    $unprocessed=$plan.Count-$processed
    $proof='Verified='+$verifiedCount+'; Deferred='+($skipped+$held.Count)+'; Unprocessed='+$unprocessed+'; MoveInvocations=0'
    for(;$i -lt $Steps.Count;$i++){
        if($State.Reconciled -ne $verifiedCount){throw 'ARCH7c completion before reconciliation.'}
        switch -CaseSensitive ($Steps[$i].Step){
            'ARCH4 Batch Verified' {$completion++}
            'ARCH7b Fresh Worker Verified' {if(-not $awaiting -or $completion -lt 1){throw 'ARCH7c unexpected earlier proof.'}}
            'ARCH7c Recovery Verified' {
                if($completion -lt 1 -or $Steps[$i].Message -cne $proof){throw 'ARCH7c recovery marker mismatch.'}
                $marker++
            }
            'ARCH7c Recovery Worker Verified' {if($marker -ne 1){throw 'ARCH7c worker proof without recovery marker.'}}
            default {throw 'ARCH7c unexpected journal step; preserve pending.'}
        }
    }
    if($marker -gt 1 -or ($cp.Status -ceq 'Completed' -and $completion -lt 1)){throw 'ARCH7c invalid completion markers.'}
    $deferred=@(Get-OPAARCH6DeferredRows -Transaction $Transaction -State $State -Steps $Steps)
    if($deferred.Count -ne $skipped){throw 'ARCH7c incomplete skip evidence.'}
    # The checkpoint may lag a durable skip; never invent an identity from it.
    $ids=@($cp.SkippedEntryIds | Where-Object {$_})
    if($ids.Count -ne [int]$cp.Skipped -or @($ids | Sort-Object -Unique).Count -ne $ids.Count){throw 'ARCH7c invalid checkpoint skip count.'}
    foreach($id in $ids){if(@($deferred | Where-Object {$_.EntryId -ieq $id}).Count -ne 1){throw 'ARCH7c checkpoint skip is not proven.'}}
    foreach($item in @($cp.SkippedItems | Where-Object {$_})){if(@($deferred | Where-Object {$_.EntryId -ieq $item.EntryId}).Count -ne 1){throw 'ARCH7c unproven checkpoint skip detail.'}}
    [pscustomobject]@{Planned=$plan.Count;Returned=$moved;Deferred=$skipped;VerificationHeld=$held.Count;TotalDeferred=($skipped+$held.Count);Unprocessed=$unprocessed;DeferredRows=$deferred;RecoveryMarkerPresent=($marker -eq 1);Proof=$proof}
}
function Complete-OPAARCH7cInterruptedBatch {
    [CmdletBinding()]
    param([object]$Transaction,[object]$State,[object]$Verification,[string]$SourceStoreId,[string]$ProfileName,[switch]$ConfirmDevLongArchive)
    $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    $review=Get-OPAARCH7cInterruptedReview -Transaction $Transaction -State $State -Steps $steps -ConfirmDevLongArchive:$ConfirmDevLongArchive
    # Restore only durable, pre-claim skipped rows; unprocessed is not deferred.
    $Transaction.State.SkippedItems=@($review.DeferredRows)
    $Transaction.State.SkippedEntryIds=@($review.DeferredRows | ForEach-Object {[string]$_.EntryId})
    $Transaction.State.Skipped=$review.Deferred
    $result=Complete-OPAARCH4VerifiedBatch -Transaction $Transaction -State $State -Verification $Verification -SourceStoreId $SourceStoreId -AllowItemHold:$ConfirmDevLongArchive
    Sync-OPAStepJournalStreams
    Close-OPAStepJournalStreams
    $completedState=Get-OPAARCH4ReturnedFromDisk -Transaction $Transaction -SourceStoreId $SourceStoreId
    $completedSteps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    $review=Get-OPAARCH7cInterruptedReview -Transaction $Transaction -State $completedState -Steps $completedSteps -ConfirmDevLongArchive:$ConfirmDevLongArchive
    if(-not $review.RecoveryMarkerPresent){
        Save-OPAArchiveTransaction -Transaction $Transaction -Status Completed -Step 'ARCH7c Recovery Verified' -Message $review.Proof -WriteCheckpoint
    }
    Sync-OPAStepJournalStreams
    Close-OPAStepJournalStreams
    $final=Get-OPAARCH4ReturnedFromDisk -Transaction $Transaction -SourceStoreId $SourceStoreId
    $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    $readback=Get-OPAARCH7cInterruptedReview -Transaction $Transaction -State $final -Steps $steps -ConfirmDevLongArchive:$ConfirmDevLongArchive
    if(-not $readback.RecoveryMarkerPresent -or $readback.Proof -cne $review.Proof -or $final.Reconciled -ne ($final.Returned-$readback.VerificationHeld)){throw 'ARCH7c recovery readback incomplete.'}
    $n=Save-OPAARCH6DeferredEvidence -Transaction $Transaction -SourceStoreId $SourceStoreId -ProfileName $ProfileName
    if($n -ne $review.Deferred){throw 'ARCH7c deferred ledger readback incomplete.'}
    $result.Status='LiveInterruptedBatchRecovered'
    $result | Add-Member -NotePropertyMembers @{Unprocessed=$review.Unprocessed;Deferred=$review.TotalDeferred;DeferredRecorded=($n+$review.VerificationHeld);RecoveryProof=$review.Proof;MoveInvocations=0}
    return $result
}
){throw 'ARCH8a3 non-item verification failure; preserve pending.'}
        $reason=$Matches[1];$id=$Matches[2]
        if(@($State.Rows | Where-Object {$_.SourceEntryId -ieq $id}).Count -ne 1){throw 'ARCH8a3 failure identity not unique.'}
        if(-not $byId.ContainsKey($id)){$byId[$id]=@()}
        $byId[$id]=@($byId[$id]+$reason | Sort-Object -Unique)
    }
    if($byId.Count -eq 0 -and (-not $Verification.Verified -or -not $Verification.EntryIdsVerified)){throw 'ARCH8a3 unexplained batch verification failure; preserve pending.'}
    foreach($r in @($State.Rows)){
        if($byId.ContainsKey([string]$r.SourceEntryId)){
            [pscustomobject][ordered]@{SourceEntryId=[string]$r.SourceEntryId;ArchiveEntryId=[string]$r.ArchiveEntryId;ArchivePst=[string]$r.ArchivePst;SourceFolderPath=[string]$r.SourceFolderPath;TargetFolderPath=[string]$r.TargetFolderPath;Reasons=@($byId[[string]$r.SourceEntryId])}
        }
    }
}
function Save-OPAARCH8a3Hold {
    param([object]$Transaction,[object]$State,[object[]]$Failures,[string]$SourceStoreId)
    $existing=@(Get-OPAARCH8a3HoldRows -Transaction $Transaction -Rows @($State.Rows) -SourceStoreId $SourceStoreId)
    if($existing.Count -gt 0){
        foreach($h in @($Failures)){if(@($existing | Where-Object {$_.SourceEntryId -ieq $h.SourceEntryId}).Count -ne 1){throw 'ARCH8a3 additional failure after sealed disposition; preserve pending.'}}
        return $existing
    }
    if(@($Failures).Count -eq 0){return}
    if($State.Reconciled -ne 0 -or $Transaction.State.Status -ceq 'Completed'){throw 'ARCH8a3 cannot revise a committed disposition.'}
    $path=Get-OPAARCH8a3HoldPath -Transaction $Transaction
    if(-not $path){throw 'ARCH8a3 missing durable hold path.'}
    $data=[ordered]@{Schema='2.6.5-ARCH8a3.Held.1';TransactionId=[string]$Transaction.TransactionId;SourcePst=[string]$Transaction.State.SourcePst;StoreId=$SourceStoreId;Rows=@($Failures)}
    $json=(ConvertTo-Json -InputObject $data -Depth 8 -Compress)+[char]10
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    if([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -cne $json){throw 'ARCH8a3 hold readback mismatch.'}
    Get-OPAARCH8a3HoldRows -Transaction $Transaction -Rows @($State.Rows) -SourceStoreId $SourceStoreId
}

function Get-OPAARCH7cInterruptedReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Transaction,
          [Parameter(Mandatory=$true)][object]$State,
          [Parameter(Mandatory=$true)][object[]]$Steps,[switch]$ConfirmDevLongArchive)
    $devLiveCap=if($ConfirmDevLongArchive){500}else{10}
    $cp=$Transaction.State;$plan=@($cp.PlannedItems);$rows=@($State.Rows)
    if($State.Planned -lt 0 -or $State.Planned -gt $devLiveCap -or [int]$cp.Limit -lt 1 -or [int]$cp.Limit -gt $devLiveCap -or
       $plan.Count -ne $State.Planned -or $rows.Count -ne $State.Returned -or $State.Claimed -ne $State.Returned -or
       $State.Reconciled -lt 0 -or $State.Reconciled -gt $State.Returned -or
       $State.OperationEventCount -ne ($State.Returned+$State.Reconciled) -or
       $cp.Status -cnotin @('Running','Planned','Completed') -or [int]$cp.Executed -lt 0 -or [int]$cp.Executed -gt $State.Returned){
        throw 'ARCH7c invalid bounded checkpoint or receipt counts.'
    }
    if($cp.Status -ceq 'Completed'){
        if([int]$cp.Verified -ne $State.Returned -or [int]$cp.Executed -ne $State.Returned -or $State.Reconciled -ne $State.Returned){throw 'ARCH7c inconsistent completed checkpoint.'}
    }elseif([int]$cp.Verified -ne 0){throw 'ARCH7c inconsistent unfinished verification.'}
    if($Steps.Count -lt 1 -or $Steps[0].Step -cne 'ARCH4 Batch Started'){throw 'ARCH7c missing batch start.'}
    $i=1;$selected=$false
    if($i -lt $Steps.Count -and $Steps[$i].Step -ceq 'Candidates'){$selected=$true;$i++}
    if(-not $selected -and ($State.Planned -ne 0 -or $State.Returned -ne 0)){throw 'ARCH7c missing durable selection.'}
    $processed=0;$moved=0;$skipped=0
    while($i -lt $Steps.Count -and $Steps[$i].Step -cin @('Move Started','Skipped')){
        if(-not $selected -or $processed -ge $plan.Count -or [string]$Steps[$i].EntryId -ine [string]$plan[$processed].EntryId){throw 'ARCH7c processed rows must be exact planned prefix.'}
        $id=[string]$plan[$processed].EntryId
        if($Steps[$i].Step -ceq 'Skipped'){
            $skipped++;$i++
        }else{
            if($i+1 -ge $Steps.Count -or $Steps[$i+1].Step -cne 'ARCH4 Move Returned' -or
               [string]$Steps[$i+1].EntryId -ine $id -or $moved -ge $rows.Count -or [string]$rows[$moved].SourceEntryId -ine $id){throw 'ARCH7c unresolved or unordered claim; no replay.'}
            $moved++;$i+=2
        }
        $processed++
    }
    if($moved -ne $State.Returned){throw 'ARCH7c incomplete receipt coverage.'}
    $awaiting=$false
    if($i -lt $Steps.Count -and $Steps[$i].Step -ceq 'ARCH4 Awaiting Restart'){
        if(-not $selected -or $processed -ne $plan.Count){throw 'ARCH7c invalid finished selection.'}
        $awaiting=$true;$i++
    }
    if($awaiting -ne [bool]$State.AwaitingRestart){throw 'ARCH7c inconsistent finished selection.'}
    $marker=0;$completion=0
    $unprocessed=$plan.Count-$processed
    $proof='Verified='+$moved+'; Deferred='+$skipped+'; Unprocessed='+$unprocessed+'; MoveInvocations=0'
    for(;$i -lt $Steps.Count;$i++){
        if($State.Reconciled -ne $State.Returned){throw 'ARCH7c completion before reconciliation.'}
        switch -CaseSensitive ($Steps[$i].Step){
            'ARCH4 Batch Verified' {$completion++}
            'ARCH7b Fresh Worker Verified' {if(-not $awaiting -or $completion -lt 1){throw 'ARCH7c unexpected earlier proof.'}}
            'ARCH7c Recovery Verified' {
                if($completion -lt 1 -or $Steps[$i].Message -cne $proof){throw 'ARCH7c recovery marker mismatch.'}
                $marker++
            }
            'ARCH7c Recovery Worker Verified' {if($marker -ne 1){throw 'ARCH7c worker proof without recovery marker.'}}
            default {throw 'ARCH7c unexpected journal step; preserve pending.'}
        }
    }
    if($marker -gt 1 -or ($cp.Status -ceq 'Completed' -and $completion -lt 1)){throw 'ARCH7c invalid completion markers.'}
    $deferred=@(Get-OPAARCH6DeferredRows -Transaction $Transaction -State $State -Steps $Steps)
    if($deferred.Count -ne $skipped){throw 'ARCH7c incomplete skip evidence.'}
    # The checkpoint may lag a durable skip; never invent an identity from it.
    $ids=@($cp.SkippedEntryIds | Where-Object {$_})
    if($ids.Count -ne [int]$cp.Skipped -or @($ids | Sort-Object -Unique).Count -ne $ids.Count){throw 'ARCH7c invalid checkpoint skip count.'}
    foreach($id in $ids){if(@($deferred | Where-Object {$_.EntryId -ieq $id}).Count -ne 1){throw 'ARCH7c checkpoint skip is not proven.'}}
    foreach($item in @($cp.SkippedItems | Where-Object {$_})){if(@($deferred | Where-Object {$_.EntryId -ieq $item.EntryId}).Count -ne 1){throw 'ARCH7c unproven checkpoint skip detail.'}}
    [pscustomobject]@{Planned=$plan.Count;Returned=$moved;Deferred=$skipped;Unprocessed=$unprocessed;DeferredRows=$deferred;RecoveryMarkerPresent=($marker -eq 1);Proof=$proof}
}
function Complete-OPAARCH7cInterruptedBatch {
    [CmdletBinding()]
    param([object]$Transaction,[object]$State,[object]$Verification,[string]$SourceStoreId,[string]$ProfileName,[switch]$ConfirmDevLongArchive)
    $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    $review=Get-OPAARCH7cInterruptedReview -Transaction $Transaction -State $State -Steps $steps -ConfirmDevLongArchive:$ConfirmDevLongArchive
    # Restore only durable, pre-claim skipped rows; unprocessed is not deferred.
    $Transaction.State.SkippedItems=@($review.DeferredRows)
    $Transaction.State.SkippedEntryIds=@($review.DeferredRows | ForEach-Object {[string]$_.EntryId})
    $Transaction.State.Skipped=$review.Deferred
    $result=Complete-OPAARCH4VerifiedBatch -Transaction $Transaction -State $State -Verification $Verification -SourceStoreId $SourceStoreId
    if(-not $review.RecoveryMarkerPresent){
        Save-OPAArchiveTransaction -Transaction $Transaction -Status Completed -Step 'ARCH7c Recovery Verified' -Message $review.Proof -WriteCheckpoint
    }
    Sync-OPAStepJournalStreams
    Close-OPAStepJournalStreams
    $final=Get-OPAARCH4ReturnedFromDisk -Transaction $Transaction -SourceStoreId $SourceStoreId
    $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    $readback=Get-OPAARCH7cInterruptedReview -Transaction $Transaction -State $final -Steps $steps -ConfirmDevLongArchive:$ConfirmDevLongArchive
    if(-not $readback.RecoveryMarkerPresent -or $readback.Proof -cne $review.Proof -or $final.Reconciled -ne $final.Returned){throw 'ARCH7c recovery readback incomplete.'}
    $n=Save-OPAARCH6DeferredEvidence -Transaction $Transaction -SourceStoreId $SourceStoreId -ProfileName $ProfileName
    if($n -ne $review.Deferred){throw 'ARCH7c deferred ledger readback incomplete.'}
    $result.Status='LiveInterruptedBatchRecovered'
    $result | Add-Member -NotePropertyMembers @{Unprocessed=$review.Unprocessed;Deferred=$review.Deferred;DeferredRecorded=$n;RecoveryProof=$review.Proof;MoveInvocations=0}
    return $result
}
