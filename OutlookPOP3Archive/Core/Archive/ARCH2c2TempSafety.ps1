#requires -Version 5.1
# ARCH2c2: protected per-witness TEMP directory and exclusive lifetime lease.
# No Outlook COM access, PST writes, automatic orphan deletion, or writer permit.
function Assert-OPA265ARCH2c2TempRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $root=[IO.Path]::GetFullPath($Path)
    if($root.StartsWith('\\') -or -not [IO.Directory]::Exists($root)){
        throw 'ARCH2c2 local TEMP root missing or unsupported; no Move authorized.'
    }
    if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'ARCH2c2 TEMP root is a reparse point; no Move authorized.'
    }
    return $root
}
function Assert-OPA265ARCH2c2PrivateWorkspaceAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$WorkspacePath)
    if(-not [IO.Directory]::Exists($WorkspacePath) -or
       (([IO.File]::GetAttributes($WorkspacePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH2c2 workspace missing or reparse point; no Move authorized.'
    }
    $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
    if($null -eq $owner){throw 'ARCH2c2 process identity unavailable; no Move authorized.'}
    $systemSid=New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'
    $security=[IO.Directory]::GetAccessControl($WorkspacePath)
    if(-not $security.AreAccessRulesProtected){
        throw 'ARCH2c2 inherited workspace DACL; no Move authorized.'
    }
    if(-not $security.GetOwner([Security.Principal.SecurityIdentifier]).Equals($owner)){
        throw 'ARCH2c2 workspace owner is not the current Windows identity.'
    }
    $rules=@($security.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if($rules.Count -lt 2){throw 'ARCH2c2 workspace private DACL is incomplete.'}
    $hasOwner=$false;$hasSystem=$false
    foreach($rule in $rules){
        if($rule.IsInherited -or
           $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){
            throw 'ARCH2c2 workspace DACL has inherited/deny access; no Move authorized.'
        }
        $sid=$rule.IdentityReference
        if($sid.Equals($owner)){$hasOwner=$true}
        elseif($sid.Equals($systemSid)){$hasSystem=$true}
        else {throw 'ARCH2c2 workspace DACL grants an unexpected identity; no Move authorized.'}
        $full=[int][Security.AccessControl.FileSystemRights]::FullControl
        if(([int]$rule.FileSystemRights -band $full) -ne $full){
            throw 'ARCH2c2 workspace DACL lacks full control for permitted identity.'
        }
    }
    if(-not $hasOwner -or -not $hasSystem){
        throw 'ARCH2c2 workspace owner/system permissions missing.'
    }
    return $true
}
function New-OPA265ARCH2c2PrivateWorkspace {
    [CmdletBinding()]
    param([string]$TemporaryDirectory=[IO.Path]::GetTempPath())
    $root=Assert-OPA265ARCH2c2TempRoot -Path $TemporaryDirectory
    $currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    if($null -eq $currentSid){throw 'ARCH2c2 Windows identity required.'}
    $systemSid=New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'
    $dacl=New-Object Security.AccessControl.DirectorySecurity
    $dacl.SetAccessRuleProtection($true,$false)
    $inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach($sid in @($currentSid,$systemSid)){
        $rule=New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inherit,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $dacl.AddAccessRule($rule)
    }
    $workspace=Join-Path $root ('OPA-ARCH2c1-'+[guid]::NewGuid().ToString('N'))
    if([IO.Directory]::Exists($workspace) -or [IO.File]::Exists($workspace)){
        throw 'ARCH2c2 workspace collision; no Move authorized.'
    }
    # .NET Framework creates the directory with this ACL rather than broad
    # inherited permissions and a subsequent, race-prone ACL adjustment.
    [void][IO.Directory]::CreateDirectory($workspace,$dacl)
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $workspace)
    $leasePath=Join-Path $workspace '.opa-lease'
    # Exclusive stream remains open until all attachment copies are removed.
    $lease=[IO.File]::Open($leasePath,[IO.FileMode]::CreateNew,
        [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    return [pscustomobject]@{
        WorkspacePath=[string]$workspace
        LeasePath=[string]$leasePath
        LeaseStream=$lease
    }
}
function Close-OPA265ARCH2c2PrivateWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Workspace)
    $workspacePath=[string]$Workspace.WorkspacePath
    $leasePath=[string]$Workspace.LeasePath
    $name=[IO.Path]::GetFileName($workspacePath)
    if($name -cnotmatch '^OPA-ARCH2c1-[0-9a-f]{32}$' -or
       $leasePath -cne (Join-Path $workspacePath '.opa-lease')){
        throw 'ARCH2c2 workspace identity mismatch; no cleanup attempted.'
    }
    $lease=$Workspace.LeaseStream
    if($null -eq $lease){throw 'ARCH2c2 lease handle missing; manual review required.'}
    try {$lease.Dispose()}
    finally {$Workspace.LeaseStream=$null}
    if(-not [IO.Directory]::Exists($workspacePath)){throw 'ARCH2c2 workspace disappeared; stop.'}
    if(([IO.File]::GetAttributes($workspacePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'ARCH2c2 workspace changed to reparse point; stop.'
    }
    [void](Assert-OPA265ARCH2c2PrivateWorkspaceAcl -WorkspacePath $workspacePath)
    if(-not [IO.File]::Exists($leasePath) -or
       (([IO.File]::GetAttributes($leasePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
        throw 'ARCH2c2 lease file missing or reparse point; manual review required.'
    }
    # Do not recursively remove files: unexpected payloads remain for review.
    if(@([IO.Directory]::GetFileSystemEntries($workspacePath)).Count -ne 1){
        throw 'ARCH2c2 workspace contains unexpected entries; manual review required.'
    }
    [IO.File]::Delete($leasePath)
    [IO.Directory]::Delete($workspacePath,$false)
}
function Get-OPA265ARCH2c2ObservedLeaseState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$WorkspacePath)
    $leasePath=Join-Path $WorkspacePath '.opa-lease'
    if(-not [IO.File]::Exists($leasePath)){return 'Absent'}
    if(([IO.File]::GetAttributes($leasePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        return 'UnsafeReparsePoint'
    }
    $probe=$null
    try {
        $probe=[IO.File]::Open($leasePath,[IO.FileMode]::Open,
            [IO.FileAccess]::Read,[IO.FileShare]::None)
        return 'NotHeldAtObservation'
    }
    catch {
        # IOException and access errors both mean that it is NOT safe to clean.
        return 'HeldOrUnavailable'
    }
    finally {
        if($null -ne $probe){$probe.Dispose()}
    }
}
