# Safe regression tests. Loads function definitions without running the entry point.
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'Remove-StaleProfiles.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Source script does not parse.' }

if (-not ([System.Management.Automation.PSTypeName]'Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException').Type) {
    Add-Type -TypeDefinition 'namespace Microsoft.ActiveDirectory.Management { public class ADIdentityNotFoundException : System.Exception { public string Kind { get { return "NotFound"; } } public ADIdentityNotFoundException(string message) : base(message) {} } }'
}
if (-not ([System.Management.Automation.PSTypeName]'ProfileSizeHelper').Type) {
    Add-Type -TypeDefinition 'public static class ProfileSizeHelper { public static long GetSize(string path) { return 104857600; } }'
}

$names = @('Initialize-Environment', 'Initialize-LocalAccountDomainSid', 'Add-ProtectedFromAdGroup', 'Get-ProfileDecision', 'Get-SamAccountName', 'Remove-UserProfile', 'Export-HtmlReport', 'ConvertTo-HtmlSafe')
foreach ($name in $names) {
    $node = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $node) { throw "Function not found: $name" }
    . ([scriptblock]::Create($node.Extent.Text))
}

$failures = 0
function Invoke-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        Write-Output "PASS $Name"
    }
    catch {
        $script:failures++
        Write-Output "FAIL $Name : $($_.Exception.Message)"
    }
}

Invoke-Case 'startup stops when log directory cannot be created' {
    $ErrorActionPreference = 'Continue'
    $script:RunFolder = 'QQQQ:\missing\run'
    $script:LogFile = 'QQQQ:\missing\run\log.txt'
    $threw = $false
    try { Initialize-Environment 2>$null } catch { $threw = $true }
    if (-not $threw) { throw 'Initialization continued after a write failure.' }
}

Invoke-Case 'missing protected AD group is incomplete protection' {
    $script:ADParams = @{}
    function Get-ADGroup { throw [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]::new('missing group') }
    function Write-Console { param($Message, $Level) }
    $complete = Add-ProtectedFromAdGroup 'S-1-5-21-1-2-3-512'
    if ($complete) { throw 'Missing protected group was accepted.' }
}

Invoke-Case 'local account domain SID is read from local CIM users' {
    $script:LocalAccountDomainSid = $null
    function Get-CimInstance { return [pscustomobject]@{ SID = 'S-1-5-21-10-20-30-500'; LocalAccount = $true } }
    function Write-Console { param($Message, $Level) }
    Initialize-LocalAccountDomainSid
    if ($script:LocalAccountDomainSid -ne 'S-1-5-21-10-20-30') { throw 'Local SID domain was not identified.' }
}

Invoke-Case 'unresolved local SID is not a domain orphan' {
    $Config = [pscustomobject]@{
        ProfileRoot = 'C:\Users'; DomainOnly = $true; ADMode = 'All'
        ExcludedUsers = @(); UseNtUserDatTime = $false; UseADLastLogon = $false
        IncludeOrphanedSIDs = $true; MinimumProfileSizeMB = 50
    }
    $script:ComputerName = 'TESTSERVER'
    $script:Threshold = (Get-Date).AddDays(-90)
    $script:LocalAccountDomainSid = 'S-1-5-21-10-20-30'
    $script:ProtectedSids = [System.Collections.Generic.HashSet[string]]::new()
    $script:ActiveSessions = [System.Collections.Generic.HashSet[string]]::new()
    function Test-Path { param($LiteralPath) return $true }
    function Convert-SidToAccount { param($Sid) return $null }
    function Get-ADUserInfo { param($Sid) return [pscustomobject]@{ Status = 'NotFound'; User = $null } }
    $profile = [pscustomobject]@{ SID = 'S-1-5-21-10-20-30-1001'; LocalPath = 'C:\Users\orphan'; Special = $false; Loaded = $false; LastUseTime = (Get-Date).AddDays(-180) }
    $decision = Get-ProfileDecision $profile
    if (-not $decision.Reason) { throw 'Unresolved local SID became a deletion candidate.' }
}

Invoke-Case 'deletion rechecks eligibility with fresh data' {
    $Config = [pscustomobject]@{ ProfileRoot = 'C:\Users'; DomainOnly = $true; AbortIfProtectionIncomplete = $true }
    $script:ComputerName = 'TESTSERVER'
    $script:ADAvailable = $true
    $script:ProtectionComplete = $true
    $script:ADCache = @{ 'S-1-5-21-1-2-3-1001' = 'stale' }
    $script:removed = $false
    $script:decisionChecked = $false
    $script:cacheCleared = $false
    function Get-CimInstance { return [pscustomobject]@{ SID = 'S-1-5-21-1-2-3-1001'; LocalPath = 'C:\Users\someone'; Special = $false; Loaded = $false } }
    function Remove-CimInstance { $script:removed = $true }
    function Initialize-ActiveDirectory { $script:ADAvailable = $true }
    function Initialize-Protection { $script:ProtectionComplete = $true }
    function Get-ActiveRDSSessions { }
    function Get-ProfileDecision {
        param($Profile)
        $script:decisionChecked = $true
        $script:cacheCleared = -not $script:ADCache.ContainsKey($Profile.SID)
        return [pscustomobject]@{ Reason = 'AD account enabled' }
    }
    function Write-Console { param($Message, $Level) }
    $script:Stats = [pscustomobject]@{ Deleted = 0; FreedBytes = [long]0 }
    $outcome = Remove-UserProfile -Sid 'S-1-5-21-1-2-3-1001' -SizeBytes 100
    if (-not $script:decisionChecked -or -not $script:cacheCleared) { throw 'Fresh profile decision was not evaluated.' }
    if ($script:removed -or $outcome) { throw 'Ineligible profile reached Remove-CimInstance.' }
}

Invoke-Case 'HTML export records a write failure' {
    $ErrorActionPreference = 'Continue'
    $script:HtmlFile = Join-Path (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))) 'report.html'
    $script:Results = New-Object 'System.Collections.Generic.List[object]'
    $script:Stats = [pscustomobject]@{ ProfilesFound = 0; ProfilesChecked = 0; WouldDelete = 0; Deleted = 0; Skipped = 0; Warnings = 0; Errors = 0; FreedBytes = [long]0 }
    $script:ComputerName = 'TESTSERVER'
    $script:StartTime = Get-Date
    $script:ADAvailable = $true
    $script:ProtectionComplete = $true
    $Config = [pscustomobject]@{ ScriptVersion = 'test'; Mode = 'Audit'; ADMode = 'All'; Days = 90 }
    $script:logLevels = New-Object 'System.Collections.Generic.List[string]'
    $script:logMessages = New-Object 'System.Collections.Generic.List[string]'
    function Write-Console { param($Message, $Level) [void]$script:logLevels.Add([string]$Level); [void]$script:logMessages.Add([string]$Message) }
    Export-HtmlReport 2>$null
    if (-not (($script:logLevels -contains 'ERROR') -and ($script:logMessages -match 'report.html'))) {
        throw "HTML export did not report the write failure: $($script:logMessages -join ' | ')"
    }
}

if ($failures -gt 0) { exit 1 }
exit 0
