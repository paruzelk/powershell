#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7mFreshOneShotGuard265.ps1')
    function New-BW4k7mOriginal {
        $pins=Get-OPA265BW4k7mPins
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7l.FreshPreMoveMapiWitness.1'
            FixtureId=[string]$pins.FixtureId
            SourceEntryId=[string]$pins.SourceEntryId
            SourceFolderEntryId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
            SourceStoreIdSha256=('a'*64)
            InternetMessageId='<bw4k7m-new@example.test>'
            InternetMessageIdSha256=[string](Get-OPA265BW4k7lStringSha -Value '<bw4k7m-new@example.test>')
            SearchKeySha256=('b'*64)
            SubjectSha256=('c'*64)
            BodySha256=('d'*64)
            HtmlBodySha256=('e'*64)
            SenderSha256=('f'*64)
            ReceivedUtcTicks=[long]639292152776489017
            SentUtcTicks=[long]639292152776489000
            MessageSizeDiagnostic=[long]9000
            RecipientCount=1
            RecipientDigestSha256=[string]$pins.RecipientDigestSha256
            RawPrMessageFlags=65555
            RawPrMessageFlagsHex='0x00010013'
            PrMessageStatusAvailable=$true
            PrMessageStatus=[int]0
            PrHasAttach=$true
            UnRead=$false
            AttachmentCount=1
            AttachmentNameSha256=('1'*64)
            AttachmentByteLength=[long]1024
            AttachmentBytesSha256=[string]$pins.AttachmentBytesSha256
            RawFlag0x00010000BeforeMove=$true
            BeforeMove=$true
            OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false
            WriterPermit=$false
            ProductionReady=$false
        }
    }
    function New-BW4k7mEvidence {
        $pins=Get-OPA265BW4k7mPins
        $w=New-BW4k7mOriginal
        $w.InternetMessageIdSha256=Get-OPA265BW4k7lStringSha -Value ([string]$w.InternetMessageId)
        return [pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7l.ImmutablePreMoveEvidence.1'
            FixtureId=[string]$pins.FixtureId
            OutlookProfile='Outlook'
            SourcePst='C:\Pst\source.pst'
            DestinationPst='C:\Pst\dest.pst'
            DestinationStoreIdSha256=('2'*64)
            DestinationFolderEntryId=[string]$pins.DestinationFolderEntryId
            DestinationFolderItems=0
            SourceWitness=$w
            IndependentSourceReads=2
            PriorBW4k7gClaimMustRemainUntouched=[string]$pins.OldBW4k7gClaimSha256
            Original0x00010000MeaningEstablished=$false
            OriginalBW4k7gFlagMismatchWaived=$false
            OutlookMoveExecuted=$false
            AutomaticRetryAllowed=$false
            WriterPermit=$false
            ProductionReady=$false
        }
    }
    function Copy-BW4k7mWitness {
        param([psobject]$Witness)
        return ($Witness | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    }
}
Describe 'BW4k7m exact new immutable 1K fixture and claim safety guards' {
    It 'locks the exact operator original fixture GUID and original SHA256' {
        $p=Get-OPA265BW4k7mPins
        $p.FixtureId | Should -BeExactly 'd1a68868-acf5-4c70-860d-5521e1ce2836'
        $p.EvidenceSha256 | Should -BeExactly '36ca109b7905e0040e57c6b9e01d0858daefd2ae7c76daba5c091663bbe36c29'
    }
    It 'locks original single source EntryID and empty destination FolderEntryID' {
        $p=Get-OPA265BW4k7mPins
        $p.SourceEntryId | Should -BeExactly '00000000E1878292411BC64291BD506DCEFD2A3504B03C00'
        $p.DestinationFolderEntryId | Should -BeExactly '00000000E88584FF275FEE45B531E472CF338A8A82800000'
    }
    It 'locks original attachment, recipient and MessageId digests' {
        $p=Get-OPA265BW4k7mPins
        $p.AttachmentBytesSha256 | Should -BeExactly '2bce1ba628720664be4b9fdd77aae0678e5f0f3f02fc6ff641ec879094f6a404'
        $p.RecipientDigestSha256 | Should -BeExactly '11f0489518257c733d080dfe9e0d260b74e431746e48b383ce54fcda10f7e024'
        $p.InternetMessageIdSha256 | Should -BeExactly '77762cb8a7eb97f398920f228e30061e9a8bb35c4047a201d79ff0ec773df3de'
    }
    It 'keeps historic Claim and reopen SHA pinned unmodified' {
        $p=Get-OPA265BW4k7mPins
        $p.OldBW4k7gClaimSha256 | Should -BeExactly '325787fee94bf5c80e75e761cfc2a1724d94683204b73c2e03eaf384a530ba4c'
        $p.OldBW4k7iBaselineSha256 | Should -BeExactly 'f75594047529cca19bbeb8d2a52db5412187325a39db4d659dc85b4b41d44399'
    }
    It 'rejects another fixture id for irreversible Claim path' {
        {Get-OPA265BW4k7mClaimPath -FixtureId '87e72fd0-9e77-4098-a403-cbe99870b9e7'} | Should -Throw
    }
    It 'new Claim path is isolated from all previous suite locations' {
        $p=Get-OPA265BW4k7mPins
        $path=Get-OPA265BW4k7mClaimPath -FixtureId $p.FixtureId
        $path | Should -Match 'OutlookPOP3Archive-BW4k7m-OneShotClaims'
        $path | Should -Match 'd1a68868-acf5-4c70-860d-5521e1ce2836'
    }
    It 'never accepts an altered expected immutable evidence SHA' {
        $p=Get-OPA265BW4k7mPins
        {Read-OPA265BW4k7mSealedEvidence -FixtureId $p.FixtureId -ExpectedEvidenceSha256 ('0'*64)} | Should -Throw
    }
    It 'never accepts a different historical test fixture even with matching SHA' {
        $p=Get-OPA265BW4k7mPins
        {Read-OPA265BW4k7mSealedEvidence -FixtureId '87e72fd0-9e77-4098-a403-cbe99870b9e7' -ExpectedEvidenceSha256 $p.EvidenceSha256} | Should -Throw
    }
    It 'valid new sealed evidence structure is admissible before irreversible action' {
        (Assert-OPA265BW4k7mEvidence -Evidence (New-BW4k7mEvidence)) | Should -BeTrue
    }
    It 'unknown source 0x00010000 must be present in sealed original' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.RawFlag0x00010000BeforeMove=$false
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'wrong source PR_MESSAGE_FLAGS stops' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.RawPrMessageFlags=17
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'wrong separate original PR_MESSAGE_STATUS stops' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.PrMessageStatus=1
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'missing original PR_MESSAGE_STATUS availability stops' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.PrMessageStatusAvailable=$false
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'original has-attachment false stops' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.PrHasAttach=$false
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'original 1K byte digest drift stops' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.AttachmentBytesSha256=('0'*64)
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'original recipient digest drift stops' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.RecipientDigestSha256=('0'*64)
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'original MessageId digest drift stops' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.InternetMessageIdSha256=('0'*64)
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'source EntryID differs from exact new message stops' {
        $e=New-BW4k7mEvidence;$e.SourceWitness.SourceEntryId=('0'*48)
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'different archive FolderEntryID stops' {
        $e=New-BW4k7mEvidence;$e.DestinationFolderEntryId=('0'*48)
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'pre-capture destination item count must be zero' {
        $e=New-BW4k7mEvidence;$e.DestinationFolderItems=1
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'two original pre-Move reads must be recorded' {
        $e=New-BW4k7mEvidence;$e.IndependentSourceReads=1
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'original provider flag waiver is forbidden' {
        $e=New-BW4k7mEvidence;$e.OriginalBW4k7gFlagMismatchWaived=$true
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'pretending original Move occurred is rejected' {
        $e=New-BW4k7mEvidence;$e.OutlookMoveExecuted=$true
        {Assert-OPA265BW4k7mEvidence -Evidence $e} | Should -Throw
    }
    It 'valid live source must exactly match sealed source fields' {
        $e=New-BW4k7mEvidence;$live=Copy-BW4k7mWitness $e.SourceWitness
        (Assert-OPA265BW4k7mSourceEqualsSealed -Original $e.SourceWitness -Live $live) | Should -BeTrue
    }
    It 'live provider message size changes must halt Move, never silently waive' {
        $e=New-BW4k7mEvidence;$live=Copy-BW4k7mWitness $e.SourceWitness
        $live.MessageSizeDiagnostic=9001
        {Assert-OPA265BW4k7mSourceEqualsSealed -Original $e.SourceWitness -Live $live} | Should -Throw '*MessageSizeDiagnostic*'
    }
    It 'live PR_MESSAGE_FLAGS change must halt Move' {
        $e=New-BW4k7mEvidence;$live=Copy-BW4k7mWitness $e.SourceWitness
        $live.RawPrMessageFlags=17
        {Assert-OPA265BW4k7mSourceEqualsSealed -Original $e.SourceWitness -Live $live} | Should -Throw
    }
    It 'live attachment SHA mismatch must halt Move' {
        $e=New-BW4k7mEvidence;$live=Copy-BW4k7mWitness $e.SourceWitness
        $live.AttachmentBytesSha256=('9'*64)
        {Assert-OPA265BW4k7mSourceEqualsSealed -Original $e.SourceWitness -Live $live} | Should -Throw
    }
    It 'missing live content field must halt Move' {
        $e=New-BW4k7mEvidence;$live=Copy-BW4k7mWitness $e.SourceWitness
        [void]$live.PSObject.Properties.Remove('BodySha256')
        {Assert-OPA265BW4k7mSourceEqualsSealed -Original $e.SourceWitness -Live $live} | Should -Throw
    }
    It 'never makes a Claim without exact pinned original SHA' {
        $e=New-BW4k7mEvidence
        {New-OPA265BW4k7mAttemptClaim -Evidence $e -EvidenceSha256 ('0'*64)} | Should -Throw
    }
    It 'new irreversible Claim is initially nonpermissive for production/retry' {
        $e=New-BW4k7mEvidence;$p=Get-OPA265BW4k7mPins
        $claim=New-OPA265BW4k7mAttemptClaim -Evidence $e -EvidenceSha256 $p.EvidenceSha256
        $claim.OneIrreversibleMoveAttemptClaimed | Should -BeTrue
        $claim.AllowAutomaticRetry | Should -BeFalse
        $claim.AllowJournalWrite | Should -BeFalse
        $claim.HistoricalFlagMismatchWaived | Should -BeFalse
        $claim.ProductionReady | Should -BeFalse
    }
    It 'new irreversible Claim pins this new email and original evidence' {
        $e=New-BW4k7mEvidence;$p=Get-OPA265BW4k7mPins
        $claim=New-OPA265BW4k7mAttemptClaim -Evidence $e -EvidenceSha256 $p.EvidenceSha256
        $claim.FixtureId | Should -BeExactly $p.FixtureId
        $claim.EvidenceSha256 | Should -BeExactly $p.EvidenceSha256
        $claim.SourceEntryId | Should -BeExactly $p.SourceEntryId
    }
    It 'CreateNew flushed Claim persists once then prevents the next Move' {
        $old=$env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA=$TestDrive
            $e=New-BW4k7mEvidence;$p=Get-OPA265BW4k7mPins
            $claim=New-OPA265BW4k7mAttemptClaim -Evidence $e -EvidenceSha256 $p.EvidenceSha256
            $written=Write-OPA265BW4k7mClaimOnce -Claim $claim
            $written.IrreversibleClaimCreated | Should -BeTrue
            $written.ClaimSha256 | Should -Match '^[a-f0-9]{64}$'
            (Get-FileHash -LiteralPath $written.ClaimPath -Algorithm SHA256).Hash.ToLowerInvariant() | Should -BeExactly $written.ClaimSha256
            {Assert-OPA265BW4k7mNeverAttempted -FixtureId $p.FixtureId} | Should -Throw '*NEVER RETRY*'
            {Write-OPA265BW4k7mClaimOnce -Claim $claim} | Should -Throw
        }finally{$env:LOCALAPPDATA=$old}
    }
    It 'forged Claim with automatic retry allowed must never be written' {
        $e=New-BW4k7mEvidence;$p=Get-OPA265BW4k7mPins
        $claim=New-OPA265BW4k7mAttemptClaim -Evidence $e -EvidenceSha256 $p.EvidenceSha256
        $claim.AllowAutomaticRetry=$true
        {Write-OPA265BW4k7mClaimOnce -Claim $claim} | Should -Throw
    }
    It 'forged Claim with journal writing allowed must never be written' {
        $e=New-BW4k7mEvidence;$p=Get-OPA265BW4k7mPins
        $claim=New-OPA265BW4k7mAttemptClaim -Evidence $e -EvidenceSha256 $p.EvidenceSha256
        $claim.AllowJournalWrite=$true
        {Write-OPA265BW4k7mClaimOnce -Claim $claim} | Should -Throw
    }
    It 'forged historical waiver Claim must never be written' {
        $e=New-BW4k7mEvidence;$p=Get-OPA265BW4k7mPins
        $claim=New-OPA265BW4k7mAttemptClaim -Evidence $e -EvidenceSha256 $p.EvidenceSha256
        $claim.HistoricalFlagMismatchWaived=$true
        {Write-OPA265BW4k7mClaimOnce -Claim $claim} | Should -Throw
    }
    It 'independent archive comparison classifies exactly the unknown bit without waiver' {
        $source=New-BW4k7mOriginal;$dest=Copy-BW4k7mWitness $source
        $dest.RawPrMessageFlags=17;$dest.RawPrMessageFlagsHex='0x00000011'
        $dest.RawFlag0x00010000BeforeMove=$false
        $comp=Get-OPA265BW4k7mContentComparison -Original $source -Destination $dest
        $comp.Status | Should -BeExactly 'ContentMatchRawPrMessageFlagsDriftUnclassifiedManualReview'
        $comp.ChangedMaskHex | Should -BeExactly '0x00010002'
        $comp.Unresolved0x00010000Changed | Should -BeTrue
        $comp.FullSemanticContentMatch | Should -BeTrue
        $comp.WriterPermit | Should -BeFalse
        $comp.HistoricalRawStateMismatchWaived | Should -BeFalse
    }
    It 'separate status property change cannot be ignored' {
        $source=New-BW4k7mOriginal;$dest=Copy-BW4k7mWitness $source
        $dest.PrMessageStatus=1
        $comp=Get-OPA265BW4k7mContentComparison -Original $source -Destination $dest
        $comp.Status | Should -BeExactly 'SeparatePrMessageStatusDriftNeedsManualReview'
        $comp.SeparatePrMessageStatusEqual | Should -BeFalse
    }
    It 'missing separate status property after Move is distinguishable from zero' {
        $source=New-BW4k7mOriginal;$dest=Copy-BW4k7mWitness $source
        $dest.PrMessageStatusAvailable=$false;$dest.PrMessageStatus=$null
        $comp=Get-OPA265BW4k7mContentComparison -Original $source -Destination $dest
        $comp.Status | Should -BeExactly 'SeparatePrMessageStatusDriftNeedsManualReview'
    }
    It 'attachment byte corruption after Move defeats semantic match' {
        $source=New-BW4k7mOriginal;$dest=Copy-BW4k7mWitness $source
        $dest.AttachmentBytesSha256=('8'*64)
        $comp=Get-OPA265BW4k7mContentComparison -Original $source -Destination $dest
        $comp.Status | Should -BeExactly 'ContentOrIdentityDriftNeedsManualReview'
        $comp.SemanticFieldMismatches | Should -Contain 'AttachmentBytesSha256'
    }
    It 'recipient change after Move defeats semantic match' {
        $source=New-BW4k7mOriginal;$dest=Copy-BW4k7mWitness $source
        $dest.RecipientDigestSha256=('0'*64)
        $comp=Get-OPA265BW4k7mContentComparison -Original $source -Destination $dest
        $comp.Status | Should -BeExactly 'ContentOrIdentityDriftNeedsManualReview'
    }
    It 'a provider MessageSize drift is separate, never automatically waived' {
        $source=New-BW4k7mOriginal;$dest=Copy-BW4k7mWitness $source
        $dest.MessageSizeDiagnostic=9050
        $comp=Get-OPA265BW4k7mContentComparison -Original $source -Destination $dest
        $comp.Status | Should -BeExactly 'ContentMatchProviderMessageSizeDriftNeedsManualReview'
        $comp.ProviderMessageSizeDrift | Should -BeTrue
        $comp.ProductionReady | Should -BeFalse
    }
    It 'matching content+flags still never grants production or automatic retry' {
        $source=New-BW4k7mOriginal;$dest=Copy-BW4k7mWitness $source
        $comp=Get-OPA265BW4k7mContentComparison -Original $source -Destination $dest
        $comp.Status | Should -BeExactly 'ContentAndObservedMapiPropertiesMatchReadOnlyNoProductionPermit'
        $comp.ProductionReady | Should -BeFalse
        $comp.WriterPermit | Should -BeFalse
        $comp.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'unrelated Outlook sender drift is never ignored after Move' {
        $source=New-BW4k7mOriginal;$dest=Copy-BW4k7mWitness $source
        $dest.SenderSha256=('4'*64)
        $comp=Get-OPA265BW4k7mContentComparison -Original $source -Destination $dest
        $comp.SemanticFieldMismatches | Should -Contain 'SenderSha256'
    }
    It 'controller explicitly requires fresh isolated Execute consent and claim-before-Move' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7mFreshOneShotMove.ps1'
        $source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $source | Should -Match "ValidateSet\('Review','Execute'\)"
        $source | Should -Match 'ConfirmOneShotFreshMove'
        $source | Should -Match 'MOVE EXACT ONE BW4K7M'
        $source | Should -Match 'Read-OPA265BW4k7mSealedEvidence'
        $source | Should -Match 'Get-OPA265BW4cPop3Store'
        $source | Should -Match 'GetDefaultFolder\(6\)'
        $source | Should -Match 'Selection\.Count -ne 1'
        $source | Should -Match 'Write-OPA265BW4k7mClaimOnce'
        $source | Should -Match '\$mail\.Move\(\$destinationFolder\)'
        $source | Should -Match 'ShouldProcess'
        $source | Should -Not -Match '(?i)\$mail\.(Save|Delete|Send)\s*\('
    }
    It 'independent post-Move audit has no Move or evidence modification route' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7mIndependentPostMoveAudit.ps1'
        $source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $source | Should -Match 'ExpectedClaimSha256'
        $source | Should -Match 'Get-OPA265BW4k7mContentComparison'
        $source | Should -Match 'SourceMessageIdMatches=0'
        $source | Should -Match 'DestinationMessageIdMatches=1'
        $source | Should -Not -Match '(?i)\.(Move|Save|Delete|Send|SetProperty)\s*\('
        $source | Should -Not -Match 'Write-OPA265BW4k7mClaimOnce'
    }
    It 'only one Outlook Move call exists and historical BW4k7g is not invoked' {
        $path=Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7mFreshOneShotMove.ps1'
        $source=Get-Content -LiteralPath $path -Raw -Encoding UTF8
        @([regex]::Matches($source,'(?i)\$mail\.Move\s*\(')).Count | Should -Be 1
        $source | Should -Not -Match 'Invoke-OPA265BW4k7gOneShotAttachmentMove|Write-OPA265BW4k7gClaimOnce'
        $source | Should -Match 'AutomaticRetryAllowed=\$false'
    }
}
