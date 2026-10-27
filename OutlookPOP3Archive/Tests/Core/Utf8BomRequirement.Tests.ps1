#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Runtime/PowerShellEncodingPolicy.ps1')
    $script:ProjectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:EmptySha='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
}
Describe 'TZ-ENC-001: every new or modified PowerShell file must be UTF-8 with BOM' {
    BeforeEach {
        $script:EncodingTestPath=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:EncodingTestPath)
    }
    It 'validates the exact pre-policy 82-file legacy snapshot for this project' {
        $e=Assert-OPAPowerShellEncodingPolicy -ProjectRoot $script:ProjectRoot
        $e.LegacyBomlessFiles | Should -Be 82
        $e.LegacyBomlessSha256 | Should -BeExactly 'ace042f4ab915f2c1bd274685ea0e041e1f94f05c82418bed5a893ae153967ca'
        $e.Utf8BomFiles | Should -BeGreaterThan 0
    }
    It 'accepts a new ASCII-only script with explicit UTF-8 BOM bytes' {
        $path=Join-Path $script:EncodingTestPath 'good.ps1'
        [IO.File]::WriteAllText($path,'Write-Output 1',[Text.UTF8Encoding]::new($true))
        $inventory=Assert-OPAPowerShellEncodingPolicy -ProjectRoot $script:EncodingTestPath -LegacyCount 0 -LegacySha256 $script:EmptySha
        $inventory.Utf8BomFiles | Should -Be 1
        $inventory.LegacyBomlessFiles | Should -Be 0
    }
    It 'rejects a newly generated UTF-8 without BOM script even when ASCII-only' {
        $path=Join-Path $script:EncodingTestPath 'bad.ps1'
        [IO.File]::WriteAllText($path,'Write-Output 1',[Text.UTF8Encoding]::new($false))
        { Assert-OPAPowerShellEncodingPolicy -ProjectRoot $script:EncodingTestPath -LegacyCount 0 -LegacySha256 $script:EmptySha } | Should -Throw '*TZ-ENC-001 FAILED*'
    }
    It 'rejects in-place modification to a previously snapshotted BOM-less script' {
        $path=Join-Path $script:EncodingTestPath 'old.ps1'
        [IO.File]::WriteAllText($path,'Write-Output 1',[Text.UTF8Encoding]::new($false))
        $known=Get-OPAPowerShellEncodingInventory -ProjectRoot $script:EncodingTestPath
        [IO.File]::WriteAllText($path,'Write-Output 2',[Text.UTF8Encoding]::new($false))
        { Assert-OPAPowerShellEncodingPolicy -ProjectRoot $script:EncodingTestPath -LegacyCount 1 -LegacySha256 $known.LegacyBomlessSha256 } | Should -Throw '*TZ-ENC-001 FAILED*'
    }
    It 'rejects invalid UTF-8 data after an otherwise correct BOM' {
        $path=Join-Path $script:EncodingTestPath 'corrupt.ps1'
        [IO.File]::WriteAllBytes($path,[byte[]]@(239,187,191,195,40))
        { Get-OPAPowerShellEncodingInventory -ProjectRoot $script:EncodingTestPath } | Should -Throw '*invalid UTF-8*'
    }
    It 'excludes JSON protocol and journal data from the source-code BOM rule' {
        [IO.File]::WriteAllText((Join-Path $script:EncodingTestPath 'request.json'),'{"ok":true}',[Text.UTF8Encoding]::new($false))
        $e=Assert-OPAPowerShellEncodingPolicy -ProjectRoot $script:EncodingTestPath -LegacyCount 0 -LegacySha256 $script:EmptySha
        $e.PowerShellFiles | Should -Be 0
    }
    It 'documents mandatory signature EF BB BF and existing legacy migration' {
        $spec=Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'docs/TECHNICAL_SPECIFICATION.md') -Encoding UTF8 -Raw
        $spec | Should -Match 'EF BB BF'
        $spec | Should -Match '82'
        $spec | Should -Match 'ТЗ-ENC-001'
    }
    It 'enforces editor UTF-8 BOM default for ps1, psm1 and psd1' {
        $config=Get-Content -LiteralPath (Join-Path $script:ProjectRoot '.editorconfig') -Raw
        $config | Should -Match 'charset\s*=\s*utf-8-bom'
        $config | Should -Match 'ps1,psm1,psd1'
    }
    It 'checks code encoding in Invoke-CI before release metadata and test discovery' {
        $ci=Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'Invoke-CI.ps1') -Raw
        $check=$ci.IndexOf('Assert-OPAPowerShellEncodingPolicy -ProjectRoot')
        $version=$ci.IndexOf("$versionScript = Join-Path $root 'Core/Version.ps1'")
        $check | Should -BeGreaterThan 0
        ($check -lt $version) | Should -BeTrue
    }
}
