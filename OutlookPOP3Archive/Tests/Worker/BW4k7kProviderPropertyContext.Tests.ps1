#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7kProviderPropertyContext265.ps1')
    function New-BW4k7kSample {
        [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7k.RawProviderPropertySample.1'
            MessageFlagsTag='0x0E070003';MessageFlags=[int]17
            MessageStatusTag='0x0E170003'
            MessageStatusAvailable=$true;MessageStatus=[int]0
            HasAttachmentsTag='0x0E1B000B'
            HasAttachments=$true;AttachmentCount=[int]1;UnRead=$false
            PstStorePathMatched=$true
            ExactDestinationEntryIdMatched=$true
            PropertyOrigin='ArchivedMailItem.PropertyAccessor'
        }
    }
}
Describe 'BW4k7k exact PST provider MAPI context: fail closed' {
    It 'stable raw reads classify only observed destination values' {
        $a=New-BW4k7kSample;$b=New-BW4k7kSample
        $r=Compare-OPA265BW4k7kPropertySamples -First $a -Second $b
        $r.Schema | Should -BeExactly '2.6.5-BW4k7k.ProviderContextClassification.1'
        $r.Status | Should -BeExactly 'ArchivedPstRawPropertiesStableUnknown0x00010000StillBlocked'
        $r.IndependentlySampledPropertyCount | Should -Be 2
        $r.DestinationMessageStatusAvailable | Should -BeTrue
        $r.DestinationMessageStatus | Should -Be 0
        $r.RawDestinationMessageFlags | Should -Be 17
        $r.OriginalMessageFlagsFromImmutableWitness | Should -Be 65555
        $r.ChangedMaskHex | Should -BeExactly '0x00010002'
    }
    It 'must not equate PR_MESSAGE_STATUS high-bit with PR_MESSAGE_FLAGS' {
        $a=New-BW4k7kSample;$b=New-BW4k7kSample
        $a.MessageStatus=[int]65536;$b.MessageStatus=[int]65536
        $r=Compare-OPA265BW4k7kPropertySamples -First $a -Second $b
        $r.DestinationMessageStatus | Should -Be 65536
        $r.CrossPropertyFlagEquivalenceAssumed | Should -BeFalse
        $r.Original0x00010000MeaningEstablished | Should -BeFalse
    }
    It 'absent PR_MESSAGE_STATUS stays absent, never coerced to zero' {
        $a=New-BW4k7kSample;$b=New-BW4k7kSample
        $a.MessageStatusAvailable=$false;$b.MessageStatusAvailable=$false
        $a.MessageStatus=$null;$b.MessageStatus=$null
        $r=Compare-OPA265BW4k7kPropertySamples -First $a -Second $b
        $r.DestinationMessageStatusAvailable | Should -BeFalse
        $null -eq $r.DestinationMessageStatus | Should -BeTrue
        $r.MessageStatusComparedToOriginal | Should -BeFalse
    }
    It 'partial availability across samples fails closed' {
        $a=New-BW4k7kSample;$b=New-BW4k7kSample
        $b.MessageStatusAvailable=$false;$b.MessageStatus=$null
        {Compare-OPA265BW4k7kPropertySamples -First $a -Second $b} | Should -Throw '*changed*'
    }
    It 'different status between reads fails closed' {
        $a=New-BW4k7kSample;$b=New-BW4k7kSample
        $b.MessageStatus=[int]1
        {Compare-OPA265BW4k7kPropertySamples -First $a -Second $b} | Should -Throw '*changed*'
    }
    It 'changed message flags fails closed' {
        $a=New-BW4k7kSample;$b=New-BW4k7kSample
        $b.MessageFlags=65553
        {Compare-OPA265BW4k7kPropertySamples -First $a -Second $b} | Should -Throw '*identity*'
    }
    It 'incorrect MAPI property tags fail closed' {
        $a=New-BW4k7kSample
        $a.MessageStatusTag='0x0E070003'
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'must not interpret STORE_HTML_OK as message flag' {
        $a=New-BW4k7kSample
        $a.MessageFlagsTag='0x340D0003'
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'invalid PR_HASATTACH fails closed' {
        $a=New-BW4k7kSample;$a.HasAttachments=$false
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'non-boolean PR_HASATTACH fails closed' {
        $a=New-BW4k7kSample;$a.HasAttachments=1
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'non-boolean UnRead fails closed' {
        $a=New-BW4k7kSample;$a.UnRead='False'
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'attachment count mismatch fails closed' {
        $a=New-BW4k7kSample;$a.AttachmentCount=0
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'wrong source PST identity fails closed' {
        $a=New-BW4k7kSample;$a.PstStorePathMatched=$false
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'wrong destination EntryID fails closed' {
        $a=New-BW4k7kSample;$a.ExactDestinationEntryIdMatched=$false
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'reported status available but non-integer fails closed' {
        $a=New-BW4k7kSample;$a.MessageStatus='65536'
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'reported status missing but stale value fails closed' {
        $a=New-BW4k7kSample;$a.MessageStatusAvailable=$false
        {Assert-OPA265BW4k7kPropertySample -Sample $a} | Should -Throw
    }
    It 'can never authorize retroactive flag waiver or Move' {
        $a=New-BW4k7kSample
        $r=Compare-OPA265BW4k7kPropertySamples -First $a -Second (New-BW4k7kSample)
        $r.ProviderSpecificFlagWaiver | Should -BeFalse
        $r.HistoricalRawUserStateHashMismatchReclassified | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
        $r.AutomaticRetryAllowed | Should -BeFalse
        $r.OutlookMoveExecuted | Should -BeFalse
        $r.OriginalClaimRewritten | Should -BeFalse
    }
    It 'controller chains existing BW4k7j and pins baseline without writes' {
        $p=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7kProviderPropertyReview.ps1'
        $text=Get-Content -LiteralPath $p -Raw -Encoding UTF8
        $text | Should -Match 'Invoke-OPA265BW4k7jFlagPolicyReview\.ps1'
        $text | Should -Match 'f75594047529cca19bbeb8d2a52db5412187325a39db4d659dc85b4b41d44399'
        $text | Should -Match '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        $text | Should -Match '0x0E070003'
        $text | Should -Match '0x0E170003'
        $text | Should -Match '0x0E1B000B'
        $text | Should -Not -Match '(?i)\$mail\.(Move|Save|Delete|Send)\s*\('
        $text | Should -Not -Match '(?i)\.SetProperty\s*\('
        $text | Should -Not -Match 'Write-OPA265BW4k7gClaimOnce'
    }
    It 'works across Russian and English PS5.1 exception texts' {
        $path=Join-Path $PSScriptRoot 'BW4k7dRecipientsFlags.Tests.ps1'
        $text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $text | Should -Match "Should -Throw # Locale-neutral"
        $text | Should -Not -Match 'Should -Throw .empty array.'
        $sample=New-BW4k7kSample
        $sample.MessageFlags=[int]18
        {Assert-OPA265BW4k7kPropertySample -Sample $sample} | Should -Throw
    }
}
