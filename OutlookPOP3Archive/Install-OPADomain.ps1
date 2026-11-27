#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [ValidateSet('Install','Update','Repair','Audit','Disable','Uninstall')][string]$Mode='Install',
    [string]$Domain,
    [string]$TargetOU,
    [string[]]$ComputerName,
    [switch]$AllComputersInOU,
    [ValidatePattern('^[A-Za-z0-9_.-]{1,20}$')][string]$GroupName='POP3Archive',
    [string]$GroupOU,
    [string]$GpoName='RDS - Outlook POP3 Archive (Pilot)',
    [ValidateRange(1,1200)][int]$OlderThanMonths=12,
    [ValidateSet('Year','YearQuarter','YearMonth')][string]$ArchiveGrouping='YearQuarter',
    [ValidateRange(1,500)][int]$BatchSize=500,
    [ValidateRange(0,100)][int]$AutoDevMaxBatches=0,
    [ValidateRange(0,60)][int]$OutlookWaitMinutes=20,
    [switch]$ConfirmDomainDeployment
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core/Runtime/ARCH8b1Domain.ps1')
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop
$d=if($Domain){Get-ADDomain -Identity $Domain -Server $Domain}else{Get-ADDomain}
$ad=@{Server=$d.PDCEmulator;ErrorAction='Stop'}
$gp=@{Domain=$d.DNSRoot;Server=$d.PDCEmulator;ErrorAction='Stop'}
$gpPerm=@{DomainName=$d.DNSRoot;Server=$d.PDCEmulator;ErrorAction='Stop'}
if(-not $TargetOU){
    if($WhatIfPreference -or $Mode -eq 'Audit'){
        [pscustomobject]@{Status='DiscoveryOnly';Domain=$d.DNSRoot;GroupName=$GroupName;GpoName=$GpoName;TargetOUs=@(Get-ADOrganizationalUnit -Filter * -SearchBase $d.DistinguishedName @ad | Select-Object Name,DistinguishedName);ProductionReady=$false}
        return
    }
    throw 'ARCH8b1 explicitly select TargetOU; use -WhatIf to discover OUs.'
}
if([string]::IsNullOrWhiteSpace($GpoName) -or $GpoName.Length -gt 200){throw 'ARCH8b1 nonempty dedicated GPO name required.'}
$ou=Get-ADOrganizationalUnit -Identity $TargetOU -Properties CanonicalName @ad
if(-not $ou.DistinguishedName.EndsWith(','+$d.DistinguishedName,[StringComparison]::OrdinalIgnoreCase)){throw 'ARCH8b1 OU must belong to selected domain.'}
if(($ComputerName -and $AllComputersInOU) -or (-not $ComputerName -and -not $AllComputersInOU)){throw 'ARCH8b1 choose ComputerName or explicitly AllComputersInOU.'}
$available=@(Get-ADComputer -Filter 'Enabled -eq $true' -SearchBase $ou.DistinguishedName -SearchScope Subtree -Properties DNSHostName @ad)
$hosts=if($AllComputersInOU){$available}else{
    foreach($name in $ComputerName){
        $match=@($available | Where-Object {$_.Name -ieq $name -or $_.DNSHostName -ieq $name})
        if($match.Count -ne 1){throw ('ARCH8b1 host is not uniquely enabled under target OU: '+$name)}
        $match[0]
    }
}
$hosts=@($hosts | Sort-Object DNSHostName)
$hostNames=@($hosts | ForEach-Object {[string]$_.DNSHostName})
$scope=Get-OPAARCH8b1ScopeId -DomainSid $d.DomainSID.Value -TargetOU $ou.DistinguishedName -GroupName $GroupName -ComputerNames $hostNames -GpoName $GpoName
$ownerComment='OPA ARCH8b1 managed '+$scope
$gpos=@(Get-GPO -All @gp | Where-Object {$_.DisplayName -ieq $GpoName})
if($gpos.Count -gt 1 -or ($gpos.Count -eq 1 -and $gpos[0].Description -cne $ownerComment)){throw 'ARCH8b1 GPO name collision or scope changed; no unrelated GPO modified.'}
$gpo=if($gpos.Count -eq 1){$gpos[0]}else{$null}
if($gpo){
    $report=[xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml @gp)
    $links=@($report.SelectNodes("//*[local-name()='LinksTo']"))
    if($links.Count -gt 1 -or @($links | Where-Object {([string]$_.SOMPath).TrimEnd('/') -ine $ou.CanonicalName.TrimEnd('/')}).Count -gt 0){throw 'ARCH8b1 unexpected GPO link; no changes.'}
}
$group=$null
try{$group=Get-ADGroup -Identity $GroupName @ad}catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]{}
if($group -and ($group.SamAccountName -ine $GroupName -or [string]$group.GroupCategory -ne 'Security' -or -not $group.SID.Value.StartsWith($d.DomainSID.Value+'-',[StringComparison]::Ordinal))){throw 'ARCH8b1 existing group is not the expected domain security group.'}
$settings=[ordered]@{Domain=$d.DNSRoot;DeploymentId=$scope;GroupSid=if($group){$group.SID.Value}else{''};BatchSize=$BatchSize;MaxBatches=$AutoDevMaxBatches;OlderThanMonths=$OlderThanMonths;ArchiveGrouping=$ArchiveGrouping;OutlookWaitMinutes=$OutlookWaitMinutes}
$plan=[pscustomobject]@{Status='Plan';Mode=$Mode;Domain=$d.DNSRoot;TargetOU=$ou.DistinguishedName;Hosts=$hostNames;GroupName=$GroupName;GroupExists=($null -ne $group);GroupSid=$settings.GroupSid;GpoName=$GpoName;GpoExists=($null -ne $gpo);DeploymentId=$scope;Settings=$settings;ProductionReady=$false}
if($WhatIfPreference){$plan;return}
$hostAction=Join-Path $PSScriptRoot 'Core/Runtime/Invoke-OPAARCH8b1Host.ps1'
$probe=New-Object 'System.Collections.Generic.List[object]'
$command=''
if($Mode -notin @('Disable','Uninstall')){
    foreach($hostName in $hostNames){
        try{
            $r=Invoke-Command -ComputerName $hostName -Authentication Kerberos -FilePath $hostAction -ArgumentList @('Probe',(ConvertTo-Json -InputObject $settings -Compress),'') -ErrorAction Stop
            if(@($r).Count -ne 1){throw 'ARCH8b1 unexpected host preflight result.'}
            $probe.Add($r)
        }catch{
            if($Mode -ne 'Audit'){throw}
            $probe.Add([pscustomobject]@{Host=$hostName;Status='ProbeFailed';Message=$_.Exception.Message})
        }
    }
    $reachable=@($probe | Where-Object {$_.Status -ne 'ProbeFailed'})
    $layout=@($reachable | ForEach-Object {$_.ProgramFiles+'|'+$_.WindowsDirectory} | Sort-Object -Unique)
    if($layout.Count -ne 1 -and $Mode -ne 'Audit'){throw 'ARCH8b1 selected RDS must share the same ProgramFiles/Windows paths.'}
    if($layout.Count -eq 1){$command=New-OPAARCH8b1PolicyCommand -ProgramFiles $reachable[0].ProgramFiles -WindowsDirectory $reachable[0].WindowsDirectory}
}
$runKey='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run'
$policyKey='HKLM\SOFTWARE\Policies\OutlookPOP3Archive'
$valueName='OutlookPOP3Archive'
if($Mode -eq 'Audit'){
    $policy=@();$permissions=@();$policyError='';$logonPolicy=$null;$logonReadError=''
    if($gpo){
        try{$policy=@(Get-GPRegistryValue -Guid $gpo.Id -Key $policyKey @gp)}catch{$policyError=$_.Exception.Message}
        try{$logonPolicy=Get-GPRegistryValue -Guid $gpo.Id -Key $runKey -ValueName $valueName @gp}catch{$logonReadError=$_.Exception.Message}
        $permissions=@(Get-GPPermission -Guid $gpo.Id -All @gpPerm)
    }
    [pscustomobject]@{Status='AuditReadOnly';Plan=$plan;HostResults=@($probe.ToArray());PolicyValues=$policy;PolicyReadError=$policyError;LogonPolicy=$logonPolicy;LogonPolicyReadError=$logonReadError;GpoPermissions=$permissions;ExpectedLogonCommand=$command;ProductionReady=$false}
    return
}
if(-not $ConfirmDomainDeployment){throw 'ARCH8b1 explicit pilot consent -ConfirmDomainDeployment required.'}
if(-not $PSCmdlet.ShouldProcess(($d.DNSRoot+' / '+$ou.DistinguishedName+' / '+($hostNames -join ',')),('OPA DEV '+$Mode))){return}
if($Mode -in @('Disable','Uninstall')){
    if(-not $gpo){throw 'ARCH8b1 owned GPO not found; no cleanup performed.'}
    [void](Set-GPRegistryValue -Guid $gpo.Id -Key $policyKey -ValueName Enabled -Type DWord -Value 0 @gp)
    [void](Set-GPRegistryValue -Guid $gpo.Id -Key $runKey -ValueName $valueName -Disable @gp)
    if(-not $group){
        [pscustomobject]@{Status='PolicyDisabledGroupMissing';Plan=$plan;LocalCleanupPerformed=$false;PolicyRefreshRequired=$true;ProductionReady=$false}
        return
    }
}else{
    $payload=New-OPAARCH8b1Payload -ProjectRoot $PSScriptRoot
    if($Mode -eq 'Update' -and -not $gpo){throw 'ARCH8b1 Update requires owned GPO.'}
    if(-not $group){
        if($Mode -ne 'Install'){throw 'ARCH8b1 existing group required for Update/Repair.'}
        $path=if($GroupOU){(Get-ADOrganizationalUnit -Identity $GroupOU @ad).DistinguishedName}else{$d.UsersContainer}
        $group=New-ADGroup -Name $GroupName -SamAccountName $GroupName -GroupCategory Security -GroupScope Global -Path $path -PassThru @ad
        $settings.GroupSid=$group.SID.Value
    }
}
$results=New-Object 'System.Collections.Generic.List[object]'
$payloadJson=if($Mode -in @('Install','Update','Repair')){ConvertTo-Json -InputObject $payload -Depth 8 -Compress}else{''}
foreach($hostName in $hostNames){
    try{
        $r=Invoke-Command -ComputerName $hostName -Authentication Kerberos -FilePath $hostAction -ArgumentList @($Mode,(ConvertTo-Json -InputObject $settings -Compress),$payloadJson) -ErrorAction Stop
        if(@($r).Count -ne 1){throw 'ARCH8b1 unexpected remote result.'}
        $results.Add($r)
    }catch{$results.Add([pscustomobject]@{Host=$hostName;Status='Failed';Message=$_.Exception.Message})}
}
if(@($results | Where-Object {$_.Status -ceq 'Failed'}).Count -gt 0){
    [pscustomobject]@{Status='PartialDeployment';Plan=$plan;HostResults=@($results.ToArray());GpoEnabled=if($Mode -in @('Disable','Uninstall')){$false}else{'Unchanged'};ProductionReady=$false}
    return
}
if($Mode -in @('Install','Update','Repair')){
    if(-not $gpo){$gpo=New-GPO -Name $GpoName -Comment $ownerComment @gp}
    [void](Set-GPRegistryValue -Guid $gpo.Id -Key $policyKey -ValueName Enabled -Type DWord -Value 0 @gp)
    $authenticated=([Security.Principal.SecurityIdentifier]::new('S-1-5-11')).Translate([Security.Principal.NTAccount]).Value
    [void](Set-GPPermission -Guid $gpo.Id -TargetName $authenticated -TargetType Group -PermissionLevel GpoRead -Replace @gpPerm)
    foreach($computer in $hosts){
        $account=$d.NetBIOSName+'\'+$computer.Name
        [void](Set-GPPermission -Guid $gpo.Id -TargetName $account -TargetType Computer -PermissionLevel GpoApply -Replace @gpPerm)
    }
    # Confirm only the explicit computer SIDs have Apply permission.
    $applies=@(Get-GPPermission -Guid $gpo.Id -All @gpPerm | Where-Object {[string]$_.Permission -eq 'GpoApply'})
    $wantedSids=@($hosts | ForEach-Object {$_.SID.Value} | Sort-Object -Unique)
    $actualSids=@($applies | ForEach-Object {[string]$_.Trustee.Sid} | Sort-Object -Unique)
    if($actualSids.Count -ne $wantedSids.Count -or @($wantedSids | Where-Object {$_ -notin $actualSids}).Count -gt 0){throw 'ARCH8b1 unexpected GPO Apply permissions; policy remains disabled.'}
    foreach($name in @('DeploymentId','GroupSid','ArchiveGrouping')){
        [void](Set-GPRegistryValue -Guid $gpo.Id -Key $policyKey -ValueName $name -Type String -Value ([string]$settings[$name]) @gp)
    }
    foreach($name in @('BatchSize','MaxBatches','OlderThanMonths','OutlookWaitMinutes')){
        [void](Set-GPRegistryValue -Guid $gpo.Id -Key $policyKey -ValueName $name -Type DWord -Value ([int]$settings[$name]) @gp)
    }
    [void](Set-GPRegistryValue -Guid $gpo.Id -Key $runKey -ValueName $valueName -Type String -Value $command @gp)
    $link=@((Get-GPInheritance -Target $ou.DistinguishedName @gp).GpoLinks | Where-Object {$_.GpoId -eq $gpo.Id})
    if($link.Count -eq 0){[void](New-GPLink -Guid $gpo.Id -Target $ou.DistinguishedName -LinkEnabled Yes -Enforced No @gp)}
    elseif($link.Count -eq 1){[void](Set-GPLink -Guid $gpo.Id -Target $ou.DistinguishedName -LinkEnabled Yes -Enforced No @gp)}
    else{throw 'ARCH8b1 duplicate GPO link.'}
    [void](Set-GPRegistryValue -Guid $gpo.Id -Key $policyKey -ValueName Enabled -Type DWord -Value 1 @gp)
}
[pscustomobject]@{Status=if($Mode -in @('Install','Update','Repair')){'DeploymentConfigured'}else{'DeploymentDisabled'};Mode=$Mode;Domain=$d.DNSRoot;Group=$GroupName;GroupSid=$settings.GroupSid;GpoId=$gpo.Id;TargetOU=$ou.DistinguishedName;HostResults=@($results.ToArray());PolicyRefreshRequired=$true;NewLogonRequired=$true;ProductionReady=$false}
