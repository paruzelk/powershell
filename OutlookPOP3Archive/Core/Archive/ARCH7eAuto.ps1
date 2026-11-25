#requires -Version 5.1
# ARCH7e: explicit test-only all-POP3 dispatcher. Never call the legacy Auto writer.
function Get-OPAARCH7eSourceRows {
    [CmdletBinding()]
    param([object]$Namespace,[string]$ProfileName)
    if([string]::IsNullOrWhiteSpace($ProfileName) -or [string]$Namespace.CurrentProfileName -ine $ProfileName){throw 'ARCH7e current profile identity unavailable.'}
    $accounts=@($Namespace.Accounts)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $paths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $ids=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($account in $accounts){
        if([int]$account.AccountType -ne 2){continue}
        # Direct delivery store only. Never infer POP3 ownership from display name.
        $store=$account.DeliveryStore
        if($null -eq $store -or -not $store.StoreID -or -not $store.FilePath){throw 'ARCH7e POP3 delivery store identity unavailable.'}
        $path=[IO.Path]::GetFullPath([string]$store.FilePath)
        $id=[string]$store.StoreID
        if($path.StartsWith('\\') -or [IO.Path]::GetExtension($path) -ine '.pst' -or -not [IO.File]::Exists($path) -or
           ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
           [IO.Path]::GetFileName($path) -match '\.Archive(?:[-.]|$)'){
            throw 'ARCH7e unsafe POP3 delivery PST; no automatic selection.'
        }
        if(-not $paths.Add($path) -or -not $ids.Add($id)){throw 'ARCH7e ambiguous POP3 shared delivery store; no automatic selection.'}
        $mounted=@($Namespace.Stores | Where-Object {[string]$_.StoreID -ieq $id -and [string]$_.FilePath -ieq $path})
        if($mounted.Count -ne 1){throw 'ARCH7e POP3 delivery store is not uniquely mounted.'}
        foreach($other in $accounts){
            if([int]$other.AccountType -eq 2){continue}
            $otherStore=$other.DeliveryStore
            if($null -ne $otherStore -and ([string]$otherStore.StoreID -ieq $id -or [string]$otherStore.FilePath -ieq $path)){throw 'ARCH7e non-POP3 account shares delivery store.'}
        }
        $rows.Add([pscustomobject]@{SourcePst=$path;StoreId=$id;Profile=$ProfileName;Protocol='POP3';Directory=(Join-Path ([IO.Path]::GetDirectoryName($path)) 'OutlookPOP3Archive-Transactions')})
    }
    return @($rows.ToArray() | Sort-Object SourcePst)
}
function Get-OPAARCH7ePendingOwner {
    [CmdletBinding()]
    param([string]$Directory,[object[]]$Sources)
    if(-not [IO.Directory]::Exists($Directory)){return $null}
    if(([IO.File]::GetAttributes($Directory) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH7e redirected transaction directory.'}
    $path=Join-Path $Directory 'ARCH4.pending'
    if(-not [IO.File]::Exists($path)){return $null}
    if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH7e redirected pending.'}
    $p=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false,$true))) -ErrorAction Stop
    $owners=@($Sources | Where-Object {$_.SourcePst -ieq [string]$p.SourcePst -and $_.StoreId -ieq [string]$p.SourceStoreId -and $_.Profile -ieq [string]$p.Profile})
    if($owners.Count -ne 1){throw 'ARCH7e pending owner is not a uniquely discovered POP3 source.'}
    $checked=Get-OPAARCH7dPending -Directory $Directory -SourcePst $owners[0].SourcePst -ProfileName $owners[0].Profile
    if($null -eq $checked -or $checked.TransactionId -cne $p.TransactionId -or $checked.SourceStoreId -ine $owners[0].StoreId){throw 'ARCH7e pending changed during owner check.'}
    return $owners[0]
}
function Invoke-OPAARCH7eSourceSequence {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Sources,[scriptblock]$PendingOwner,[scriptblock]$RunSource,
          [ValidateRange(1,100)][int]$MaxBatchesPerSource)
    $results=New-Object 'System.Collections.Generic.List[object]'
    $halt=$false
    # Group by original directory-wide lease/pending. No migration, no overwrite.
    foreach($group in @($Sources | Group-Object Directory | Sort-Object Name)){
        $members=@($group.Group | Sort-Object SourcePst)
        $owner=$null
        try{$owner=& $PendingOwner $group.Name $members}
        catch{
            foreach($member in $members){$results.Add([pscustomobject]@{SourcePst=$member.SourcePst;Status='DirectoryBlocked';Verified=0;Deferred=0;Batches=0;Detail=$_.Exception.Message})}
            continue
        }
        $ordered=@()
        if($null -ne $owner){$ordered+=@($owner)}
        $ordered+=@($members | Where-Object {$null -eq $owner -or $_.SourcePst -ine $owner.SourcePst})
        $directoryBlocked=$false
        foreach($member in $ordered){
            if($halt -or $directoryBlocked){
                $results.Add([pscustomobject]@{SourcePst=$member.SourcePst;Status='NotRunBlocked';Verified=0;Deferred=0;Batches=0})
                continue
            }
            $verified=0;$deferred=0;$batches=0;$attempts=0;$status='BatchLimitReached';$last=$null;$detail=''
            while($attempts -lt $MaxBatchesPerSource){
                try{
                    $current=& $PendingOwner $group.Name $members
                    if($null -ne $current -and $current.SourcePst -ine $member.SourcePst){$status='DirectoryBlocked';$directoryBlocked=$true;break}
                    # Single verified batch per call. Preserve existing controller and
                    # worker identities. Never re-enter Archive after uncertain result.
                    $last=& $RunSource $member
                    $attempts++
                    if($null -eq $last -or @($last).Count -ne 1 -or $last.Schema -cne '2.6.5-ARCH7d.Supervisor.1' -or
                       $last.ProductionReady -ne $false -or $last.AutomaticMoveRetryAllowed -ne $false -or $last.OutlookRestartRequired -ne $false -or
                       [int]$last.Batches -lt 0 -or [int]$last.Batches -gt 1 -or [int]$last.Verified -lt 0 -or [int]$last.Deferred -lt 0 -or
                       [int]$last.Unprocessed -lt 0 -or ([int]$last.Verified+[int]$last.Deferred+[int]$last.Unprocessed) -gt 10){
                        throw 'ARCH7e invalid source supervisor result.'
                    }
                    $verified+=[int]$last.Verified;$deferred+=[int]$last.Deferred;$batches+=[int]$last.Batches
                    $status=[string]$last.Status
                    if($status -cin @('WorkerStillRunning','WorkerExitCodeUnavailable','RecoveryExitWithoutEvidence')){$halt=$true;break}
                    if($status -cin @('NoEligibleFolders','NoEligibleMessages')){
                        if($null -ne (& $PendingOwner $group.Name $members)){throw 'ARCH7e exhaustion with pending.'}
                        $status='Exhausted';break
                    }
                    if($status -cnotin @('BatchLimitReached','RecoveredPendingBatch')){
                        # Known completed worker failure: leave this source blocked.
                        if($null -ne (& $PendingOwner $group.Name $members)){$directoryBlocked=$true}
                        break
                    }
                    if($null -ne (& $PendingOwner $group.Name $members)){throw 'ARCH7e verified batch still has pending.'}
                    if([int]$last.Batches -ne 1){throw 'ARCH7e missing completed batch.'}
                    if(([int]$last.Verified+[int]$last.Deferred) -eq 0){
                        $status='StoppedNoProgress';break
                    }
                    # After successful interrupted recovery, select a fresh batch
                    # from current source, not the historical unprocessed EntryIDs.
                    $status='BatchLimitReached'
                }catch{
                    $status='SupervisorException';$detail=$_.Exception.Message
                    # Cannot prove an exception occurred before child start/exit.
                    $halt=$true;break
                }
            }
            $results.Add([pscustomobject]@{SourcePst=$member.SourcePst;Status=$status;Verified=$verified;Deferred=$deferred;Batches=$batches;Attempts=$attempts;LastResult=$last;Detail=$detail})
        }
        if($halt){break}
    }
    if($halt){
        foreach($member in $Sources){
            if(@($results | Where-Object {$_.SourcePst -ieq $member.SourcePst}).Count -eq 0){$results.Add([pscustomobject]@{SourcePst=$member.SourcePst;Status='NotRunBlocked';Verified=0;Deferred=0;Batches=0})}
        }
    }
    $all=@($results.ToArray())
    $status=if($Sources.Count -eq 0){'NoPop3Sources'}elseif(@($all | Where-Object {$_.Status -cne 'Exhausted'}).Count -eq 0){'AllSourcesExhausted'}else{'PartialOrBlocked'}
    [pscustomobject]@{Schema='2.6.5-ARCH7e.Auto.1';Status=$status;SourcesDiscovered=$Sources.Count;SourcesExhausted=@($all | Where-Object {$_.Status -ceq 'Exhausted'}).Count;Verified=[long](($all | Measure-Object Verified -Sum).Sum);Deferred=[long](($all | Measure-Object Deferred -Sum).Sum);Sources=$all;OutlookRestartRequired=$false;AutomaticMoveRetryAllowed=$false;ProductionReady=$false}
}
function Invoke-OPAARCH7eAuto {
    [CmdletBinding()]
    param([string]$ProjectRoot,[string]$ProfileName,[int]$BatchSize,[int]$MaxBatchesPerSource,
          [int]$OlderThanMonths,[string]$ArchiveGrouping,[switch]$IncludeRootMail,[int]$MaxResumeAttempts)
    . (Join-Path $ProjectRoot 'Core/Runtime/ComManager.ps1')
    . (Join-Path $ProjectRoot 'Core/Archive/ARCH7dSupervisor.ps1')
    $safeUser=(("{0}_{1}" -f [string]$env:USERDOMAIN,[string]$env:USERNAME) -replace '[^A-Za-z0-9_.-]','_')
    $mutex=[Threading.Mutex]::new($false,("Global\OutlookPOP3Archive-ARCH7e-"+$safeUser))
    $held=$false;$session=$null
    try{
        try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){throw 'ARCH7e another Auto dispatcher is active.'}
        # Release discovery COM objects before launching any worker.
        $session=New-OPAComSession -ProfileName $ProfileName -AttachOnly
        try{$sourceRows=@(Get-OPAARCH7eSourceRows -Namespace $session.Namespace -ProfileName $session.ProfileName)}
        finally{Close-OPAComSession -Session $session;$session=$null}
        $arch7eControllerPath=Join-Path $ProjectRoot 'Invoke-OPALiveArchiveBatches.ps1'
        $arch7eCommon=@{ConfirmTestArchive=$true;ConfirmLiveOutlookVerification=$true;BatchSize=$BatchSize;MaxBatches=1;OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping;IncludeRootMail=[bool]$IncludeRootMail;MaxResumeAttempts=$MaxResumeAttempts}
        $arch7eRead={param($directory,$members) Get-OPAARCH7ePendingOwner -Directory $directory -Sources $members}
        $arch7eRun={
            param($row)
            $params=$arch7eCommon.Clone();$params.SourcePst=$row.SourcePst;$params.ProfileName=$row.Profile
            & $arch7eControllerPath @params
        }
        Invoke-OPAARCH7eSourceSequence -Sources $sourceRows -PendingOwner $arch7eRead -RunSource $arch7eRun -MaxBatchesPerSource $MaxBatchesPerSource
    }finally{
        if($null -ne $session){Close-OPAComSession -Session $session}
        if($held){[void]$mutex.ReleaseMutex()}
        $mutex.Dispose()
    }
}
