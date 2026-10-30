#requires -Version 5.1
BeforeAll {
    $root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $source=Join-Path $root 'Core/Diagnostics/Invoke-OPA265BW4gOneShotDisposableMove.ps1'
    $classifier=Join-Path $root 'Core/Worker/BW4fFreshFixtureScope265.ps1'
    $permit=Join-Path $root 'Core/Worker/BW4gOneShotPermit265.ps1'
    $script:worker=[IO.File]::ReadAllText($source)
    . $classifier
    $script:id='98bef817-0fb5-478a-b869-33f02fda59d3'
    $script:subject='OPA265 BW4e1 FRESH TEST '+$script:id
    $script:body=("OPA265 BW4e1 disposable synthetic test. `r`n`r`n"+
       "TestId: $script:id `r`n`r`n"+
       "This message contains no customer data. `r`n"+
       "Created exclusively for read-only Outlook/MAPI verification. `r`n"+
       "No historical operation or journal may be reused. `r`n")
}
Describe 'BW4g1 merge: real BW4f3 250-char Outlook fixture is eligible for ONLY one separately authorized attempt' {
    It 'recognizes the actual received POP3 Body length 250 and exact padded markers' {
        $script:body.Length | Should -Be 250
        $r=Get-OPA265BW4fFixtureTag -Subject $script:subject -Body $script:body -AttachmentCount 0
        $r.IsExactOperatorFixture | Should -BeTrue
        $r.TestId | Should -BeExactly $script:id
    }
    It 'has no MailItem.Move call in read-only marker classifier' {
        $classifierCode=[IO.File]::ReadAllText($classifier)
        $classifierCode | Should -Not -Match '(?i)\.Move\('
        $classifierCode | Should -Not -Match '(?i)\.Save\('
    }
    It 'checks pin witnesses before durable claim and creates claim before the only Move call' {
        $iFinal=$script:worker.IndexOf('Get-OPA265BW4cItemWitness')
        $iClaim=$script:worker.IndexOf('Write-OPA265BW4gOneShotClaim')
        $iMove=$script:worker.IndexOf('$mail.Move($dest)')
        $iFinal | Should -BeGreaterThan 0
        $iClaim | Should -BeGreaterThan $iFinal
        $iMove | Should -BeGreaterThan $iClaim
        ([regex]::Matches($script:worker,'\$mail\.Move\(\$dest\)')).Count | Should -Be 1
    }
    It 'requires explicit operator Execute and one-shot confirmation; Review excludes execution' {
        $script:worker | Should -Match '\$Execute -and -not \$ConfirmOneShotDisposableMove'
        $script:worker | Should -Match 'if \(\$Review\) \{'
        $script:worker | Should -Match 'return'
    }
    It 'prevents a preexisting local attempt claim from reaching COM Move' {
        $script:worker | Should -Match 'persistent prior attempt claim exists; NEVER RETRY'
        $script:worker | Should -Match 'File\]::Exists\(\$claimPath\)'
        $permitCode=[IO.File]::ReadAllText($permit)
        $permitCode | Should -Match 'FileMode\]::CreateNew'
        $permitCode | Should -Match 'Flush\(\$true\)'
    }
}
