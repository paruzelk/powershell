#requires -Version 5.1
BeforeAll {
    $script:gRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:gRoot 'Core/Runtime/ARCH7gRds.ps1')
    $script:gSid='S-1-5-21-111-222-333-1001'
    function New-ARCH7gFixture {
        param([string]$DailyAt='')
        New-OPAARCH7gTaskDefinition -UserSid $script:gSid -InstallDirectory 'C:\Program Files\OPA & Tests' -WindowsDirectory 'C:\Windows' -DailyAt $DailyAt
    }
}
Describe 'ARCH7g disabled task definition and RDS identity fence' {
    It 'plans only a disabled unregistered DEV task' {
        $r=New-ARCH7gFixture
        $r.Status | Should -BeExactly DisabledDefinitionOnly
        $r.Enabled | Should -BeFalse
        $r.Registered | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        ([xml]$r.TaskXml).Task.Settings.Enabled | Should -BeExactly 'false'
    }
    It 'pins principal and trigger to the same user SID with least privilege interactive token' {
        $x=([xml](New-ARCH7gFixture).TaskXml).Task
        $x.Principals.Principal.UserId | Should -BeExactly $script:gSid
        $x.Principals.Principal.LogonType | Should -BeExactly InteractiveToken
        $x.Principals.Principal.RunLevel | Should -BeExactly LeastPrivilege
        $x.Triggers.LogonTrigger.UserId | Should -BeExactly $script:gSid
        $x.Triggers.LogonTrigger.Delay | Should -BeExactly PT2M
    }
    It 'has no forced termination timeout or external restart policy' {
        $x=([xml](New-ARCH7gFixture).TaskXml).Task.Settings
        $x.MultipleInstancesPolicy | Should -BeExactly IgnoreNew
        $x.ExecutionTimeLimit | Should -BeExactly PT0S
        $x.AllowHardTerminate | Should -BeExactly 'false'
        $x.StartWhenAvailable | Should -BeExactly 'false'
        $x.RestartOnFailure | Should -BeNullOrEmpty
    }
    It 'quotes local paths and escapes XML ampersands without execution policy bypass' {
        $r=New-ARCH7gFixture
        $x=([xml]$r.TaskXml).Task.Actions.Exec
        $x.WorkingDirectory | Should -BeExactly 'C:\Program Files\OPA & Tests'
        $x.Arguments | Should -Match '-File "C:\\Program Files\\OPA & Tests\\Invoke-OPARdsAutoDev.ps1"'
        $x.Arguments | Should -Match '-ConfirmDevAutoArchive -ExpectedUserSid S-1-5-21-111-222-333-1001'
        $x.Arguments | Should -Not -Match 'ExecutionPolicy|Password'
    }
    It 'supports an optional daily trigger without enabling the task' {
        $x=([xml](New-ARCH7gFixture -DailyAt '03:15').TaskXml).Task
        $x.Triggers.CalendarTrigger.StartBoundary | Should -Match 'T03:15:00$'
        $x.Triggers.CalendarTrigger.ScheduleByDay.DaysInterval | Should -BeExactly '1'
        $x.Settings.Enabled | Should -BeExactly 'false'
        {New-ARCH7gFixture -DailyAt '25:00'} | Should -Throw '*HH:mm*'
    }
    It 'rejects SYSTEM, services, UNC and nonabsolute executable directories' {
        foreach($sid in @('S-1-5-18','S-1-5-19','S-1-5-20','S-1-5-80-123')){
            {New-OPAARCH7gTaskDefinition -UserSid $sid -InstallDirectory 'C:\OPA' -WindowsDirectory 'C:\Windows'} | Should -Throw '*user SID*'
        }
        foreach($path in @('\\server\share','relative','C:\OPA\..\other')){
            {New-OPAARCH7gTaskDefinition -UserSid $script:gSid -InstallDirectory $path -WindowsDirectory 'C:\Windows'} | Should -Throw '*absolute local path*'
        }
    }
    It 'allows only the matching ordinary interactive limited user' {
        $r=Get-OPAARCH7gContextDecision -ActualSid $script:gSid -ExpectedSid $script:gSid -SessionId 2 -Interactive $true -Elevated $false
        $r.MayInvokeAuto | Should -BeTrue
    }
    It 'blocks wrong SID, session zero, noninteractive and elevated token' {
        foreach($case in @(@{ActualSid='S-1-5-18';SessionId=2;Interactive=$true;Elevated=$false},@{ActualSid='S-1-5-21-111-222-333-1002';SessionId=2;Interactive=$true;Elevated=$false},@{ActualSid=$script:gSid;SessionId=0;Interactive=$true;Elevated=$false},@{ActualSid=$script:gSid;SessionId=2;Interactive=$false;Elevated=$false},@{ActualSid=$script:gSid;SessionId=2;Interactive=$true;Elevated=$true})){
            $r=Get-OPAARCH7gContextDecision @case -ExpectedSid $script:gSid
            $r.ExitCode | Should -Be 30
            $r.MayInvokeAuto | Should -BeFalse
        }
    }
    It 'defers when Outlook is absent without launching it' {
        $r=Get-OPAARCH7gOutlookDecision -ExpectedSid $script:gSid -SessionId 2 -OutlookRows @()
        $r.ExitCode | Should -Be 40
        $r.MayInvokeAuto | Should -BeFalse
    }
    It 'requires exactly one Outlook matching user and session' {
        $row=[pscustomobject]@{OwnerSid=$script:gSid;SessionId=2;ProcessId=123}
        (Get-OPAARCH7gOutlookDecision -ExpectedSid $script:gSid -SessionId 2 -OutlookRows @($row)).MayInvokeAuto | Should -BeTrue
        (Get-OPAARCH7gOutlookDecision -ExpectedSid $script:gSid -SessionId 2 -OutlookRows @($row,$row)).ExitCode | Should -Be 30
        $row.SessionId=3
        (Get-OPAARCH7gOutlookDecision -ExpectedSid $script:gSid -SessionId 2 -OutlookRows @($row)).ExitCode | Should -Be 30
        $row.SessionId=2;$row.OwnerSid='S-1-5-21-111-222-333-1002'
        (Get-OPAARCH7gOutlookDecision -ExpectedSid $script:gSid -SessionId 2 -OutlookRows @($row)).ExitCode | Should -Be 30
    }
    It 'runs the public WhatIf in a real STA child without Outlook or task writes' {
        $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $entry=Join-Path $script:gRoot 'Invoke-OPARdsAutoDev.ps1'
        $out=& $exe -NoProfile -NonInteractive -STA -File $entry -ConfirmDevAutoArchive -ExpectedUserSid $script:gSid -WhatIf
        $LASTEXITCODE | Should -Be 0
        ($out -join ' ') | Should -Match 'NoOutlookOrPersistentWrites'
    }
    It 'rejects an unconfirmed public child before any real operation' {
        $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $entry=Join-Path $script:gRoot 'Invoke-OPARdsAutoDev.ps1'
        & $exe -NoProfile -NonInteractive -STA -File $entry -ExpectedUserSid $script:gSid -WhatIf
        $LASTEXITCODE | Should -Be 30
    }
    It 'keeps public plan read-only and runtime dispatch guarded and quiet' {
        $plan=[IO.File]::ReadAllText((Join-Path $script:gRoot 'New-OPARdsTaskPlan.ps1'))
        $runtime=[IO.File]::ReadAllText((Join-Path $script:gRoot 'Invoke-OPARdsAutoDev.ps1'))
        $plan | Should -Not -Match 'Register-ScheduledTask|Enable-ScheduledTask|Start-ScheduledTask'
        $runtime | Should -Match 'Get-OPAARCH7gRuntimeDecision'
        $runtime | Should -Match 'ConfirmDevAutoArchive=\$true;Quiet=\$true'
        $runtime | Should -Not -Match 'Start-Process|Stop-Process|Register-ScheduledTask|Restart-ScheduledTask'
    }
}
