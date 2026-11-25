#requires -Version 5.1
. (Join-Path $PSScriptRoot 'ARCH6Antivirus.ps1')
function Get-OPAARCH6DeferredReason {
    param([string]$Message)
    $av=ConvertFrom-OPAARCH6AntivirusMessage -Message $Message
    if($null -ne $av){return [string]$av.Reason}
    if($Message -match '^ARCH5 Attachment(Type|Size)Unsupported:'){return ('Attachment'+$Matches[1]+'Unsupported')}
    if($Message -ceq 'ARCH2b attachment count exceeds bounded witness limit; no Move authorized.'){return 'AttachmentCountUnsupported'}
    if($Message -ceq 'ARCH2b recipient count exceeds witness bound.'){return 'RecipientCountUnsupported'}
    if($Message -ceq 'ARCH2b attachment name exceeds bound.'){return 'AttachmentNameUnsupported'}
    return $null
}
function Get-OPAARCH6DeferredProof {
    param([object]$Transaction,[string]$SourceStoreId)
    if($Transaction.State.Status -cne 'Completed'){throw 'ARCH6f3a deferred proof requires completed checkpoint.'}
    $state=Get-OPAARCH4ReturnedFromDisk -Transaction $Transaction -SourceStoreId $SourceStoreId
    if(-not $state.AwaitingRestart -or $state.Reconciled -ne $state.Returned -or $state.OperationEventCount -ne (2*$state.Returned) -or [int]$Transaction.State.Verified -ne $state.Returned -or [int]$Transaction.State.Executed -ne $state.Returned){throw 'ARCH6f3a incomplete reconciliation evidence.'}
    $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    if(@($steps | Where-Object {$_.Step -ceq 'ARCH4 Batch Verified'}).Count -lt 1){throw 'ARCH6f3a missing completed step.'}
    $moved=@{};foreach($r in @($state.Rows)){$moved[[string]$r.SourceEntryId]=$true}
    $plan=@{};foreach($p in @($Transaction.State.PlannedItems)){$plan[[string]$p.EntryId]=$p}
    $seen=@{}
    foreach($s in @($steps | Where-Object {$_.Step -ceq 'Skipped'})){
        $id=[string]$s.EntryId
        if(-not $plan.ContainsKey($id) -or $moved.ContainsKey($id) -or $seen.ContainsKey($id)){throw 'ARCH6f3a conflicting deferred identity.'}
        $p=$plan[$id];$reason=$null
        if([string]$s.Message -cmatch '^ARCH6f3a deferred ([A-Za-z]+): (.*)$'){
            $reason=$Matches[1];$detail=$Matches[2]
            if($reason -cne 'ExceedsArchiveCapacity' -and $reason -cne (Get-OPAARCH6DeferredReason -Message $detail)){throw 'ARCH6f3a invalid deferred reason.'}
            if($reason -cin @('AttachmentBlockedByAntivirus','AttachmentQuarantined') -and $null -eq (ConvertFrom-OPAARCH6AntivirusMessage -Message $detail -ExpectedEntryId $id)){throw 'ARCH6f3c2 antivirus skip identity mismatch.'}
            if([string]$s.SourceFolderPath -ine [string]$p.SourceFolderPath){throw 'ARCH6f3a deferred folder mismatch.'}
        }elseif([string]$s.Message -match '^Item skipped after unexpected error: .* \| (ARCH5 AttachmentTypeUnsupported:.*)$'){
            $detail=$Matches[1];$reason=Get-OPAARCH6DeferredReason -Message $detail
            $old=@($Transaction.State.SkippedItems | Where-Object {$_.EntryId -ieq $id})
            if($old.Count -ne 1 -or $old[0].Reason -cne $reason -or $old[0].Message -cne $detail -or $old[0].SourceFolderPath -ine $p.SourceFolderPath){throw 'ARCH6f3a historical skip evidence mismatch.'}
        }else{throw 'ARCH6f3a unknown or unsafe skipped item.'}
        $seen[$id]=[pscustomobject][ordered]@{EntryId=$id;SourceFolderPath=[string]$p.SourceFolderPath;Reason=$reason;Message=$detail;Subject=[string]$p.Subject;Sender=[string]$p.Sender;ArchiveDate=[string]$p.ArchiveDate;Size=$p.Size;Time=[string]$s.Time}
    }
    if($seen.Count -ne ($state.Planned-$state.Returned) -or $seen.Count -ne [int]$Transaction.State.Skipped){throw 'ARCH6f3a incomplete skip coverage.'}
    foreach($id in @($Transaction.State.SkippedEntryIds)){if(-not $seen.ContainsKey([string]$id)){throw 'ARCH6f3a checkpoint skip identity mismatch.'}}
    foreach($id in @($seen.Keys | Sort-Object)){ $seen[$id] }
}
function Save-OPAARCH6DeferredEvidence {
    param([object]$Transaction,[string]$SourceStoreId,[string]$ProfileName)
    $rows=@(Get-OPAARCH6DeferredProof -Transaction $Transaction -SourceStoreId $SourceStoreId)
    if($rows.Count -eq 0){return 0}
    $path=Join-Path ([IO.Path]::GetDirectoryName($Transaction.Path)) ('ARCH6-deferred-'+$Transaction.TransactionId+'.jsonl')
    $data=[ordered]@{Schema='2.6.5-ARCH6f3a.Deferred.1';SourcePst=[string]$Transaction.State.SourcePst;StoreId=$SourceStoreId;Profile=$ProfileName;TransactionId=[string]$Transaction.TransactionId;Rows=$rows}
    $json=ConvertTo-Json -InputObject $data -Depth 8 -Compress
    if(-not [IO.File]::Exists($path)){
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json+[char]10)
        $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    }
    if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -cne ($json+[char]10)){throw 'ARCH6f3a deferred durable readback mismatch.'}
    return $rows.Count
}
function Get-OPAARCH6DeferredIds {
    param([string]$SourcePst,[string]$SourceStoreId,[string]$ProfileName,[string]$Directory)
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($file in @(Get-ChildItem -LiteralPath $Directory -Filter 'ARCH6-deferred-*.jsonl' -File)){
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH6f3a redirected deferred ledger.'}
        $raw=[IO.File]::ReadAllText($file.FullName,[Text.UTF8Encoding]::new($false,$true))
        if(-not $raw.EndsWith([string][char]10)){throw 'ARCH6f3a incomplete deferred ledger.'}
        $d=ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        if($d.Schema -cne '2.6.5-ARCH6f3a.Deferred.1' -or [string]$d.TransactionId -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or $file.Name -cne ('ARCH6-deferred-'+$d.TransactionId+'.jsonl')){throw 'ARCH6f3a invalid deferred ledger.'}
        if([string]$d.SourcePst -ine $SourcePst){continue}
        if([string]$d.StoreId -ine $SourceStoreId -or [string]$d.Profile -ine $ProfileName){throw 'ARCH6f3a deferred source/profile/store mismatch.'}
        $tx=Get-OPAArchiveTransaction -SourcePst $SourcePst -TransactionId $d.TransactionId
        if([string]$tx.State.SourcePst -ine $SourcePst){throw 'ARCH6f3a checkpoint source mismatch.'}
        $proof=@(Get-OPAARCH6DeferredProof -Transaction $tx -SourceStoreId $SourceStoreId)
        if($proof.Count -eq 0 -or (ConvertTo-Json -InputObject $proof -Depth 8 -Compress) -cne (ConvertTo-Json -InputObject @($d.Rows) -Depth 8 -Compress)){throw 'ARCH6f3a deferred proof differs from original journals.'}
        foreach($r in $proof){if(-not $seen.Add([string]$r.EntryId)){throw 'ARCH6f3a repeated deferred identity.'}}
    }
    foreach($id in @(Get-OPAARCH6HistoricalThreatIds -SourcePst $SourcePst -SourceStoreId $SourceStoreId -ProfileName $ProfileName -Directory $Directory)){if(-not $seen.Add($id)){throw 'ARCH6f3c2 repeated historical hold identity.'}}
    return @($seen)
}

# Historical operator-confirmed hold, separate from completed-batch skip evidence.
function Get-OPAARCH6HistoricalThreatCandidate {
    param([object]$Transaction,[string]$SourceStoreId,[string]$EntryId)
    $state=Get-OPAARCH4ReturnedFromDisk -Transaction $Transaction -SourceStoreId $SourceStoreId
    $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    $review=Assert-OPAARCH6InterruptedState -Transaction $Transaction -State $state -Steps $steps -ExpectedPlanned $state.Planned -ExpectedReturned $state.Returned
    if(-not $review.RecoveryMarkerPresent -or $Transaction.State.Status -cne 'Completed' -or $state.Reconciled -ne $state.Returned){throw 'ARCH6f3c2 historical hold requires completed interrupted recovery.'}
    $p=@($Transaction.State.PlannedItems)[$state.Returned]
    if([string]$p.EntryId -ine $EntryId){throw 'ARCH6f3c2 historical hold requires exact first unprocessed identity.'}
    $last=[datetime]$steps[(1+2*$state.Returned)].Time
    [pscustomobject]@{Candidate=$p;LastReturn=$last}
}
function Save-OPAARCH6HistoricalThreat {
    [CmdletBinding()]
    param([object]$Transaction,[string]$SourceStoreId,[string]$ProfileName,[object]$Namespace,
          [object[]]$Folders,[string]$EntryId,[string]$DetectionId,[string]$AttachmentName)
    $review=Get-OPAARCH6HistoricalThreatCandidate -Transaction $Transaction -SourceStoreId $SourceStoreId -EntryId $EntryId
    $p=$review.Candidate
    $folder=@($Folders | Where-Object {[string]$_.FolderPath -ieq [string]$p.SourceFolderPath})
    if($folder.Count -ne 1){throw 'ARCH6f3c2 historical source folder not unique.'}
    $item=$null;$attachments=$null
    try{
        $item=$Namespace.GetItemFromID($EntryId,$SourceStoreId)
        Assert-OPAARCH4Candidate -Item $item -SourceFolder $folder[0] -Candidate $p
        $attachments=$item.Attachments
        $indices=@(for($i=1;$i -le [int]$attachments.Count;$i++){
            $a=$null
            try{$a=$attachments.Item($i);if([int]$a.Type -eq 1 -and [string]$a.FileName -ceq $AttachmentName){$i}}
            finally{Release-OPAComObject -Object $a}
        })
        if($indices.Count -ne 1){throw 'ARCH6f3c2 historical attachment metadata not unique; no export attempted.'}
        $matches=@(Get-OPAARCH6DefenderMatches -AttachmentName $AttachmentName -From $review.LastReturn.AddSeconds(-1) -To $review.LastReturn.AddSeconds(10) -DetectionId $DetectionId)
        if($matches.Count -ne 1){throw 'ARCH6f3c2 historical Defender evidence unavailable or ambiguous.'}
        $e=[pscustomobject][ordered]@{EntryId=$EntryId;AttachmentName=$AttachmentName;AttachmentIndex=[int]$indices[0];HResult=$null;ObservedHResult='';Reason='AttachmentBlockedByAntivirus';Defender=$matches[0];MoveAttempted=$false}
        $message=ConvertTo-OPAARCH6AntivirusMessage -Evidence $e
        $row=[ordered]@{EntryId=$EntryId;SourceFolderPath=[string]$p.SourceFolderPath;Reason=$e.Reason;Message=$message;Subject=[string]$p.Subject;Sender=[string]$p.Sender;ArchiveDate=[string]$p.ReceivedTime;Size=$p.Size;Time=[string]$e.Defender.DetectionTime}
        $data=[ordered]@{Schema='2.6.5-ARCH6f3c2.HistoricalThreat.1';SourcePst=[string]$Transaction.State.SourcePst;StoreId=$SourceStoreId;Profile=$ProfileName;TransactionId=[string]$Transaction.TransactionId;Rows=@($row)}
        $json=(ConvertTo-Json -InputObject $data -Depth 8 -Compress)+[char]10
        $path=Join-Path ([IO.Path]::GetDirectoryName($Transaction.Path)) ('ARCH6-threat-'+$Transaction.TransactionId+'.jsonl')
        if(-not [IO.File]::Exists($path)){
            $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
            $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
            try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        }
        if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) -cne $json){throw 'ARCH6f3c2 historical hold readback mismatch.'}
        [pscustomobject]@{Status='HistoricalThreatDeferred';TransactionId=$Transaction.TransactionId;EntryId=$EntryId;Deferred=1;AttachmentName=$AttachmentName;ThreatName=$e.Defender.ThreatName;DetectionId=$e.Defender.DetectionId;MoveInvocations=0;AttachmentExports=0;ProductionReady=$false}
    }finally{Release-OPAComObject -Object $attachments;Release-OPAComObject -Object $item}
}
function Get-OPAARCH6HistoricalThreatIds {
    param([string]$SourcePst,[string]$SourceStoreId,[string]$ProfileName,[string]$Directory)
    foreach($file in @(Get-ChildItem -LiteralPath $Directory -Filter 'ARCH6-threat-*.jsonl' -File)){
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH6f3c2 redirected historical hold.'}
        $raw=[IO.File]::ReadAllText($file.FullName,[Text.UTF8Encoding]::new($false,$true))
        if(-not $raw.EndsWith([string][char]10)){throw 'ARCH6f3c2 incomplete historical hold.'}
        $d=ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        if($d.Schema -cne '2.6.5-ARCH6f3c2.HistoricalThreat.1' -or [string]$d.TransactionId -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or $file.Name -cne ('ARCH6-threat-'+$d.TransactionId+'.jsonl') -or @($d.Rows).Count -ne 1){throw 'ARCH6f3c2 invalid historical hold.'}
        if($d.SourcePst -ine $SourcePst){continue}
        if($d.StoreId -ine $SourceStoreId -or $d.Profile -ine $ProfileName){throw 'ARCH6f3c2 historical hold source mismatch.'}
        $tx=Get-OPAArchiveTransaction -SourcePst $SourcePst -TransactionId $d.TransactionId
        if($tx.State.SourcePst -ine $SourcePst){throw 'ARCH6f3c2 historical checkpoint source mismatch.'}
        $r=$d.Rows[0]
        $review=Get-OPAARCH6HistoricalThreatCandidate -Transaction $tx -SourceStoreId $SourceStoreId -EntryId $r.EntryId
        $e=ConvertFrom-OPAARCH6AntivirusMessage -Message $r.Message -ExpectedEntryId $r.EntryId
        if($null -eq $e -or $null -eq $e.Defender -or $e.HResult -or $e.Reason -cne $r.Reason -or $r.SourceFolderPath -ine $review.Candidate.SourceFolderPath -or
           [datetime]$e.Defender.DetectionTime -lt $review.LastReturn.AddSeconds(-1) -or [datetime]$e.Defender.DetectionTime -gt $review.LastReturn.AddSeconds(10)){throw 'ARCH6f3c2 historical hold proof mismatch.'}
        [string]$r.EntryId
    }
}
