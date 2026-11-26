#requires -Version 5.1
# ARCH7g DEV: task definition and fail-closed interactive session preflight.
# No COM, task registration, elevation, process termination or password handling.
function Test-OPAARCH7gUserSid {
    [CmdletBinding()]
    param([string]$Sid)
    return ($Sid -cmatch '^S-1-5-21-\d+-\d+-\d+-\d+$')
}
function Get-OPAARCH7gContextDecision {
    [CmdletBinding()]
    param([string]$ActualSid,[string]$ExpectedSid,[int]$SessionId,[bool]$Interactive,[bool]$Elevated)
    if(-not (Test-OPAARCH7gUserSid -Sid $ActualSid) -or $ActualSid -cne $ExpectedSid -or
       $SessionId -le 0 -or -not $Interactive -or $Elevated){
        return [pscustomobject]@{Status='UnsafeSession';ExitCode=30;MayInvokeAuto=$false}
    }
    return [pscustomobject]@{Status='SessionAccepted';ExitCode=0;MayInvokeAuto=$true}
}
function Get-OPAARCH7gOutlookDecision {
    [CmdletBinding()]
    param([string]$ExpectedSid,[int]$SessionId,[AllowEmptyCollection()][object[]]$OutlookRows)
    if($OutlookRows.Count -eq 0){return [pscustomobject]@{Status='OutlookNotRunning';ExitCode=40;MayInvokeAuto=$false}}
    if($OutlookRows.Count -ne 1 -or [int]$OutlookRows[0].SessionId -ne $SessionId -or
       [string]$OutlookRows[0].OwnerSid -cne $ExpectedSid -or [int]$OutlookRows[0].ProcessId -le 0){
        return [pscustomobject]@{Status='OutlookIdentityUncertain';ExitCode=30;MayInvokeAuto=$false}
    }
    return [pscustomobject]@{Status='OutlookPresent';ExitCode=0;MayInvokeAuto=$true}
}
function Get-OPAARCH7gRuntimeDecision {
    [CmdletBinding()]
    param([string]$ExpectedSid)
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $process=[Diagnostics.Process]::GetCurrentProcess()
    try{
        $principal=[Security.Principal.WindowsPrincipal]::new($identity)
        $sessionId=[int]$process.SessionId
        $context=Get-OPAARCH7gContextDecision -ActualSid $identity.User.Value -ExpectedSid $ExpectedSid -SessionId $sessionId -Interactive ([Environment]::UserInteractive) -Elevated ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
        if(-not $context.MayInvokeAuto){return $context}
        $rows=New-Object 'System.Collections.Generic.List[object]'
        foreach($outlook in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='OUTLOOK.EXE' AND SessionId=$sessionId" -ErrorAction Stop)){
            $owner=Invoke-CimMethod -InputObject $outlook -MethodName GetOwnerSid -ErrorAction Stop
            if($owner.ReturnValue -ne 0 -or -not $owner.Sid){throw 'ARCH7g Outlook owner not proven.'}
            $rows.Add([pscustomobject]@{OwnerSid=[string]$owner.Sid;SessionId=[int]$outlook.SessionId;ProcessId=[int]$outlook.ProcessId})
        }
        return Get-OPAARCH7gOutlookDecision -ExpectedSid $ExpectedSid -SessionId $sessionId -OutlookRows @($rows.ToArray())
    }finally{$process.Dispose();$identity.Dispose()}
}
function New-OPAARCH7gTaskDefinition {
    [CmdletBinding()]
    param([string]$UserSid,[string]$InstallDirectory,[string]$WindowsDirectory,
          [ValidateRange(0,30)][int]$LogonDelayMinutes=2,
          [ValidateRange(1,100)][int]$MaxBatches=1,
          [ValidateRange(1,1200)][int]$OlderThanMonths=12,
          [ValidateSet('Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='YearQuarter',
          [string]$DailyAt='')
    if(-not (Test-OPAARCH7gUserSid -Sid $UserSid)){throw 'ARCH7g ordinary local/domain user SID required.'}
    foreach($path in @($InstallDirectory,$WindowsDirectory)){
        if($path -notmatch '^[A-Za-z]:\\' -or $path -match '["\r\n]' -or $path -match '(^|\\)\.\.?($|\\)'){throw 'ARCH7g absolute local path required.'}
    }
    $directory=[IO.Path]::GetFullPath($InstallDirectory)
    $exe=Join-Path ([IO.Path]::GetFullPath($WindowsDirectory)) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $entry=Join-Path $directory 'Invoke-OPARdsAutoDev.ps1'
    $arguments='-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File "'+$entry+'" -ConfirmDevAutoArchive -ExpectedUserSid '+$UserSid+' -AutoDevMaxBatches '+$MaxBatches+' -OlderThanMonths '+$OlderThanMonths+' -ArchiveGrouping '+$ArchiveGrouping
    $daily=''
    if($DailyAt){
        if($DailyAt -cnotmatch '^(?:[01]\d|2[0-3]):[0-5]\d$'){throw 'ARCH7g daily time must be HH:mm.'}
        $boundary=[DateTime]::Today.ToString('yyyy-MM-dd')+'T'+$DailyAt+':00'
        $daily='<CalendarTrigger><StartBoundary>'+$boundary+'</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>'
    }
    $esc={param([string]$Value) [Security.SecurityElement]::Escape($Value)}
    $xml=@"
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>OutlookPOP3Archive ARCH7g DEV disabled definition; no production permission.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>$UserSid</UserId><Delay>PT${LogonDelayMinutes}M</Delay></LogonTrigger>
    $daily
  </Triggers>
  <Principals><Principal id="CurrentUser"><UserId>$UserSid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>false</Enabled>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
  </Settings>
  <Actions Context="CurrentUser"><Exec><Command>$(& $esc $exe)</Command><Arguments>$(& $esc $arguments)</Arguments><WorkingDirectory>$(& $esc $directory)</WorkingDirectory></Exec></Actions>
</Task>
"@
    # Parse now; do not claim Task Scheduler registration/schema validation.
    [void]([xml]$xml)
    [pscustomobject]@{Schema='2.6.5-ARCH7g.TaskPlan.1';Status='DisabledDefinitionOnly';TaskName=('OutlookPOP3Archive-DEV-'+$UserSid);UserSid=$UserSid;Enabled=$false;Registered=$false;ProductionReady=$false;TaskXml=$xml;Command=$exe;Arguments=$arguments;WorkingDirectory=$directory}
}
