#requires -Version 5.1
BeforeAll {
    $script:projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:projectRoot 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1')
    $script:originalRun='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
    $script:originalLength=[long]7735903232
    $script:observedLength=[long]7756473344
}
Describe 'ARCH3x1a original physical PST growth isolated from immutable original full semantic witnesses' {
    It 'maintains strict original ARCH3v behaviour when opt-in is absent' {
        {Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes $script:observedLength} | Should -Throw
    }
    It 'strict original equal-length history still passes unchanged' {
        $r=Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes $script:originalLength
        $r.GrowthBytes | Should -Be 0
        $r.OptInForExactOperatorRunId | Should -BeFalse
    }
    It 'accepts the observed operator 20570112-byte physical growth by narrow opt-in' {
        $r=Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes $script:observedLength -PermitHistoricalGrowth
        $r.GrowthBytes | Should -Be 20570112
        $r.HistoricalLengthBytes | Should -Be $script:originalLength
        $r.ObservedLengthBytes | Should -Be $script:observedLength
        $r.HistoricalDigestPreserved | Should -BeTrue
    }
    It 'permits exact same current size with opt-in' {
        $r=Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes $script:originalLength -PermitHistoricalGrowth
        $r.GrowthBytes | Should -Be 0
    }
    It 'rejects physical shrink even with opt-in' {
        {Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes ($script:originalLength-4096) -PermitHistoricalGrowth} | Should -Throw
    }
    It 'rejects an unrelated run ID even with opt-in' {
        {Get-OPA265ARCH3x1aSourceLengthGate -RunId ([guid]::NewGuid().ToString('D')) -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes $script:observedLength -PermitHistoricalGrowth} | Should -Throw
    }
    It 'rejects absent historical PST length' {
        {Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes 0 -ObservedLengthBytes $script:observedLength -PermitHistoricalGrowth} | Should -Throw
    }
    It 'rejects absent current PST length' {
        {Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes 0 -PermitHistoricalGrowth} | Should -Throw
    }
    It 'accepts the bounded upper growth limit of exactly 256 MiB' {
        $r=Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes ($script:originalLength+268435456) -PermitHistoricalGrowth
        $r.GrowthBytes | Should -Be 268435456
    }
    It 'rejects growth exceeding 256 MiB even for authorized test PST' {
        {Get-OPA265ARCH3x1aSourceLengthGate -RunId $script:originalRun -HistoricalLengthBytes $script:originalLength -ObservedLengthBytes ($script:originalLength+268435457) -PermitHistoricalGrowth} | Should -Throw
    }
    It 'keeps original ARCH3v public Audit/Seal switchless and defaults to strict mode' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3vRealTenFullWitness.ps1') -Raw -Encoding UTF8
        $start=$s.IndexOf('function Invoke-OPA265ARCH3vRealTenFullWitness')
        $start | Should -BeGreaterThan 0
        $public=$s.Substring($start)
        $public | Should -Not -Match 'ARCH3x1aAllowSourcePstLengthGrowth'
        $s | Should -Match 'if\(-not \$PermitHistoricalGrowth\)'
    }
    It 'reconstructs historical source size in memory only AFTER full original semantic witnessing' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3vRealTenFullWitness.ps1') -Raw -Encoding UTF8
        $start=$s.IndexOf('function Get-OPA265ARCH3vFullReadOnlyAudit')
        $end=$s.IndexOf('function Test-OPA265ARCH3vFullTenReadback')
        $body=$s.Substring($start,$end-$start)
        $witness=$body.IndexOf('Get-OPA265ARCH2bMailSemanticWitness -Mail $mail')
        $projection=$body.IndexOf('$p.SourcePstLengthBytes=[long]$physical.HistoricalLengthBytes')
        $digest=$body.IndexOf('$bundle=New-OPA265ARCH3vEnvelopeFromPreview')
        $witness | Should -BeGreaterThan 0
        $projection | Should -BeGreaterThan $witness
        $digest | Should -BeGreaterThan $projection
        $body | Should -Not -Match '(?m)^\s*Write-OPAOperationJournalEvent\s'
    }
    It 'rechecks current physical size after all original full witnesses within same audit' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3vRealTenFullWitness.ps1') -Raw -Encoding UTF8
        $s | Should -Match '\(\[IO.FileInfo\]::new\(\$source\)\)\.Length -ne \[long\]\$physical\.ObservedLengthBytes'
        $s | Should -Match 'OriginalHistoricalSourceLengthPreservedInDigest=\$true'
    }
    It 'ARCH3x1a ties Move audit to original full witness SHA and sealed ten Intent still' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Get-OPA265ARCH3x1bPinnedTenLiveAudit -Manifest'
        $s | Should -Match 'Get-OPA265ARCH3x1bPinnedTenLiveAudit -Manifest'
        $s | Should -Match '\[string\]\$full.AuditSha256 -cne \[string\]\$m.AuditSha256'
        $s | Should -Match '\$row.FullOriginalWitnessSha256 -cne \[string\]\$saved.FullOriginalWitnessSha256'
        $s | Should -Match 'Assert-OPA265ARCH3iFullWitnessPinned -Witness'
    }
    It 'observed size is signed into preflight digest and rechecked before writer entry' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match 'SourcePstLengthGrowthBytes=\[long\]\$audit.SourcePstLengthGrowthBytes'
        $s | Should -Not -Match '\[long\]\$audit.ObservedSourcePstLengthBytes'
        $s | Should -Match 'Get-OPA265ARCH3x1bPinnedTenLiveAudit -Manifest'
        $i=$s.IndexOf('$writerSha=Write-OPA265ARCH3cJsonOnce')
        $guard=$s.IndexOf('Get-OPA265ARCH3x1bPinnedTenLiveAudit -Manifest')
        $i | Should -BeGreaterThan $guard
    }
    It 'all changed PowerShell files retain UTF8 BOM; shared original journal/index writer remain closed' {
        foreach($p in @('Core/Archive/ARCH3vRealTenFullWitness.ps1','Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1','Tests/Archive/ARCH3x1aSourcePstPhysicalGrowth.Tests.ps1')){
            $bytes=[IO.File]::ReadAllBytes((Join-Path $script:projectRoot $p))
            (@($bytes[0],$bytes[1],$bytes[2]) -join ',') | Should -BeExactly '239,187,191'
        }
        $core=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $core | Should -Not -Match '(?m)^\s*Add-OPADuplicateEntry\s'
        $core | Should -Not -Match '(?m)^\s*Write-OPAOperationJournalEvent\s'
    }
}
