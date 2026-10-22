BeforeAll {
    . "$PSScriptRoot/../../Core/Version.ps1"
}

Describe 'Version constants' {
    It 'transaction schema version is in the supported list' {
        $script:OPATransactionSchemaSupported | Should -Contain $script:OPATransactionSchemaVersion
    }
    It 'duplicate index schema version is supported' {
        $script:OPADuplicateIndexSchemasSupported | Should -Contain $script:OPADuplicateIndexSchemaVersion
    }
    It 'application version matches the expected build tag' {
        $script:OPAApplicationVersion | Should -Match '^0\.9\.3-rc\d+-build\d+\.\d+\.\d+'
    }
    It 'supported schema list is sorted and deduplicated' {
        $sorted = @($script:OPATransactionSchemaSupported | Sort-Object -Unique)
        @($script:OPATransactionSchemaSupported) | Should -Be $sorted
    }
}
