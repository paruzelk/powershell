#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a1ExistingProfilePolicy265.ps1')
    $script:guid='99201994-156b-40d2-9a63-52d73f99ee01'
    $script:layout=Get-OPA265BW4k7v2a1Layout -SuiteId $script:guid -LocalAppData $env:LOCALAPPDATA
    $script:controller=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2a1ExistingProfilePilot.ps1') -Raw -Encoding UTF8
    function New-BW4k7v2a1ScopeArguments {
        return @{
            Layout=$script:layout
            ActualProfileName='Outlook'
            Accounts=@([pscustomobject]@{SmtpAddress='info@stios.ru';AccountType=2;DeliveryStoreId='POP3'})
            Stores=@(
                [pscustomobject]@{StoreId='POP3';FilePath='C:\Dummy\info@stios.ru.pst'}
                [pscustomobject]@{StoreId='OTHER';FilePath='C:\Dummy\another.pst'}
            )
        }
    }
}
Describe 'BW4k7v2a1 existing POP3 Outlook profile safely targets a new PST' {
    It 'accepts new canonical lowercase SuiteId' {
        {Assert-OPA265BW4k7v2a1SuiteId -SuiteId $script:guid} | Should -Not -Throw
    }
    It 'rejects uppercase SuiteId' {
        {Assert-OPA265BW4k7v2a1SuiteId -SuiteId $script:guid.ToUpperInvariant()} | Should -Throw
    }
    It 'rejects original failed BW4k7v SuiteId' {
        {Assert-OPA265BW4k7v2a1SuiteId -SuiteId '78a3e477-98fc-4134-b400-429b3e3b216b'} | Should -Throw
    }
    It 'rejects all-zero SuiteId' {
        {Assert-OPA265BW4k7v2a1SuiteId -SuiteId '00000000-0000-0000-0000-000000000000'} | Should -Throw
    }
    It 'plans original Outlook profile rather than dedicated account-free profile' {
        $script:layout.ProfileName | Should -BeExactly 'Outlook'
    }
    It 'allocates a unique local PST path under suite directory' {
        $script:layout.PstPath.StartsWith($script:layout.SuiteDirectory,[StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
    }
    It 'accepts existing POP3 account with multiple existing stores' {
        $a=New-BW4k7v2a1ScopeArguments
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeTrue
    }
    It 'rejects other Outlook profile names' {
        $a=New-BW4k7v2a1ScopeArguments;$a.ActualProfileName='Other'
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'rejects IMAP instead of POP3 even with matching address' {
        $a=New-BW4k7v2a1ScopeArguments;$a.Accounts[0].AccountType=1
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'rejects missing target POP3 account' {
        $a=New-BW4k7v2a1ScopeArguments;$a.Accounts=@()
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'rejects multiple POP3 accounts matching exact address' {
        $a=New-BW4k7v2a1ScopeArguments;$a.Accounts=@($a.Accounts[0],$a.Accounts[0])
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'rejects POP3 delivery to missing StoreID' {
        $a=New-BW4k7v2a1ScopeArguments;$a.Accounts[0].DeliveryStoreId='MISSING'
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'rejects missing POP3 DeliveryStoreID' {
        $a=New-BW4k7v2a1ScopeArguments;$a.Accounts[0].DeliveryStoreId=''
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'rejects duplicate StoreIDs' {
        $a=New-BW4k7v2a1ScopeArguments;$a.Stores[1].StoreId='POP3'
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'rejects a null store descriptor' {
        $a=New-BW4k7v2a1ScopeArguments;$a.Stores=@($null,$a.Stores[0])
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'rejects a preattached test PST before creating new one' {
        $a=New-BW4k7v2a1ScopeArguments
        $a.Stores+=([pscustomobject]@{StoreId='TEST';FilePath=$script:layout.PstPath})
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).Approved | Should -BeFalse
    }
    It 'accepts one separate test PST after it has been attached' {
        $a=New-BW4k7v2a1ScopeArguments
        $a.Stores+=([pscustomobject]@{StoreId='TEST';FilePath=$script:layout.PstPath})
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a -AllowTargetAttached).Approved | Should -BeTrue
    }
    It 'rejects detached target in post-restart inspection' {
        $a=New-BW4k7v2a1ScopeArguments
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a -AllowTargetAttached).Approved | Should -BeFalse
    }
    It 'rejects two stores bound to one exact test PST' {
        $a=New-BW4k7v2a1ScopeArguments
        $a.Stores+=@(
            [pscustomobject]@{StoreId='TEST1';FilePath=$script:layout.PstPath}
            [pscustomobject]@{StoreId='TEST2';FilePath=$script:layout.PstPath}
        )
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a -AllowTargetAttached).Approved | Should -BeFalse
    }
    It 'rejects test PST that is also the POP3 delivery store' {
        $a=New-BW4k7v2a1ScopeArguments
        $a.Stores[0].FilePath=$script:layout.PstPath
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a -AllowTargetAttached).Approved | Should -BeFalse
    }
    It 'does not declare production ready or writer permit' {
        $a=New-BW4k7v2a1ScopeArguments
        $r=Test-OPA265BW4k7v2a1ExistingProfileScope @a
        $r.ProductionReady | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
    }
    It 'does not allow automatic retries' {
        $a=New-BW4k7v2a1ScopeArguments
        (Test-OPA265BW4k7v2a1ExistingProfileScope @a).AutomaticRetryAllowed | Should -BeFalse
    }
    It 'controller uses explicit folder Items.Add instead of Application.CreateItem' {
        $script:controller | Should -Match '\$folder\.Items\.Add\(''IPM.Note''\)'
        $script:controller | Should -Not -Match '\$app\.CreateItem\('
    }
    It 'controller uses correct Unicode PST olStoreUnicode value 2' {
        $script:controller | Should -Match 'AddStoreEx\(\[string\]\$layout.PstPath,2\)'
    }
    It 'controller writes immutable one-shot intent before AddStoreEx' {
        $a=$script:controller.IndexOf('Write-OPA265BW4k7v2a1JsonOnce -Path $layout.IntentPath')
        $b=$script:controller.IndexOf('$ns.AddStoreEx(')
        $a | Should -BeGreaterThan 0
        $b | Should -BeGreaterThan $a
    }
    It 'controller verifies both actual parent StoreID and Folder EntryID' {
        $script:controller | Should -Match '\$pilot.Parent.StoreID'
        $script:controller | Should -Match '\$pilot.Parent.EntryID'
    }
    It 'controller does not Move Send or Delete mail' {
        $script:controller | Should -Not -Match '\.(Move|Send|Delete)\s*\('
    }
    It 'controller does not change profile default store or PST registry' {
        $script:controller | Should -Not -Match 'DefaultStore\s*=|Set-ItemProperty|New-ItemProperty|Remove-ItemProperty'
    }
    It 'controller requires Outlook restart before independent VerifyPilot' {
        $script:controller | Should -Match 'Complete Outlook process restart required'
    }
    It 'controller preserves failed run and explicitly forbids retries' {
        $script:controller | Should -Match 'NEVER RETRY CreatePilot'
    }
}