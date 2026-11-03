#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7jRawMessageFlagPolicy265.ps1')
    function Get-BW4k7jOriginalSyntheticFlagReview {
        Get-OPA265BW4k7jFlagDifference -OriginalFlags 65555 -DestinationFlags 17
    }
}
Describe 'BW4k7j authoritative source-aligned PidTagMessageFlags catalog' {
    It 'provides 13 unique documented flag bits only' {
        $catalog=@(Get-OPA265BW4k7jDocumentedFlagCatalog)
        $catalog.Count | Should -Be 13
        @($catalog | Select-Object -ExpandProperty Bit -Unique).Count | Should -Be 13
    }
    It 'maps 0x2 to precisely mfUnmodified under the right property' {
        $r=Get-BW4k7jOriginalSyntheticFlagReview
        $r.ChangedBits[0].BitDecimal | Should -Be 2
        $r.ChangedBits[0].FlagName | Should -BeExactly 'mfUnmodified'
        $r.ChangedBits[0].SourceReference | Should -BeExactly 'MS-OXCMSG:2.2.1.6'
    }
    It 'refuses to document 0x00010000 as a PR_MESSAGE_FLAGS flag name' {
        $r=Get-BW4k7jOriginalSyntheticFlagReview
        $r.ChangedBits[1].FlagName | Should -BeExactly 'UnspecifiedInReviewedMsOxcmsgTable'
        $r.ChangedBits[1].DocumentedForPidTagMessageFlags | Should -BeFalse
        $r.ChangedBits[1].BitDecimal | Should -Be 65536
    }
    It 'does not mistake STORE_HTML_OK 0x10000 in store support property as message flags' {
        $r=Get-BW4k7jOriginalSyntheticFlagReview
        $r.StoreHtmlOk0x10000BelongsToOtherProperty | Should -BeTrue
        $r.CrossPropertyBitValueNameReuseAccepted | Should -BeFalse
    }
    It 'does not mistake high bits in PR_MESSAGE_STATUS for PR_MESSAGE_FLAGS' {
        $r=Get-BW4k7jOriginalSyntheticFlagReview
        $r.MessageStatusHighBitsAreDifferentProperty | Should -BeTrue
    }
    It 'has correct read bit catalog name' {
        $c=@(Get-OPA265BW4k7jDocumentedFlagCatalog | Where-Object {$_.Bit -eq 1})
        $c.Count | Should -Be 1
        $c[0].FlagName | Should -BeNullOrEmpty
        $c[0].Name | Should -BeExactly 'mfRead'
    }
    It 'has correct attachment catalog name' {
        $c=@(Get-OPA265BW4k7jDocumentedFlagCatalog | Where-Object {$_.Bit -eq 16})
        $c.Count | Should -Be 1
        $c[0].Name | Should -BeExactly 'mfHasAttach'
    }
}
Describe 'BW4k7j exact original raw flag mismatch remains BLOCKED' {
    BeforeEach {$script:r=Get-BW4k7jOriginalSyntheticFlagReview}
    It 'classifies exact raw full 0x00010013 -> 0x00000011 flag change' {
        $script:r.Status | Should -BeExactly 'DocumentedModificationBitAndUnspecifiedRawBitRequireManualReview'
        $script:r.PropertyTag | Should -BeExactly '0x0E070003'
    }
    It 'computes the exact XOR 0x00010002, two bits and the original direction' {
        $script:r.OriginalFlags | Should -Be 65555
        $script:r.DestinationFlags | Should -Be 17
        $script:r.ChangedMaskDecimal | Should -Be 65538
        $script:r.ChangedMaskHex | Should -BeExactly '0x00010002'
        $script:r.ChangedBitCount | Should -Be 2
        $script:r.ChangedBits[0].SetBeforeMove | Should -BeTrue
        $script:r.ChangedBits[0].SetAfterMove | Should -BeFalse
        $script:r.ChangedBits[1].SetBeforeMove | Should -BeTrue
        $script:r.ChangedBits[1].SetAfterMove | Should -BeFalse
    }
    It 'counts only mfUnmodified as known storage lifecycle and 0x10000 as unknown' {
        $script:r.KnownModificationStateChangeCount | Should -Be 1
        $script:r.OtherDocumentedChangedBitCount | Should -Be 0
        $script:r.UnspecifiedChangedBitCount | Should -Be 1
        @($script:r.UnspecifiedChangedBitValues).Count | Should -Be 1
        $script:r.UnspecifiedChangedBitValues[0] | Should -Be 65536
    }
    It 'preserves read and attachment mask but never broad-waives full message state' {
        $script:r.ReadAndHasAttachBitsUnchanged | Should -BeTrue
        $script:r.OriginalFullRawUserStateShaMismatchAccepted | Should -BeFalse
        $script:r.ProviderModificationBitGloballyWaived | Should -BeFalse
    }
    It 'forbids all automatic retries/production and permits even after a known flag transition' {
        $script:r.UnspecifiedRawBitsWaived | Should -BeFalse
        $script:r.PermanentSemanticPolicyPermit | Should -BeFalse
        $script:r.AutomaticRetryAllowed | Should -BeFalse
        $script:r.WriterPermit | Should -BeFalse
        $script:r.ProductionReady | Should -BeFalse
    }
    It 'strictly recognizes original pinned classification' {
        (Assert-OPA265BW4k7jExactOriginalClassification -Result $script:r) | Should -BeTrue
    }
    It 'rejects fabricated waiver to unknown bit' {
        $script:r.UnspecifiedRawBitsWaived=$true
        {Assert-OPA265BW4k7jExactOriginalClassification -Result $script:r} | Should -Throw
    }
    It 'rejects a forged real-world writer permission' {
        $script:r.WriterPermit=$true
        {Assert-OPA265BW4k7jExactOriginalClassification -Result $script:r} | Should -Throw
    }
    It 'rejects altered exact immutable source message flags' {
        $script:r.OriginalFlags=65554
        {Assert-OPA265BW4k7jExactOriginalClassification -Result $script:r} | Should -Throw
    }
    It 'rejects any attempt to call undocumented bit a documented MAPI flag' {
        $script:r.ChangedBits[1].DocumentedForPidTagMessageFlags=$true
        {Assert-OPA265BW4k7jExactOriginalClassification -Result $script:r} | Should -Throw
    }
    It 'rejects cross-property STORE_HTML_OK as evidence of message flag semantics' {
        $script:r.CrossPropertyBitValueNameReuseAccepted=$true
        {Assert-OPA265BW4k7jExactOriginalClassification -Result $script:r} | Should -Throw
    }
}
Describe 'BW4k7j synthetic fault matrix for other MAPI flag changes' {
    It 'separately records pure documented modification state bit clearing' {
        $r=Get-OPA265BW4k7jFlagDifference -OriginalFlags 19 -DestinationFlags 17
        $r.Status | Should -BeExactly 'DocumentedModificationBitChangedNeedsExplicitPolicyReview'
        $r.UnspecifiedChangedBitCount | Should -Be 0
        $r.WriterPermit | Should -BeFalse
    }
    It 'rejects a changed READ bit even with no unknown bit' {
        $r=Get-OPA265BW4k7jFlagDifference -OriginalFlags 17 -DestinationFlags 16
        $r.Status | Should -BeExactly 'ReadOrAttachmentSemanticBitChangedStop'
        $r.ReadAndHasAttachBitsUnchanged | Should -BeFalse
    }
    It 'rejects a changed HASATTACH bit' {
        $r=Get-OPA265BW4k7jFlagDifference -OriginalFlags 17 -DestinationFlags 1
        $r.Status | Should -BeExactly 'ReadOrAttachmentSemanticBitChangedStop'
    }
    It 'rejects changes to documented submission flag even if read/attachment stable' {
        $r=Get-OPA265BW4k7jFlagDifference -OriginalFlags 21 -DestinationFlags 17
        $r.Status | Should -BeExactly 'DocumentedOperationalOrIdentityFlagChangedStop'
        $r.OtherDocumentedChangedBitCount | Should -Be 1
    }
    It 'retains unknown flag differences even when mfUnmodified is unchanged' {
        $r=Get-OPA265BW4k7jFlagDifference -OriginalFlags 65553 -DestinationFlags 17
        $r.UnspecifiedChangedBitCount | Should -Be 1
        $r.KnownModificationStateChangeCount | Should -Be 0
    }
    It 'detects unknown 0x00020000 as a separate bit and does not misname it' {
        $r=Get-OPA265BW4k7jFlagDifference -OriginalFlags 131089 -DestinationFlags 17
        $r.UnspecifiedChangedBitValues[0] | Should -Be 131072
        $r.ChangedBits[0].FlagName | Should -BeExactly 'UnspecifiedInReviewedMsOxcmsgTable'
    }
    It 'allows identical flags only as a read-only result, not production' {
        $r=Get-OPA265BW4k7jFlagDifference -OriginalFlags 17 -DestinationFlags 17
        $r.Status | Should -BeExactly 'IdenticalRawMessageFlagsReadOnly'
        $r.ChangedBitCount | Should -Be 0
        $r.ProductionReady | Should -BeFalse
    }
    It 'rejects negative MAPI flags' {
        {Get-OPA265BW4k7jFlagDifference -OriginalFlags -1 -DestinationFlags 17} | Should -Throw
    }
    It 'always reports read-only per-bit rows with no waiver' {
        $r=Get-BW4k7jOriginalSyntheticFlagReview
        @($r.ChangedBits | Where-Object {$_.AutomaticallyWaived}).Count | Should -Be 0
    }
}
Describe 'BW4k7j controller and origin evidence must remain immutable and read-only' {
    BeforeAll {
        $script:ctrl=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7jFlagPolicyReview.ps1') -Encoding UTF8 -Raw
        $script:worker=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7jRawMessageFlagPolicy265.ps1') -Encoding UTF8 -Raw
    }
    It 'requires exact original Claim and independent BW4k7i baseline SHA' {
        $script:ctrl | Should -Match '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        $script:ctrl | Should -Match 'f75594047529cca19bbeb8d2a52db5412187325a39db4d659dc85b4b41d44399'
    }
    It 'calls BW4k7i VerifyAfterReopen instead of a Move worker' {
        $script:ctrl | Should -Match 'Invoke-OPA265BW4k7iReopenIntegrityReview'
        $script:ctrl | Should -Match "Mode='VerifyAfterReopen'"
        $script:ctrl | Should -Not -Match '\$mail\.(Move|Save|Send|Delete)\s*\('
    }
    It 'writes no original Claim, Journal, PST or new snapshot files' {
        $script:ctrl | Should -Not -Match 'Write-OPA265BW4k7iBaselineOnce'
        $script:ctrl | Should -Not -Match 'Write-OPA265BW4k7gClaimOnce'
        $script:ctrl | Should -Not -Match 'FileMode.*CreateNew'
        $script:worker | Should -Not -Match 'FileMode.*CreateNew'
    }
    It 'reports unchanged historical postmove audit status, no proof of production' {
        $script:ctrl | Should -Match 'HistoricalPostmoveMismatchAutomaticallyReclassified=\$false'
        $script:ctrl | Should -Match 'PhysicalPstDurabilityFullyProven=\$false'
        $script:ctrl | Should -Match 'ProductionReady=\$false'
    }
    It 'never silently aliases STORE_HTML_OK from another MAPI property' {
        $script:ctrl | Should -Match 'STORE_HTML_OK;DifferentProperty'
    }
}
