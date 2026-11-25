#requires -Version 5.1
# ARCH7c: recover only the proven processed prefix of a tagged live batch.
# Never fabricate a Move receipt, an Awaiting Restart marker or a new plan.
function Get-OPAARCH7cInterruptedReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Transaction,
          [Parameter(Mandatory=$true)][object]$State,
          [Parameter(Mandatory=$true)][object[]]$Steps)
    $cp=$Transaction.State;$plan=@($cp.PlannedItems);$rows=@($State.Rows)
    if($State.Planned -lt 0 -or $State.Planned -gt 10 -or [int]$cp.Limit -lt 1 -or [int]$cp.Limit -gt 10 -or
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
    param([object]$Transaction,[object]$State,[object]$Verification,[string]$SourceStoreId,[string]$ProfileName)
    $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    $review=Get-OPAARCH7cInterruptedReview -Transaction $Transaction -State $State -Steps $steps
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
    $readback=Get-OPAARCH7cInterruptedReview -Transaction $Transaction -State $final -Steps $steps
    if(-not $readback.RecoveryMarkerPresent -or $readback.Proof -cne $review.Proof -or $final.Reconciled -ne $final.Returned){throw 'ARCH7c recovery readback incomplete.'}
    $n=Save-OPAARCH6DeferredEvidence -Transaction $Transaction -SourceStoreId $SourceStoreId -ProfileName $ProfileName
    if($n -ne $review.Deferred){throw 'ARCH7c deferred ledger readback incomplete.'}
    $result.Status='LiveInterruptedBatchRecovered'
    $result | Add-Member -NotePropertyMembers @{Unprocessed=$review.Unprocessed;Deferred=$review.Deferred;DeferredRecorded=$n;RecoveryProof=$review.Proof;MoveInvocations=0}
    return $result
}
