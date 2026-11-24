#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ProfileName,
    [switch]$ConfirmTestArchive,
    [switch]$ConfirmOutlookRestart,
    [ValidateRange(1,500)][int]$BatchSize=500,
    [ValidateRange(1,2147483647)][int]$MaxMessages=10000,
    [ValidateRange(1,100000)][int]$MaxBatches=100,
    [ValidateRange(0,1200)][int]$OlderThanMonths=12,
    [ValidateSet('None','Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='YearQuarter',
    [string[]]$IncludeFolderPath,
    [switch]$IgnoreAge,
    [switch]$ConfirmComplexAttachments,
    [ValidateRange(0.01,1000)][double]$MaxArchivePstSizeGB=10,
    [ValidateRange(0,100)][double]$SafetyMarginGB=0.5,
    [switch]$DisableArchivePstSizeLimit,
    [ValidateRange(5,300)][int]$RestartTimeoutSeconds=60,
    [string]$RecoverTransaction,
    [switch]$WhatIf
)
$ErrorActionPreference='Stop'
if(-not $ConfirmTestArchive -or -not $ConfirmOutlookRestart -or [string]::IsNullOrWhiteSpace($ProfileName) -or
   ($OlderThanMonths -eq 0 -and -not $IgnoreAge) -or ($ConfirmComplexAttachments -and $BatchSize -gt 10) -or
   ($DisableArchivePstSizeLimit -and ($PSBoundParameters.ContainsKey('MaxArchivePstSizeGB') -or $PSBoundParameters.ContainsKey('SafetyMarginGB'))) -or
   (-not $DisableArchivePstSizeLimit -and ($MaxArchivePstSizeGB -le $SafetyMarginGB -or [double]::IsNaN($MaxArchivePstSizeGB) -or [double]::IsNaN($SafetyMarginGB))) -or
   ($RecoverTransaction -and $RecoverTransaction -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$')){
    throw 'ARCH6 requires explicit test PST/profile and restart consent, valid batch/age/capacity options or exact recovery transaction.'
}
if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
   [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -ne 'STA'){throw 'ARCH6 requires Windows PowerShell 5.1 STA.'}
if($RecoverTransaction){
    foreach($key in @('BatchSize','MaxMessages','MaxBatches','OlderThanMonths','ArchiveGrouping','IncludeFolderPath','IgnoreAge','ConfirmComplexAttachments','MaxArchivePstSizeGB','SafetyMarginGB','DisableArchivePstSizeLimit')){
        if($PSBoundParameters.ContainsKey($key)){throw 'ARCH6 recovery-only mode cannot accept new Archive options.'}
    }
}
if($WhatIf){
    [pscustomobject]@{Schema='2.6.5-ARCH6.WhatIf.1';Status='NoOutlookOrPersistentWrites';SourcePst=$SourcePst;BatchSize=$BatchSize;MaxMessages=$MaxMessages;MaxBatches=$MaxBatches;RecoverTransaction=$RecoverTransaction;ProductionReady=$false}
    return
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH6Orchestration.ps1')
$source=[IO.Path]::GetFullPath($SourcePst)
if($source.StartsWith('\\') -or -not [IO.File]::Exists($source) -or [IO.Path]::GetExtension($source) -ine '.pst' -or
   (([IO.File]::GetAttributes($source) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'ARCH6 requires existing non-reparse local test PST.'}
# Same named mutex as the original entrypoint, held across all phases.
# Windows mutex acquisition is recursive on this STA thread.
$safeUser=(("{0}_{1}" -f [string]$env:USERDOMAIN,[string]$env:USERNAME) -replace '[^A-Za-z0-9_.-]','_')
$mutex=[Threading.Mutex]::new($false,("Global\OutlookPOP3Archive-Auto-"+$safeUser))
$held=$false;$logPath=$null
try{
    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){throw 'ARCH6 another archive operation is already running.'}
    $dir=Join-Path ([IO.Path]::GetDirectoryName($source)) 'OutlookPOP3Archive-Transactions'
    [void][IO.Directory]::CreateDirectory($dir)
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH6 redirected transaction directory.'}
    $pending=Join-Path $dir 'ARCH4.pending'
    if(-not $RecoverTransaction -and [IO.File]::Exists($pending)){throw 'ARCH6 pending transaction exists; use -RecoverTransaction with its exact ID or original Resume.'}
    $runId=[guid]::NewGuid().ToString('N')
    $logPath=Join-Path $dir ('ARCH6-run-'+$runId+'.jsonl')
    $new=[IO.FileStream]::new($logPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $new.Dispose()
    $main=Join-Path $PSScriptRoot 'OutlookPOP3Archive.ps1'
    $common=@{SourcePst=$source;ProfileName=$ProfileName;ConfirmTestArchive=$true}
    $archiveOptions=@{OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping;IgnoreAge=[bool]$IgnoreAge;ConfirmComplexAttachments=[bool]$ConfirmComplexAttachments}
    if($IncludeFolderPath){$archiveOptions.IncludeFolderPath=$IncludeFolderPath}
    if($DisableArchivePstSizeLimit){$archiveOptions.DisableArchivePstSizeLimit=$true}
    else{$archiveOptions.MaxArchivePstSizeGB=$MaxArchivePstSizeGB;$archiveOptions.SafetyMarginGB=$SafetyMarginGB}
    Write-OPAARCH6RunEvent -Path $logPath -Phase RunStarted -Data ([pscustomobject]@{RunId=$runId;SourcePst=$source;Profile=$ProfileName;BatchSize=$BatchSize;MaxMessages=$MaxMessages;MaxBatches=$MaxBatches;Recovery=$RecoverTransaction;ArchiveOptions=$archiveOptions})
    $restart={
        param($id)
        $p=Get-OPAARCH6PendingRecord -SourcePst $source -ProfileName $ProfileName -TransactionId $id
        Restart-OPAARCH6OutlookForResume -Pending $p -TimeoutSeconds $RestartTimeoutSeconds
    }
    $resume={
        param($id)
        $global:LASTEXITCODE=0
        $r=& $main -Mode Resume @common -Transaction $id
        if($LASTEXITCODE -ne 0){throw 'ARCH6 original Resume failed; preserve pending, no new Archive.'}
        $r
    }
    if($RecoverTransaction){
        & $restart $RecoverTransaction
        $r=& $resume $RecoverTransaction
        if($null -eq $r -or @($r).Count -ne 1 -or [string]$r.TransactionId -cne $RecoverTransaction -or
           $r.Status -cnotin @('BatchVerifiedReconciledAndIndexed','BatchCompletedNoMoves') -or
           [int]$r.Verified -ne [int]$r.Indexed -or [int]$r.Verified -ne [int]$r.Reconciled){
            throw 'ARCH6 recovery did not return exact verified completion.'
        }
        Write-OPAARCH6RunEvent -Path $logPath -Phase Recovered -Data $r
        $r
        return
    }
    $archive={
        param($limit)
        $global:LASTEXITCODE=0
        $a=& $main -Mode Archive @common @archiveOptions -Limit $limit
        if($LASTEXITCODE -ne 0){throw 'ARCH6 original Archive failed; never repeat automatically.'}
        $a
    }
    $record={
        param($phase,$data)
        Write-OPAARCH6RunEvent -Path $logPath -Phase $phase -Data $data
        if($phase -eq 'BatchVerified'){Write-Host ('Verified batch '+$data.TransactionId+': '+$data.Verified+'; skipped: '+$data.NotMoved)}
    }
    $result=Invoke-OPAARCH6Sequence -Archive $archive -Resume $resume -Restart $restart -Record $record -BatchSize $BatchSize -MaxMessages $MaxMessages -MaxBatches $MaxBatches
    $result | Add-Member -NotePropertyName RunJournal -NotePropertyValue $logPath
    Write-OPAARCH6RunEvent -Path $logPath -Phase RunCompleted -Data $result
    $result
}catch{
    if($logPath){try{Write-OPAARCH6RunEvent -Path $logPath -Phase Stopped -Data ([pscustomobject]@{Message=$_.Exception.Message})}catch{Write-Warning 'ARCH6 controller log unavailable; original transaction remains authoritative.'}}
    throw
}finally{
    if($held){[void]$mutex.ReleaseMutex()}
    $mutex.Dispose()
}
