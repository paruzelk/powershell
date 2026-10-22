BeforeAll {
    . "$PSScriptRoot/../../Core/Version.ps1"
}

Describe 'Version constants and release metadata' {
    It 'transaction schema version is in the supported list' {
        $script:OPATransactionSchemaSupported | Should -Contain $script:OPATransactionSchemaVersion
    }
    It 'duplicate index schema version is supported' {
        $script:OPADuplicateIndexSchemasSupported | Should -Contain $script:OPADuplicateIndexSchemaVersion
    }
    It 'application version matches the expected build tag' {
        # Validate the version format without pinning it to the previous release.
        $script:OPAApplicationVersion | Should -Match '^\d+\.\d+\.\d+-rc\d+-build\d+\.\d+\.\d+(?:-[A-Za-z0-9]+)*$'
        # The manifest and product must advertise exactly the same version.
        $manifest = Get-Content -LiteralPath "$PSScriptRoot/../../MANIFEST.txt" -Raw
        $manifest | Should -Match ([regex]::Escape("Application: $script:OPAApplicationVersion"))
    }
    It 'supported schema list is sorted and deduplicated' {
        $sorted = @($script:OPATransactionSchemaSupported | Sort-Object -Unique)
        @($script:OPATransactionSchemaSupported) | Should -Be $sorted
    }

    It 'release.json uses the exact build, schema and application version' {
        $release = ConvertFrom-Json -InputObject (Get-Content -LiteralPath "$PSScriptRoot/../../RELEASE.json" -Raw)
        $script:OPAApplicationVersion | Should -Match ('-build' + [regex]::Escape([string]$release.Build) + '$')
        $release.ApplicationVersion | Should -Be $script:OPAApplicationVersion
        $release.TransactionSchemaVersion | Should -Be $script:OPATransactionSchemaVersion
        $release.DuplicateIndexSchemaVersion | Should -Be $script:OPADuplicateIndexSchemaVersion
    }
    It 'distributes only current root-level runbooks' {
        @(Get-ChildItem -LiteralPath "$PSScriptRoot/../.." -File | Where-Object {
            $_.Name -match '^TEST-FIX.*\.md$|^MANIFEST-RC1\.txt$|^RELEASE-RC1\.json$|^BUILD-2\.5\.7\.txt$'
        }).Count | Should -Be 0
    }
}
