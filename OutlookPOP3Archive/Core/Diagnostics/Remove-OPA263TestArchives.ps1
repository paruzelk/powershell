#requires -Version 5.1
<#
.SYNOPSIS
  Previews or explicitly removes OLD, abandoned opa263_archive*.pst test files.
.DESCRIPTION
  Preview by default. Does not use Outlook COM, detach stores, close Outlook,
  delete folders, or touch opa264 test evidence. Recursive search is opt-in.
  Actual deletion requires -Delete and a precise -ApprovalToken.
.EXAMPLE
  .\Remove-OPA263TestArchives.ps1 -SearchPath "$env:USERPROFILE\Downloads" -Recurse
.EXAMPLE
  .\Remove-OPA263TestArchives.ps1 -SearchPath "$env:USERPROFILE\Downloads" -Recurse -Delete -ApprovalToken DELETE-OPA263-ARCHIVES -Confirm
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SearchPath = (Join-Path $env:USERPROFILE 'Downloads'),

    [switch]$Recurse,
    [switch]$Delete,

    [string]$ApprovalToken = '',

    [ValidateRange(1, 100000)]
    [int]$MaxFiles = 1000
)

$ErrorActionPreference = 'Stop'
$pattern = '^opa263_archive.*\.pst$'

function Assert-OPA263LocalRealDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw 'UNC / network directories are not allowed for this cleanup.'
    }
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw 'SearchPath must be an existing directory.'
    }
    $full = [IO.Path]::GetFullPath($resolved).TrimEnd([char]'\', [char]'/')
    if ([string]::IsNullOrWhiteSpace($full)) { throw 'Invalid search directory.' }
    $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) {
        throw 'Only a fixed local filesystem drive is allowed.'
    }
    # Check the directory itself AND its ancestors. GetFullPath does not
    # resolve junctions; do not let a junction redirect deletion elsewhere.
    $cursor = $full
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        $info = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Symlink/junction in SearchPath: ' + $cursor)
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }
    return $full
}

function Assert-OPA263Candidate {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $full = [IO.Path]::GetFullPath($FilePath)
    $inside = $Root.TrimEnd([char]'\', [char]'/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($inside, [StringComparison]::OrdinalIgnoreCase)) {
        throw ('Candidate escapes search root: ' + $full)
    }
    if ([IO.Path]::GetFileName($full) -cnotmatch '(?i)^opa263_archive.*\.pst$') {
        throw ('Unexpected filename outside the exact test prefix: ' + $full)
    }
    $cursor = $full
    while ($true) {
        $info = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Symlink/junction candidate is forbidden: ' + $cursor)
        }
        if ($cursor.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { throw 'Candidate escaped root during verification.' }
        $cursor = $parent.FullName
    }
    return $full
}

$root = Assert-OPA263LocalRealDirectory -Path $SearchPath
if ($Delete -and $ApprovalToken -cne 'DELETE-OPA263-ARCHIVES') {
    throw 'Deletion requires -ApprovalToken DELETE-OPA263-ARCHIVES.'
}
if (-not $Delete -and -not [string]::IsNullOrWhiteSpace($ApprovalToken)) {
    throw 'ApprovalToken can only be passed with -Delete.'
}

# For deletion, fail closed if ANY Outlook process is active. Even a .pst
# apparently free of open handles may still be attached to an Outlook profile.
if ($Delete) {
    $outlook = @(Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue)
    if ($outlook.Count -gt 0) {
        throw ('Close Outlook before deletion. Detach old test PST stores manually; ' +
               'Outlook process(es) currently running: ' + $outlook.Count)
    }
}

$params = @{ LiteralPath = $root; File = $true; Force = $true; ErrorAction = 'Stop' }
if ($Recurse) { $params['Recurse'] = $true }
$found = @(Get-ChildItem @params | Where-Object { $_.Name -match $pattern })
if ($found.Count -gt $MaxFiles) {
    throw ('Too many candidates: {0}, MaxFiles={1}. Review this folder manually.' -f $found.Count, $MaxFiles)
}

$paths = New-Object 'System.Collections.Generic.List[string]'
foreach ($item in $found) {
    [void]$paths.Add((Assert-OPA263Candidate -FilePath $item.FullName -Root $root))
}
$sorted = @($paths.ToArray() | Sort-Object)
Write-Host ('Mode: {0} | Root: {1} | Recursive: {2} | Candidates: {3}' -f
    $(if ($Delete) { 'DELETE (explicit approval)' } else { 'PREVIEW ONLY' }),
    $root, [bool]$Recurse, $sorted.Count)

foreach ($path in $sorted) {
    # Reconfirm file is present and remains in the allowed scope.
    $safe = Assert-OPA263Candidate -FilePath $path -Root $root
    $file = Get-Item -LiteralPath $safe -Force -ErrorAction Stop
    $sizeMB = [Math]::Round(([double]$file.Length / 1MB), 2)
    if (-not $Delete) {
        [pscustomobject]@{
            Action = 'PreviewOnly'
            PST = $safe
            SizeMB = $sizeMB
        }
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($safe, 'Permanently delete abandoned opa263_archive*.pst')) {
        [pscustomobject]@{ Action = 'Skipped'; PST = $safe; SizeMB = $sizeMB }
        continue
    }
    # A locked PST is not safe to remove. No -Force switch on Remove-Item;
    # a read-only or inaccessible file remains untouched.
    $stream = $null
    try {
        $stream = [IO.File]::Open($safe, [IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch {
        Write-Warning ('Locked or inaccessible PST, skipped: ' + $safe)
        [pscustomobject]@{ Action = 'LockedSkipped'; PST = $safe; SizeMB = $sizeMB }
        continue
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
    try {
        Remove-Item -LiteralPath $safe -ErrorAction Stop
        [pscustomobject]@{ Action = 'Deleted'; PST = $safe; SizeMB = $sizeMB }
    }
    catch {
        Write-Warning ('Deletion failed: ' + $safe + ' — ' + $_.Exception.Message)
        [pscustomobject]@{ Action = 'DeleteFailed'; PST = $safe; SizeMB = $sizeMB }
    }
}
