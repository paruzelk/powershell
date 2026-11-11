#requires -Version 5.1
# ARCH2a no-blind-retry policy: fail closed for incomplete Move attempts.
# Pure functions; no Outlook, file, journal or PST I/O.
function Test-OPA265ARCH2aUnresolvedMoveSteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyCollection()][object[]]$Steps,
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyCollection()][object[]]$PlannedItems
    )
    $planned=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($item in @($PlannedItems)){
        if($null -eq $item){throw 'ARCH2a null planned item; cannot validate Move claims.'}
        $id=[string]$item.EntryId
        if([string]::IsNullOrWhiteSpace($id) -or -not $planned.Add($id)){
            throw 'ARCH2a duplicate or empty source EntryId in original planned items.'
        }
    }
    $attempts=@{}
    $completed=@{}
    $gaps=New-Object 'System.Collections.Generic.List[string]'
    $invalid=New-Object 'System.Collections.Generic.List[string]'
    foreach($entry in @($Steps)){
        if($null -eq $entry){throw 'ARCH2a null step in journal; manual reconciliation required.'}
        $step=[string]$entry.Step
        if($step -notin @('Move Started','Move Completed','Move Reconciled','Move Indeterminate') -and
           $step -cnotmatch '^Move \d+/\d+$'){continue}
        $id=[string]$entry.EntryId
        if([string]::IsNullOrWhiteSpace($id) -or -not $planned.Contains($id)){
            $invalid.Add('MoveStepMissingOrUnknownPlannedId')
            continue
        }
        if($step -ceq 'Move Started'){
            if(-not $attempts.ContainsKey($id)){$attempts[$id]=0}
            $attempts[$id]=[int]$attempts[$id]+1
        }
        elseif($step -cin @('Move Completed','Move Reconciled') -or
               $step -cmatch '^Move \d+/\d+$'){
            if(-not $completed.ContainsKey($id)){$completed[$id]=0}
            $completed[$id]=[int]$completed[$id]+1
        }
        elseif($step -ceq 'Move Indeterminate'){
            $gaps.Add($id)
        }
    }
    foreach($id in @($attempts.Keys)){
        $attemptCount=[int]$attempts[$id]
        $completeCount=0
        if($completed.ContainsKey($id)){$completeCount=[int]$completed[$id]}
        if($attemptCount -gt 1){$gaps.Add($id);$invalid.Add('MultipleAttemptsForSameSourceId')}
        if($completeCount -lt 1){$gaps.Add($id)}
    }
    # Only the original archive journal may be used. Neither an index nor a
    # provider returned object is independent proof of full semantic integrity.
    $distinct=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $unresolved=New-Object 'System.Collections.Generic.List[string]'
    foreach($id in $gaps){
        if($distinct.Add($id)){$unresolved.Add($id)}
    }
    $safe=($unresolved.Count -eq 0 -and $invalid.Count -eq 0)
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2a.MoveClaimFence.1'
        Status=if($safe){'NoUnresolvedMoveClaimObserved'}else{'UnresolvedMoveClaimManualReconciliationRequired'}
        UnresolvedSourceIds=@($unresolved.ToArray())
        IssueCodes=@($invalid.ToArray())
        AttemptedSourceCount=$attempts.Count
        SafeToContinueFromThisJournal=$safe
        IndependentContentVerificationPerformed=$false
        AutomaticMoveRetryAllowed=$false
        HistoricalMoveClaimsRewritten=$false
        WriterPermit=$false
        ProductionReady=$false
    }
}

function Assert-OPA265ARCH2aNoUnresolvedMove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Transaction,
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyCollection()][object[]]$JournalSteps
    )
    if($null -eq $Transaction.State -or
       $null -eq $Transaction.State.PlannedItems){
        throw 'ARCH2a no complete original planned-item inventory; cannot authorize any Move.'
    }
    $result=Test-OPA265ARCH2aUnresolvedMoveSteps -Steps $JournalSteps -PlannedItems @($Transaction.State.PlannedItems)
    if(-not $result.SafeToContinueFromThisJournal){
        throw ('ARCH2a STOP: unresolved Move claim, no automatic retry or Resume; '+
               'preserve original PST/transaction journal and independently reconcile. IDs='+
               (($result.UnresolvedSourceIds -join ',') -replace '[\r\n]','')+
               '; issues='+($result.IssueCodes -join ','))
    }
    return $result
}

function Assert-OPA265ARCH2aDevelopmentWriterClosed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Analyze','Plan','Archive','Resume','Auto')][string]$Mode
    )
    if($Mode -cin @('Archive','Resume','Auto')){
        throw ('ARCH2a DEV: mutating '+$Mode+' is blocked until the original '+
               'ArchiveVerifier implements independent Body/HTML/recipient/'+
               'attachment-byte SHA256 checks and the Move claim/resume workflow '+
               'passes real disposable-PST failure-window tests. The disabled worker '+
               'integration flags do not protect the legacy direct COM writer.')
    }
    return [pscustomobject][ordered]@{
        Schema='2.6.5-ARCH2a.WriterClosed.1'
        Mode=$Mode
        Status='ReadOnlyModePermitted'
        WriterPermit=$false;ProductionReady=$false
    }
}
