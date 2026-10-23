#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Runtime/ReleaseReadiness264.ps1')
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    function Add-OPAGZipEntry {
        param([object]$Archive,[string]$Name,[byte[]]$Data)
        $entry=$Archive.CreateEntry($Name)
        $stream=$null
        try {
            $stream=$entry.Open()
            $stream.Write($Data,0,$Data.Length)
        }
        finally { if ($null -ne $stream) { $stream.Dispose() } }
    }
    function New-OPAGTestZip {
        param([string]$WrongRoot='', [string]$Extra='', [string]$Omit='')
        if ([IO.File]::Exists($script:zipPath)) { [IO.File]::Delete($script:zipPath) }
        $root=$script:stem
        if ($WrongRoot) { $root=$WrongRoot }
        $archive=$null
        try {
            $archive=[IO.Compression.ZipFile]::Open($script:zipPath,[IO.Compression.ZipArchiveMode]::Create)
            $inv=Get-OPA264GSourceInventory -SourceRoot $script:srcRoot
            foreach ($file in $inv.Files) {
                if ([string]$file.RelativePath -ceq $Omit) { continue }
                Add-OPAGZipEntry -Archive $archive -Name ($root+'/'+$file.RelativePath) -Data ([IO.File]::ReadAllBytes($file.FilePath))
            }
            if ($Extra) {
                Add-OPAGZipEntry -Archive $archive -Name ($root+'/'+$Extra) -Data ([Text.Encoding]::UTF8.GetBytes('extra'))
            }
            $json=ConvertTo-Json -InputObject $script:meta -Depth 6
            Add-OPAGZipEntry -Archive $archive -Name ($root+'/BUILD-INFO.json') -Data ((New-Object Text.UTF8Encoding($false)).GetBytes($json))
        }
        finally { if ($null -ne $archive) { $archive.Dispose() } }
        $script:zipSha=([string](Get-FileHash -LiteralPath $script:zipPath -Algorithm SHA256).Hash).ToLowerInvariant()
    }
    function Test-OPAGPackage {
        Assert-OPA264GDevPackage -SourceRoot $script:srcRoot -ZipPath $script:zipPath -ExpectedSourceCommit $script:commit -ExpectedZipSHA256 $script:zipSha -ExpectedTests 464 -ExpectedContainers 34
    }
}
Describe '2.6.4-G release integrity audit on synthetic files (no Outlook)' {
    BeforeEach {
        $script:srcRoot=Join-Path $TestDrive ('src-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:srcRoot)
        [void][IO.Directory]::CreateDirectory((Join-Path $script:srcRoot 'nested'))
        [IO.File]::WriteAllText((Join-Path $script:srcRoot 'a.txt'),'Alpha')
        [IO.File]::WriteAllText((Join-Path $script:srcRoot 'nested/b.txt'),'Beta')
        [IO.File]::WriteAllText((Join-Path $script:srcRoot 'BUILD-INFO.json'),'ignored')
        $script:commit='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $script:stem='OutlookPOP3Archive-2.6.4-G-dev-gaaaaaaaa'
        $script:zipPath=Join-Path $TestDrive ($script:stem+'.zip')
        $inv=Get-OPA264GSourceInventory -SourceRoot $script:srcRoot
        $script:meta=[pscustomobject]@{
            Kind='DEVELOPMENT_SNAPSHOT_NOT_RELEASE'
            Stage='2.6.4-G'
            SourceCommit=$script:commit
            SourceInventorySHA256=$inv.InventorySHA256
            SourceFileCount=2
            ExpectedPesterTests=464
            ExpectedTestContainers=34
            WindowsCI='PENDING'
            RealOutlookTest='NOT_RUN'
            PackageRoot=$script:stem
            ArchiveWorkerEnabled=$false
            ResumeWorkerEnabled=$false
            AutoWorkerEnabled=$false
        }
        $script:release=[pscustomobject]@{
            Build='2.6.3-PREVIEW1'
            ApplicationVersion='0.9.4-rc1-build2.6.3-PREVIEW1'
            Integration=[pscustomobject]@{
                ArchiveWorkerEnabled=$false
                ResumeWorkerEnabled=$false
                AutoWorkerEnabled=$false
            }
            Verification=[pscustomobject]@{
                RealMailMoveViaWorker=$false
                ExpectedPesterTests=464
                ExpectedTestContainers=34
            }
        }
        New-OPAGTestZip
    }
    It 'computes a canonical ordered source inventory without BUILD-INFO.json' {
        $i=Get-OPA264GSourceInventory -SourceRoot $script:srcRoot
        $i.FileCount | Should -Be 2
        (@($i.Files | ForEach-Object { $_.RelativePath }) -join ',') | Should -Be 'a.txt,nested/b.txt'
    }
    It 'recomputes stable inventory SHA256' {
        $a=Get-OPA264GSourceInventory -SourceRoot $script:srcRoot
        $b=Get-OPA264GSourceInventory -SourceRoot $script:srcRoot
        $a.InventorySHA256 | Should -Be $b.InventorySHA256
    }
    It 'fails on nonexistent root' {
        { Get-OPA264GSourceInventory -SourceRoot (Join-Path $TestDrive 'notfound') } | Should -Throw '*missing*'
    }
    It 'verifies exact ZIP bytes and single root' {
        $p=Test-OPAGPackage
        $p.ExactContentsVerified | Should -BeTrue
        $p.PackageEntries | Should -Be 3
        $p.ProductionReady | Should -BeFalse
    }
    It 'rejects incorrect external ZIP SHA256' {
        { Assert-OPA264GDevPackage -SourceRoot $script:srcRoot -ZipPath $script:zipPath -ExpectedSourceCommit $script:commit -ExpectedZipSHA256 ('b'*64) -ExpectedTests 464 -ExpectedContainers 34 } | Should -Throw '*SHA256 mismatch*'
    }
    It 'rejects incorrect externally pinned commit prefix' {
        { Assert-OPA264GDevPackage -SourceRoot $script:srcRoot -ZipPath $script:zipPath -ExpectedSourceCommit ('c'*40) -ExpectedZipSHA256 $script:zipSha -ExpectedTests 464 -ExpectedContainers 34 } | Should -Throw '*basename*'
    }
    It 'rejects an invalid external commit format' {
        { Assert-OPA264GDevPackage -SourceRoot $script:srcRoot -ZipPath $script:zipPath -ExpectedSourceCommit 'bad' -ExpectedZipSHA256 $script:zipSha -ExpectedTests 464 -ExpectedContainers 34 } | Should -Throw '*pinned*'
    }
    It 'rejects an alien ZIP root' {
        New-OPAGTestZip -WrongRoot 'OtherProject'
        { Test-OPAGPackage } | Should -Throw '*root folder*'
    }
    It 'rejects a missing source file inside ZIP' {
        New-OPAGTestZip -Omit 'nested/b.txt'
        { Test-OPAGPackage } | Should -Throw '*file count*'
    }
    It 'rejects extra project files inside ZIP' {
        New-OPAGTestZip -Extra 'unexpected.txt'
        { Test-OPAGPackage } | Should -Throw '*file count*'
    }
    It 'rejects path traversal attempts in ZIP' {
        New-OPAGTestZip -Extra '../unexpected.txt'
        { Test-OPAGPackage } | Should -Throw
    }
    It 'detects a changed source after packaging' {
        [IO.File]::AppendAllText((Join-Path $script:srcRoot 'a.txt'),'tampered')
        { Test-OPAGPackage } | Should -Throw '*differs from checked-out source*'
    }
    It 'rejects embedded source SHA mismatch' {
        $script:meta.SourceCommit=('b'*40)
        New-OPAGTestZip
        { Test-OPAGPackage } | Should -Throw '*BUILD-INFO*'
    }
    It 'rejects embedded source inventory mismatch' {
        $script:meta.SourceInventorySHA256=('0'*64)
        New-OPAGTestZip
        { Test-OPAGPackage } | Should -Throw '*BUILD-INFO*'
    }
    It 'rejects incorrect embedded Pester test count' {
        $script:meta.ExpectedPesterTests=999
        New-OPAGTestZip
        { Test-OPAGPackage } | Should -Throw '*BUILD-INFO*'
    }
    It 'refuses optimistic Windows CI claim inside a new DEV package' {
        $script:meta.WindowsCI='PASSED'
        New-OPAGTestZip
        { Test-OPAGPackage } | Should -Throw '*BUILD-INFO*'
    }
    It 'refuses positive Worker integration flags' {
        $script:meta.ArchiveWorkerEnabled=$true
        New-OPAGTestZip
        { Test-OPAGPackage } | Should -Throw '*ArchiveWorkerEnabled*'
    }
    It 'does not promote a valid package to production release' {
        $r=New-OPA264GReleaseDecision -Package (Test-OPAGPackage) -Release $script:release
        $r.ReleaseAllowed | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $r.Readiness | Should -Be 'BlockedPendingRealOutlookTestsAndVersionBump'
    }
    It 'rejects release metadata activating Archive Worker' {
        $script:release.Integration.ArchiveWorkerEnabled=$true
        { New-OPA264GReleaseDecision -Package (Test-OPAGPackage) -Release $script:release } | Should -Throw '*metadata*'
    }
    It 'rejects claimed CI without exact commit and zero skips' {
        $ci=[pscustomobject]@{
            SourceCommit=('b'*40)
            Passed=464
            Containers=34
            Failed=0
            Skipped=0
        }
        { New-OPA264GReleaseDecision -Package (Test-OPAGPackage) -Release $script:release -UserReportedCI $ci } | Should -Throw '*CI counts*'
    }
    It 'labels even matching user-reported CI as not independently attested' {
        $ci=[pscustomobject]@{
            SourceCommit=$script:commit
            Passed=464
            Containers=34
            Failed=0
            Skipped=0
        }
        $r=New-OPA264GReleaseDecision -Package (Test-OPAGPackage) -Release $script:release -UserReportedCI $ci
        $r.CiEvidence | Should -Be 'UserReportedNotCryptographicallyAttested'
        $r.NativeCiIndependentlyAttested | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'keeps audit CLI free of any PST, Outlook or process mutations' {
        $file=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA264GPackageReview.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $methods=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]},$true))
        @($methods | Where-Object { [string]$_.Member.Value -in @('Move','Copy','Delete','Kill','AddStore','AddStoreEx','RemoveStore','Quit','WriteAllText') }).Count | Should -Be 0
    }
}
