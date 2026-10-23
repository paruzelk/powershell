#requires -Version 5.1
# 2.6.4-G: offline source/ZIP release-readiness evidence. No Outlook COM,
# PST handling, Worker launch, file mutation, or implicit production approval.

function Get-OPA264GSourceInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourceRoot)
    $root=[IO.Path]::GetFullPath($SourceRoot).TrimEnd([char]'\',[char]'/')
    if (-not [IO.Directory]::Exists($root)) { throw 'G inventory source directory missing.' }
    if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'G inventory refuses a reparse-point source root.'
    }
    $files=@(Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction Stop)
    $directories=@(Get-ChildItem -LiteralPath $root -Recurse -Force -Directory -ErrorAction Stop)
    foreach ($element in @($files)+@($directories)) {
        if ($element.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'G inventory refuses a reparse-point source entry.'
        }
    }
    $paths=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $files) {
        $relative=$item.FullName.Substring($root.Length).TrimStart([char]'\',[char]'/').Replace('\','/')
        if ($relative -ceq 'BUILD-INFO.json') { continue }
        if ([string]::IsNullOrWhiteSpace($relative) -or
            $relative.StartsWith('/') -or
            @($relative.Split('/') | Where-Object { $_ -in @('.','..','') }).Count -gt 0) {
            throw 'G inventory contains an invalid relative filename.'
        }
        if ($paths.ContainsKey($relative)) { throw 'G inventory has a colliding relative filename.' }
        $paths.Add($relative,$item.FullName)
    }
    $names=[string[]]@($paths.Keys)
    [Array]::Sort($names,[StringComparer]::Ordinal)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $content=New-Object Text.StringBuilder
    foreach ($name in $names) {
        $sha=([string](Get-FileHash -LiteralPath $paths[$name] -Algorithm SHA256 -ErrorAction Stop).Hash).ToLowerInvariant()
        [void]$rows.Add([pscustomobject]@{RelativePath=$name;SHA256=$sha;FilePath=$paths[$name]})
        [void]$content.Append($name).Append([char]9).Append($sha).Append([char]10)
    }
    $hash=[Security.Cryptography.SHA256]::Create()
    try {
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($content.ToString())
        $inventoryHash=([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    }
    finally { $hash.Dispose() }
    return [pscustomobject]@{
        SourceRoot=$root
        FileCount=[int]$rows.Count
        InventorySHA256=$inventoryHash
        Files=$rows.ToArray()
    }
}

function Assert-OPA264GDevPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$SourceRoot,
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$ExpectedSourceCommit,
        [Parameter(Mandatory=$true)][string]$ExpectedZipSHA256,
        [ValidateRange(1,50000)][int]$ExpectedTests=442,
        [ValidateRange(1,1000)][int]$ExpectedContainers=33
    )
    if ($ExpectedSourceCommit -cnotmatch '^[a-f0-9]{40}$' -or
        $ExpectedZipSHA256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'G package requires externally pinned lowercase Git commit and ZIP SHA256.'
    }
    $zipFile=[IO.Path]::GetFullPath($ZipPath)
    if (-not [IO.File]::Exists($zipFile)) { throw 'G package ZIP file missing.' }
    $stem=[IO.Path]::GetFileNameWithoutExtension($zipFile)
    if ($stem -cnotmatch '^OutlookPOP3Archive-2\.6\.4-G-dev-g[a-f0-9]{8}$' -or
        -not $stem.EndsWith(('g'+$ExpectedSourceCommit.Substring(0,8)),[StringComparison]::Ordinal)) {
        throw 'G package ZIP basename does not match source Git commit.'
    }
    $actualZip=([string](Get-FileHash -LiteralPath $zipFile -Algorithm SHA256 -ErrorAction Stop).Hash).ToLowerInvariant()
    if ($actualZip -cne $ExpectedZipSHA256) { throw 'G package ZIP SHA256 mismatch.' }
    $inventory=Get-OPA264GSourceInventory -SourceRoot $SourceRoot
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive=$null
    $entryCount=0
    $buildInfo=$null
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $sourceLookup=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $inventory.Files) { $sourceLookup.Add([string]$row.RelativePath,[string]$row.SHA256) }
    try {
        $archive=[IO.Compression.ZipFile]::OpenRead($zipFile)
        if ($archive.Entries.Count -gt 1000 -or $archive.Entries.Count -ne ($inventory.FileCount+1)) {
            throw 'G package ZIP has an unexpected file count.'
        }
        [long]$uncompressed=0
        foreach ($entry in $archive.Entries) {
            $entryCount++
            [string]$name=$entry.FullName
            if (-not $name.StartsWith(($stem+'/'),[StringComparison]::Ordinal)) {
                throw 'G package ZIP has an unexpected root folder.'
            }
            $relative=$name.Substring($stem.Length+1)
            if ([string]::IsNullOrWhiteSpace($relative) -or
                $relative.Contains('\') -or
                $relative.StartsWith('/') -or
                @($relative.Split('/') | Where-Object { $_ -in @('.','..','') }).Count -gt 0) {
                throw 'G package ZIP contains a traversal, directory, or invalid entry.'
            }
            if (-not $seen.Add($relative)) { throw 'G package ZIP contains duplicate entry names.' }
            if ($entry.Length -gt 50000000) { throw 'G package ZIP entry too large.' }
            $uncompressed += [long]$entry.Length
            if ($uncompressed -gt 200000000) { throw 'G package ZIP uncompressed size limit exceeded.' }
            $stream=$null
            $hash=$null
            try {
                $stream=$entry.Open()
                $hash=[Security.Cryptography.SHA256]::Create()
                $entryHash=([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
            }
            finally {
                if ($null -ne $hash) { $hash.Dispose() }
                if ($null -ne $stream) { $stream.Dispose() }
            }
            if ($relative -ceq 'BUILD-INFO.json') {
                $reader=$null
                try {
                    $reader=New-Object IO.StreamReader($entry.Open(),(New-Object Text.UTF8Encoding($false)))
                    $buildInfo=ConvertFrom-Json -InputObject $reader.ReadToEnd() -ErrorAction Stop
                }
                finally { if ($null -ne $reader) { $reader.Dispose() } }
                continue
            }
            if (-not $sourceLookup.ContainsKey($relative) -or
                $entryHash -cne $sourceLookup[$relative]) {
                throw 'G package ZIP entry differs from checked-out source.'
            }
        }
    }
    finally { if ($null -ne $archive) { $archive.Dispose() } }
    if ($null -eq $buildInfo -or
        [string]$buildInfo.Kind -cne 'DEVELOPMENT_SNAPSHOT_NOT_RELEASE' -or
        [string]$buildInfo.Stage -cne '2.6.4-G' -or
        [string]$buildInfo.SourceCommit -cne $ExpectedSourceCommit -or
        [string]$buildInfo.SourceInventorySHA256 -cne $inventory.InventorySHA256 -or
        [int]$buildInfo.SourceFileCount -ne $inventory.FileCount -or
        [int]$buildInfo.ExpectedPesterTests -ne $ExpectedTests -or
        [int]$buildInfo.ExpectedTestContainers -ne $ExpectedContainers -or
        [string]$buildInfo.WindowsCI -cne 'PENDING' -or
        [string]$buildInfo.RealOutlookTest -cne 'NOT_RUN' -or
        [string]$buildInfo.PackageRoot -cne $stem) {
        throw 'G package embedded BUILD-INFO identity or release-gate mismatch.'
    }
    foreach ($field in @('ArchiveWorkerEnabled','ResumeWorkerEnabled','AutoWorkerEnabled')) {
        if ($buildInfo.PSObject.Properties.Name -cnotcontains $field -or
            $buildInfo.$field -isnot [bool] -or [bool]$buildInfo.$field) {
            throw "G package has unsafe Worker integration flag: $field."
        }
    }
    return [pscustomobject]@{
        Schema='2.6.4-G.Package.1'
        PackageName=[IO.Path]::GetFileName($zipFile)
        RootFolder=$stem
        SourceCommit=$ExpectedSourceCommit
        SourceInventorySHA256=$inventory.InventorySHA256
        ZipSHA256=$actualZip
        FilesChecked=$inventory.FileCount
        PackageEntries=$entryCount
        ExpectedPesterTests=$ExpectedTests
        ExpectedTestContainers=$ExpectedContainers
        ExactContentsVerified=$true
        ProductionReady=$false
    }
}

function New-OPA264GReleaseDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Package,
        [Parameter(Mandatory=$true)][object]$Release,
        [AllowNull()][object]$UserReportedCI=$null
    )
    if ($null -eq $Package -or [string]$Package.Schema -cne '2.6.4-G.Package.1' -or
        $Package.ExactContentsVerified -isnot [bool] -or
        -not [bool]$Package.ExactContentsVerified -or
        [bool]$Package.ProductionReady) {
        throw 'G readiness requires a validated, nonproduction package.'
    }
    if ($null -eq $Release -or [string]$Release.Build -cne '2.6.3-PREVIEW1' -or
        [string]$Release.ApplicationVersion -cne '0.9.4-rc1-build2.6.3-PREVIEW1' -or
        [bool]$Release.Integration.ArchiveWorkerEnabled -or
        [bool]$Release.Integration.ResumeWorkerEnabled -or
        [bool]$Release.Integration.AutoWorkerEnabled -or
        [bool]$Release.Verification.RealMailMoveViaWorker -or
        [int]$Release.Verification.ExpectedPesterTests -ne [int]$Package.ExpectedPesterTests -or
        [int]$Release.Verification.ExpectedTestContainers -ne [int]$Package.ExpectedTestContainers) {
        throw 'G release metadata violates development-only, disabled-worker gate.'
    }
    $ci='NotSubmitted'
    if ($null -ne $UserReportedCI) {
        if ([string]$UserReportedCI.SourceCommit -cne [string]$Package.SourceCommit -or
            [int]$UserReportedCI.Passed -ne [int]$Package.ExpectedPesterTests -or
            [int]$UserReportedCI.Containers -ne [int]$Package.ExpectedTestContainers -or
            [int]$UserReportedCI.Failed -ne 0 -or
            [int]$UserReportedCI.Skipped -ne 0) {
            throw 'G claimed CI counts or source commit mismatch.'
        }
        $ci='UserReportedNotCryptographicallyAttested'
    }
    return [pscustomobject]@{
        Schema='2.6.4-G.Readiness.1'
        SourceCommit=[string]$Package.SourceCommit
        ZipSHA256=[string]$Package.ZipSHA256
        SourceInventorySHA256=[string]$Package.SourceInventorySHA256
        PackageIntegrity='ExactContentMatch'
        CiEvidence=$ci
        NativeCiIndependentlyAttested=$false
        RealOutlookCrashTests='NotVerified'
        VersionAlignedTo264=$false
        ReleaseAllowed=$false
        ProductionReady=$false
        ArchiveWorkerEnabled=$false
        ResumeWorkerEnabled=$false
        AutoWorkerEnabled=$false
        ManualReviewRequired=$true
        Readiness='BlockedPendingRealOutlookTestsAndVersionBump'
        Disposition='KeepDraftAndPreserveEvidence'
    }
}
