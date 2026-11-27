#requires -Version 5.1
# Executed only via an explicit, authenticated administrative WinRM operation.
param([string]$Operation,[string]$SettingsJson,[string]$PayloadJson)
$ErrorActionPreference='Stop'
$s=ConvertFrom-Json -InputObject $SettingsJson
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
try{if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'ARCH8b1 remote administrator required.'}}finally{$identity.Dispose()}
$cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
if(-not $cs.PartOfDomain -or $cs.Domain -ine $s.Domain -or [int]$cs.DomainRole -ne 3){throw 'ARCH8b1 only target-domain member servers allowed.'}
$feature=Get-WindowsFeature -Name RDS-RD-Server -ErrorAction Stop
if(-not $feature.Installed){throw 'ARCH8b1 RDS Session Host role required; no role changes performed.'}
$pf=[Environment]::GetFolderPath('ProgramFiles')
$win=$env:WINDIR
$app=Join-Path $pf 'OutlookPOP3Archive'
$boot=Join-Path $pf 'OutlookPOP3Archive-Logon'
$marker=Join-Path $boot 'deployment.json'
$lockPath=Join-Path $boot 'deployment.lock'
$appMarker=Join-Path $app 'OPA-runtime.json'
$admin='S-1-5-32-544';$system='S-1-5-18';$auth='S-1-5-11'
$rx=[Security.AccessControl.FileSystemRights]::ReadAndExecute
$rxMask=[int]($rx -bor [Security.AccessControl.FileSystemRights]::Synchronize)
function Assert-LocalPath {
    param([string]$Path)
    if(Test-Path -LiteralPath $Path){
        $item=Get-Item -LiteralPath $Path -Force
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw ('ARCH8b1 redirected path: '+$Path)}
    }
}
function Set-ManagedAcl {
    param([string]$Path,[string]$ReaderSid)
    $item=Get-Item -LiteralPath $Path -Force
    $acl=if($item.PSIsContainer){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()}
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($admin))
    $inherit=if($item.PSIsContainer){[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'}else{[Security.AccessControl.InheritanceFlags]::None}
    foreach($sid in @($admin,$system)+@($ReaderSid | Where-Object {$_})){
        $rights=if($sid -in @($admin,$system)){[Security.AccessControl.FileSystemRights]::FullControl}else{$rx}
        $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),$rights,$inherit,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
function Assert-ManagedTree {
    param([string]$Path,[string]$ReaderSid,[switch]$RequireExact)
    Assert-LocalPath -Path $Path
    $root=Get-Item -LiteralPath $Path -Force
    if(-not $root.PSIsContainer){throw 'ARCH8b1 deployment directory expected.'}
    foreach($item in @($root)+@(Get-ChildItem -LiteralPath $Path -Recurse -Force)){
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'ARCH8b1 redirected managed tree entry.'}
        $acl=Get-Acl -LiteralPath $item.FullName
        if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @($admin,$system)){throw 'ARCH8b1 untrusted owner; quarantine manually.'}
        $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
        if($RequireExact){
            if(-not $acl.AreAccessRulesProtected -or @($rules | Where-Object {$_.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow}).Count -gt 0){throw 'ARCH8b1 managed ACL protection drift.'}
            foreach($sid in @($admin,$system)+@($ReaderSid | Where-Object {$_})){
                $wanted=if($sid -in @($admin,$system)){[int][Security.AccessControl.FileSystemRights]::FullControl}else{$rxMask}
                if(@($rules | Where-Object {$_.IdentityReference.Value -eq $sid -and ([int]$_.FileSystemRights -band $wanted) -eq $wanted}).Count -lt 1){throw 'ARCH8b1 managed ACL access drift.'}
            }
        }
        foreach($rule in $rules){
            if($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $rule.IdentityReference.Value -notin @($admin,$system)){
                if($rule.IdentityReference.Value -ne $ReaderSid -or ([int]$rule.FileSystemRights -band (-bnot $rxMask)) -ne 0){throw 'ARCH8b1 unexpected managed ACL; no overwrite.'}
            }
        }
    }
}
function Read-ManagedMarker {
    param([string]$Path)
    Assert-LocalPath -Path $Path
    if(-not [IO.File]::Exists($Path)){throw 'ARCH8b1 existing unowned installation; no overwrite.'}
    $data=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if($data.DeploymentId -cne $s.DeploymentId){throw 'ARCH8b1 installation belongs to another deployment.'}
    return $data
}
function Test-RuntimePath {
    param([string]$Name)
    if($Name -cin @('OutlookPOP3Archive.ps1','Invoke-OPARdsAutoDev.ps1','Invoke-OPALiveArchiveBatches.ps1','BUILD-INFO.json')){return $true}
    return ($Name -cmatch '^Core/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\.ps1$' -and $Name -notmatch '(^|/)\.\.?(/|$)')
}
function Get-RuntimeDrift {
    param([string]$Path,[object]$Record)
    $expected=@{}
    foreach($entry in @($Record.Files)){
        $name=[string]$entry.Path
        if(-not (Test-RuntimePath -Name $name) -or $expected.ContainsKey($name) -or $entry.Sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH8b1 invalid recorded inventory.'}
        $expected[$name]=$entry.Sha256
    }
    $missing=0;$changed=0
    foreach($name in $expected.Keys){
        $file=Join-Path $Path $name
        if(-not [IO.File]::Exists($file)){$missing++;continue}
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $expected[$name]){$changed++}
    }
    foreach($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force)){
        $relative=$file.FullName.Substring($Path.Length+1).Replace('\','/')
        if($relative -cne 'OPA-runtime.json' -and -not $expected.ContainsKey($relative)){throw ('ARCH8b1 unowned extra file; preserve directory: '+$relative)}
    }
    [pscustomobject]@{Missing=$missing;Changed=$changed;Expected=$expected.Count}
}
foreach($path in @($pf,$win,$app,$boot)){Assert-LocalPath -Path $path}
$oldBoot=$null;$oldApp=$null;$drift=$null;$bootAclExact=$false;$runtimeAclExact=$false
if([IO.Directory]::Exists($boot)){
    Assert-ManagedTree -Path $boot -ReaderSid $auth
    try{Assert-ManagedTree -Path $boot -ReaderSid $auth -RequireExact;$bootAclExact=$true}catch{}
    $oldBoot=Read-ManagedMarker -Path $marker
    if($oldBoot.Schema -cne 'OPA.Domain.Logon.1' -or $oldBoot.GroupSid -cnotmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or -not [IO.File]::Exists($lockPath)){throw 'ARCH8b1 invalid launcher marker/lock.'}
    foreach($file in @(Get-ChildItem -LiteralPath $boot -Force)){
        if($file.Name -cnotin @('deployment.json','deployment.lock','Start-OPAArchiveAtLogon.ps1') -or $file.PSIsContainer){throw 'ARCH8b1 unowned launcher entry.'}
    }
}
if([IO.Directory]::Exists($app)){
    if($null -eq $oldBoot){throw 'ARCH8b1 runtime without owned launcher; no overwrite.'}
    Assert-ManagedTree -Path $app -ReaderSid ([string]$oldBoot.GroupSid)
    $oldApp=Read-ManagedMarker -Path $appMarker
    if($oldApp.Schema -cne 'OPA.Domain.Runtime.1' -or $oldApp.GroupSid -cne $oldBoot.GroupSid){throw 'ARCH8b1 inconsistent runtime ownership.'}
    $drift=Get-RuntimeDrift -Path $app -Record $oldApp
    try{Assert-ManagedTree -Path $app -ReaderSid ([string]$oldBoot.GroupSid) -RequireExact;$runtimeAclExact=$true}catch{}
}
if($Operation -in @('Probe','Audit')){
    $effective=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\OutlookPOP3Archive' -ErrorAction SilentlyContinue
    return [pscustomobject]@{Status=if($oldApp){'OwnedRuntime'}else{'NotInstalled'};Host=$env:COMPUTERNAME;ProgramFiles=$pf;WindowsDirectory=$win;InstalledCommit=if($oldApp){$oldApp.SourceCommit}else{''};LocalEnabled=if($oldBoot){[bool]$oldBoot.Enabled}else{$false};EffectiveEnabled=if($effective){$effective.Enabled}else{$null};EffectiveDeploymentId=if($effective){$effective.DeploymentId}else{''};LauncherAclExact=$bootAclExact;RuntimeAclExact=$runtimeAclExact;Drift=$drift;GroupSid=if($oldBoot){$oldBoot.GroupSid}else{''};LauncherHashMatches=($null -ne $oldBoot -and [IO.File]::Exists((Join-Path $boot 'Start-OPAArchiveAtLogon.ps1')) -and (Get-FileHash -LiteralPath (Join-Path $boot 'Start-OPAArchiveAtLogon.ps1') -Algorithm SHA256).Hash -ieq $oldBoot.LauncherSha256)}
}
if($Operation -notin @('Install','Update','Repair','Disable','Uninstall') -or $s.GroupSid -cnotmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw 'ARCH8b1 explicit operation and valid group SID required.'}
if($oldBoot -and $oldBoot.GroupSid -cne $s.GroupSid){throw 'ARCH8b1 group SID changed; manual migration required.'}
if($Operation -eq 'Update' -and $null -eq $oldApp){throw 'ARCH8b1 Update requires an owned runtime.'}
if($Operation -in @('Disable','Uninstall') -and $null -eq $oldBoot){return [pscustomobject]@{Host=$env:COMPUTERNAME;Status='NotInstalled'}}
if($null -eq $oldBoot){
    [void][IO.Directory]::CreateDirectory($boot)
    Set-ManagedAcl -Path $boot -ReaderSid $auth
    $oldBoot=[pscustomobject]@{Schema='OPA.Domain.Logon.1';DeploymentId=$s.DeploymentId;GroupSid=$s.GroupSid;Enabled=$false;LauncherSha256=''}
    [IO.File]::WriteAllText($marker,(ConvertTo-Json -InputObject $oldBoot -Compress),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllBytes($lockPath,[byte[]]@())
    Set-ManagedAcl -Path $marker -ReaderSid $auth
    Set-ManagedAcl -Path $lockPath -ReaderSid $auth
}
$lease=[IO.FileStream]::new($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    $running=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" | Where-Object {$_.ProcessId -ne $PID -and [string]$_.CommandLine -like '*OutlookPOP3Archive*'})
    if($running.Count -gt 0){throw 'ARCH8b1 archive PowerShell process may be active; retry after completion.'}
    $oldBoot.Enabled=$false
    [IO.File]::WriteAllText($marker,(ConvertTo-Json -InputObject $oldBoot -Compress),[Text.UTF8Encoding]::new($false))
    if($Operation -in @('Disable','Uninstall')){
        if($Operation -eq 'Uninstall' -and $oldApp){
            [void](Get-RuntimeDrift -Path $app -Record $oldApp)
            Remove-Item -LiteralPath $app -Recurse -Force -ErrorAction Stop
        }
        return [pscustomobject]@{Host=$env:COMPUTERNAME;Status=if($Operation -eq 'Disable'){'Disabled'}else{'RuntimeRemovedLauncherDisabled'}}
    }
    $payload=ConvertFrom-Json -InputObject $PayloadJson
    $zip=[Convert]::FromBase64String([string]$payload.ZipBase64)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$actual=[BitConverter]::ToString($sha.ComputeHash($zip)).Replace('-','')}finally{$sha.Dispose()}
    if($actual -ine $payload.ZipSha256){throw 'ARCH8b1 transferred ZIP hash mismatch.'}
    if($oldApp -and $oldApp.SourceCommit -ceq $payload.SourceCommit -and $runtimeAclExact -and $bootAclExact -and $drift.Missing -eq 0 -and $drift.Changed -eq 0 -and $oldBoot.LauncherSha256 -ceq $payload.LauncherSha256 -and [IO.File]::Exists((Join-Path $boot 'Start-OPAArchiveAtLogon.ps1')) -and (Get-FileHash -LiteralPath (Join-Path $boot 'Start-OPAArchiveAtLogon.ps1') -Algorithm SHA256).Hash -ieq $payload.LauncherSha256){
        $current=Get-RuntimeDrift -Path $app -Record ([pscustomobject]@{Files=@($payload.Files)})
        if($current.Missing -eq 0 -and $current.Changed -eq 0){
            $oldBoot.Enabled=$true
            [IO.File]::WriteAllText($marker,(ConvertTo-Json -InputObject $oldBoot -Compress),[Text.UTF8Encoding]::new($false))
            return [pscustomobject]@{Host=$env:COMPUTERNAME;Status='RuntimeAlreadyCurrent';SourceCommit=$payload.SourceCommit;ProgramFiles=$pf;WindowsDirectory=$win}
        }
    }
    $stage=Join-Path $pf ('OutlookPOP3Archive.stage.'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    Set-ManagedAcl -Path $stage -ReaderSid ''
    Add-Type -AssemblyName System.IO.Compression
    $memory=[IO.MemoryStream]::new($zip)
    $archive=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Read,$false)
    $expected=@{}
    foreach($entry in @($payload.Files)){
        $name=[string]$entry.Path
        if(-not (Test-RuntimePath -Name $name) -or $expected.ContainsKey($name) -or $entry.Sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'ARCH8b1 invalid transfer manifest.'}
        $expected[$name]=$entry.Sha256
    }
    try{
        if($archive.Entries.Count -ne $expected.Count){throw 'ARCH8b1 transfer inventory mismatch.'}
        $seen=@{}
        foreach($entry in $archive.Entries){
            $name=$entry.FullName
            if(-not $expected.ContainsKey($name) -or $seen.ContainsKey($name)){throw 'ARCH8b1 unexpected or repeated ZIP entry.'}
            $seen[$name]=$true
            $dst=Join-Path $stage $name
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
            $inputStream=$entry.Open();$outputStream=[IO.FileStream]::new($dst,[IO.FileMode]::CreateNew)
            try{$inputStream.CopyTo($outputStream);$outputStream.Flush($true)}finally{$outputStream.Dispose();$inputStream.Dispose()}
            if((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -ine $expected[$name]){throw 'ARCH8b1 staged file hash mismatch.'}
        }
    }finally{$archive.Dispose();$memory.Dispose()}
    $record=[ordered]@{Schema='OPA.Domain.Runtime.1';DeploymentId=$s.DeploymentId;GroupSid=$s.GroupSid;SourceCommit=$payload.SourceCommit;Files=@($payload.Files)}
    [IO.File]::WriteAllText((Join-Path $stage 'OPA-runtime.json'),(ConvertTo-Json -InputObject $record -Depth 6 -Compress),[Text.UTF8Encoding]::new($false))
    foreach($item in @(Get-ChildItem -LiteralPath $stage -Recurse -Force)){Set-ManagedAcl -Path $item.FullName -ReaderSid $s.GroupSid}
    Set-ManagedAcl -Path $stage -ReaderSid $s.GroupSid
    Assert-ManagedTree -Path $stage -ReaderSid $s.GroupSid -RequireExact
    $backup=$null
    if($oldApp){
        $backup=Join-Path $pf ('OutlookPOP3Archive.previous.'+[guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $app -Destination $backup -ErrorAction Stop
    }
    try{Move-Item -LiteralPath $stage -Destination $app -ErrorAction Stop}
    catch{if($backup -and -not [IO.Directory]::Exists($app)){Move-Item -LiteralPath $backup -Destination $app -ErrorAction Stop};throw}
    $launchSource=Join-Path $app 'Core\Runtime\Start-OPAArchiveAtLogon.ps1'
    $launchTarget=Join-Path $boot 'Start-OPAArchiveAtLogon.ps1'
    [IO.File]::WriteAllBytes($launchTarget,[IO.File]::ReadAllBytes($launchSource))
    Set-ManagedAcl -Path $launchTarget -ReaderSid $auth
    foreach($path in @($boot,$marker,$lockPath)){Set-ManagedAcl -Path $path -ReaderSid $auth}
    Assert-ManagedTree -Path $boot -ReaderSid $auth -RequireExact
    if((Get-FileHash -LiteralPath $launchTarget -Algorithm SHA256).Hash -ine $payload.LauncherSha256){throw 'ARCH8b1 launcher hash mismatch.'}
    $oldBoot.LauncherSha256=$payload.LauncherSha256
    $oldBoot.Enabled=$true
    [IO.File]::WriteAllText($marker,(ConvertTo-Json -InputObject $oldBoot -Compress),[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{Host=$env:COMPUTERNAME;Status='RuntimeInstalled';SourceCommit=$payload.SourceCommit;PreviousRuntime=$backup;ProgramFiles=$pf;WindowsDirectory=$win}
}finally{$lease.Dispose()}
