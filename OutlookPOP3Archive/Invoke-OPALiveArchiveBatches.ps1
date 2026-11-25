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
    # Callback free variables must not collide with the dynamically scoped
    # parameters/locals of Invoke-OPAARCH7dSequence (notably $Archive).
    $arch7dControllerTransactionDirectory=$dir
    $arch7dControllerSourcePst=$source
    $arch7dControllerProfile=$ProfileName
    $arch7dControllerTimeout=$WorkerTimeoutSeconds
    $arch7dControllerLogDirectory=Join-Path $arch7dControllerTransactionDirectory ('ARCH7d-run-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($arch7dControllerLogDirectory)
    $arch7dControllerJournalPath=Join-Path $arch7dControllerLogDirectory 'supervisor.jsonl'
    $arch7dControllerMainPath=Join-Path $PSScriptRoot 'OutlookPOP3Archive.ps1'
    $arch7dControllerCommonParameters=@{SourcePst=$arch7dControllerSourcePst;ProfileName=$arch7dControllerProfile;ConfirmTestArchive=$true;ConfirmLiveOutlookVerification=$true}
    $arch7dControllerArchiveParameters=$arch7dControllerCommonParameters.Clone()
    $arch7dControllerArchiveParameters.Mode='Archive';$arch7dControllerArchiveParameters.Limit=$BatchSize;$arch7dControllerArchiveParameters.OlderThanMonths=$OlderThanMonths;$arch7dControllerArchiveParameters.ArchiveGrouping=$ArchiveGrouping
    $arch7dControllerArchiveParameters.DisableArchivePstSizeLimit=$true;$arch7dControllerArchiveParameters.IncludeRootMail=[bool]$IncludeRootMail
    if($IncludeFolderPath){$arch7dControllerArchiveParameters.IncludeFolderPath=$IncludeFolderPath}
    if($InterruptAfterReturned -gt 0){$arch7dControllerArchiveParameters.ARCH7dInterruptAfterReturned=$InterruptAfterReturned}
    $arch7dControllerReadPending={Get-OPAARCH7dPending -Directory $arch7dControllerTransactionDirectory -SourcePst $arch7dControllerSourcePst -ProfileName $arch7dControllerProfile}
    $arch7dControllerStartArchive={Invoke-OPAARCH7dWorker -Main $arch7dControllerMainPath -Parameters $arch7dControllerArchiveParameters -Directory $arch7dControllerTransactionDirectory -LogDirectory $arch7dControllerLogDirectory -TimeoutSeconds $arch7dControllerTimeout}
    $arch7dControllerStartResume={
        param($id)
        $arch7dControllerResumeParameters=$arch7dControllerCommonParameters.Clone();$arch7dControllerResumeParameters.Mode='Resume';$arch7dControllerResumeParameters.Transaction=$id;$arch7dControllerResumeParameters.RecoverLiveInterrupted=$true
        Invoke-OPAARCH7dWorker -Main $arch7dControllerMainPath -Parameters $arch7dControllerResumeParameters -Directory $arch7dControllerTransactionDirectory -LogDirectory $arch7dControllerLogDirectory -TimeoutSeconds $arch7dControllerTimeout
    }
    $arch7dControllerRecord={
        param($phase,$data)
        $row=[ordered]@{Time=(Get-Date).ToString('o');Phase=$phase;Data=$data}
        $json=ConvertTo-Json -InputObject $row -Depth 14 -Compress
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json+[char]10)
        $stream=[IO.FileStream]::new($arch7dControllerJournalPath,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    }
    $result=Invoke-OPAARCH7dSequence -ReadPending $arch7dControllerReadPending -Archive $arch7dControllerStartArchive -Resume $arch7dControllerStartResume -Record $arch7dControllerRecord -MaxBatches $MaxBatches -MaxResumeAttempts $MaxResumeAttempts -RetryDelaySeconds $RetryDelaySeconds -RecoverOnly:$RecoverOnly
    $result | Add-Member -NotePropertyMembers @{LogDirectory=$arch7dControllerLogDirectory;ControlledInterruptionRequested=$InterruptAfterReturned}
    & $arch7dControllerRecord 'SupervisorCompleted' $result
    $result
}finally{$lease.Dispose()}
