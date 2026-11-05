#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7vDisposablePstManifest265.ps1')
    $script:source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v1PartialPstReadOnly.ps1') -Raw -Encoding UTF8
    $script:id='56acebd7-4911-40e7-8b9f-32f1ad3b906a'
    $script:layout=Get-OPA265BW4k7vLayout -SuiteId $script:id -LocalAppData $env:LOCALAPPDATA
}
Describe 'BW4k7v1 failed partial disposable PST forensic read-only no retry safety' {
    It 'canonical failed-suite GUID remains required' {
        {Assert-OPA265BW4k7vSuiteId -SuiteId 'unknown'} | Should -Throw
    }
    It 'new forensic path is derived only from old GUID' {
        $script:layout.SourcePst | Should -Match $script:id
    }
    It 'forensic path is isolated local PST' {
        $script:layout.SourcePst | Should -Match 'OutlookPOP3Archive-BW4k7v-Isolated'
    }
    It 'older historic one shot suite ID rejected' {
        {Assert-OPA265BW4k7vSuiteId -SuiteId 'd1a68868-acf5-4c70-860d-5521e1ce2836'} | Should -Throw
    }
    It 'original old manifest cannot be constructed from diagnostic result' {
        $script:source | Should -Not -Match 'Write-OPA265BW4k7vManifestOnce'
    }
    It 'diagnostic never calls MailItem Save' {
        $script:source | Should -Not -Match '[.]Save\s*[(]'
    }
    It 'diagnostic never calls Outlook Move' {
        $script:source | Should -Not -Match '[.]Move\s*[(]'
    }
    It 'diagnostic never calls Outlook Send' {
        $script:source | Should -Not -Match '[.]Send\s*[(]'
    }
    It 'diagnostic never deletes real or synthetic item' {
        $script:source | Should -Not -Match '[.]Delete\s*[(]'
    }
    It 'diagnostic never calls Outlook AddStoreEx' {
        $script:source | Should -Not -Match 'AddStoreEx\s*\('
    }
    It 'diagnostic never creates PST file' {
        $script:source | Should -Not -Match 'CreateDirectory\s*\('
    }
    It 'diagnostic never calls Items.Add' {
        $script:source | Should -Not -Match 'Items.Add\s*\('
    }
    It 'diagnostic never calls Application.CreateItem' {
        $script:source | Should -Not -Match 'CreateItem\s*\('
    }
    It 'diagnostic never calls FileMode CreateNew' {
        $script:source | Should -Not -Match 'FileMode]::CreateNew'
    }
    It 'diagnostic never writes attached file' {
        $script:source | Should -Not -Match 'WriteAllBytes|WriteAllText|Set-Content|Out-File'
    }
    It 'diagnostic never edits registry' {
        $script:source | Should -Not -Match 'Set-ItemProperty|New-ItemProperty|Remove-ItemProperty'
    }
    It 'diagnostic binds existing local file only' {
        $script:source | Should -Match 'original NEW disposable PST not found'
    }
    It 'diagnostic rejects existing symlink root' {
        $script:source | Should -Match 'ReparsePoint'
    }
    It 'diagnostic requires exact Outlook profile' {
        $script:source | Should -Match 'CurrentProfileName'
    }
    It 'diagnostic matches unique exact test PST only' {
        $script:source | Should -Match 'Get-OPA265BW4k7vExactMountedStore'
    }
    It 'diagnostic excludes Outlook default store' {
        $script:source | Should -Match 'unexpectedly default store'
    }
    It 'diagnostic only looks under exact test root' {
        $script:source | Should -Match 'FixtureRootFolderName'
    }
    It 'diagnostic source folder scan is bounded' {
        $script:source | Should -Match 'MaxItemsPerFolder=20'
    }
    It 'diagnostic rejects count over configured bound' {
        $script:source | Should -Match 'refuses to enumerate oversized test folder'
    }
    It 'diagnostic limits scope to four paths' {
        $script:source | Should -Match 'Projects\\Alpha\\2022'; $script:source | Should -Match 'Sent Items'
    }
    It 'diagnostic never reconstructs original manifest' {
        $script:source | Should -Match 'OriginalManifestCreatedOrModified=\$false'
    }
    It 'diagnostic pins original exact expected synthetic subject' {
        $script:source | Should -Match 'Get-OPA265BW4k7vExpectedSubject'
    }
    It 'diagnostic calls GetItemFromID only on explicit switch' {
        $script:source | Should -Match 'if\(\$InspectGetItemFromId -and \$synthetic\)'
    }
    It 'diagnostic captures original GetItemFromID HRESULT' {
        $script:source | Should -Match 'OpenErrorHResult'
    }
    It 'diagnostic records item enumeration failure without mutating' {
        $script:source | Should -Match 'CollectionReadError'
    }
    It 'diagnostic reports no body or attachments read' {
        $script:source | Should -Match 'RawMailBodiesOrAttachmentsRead=\$false'
    }
    It 'diagnostic prohibits any old SuiteId Create retry' {
        $script:source | Should -Match 'AutomaticRetryOfOldSuiteAllowed=\$false'
    }
    It 'diagnostic never grants writer permit' {
        $script:source | Should -Match 'WriterPermit=\$false'
    }
    It 'diagnostic never grants production' {
        $script:source | Should -Match 'ProductionReady=\$false'
    }
    It 'diagnostic reports null/empty manifest without creating' {
        $script:source | Should -Match 'OriginalManifestExists='
    }
    It 'diagnostic has WhatIf that does not touch Outlook' {
        $script:source | Should -Match 'WhatIfNoOutlookOrPstRead'
    }
    It 'diagnostic records failed GetItemFromID separately' {
        $script:source | Should -Match 'GetItemFromIdFailed='
    }
    It 'diagnostic never auto moves once read by ID succeeds' {
        $script:source | Should -Match 'EightExactSyntheticItemsVisibleButNoSealedManifestNoMovePermit'
    }
    It 'diagnostic calls GetItemFromID with exact StoreID' {
        $script:source | Should -Match 'GetItemFromID\(\$id,\[string\]\$store.StoreID\)'
    }
    It 'diagnostic captures exact synthetic EntryID per item' {
        $script:source | Should -Match 'EntryId=\$id'
    }
}
