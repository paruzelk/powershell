Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'shareaudit.ps1'
$fixture = Join-Path $PSScriptRoot ('.fixture-' + $PID)
$oldComputerName = $env:COMPUTERNAME
$oldDomain = $env:USERDOMAIN
$oldModulePath = $env:PSModulePath
$global:mockIdentity = 'Everyone'
$global:mockSecondAce = $true
$global:mockAclFailure = $false

function global:Get-Acl {
    param([string]$LiteralPath)
    if ($global:mockAclFailure) { throw 'simulated ACL failure' }
    $access = @([pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = $global:mockIdentity }; IsInherited = $false; AccessControlType = 'Allow'; FileSystemRights = 'Read' })
    if ($global:mockSecondAce) {
        $access += [pscustomobject]@{ IdentityReference = [pscustomobject]@{ Value = 'CONTOSO\TestGroup' }; IsInherited = $false; AccessControlType = 'Allow'; FileSystemRights = 'Read' }
    }
    [pscustomobject]@{
        Access = $access
    }
}

try {
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    $env:COMPUTERNAME = '<script>alert(1)</script>'
    $env:USERDOMAIN = '<domain&test>'
    $reportPath = Join-Path $fixture 'report.html'

    try {
        & $scriptPath -Drives @($fixture) -OutputPath $reportPath -ResolveGroups $false -ScanSubfolders $false | Out-Null
    } catch {
        Write-Output $_.ScriptStackTrace
        throw
    }
    $html = Get-Content -LiteralPath $reportPath -Raw
    if ($html -notmatch '&lt;script&gt;alert\(1\)&lt;/script&gt;') { throw 'Server metadata is not HTML encoded.' }
    if ($html -match '<script>alert\(1\)</script>') { throw 'Server metadata permits HTML injection.' }
    if ($html -notmatch '&lt;domain&amp;test&gt;') { throw 'Domain metadata is not HTML encoded.' }
    if ($html -notmatch '<td>Everyone(?:\s|<)') { throw 'Default report omits Everyone permissions.' }

    $missingParent = Join-Path $fixture 'missing'
    $missingOutput = Join-Path $missingParent 'report.html'
    $writeFailed = $false
    try {
        & $scriptPath -Drives @($fixture) -OutputPath $missingOutput -ResolveGroups $false -ScanSubfolders $false 2>$null 6>$null | Out-Null
    } catch {
        $writeFailed = $true
    }
    if (-not $writeFailed) { throw 'Unwritable output path was reported as success.' }

    $moduleDir = Join-Path $fixture 'ActiveDirectory'
    New-Item -ItemType Directory -Path $moduleDir | Out-Null
    @'
function Get-ADGroup {
    param([string]$Identity)
    if ($Identity -ne 'S-1-5-21-111-222-333-444') { throw "Unexpected group identity: $Identity" }
    [pscustomobject]@{ DistinguishedName = 'CN=TestGroup,DC=contoso,DC=example' }
}
function Get-ADGroupMember {
    param([string]$Identity)
    if ($Identity -ne 'CN=TestGroup,DC=contoso,DC=example') { throw "Unexpected member lookup: $Identity" }
    [pscustomobject]@{ objectClass = 'user'; SamAccountName = 'user1'; DistinguishedName = 'CN=User One,DC=contoso,DC=example' }
}
function Get-ADUser {
    param([string]$Identity, [string[]]$Properties)
    [pscustomobject]@{ DisplayName = '<AD User>' }
}
Export-ModuleMember -Function Get-ADGroup,Get-ADGroupMember,Get-ADUser
'@ | Set-Content -LiteralPath (Join-Path $moduleDir 'ActiveDirectory.psm1') -Encoding ASCII
    $env:PSModulePath = "$fixture;$oldModulePath"
    $global:mockIdentity = 'S-1-5-21-111-222-333-444'
    $global:mockSecondAce = $false
    & $scriptPath -Drives @($fixture) -OutputPath $reportPath -ResolveGroups $true -ScanSubfolders $false | Out-Null
    $html = Get-Content -LiteralPath $reportPath -Raw
    if ($html -notmatch '&lt;AD User&gt;') { throw 'AD group referenced by SID was not expanded.' }

    $global:mockAclFailure = $true
    & $scriptPath -Drives @($fixture) -OutputPath $reportPath -ResolveGroups $false -ScanSubfolders $false | Out-Null
    $html = Get-Content -LiteralPath $reportPath -Raw
    if ($html -notmatch 'Предупреждения при сканировании' -or $html -notmatch 'simulated ACL failure') {
        throw 'ACL read failure is missing from the report.'
    }

    Write-Output 'PASS: report metadata, default principals, output errors, AD SID lookup, and scan warnings'
} finally {
    $env:COMPUTERNAME = $oldComputerName
    $env:USERDOMAIN = $oldDomain
    $env:PSModulePath = $oldModulePath
    Remove-Item -Path Function:\Get-Acl -ErrorAction SilentlyContinue
    Remove-Variable -Name mockIdentity -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name mockSecondAce -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name mockAclFailure -Scope Global -ErrorAction SilentlyContinue
    Remove-Module ActiveDirectory -Force -ErrorAction SilentlyContinue
    $fixturePath = [IO.Path]::GetFullPath($fixture)
    $testsPath = [IO.Path]::GetFullPath($PSScriptRoot)
    if ($fixturePath.StartsWith($testsPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $fixturePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
