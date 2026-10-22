#requires -Version 5.1
# Release-only file selection. This module never removes files from the source.
# PST, checkpoints, worker evidence, and transaction folders are never staged.

function Get-OPAReleasePackageFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$ExpectedBuild
    )
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Project directory not found: $root"
    }
    $source = New-Object 'System.Collections.Generic.List[object]'
    $topLevel = @(
        '.gitignore', '.psscriptanalyzer.psd1', 'CHANGELOG.md', 'README.md',
        'MANIFEST.txt', 'RELEASE.json', 'OutlookPOP3Archive.ps1',
        'OutlookPOP3Archive.Worker.ps1', 'Invoke-CI.ps1',
        'Invoke-OPAWorkerSelfTest.ps1', 'New-OPABuildPackage.ps1'
    )
    foreach ($name in $topLevel) {
        $full = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Mandatory release source file is missing: $name"
        }
        $file = Get-Item -LiteralPath $full -Force
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Release source contains a link: $name"
        }
        [void]$source.Add([pscustomobject]@{RelativePath=$name; FullName=$file.FullName})
    }
    foreach ($spec in @(
        @{ Name='Core'; Extension='.ps1' },
        @{ Name='Tests'; Extension='.ps1' },
        @{ Name='docs'; Extension='.md' }
    )) {
        $folder = Join-Path $root $spec.Name
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            throw "Mandatory release directory missing: $($spec.Name)"
        }
        $items = @(Get-ChildItem -LiteralPath $folder -File -Recurse -Force -ErrorAction Stop)
        foreach ($file in $items) {
            $relative = $file.FullName.Substring($root.Length).TrimStart('\','/') -replace '\\','/'
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Release source contains a link: $relative"
            }
            if ($file.Extension -cne $spec.Extension) {
                throw "Unexpected file in release source directory: $relative"
            }
            if ($spec.Name -eq 'Tests' -and $file.Name -notmatch '\.Tests\.ps1$') {
                throw "Non-Pester script in Tests directory: $relative"
            }
            if ($relative -match '(?i)(?:^|/)(?:TEST-FIX[^/]*|MANIFEST-RC1[^/]*|RELEASE-RC1[^/]*|BUILD-2\.[^/]*|TEST-2\.[^/]*)$') {
                throw "Obsolete release artifact: $relative"
            }
            # Versioned feature documents cannot be shipped as a different
            # build. This catches a 2.6.2 plan accidentally in a 2.6.1 ZIP.
            if ($spec.Name -eq 'docs' -and $file.Name -match '^(?<version>\d+\.\d+\.\d+)-') {
                $expectedBase = ([regex]::Match($ExpectedBuild, '^\d+\.\d+\.\d+')).Value
                if ($Matches['version'] -cne $expectedBase) {
                    throw "Versioned document '$relative' disagrees with build $ExpectedBuild."
                }
            }
            [void]$source.Add([pscustomobject]@{RelativePath=$relative; FullName=$file.FullName})
        }
    }
    if ($source.Count -lt 10) { throw 'Release source inventory unexpectedly empty.' }
    return $source.ToArray() | Sort-Object RelativePath
}

function Assert-OPAReleaseSourceHygiene {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectRoot)
    # Historical documents must remain in Git history, not in the release root.
    $root = [IO.Path]::GetFullPath($ProjectRoot)
    $old = @(Get-ChildItem -LiteralPath $root -File -Force -ErrorAction Stop | Where-Object {
        $_.Name -match '(?i)^(?:TEST-FIX.*\.md|TEST-2\.\d+.*\.md|MANIFEST-RC1\.txt|RELEASE-RC1\.json|BUILD-2\.\d+.*\.txt)$' -or
        $_.Extension -in @('.zip','.bak','.old','.tmp')
    })
    if ($old.Count -gt 0) {
        throw ('Obsolete files at project root: ' + (($old | ForEach-Object Name) -join ', '))
    }
    return $true
}
