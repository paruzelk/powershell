#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3xOriginalBatchTenFence.ps1')
    $script:run='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
}
Describe 'ARCH3x original ten fake-only provider fences and original Intent readback' {
    It 'public CLI exposes no live Move or Resume' {
        $p=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3x.ps1') -Raw -Encoding UTF8
        $p | Should -Match "ValidateSet\('Plan','ReviewPrepared','Synthetic','Inspect'\)"
        $p | Should -Not -Match "ValidateSet\('Move'"
    }
    It 'fixes the ARCH3w1 original CLI missing module path' {
        $p=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3w1.ps1') -Raw -Encoding UTF8
        $p | Should -Match 'Core/Archive/ARCH3w1SemanticPart2Intents.ps1'
        $p | Should -Not -Match 'Core/Archive/ARCH3w1TenOriginalIntents.ps1'
        Test-Path -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3w1SemanticPart2Intents.ps1') | Should -BeTrue
    }
    It 'Plan does not require Outlook or touch PST and requires original RunId' {
        $r=Invoke-OPA265ARCH3xOriginalBatchFence -Mode Plan -RunId $script:run
        $r.Expected | Should -Be 10
        $r.OriginalMailMoverRequired | Should -BeTrue
        $r.RealOutlookContacted | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
    }
    It 'Plan rejects an unknown operator RunId' {
        {Invoke-OPA265ARCH3xOriginalBatchFence -Mode Plan -RunId ([guid]::NewGuid().ToString('D'))} | Should -Throw
    }
    It 'Plan rejects untrusted hashes before reading evidence' {
        {Invoke-OPA265ARCH3xOriginalBatchFence -Mode Plan -RunId $script:run -SealSha256 ('a'*64)} | Should -Throw
    }
    It 'ReviewPrepared requires three pinned original SHA256 hashes' {
        {Invoke-OPA265ARCH3xOriginalBatchFence -Mode ReviewPrepared -RunId $script:run} | Should -Throw
    }
    It 'Synthetic WhatIf does not persist TEMP evidence' {
        $r=Invoke-OPA265ARCH3xOriginalBatchFence -Mode Synthetic -WhatIf
        $r.Status | Should -BeExactly 'SyntheticWhatIfNoWrites'
    }
    It 'ten fake claims and original MailMover invocations yield ten durable returns' {
        $r=Invoke-OPA265ARCH3xSyntheticTen
        try{
            $r.Claims | Should -Be 10
            $r.ProviderInvocations | Should -Be 10
            $r.Returned | Should -Be 10
            $r.OriginalMailMoverSyntheticProviderUsed | Should -BeTrue
            (Get-OPA265ARCH3xSyntheticStatus -Workspace $r.Workspace).Returned | Should -Be 10
        }finally{[IO.Directory]::Delete([string]$r.Workspace,$true)}
    }
    It 'AfterClaim leaves original durable claim without any provider replay' {
        $r=Invoke-OPA265ARCH3xSyntheticTen -Fault AfterClaim -FaultAt 4
        try{
            $r.Claims | Should -Be 4
            $r.ProviderInvocations | Should -Be 3
            $r.Returned | Should -Be 3
            $r.AutomaticMoveRetryAllowed | Should -BeFalse
        }finally{[IO.Directory]::Delete([string]$r.Workspace,$true)}
    }
    It 'AfterInvocation stops before fake Move without false receipt' {
        $r=Invoke-OPA265ARCH3xSyntheticTen -Fault AfterInvocation -FaultAt 4
        try{
            $r.Claims | Should -Be 4
            $r.ProviderInvocations | Should -Be 4
            $r.Returned | Should -Be 3
        }finally{[IO.Directory]::Delete([string]$r.Workspace,$true)}
    }
    It 'fake provider exception remains unresolved and cannot replay' {
        $r=Invoke-OPA265ARCH3xSyntheticTen -Fault ProviderThrows -FaultAt 4
        try{
            $r.Claims | Should -Be 4
            $r.ProviderInvocations | Should -Be 4
            $r.Returned | Should -Be 3
            $r.StopReason | Should -Match 'fake Outlook provider exception'
        }finally{[IO.Directory]::Delete([string]$r.Workspace,$true)}
    }
    It 'AfterMoveReturned persists invocation but never a false completed receipt' {
        $r=Invoke-OPA265ARCH3xSyntheticTen -Fault AfterMoveReturned -FaultAt 4
        try{
            $r.Claims | Should -Be 4
            $r.ProviderInvocations | Should -Be 4
            $r.Returned | Should -Be 3
        }finally{[IO.Directory]::Delete([string]$r.Workspace,$true)}
    }
    It 'original MailMover fake-only provider rejects unmarked actual-looking mail' {
        $mail=[pscustomobject]@{Class=43;EntryID='FAKE';SyntheticOnly=$false}
        $target=[pscustomobject]@{EntryID='DEST';SyntheticOnly=$true}
        {Invoke-OPA265ARCH3xFakeOnlyOriginalProviderCall -Mail $mail -Folder $target -ClaimPath 'bad' -ExpectedClaimSha256 ('a'*64) -InvocationPath 'bad'} | Should -Throw
    }
    It 'original MailMover refuses malformed claim hash before file write' {
        $mail=[pscustomobject]@{Class=43;EntryID='FAKE';SyntheticOnly=$true}
        $target=[pscustomobject]@{EntryID='DEST';SyntheticOnly=$true}
        {Invoke-OPA265ARCH3xFakeOnlyOriginalProviderCall -Mail $mail -Folder $target -ClaimPath 'bad' -ExpectedClaimSha256 'bad' -InvocationPath 'bad'} | Should -Throw
    }
    It 'edited and new PowerShell code has UTF8 BOM and no production writer unlock' {
        foreach($p in @('Invoke-ARCH3x.ps1','Invoke-ARCH3w1.ps1','Core/Archive/ARCH3xOriginalBatchTenFence.ps1','Core/Archive/MailMover.ps1','Tests/Archive/ARCH3xOriginalBatchTenFence.Tests.ps1')){
            $b=[IO.File]::ReadAllBytes((Join-Path $script:root $p))
            (@($b[0],$b[1],$b[2]) -join ',') | Should -BeExactly '239,187,191'
        }
        $core=[IO.File]::ReadAllText((Join-Path $script:root 'Core/Archive/ARCH3xOriginalBatchTenFence.ps1'))
        $core | Should -Not -Match '\.AddStoreEx\s*\('
        $core | Should -Not -Match 'Add-OPADuplicateEntry\s'
    }
}
