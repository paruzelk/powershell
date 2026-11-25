#requires -Version 5.1
# ARCH4 controlled test batch: original selection, mover, witness and verifier.
# One pending batch per shared-index directory. Resume only reconciles receipts.
. (Join-Path $PSScriptRoot 'OperationJournal.ps1')
. (Join-Path $PSScriptRoot 'ARCH6Deferred.ps1')

function Assert-OPAARCH4Candidate {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Item,
          [Parameter(Mandatory=$true)][object]$SourceFolder,
          [Parameter(Mandatory=$true)][object]$Candidate,
          [Nullable[datetime]]$Cutoff)
    $parent=$null
    try {
        $parent=$Item.Parent
        if($null -eq $parent -or [int]$Item.Class -ne 43 -or
           [string]$Item.EntryID -ine [string]$Candidate.EntryID -or
           [string]$parent.EntryID -ine [string]$SourceFolder.EntryID -or
           [string]$parent.StoreID -ine [string]$SourceFolder.StoreID -or
           [string]$Item.Subject -cne [string]$Candidate.Subject -or
           [string](Get-OPAInternetMessageId -Item $Item) -cne [string]$Candidate.InternetMessageId){
            throw 'ARCH4 selected mail no longer matches source identity/folder.'
        }
        $store=$SourceFolder.Store
        $map=Get-OPAWellKnownFolderEntryIds -Store $store
        $sent=Test-OPASentLikeFolder -Name ([string]$SourceFolder.Name) -EntryID ([string]$SourceFolder.EntryID) -WellKnownEntryIdMap $map -FolderPath ([string]$SourceFolder.FolderPath) -Store $store
        $date=Get-OPAArchiveItemDate -Item $Item -PreferSentOn:$sent
        if($null -eq $date -or ([datetime]$date).Ticks -ne ([datetime]$Candidate.ReceivedTime).Ticks -or
           ($null -ne $Cutoff -and $date -ge $Cutoff)){
            throw 'ARCH4 selected mail date/cutoff changed before claim.'
        }
    } finally { Release-OPAComObject -Object $parent }
}

function Assert-OPAARCH4Destination {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Namespace,
          [Parameter(Mandatory=$true)][object]$SourceFolder,
          [Parameter(Mandatory=$true)][object]$Destination)
    $id=[string]$Destination.Store.StoreID
    if(-not $id -or $id -ieq [string]$SourceFolder.StoreID -or
       $id -ine [string]$Destination.Folder.StoreID -or
       [IO.Path]::GetFullPath([string]$Destination.Store.FilePath) -ine [IO.Path]::GetFullPath([string]$Destination.Path) -or
       $id -ieq [string]$Namespace.DefaultStore.StoreID){
        throw 'ARCH4 destination is not a distinct archive store.'
    }
    foreach($account in @($Namespace.Accounts)){
        $delivery=$account.DeliveryStore
        if($null -ne $delivery -and [string]$delivery.StoreID -ieq $id){
            throw 'ARCH4 destination is an account delivery store.'
        }
    }
}

function Assert-OPAARCH5Route {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][datetime]$ArchiveDate,
          [Parameter(Mandatory=$true)][string]$SourceFolderPath,
          [Parameter(Mandatory=$true)][string]$TargetFolderPath,
          [Parameter(Mandatory=$true)][string]$ArchivePst,
          [Parameter(Mandatory=$true)][string]$Grouping)
    $parts=@($TargetFolderPath -split '\\' | Where-Object {$_})
    $relative=($parts | Select-Object -Skip 1) -join '\'
    $expected=Get-OPAArchiveTargetPath -ReceivedTime $ArchiveDate -SourceFolderPath $SourceFolderPath -Grouping $Grouping
    $base=[regex]::Escape([IO.Path]::GetFileNameWithoutExtension($SourcePst))
    $year=$ArchiveDate.Year
    if($parts.Count -lt 2 -or $relative -ine $expected -or
       [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ArchivePst)) -ine [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($SourcePst)) -or
       [IO.Path]::GetFileName($ArchivePst) -inotmatch ('^'+$base+'\.Archive-'+$year+'(?:-\d{2,})?\.pst$')){
        throw 'ARCH5 ArchiveRouteMismatch: destination year/part or folder hierarchy differs from selected source.'
    }
}

function Select-OPAARCH5SourceFolders {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$EligibleFolders,[string[]]$IncludeFolderPath)
    if(@($IncludeFolderPath | Where-Object {$_}).Count -eq 0){return $EligibleFolders}
    foreach($path in $IncludeFolderPath){
        if([string]::IsNullOrWhiteSpace($path) -or @($EligibleFolders | Where-Object {[string]$_.FolderPath -ieq $path}).Count -ne 1){
            throw ('ARCH5 source folder not uniquely eligible: '+$path)
        }
    }
    return @($EligibleFolders | Where-Object {$IncludeFolderPath -icontains [string]$_.FolderPath})
}

function Get-OPAARCH4OperationPath {
    param([Parameter(Mandatory=$true)][object]$Transaction)
    return ([string]$Transaction.Path -replace '\.json$','.arch4.operations.jsonl')
}

function Read-OPAARCH4StepRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not [IO.File]::Exists($Path)){throw 'ARCH4 step journal missing; preserve pending batch.'}
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length -eq 0 -or $bytes[$bytes.Length-1] -ne 10){
        throw 'ARCH4 step journal has an incomplete tail; no automatic recovery.'
    }
    $lines=([Text.UTF8Encoding]::new($false,$true)).GetString($bytes) -split '\r?\n'
    for($i=0;$i -lt ($lines.Count-1);$i++){
        if([string]::IsNullOrWhiteSpace($lines[$i])){throw 'ARCH4 empty step record.'}
        $row=ConvertFrom-Json -InputObject $lines[$i] -ErrorAction Stop
        if($null -eq $row -or $row -is [array] -or -not $row.Step){throw 'ARCH4 invalid step record.'}
        $row
    }
}

function Get-OPAARCH4ReturnedState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Transaction,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Steps,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Events,
          [Parameter(Mandatory=$true)][string]$SourceStoreId)
    $planned=@{};$claims=@{};$returns=@{};$done=@{};$ordered=New-Object 'System.Collections.Generic.List[object]'
    $archiveIds=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($p in @($Transaction.State.PlannedItems)){
        $id=[string]$p.EntryId
        if(-not $id -or $planned.ContainsKey($id)){throw 'ARCH4 invalid planned identity.'}
        $planned[$id]=$p
    }
    if($planned.Count -ne [int]$Transaction.State.Planned -or $planned.Count -gt [int]$Transaction.State.Limit){
        throw 'ARCH4 invalid durable plan.'
    }
    foreach($s in $Steps){
        $id=[string]$s.EntryId
        switch -CaseSensitive ([string]$s.Step){
            'Move Started' {
                if(-not $planned.ContainsKey($id) -or $claims.ContainsKey($id) -or
                   [string]$s.SourceFolderPath -ine [string]$planned[$id].SourceFolderPath -or
                   -not $s.ArchivePst -or -not $s.TargetFolderPath -or
                   -not (Test-OPA265ARCH2bWitnessSchema -Witness $s.SourceSemanticWitness)){
                    throw 'ARCH4 invalid or repeated pre-Move claim.'
                }
                $claims[$id]=$s
            }
            'Move Indeterminate' {throw 'ARCH4 indeterminate COM Move; manual reconciliation required; no retry.'}
            'ARCH4 Move Returned' {
                if(-not $claims.ContainsKey($id) -or $returns.ContainsKey($id) -or
                   -not $s.ArchiveEntryId -or -not $archiveIds.Add([string]$s.ArchiveEntryId)){
                    throw 'ARCH4 missing claim or duplicate provider return.'
                }
                $c=$claims[$id];$p=$planned[$id]
                if([string]$s.ArchivePst -ine [string]$c.ArchivePst -or
                   [string]$s.TargetFolderPath -ine [string]$c.TargetFolderPath -or
                   [string]$s.SourceFolderPath -ine [string]$c.SourceFolderPath){
                    throw 'ARCH4 provider receipt differs from original claim route.'
                }
                $r=[pscustomobject]@{
                    SourceEntryId=$id;ArchiveEntryId=[string]$s.ArchiveEntryId
                    ArchivePst=[string]$s.ArchivePst;TargetFolderPath=[string]$s.TargetFolderPath
                    SourceFolderPath=[string]$s.SourceFolderPath
                    InternetMessageId=[string]$p.InternetMessageId;Subject=[string]$p.Subject;Sender=[string]$p.Sender
                    Size=$p.Size;ReceivedTime=$c.ReceivedTime
                    SourceSemanticWitness=$c.SourceSemanticWitness
                }
                $returns[$id]=$r
                [void]$ordered.Add($r)
            }
            'Move Completed' {throw 'ARCH4 unexpected legacy completion; manual review.'}
            'Move Reconciled' {throw 'ARCH4 unexpected legacy reconciliation; manual review.'}
        }
    }
    if($claims.Count -ne $returns.Count){throw 'ARCH4 unresolved claim; no automatic retry or index mutation.'}
    $count=$ordered.Count;$seq=0
    foreach($e in $Events){
        $seq++
        if([long]$e.Sequence -ne $seq -or [string]$e.TransactionId -cne [string]$Transaction.TransactionId -or
           [string]$e.OperationKind -cne 'MailMove' -or
           [string]$e.OperationId -cne [string]$e.SourceEntryId -or
           [string]$e.SourceStoreId -ine $SourceStoreId){
            throw 'ARCH4 invalid operation journal sequence/identity.'
        }
        $id=[string]$e.SourceEntryId
        if(-not $returns.ContainsKey($id)){throw 'ARCH4 operation journal lacks a verified provider receipt.'}
        $r=$returns[$id]
        if([string]$e.ArchivePst -ine $r.ArchivePst -or [string]$e.TargetFolderPath -ine $r.TargetFolderPath -or
           [string]$e.SourceFolderPath -ine $r.SourceFolderPath){throw 'ARCH4 original operation route mismatch.'}
        if($seq -le $count){
            if($e.Phase -cne 'Intent' -or $id -ine $ordered[$seq-1].SourceEntryId){throw 'ARCH4 invalid Intent prefix.'}
        }else{
            $i=$seq-$count-1
            if($i -ge $count -or $e.Phase -cne 'Reconciled' -or $id -ine $ordered[$i].SourceEntryId -or
               [string]$e.ArchiveEntryId -ine $r.ArchiveEntryId){throw 'ARCH4 invalid Reconciled prefix.'}
            $done[$id]=$true
        }
    }
    if($seq -lt $count){throw 'ARCH4 original OperationJournal Intent missing.'}
    return [pscustomobject]@{Rows=@($ordered.ToArray());Claimed=$count;Returned=$count;Reconciled=$done.Count;Planned=$planned.Count;AwaitingRestart=(@($Steps | Where-Object {$_.Step -ceq 'ARCH4 Awaiting Restart'}).Count -eq 1);OperationEventCount=$Events.Count}
}

function Get-OPAARCH4OutlookProcess {
    [CmdletBinding()]
    param()
    $sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
    $p=@(Get-Process -Name OUTLOOK -ErrorAction Stop | Where-Object {$_.SessionId -eq $sessionId})
    if($p.Count -ne 1){throw 'ARCH4 requires one identifiable Outlook process in this Windows session.'}
    return [pscustomobject]@{Id=[int]$p[0].Id;StartUtcTicks=[long]$p[0].StartTime.ToUniversalTime().Ticks}
}

function Write-OPAARCH4Pending {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][object]$Record)
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Record -Depth 8 -Compress))
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Get-OPAARCH4ReturnedFromDisk {
    param([Parameter(Mandatory=$true)][object]$Transaction,[Parameter(Mandatory=$true)][string]$SourceStoreId)
    # ReadAllBytes opens a new Windows handle; flush and close the original
    # append stream first, then re-open on the next append if necessary.
    Sync-OPAStepJournalStreams
    Close-OPAStepJournalStreams
    $steps=@(Read-OPAARCH4StepRecords -Path (Get-OPAStepJournalPath -Transaction $Transaction))
    $events=@();$op=Get-OPAARCH4OperationPath -Transaction $Transaction
    if([IO.File]::Exists($op)){
        $journal=Read-OPAOperationJournal -Path $op
        if($journal.TrailingPartial){throw 'ARCH4 operation journal incomplete tail; no retry.'}
        $events=@($journal.Events)
    }
    return (Get-OPAARCH4ReturnedState -Transaction $Transaction -Steps $steps -Events $events -SourceStoreId $SourceStoreId)
}

function Complete-OPAARCH4VerifiedBatch {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Transaction,
          [Parameter(Mandatory=$true)][object]$State,
          [Parameter(Mandatory=$true)][object]$Verification,
          [Parameter(Mandatory=$true)][string]$SourceStoreId)
    if(-not $Verification.Verified -or -not $Verification.EntryIdsVerified -or
       -not $Verification.SemanticWitnessRequired -or -not $Verification.AllRequiredOriginalSemanticWitnessesPresent -or
       [int]$Verification.ExpectedMoved -ne $State.Returned -or
       [int]$Verification.ExpectedEntryIdsChecked -ne $State.Returned -or
       @($Verification.MissingEntryIds).Count -gt 0 -or @($Verification.WarningEntryIds).Count -gt 0){
        throw 'ARCH4 independent full verification failed; no journal/index commit.'
    }
    $rows=@($State.Rows);$source=[string]$Transaction.State.SourcePst
    if($rows.Count -gt 0){
        $idx=Import-OPADuplicateIndex -ArchivePst $rows[0].ArchivePst
        # Validate all conflicts before appending any Reconciled or index row.
        foreach($r in $rows){
            $e=Test-OPADuplicateEntry -Index $idx -SourceEntryId $r.SourceEntryId
            if($null -ne $e -and ([string]$e.ArchiveEntryId -ine $r.ArchiveEntryId -or
                [string]$e.ArchivePst -ine $r.ArchivePst -or [string]$e.TargetFolderPath -ine $r.TargetFolderPath -or
                [string]$e.SourcePst -ine $source -or [string]$e.TransactionId -cne [string]$Transaction.TransactionId)){
                throw 'ARCH4 conflicting shared DuplicateIndex record; no commit.'
            }
        }
        for($i=[int]$State.Reconciled;$i -lt $rows.Count;$i++){
            $r=$rows[$i]
            [void](Write-OPAOperationJournalEvent -Path (Get-OPAARCH4OperationPath -Transaction $Transaction) -TransactionId $Transaction.TransactionId -OperationId $r.SourceEntryId -Sequence ([long]($rows.Count+$i+1)) -Phase Reconciled -SourceEntryId $r.SourceEntryId -ArchiveEntryId $r.ArchiveEntryId -ArchivePst $r.ArchivePst -SourceStoreId $SourceStoreId -SourceFolderPath $r.SourceFolderPath -TargetFolderPath $r.TargetFolderPath -Message 'Independent original full semantic ArchiveVerifier passed')
        }
        $check=Get-OPAARCH4ReturnedFromDisk -Transaction $Transaction -SourceStoreId $SourceStoreId
        if($check.Reconciled -ne $rows.Count){throw 'ARCH4 Reconciled readback incomplete.'}
        foreach($r in $rows){
            if($null -eq (Test-OPADuplicateEntry -Index $idx -SourceEntryId $r.SourceEntryId)){
                Add-OPADuplicateEntry -Index $idx -SourceEntryId $r.SourceEntryId -ArchiveEntryId $r.ArchiveEntryId -ArchivePst $r.ArchivePst -SourceFolderPath $r.SourceFolderPath -TargetFolderPath $r.TargetFolderPath -ReceivedTime ([datetime]$r.ReceivedTime) -Subject $r.Subject -TransactionId $Transaction.TransactionId -TransactionLimit ([int]$Transaction.State.Limit) -ArchiveGrouping ([string]$Transaction.State.ArchiveGrouping) -SourcePst $source -OlderThanMonths ([int]$Transaction.State.OlderThanMonths) -ArchiveCutoff ([string]$Transaction.State.ArchiveCutoff)
                Sync-OPADuplicateJournalStreams
            }
        }
        Close-OPADuplicateJournalStreams
        $readback=Import-OPADuplicateIndex -ArchivePst $rows[0].ArchivePst
        foreach($r in $rows){
            $e=Test-OPADuplicateEntry -Index $readback -SourceEntryId $r.SourceEntryId
            if($null -eq $e -or [string]$e.ArchiveEntryId -ine $r.ArchiveEntryId -or
               [string]$e.ArchivePst -ine $r.ArchivePst -or [string]$e.TransactionId -cne [string]$Transaction.TransactionId){
                throw 'ARCH4 shared DuplicateIndex readback incomplete.'
            }
        }
    }
    $logical=[long]0
    foreach($r in $rows){$logical+=[long]$r.Size}
    Set-OPAArchiveTransactionCount -Transaction $Transaction -Planned $State.Planned -Executed $State.Returned -Verified $State.Returned
    Set-OPAArchiveTransactionStorageStats -Transaction $Transaction -LogicalFreedBytes $logical
    Save-OPAArchiveTransaction -Transaction $Transaction -Status Completed -Step 'ARCH4 Batch Verified' -Message ('Verified='+$State.Returned+'; Indexed='+$State.Returned) -WriteCheckpoint
    Sync-OPAStepJournalStreams
    return [pscustomobject]@{
        Schema='2.6.5-ARCH4.Completed.1';Status='BatchVerifiedReconciledAndIndexed';TransactionId=[string]$Transaction.TransactionId
        Planned=$State.Planned;Verified=$State.Returned;Reconciled=$State.Returned;Indexed=$State.Returned
        NotMoved=($State.Planned-$State.Returned);LogicalBytes=$logical
        SkipReasons=@($Transaction.State.SkippedItems | Group-Object Reason | ForEach-Object {[pscustomobject]@{Reason=$_.Name;Count=$_.Count}})
        SkippedItems=@($Transaction.State.SkippedItems)
        SkipDetailsTruncated=([int]$Transaction.State.Skipped -gt @($Transaction.State.SkippedItems).Count)
        AutomaticMoveRetryAllowed=$false;ProductionReady=$false
    }
}

function Complete-OPAARCH5aZeroMoveBatch {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Transaction,
          [Parameter(Mandatory=$true)][object]$State,
          [Parameter(Mandatory=$true)][string]$SourceStoreId)
    if($State.Claimed -ne 0 -or $State.Returned -ne 0 -or $State.Reconciled -ne 0 -or
       $State.OperationEventCount -ne 0 -or -not $State.AwaitingRestart -or
       @($State.Rows).Count -ne 0 -or [int]$Transaction.State.Executed -ne 0){
        throw 'ARCH5a no-Move completion requires a durable finished selection and zero claims, returns and operation events.'
    }
    # Vacuous verification: there is no destination item to verify and no
    # journal/index row to append. The original replay has checked the journal.
    $verification=[pscustomobject]@{Verified=$true;EntryIdsVerified=$true;SemanticWitnessRequired=$true;AllRequiredOriginalSemanticWitnessesPresent=$true;ExpectedMoved=0;ExpectedEntryIdsChecked=0;MissingEntryIds=@();WarningEntryIds=@()}
    $result=Complete-OPAARCH4VerifiedBatch -Transaction $Transaction -State $State -Verification $verification -SourceStoreId $SourceStoreId
    $result.Status='BatchCompletedNoMoves'
    $result | Add-Member -NotePropertyName RestartRequired -NotePropertyValue $false
    return $result
}

function Invoke-OPAARCH4Batch {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Archive','Resume')][string]$Mode,
          [Parameter(Mandatory=$true)][object]$Session,
          [Parameter(Mandatory=$true)][object]$Discovery,
          [Parameter(Mandatory=$true)][string]$SourcePst,
          [string]$TransactionId,
          [int]$Limit=100,[int]$OlderThanMonths=12,[string]$ArchiveGrouping='Year',
          [double]$MaxArchivePstSizeGB=10,[double]$SafetyMarginGB=0.5,
          [switch]$ARCH5Batch,[switch]$ConfirmComplexAttachments,[string[]]$IncludeFolderPath,[switch]$IncludeRootMail,[switch]$ARCH6DeferredPolicy,[string]$ImportDeferredTransaction)
    if($IncludeRootMail -and ($Mode -ne 'Archive' -or -not $ARCH5Batch)){throw 'ARCH6f2 root mail requires explicit controlled Archive.'}
    $source=[IO.Path]::GetFullPath($SourcePst)
    if($source.StartsWith('\\') -or -not [IO.File]::Exists($source) -or [IO.Path]::GetExtension($source) -ine '.pst' -or
       (([IO.File]::GetAttributes($source) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH4 explicit existing non-reparse local test PST required.'
    }
    $matches=@($Discovery.Pop3Sources | Where-Object {[IO.Path]::GetFullPath([string]$_.FilePath) -ieq $source -and $_.Protocol -eq 'POP3'})
    if($matches.Count -ne 1){throw 'ARCH4 source must identify exactly one discovered POP3 delivery PST.'}
    $s=$matches[0];$storeId=[string]$s.StoreHandle.StoreID
    $accounts=@($Session.Namespace.Accounts | Where-Object {[int]$_.AccountType -eq 2 -and [string]$_.DeliveryStore.StoreID -ieq $storeId})
    if(-not $storeId -or $accounts.Count -ne 1 -or [string]$Session.Namespace.CurrentProfileName -ne [string]$Discovery.Profile){
        throw 'ARCH4 live POP3 account/profile/store identity failed.'
    }
    $folders=@(Get-OPAPop3SourceFolders -StoreHandle $s.StoreHandle -IncludeEmptyFolders:($Mode -eq 'Resume' -or @($IncludeFolderPath | Where-Object {$_}).Count -gt 0) -IncludeRootForVerification:($Mode -eq 'Resume') -IncludeRootMail:$IncludeRootMail)
    if($folders.Count -eq 0){
        if($Mode -eq 'Archive' -and $ARCH5Batch -and @($IncludeFolderPath | Where-Object {$_}).Count -eq 0){
            # Still go through the pending lease before returning exhaustion.
            $folders=@()
        }else{throw 'ARCH4 no eligible POP3 folders.'}
    }
    if($Mode -eq 'Archive' -and $ARCH5Batch){
        $folders=@(Select-OPAARCH5SourceFolders -EligibleFolders $folders -IncludeFolderPath $IncludeFolderPath)
        foreach($folder in $folders){
            $path=[string]$folder.FolderPath
            if($path -match '^\\\\[^\\]+$' -and -not $IncludeRootMail){throw 'ARCH6f2 root selection requires -IncludeRootMail.'}
            # Reject reserved route collisions before creating a transaction.
            [void](Get-OPAArchiveTargetPath -ReceivedTime ([datetime]'2020-01-01') -SourceFolderPath $path -SourceFolderName ([string]$folder.Name) -Grouping $ArchiveGrouping)
        }
        Write-Host ('Выбрано папок POP3: '+$folders.Count)
        foreach($f in $folders){Write-Host ('  '+[string]$f.FolderPath)}
    }
    foreach($f in $folders){if([string]$f.StoreID -ine $storeId){throw 'ARCH4 foreign source folder.'}}
    $dir=Join-Path ([IO.Path]::GetDirectoryName($source)) 'OutlookPOP3Archive-Transactions'
    [void][IO.Directory]::CreateDirectory($dir)
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH4 transaction directory redirected.'}
    $pending=Join-Path $dir 'ARCH4.pending'
    $lease=[IO.FileStream]::new((Join-Path $dir 'ARCH4.lease'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $proc=Get-OPAARCH4OutlookProcess
        $global:OPADurabilityMode='Safe'
        if($Mode -eq 'Archive'){
            if([IO.File]::Exists($pending)){throw 'ARCH4 unfinished batch exists. Use Resume, never a new Archive.'}
            if($ImportDeferredTransaction){
                if($ImportDeferredTransaction -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$'){throw 'ARCH6f3a invalid historical transaction ID.'}
                $old=Get-OPAArchiveTransaction -SourcePst $source -TransactionId $ImportDeferredTransaction
                if([string]$old.State.SourcePst -ine $source -or [int]$old.State.Verified -lt 1){throw 'ARCH6f3a historical import requires completed same-source reconciled moves.'}
                $n=Save-OPAARCH6DeferredEvidence -Transaction $old -SourceStoreId $storeId -ProfileName ([string]$Discovery.Profile)
                return [pscustomobject]@{Status='DeferredImportCompleted';TransactionId=$ImportDeferredTransaction;Deferred=[int]$n;ProductionReady=$false}
            }
            $deferredIds=@()
            if($ARCH6DeferredPolicy){$deferredIds=@(Get-OPAARCH6DeferredIds -SourcePst $source -SourceStoreId $storeId -ProfileName ([string]$Discovery.Profile) -Directory $dir)}
            if($folders.Count -eq 0){return [pscustomobject]@{Schema='2.6.5-ARCH4.Status.1';Status='NoEligibleFolders';SourcePst=$source;RestartRequired=$false;AutomaticMoveRetryAllowed=$false;ProductionReady=$false}}
            # Check existing archive paths before the original destination planner can mount one.
            foreach($part in @(Get-OPAArchivePstPartsOnDiskAll -SourcePst $source)){
                $path=[string]$part.Path
                if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH4 archive part redirected.'}
                foreach($account in @($Session.Namespace.Accounts)){
                    $ds=$account.DeliveryStore
                    if($null -ne $ds -and [string]$ds.FilePath -ieq $path){throw 'ARCH4 archive path is already an account delivery PST.'}
                }
            }
            $cutoff=Get-OPAArchiveCutoff -OlderThanMonths $OlderThanMonths
            $tx=New-OPAArchiveTransaction -SourcePst $source -ArchivePst '' -Limit $Limit -ArchiveGrouping $ArchiveGrouping -OlderThanMonths $OlderThanMonths -ArchiveCutoff $cutoff -AccountEmail ([string]$s.AccountEmail) -DurabilityMode Safe
            Write-OPAARCH4Pending -Path $pending -Record ([pscustomobject]@{Schema='2.6.5-ARCH4.Pending.1';TransactionId=$tx.TransactionId;SourcePst=$source;SourceStoreId=$storeId;Profile=[string]$Discovery.Profile;MoveProcessId=$proc.Id;MoveProcessStartUtcTicks=$proc.StartUtcTicks;DeferredPolicy=[bool]$ARCH6DeferredPolicy})
            Save-OPAArchiveTransaction -Transaction $tx -Status Running -Step 'ARCH4 Batch Started' -WriteCheckpoint
            $moved=Move-OPAItemsWithLimit -Namespace $Session.Namespace -SourceFolders $folders -Transaction $tx -Limit $Limit -ArchiveGrouping $ArchiveGrouping -OlderThanCutoff $cutoff -MaxArchivePstSizeGB $MaxArchivePstSizeGB -SafetyMarginGB $SafetyMarginGB -ARCH4Batch -ARCH5Batch:$ARCH5Batch -ConfirmComplexAttachments:$ConfirmComplexAttachments -ARCH6DeferredPolicy:$ARCH6DeferredPolicy -DeferredEntryIds $deferredIds
            Save-OPAArchiveTransaction -Transaction $tx -Status Running -Step 'ARCH4 Awaiting Restart' -WriteCheckpoint
            Sync-OPAStepJournalStreams
            $state=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId $storeId
            if($state.Returned -ne [int]$moved){throw 'ARCH4 batch receipt count mismatch.'}
            if($ARCH5Batch -and $state.Returned -eq 0){
                $completed=Complete-OPAARCH5aZeroMoveBatch -Transaction $tx -State $state -SourceStoreId $storeId
                if($ARCH6DeferredPolicy){$n=Save-OPAARCH6DeferredEvidence -Transaction $tx -SourceStoreId $storeId -ProfileName ([string]$Discovery.Profile);$completed | Add-Member -NotePropertyName DeferredRecorded -NotePropertyValue ([int]$n)}
                [IO.File]::Delete($pending)
                return $completed
            }
            return [pscustomobject]@{Schema='2.6.5-ARCH4.Returned.1';Status='BatchReturnedRestartAndResumeRequired';TransactionId=$tx.TransactionId;Planned=$state.Planned;Returned=$state.Returned;NotMoved=($state.Planned-$state.Returned);OutlookProcessId=$proc.Id;SkipReasons=@($tx.State.SkippedItems | Group-Object Reason | ForEach-Object {[pscustomobject]@{Reason=$_.Name;Count=$_.Count}});SkippedItems=@($tx.State.SkippedItems);SkipDetailsTruncated=([int]$tx.State.Skipped -gt @($tx.State.SkippedItems).Count);OriginalIndexWritten=$false;AutomaticMoveRetryAllowed=$false;ProductionReady=$false}
        }
        if(-not [IO.File]::Exists($pending)){
            return [pscustomobject]@{Schema='2.6.5-ARCH4.Status.1';Status='NoPendingBatch';SourcePst=$source;RestartRequired=$false;AutomaticMoveRetryAllowed=$false;ProductionReady=$false}
        }
        $p=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($pending,[Text.Encoding]::UTF8)) -ErrorAction Stop
        if($p.Schema -cne '2.6.5-ARCH4.Pending.1' -or [string]$p.SourcePst -ine $source -or [string]$p.SourceStoreId -ine $storeId -or
           [string]$p.Profile -ine [string]$Discovery.Profile -or [string]$p.TransactionId -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
           ($TransactionId -and $TransactionId -cne [string]$p.TransactionId)){
            throw 'ARCH4 pending transaction identity mismatch.'
        }
        $tx=Get-OPAArchiveTransaction -SourcePst $source -TransactionId ([string]$p.TransactionId)
        if([string]$tx.State.SourcePst -ine $source -or [string]$tx.TransactionId -cne [string]$p.TransactionId){throw 'ARCH4 transaction identity changed.'}
        if($ARCH5Batch){
            Write-Host ('Транзакция: '+$tx.TransactionId)
            Write-Host ('Размер партии: '+$tx.State.Limit+'; группировка: '+$tx.State.ArchiveGrouping+'; возраст: '+$tx.State.OlderThanMonths+' мес.; режим записи: Safe')
        }
        $state=Get-OPAARCH4ReturnedFromDisk -Transaction $tx -SourceStoreId $storeId
        if($ARCH5Batch -and $state.Returned -eq 0){
            $completed=Complete-OPAARCH5aZeroMoveBatch -Transaction $tx -State $state -SourceStoreId $storeId
            if($p.PSObject.Properties.Name -contains 'DeferredPolicy' -and $p.DeferredPolicy -eq $true){$n=Save-OPAARCH6DeferredEvidence -Transaction $tx -SourceStoreId $storeId -ProfileName ([string]$Discovery.Profile);$completed | Add-Member -NotePropertyName DeferredRecorded -NotePropertyValue ([int]$n)}
            [IO.File]::Delete($pending)
            return $completed
        }
        if($proc.StartUtcTicks -le [long]$p.MoveProcessStartUtcTicks){throw 'ARCH4 fully restart Outlook before Resume.'}
        $stores=@()
        foreach($path in @($state.Rows | ForEach-Object {$_.ArchivePst} | Sort-Object -Unique)){
            if(-not [IO.File]::Exists($path)){throw 'ARCH4 archive PST missing; never recreate on Resume.'}
            $found=@($Session.Namespace.Stores | Where-Object {[string]$_.FilePath -ieq $path})
            if($found.Count -ne 1 -or [string]$found[0].StoreID -ieq $storeId){throw 'ARCH4 reconnect the existing archive PST to Outlook before Resume.'}
            foreach($account in @($Session.Namespace.Accounts)){
                if([string]$account.DeliveryStore.StoreID -ieq [string]$found[0].StoreID){throw 'ARCH4 archive store is an account delivery store.'}
            }
            $stores+=$found[0]
        }
        # Check absence across all eligible source folders, not a fixed inbox count.
        $result=Test-OPAArchiveMoves -Namespace $Session.Namespace -SourceFolder $folders -ArchiveStores $stores -ExpectedMoved $state.Returned -ExpectedMoves @($state.Rows) -RequireSemanticWitness -RequireSourceAbsentAcrossFolders -BoundedSourceIdMemory:$ARCH5Batch
        if($ARCH5Batch){
            foreach($r in @($state.Rows)){
                if([string]$r.SourceSemanticWitness.Schema -cin @('2.6.5-ARCH5.MailSemanticWitness.2','2.6.5-ARCH5a.MailSemanticWitness.3')){
                    Assert-OPAARCH5Route -SourcePst $source -ArchiveDate ([datetime]$r.ReceivedTime) -SourceFolderPath $r.SourceFolderPath -TargetFolderPath $r.TargetFolderPath -ArchivePst $r.ArchivePst -Grouping ([string]$tx.State.ArchiveGrouping)
                }
            }
        }
        $completed=Complete-OPAARCH4VerifiedBatch -Transaction $tx -State $state -Verification $result -SourceStoreId $storeId
        if($p.PSObject.Properties.Name -contains 'DeferredPolicy' -and $p.DeferredPolicy -eq $true){$n=Save-OPAARCH6DeferredEvidence -Transaction $tx -SourceStoreId $storeId -ProfileName ([string]$Discovery.Profile);$completed | Add-Member -NotePropertyName DeferredRecorded -NotePropertyValue ([int]$n)}
        [IO.File]::Delete($pending)
        return $completed
    } finally { $lease.Dispose() }
}
