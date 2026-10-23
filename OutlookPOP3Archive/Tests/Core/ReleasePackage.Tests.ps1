#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Runtime/ReleasePackage.ps1')
    function New-OPATestReleaseTree {
        param([Parameter(Mandatory=$true)][string]$Root)
        foreach ($d in @('Core/Archive','Tests/Core','docs','OutlookPOP3Archive-Transactions')) {
            [void][IO.Directory]::CreateDirectory((Join-Path $Root $d))
        }
        foreach ($name in @(
            '.gitignore', '.psscriptanalyzer.psd1', 'CHANGELOG.md', 'README.md',
            'MANIFEST.txt', 'RELEASE.json', 'OutlookPOP3Archive.ps1',
            'OutlookPOP3Archive.Worker.ps1', 'Invoke-CI.ps1',
            'Invoke-OPAWorkerSelfTest.ps1', 'New-OPABuildPackage.ps1',
            'Core/Archive/MailMover.ps1', 'Tests/Core/Version.Tests.ps1',
            'docs/2.6.2-operation-journal.md'
        )) {
            [IO.File]::WriteAllText((Join-Path $Root $name),'fixture')
        }
    }
}

Describe 'Release ZIP hygiene and allowlist' {
    BeforeEach {
        $script:project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-OPATestReleaseTree -Root $script:project
    }
    It 'includes only project sources and tests, including dotfiles' {
        $all = @(Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1')
        $all.Count | Should -Be 14
        @($all | Where-Object { $_.RelativePath -eq '.gitignore' }).Count | Should -Be 1
        @($all | Where-Object { $_.RelativePath -eq '.psscriptanalyzer.psd1' }).Count | Should -Be 1
    }
    It 'never includes PST or runtime transactions from the source' {
        [IO.File]::WriteAllText((Join-Path $script:project 'OutlookPOP3Archive-Transactions/resume.steps.jsonl'), 'private checkpoint')
        [IO.File]::WriteAllText((Join-Path $script:project 'OutlookPOP3Archive-Transactions/live.pst'), 'private PST')
        [IO.File]::WriteAllText((Join-Path $script:project 'private.pst'), 'private PST')
        $all = @(Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1')
        $all.Count | Should -Be 14
        @($all | Where-Object { $_.RelativePath -match '\.pst$|\.jsonl$' }).Count | Should -Be 0
    }
    It 'rejects a document for a different major/minor build' {
        { Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.1-PREVIEW1a' } |
            Should -Throw '*Versioned document*'
    }
    It 'rejects non-source artifacts accidentally committed under Core' {
        [IO.File]::WriteAllText((Join-Path $script:project 'Core/Archive/old.zip'),'garbage')
        { Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1' } |
            Should -Throw '*Unexpected file*'
    }
    It 'rejects an unexpected script under Tests' {
        [IO.File]::WriteAllText((Join-Path $script:project 'Tests/Core/debug.ps1'),'debug')
        { Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1' } |
            Should -Throw '*Non-Pester script*'
    }
    It 'rejects stale root manifests without deleting them' {
        $old = Join-Path $script:project 'MANIFEST-RC1.txt'
        [IO.File]::WriteAllText($old,'old manifest')
        { Assert-OPAReleaseSourceHygiene -ProjectRoot $script:project } | Should -Throw '*MANIFEST-RC1.txt*'
        Test-Path -LiteralPath $old | Should -BeTrue
    }
    It 'rejects a missing required source file' {
        Remove-Item -LiteralPath (Join-Path $script:project 'RELEASE.json') -Force
        { Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1' } |
            Should -Throw '*Mandatory release source file is missing*'
    }

    It 'calculates a deterministic inventory hash independent of file iteration order' {
        $inventory = @(Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1')
        $expected = Get-OPAReleaseSourceInventorySha256 -Files $inventory
        $reversed = @($inventory | Sort-Object RelativePath -Descending)
        Get-OPAReleaseSourceInventorySha256 -Files $reversed | Should -Be $expected
        $expected | Should -Match '^[a-f0-9]{64}$'
        Assert-OPAReleaseSourceInventorySha256 -Files $inventory -ExpectedSha256 $expected | Should -Be $expected
    }
    It 'refuses a changed source file even if version and file count remain unchanged' {
        $inventory = @(Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1')
        $expected = Get-OPAReleaseSourceInventorySha256 -Files $inventory
        [IO.File]::AppendAllText((Join-Path $script:project 'Core/Archive/MailMover.ps1'),'modified')
        { Assert-OPAReleaseSourceInventorySha256 -Files $inventory -ExpectedSha256 $expected } |
            Should -Throw '*Source inventory SHA-256 mismatch*'
    }
    It 'refuses an extra test file missing from the pinned source manifest' {
        $inventory = @(Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1')
        $expected = Get-OPAReleaseSourceInventorySha256 -Files $inventory
        [IO.File]::WriteAllText((Join-Path $script:project 'Tests/Core/Extra.Tests.ps1'),'test')
        $updated = @(Get-OPAReleasePackageFiles -ProjectRoot $script:project -ExpectedBuild '2.6.2-PREVIEW1')
        { Assert-OPAReleaseSourceInventorySha256 -Files $updated -ExpectedSha256 $expected } |
            Should -Throw '*Source inventory SHA-256 mismatch*'
    }
}
