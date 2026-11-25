#requires -Version 5.1
# No Outlook COM in supervisor. Child holds original Archive/Resume mutex.
function Get-OPAARCH7dPending {
    [CmdletBinding()]
    param([string]$Directory,[string]$SourcePst,[string]$ProfileName)
    $path=Join-Path $Directory 'ARCH4.pending'
    if(-not [IO.File]::Exists($path)){return $null}
    if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH7d redirected pending.'}
    $p=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false,$true))) -ErrorAction Stop
    if($p.Schema -cne '2.6.5-ARCH4.Pending.1' -or $p.VerificationPolicy -cne 'ARCH7bFreshWorkerSameOutlook' -or
       $p.DeferredPolicy -ne $true -or [string]$p.SourcePst -ine $SourcePst -or [string]$p.Profile -ine $ProfileName -or
       [string]$p.TransactionId -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or -not $p.SourceStoreId){
        throw 'ARCH7d foreign or invalid pending; preserve it.'
    }
    return $p
}
function New-OPAARCH7dWorkerCommand {
    [CmdletBinding()]
    param([string]$Main,[hashtable]$Parameters,[string]$WorkerLease,[string]$ResponsePath)
    $data=[ordered]@{Main=$Main;Parameters=$Parameters;WorkerLease=$WorkerLease;ResponsePath=$ResponsePath}
    $json=ConvertTo-Json -InputObject $data -Depth 8 -Compress
    $payload=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($json))
    # Base64 only is interpolated. All paths, folder names and parameters stay data.
    $body=@'
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Console]::OutputEncoding
$c=ConvertFrom-Json -InputObject ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('__PAYLOAD__')))
$lease=$null
try{
    $lease=[IO.FileStream]::new([string]$c.WorkerLease,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $invoke=@{}
    foreach($prop in $c.Parameters.PSObject.Properties){$invoke[$prop.Name]=$prop.Value}
    $r=@(& ([string]$c.Main) @invoke)
    if($r.Count -ne 1 -or -not $r[0].Schema -or -not $r[0].Status){throw 'ARCH7d missing unique worker response.'}
    $json=ConvertTo-Json -InputObject $r[0] -Depth 12 -Compress
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
    $fs=[IO.FileStream]::new([string]$c.ResponsePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
}catch{
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}finally{if($null -ne $lease){$lease.Dispose()}}
exit 0
'@
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body.Replace('__PAYLOAD__',$payload)))
}
function Invoke-OPAARCH7dWorker {
    [CmdletBinding()]
    param([string]$Main,[hashtable]$Parameters,[string]$Directory,[string]$LogDirectory,[int]$TimeoutSeconds)
    $id=[guid]::NewGuid().ToString('N')
    $response=Join-Path $LogDirectory ($id+'.result.json')
    $stdout=Join-Path $LogDirectory ($id+'.stdout.log')
    $stderr=Join-Path $LogDirectory ($id+'.stderr.log')
    $encoded=New-OPAARCH7dWorkerCommand -Main $Main -Parameters $Parameters -WorkerLease (Join-Path $Directory 'ARCH7d.worker.lease') -ResponsePath $response
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $process=Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-STA','-NonInteractive','-EncodedCommand',$encoded) -WorkingDirectory ([IO.Path]::GetDirectoryName($Main)) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    try{
        # Windows PowerShell 5.1 Start-Process -PassThru may return a Process
        # with only its PID. Cache the CLR handle BEFORE waiting for exit;
        # after a short-lived process exits, reopening by PID is unreliable.
        $workerId=[int]$process.Id
        $handle=[Diagnostics.Process].GetProperty('Handle').GetValue($process)
        if($null -eq $handle -or $handle -eq [IntPtr]::Zero){throw 'ARCH7d1 worker handle unavailable; no further worker launch.'}
        if(-not $process.WaitForExit($TimeoutSeconds*1000)){
            # Never kill an active worker: it may be inside Outlook Move.
            return [pscustomobject]@{Exited=$false;ExitCode=$null;WorkerId=$workerId;Result=$null;Log=$stdout;ErrorLog=$stderr}
        }
        # The bounded wait has already observed exit. Finish the redirected
        # output drain, then read the original CLR property (not PS adaptation).
        $process.WaitForExit()
        $code=$null;$result=$null;$exitCodeError=''
        try{
            $raw=[Diagnostics.Process].GetProperty('ExitCode').GetValue($process)
            if($raw -isnot [int]){throw 'ARCH7d1 worker exit code is not an Int32.'}
            $code=$raw
        }catch{$exitCodeError=$_.Exception.Message}
        if($null -eq $code){
            return [pscustomobject]@{Exited=$true;ExitCode=$null;ExitCodeError=$exitCodeError;WorkerId=$workerId;Result=$null;Log=$stdout;ErrorLog=$stderr}
        }
        if($code -eq 0 -and [IO.File]::Exists($response)){
            $result=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($response,[Text.UTF8Encoding]::new($false,$true))) -ErrorAction Stop
        }
        return [pscustomobject]@{Exited=$true;ExitCode=$code;WorkerId=$workerId;Result=$result;Log=$stdout;ErrorLog=$stderr}
    }finally{$process.Dispose()}
}
function Invoke-OPAARCH7dSequence {
    [CmdletBinding()]
    param([scriptblock]$ReadPending,[scriptblock]$Archive,[scriptblock]$Resume,[scriptblock]$Record,
          [ValidateRange(1,100)][int]$MaxBatches=1,[ValidateRange(1,10)][int]$MaxResumeAttempts=3,
          [ValidateRange(0,300)][int]$RetryDelaySeconds=5,[switch]$RecoverOnly)
    $verified=0;$deferred=0;$unprocessed=0;$batches=0;$archives=0;$recoveries=0;$last=''
    $status='BatchLimitReached';$lastRecovery=$null;$lastArchiveExitCode=$null;$lastArchiveWorkerId=$null
    while($batches -lt $MaxBatches){
        $p=& $ReadPending
        if($null -eq $p){
            if($RecoverOnly){$status='NoPendingBatch';break}
            $a=& $Archive
            $archives++;$lastArchiveExitCode=$a.ExitCode;$lastArchiveWorkerId=$a.WorkerId
            & $Record 'ArchiveWorker' $a
            if(-not $a.Exited){$status='WorkerStillRunning';break}
            if($a.ExitCode -isnot [int]){$status='WorkerExitCodeUnavailable';break}
            $p=& $ReadPending
            if($null -eq $p){
                if($a.ExitCode -ne 0 -or $null -eq $a.Result){$status='ArchiveFailedWithoutPending';break}
                $r=$a.Result
                if($r.Status -ceq 'NoEligibleFolders'){$status='NoEligibleFolders';break}
                if($r.Schema -cne '2.6.5-ARCH4.Completed.1' -or $r.Status -cne 'BatchCompletedNoMoves' -or [int]$r.Planned -lt 0 -or [int]$r.Planned -gt 10 -or $r.PSObject.Properties.Name -notcontains 'DeferredRecorded' -or [int]$r.Verified -ne 0 -or [int]$r.Indexed -ne 0 -or [int]$r.DeferredRecorded -ne [int]$r.Planned){throw 'ARCH7d unproven Archive completion; no next batch.'}
                $deferred+=[int]$r.DeferredRecorded;$batches++
                if([int]$r.Planned -eq 0){$status='NoEligibleMessages';break}
                continue
            }
            if($a.ExitCode -eq 0 -and ($null -eq $a.Result -or $a.Result.Status -cne 'BatchReturnedFreshWorkerResumeRequired' -or $a.Result.TransactionId -cne $p.TransactionId)){throw 'ARCH7d mismatched Archive response/pending.'}
            if($p.MoveWorkerId -ne $a.WorkerId){throw 'ARCH7d pending not owned by launched Archive worker.'}
        }
        $last=[string]$p.TransactionId
        $completed=$false
        for($attempt=1;$attempt -le $MaxResumeAttempts;$attempt++){
            $current=& $ReadPending
            if($null -eq $current -or $current.TransactionId -cne $last){throw 'ARCH7d pending changed before recovery.'}
            $v=& $Resume $last
            $recoveries++
            & $Record 'ResumeWorker' $v
            if(-not $v.Exited){$status='WorkerStillRunning';break}
            if($v.ExitCode -isnot [int]){$status='WorkerExitCodeUnavailable';break}
            $after=& $ReadPending
            if($null -ne $after -and $after.TransactionId -cne $last){throw 'ARCH7d pending identity changed after recovery.'}
            if($v.ExitCode -eq 0 -and $null -ne $v.Result -and $null -eq $after){
                $r=$v.Result
                if($r.Schema -cne '2.6.5-ARCH4.Completed.1' -or $r.Status -cne 'LiveInterruptedBatchRecovered' -or $r.TransactionId -cne $last -or
                   -not $r.PendingCleared -or $r.OutlookRestartRequired -ne $false -or $r.VerifyWorkerId -ne $v.WorkerId -or
                   $r.MoveWorkerId -ne $p.MoveWorkerId -or $r.VerifyWorkerId -eq $p.MoveWorkerId -or
                   [int]$r.MoveInvocations -ne 0 -or [int]$r.Verified -ne [int]$r.Reconciled -or [int]$r.Verified -ne [int]$r.Indexed -or
                   [int]$r.Verified -lt 0 -or [int]$r.Deferred -lt 0 -or [int]$r.Unprocessed -lt 0 -or
                   [int]$r.Deferred -ne [int]$r.DeferredRecorded -or
                   [int]$r.Planned -lt 0 -or [int]$r.Planned -gt 10 -or
                   [int]$r.Planned -ne ([int]$r.Verified+[int]$r.Deferred+[int]$r.Unprocessed)){
                    throw 'ARCH7d invalid recovery result; no next batch.'
                }
                $verified+=[int]$r.Verified;$deferred+=[int]$r.Deferred;$unprocessed+=[int]$r.Unprocessed
                $batches++;$completed=$true;$lastRecovery=$r
                if($RecoverOnly -or [int]$r.Unprocessed -gt 0){$status='RecoveredPendingBatch'}
                break
            }
            if($null -eq $after){$status='RecoveryExitWithoutEvidence';break}
            $status='RecoveryAttemptsExhausted'
            if($attempt -lt $MaxResumeAttempts -and $RetryDelaySeconds -gt 0){Start-Sleep -Seconds $RetryDelaySeconds}
        }
        if(-not $completed -or $RecoverOnly -or $unprocessed -gt 0){break}
        $status='BatchLimitReached'
    }
    return [pscustomobject]@{Schema='2.6.5-ARCH7d.Supervisor.1';Status=$status;Batches=$batches;Verified=$verified;Deferred=$deferred;Unprocessed=$unprocessed;ArchiveWorkers=$archives;ResumeWorkers=$recoveries;LastTransactionId=$last;LastArchiveExitCode=$lastArchiveExitCode;LastArchiveWorkerId=$lastArchiveWorkerId;LastRecovery=$lastRecovery;OutlookRestartRequired=$false;AutomaticMoveRetryAllowed=$false;ProductionReady=$false}
}
