#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7hPostMoveFlagAttribution265.ps1')
    function New-OPA265BW4k7hSyntheticState {
        [pscustomobject][ordered]@{
            UnRead=$false
            Categories=''
            Importance=1
            Sensitivity=0
            FlagStatus=0
            FlagRequest=''
            ReminderSet=$false
            To='synthetic@example.test'
            CC=''
            BCC=''
        }
    }
    function New-OPA265BW4k7hSyntheticCase {
        $state=New-OPA265BW4k7hSyntheticState
        $origin=Get-OPA265BW4k7hCanonicalStateSha256 -State $state -MapiFlags 65555
        $dest=Get-OPA265BW4k7hCanonicalStateSha256 -State $state -MapiFlags 65553
        [pscustomobject]@{
            State=$state
            OriginalDigest=$origin
            DestinationDigest=$dest
        }
    }
}
Describe 'BW4k7h original BW4k7d canonical semantic SHA is reproduced exactly' {
    BeforeEach {$script:state=New-OPA265BW4k7hSyntheticState}
    It 'reproduces the original BW4k7d ten-field plus PR_MESSAGE_FLAGS SHA byte-for-byte' {
        $row=[pscustomobject][ordered]@{
            Index=1;Type=1;Name='Synthetic';Address='synthetic@example.test'
        }
        $original=Get-OPA265BW4k7dWitness -Recipients @($row) -State $script:state -MapiFlags 65555 -AttachmentCount 1 -SuiteId '74912f94-d523-4856-9efd-d5528a92426f' -TestId '87e72fd0-9e77-4098-a403-cbe99870b9e7' -SourceEntryId '00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
        $new=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65555
        $new | Should -BeExactly $original.UserStateDigestSha256
    }
    It 'changes when only raw full MAPIFlags change' {
        $a=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65555
        $b=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65553
        $b | Should -Not -BeExactly $a
    }
    It 'changes for a different Categories field' {
        $a=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65555
        $script:state.Categories='Risk'
        $b=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65555
        $b | Should -Not -BeExactly $a
    }
    It 'rejects a missing user-visible state field' {
        $script:state.PSObject.Properties.Remove('CC')
        {Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65555} | Should -Throw '*field count*'
    }
    It 'rejects an unexpected state field' {
        $script:state | Add-Member -NotePropertyName ForgedPermit -NotePropertyValue $true
        {Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65555} | Should -Throw '*field count*'
    }
    It 'rejects non-boolean UnRead' {
        $script:state.UnRead='False'
        {Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65555} | Should -Throw '*boolean*'
    }
    It 'rejects invalid Importance enum' {
        $script:state.Importance=23
        {Get-OPA265BW4k7hCanonicalStateSha256 -State $script:state -MapiFlags 65555} | Should -Throw '*enum*'
    }
}
Describe 'BW4k7h exact-only raw PR_MESSAGE_FLAGS attribution, no semantic waiver' {
    BeforeEach {
        $script:fixture=New-OPA265BW4k7hSyntheticCase
        $script:opts=@{
            DestinationState=$script:fixture.State
            DestinationFlags=65553
            OriginalFlags=65555
            OriginalUserStateSha256=$script:fixture.OriginalDigest
            ObservedDestinationUserStateSha256=$script:fixture.DestinationDigest
        }
    }
    It 'proves one changed raw flag when all ten captured fields match' {
        $result=Compare-OPA265BW4k7hRawFlagAttribution @opts
        $result.Status | Should -BeExactly 'OnlyRawPrMessageFlagsChangedAllCapturedUserFieldsMatch'
        $result.OnlyRawMapiFlagsChanged | Should -BeTrue
        $result.CapturedOutlookUserFieldsMatchExcludingRawMapiFlags | Should -BeTrue
        $result.ChangedMapiFlagsXor | Should -Be 2
        $result.ChangedMapiFlagsXorHex | Should -BeExactly '0x00000002'
    }
    It 'still forbids automatic semantic equivalence or production' {
        $result=Compare-OPA265BW4k7hRawFlagAttribution @opts
        $result.ChangedRawFlagBitsSemanticallyClassified | Should -BeFalse
        $result.PriorObservedMismatchMayBeReclassifiedAutomatically | Should -BeFalse
        $result.WriterPermit | Should -BeFalse
        $result.ProductionReady | Should -BeFalse
    }
    It 'reports exact nonzero changed bit values' {
        $result=Compare-OPA265BW4k7hRawFlagAttribution @opts
        @($result.ChangedFlagBitValues).Count | Should -Be 1
        $result.ChangedFlagBitValues[0] | Should -Be 2
    }
    It 'flags changed Categories as additional unresolved drift' {
        $script:fixture.State.Categories='ManualCategory'
        $script:opts.ObservedDestinationUserStateSha256=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:fixture.State -MapiFlags 65553
        $result=Compare-OPA265BW4k7hRawFlagAttribution @opts
        $result.Status | Should -BeExactly 'CapturedUserFieldOrCanonicalizationDifferenceUnresolved'
        $result.OnlyRawMapiFlagsChanged | Should -BeFalse
    }
    It 'flags changed To field without disclosing raw recipient addresses' {
        $script:fixture.State.To='alternate@example.test'
        $script:opts.ObservedDestinationUserStateSha256=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:fixture.State -MapiFlags 65553
        $result=Compare-OPA265BW4k7hRawFlagAttribution @opts
        $result.RawRecipientAddressesExposed | Should -BeFalse
        $result.CapturedOutlookUserFieldsMatchExcludingRawMapiFlags | Should -BeFalse
        $result.PSObject.Properties.Name | Should -Not -Contain 'To'
    }
    It 'flags changed user-visible FlagStatus even if raw flag change is identical' {
        $script:fixture.State.FlagStatus=2
        $script:opts.ObservedDestinationUserStateSha256=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:fixture.State -MapiFlags 65553
        $result=Compare-OPA265BW4k7hRawFlagAttribution @opts
        $result.Status | Should -BeExactly 'CapturedUserFieldOrCanonicalizationDifferenceUnresolved'
    }
    It 'flags READ or HASATTACH bit changes regardless of other fields' {
        $script:opts.DestinationFlags=65537
        $script:opts.ObservedDestinationUserStateSha256=Get-OPA265BW4k7hCanonicalStateSha256 -State $script:fixture.State -MapiFlags 65537
        $result=Compare-OPA265BW4k7hRawFlagAttribution @opts
        $result.Status | Should -BeExactly 'ReadOrAttachmentSemanticBitsChangedNeedsManualReview'
        $result.SignificantReadAttachBitsMatch | Should -BeFalse
    }
    It 'requires reserialized destination digest to equal independent BW4k7g digest' {
        $script:opts.ObservedDestinationUserStateSha256=('0'*64)
        {Compare-OPA265BW4k7hRawFlagAttribution @opts} | Should -Throw '*serialization does not match*'
    }
    It 'rejects unknown hash notation' {
        $script:opts.OriginalUserStateSha256='INVALID'
        {Compare-OPA265BW4k7hRawFlagAttribution @opts} | Should -Throw '*SHA-256 inputs*'
    }
    It 'recognizes exact unchanged fully matching state as a diagnostic only' {
        $script:opts.DestinationFlags=65555
        $script:opts.ObservedDestinationUserStateSha256=$script:fixture.OriginalDigest
        $result=Compare-OPA265BW4k7hRawFlagAttribution @opts
        $result.Status | Should -BeExactly 'FullUserStateShaNowMatchesOriginal'
        $result.PriorObservedMismatchMayBeReclassifiedAutomatically | Should -BeFalse
    }
}
Describe 'BW4k7h independent double-read stability and static controller boundaries' {
    BeforeEach {
        $script:f=New-OPA265BW4k7hSyntheticCase
        $script:o=@{
            DestinationState=$script:f.State
            DestinationFlags=65553;OriginalFlags=65555
            OriginalUserStateSha256=$script:f.OriginalDigest
            ObservedDestinationUserStateSha256=$script:f.DestinationDigest
        }
    }
    It 'accepts two independently identical attribution results' {
        $a=Compare-OPA265BW4k7hRawFlagAttribution @o
        $b=Compare-OPA265BW4k7hRawFlagAttribution @o
        (Assert-OPA265BW4k7hStableAttribution -First $a -Second $b) | Should -BeTrue
    }
    It 'rejects changed destination raw flag bit set between independent reads' {
        $a=Compare-OPA265BW4k7hRawFlagAttribution @o
        $b=Compare-OPA265BW4k7hRawFlagAttribution @o
        $b.ChangedFlagBitValues=@(4)
        {Assert-OPA265BW4k7hStableAttribution -First $a -Second $b} | Should -Throw '*flag bits*'
    }
    It 'rejects changed user-state digest between read-only reviews' {
        $a=Compare-OPA265BW4k7hRawFlagAttribution @o
        $b=Compare-OPA265BW4k7hRawFlagAttribution @o
        $b.DestinationUserStateSha256=('f'*64)
        {Assert-OPA265BW4k7hStableAttribution -First $a -Second $b} | Should -Throw '*drift*'
    }
    It 'has no method to replay Outlook Move or overwrite a Claim' {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7hPostMoveFlagReview.ps1'
        $txt=Get-Content -LiteralPath $p -Raw -Encoding UTF8
        $txt | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\s*\('
        $txt | Should -Not -Match 'Write-OPA265BW4k7gClaimOnce'
        $txt | Should -Not -Match 'FileMode.*CreateNew'
    }
    It 'reuses independent BW4k7g postmove Audit and requires source-zero target-one' {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7hPostMoveFlagReview.ps1'
        $txt=Get-Content -LiteralPath $p -Raw -Encoding UTF8
        $txt | Should -Match 'Invoke-OPA265BW4k7gPostMoveReadOnly'
        $txt | Should -Match 'SourceMessageIdMatches -ne 0'
        $txt | Should -Match 'DestinationMessageIdMatches -ne 1'
    }
    It 'pins original irreversible Claim SHA and specific destination EntryId' {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7hPostMoveFlagReview.ps1'
        $txt=Get-Content -LiteralPath $p -Raw -Encoding UTF8
        $txt | Should -Match '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        $txt | Should -Match '00000000D3E190022DF61241BBDE594AD46A661B24002000'
    }
    It 'never authorizes production or prior observed mismatch reclassification' {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7hPostMoveFlagReview.ps1'
        $txt=Get-Content -LiteralPath $p -Raw -Encoding UTF8
        $txt | Should -Match 'PriorObservedMismatchMayBeReclassifiedAutomatically=\$false'
        $txt | Should -Match 'ProductionReady=\$false'
    }
}
