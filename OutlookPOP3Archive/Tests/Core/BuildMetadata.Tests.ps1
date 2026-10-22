BeforeAll {
    . "$PSScriptRoot/../../Core/Runtime/BuildMetadata.ps1"
    . "$PSScriptRoot/../../Core/Version.ps1"
    $script:app = [string]$script:OPAApplicationVersion
    $script:build = [regex]::Match($script:app, '-build(?<build>[^\s]+)$').Groups['build'].Value
    if ([string]::IsNullOrWhiteSpace($script:build)) { throw 'Unable to derive build from application version.' }
    $script:transactionSchema = [string]$script:OPATransactionSchemaVersion
    $script:duplicateSchema = [string]$script:OPADuplicateIndexSchemaVersion

    function Write-OPATestManifest {
        param([string]$Path, [string[]]$Lines)
        # PS5.1 UTF8-BOM interoperability, with explicit CRLF/LF handling.
        [IO.File]::WriteAllLines($Path, $Lines, (New-Object System.Text.UTF8Encoding($true)))
    }
    function Assert-OPATestManifest {
        param([string]$Path)
        Assert-OPABuildManifest -Path $Path -Build $script:build `
            -ApplicationVersion $script:app `
            -TransactionSchemaVersion $script:transactionSchema `
            -DuplicateIndexSchemaVersion $script:duplicateSchema
    }
}

Describe 'Manifest version guard regression (PS5.1)' {
    It 'returns four separate expected version lines in their intended order' {
        $lines = @(Get-OPARequiredManifestLines -Build $script:build -ApplicationVersion $script:app `
            -TransactionSchemaVersion $script:transactionSchema `
            -DuplicateIndexSchemaVersion $script:duplicateSchema)
        $lines.Count | Should -Be 4
        $lines[0] | Should -Be "Build: $script:build"
        $lines[1] | Should -Be "Application: $script:app"
        $lines[2] | Should -Be "Transaction schema: $script:transactionSchema"
        $lines[3] | Should -Be "DuplicateIndex schema: $script:duplicateSchema"
    }
    It 'accepts the actual four separately printed lines in the released MANIFEST' {
        $path = Join-Path $PSScriptRoot '../../MANIFEST.txt'
        Assert-OPATestManifest -Path $path | Should -BeTrue
    }
    It 'accepts a correctly formatted synthetic manifest' {
        $path = Join-Path $TestDrive 'correct-manifest.txt'
        $expected = @(Get-OPARequiredManifestLines -Build $script:build -ApplicationVersion $script:app `
            -TransactionSchemaVersion $script:transactionSchema `
            -DuplicateIndexSchemaVersion $script:duplicateSchema)
        Write-OPATestManifest -Path $path -Lines $expected
        Assert-OPATestManifest -Path $path | Should -BeTrue
    }
    It 'rejects a collapsed single line containing all metadata (original PREVIEW1 bug)' {
        $path = Join-Path $TestDrive 'combined-manifest.txt'
        $lines = @(Get-OPARequiredManifestLines -Build $script:build -ApplicationVersion $script:app `
            -TransactionSchemaVersion $script:transactionSchema `
            -DuplicateIndexSchemaVersion $script:duplicateSchema)
        Write-OPATestManifest -Path $path -Lines @([string]::Join(' ',[string[]]$lines))
        { Assert-OPATestManifest -Path $path } | Should -Throw '*Manifest version mismatch*'
    }
    It 'rejects a stale version even if the manifest contains all other correct lines' {
        $path = Join-Path $TestDrive 'stale-manifest.txt'
        $lines = @(Get-OPARequiredManifestLines -Build $script:build -ApplicationVersion $script:app `
            -TransactionSchemaVersion $script:transactionSchema `
            -DuplicateIndexSchemaVersion $script:duplicateSchema)
        $lines[1] = 'Application: WRONG'
        Write-OPATestManifest -Path $path -Lines $lines
        { Assert-OPATestManifest -Path $path } | Should -Throw '*Manifest version mismatch*'
    }
    It 'rejects duplicate matching version lines' {
        $path = Join-Path $TestDrive 'duplicate-manifest.txt'
        $lines = @(Get-OPARequiredManifestLines -Build $script:build -ApplicationVersion $script:app `
            -TransactionSchemaVersion $script:transactionSchema `
            -DuplicateIndexSchemaVersion $script:duplicateSchema)
        Write-OPATestManifest -Path $path -Lines @($lines + $lines[0])
        { Assert-OPATestManifest -Path $path } | Should -Throw '*Manifest version mismatch*'
    }
    It 'rejects a missing mandatory version line' {
        $path = Join-Path $TestDrive 'missing-manifest.txt'
        $lines = @(Get-OPARequiredManifestLines -Build $script:build -ApplicationVersion $script:app `
            -TransactionSchemaVersion $script:transactionSchema `
            -DuplicateIndexSchemaVersion $script:duplicateSchema)
        Write-OPATestManifest -Path $path -Lines @($lines[0],$lines[1],$lines[2])
        { Assert-OPATestManifest -Path $path } | Should -Throw '*Manifest version mismatch*'
    }
}
