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


Describe 'ARCH8b group-scoped RDS logon pilot' {
    BeforeAll {$script:gGroup='S-1-5-21-111-222-333-2001'}
    It 'accepts only a group member in a normal interactive session' {
        $r=Get-OPAARCH8bGroupDecision -GroupSid $script:gGroup -ActualSid $script:gSid -SessionId 2 -Interactive $true -Elevated $false -Member $true
        $r.MayInvokeAuto | Should -BeTrue
        $r.ExitCode | Should -Be 0
    }
    It 'does not authorize a nonmember, a user SID as group, or a service token' {
        (Get-OPAARCH8bGroupDecision -GroupSid $script:gGroup -ActualSid $script:gSid -SessionId 2 -Interactive $true -Member $false).ExitCode | Should -Be 41
        (Get-OPAARCH8bGroupDecision -GroupSid $script:gSid -ActualSid $script:gSid -SessionId 2 -Interactive $true -Member $true).ExitCode | Should -Be 30
        (Get-OPAARCH8bGroupDecision -GroupSid $script:gGroup -ActualSid 'S-1-5-18' -SessionId 0 -Member $true).ExitCode | Should -Be 30
        (Get-OPAARCH8bGroupDecision -GroupSid $script:gGroup -ActualSid $script:gSid -SessionId 2 -Interactive $true -Elevated $true -Member $true).ExitCode | Should -Be 30
    }
    It 'waits for Outlook readiness only before Auto and stops after readiness' {
        $script:gAttempts=0;$script:gDelays=0
        $result=Wait-OPAARCH8bOutlook -MaxWaitIntervals 4 -Probe {
            $script:gAttempts++
            if($script:gAttempts -lt 3){[pscustomobject]@{ExitCode=40;MayInvokeAuto=$false}}else{[pscustomobject]@{ExitCode=0;MayInvokeAuto=$true}}
        } -Delay {$script:gDelays++}
        $result.ExitCode | Should -Be 0
        $script:gAttempts | Should -Be 3
        $script:gDelays | Should -Be 2
    }
    It 'does not retry denied membership or identity failures' {
        foreach($code in @(30,41)){
            $script:gAttempts=0
            $r=Wait-OPAARCH8bOutlook -MaxWaitIntervals 4 -Probe {$script:gAttempts++;[pscustomobject]@{ExitCode=$code;MayInvokeAuto=$false}} -Delay {throw 'unexpected delay'}
            $r.ExitCode | Should -Be $code
            $script:gAttempts | Should -Be 1
        }
    }
    It 'ends the bounded wait without starting Outlook' {
        $script:gAttempts=0;$script:gDelays=0
        $r=Wait-OPAARCH8bOutlook -MaxWaitIntervals 2 -Probe {$script:gAttempts++;[pscustomobject]@{ExitCode=40;MayInvokeAuto=$false}} -Delay {$script:gDelays++}
        $r.ExitCode | Should -Be 40
        $script:gAttempts | Should -Be 3
        $script:gDelays | Should -Be 2
    }
    It 'rejects inconsistent readiness response without invoking the dispatcher' {
        {Wait-OPAARCH8bOutlook -Probe {[pscustomobject]@{ExitCode=40;MayInvokeAuto=$true}} -Delay {throw 'unexpected delay'}} | Should -Throw '*invalid readiness*'
    }
    It 'public group WhatIf has 500 and unlimited defaults and no fixed user SID' {
        $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $entry=Join-Path $script:gRoot 'Invoke-OPARdsAutoDev.ps1'
        $out=& $exe -NoProfile -NonInteractive -STA -File $entry -ConfirmDevAutoArchive -ConfirmDevGpoArchive -ArchiveGroupSid $script:gGroup -WhatIf
        $LASTEXITCODE | Should -Be 0
        ($out -join ' ') | Should -Match 'NoOutlookOrPersistentWrites'
        ($out -join ' ') | Should -Match '500'
    }
    It 'public group WhatIf rejects absent group, fixed user, and legacy unlimited mode' {
        $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $entry=Join-Path $script:gRoot 'Invoke-OPARdsAutoDev.ps1'
        & $exe -NoProfile -NonInteractive -STA -File $entry -ConfirmDevAutoArchive -ConfirmDevGpoArchive -WhatIf
        $LASTEXITCODE | Should -Be 30
        & $exe -NoProfile -NonInteractive -STA -File $entry -ConfirmDevAutoArchive -ConfirmDevGpoArchive -ArchiveGroupSid $script:gGroup -ExpectedUserSid $script:gSid -WhatIf
        $LASTEXITCODE | Should -Be 30
        & $exe -NoProfile -NonInteractive -STA -File $entry -ConfirmDevAutoArchive -ExpectedUserSid $script:gSid -AutoDevMaxBatches 0 -WhatIf
        $LASTEXITCODE | Should -Be 30
    }
}


Describe 'ARCH8b1 domain deployment planning and safety boundaries' {
    BeforeAll {
        . (Join-Path $script:gRoot 'Core/Runtime/ARCH8b1Domain.ps1')
        $script:domainSid='S-1-5-21-111-222-333'
        $script:ou='OU=RDS,DC=example,DC=local'
        $script:hosts=@('rds01.example.local','rds02.example.local')
        function New-ARCH8b1Fixture {
            $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory((Join-Path $root 'Core\Runtime'))
            foreach($name in @('OutlookPOP3Archive.ps1','Invoke-OPARdsAutoDev.ps1','Invoke-OPALiveArchiveBatches.ps1','Core\Runtime\Start-OPAArchiveAtLogon.ps1')){
                [IO.File]::WriteAllText((Join-Path $root $name),'# synthetic payload only',[Text.UTF8Encoding]::new($true))
            }
            [IO.File]::WriteAllText((Join-Path $root 'BUILD-INFO.json'),(ConvertTo-Json @{WindowsPowerShell51CiPassed=$true;SourceCommit=('a'*40)} -Compress))
            return $root
        }
    }
    It 'generates stable independent scope from domain OU group GPO and unordered hosts' {
        $x=Get-OPAARCH8b1ScopeId -DomainSid $script:domainSid -TargetOU $script:ou -GroupName POP3Archive -ComputerNames $script:hosts
        $y=Get-OPAARCH8b1ScopeId -DomainSid $script:domainSid -TargetOU $script:ou.ToUpperInvariant() -GroupName pop3archive -ComputerNames @('RDS02.EXAMPLE.LOCAL','RDS01.EXAMPLE.LOCAL')
        $x | Should -BeExactly $y
        $x | Should -Match '^[a-f0-9]{64}$'
        (Get-OPAARCH8b1ScopeId -DomainSid 'S-1-5-21-444-555-666' -TargetOU $script:ou -GroupName POP3Archive -ComputerNames $script:hosts) | Should -Not -Be $x
        (Get-OPAARCH8b1ScopeId -DomainSid $script:domainSid -TargetOU $script:ou -GroupName POP3Archive -ComputerNames $script:hosts -GpoName Different) | Should -Not -Be $x
    }
    It 'rejects domain root duplicate hosts and missing FQDN' {
        {Get-OPAARCH8b1ScopeId -DomainSid $script:domainSid -TargetOU 'DC=example,DC=local' -GroupName POP3Archive -ComputerNames $script:hosts} | Should -Throw
        {Get-OPAARCH8b1ScopeId -DomainSid $script:domainSid -TargetOU $script:ou -GroupName POP3Archive -ComputerNames @('rds01.example.local','RDS01.EXAMPLE.LOCAL')} | Should -Throw
        {Get-OPAARCH8b1ScopeId -DomainSid $script:domainSid -TargetOU $script:ou -GroupName POP3Archive -ComputerNames @('rds01')} | Should -Throw
    }
    It 'generates a quoted quiet local Windows PowerShell command without policy bypass' {
        $r=New-OPAARCH8b1PolicyCommand -ProgramFiles 'C:\Program Files' -WindowsDirectory 'C:\Windows'
        $r | Should -Match '^"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"'
        $r | Should -Match '-STA -WindowStyle Hidden -File "C:\\Program Files\\OutlookPOP3Archive-Logon\\Start-OPAArchiveAtLogon.ps1"'
        $r | Should -Not -Match 'ExecutionPolicy|Password|SYSVOL'
        $r.Length | Should -BeLessThan 260
    }
    It 'rejects nonlocal redirected or command-injection-shaped paths' {
        foreach($path in @('\\server\share','relative','C:\OPA\..\other','C:\OPA" & bad','C:\%bad%')){
            {New-OPAARCH8b1PolicyCommand -ProgramFiles $path -WindowsDirectory 'C:\Windows'} | Should -Throw
        }
    }
    It 'allowlists only original runtime scripts and build metadata' {
        foreach($path in @('OutlookPOP3Archive.ps1','Invoke-OPARdsAutoDev.ps1','Core/Runtime/Start-OPAArchiveAtLogon.ps1','BUILD-INFO.json')){
            Test-OPAARCH8b1RuntimeRelativePath -Path $path | Should -BeTrue
        }
        foreach($path in @('Core/../mail.pst','Core/../../evil.ps1','Core/mail.pst','../Other.ps1','Core/a.jsonl','C:/mail.pst','Core/a.ps1:stream','Install-OPADomain.ps1')){
            Test-OPAARCH8b1RuntimeRelativePath -Path $path | Should -BeFalse
        }
    }
    It 'packages a synthetic runtime and verifies compressed transfer hash and file inventory' {
        $root=New-ARCH8b1Fixture
        $p=New-OPAARCH8b1Payload -ProjectRoot $root
        $p.SourceCommit | Should -BeExactly ('a'*40)
        $p.Files.Count | Should -Be 5
        (Get-OPAARCH8b1Sha256 -Bytes ([Convert]::FromBase64String($p.ZipBase64))) | Should -BeExactly $p.ZipSha256
        $p.LauncherSha256 | Should -BeExactly (@($p.Files | Where-Object Path -ceq 'Core/Runtime/Start-OPAArchiveAtLogon.ps1')[0].Sha256)
        $mem=[IO.MemoryStream]::new([Convert]::FromBase64String($p.ZipBase64))
        $zip=[IO.Compression.ZipArchive]::new($mem,[IO.Compression.ZipArchiveMode]::Read,$false)
        try{$zip.Entries.Count | Should -Be 5}finally{$zip.Dispose();$mem.Dispose()}
    }
    It 'refuses missing CI marker or an extra non-runtime file' {
        $root=New-ARCH8b1Fixture
        [IO.File]::WriteAllText((Join-Path $root 'Core\mail.pst'),'must not be packed')
        {New-OPAARCH8b1Payload -ProjectRoot $root} | Should -Throw '*unexpected package path*'
        Remove-Item -LiteralPath (Join-Path $root 'Core\mail.pst')
        Remove-Item -LiteralPath (Join-Path $root 'BUILD-INFO.json')
        {New-OPAARCH8b1Payload -ProjectRoot $root} | Should -Throw
    }
    It 'allows concurrent readers but refuses maintenance exclusive access while an archive holds the lock' {
        $path=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.lock')
        [IO.File]::WriteAllBytes($path,[byte[]]@())
        $a=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $b=$null
        try{
            $b=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            {$exclusive=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$exclusive.Dispose()} | Should -Throw
        }finally{if($b){$b.Dispose()};$a.Dispose()}
        $exclusive=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $exclusive.Dispose()
    }
    It 'keeps real domain mutations behind explicit scope and consent and uses supported policy cmdlets' {
        $s=[IO.File]::ReadAllText((Join-Path $script:gRoot 'Install-OPADomain.ps1'))
        $s | Should -Match 'SupportsShouldProcess=\$true'
        $s | Should -Match 'if\(\$WhatIfPreference\)\{\$plan;return\}'
        $s | Should -Match 'if\(-not \$ConfirmDomainDeployment\)'
        $s | Should -Match 'Set-GPRegistryValue'
        $s | Should -Match 'New-GPLink'
        $s | Should -Not -Match 'Remove-ADGroup|Remove-GPO|Set-GPInheritance|SYSVOL|Stop-Process'
    }
    It 'gates the bootstrap before loading archive code and preserves user data in maintenance' {
        $s=[IO.File]::ReadAllText((Join-Path $script:gRoot 'Core/Runtime/Start-OPAArchiveAtLogon.ps1'))
        $s.IndexOf('$principal.IsInRole([Security.Principal.SecurityIdentifier]') | Should -BeLessThan $s.IndexOf('Invoke-OPARdsAutoDev.ps1')
        $s | Should -Match 'FileShare\]::Read'
        $h=[IO.File]::ReadAllText((Join-Path $script:gRoot 'Core/Runtime/Invoke-OPAARCH8b1Host.ps1'))
        $h | Should -Match 'FileShare\]::None'
        $h | Should -Match 'unowned extra file; preserve directory'
        $h | Should -Not -Match 'Stop-Process|Remove-Item.*\.pst|Remove-Item.*Transactions'
    }
}
