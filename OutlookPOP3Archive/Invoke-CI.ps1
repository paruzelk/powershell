[CmdletBinding()]
param(
    # Packaging passes its intended build here; a 2.6.2 package built from
    # an unbumped 2.6.1 Core/Version.ps1 must fail before ZIP creation.
    [string]$ExpectedBuild = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# TZ-ENC-001: enforce raw UTF-8 BOM before loading arbitrary PowerShell source,
# running Pester or creating any package. Legacy BOM-less files are valid only
# while their entire pre-requirement byte snapshot remains unchanged.
. (Join-Path $root 'Core/Runtime/PowerShellEncodingPolicy.ps1')
[void](Assert-OPAPowerShellEncodingPolicy -ProjectRoot $root)
Write-Host 'PASS TZ-ENC-001: UTF-8 BOM for all new/modified PowerShell code.'

Write-Host '== Build version and package hygiene =='
$versionScript = Join-Path $root 'Core/Version.ps1'
if (-not (Test-Path -LiteralPath $versionScript -PathType Leaf)) { throw 'Missing Core/Version.ps1.' }
. $versionScript
$applicationVersion = [string]$script:OPAApplicationVersion
$versionMatch = [regex]::Match($applicationVersion, '^\d+\.\d+\.\d+-rc\d+-build(?<build>\d+\.\d+\.\d+(?:-[A-Za-z0-9]+)*)$')
if (-not $versionMatch.Success) { throw "Invalid application version: $applicationVersion" }
$build = [string]$versionMatch.Groups['build'].Value
if (-not [string]::IsNullOrWhiteSpace($ExpectedBuild) -and $ExpectedBuild -cne $build) {
    throw ("Expected build '{0}', but Core/Version.ps1 declares '{1}'." -f $ExpectedBuild,$build)
}
$manifestPath = Join-Path $root 'MANIFEST.txt'
$releasePath = Join-Path $root 'RELEASE.json'
$readmePath = Join-Path $root 'README.md'
foreach ($path in @($manifestPath,$releasePath,$readmePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release metadata missing: $path" }
}
# Dedicated manifest validator is also tested against malformed synthetic
# manifests; do not construct comma-separated concatenations inside @(...).
. (Join-Path $root 'Core/Runtime/BuildMetadata.ps1')
Assert-OPABuildManifest -Path $manifestPath -Build $build `
    -ApplicationVersion $applicationVersion `
    -TransactionSchemaVersion ([string]$script:OPATransactionSchemaVersion) `
    -DuplicateIndexSchemaVersion ([string]$script:OPADuplicateIndexSchemaVersion) | Out-Null
$release = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $releasePath -Raw) -ErrorAction Stop
$readme = Get-Content -LiteralPath $readmePath -Raw
if ([string]$release.Build -cne $build -or
    [string]$release.ApplicationVersion -cne $applicationVersion -or
    [string]$release.TransactionSchemaVersion -cne [string]$script:OPATransactionSchemaVersion -or
    [string]$release.DuplicateIndexSchemaVersion -cne [string]$script:OPADuplicateIndexSchemaVersion) {
    throw 'RELEASE.json disagrees with Core/Version.ps1 or MANIFEST.txt.'
}
if (-not $readme.Contains($applicationVersion)) { throw 'README.md does not describe the current application version.' }
if (-not $readme.Contains($build)) { throw 'README.md is missing the current build identifier.' }
# Active operational documentation must not retain an old release banner.
# CHANGELOG.md is intentionally exempt: historical versions belong there.
foreach ($docName in @('ARCHITECTURE.md','CONFIGURATION.md','RECOVERY.md','TESTING.md')) {
    $docPath = Join-Path (Join-Path $root 'docs') $docName
    if (-not (Test-Path -LiteralPath $docPath -PathType Leaf)) {
        throw "Current release documentation missing: $docName"
    }
    $firstLine = [string](Get-Content -LiteralPath $docPath -Encoding UTF8 -TotalCount 1)
    if (-not $firstLine.Contains($build)) {
        throw ("Stale release header in docs/{0}. Expected {1}." -f $docName,$build)
    }
}
# Historical runbooks are kept in prior release archives; ship only current docs.
$obsolete = @(Get-ChildItem -LiteralPath $root -File | Where-Object {
    $_.Name -match '^(?:TEST-FIX.*\.md|TEST-2\.6\.0\.md|BUILD-2\.5\.7\.txt|BUILD-2\.6\.0\.txt|MANIFEST-RC1\.txt|RELEASE-RC1\.json)$' -or
    $_.Extension -in @('.zip','.bak','.old','.tmp')
})
if ($obsolete.Count -gt 0) { throw ('Obsolete package files detected: ' + (($obsolete | ForEach-Object { $_.Name }) -join ', ')) }
# No Pester test may pin the old 0.9.x pattern, or embed a stale build tag.
$testFiles = @(Get-ChildItem -Path (Join-Path $root 'Tests') -Recurse -File -Filter '*.Tests.ps1')
if ($release.Verification.PSObject.Properties.Name -contains 'ExpectedTestContainers' -and
    $testFiles.Count -ne [int]$release.Verification.ExpectedTestContainers) {
    throw ("Test inventory incomplete: expected {0} test files, found {1}." -f
        [int]$release.Verification.ExpectedTestContainers,$testFiles.Count)
}
$tagPattern = '\d+\.\d+\.\d+-rc\d+-build\d+\.\d+\.\d+(?:-[A-Za-z0-9]+)*'
foreach ($testFile in $testFiles) {
    # Fail early on syntax/discovery errors in tests. Pester's FailedCount
    # does not include a test file rejected before discovery.
    $testTokens = $null
    $testParseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        [string]$testFile.FullName,[ref]$testTokens,[ref]$testParseErrors)
    if ($null -ne $testParseErrors -and $testParseErrors.Count -gt 0) {
        $first = $testParseErrors[0]
        throw ("Test source syntax failure: {0}:{1}: {2}" -f
            [string]$testFile.FullName,[int]$first.Extent.StartLineNumber,[string]$first.Message)
    }
    $testContent = Get-Content -LiteralPath $testFile.FullName -Raw
    if ($testContent.Contains('^0\.9\.')) {
        throw ("Obsolete hardcoded application-version regex in test: {0}" -f $testFile.FullName)
    }
    foreach ($tag in [regex]::Matches($testContent, $tagPattern)) {
        if ([string]$tag.Value -cne $applicationVersion) {
            throw ("Stale application build tag '{0}' in test {1}" -f $tag.Value,$testFile.FullName)
        }
    }
}
Write-Host 'PASS'

Write-Host '== PS5.1 ConvertTo-Json rule =='
$production = @(Get-ChildItem -Path $root -Recurse -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch '[\\/]Tests[\\/]' })
$badJson = @()
foreach ($file in $production) {
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        foreach ($e in @($parseErrors)) {
            $badJson += ('{0}:{1}: PowerShell parse error: {2}' -f $file.FullName,$e.Extent.StartLineNumber,$e.Message)
        }
        continue
    }
    $pipelines = $ast.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
        $els=@($node.PipelineElements); if ($els.Count -lt 2) { return $false }
        $last=$els[$els.Count-1]
        if ($last -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
        try { return ($last.GetCommandName() -eq 'ConvertTo-Json') } catch { return $false }
    },$true)
    foreach ($pipeline in $pipelines) {
        $cmd=$pipeline.PipelineElements[$pipeline.PipelineElements.Count-1]
        $hasInputObject=$false
        foreach ($el in @($cmd.CommandElements)) {
            if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -eq 'InputObject') { $hasInputObject=$true; break }
        }
        if (-not $hasInputObject) { $badJson += ('{0}:{1}: pipeline ConvertTo-Json without -InputObject' -f $file.FullName,$pipeline.Extent.StartLineNumber) }
    }
}
if ($badJson.Count -gt 0) {
    $summary = "PS 5.1 JSON compatibility gate failed: {0} finding(s).`n{1}" -f $badJson.Count, ($badJson -join "`n")
    throw $summary
}
Write-Host 'PASS'

Write-Host '== PS5.1 generic List safety =='
$genericListUnsafe = @()

foreach ($file in $production) {
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { continue }

    # PowerShell has function-scoped variables. Scanning the file as one
    # namespace (the previous regex-based gate) mixed unrelated scopes and
    # produced false positives whenever a name like $list was a generic
    # collection in one function and a plain array in another.
    # Scan each function body and the script top level as separate scopes.
    # Nested function bodies are masked out of the enclosing scope so their
    # declarations do not leak upward.
    $scopeAsts = New-Object System.Collections.Generic.List[object]
    foreach ($fn in @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true))) {
        $scopeAsts.Add($fn.Body) | Out-Null
    }
    if ($null -ne $ast.EndBlock) { $scopeAsts.Add($ast.EndBlock) | Out-Null }

    foreach ($scopeAst in $scopeAsts) {
        $scopeText = [string]$scopeAst.Extent.Text
        if ([string]::IsNullOrWhiteSpace($scopeText)) { continue }

        # Mask nested function bodies: replace every non-newline character
        # inside them with a space. Length and line count are preserved, so
        # downstream offset arithmetic stays valid.
        foreach ($nf in @($scopeAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true))) {
            $s = $nf.Extent.StartOffset - $scopeAst.Extent.StartOffset
            $len = $nf.Extent.EndOffset - $nf.Extent.StartOffset
            if ($s -lt 0 -or $len -le 0 -or ($s + $len) -gt $scopeText.Length) { continue }
            $slice = $scopeText.Substring($s, $len)
            $masked = [regex]::Replace($slice, '[^\r\n]', ' ')
            $scopeText = $scopeText.Substring(0, $s) + $masked + $scopeText.Substring($s + $len)
        }

        # Strip full-line comments (content only, keep the newline). Line
        # counts are preserved; inline code before a '#' is untouched.
        $scanText = [regex]::Replace($scopeText, '(?m)^\s*#[^\r\n]*', '')

        $genericVars = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase)
        # NOTE: HashSet<T> is deliberately excluded. @() on a HashSet<string>
# is safe because its elements are always homogeneous strings;
# the PS 5.1 enumerable-binder bug only fires on mixed-type
# collections such as List[object] populated from ConvertFrom-Json.
$declPatterns = @(
            '\$(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*New-Object\s+[''"]?System\.Collections\.Generic\.(?:List|Queue)\[[^\]]+\]?',
            '\$(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*\[System\.Collections\.Generic\.(?:List|Queue)\[[^\]]+\]\]::new'
        )
        foreach ($pattern in $declPatterns) {
            foreach ($m in [regex]::Matches($scanText, $pattern,
                        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                [void]$genericVars.Add($m.Groups['name'].Value)
            }
        }
        if ($genericVars.Count -eq 0) { continue }

        foreach ($m in [regex]::Matches($scanText, '@\(\$(?<name>[A-Za-z_][A-Za-z0-9_]*)\)',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $name = $m.Groups['name'].Value
            if (-not $genericVars.Contains($name)) { continue }

            $linesIntoScope = (($scanText.Substring(0, $m.Index)) -split "`n").Count - 1
            $line = $scopeAst.Extent.StartLineNumber + $linesIntoScope
            $genericListUnsafe += ('{0}:{1}: direct @(${2}) on generic collection; review explicit enumeration for PS5.1 compatibility.' -f $file.FullName, $line, $name)
        }
    }
}

if ($genericListUnsafe.Count -gt 0) {
    $summary = "PS5.1 generic collection safety gate failed: {0} finding(s).`n{1}" -f $genericListUnsafe.Count, ($genericListUnsafe -join "`n")
    throw $summary
}
Write-Host 'PASS'

if (-not (Test-Path -LiteralPath (Join-Path $root '.psscriptanalyzer.psd1'))) { throw 'PSScriptAnalyzer settings file is missing.' }

Write-Host '== PSScriptAnalyzer =='
if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    Import-Module PSScriptAnalyzer -Force
    # Windows PowerShell 5.1 can bind the member-enumerated 
    # $production.FullName as System.Object[] while this PSScriptAnalyzer
    # version expects a scalar String. Analyze each production script
    # separately and aggregate the findings.
    $settingsPath = Join-Path $root '.psscriptanalyzer.psd1'
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($file in $production) {
        try {
            $fileFindings = @(Invoke-ScriptAnalyzer -Path ([string]$file.FullName) -Settings $settingsPath -ErrorAction Stop)
        }
        catch {
            throw ("PSScriptAnalyzer failed for '{0}': {1}" -f [string]$file.FullName, $_.Exception.Message)
        }
        foreach ($finding in $fileFindings) { [void]$findings.Add($finding) }
    }
    $findingsArray = $findings.ToArray()
    if ($findingsArray.Count -gt 0) { $findingsArray | Format-Table -AutoSize }
    if ($findings.Count -gt 0) { throw "PSScriptAnalyzer reported $($findings.Count) finding(s)." }
} else {
    throw 'PSScriptAnalyzer is required for CI/release and is not installed.'
}

Write-Host '== Pester =='
if (-not (Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -ge [version]'5.0' })) {
    throw 'Pester 5.0 or newer is required for CI/release and is not installed.'
}
Import-Module Pester -MinimumVersion 5.0 -Force -ErrorAction Stop
# -CI causes Pester to exit the host process on test failure. Use PassThru
# instead so callers receive an explicit, inspectable exception and tests
# cannot silently succeed just because the console printed failures.
$pesterResult = Invoke-Pester -Path (Join-Path $root 'Tests') -PassThru
if ($null -eq $pesterResult) { throw 'Pester returned no result; release denied.' }
. (Join-Path $root 'Core/Runtime/PesterReleaseGate.ps1')
# Count every discovered test file, including files that fail to parse.
# A discovery error creates a failed container but can leave FailedCount=0.
$gate = Assert-OPAPesterReleaseGate -Result $pesterResult -ExpectedContainerCount $testFiles.Count
if ($release.Verification.PSObject.Properties.Name -contains 'ExpectedPesterTests' -and
    $gate.PassedCount -ne [int]$release.Verification.ExpectedPesterTests) {
    throw ("Pester test count incomplete: expected {0}, passed {1}." -f
        [int]$release.Verification.ExpectedPesterTests,$gate.PassedCount)
}
Write-Host ("PASS Pester: {0} tests in {1} containers, 0 failed, 0 skipped, 0 failed containers." -f
    $gate.PassedCount,$gate.ContainerCount)
Write-Host 'CI PASSED — release prerequisites satisfied.'
