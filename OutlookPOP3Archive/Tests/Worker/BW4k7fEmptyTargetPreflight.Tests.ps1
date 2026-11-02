#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7fEmptyTargetPreflight265.ps1')
    function New-BW4k7fVerifiedSnapshot {
        [pscustomobject]@{
            Schema='2.6.5-BW4k7e.IndependentSourceSnapshotVerify.1'
            Status='OriginalRecipientStateSnapshotVerifiedNoWriterPermit'
            SnapshotSha256='fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
            RecipientDigestSha256='11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024'
            UserStateDigestSha256='2d8e72b5e72b7beb94bb3d9cf9a20438936a6b0a4c4f701ff7d50b19177d0a8f'
            WriterPermit=$false;OutlookMoveExecuted=$false;ProductionReady=$false
        }
    }
    function New-BW4k7fEmptyTarget {
        [pscustomobject]@{
            SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
            TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
            SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
            SourceFolderEntryId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
            SourceStoreId='SOURCE-STORE'
            DestinationStoreId='DEST-STORE'
            DestinationPstLeaf='OPA265-BW4j-74912f94d52348569efdd5528a92426f-87e72fd09e774098a403cbe99870b9e7.pst'
            DestinationRootEntryId='DEST-ROOT'
            DestinationFolderEntryId='DEST-FOLDER'
            DestinationFolderParentEntryId='DEST-ROOT'
            DestinationFolderStoreId='DEST-STORE'
            DestinationFolderName='OPA265-BW4j-87e72fd09e774098a403cbe99870b9e7'
            MatchedTargetNamedFolderCount=1
            DestinationFolderItemCount=0
            SourceMessageIdMatches=1
            DestinationMessageIdMatches=0
            AttemptClaimExists=$false
            LegacyClaimExists=$false
        }
    }
}
Describe 'BW4k7f exact source semantic snapshot pin; never Move permit' {
    BeforeEach {$script:verified=New-BW4k7fVerifiedSnapshot}
    It 'accepts only exact immutable original recipient/state snapshot' {
        (Assert-OPA265BW4k7fEvidencePins -Verified $script:verified) | Should -BeTrue
    }
    It 'stops changed snapshot SHA' {
        $script:verified.SnapshotSha256=('a'*64)
        {Assert-OPA265BW4k7fEvidencePins -Verified $script:verified} | Should -Throw '*snapshot pin*'
    }
    It 'stops changed recipient digest' {
        $script:verified.RecipientDigestSha256=('a'*64)
        {Assert-OPA265BW4k7fEvidencePins -Verified $script:verified} | Should -Throw '*snapshot pin*'
    }
    It 'stops changed user-state digest' {
        $script:verified.UserStateDigestSha256=('a'*64)
        {Assert-OPA265BW4k7fEvidencePins -Verified $script:verified} | Should -Throw '*snapshot pin*'
    }
    It 'stops forged writer permission' {
        $script:verified.WriterPermit=$true
        {Assert-OPA265BW4k7fEvidencePins -Verified $script:verified} | Should -Throw '*writer permit*'
    }
    It 'stops forged Outlook Move claim' {
        $script:verified.OutlookMoveExecuted=$true
        {Assert-OPA265BW4k7fEvidencePins -Verified $script:verified} | Should -Throw '*writer permit*'
    }
}
Describe 'BW4k7f exact source-one/destination-zero scoped PST and folder' {
    BeforeEach {$script:target=New-BW4k7fEmptyTarget}
    It 'passes exact nonmoving empty target' {
        (Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target) | Should -BeTrue
    }
    It 'blocks populated destination' {
        $script:target.DestinationFolderItemCount=1
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks duplicate destination MessageId' {
        $script:target.DestinationMessageIdMatches=2
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks missing exact source' {
        $script:target.SourceMessageIdMatches=0
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks duplicate exact source' {
        $script:target.SourceMessageIdMatches=2
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks duplicate named target folder' {
        $script:target.MatchedTargetNamedFolderCount=2
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks destination folder belonging to different store' {
        $script:target.DestinationFolderStoreId='OTHER'
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks source store reused as destination' {
        $script:target.DestinationStoreId='SOURCE-STORE'
        $script:target.DestinationFolderStoreId='SOURCE-STORE'
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks wrong parent folder' {
        $script:target.DestinationFolderParentEntryId='NESTED'
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks wrong target PST leaf' {
        $script:target.DestinationPstLeaf='something-else.pst'
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*wrong exact*'
    }
    It 'blocks wrong target folder name' {
        $script:target.DestinationFolderName='Inbox'
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*wrong exact*'
    }
    It 'blocks a current irreversible claim' {
        $script:target.AttemptClaimExists=$true
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks an old claim' {
        $script:target.LegacyClaimExists=$true
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*empty-PST*'
    }
    It 'blocks a missing store identity' {
        $script:target.DestinationStoreId=''
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw '*opaque identity*'
    }
    It 'blocks extra fields in target witness' {
        $script:target | Add-Member -NotePropertyName WriterPermit -NotePropertyValue $true
        {Assert-OPA265BW4k7fExactEmptyTarget -Observed $script:target} | Should -Throw
    }
    It 'requires two matching target observations' {
        $a=New-BW4k7fEmptyTarget
        (Assert-OPA265BW4k7fStableEmptyTarget -First $a -Second $script:target) | Should -BeTrue
    }
    It 'blocks changes between target observations' {
        $a=New-BW4k7fEmptyTarget
        $script:target.DestinationFolderEntryId='ANOTHER'
        {Assert-OPA265BW4k7fStableEmptyTarget -First $a -Second $script:target} | Should -Throw '*changed between*'
    }
}
Describe 'BW4k7f controller is Review and WhatIf ONLY' {
    BeforeAll {
        $script:controller=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7fEmptyTargetReview.ps1') -Raw -Encoding UTF8
    }
    It 'requires original independent semantic Verify twice' {
        $script:controller | Should -Match 'Invoke-OPA265BW4k7eSemanticSourceSnapshot'
        $script:controller | Should -Match 'Assert-OPA265BW4k7fEvidencePins'
    }
    It 'pins exact recipient snapshot SHA' {
        $script:controller | Should -Match 'fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac'
    }
    It 'never calls MailItem.Move, Save, Send, or Delete' {
        $script:controller | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\s*\('
        $script:controller | Should -Not -Match 'Write-OPA265BW4k1ClaimOnce'
    }
    It 'has no CreateNew or AddStoreEx side effects' {
        $script:controller | Should -Not -Match 'CreateNew'
        $script:controller | Should -Not -Match 'AddStoreEx\s*\('
    }
    It 'has explicit WhatIf output and no production authorization' {
        $script:controller | Should -Match 'WhatIfNoClaimNoMove'
        $script:controller | Should -Match 'WriterPermit=\$false'
        $script:controller | Should -Match 'ProductionReady=\$false'
    }
}
