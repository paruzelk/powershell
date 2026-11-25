#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourcePst,
    [Parameter(Mandatory=$true)][string]$ProfileName,
    [switch]$ConfirmTestArchive,[switch]$ConfirmLiveOutlookVerification,
    [ValidateRange(1,10)][int]$BatchSize=10,
    [ValidateRange(1,100)][int]$MaxBatches=1,
    [ValidateRange(1,1200)][int]$OlderThanMonths=12,
    [ValidateSet('Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='YearQuarter',
    [string[]]$IncludeFolderPath,[switch]$IncludeRootMail,
    [ValidateRange(1,10)][int]$MaxResumeAttempts=3,
    [ValidateRange(5,300)][int]$RetryDelaySeconds=5,
    [ValidateRange(30,3600)][int]$WorkerTimeoutSeconds=600,
    [ValidateRange(0,9)][int]$InterruptAfterReturned=0,
    [switch]$RecoverOnly,[switch]$WhatIf
)
$ErrorActionPreference='Stop'
if(-not $ConfirmTestArchive -or -not $ConfirmLiveOutlookVerification -or [string]::IsNullOrWhiteSpace($ProfileName) -or
   [string]::IsNullOrWhiteSpace($SourcePst) -or
   ($InterruptAfterReturned -gt 0 -and ($RecoverOnly -or $MaxBatches -ne 1 -or $InterruptAfterReturned -ge $BatchSize))){
    throw 'ARCH7d explicit test/live confirmation and valid interruption scope required.'
}
if($RecoverOnly){
    foreach($key in @('BatchSize','MaxBatches','OlderThanMonths','ArchiveGrouping','IncludeFolderPath','IncludeRootMail','InterruptAfterReturned')){
        if($PSBoundParameters.ContainsKey($key)){throw 'ARCH7d recovery-only cannot accept Archive options.'}
    }
}
if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or [Threading.Thread]::CurrentThread.GetApartmentState().ToString() -ne 'STA'){throw 'ARCH7d requires Windows PowerShell 5.1 STA.'}
if($WhatIf){
    [pscustomobject]@{Schema='2.6.5-ARCH7d.WhatIf.1';Status='NoOutlookOrPersistentWrites';SourcePst=$SourcePst;BatchSize=$BatchSize;MaxBatches=$MaxBatches;RecoverOnly=[bool]$RecoverOnly;InterruptAfterReturned=$InterruptAfterReturned;ProductionReady=$false}
    return
}
. (Join-Path $PSScriptRoot 'Core/Archive/ARCH7dSupervisor.ps1')
$source=[IO.Path]::GetFullPath($SourcePst)
if($source.StartsWith('\\') -or -not [IO.File]::Exists($source) -or [IO.Path]::GetExtension($source) -ine '.pst' -or
   ([IO.File]::GetAttributes($source) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH7d existing non-reparse local test PST required.'}
$dir=Join-Path ([IO.Path]::GetDirectoryName($source)) 'OutlookPOP3Archive-Transactions'
[void][IO.Directory]::CreateDirectory($dir)
if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH7d redirected transaction directory.'}
$lease=[IO.FileStream]::new((Join-Path $dir 'ARCH7d.supervisor.lease'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    # Independent supervisor lock, never the original user's worker mutex.
    $probe=[IO.FileStream]::new((Join-Path $dir 'ARCH7d.worker.lease'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $probe.Dispose()
    if($InterruptAfterReturned -gt 0 -and $null -ne (Get-OPAARCH7dPending -Directory $dir -SourcePst $source -ProfileName $ProfileName)){throw 'ARCH7d existing pending; recover it before fault test.'}
    $logDir=Join-Path $dir ('ARCH7d-run-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($logDir)
    $log=Join-Path $logDir 'supervisor.jsonl'
    $main=Join-Path $PSScriptRoot 'OutlookPOP3Archive.ps1'
    $common=@{SourcePst=$source;ProfileName=$ProfileName;ConfirmTestArchive=$true;ConfirmLiveOutlookVerification=$true}
    $archive=$common.Clone()
    $archive.Mode='Archive';$archive.Limit=$BatchSize;$archive.OlderThanMonths=$OlderThanMonths;$archive.ArchiveGrouping=$ArchiveGrouping
    $archive.DisableArchivePstSizeLimit=$true;$archive.IncludeRootMail=[bool]$IncludeRootMail
    if($IncludeFolderPath){$archive.IncludeFolderPath=$IncludeFolderPath}
    if($InterruptAfterReturned -gt 0){$archive.ARCH7dInterruptAfterReturned=$InterruptAfterReturned}
    $read={Get-OPAARCH7dPending -Directory $dir -SourcePst $source -ProfileName $ProfileName}
    $startArchive={Invoke-OPAARCH7dWorker -Main $main -Parameters $archive -Directory $dir -LogDirectory $logDir -TimeoutSeconds $WorkerTimeoutSeconds}
    $startResume={
        param($id)
        $options=$common.Clone();$options.Mode='Resume';$options.Transaction=$id;$options.RecoverLiveInterrupted=$true
        Invoke-OPAARCH7dWorker -Main $main -Parameters $options -Directory $dir -LogDirectory $logDir -TimeoutSeconds $WorkerTimeoutSeconds
    }
    $record={
        param($phase,$data)
        $row=[ordered]@{Time=(Get-Date).ToString('o');Phase=$phase;Data=$data}
        $json=ConvertTo-Json -InputObject $row -Depth 14 -Compress
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json+[char]10)
        $stream=[IO.FileStream]::new($log,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    }
    $result=Invoke-OPAARCH7dSequence -ReadPending $read -Archive $startArchive -Resume $startResume -Record $record -MaxBatches $MaxBatches -MaxResumeAttempts $MaxResumeAttempts -RetryDelaySeconds $RetryDelaySeconds -RecoverOnly:$RecoverOnly
    $result | Add-Member -NotePropertyMembers @{LogDirectory=$logDir;ControlledInterruptionRequested=$InterruptAfterReturned}
    & $record 'SupervisorCompleted' $result
    $result
}finally{$lease.Dispose()}
