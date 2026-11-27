#requires -Version 5.1
# ARCH6 bounded test-only orchestration. Original journals are authoritative.
function Test-OPAARCH6ExportFailureBurst {
    param([object]$Result)
    if($Result.PSObject.Properties.Name -notcontains 'SkipReasons'){return $false}
    $n=0
    foreach($r in @($Result.SkipReasons)){
        if($r.Reason -cin @('AttachmentExportFailed','AttachmentPayloadUnavailable','UnknownItemPreMove')){$n+=[int]$r.Count}
    }
    return ($n -ge 10 -and 2*$n -ge [int]$Result.Planned)
}
function Invoke-OPAARCH6Sequence {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][scriptblock]$Archive,
          [Parameter(Mandatory=$true)][scriptblock]$Resume,
          [Parameter(Mandatory=$true)][scriptblock]$Restart,
          [Parameter(Mandatory=$true)][scriptblock]$Record,
          [ValidateRange(1,500)][int]$BatchSize,
          [ValidateRange(1,2147483647)][int]$MaxMessages,
          [ValidateRange(1,100000)][int]$MaxBatches,
          [ValidateSet('Continue','Stop')][string]$SkipPolicy='Continue')
    $verified=0L;$logical=0L;$deferred=0L;$batches=0;$last='';$status='BatchLimitReached'
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
            $batches++
            if([int]$a.Planned -gt 0 -and $SkipPolicy -eq 'Continue'){
                if([int]$a.DeferredRecorded -ne [int]$a.Planned){throw 'ARCH6f3a zero-Move deferred evidence incomplete.'}
                $deferred+=[int]$a.DeferredRecorded
                & $Record 'BatchVerified' $a
                if(Test-OPAARCH6ExportFailureBurst -Result $a){$status='StoppedOnExportFailureBurst';break}
                $status='BatchLimitReached';continue
            }
            break
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
        if([int]$r.NotMoved -gt 0){
            if($SkipPolicy -eq 'Stop'){$status='StoppedOnSkippedItems';break}
            if([int]$r.DeferredRecorded -ne [int]$r.NotMoved){throw 'ARCH6f3a deferred evidence incomplete.'}
            $deferred+=[int]$r.DeferredRecorded
            if(Test-OPAARCH6ExportFailureBurst -Result $r){$status='StoppedOnExportFailureBurst';break}
            continue
        }
        if([int]$a.Planned -lt $limit){$status='NoMoreSelectedMessages';break}
    }
    if($verified -ge $MaxMessages){$status='MessageLimitReached'}
    return [pscustomobject]@{Schema='2.6.5-ARCH6.Sequence.1';Status=$status;SkipPolicy=$SkipPolicy;Deferred=$deferred;Batches=$batches;Verified=$verified;LogicalBytes=$logical;LastTransactionId=$last;AutomaticMoveRetryAllowed=$false;ProductionReady=$false}
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
# Outlook started by COM can exist without registration in the ROT.
# Only MK_E_UNAVAILABLE permits one COM activation. All other failures
# remain fail-closed. The caller revalidates the exact process before Quit.
function Get-OPAARCH6RestartApplication {
    [CmdletBinding()]
    param([scriptblock]$GetActive={ [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application') },
          [scriptblock]$Activate={ New-Object -ComObject Outlook.Application -ErrorAction Stop })
    try {
        $app=& $GetActive
    }catch{
        $ex=$_.Exception
        $unavailable=$false
        while($null -ne $ex){
            if($ex -is [Runtime.InteropServices.COMException] -and $ex.HResult -eq -2147221021){$unavailable=$true;break}
            $ex=$ex.InnerException
        }
        if(-not $unavailable){throw}
        $app=& $Activate
    }
    if($null -eq $app -or @($app).Count -ne 1){throw 'ARCH6 no unique Outlook application for restart.'}
    return $app
}

function Assert-OPAARCH6RestartProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pending,
          [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Processes)
    if($Processes.Count -ne 1 -or
       [int]$Processes[0].Id -ne [int]$Pending.MoveProcessId -or
       [long]$Processes[0].StartTime.ToUniversalTime().Ticks -ne [long]$Pending.MoveProcessStartUtcTicks){
        throw 'ARCH6 exact Move process no longer identifiable; never Quit a replacement Outlook process.'
    }
}

function Restart-OPAARCH6OutlookForResume {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Pending,
          [ValidateRange(5,300)][int]$TimeoutSeconds=60)
    if($Pending.PSObject.Properties.Name -contains 'VerificationPolicy'){throw 'ARCH7b live verification pending: legacy Outlook restart prohibited.'}
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
        $app=Get-OPAARCH6RestartApplication
        Assert-OPAARCH6RestartProcess -Pending $Pending -Processes @(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $sessionId})
        $ns=$app.GetNamespace('MAPI')
        if([string]$ns.CurrentProfileName -ine [string]$Pending.Profile){throw 'ARCH6 active Outlook profile differs.'}
        $inspectors=$app.Inspectors
        if([int]$inspectors.Count -ne 0){throw 'ARCH6 close all open Outlook messages before automatic restart.'}
        # Refuse shutdown with unsent mail in any accessible delivery Outbox.
        foreach($account in @($ns.Accounts)){
            $store=$null;$outbox=$null;$outboxItems=$null
            try{
                $store=$account.DeliveryStore
                if($null -ne $store){
                    $outbox=$store.GetDefaultFolder(4)
                    if($null -eq $outbox){throw 'ARCH6 Outbox unavailable; manual restart required.'}
                    $outboxItems=$outbox.Items
                    if($null -eq $outboxItems -or [int]$outboxItems.Count -ne 0){throw 'ARCH6 Outbox not empty or unavailable; manual restart required.'}
                }
            }finally{
                foreach($o in @($outboxItems,$outbox,$store,$account)){if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)}}
            }
        }
        Assert-OPAARCH6RestartProcess -Pending $Pending -Processes @(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $sessionId})
        $app.Quit()
    }finally{
        foreach($o in @($inspectors,$ns,$app)){if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($o)}}
    }
    # Original phase-local references may remain as unreachable RCWs in ISE.
    # Collect unreachable wrappers only; never FinalRelease arbitrary shared objects.
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
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
