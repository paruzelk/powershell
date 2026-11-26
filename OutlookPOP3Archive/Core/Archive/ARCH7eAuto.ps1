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
          [ValidateRange(1,100)][int]$MaxBatchesPerSource,[ValidateRange(0,300)][int]$BatchDelaySeconds=0,[scriptblock]$Record)
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
                    if($Record){& $Record 'Batch' $member $last}
                    if($status -cin @('WorkerStillRunning','WorkerExitCodeUnavailable','RecoveryExitWithoutEvidence')){$halt=$true;break}
                    if($status -cin @('NoEligibleFolders','NoEligibleMessages')){
                        if($null -ne (& $PendingOwner $group.Name $members)){throw 'ARCH7e exhaustion with pending.'}
                        $status='Exhausted';break
                    }
                    if($status -cnotin @('BatchLimitReached','RecoveredPendingBatch')){
                        if($status -cnotin @('RecoveryAttemptsExhausted','ArchiveFailedWithoutPending')){throw 'ARCH7e unknown supervisor status.'}
                        # Known completed worker failure: leave this source blocked.
                        if($null -ne (& $PendingOwner $group.Name $members)){$directoryBlocked=$true}
                        break
                    }
                    if($null -ne (& $PendingOwner $group.Name $members)){throw 'ARCH7e verified batch still has pending.'}
                    if([int]$last.Batches -ne 1){throw 'ARCH7e missing completed batch.'}
                    if($null -ne $last.LastBatchResult -and (Test-OPAARCH6ExportFailureBurst -Result $last.LastBatchResult)){$status='StoppedOnExportFailureBurst';break}
                    if(([int]$last.Verified+[int]$last.Deferred) -eq 0){
                        $status='StoppedNoProgress';break
                    }
                    # After successful interrupted recovery, select a fresh batch
                    # from current source, not the historical unprocessed EntryIDs.
                    $status='BatchLimitReached'
                    if($attempts -lt $MaxBatchesPerSource -and $BatchDelaySeconds -gt 0){Start-Sleep -Seconds $BatchDelaySeconds}
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
          [int]$OlderThanMonths,[string]$ArchiveGrouping,[switch]$IncludeRootMail,[int]$MaxResumeAttempts,
          [ValidateRange(0,300)][int]$BatchDelaySeconds=0,[ValidateRange(5,300)][int]$RetryDelaySeconds=5,[scriptblock]$Record)
    . (Join-Path $ProjectRoot 'Core/Runtime/ComManager.ps1')
    . (Join-Path $ProjectRoot 'Core/Archive/ARCH7dSupervisor.ps1')
    . (Join-Path $ProjectRoot 'Core/Archive/ARCH6Orchestration.ps1')
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
        $arch7eRetryDelay=$RetryDelaySeconds
        $arch7eRead={param($directory,$members) Get-OPAARCH7ePendingOwner -Directory $directory -Sources $members}
        $arch7eRun={
            param($row)
            $params=$arch7eCommon.Clone();$params.SourcePst=$row.SourcePst;$params.ProfileName=$row.Profile
            if($arch7eRetryDelay -ne 5){$params.RetryDelaySeconds=$arch7eRetryDelay}
            & $arch7eControllerPath @params
        }
        Invoke-OPAARCH7eSourceSequence -Sources $sourceRows -PendingOwner $arch7eRead -RunSource $arch7eRun -MaxBatchesPerSource $MaxBatchesPerSource -BatchDelaySeconds $BatchDelaySeconds -Record $Record
    }finally{
        if($null -ne $session){Close-OPAComSession -Session $session}
        if($held){[void]$mutex.ReleaseMutex()}
        $mutex.Dispose()
    }
}

# ARCH7f: private diagnostic summaries; original evidence is never rotated.
function Get-OPAARCH7fExitCode {
    [CmdletBinding()]
    param([object]$Result)
    if($null -eq $Result -or $Result.Schema -cne '2.6.5-ARCH7e.Auto.1' -or $Result.ProductionReady -ne $false){return 30}
    if($Result.Status -cin @('AllSourcesExhausted','NoPop3Sources')){return 0}
    if($Result.Status -ceq 'PartialOrBlocked'){
        $rows=@($Result.Sources)
        if($rows.Count -gt 0 -and @($rows | Where-Object {$_.Status -cnotin @('Exhausted','BatchLimitReached')}).Count -eq 0){return 10}
        return 20
    }
    return 30
}
function New-OPAARCH7fLogRoot {
    [CmdletBinding()]
    param([string]$BaseDirectory)
    if([string]::IsNullOrWhiteSpace($BaseDirectory) -or -not [IO.Directory]::Exists($BaseDirectory)){throw 'ARCH7f local diagnostic base unavailable.'}
    $base=[IO.Path]::GetFullPath($BaseDirectory)
    if($base.StartsWith('\\') -or ([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH7f redirected diagnostic base.'}
    $path=Join-Path $base 'OutlookPOP3Archive-ARCH7f'
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    if(-not [IO.Directory]::Exists($path)){
        $security=[Security.AccessControl.DirectorySecurity]::new()
        $security.SetOwner($sid)
        $security.SetAccessRuleProtection($true,$false)
        $rule=[Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        $security.AddAccessRule($rule)
        [void][IO.Directory]::CreateDirectory($path,$security)
    }
    if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH7f redirected diagnostic directory.'}
    $acl=[IO.Directory]::GetAccessControl($path)
    if(-not $acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value){throw 'ARCH7f diagnostic directory not private.'}
    foreach($access in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($access.AccessControlType -eq 'Allow' -and $access.IdentityReference.Value -ne $sid.Value){throw 'ARCH7f unexpected diagnostic directory access.'}
    }
    return $path
}
function Write-OPAARCH7fDiagnostic {
    [CmdletBinding()]
    param([IO.FileStream]$Stream,[string]$Phase,[object]$Data)
    $row=[ordered]@{TimeUtc=[DateTime]::UtcNow.ToString('o');Phase=$Phase;Data=$Data}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $row -Compress -Depth 8)+[char]10)
    $Stream.Write($bytes,0,$bytes.Length)
    $Stream.Flush($true)
}
function Remove-OPAARCH7fExpiredDiagnostics {
    [CmdletBinding()]
    param([string]$Directory,[ValidateRange(1,3650)][int]$RetentionDays,[DateTime]$NowUtc=[DateTime]::UtcNow)
    foreach($file in [IO.Directory]::EnumerateFiles($Directory,'ARCH7f-*.complete.jsonl',[IO.SearchOption]::TopDirectoryOnly)){
        if([IO.Path]::GetFileName($file) -cnotmatch '^ARCH7f-[0-9a-f]{32}\.complete\.jsonl$' -or
           ([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
        if([IO.File]::GetLastWriteTimeUtc($file) -lt $NowUtc.AddDays(-$RetentionDays)){[IO.File]::Delete($file)}
    }
}
function Invoke-OPAARCH7fQuietAuto {
    [CmdletBinding()]
    param([hashtable]$AutoParameters,[ValidateRange(1,3650)][int]$RetentionDays=30)
    $arch7fRoot=New-OPAARCH7fLogRoot -BaseDirectory ([Environment]::GetFolderPath('LocalApplicationData'))
    $arch7fId='ARCH7f-'+[guid]::NewGuid().ToString('N')
    $arch7fPath=Join-Path $arch7fRoot ($arch7fId+'.jsonl')
    $arch7fStream=[IO.FileStream]::new($arch7fPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $arch7fExit=30
    try{
        Write-OPAARCH7fDiagnostic -Stream $arch7fStream -Phase Start -Data @{Pid=$PID;BatchSize=$AutoParameters.BatchSize;MaxBatchesPerSource=$AutoParameters.MaxBatchesPerSource;OlderThanMonths=$AutoParameters.OlderThanMonths;ArchiveGrouping=$AutoParameters.ArchiveGrouping;BatchDelaySeconds=$AutoParameters.BatchDelaySeconds;RetryDelaySeconds=$AutoParameters.RetryDelaySeconds}
        try{Remove-OPAARCH7fExpiredDiagnostics -Directory $arch7fRoot -RetentionDays $RetentionDays}
        catch{Write-OPAARCH7fDiagnostic -Stream $arch7fStream -Phase RetentionWarning -Data @{Message=$_.Exception.Message}}
        $arch7fRecord={
            param($phase,$row,$data)
            Write-OPAARCH7fDiagnostic -Stream $arch7fStream -Phase $phase -Data @{SourcePst=$row.SourcePst;Status=$data.Status;Verified=$data.Verified;Deferred=$data.Deferred;Unprocessed=$data.Unprocessed;TransactionId=$data.LastTransactionId;WorkerLogDirectory=$data.LogDirectory;ArchiveExitCode=$data.LastArchiveExitCode}
        }
        $arch7fParams=$AutoParameters.Clone()
        $arch7fParams.Record=$arch7fRecord
        $arch7fResult=Invoke-OPAARCH7eAuto @arch7fParams 3>$null 4>$null 5>$null 6>$null
        $arch7fExit=Get-OPAARCH7fExitCode -Result $arch7fResult
        foreach($arch7fSource in @($arch7fResult.Sources)){
            Write-OPAARCH7fDiagnostic -Stream $arch7fStream -Phase Source -Data @{SourcePst=$arch7fSource.SourcePst;Status=$arch7fSource.Status;Verified=$arch7fSource.Verified;Deferred=$arch7fSource.Deferred;Batches=$arch7fSource.Batches;Detail=$arch7fSource.Detail}
        }
        Write-OPAARCH7fDiagnostic -Stream $arch7fStream -Phase Completed -Data @{Status=$arch7fResult.Status;Verified=$arch7fResult.Verified;Deferred=$arch7fResult.Deferred;ExitCode=$arch7fExit}
    }catch{
        try{Write-OPAARCH7fDiagnostic -Stream $arch7fStream -Phase Failed -Data @{Message=$_.Exception.Message;Type=$_.Exception.GetType().FullName;HResult=$_.Exception.HResult}}catch{}
        throw
    }finally{$arch7fStream.Dispose()}
    if($arch7fExit -in @(0,10)){
        $arch7fFinal=Join-Path $arch7fRoot ($arch7fId+'.complete.jsonl')
        [IO.File]::Move($arch7fPath,$arch7fFinal)
        $arch7fPath=$arch7fFinal
    }
    $arch7fResult | Add-Member -NotePropertyMembers @{DiagnosticLog=$arch7fPath;ExitCode=$arch7fExit}
    return $arch7fResult
}
