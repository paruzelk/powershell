#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2IsolatedProfilePolicy265.ps1')
    $script:id='c934c588-321b-4f74-88c7-3e2e2ab7ab8f'
    $script:layout=Get-OPA265BW4k7v2Layout -SuiteId $script:id -LocalAppData $env:LOCALAPPDATA
    $script:isolationParams=@{
        Layout=$script:layout
        ActualProfileName='OPA265-BW4k7v2'
        AccountsCount=0
        StoresCount=1
        DefaultStoreId='TEST-ID'
        OnlyStoreId='TEST-ID'
        OnlyStoreFilePath=$script:layout.PstPath
        PstSizeBytes=1048576
        RequirePristine=$true
    }
    $script:manifest=[pscustomobject]@{
        Schema='2.6.5-BW4k7v2.PilotPreMoveManifest.1'
        SuiteId=$script:id
        PstPath=$script:layout.PstPath
        ProfileName=$script:layout.ProfileName
        Subject=$script:layout.PilotSubject
        StoreId='STORE'
        RootId='ROOT'
        FolderId='FOLDER'
        EntryId='ENTRY'
        CreatingProcessStartUtcTicks=639000000000000000L
        WitnessSha256=('a'*64)
        SyntheticArchiveYear=2020
        DedicatedSinglePstNoAccounts=$true
        MoveExecuted=$false
        SendExecuted=$false
        OldProfileTouched=$false
        ProductionReady=$false
        WriterPermit=$false
    }
    function Copy-BW4k7v2Object {
        param($x)
        ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $x -Depth 12 -Compress)
    }
    $script:policyCode=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2IsolatedProfilePolicy265.ps1') -Raw -Encoding UTF8
    $script:controlCode=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2IsolatedPilotPreflight.ps1') -Raw -Encoding UTF8
}
Describe 'BW4k7v2 dedicated single-default-PST zero-account profile and one-pilot explicit InFolder semantic safety' {
    It 'accepts fresh canonical suite' {
        (Assert-OPA265BW4k7v2SuiteId -SuiteId $script:id) | Should -BeTrue
    }
    It 'rejects original failed BW4k7v suite' {
        {Assert-OPA265BW4k7v2SuiteId -SuiteId '78a3e477-98fc-4134-b400-429b3e3b216b'} | Should -Throw
    }
    It 'rejects irreversible BW4k7m suite' {
        {Assert-OPA265BW4k7v2SuiteId -SuiteId 'd1a68868-acf5-4c70-860d-5521e1ce2836'} | Should -Throw
    }
    It 'rejects random malformed GUID' {
        {Assert-OPA265BW4k7v2SuiteId -SuiteId 'bad'} | Should -Throw
    }
    It 'rejects uppercase GUID' {
        {Assert-OPA265BW4k7v2SuiteId -SuiteId $script:id.ToUpperInvariant()} | Should -Throw
    }
    It 'rejects empty GUID' {
        {Assert-OPA265BW4k7v2SuiteId -SuiteId '00000000-0000-0000-0000-000000000000'} | Should -Throw
    }
    It 'layout profile exact dedicated name' {
        $script:layout.ProfileName | Should -BeExactly 'OPA265-BW4k7v2'
    }
    It 'layout independent from old BW4k7v path' {
        $script:layout.PstPath | Should -Not -Match 'BW4k7v-Isolated'
    }
    It 'layout under new isolated local folder' {
        $script:layout.PstPath | Should -Match 'OutlookPOP3Archive-BW4k7v2-Isolated'
    }
    It 'layout requires same suite ID in file' {
        $script:layout.PstPath | Should -Match $script:id
    }
    It 'layout has exact new PST filename' {
        [IO.Path]::GetFileName($script:layout.PstPath) | Should -BeExactly ('OPA265-BW4k7v2-'+$script:id+'.pst')
    }
    It 'layout has exact one pilot template filename' {
        [IO.Path]::GetFileName($script:layout.TemplatePath) | Should -BeExactly ('pilot-'+$script:id+'.oft')
    }
    It 'layout pinned pilot root' {
        $script:layout.RootFolderName | Should -BeExactly ('OPA265-BW4k7v2-'+$script:id)
    }
    It 'layout pilot folder one and exact' {
        $script:layout.PilotFolderName | Should -BeExactly 'Pilot-Inbox'
    }
    It 'layout synthetic year 2020 not MAPI' {
        $script:layout.SyntheticYear | Should -Be 2020
    }
    It 'layout writer never granted' {
        $script:layout.WriterPermit | Should -BeFalse
    }
    It 'layout production never granted' {
        $script:layout.ProductionReady | Should -BeFalse
    }
    It 'layout rejects relative local appdata' {
        {Get-OPA265BW4k7v2Layout -SuiteId $script:id -LocalAppData 'Downloads'} | Should -Throw
    }
    It 'layout rejects UNC appdata' {
        {Get-OPA265BW4k7v2Layout -SuiteId $script:id -LocalAppData '\\server\root'} | Should -Throw
    }
    It 'layout cannot be replaced by custom PST' {
        $copy=Copy-BW4k7v2Object $script:layout; $copy.PstPath='C:\prod.pst'; {Assert-OPA265BW4k7v2Layout -Layout $copy -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'layout cannot change profile name' {
        $copy=Copy-BW4k7v2Object $script:layout; $copy.ProfileName='Outlook'; {Assert-OPA265BW4k7v2Layout -Layout $copy -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'layout cannot change manifest name' {
        $copy=Copy-BW4k7v2Object $script:layout; $copy.ManifestPath='C:\other.json'; {Assert-OPA265BW4k7v2Layout -Layout $copy -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'layout exact canonical validation succeeds' {
        (Assert-OPA265BW4k7v2Layout -Layout $script:layout -LocalAppData $env:LOCALAPPDATA) | Should -BeTrue
    }
    It 'only test PST default and one account-free store passes' {
        (Test-OPA265BW4k7v2StoreIsolation @script:args).Isolated | Should -BeTrue
    }
    It 'new Outlook main working profile rejected' {
        $x=@{}+$script:isolationParams; $x.ActualProfileName='Outlook'; (Test-OPA265BW4k7v2StoreIsolation @x).Isolated | Should -BeFalse
    }
    It 'wrong profile reason code surfaced' {
        $x=@{}+$script:isolationParams; $x.ActualProfileName='Outlook'; (Test-OPA265BW4k7v2StoreIsolation @x).ReasonCodes | Should -Contain 'NotDedicatedProfile'
    }
    It 'one linked mail account rejected' {
        $x=@{}+$script:isolationParams; $x.AccountsCount=1; (Test-OPA265BW4k7v2StoreIsolation @x).ReasonCodes | Should -Contain 'MailAccountsPresent'
    }
    It 'two accounts rejected' {
        $x=@{}+$script:isolationParams; $x.AccountsCount=2; (Test-OPA265BW4k7v2StoreIsolation @x).Isolated | Should -BeFalse
    }
    It 'two mounted PSTs rejected' {
        $x=@{}+$script:isolationParams; $x.StoresCount=2; (Test-OPA265BW4k7v2StoreIsolation @x).ReasonCodes | Should -Contain 'MultipleOrMissingStores'
    }
    It 'zero stores rejected' {
        $x=@{}+$script:isolationParams; $x.StoresCount=0; (Test-OPA265BW4k7v2StoreIsolation @x).Isolated | Should -BeFalse
    }
    It 'wrong default StoreID rejected' {
        $x=@{}+$script:isolationParams; $x.DefaultStoreId='different'; (Test-OPA265BW4k7v2StoreIsolation @x).ReasonCodes | Should -Contain 'DefaultStoreNotOnlyStore'
    }
    It 'empty only StoreID rejected' {
        $x=@{}+$script:isolationParams; $x.OnlyStoreId=''; (Test-OPA265BW4k7v2StoreIsolation @x).Isolated | Should -BeFalse
    }
    It 'wrong default path rejected' {
        $x=@{}+$script:isolationParams; $x.OnlyStoreFilePath='C:\Outlook Files\info@stios.ru.pst'; (Test-OPA265BW4k7v2StoreIsolation @x).ReasonCodes | Should -Contain 'OnlyStorePathMismatch'
    }
    It 'empty default path rejected' {
        $x=@{}+$script:isolationParams; $x.OnlyStoreFilePath=''; (Test-OPA265BW4k7v2StoreIsolation @x).Isolated | Should -BeFalse
    }
    It 'suspiciously large initial PST rejected' {
        $x=@{}+$script:isolationParams; $x.PstSizeBytes=30000000; (Test-OPA265BW4k7v2StoreIsolation @x).ReasonCodes | Should -Contain 'PilotPstTooLargeOrMissing'
    }
    It 'missing or empty initial PST rejected' {
        $x=@{}+$script:isolationParams; $x.PstSizeBytes=0; (Test-OPA265BW4k7v2StoreIsolation @x).Isolated | Should -BeFalse
    }
    It 'hard-stop on failed profile safety' {
        $x=@{}+$script:isolationParams; $x.AccountsCount=1; (Test-OPA265BW4k7v2StoreIsolation @x).MustStopBeforeAnyMailCreation | Should -BeTrue
    }
    It 'never fallback to another store' {
        (Test-OPA265BW4k7v2StoreIsolation @script:args).AutomaticRecoveryOrFallbackAllowed | Should -BeFalse
    }
    It 'never grant writer even in valid one-store test' {
        (Test-OPA265BW4k7v2StoreIsolation @script:args).WriterPermit | Should -BeFalse
    }
    It 'sha256 abc correct RFC value' {
        (Get-OPA265BW4k7v2Sha256 -Text 'abc') | Should -BeExactly 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }
    It 'sha256 unicode deterministic' {
        (Get-OPA265BW4k7v2Sha256 -Text 'Пример') | Should -BeExactly (Get-OPA265BW4k7v2Sha256 -Text 'Пример')
    }
    It 'valid pure synthetic pilot manifest shape' {
        (Assert-OPA265BW4k7v2PilotManifest -Manifest $script:manifest -Layout $script:layout) | Should -BeTrue
    }
    It 'pilot manifest rejects original failed GUID' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.SuiteId='78a3e477-98fc-4134-b400-429b3e3b216b'; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects profile substitution' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.ProfileName='Outlook'; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects different PST' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.PstPath='C:\original.pst'; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects changed subject' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.Subject='UserMessage'; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects changed folder id' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.FolderId=''; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects changed EntryID' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.EntryId=''; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects missing StoreID' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.StoreId=''; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects fake hash' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.WitnessSha256='abc'; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects no Outlook start ticks' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.CreatingProcessStartUtcTicks=0; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects missing isolation assurance' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.DedicatedSinglePstNoAccounts=$false; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects Move performed' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.MoveExecuted=$true; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects Send performed' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.SendExecuted=$true; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects old profile touched' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.OldProfileTouched=$true; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects production flag' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.ProductionReady=$true; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'pilot manifest rejects writer flag' {
        $m=Copy-BW4k7v2Object $script:manifest; $m.WriterPermit=$true; {Assert-OPA265BW4k7v2PilotManifest -Manifest $m -Layout $script:layout} | Should -Throw
    }
    It 'manifest can only be created once' {
        $script:policyCode | Should -Match 'FileMode]::CreateNew'
    }
    It 'manifest calls disk flush true' {
        $script:policyCode | Should -Match 'Flush\(\$true\)'
    }
    It 'manifest verify requires exact original SHA256' {
        $script:policyCode | Should -Match 'sealed manifest tampered'
    }
    It 'controller allows only five modes' {
        $script:controlCode | Should -Match 'Plan.+Prepare.+Inspect.+CreatePilot.+VerifyPilot'
    }
    It 'controller main profile never accepted' {
        $script:controlCode | Should -Match 'Test-OPA265BW4k7v2StoreIsolation'
    }
    It 'controller uses exact dedicated no-account account count' {
        $script:controlCode | Should -Match 'Accounts.Count'
    }
    It 'controller restricts exactly one Outlook store' {
        $script:controlCode | Should -Match '\$stores -ne 1'
    }
    It 'controller only one template-based pilot' {
        $script:controlCode | Should -Match 'MessageCountMaximumThisStage=1'
    }
    It 'controller explicitly targets InFolder' {
        $script:controlCode | Should -Match 'CreateItemFromTemplate\(\[string\]\$layout.TemplatePath,\$pilotFolder\)'
    }
    It 'controller template is OFT format 2' {
        $script:controlCode | Should -Match 'SaveAs\(\[string\]\$layout.TemplatePath,2\)'
    }
    It 'controller checks real parent folder after Save' {
        $script:controlCode | Should -Match '\$pilot.Parent.EntryID'
    }
    It 'controller checks real store after Save' {
        $script:controlCode | Should -Match '\$pilot.Parent.StoreID'
    }
    It 'controller stops on misrouted pilot' {
        $script:controlCode | Should -Match 'pilot misrouted; STOP'
    }
    It 'controller never creates 8 objects in one run' {
        $script:controlCode | Should -Not -Match 'foreach\(\$case in'
    }
    It 'controller requests per GUID consent' {
        $script:controlCode | Should -Match 'CREATE BW4K7V2 PILOT'
    }
    It 'controller never calls MailItem Move' {
        $script:controlCode | Should -Not -Match '[.]Move\s*\('
    }
    It 'controller never calls MailItem Send' {
        $script:controlCode | Should -Not -Match '[.]Send\s*\('
    }
    It 'controller never calls MailItem Delete' {
        $script:controlCode | Should -Not -Match '[.]Delete\s*\('
    }
    It 'controller never changes registry' {
        $script:controlCode | Should -Not -Match 'Set-ItemProperty|New-ItemProperty'
    }
    It 'controller never mounts original PST' {
        $script:controlCode | Should -Not -Match 'AddStoreEx\s*\('
    }
    It 'controller never opens another PST by filename' {
        $script:controlCode | Should -Not -Match 'OpenSharedItem\s*\('
    }
    It 'controller requires new process on VerifyPilot' {
        $script:controlCode | Should -Match 'VerifyPilot requires Outlook full restart'
    }
    It 'controller forbids retry after pilot fails' {
        $script:controlCode | Should -Match 'NEVER retry CreatePilot for this SuiteId'
    }
    It 'controller records HRESULT per precise stage' {
        $script:controlCode | Should -Match 'HRESULT='
    }
    It 'controller no writer permit' {
        $script:controlCode | Should -Match 'WriterPermit=\$false'
    }
    It 'controller no production readiness' {
        $script:controlCode | Should -Match 'ProductionReady=\$false'
    }
}
