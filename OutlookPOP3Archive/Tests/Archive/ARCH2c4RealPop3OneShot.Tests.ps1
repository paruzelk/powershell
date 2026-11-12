#requires -Version 5.1
# ARCH2c4 pure policy gates plus sealed journal simulation.
# NO Outlook started and NO existing PST touched in GitHub Actions.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2c4OneShotPolicy.ps1')
    $script:run='77777777-8888-4999-aabb-cccccccccccc'
    $script:sourcePath=Join-Path $TestDrive 'info@stios.ru.pst'
    [IO.File]::WriteAllBytes($script:sourcePath,[byte[]]@(1,2,3))
    function New-ARCH2c4Layout {
        return Get-OPA265ARCH2c4Layout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
    }
    function New-ARCH2c4Scope {
        param([object]$Layout=(New-ARCH2c4Layout),
              [object[]]$Stores=@([pscustomobject]@{StoreId='OTHER';FilePath='C:\Office\other.pst'},
                                 [pscustomobject]@{StoreId='POP3';FilePath=$script:sourcePath}),
              [object[]]$Accounts=@([pscustomobject]@{SmtpAddress='info@stios.ru';AccountType=2;DeliveryStoreId='POP3'}),
              [string]$Profile='Outlook',[string]$Default='OTHER')
        return Test-OPA265ARCH2c4Pop3StoreScope -Layout $Layout -SourcePst $script:sourcePath -CurrentProfileName $Profile -DefaultStoreId $Default -Stores $Stores -Accounts $Accounts
    }
}
Describe 'ARCH2c4 real POP3 single-Move policy: synthetic CI only' {
    It 'derives one unique new archive destination without existing BW4k7v test PSTs' {
        $l=New-ARCH2c4Layout
        $l.ArchivePst | Should -BeLike ('*OutlookPOP3Archive-ARCH2c4-RealPilot*'+$script:run+'.pst')
        $l.WriterPermit | Should -BeFalse
        $l.ProductionReady | Should -BeFalse
    }
    It 'rejects malformed RunId' {
        {Get-OPA265ARCH2c4Layout -RunId 'not-guid' -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'rejects upper-case RunId normalization' {
        {Get-OPA265ARCH2c4Layout -RunId $script:run.ToUpperInvariant() -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'accepts only exact existing local info@stios.ru.pst basename' {
        $l=New-ARCH2c4Layout
        (Assert-OPA265ARCH2c4SourcePst -SourcePst $script:sourcePath -Layout $l) | Should -BeExactly $script:sourcePath
    }
    It 'rejects arbitrary archive PST as source' {
        $l=New-ARCH2c4Layout
        $bad=Join-Path $TestDrive 'Archive-2019.pst'
        [IO.File]::WriteAllBytes($bad,[byte[]]@(7))
        {Assert-OPA265ARCH2c4SourcePst -SourcePst $bad -Layout $l} | Should -Throw
    }
    It 'rejects deleted/missing source PST' {
        $l=New-ARCH2c4Layout
        {Assert-OPA265ARCH2c4SourcePst -SourcePst (Join-Path $TestDrive 'missing/info@stios.ru.pst') -Layout $l} | Should -Throw
    }
    It 'rejects mismatched or forged archive path' {
        $l=New-ARCH2c4Layout
        $l.ArchivePst=$script:sourcePath
        {Assert-OPA265ARCH2c4Layout -Layout $l} | Should -Throw
    }
    It 'approves exactly one POP3 delivery store when different from Outlook default' {
        (New-ARCH2c4Scope).Approved | Should -BeTrue
        (New-ARCH2c4Scope).SourceStoreId | Should -BeExactly 'POP3'
    }
    It 'rejects unrelated Outlook profile' {
        (New-ARCH2c4Scope -Profile 'Different').ReasonCodes | Should -Contain 'WrongProfile'
    }
    It 'rejects POP3 source as the default store' {
        (New-ARCH2c4Scope -Default 'POP3').ReasonCodes | Should -Contain 'SourceIsDefaultStore'
    }
    It 'rejects non-POP3 account even with matching SMTP address' {
        $accounts=@([pscustomobject]@{SmtpAddress='info@stios.ru';AccountType=1;DeliveryStoreId='POP3'})
        (New-ARCH2c4Scope -Accounts $accounts).ReasonCodes | Should -Contain 'Pop3AccountNotUnique'
    }
    It 'rejects account delivery store pointing to another PST' {
        $accounts=@([pscustomobject]@{SmtpAddress='info@stios.ru';AccountType=2;DeliveryStoreId='OTHER'})
        (New-ARCH2c4Scope -Accounts $accounts).ReasonCodes | Should -Contain 'Pop3AccountNotDeliveringToSource'
    }
    It 'rejects duplicated POP3 accounts' {
        $accounts=@([pscustomobject]@{SmtpAddress='info@stios.ru';AccountType=2;DeliveryStoreId='POP3'},
                    [pscustomobject]@{SmtpAddress='info@stios.ru';AccountType=2;DeliveryStoreId='POP3'})
        (New-ARCH2c4Scope -Accounts $accounts).ReasonCodes | Should -Contain 'Pop3AccountNotUnique'
    }
    It 'rejects source PST not uniquely mounted' {
        $stores=@([pscustomobject]@{StoreId='POP3';FilePath=$script:sourcePath},
                  [pscustomobject]@{StoreId='DUP';FilePath=$script:sourcePath})
        (New-ARCH2c4Scope -Stores $stores).ReasonCodes | Should -Contain 'SourceStoreNotUnique'
    }
    It 'rejects an ambiguous archive attachment' {
        $l=New-ARCH2c4Layout
        $stores=@([pscustomobject]@{StoreId='OTHER';FilePath='C:\Office\other.pst'},
                  [pscustomobject]@{StoreId='POP3';FilePath=$script:sourcePath},
                  [pscustomobject]@{StoreId='ARCH1';FilePath=[string]$l.ArchivePst},
                  [pscustomobject]@{StoreId='ARCH2';FilePath=[string]$l.ArchivePst})
        (New-ARCH2c4Scope -Layout $l -Stores $stores).ReasonCodes | Should -Contain 'ArchiveStoreAmbiguous'
    }
    It 'rejects unspecified operator approval' {
        {Assert-OPA265ARCH2c4OneShotApproval -Action Move -RunId $script:run -ApprovalText '' -Confirmed $true} | Should -Throw
    }
    It 'rejects approval for another RunId' {
        {Assert-OPA265ARCH2c4OneShotApproval -Action Prepare -RunId $script:run -ApprovalText 'PREPARE ARCH2C4 other' -Confirmed $true} | Should -Throw
    }
    It 'requires confirmation switch in addition to exact text' {
        {Assert-OPA265ARCH2c4OneShotApproval -Action Move -RunId $script:run -ApprovalText ('MOVE ARCH2C4 '+$script:run) -Confirmed $false} | Should -Throw
    }
    It 'accepts exact one-shot approval and still does not write a PST by itself' {
        (Assert-OPA265ARCH2c4OneShotApproval -Action Move -RunId $script:run -ApprovalText ('MOVE ARCH2C4 '+$script:run) -Confirmed $true) | Should -BeTrue
    }
    It 'creates immutable JSON with forced durability, then verifies exact SHA256' {
        $p=Join-Path $TestDrive 'arch2c4-immutable.json'
        $value=[pscustomobject]@{Schema='test';RunId=$script:run;NeverRetry=$true}
        $sha=Write-OPA265ARCH2c4JsonOnce -Path $p -Value $value
        $sha | Should -Match '^[a-f0-9]{64}$'
        $v=Read-OPA265ARCH2c4JsonSealed -Path $p -ExpectedSha256 $sha
        $v.RunId | Should -BeExactly $script:run
    }
    It 'refuses to overwrite an existing one-shot claim after a simulated crash' {
        $p=Join-Path $TestDrive 'arch2c4-claimed.json'
        $value=[pscustomobject]@{RunId=$script:run;MoveAttemptClaimed=$true}
        [void](Write-OPA265ARCH2c4JsonOnce -Path $p -Value $value)
        {Write-OPA265ARCH2c4JsonOnce -Path $p -Value $value} | Should -Throw
    }
    It 'rejects tampered durable evidence before any Move' {
        $p=Join-Path $TestDrive 'arch2c4-tamper.json'
        $sha=Write-OPA265ARCH2c4JsonOnce -Path $p -Value ([pscustomobject]@{Status='Original'})
        [IO.File]::AppendAllText($p,'tampered')
        {Read-OPA265ARCH2c4JsonSealed -Path $p -ExpectedSha256 $sha} | Should -Throw
    }
    It 'rejects an invalid expected SHA256' {
        $p=Join-Path $TestDrive 'arch2c4-invalid-hash.json'
        [void](Write-OPA265ARCH2c4JsonOnce -Path $p -Value ([pscustomobject]@{Status='Original'}))
        {Read-OPA265ARCH2c4JsonSealed -Path $p -ExpectedSha256 'INVALID'} | Should -Throw
    }
    It 'only accepts source zero archive one semantic match after restart' {
        $r=Test-OPA265ARCH2c4Reconciliation -SourceCount 0 -DestinationCount 1 -SemanticContentMatches $true -RestartConfirmed $true
        $r.IndependentlyMatched | Should -BeTrue
        $r.AutomaticMoveRetryAllowed | Should -BeFalse
    }
    It 'rejects source still containing the original entry' {
        (Test-OPA265ARCH2c4Reconciliation -SourceCount 1 -DestinationCount 1 -SemanticContentMatches $true -RestartConfirmed $true).IndependentlyMatched | Should -BeFalse
    }
    It 'rejects unknown source state even if destination looks correct' {
        (Test-OPA265ARCH2c4Reconciliation -SourceCount -1 -DestinationCount 1 -SemanticContentMatches $true -RestartConfirmed $true).IndependentlyMatched | Should -BeFalse
    }
    It 'rejects two destination matches' {
        (Test-OPA265ARCH2c4Reconciliation -SourceCount 0 -DestinationCount 2 -SemanticContentMatches $true -RestartConfirmed $true).IndependentlyMatched | Should -BeFalse
    }
    It 'rejects changed user content/attachment digest' {
        (Test-OPA265ARCH2c4Reconciliation -SourceCount 0 -DestinationCount 1 -SemanticContentMatches $false -RestartConfirmed $true).IndependentlyMatched | Should -BeFalse
    }
    It 'rejects unchanged Outlook process' {
        (Test-OPA265ARCH2c4Reconciliation -SourceCount 0 -DestinationCount 1 -SemanticContentMatches $true -RestartConfirmed $false).IndependentlyMatched | Should -BeFalse
    }
    It 'uses exactly one COM Move in the dedicated core and no Copy/Delete/Send' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2c4OneShotCore.ps1') -Raw -Encoding UTF8
        ([regex]::Matches($s,'\$sourceItem\.Move\(\$archiveFolder\)')).Count | Should -Be 1
        $s | Should -Not -Match '\.(Copy|Delete|Send)\s*\('
        $s | Should -Match 'Write-OPA265ARCH2c4JsonOnce -Path \$layout.GlobalClaimPath'
        $s | Should -Match 'Write-OPA265ARCH2c4JsonOnce -Path \$layout.ClaimPath'
    }
    It 'seals global and run-specific claims before the only COM Move' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2c4OneShotCore.ps1') -Raw -Encoding UTF8
        $globalIndex=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path $layout.GlobalClaimPath')
        $claimIndex=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path $layout.ClaimPath')
        $moveIndex=$s.IndexOf('$sourceItem.Move($archiveFolder)')
        ($globalIndex -ge 0 -and $claimIndex -gt $globalIndex -and $moveIndex -gt $claimIndex) | Should -BeTrue
    }
    It 'preserves the ARCH2a production writer gate in the original entrypoint' {
        $app=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $app | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
        $app | Should -Not -Match "ValidateSet\('Auto','Analyze','Plan','Archive','Resume','ARCH2c4'"
    }
    It 'requires explicit operator one-shot entrypoint instead of legacy Archive' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Invoke-ARCH2c4.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Plan','Inventory','Prepare','Move','Reconcile'\)"
        $s | Should -Match 'Invoke-OPA265ARCH2c4OneShot'
    }
}
