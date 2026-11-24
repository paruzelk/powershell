#requires -Version 5.1
# ARCH6 bounded test-only orchestration. Original journals are authoritative.
function Invoke-OPAARCH6Sequence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][scriptblock]$Archive,
          [Parameter(Mandatory=$true)][scriptblock]$Resume,
          [Parameter(Mandatory=$true)][scriptblock]$Restart,
          [Parameter(Mandatory=$true)][scriptblock]$Record,
          [ValidateRange(1,500)][int]$BatchSize,
          [ValidateRange(1,2147483647)][int]$MaxMessages,
          [ValidateRange(1,100000)][int]$MaxBatches)
    $verified=0L;$logical=0L;$batches=0;$last='';$status='BatchLimitReached'
    while($batches -lt $MaxBatches -and $verified -lt $MaxMessages){
        $limit=[int][math]::Min($BatchSize,($MaxMessages-$verified))
        & $Record 'ArchiveStarting' ([pscustomobject]@{Limit=$limit;VerifiedTotal=$verified})
        $a=& $Archive $limit
        if($null -eq $a -or @($a).Count -ne 1){throw 'ARCH6 Archive returned no unique result; inspect pending, never retry automatically.'}
        if($a.Status -ceq 'NoEligibleFolders'){
            $status='NoEligibleFolders';break
        }
        if([string]$a.TransactionId -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
           [int]$a.Planned -lt 0 -or [int]$a.Planned -gt $limit){
            throw 'ARCH6 invalid Archive transaction result; no next batch.'
        }
        $last=[string]$a.TransactionId
        & $Record 'ArchiveReturned' $a
        if($a.Status -ceq 'BatchCompletedNoMoves'){
            if([int]$a.Verified -ne 0 -or [int]$a.Indexed -ne 0 -or $a.RestartRequired -ne $false){
                throw 'ARCH6 inconsistent zero-Move terminal result.'
            }
            $status=if([int]$a.Planned -eq 0){'NoEligibleMessages'}else{'StoppedOnSkippedItems'}
            $batches++;break
        }
        if($a.Status -cne 'BatchReturnedRestartAndResumeRequired' -or
           [int]$a.Returned -lt 1 -or [int]$a.Returned -gt [int]$a.Planned -or
           [int]$a.NotMoved -ne ([int]$a.Planned-[int]$a.Returned)){
            throw 'ARCH6 invalid returned batch; preserve pending.'
        }
        & $Record 'ResumeStarting' ([pscustomobject]@{TransactionId=$last;Returned=$a.Returned})
        & $Restart $last
        $r=& $Resume $last
        if($null -eq $r -or @($r).Count -ne 1 -or
           $r.Status -cne 'BatchVerifiedReconciledAndIndexed' -or
           [string]$r.TransactionId -cne $last -or
           [int]$r.Planned -ne [int]$a.Planned -or
           [int]$r.Verified -ne [int]$a.Returned -or
           [int]$r.Reconciled -ne [int]$a.Returned -or
           [int]$r.Indexed -ne [int]$a.Returned -or
           [int]$r.NotMoved -ne [int]$a.NotMoved -or [long]$r.LogicalBytes -lt 0){
            throw 'ARCH6 Resume not fully verified; no next batch.'
        }
        $verified+=[int]$r.Verified;$logical+=[long]$r.LogicalBytes;$batches++
        & $Record 'BatchVerified' $r
        # Stop on skips, including persistent oldest unsupported items.
        if([int]$r.NotMoved -gt 0){$status='StoppedOnSkippedItems';break}
        if([int]$a.Planned -lt $limit){$status='NoMoreSelectedMessages';break}
    }
    if($verified -ge $MaxMessages){$status='MessageLimitReached'}
    return [pscustomobject]@{Schema='2.6.5-ARCH6.Sequence.1';Status=$status;Batches=$batches;Verified=$verified;LogicalBytes=$logical;LastTransactionId=$last;AutomaticMoveRetryAllowed=$false;ProductionReady=$false}
}
function Get-OPAARCH6PendingRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourcePst,
          [Parameter(Mandatory=$true)][string]$ProfileName,
          [Parameter(Mandatory=$true)][string]$TransactionId)
    $dir=Join-Path ([IO.Path]::GetDirectoryName($SourcePst)) 'OutlookPOP3Archive-Transactions'
    $path=Join-Path $dir 'ARCH4.pending'
    if(-not [IO.File]::Exists($path)){throw 'ARCH6 pending transaction not found; no automatic replay.'}
    if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH6 redirected pending file.'}
    $p=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8))
    if($p.Schema -cne '2.6.5-ARCH4.Pending.1' -or [string]$p.SourcePst -ine $SourcePst -or
       [string]$p.Profile -ine $ProfileName -or [string]$p.TransactionId -cne $TransactionId -or
       $TransactionId -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
       [int]$p.MoveProcessId -le 0 -or [long]$p.MoveProcessStartUtcTicks -le 0){
        throw 'ARCH6 pending identity mismatch; no Outlook restart or Resume.'
    }
    return $p
}
function Restart-OPAARCH6OutlookForResume {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pending,
          [ValidateRange(5,300)][int]$TimeoutSeconds=60)
    $sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
    $processes=@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $sessionId})
    if($processes.Count -eq 0){return}
    if($processes.Count -ne 1){throw 'ARCH6 multiple Outlook processes; manual restart required.'}
    $proc=$processes[0]
    $ticks=[long]$proc.StartTime.ToUniversalTime().Ticks
    if($ticks -gt [long]$Pending.MoveProcessStartUtcTicks){return}
    if($ticks -ne [long]$Pending.MoveProcessStartUtcTicks -or $proc.Id -ne [int]$Pending.MoveProcessId){
        throw 'ARCH6 Outlook process identity changed; manual review.'
    }
    $app=$null;$ns=$null;$inspectors=$null
    try{
        $app=[Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
        $ns=$app.GetNamespace('MAPI')
        if([string]$ns.CurrentProfileName -ine [string]$Pending.Profile){throw 'ARCH6 active Outlook profile differs.'}
        $inspectors=$app.Inspectors
        if([int]$inspectors.Count -ne 0){throw 'ARCH6 close all open Outlook messages before automatic restart.'}
        # Refuse shutdown with unsent mail in any accessible delivery Outbox.
        foreach($account in @($ns.Accounts)){
            $store=$null;$outbox=$null
            try{
                $store=$account.DeliveryStore
                if($null -ne $store){
                    $outbox=$store.GetDefaultFolder(4)
                    if($null -eq $outbox -or [int]$outbox.Items.Count -ne 0){throw 'ARCH6 Outbox not empty or unavailable; manual restart required.'}
                }
            }finally{
                foreach($o in @($outbox,$store,$account)){if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)}}
            }
        }
        $app.Quit()
    }finally{
        foreach($o in @($inspectors,$ns,$app)){if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)}}
    }
    if(-not $proc.WaitForExit($TimeoutSeconds*1000)){throw 'ARCH6 graceful Outlook shutdown timed out; never kill; use manual restart and Resume.'}
    $remaining=@(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $sessionId})
    if($remaining.Count -ne 0){throw 'ARCH6 Outlook still running or relaunched; manual review required.'}
}
function Write-OPAARCH6RunEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][string]$Phase,
          [Parameter(Mandatory=$true)][object]$Data)
    $line=ConvertTo-Json -InputObject ([ordered]@{Utc=(Get-Date).ToUniversalTime().ToString('o');Phase=$Phase;Data=$Data}) -Depth 12 -Compress
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($line+[char]10)
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
