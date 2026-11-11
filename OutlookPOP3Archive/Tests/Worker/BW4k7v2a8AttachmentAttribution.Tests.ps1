#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7v2a8AttachmentAttributionPolicy265.ps1')
    $script:controller=Get-Content -LiteralPath (
        Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7v2a8ReadOnlyAttachmentAttribution.ps1') -Raw -Encoding UTF8
    function New-BW4k7v2a8Fixture {
        $m=[pscustomobject]@{
            SuiteId='1a6683eb-3136-46eb-a1a8-ed8ece33b52c'
            SourceEntryId='ORIGINALSOURCE'
            TargetStoreId='TARGETSTORE'
            TargetFolderId='TARGETFOLDER'
            SourceRawMapiFlags=9
            SourceSizeBytes=1952
        }
        $c=[pscustomobject]@{
            SuiteId=$m.SuiteId
            SourceEntryId=$m.SourceEntryId
            TargetStoreId=$m.TargetStoreId
            TargetFolderId=$m.TargetFolderId
        }
        $s=[pscustomobject]@{
            OutlookRestartConfirmed=$true
            SourceMatches=0;DestinationMatches=1
            DestinationIdentityMatchesPinned=$true
            SemanticSha256MatchesManifest=$true
            DestinationRawMapiFlags=25
            DestinationSizeBytes=2076
            AttachmentCountReadComplete=$true
            DestinationAttachmentsCount=1
            AttachmentSummaries=@([pscustomobject]@{Type=1;SizeBytes=124})
            PrHasAttachAvailable=$true
            PrHasAttach=$true
        }
        return @{Manifest=$m;Claim=$c;Snapshot=$s}
    }
}
Describe 'BW4k7v2a8 exact post-Move HASATTACH and size read-only attribution' {
    It 'recognizes exact prior +16 bit flag transition' {
        $p=New-BW4k7v2a8Fixture
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).HasAttachBitIntroduced | Should -BeTrue
    }
    It 'recognizes MSGFLAG_HASATTACH bit 0x10' {
        $p=New-BW4k7v2a8Fixture
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).ChangedFlagsXor | Should -Be 16
    }
    It 'recognizes 9 means read and unsent without hasattach' {
        $p=New-BW4k7v2a8Fixture
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).OriginalRawMapiFlags | Should -Be 9
    }
    It 'recognizes 25 means read unsent and hasattach' {
        $p=New-BW4k7v2a8Fixture
        $r=Test-OPA265BW4k7v2a8FlagsAndAttachments @p
        $r.DestinationRawMapiFlags | Should -Be 25
        $r.DestinationFlagHasAttach | Should -BeTrue
    }
    It 'classifies attachment objects but leaves their origin unknown' {
        $p=New-BW4k7v2a8Fixture
        $r=Test-OPA265BW4k7v2a8FlagsAndAttachments @p
        $r.Attribution | Should -BeExactly 'DestinationAttachmentObjectsExistOriginalPreMoveCountUnknown'
        $r.OriginalPreMoveAttachmentCountKnown | Should -BeFalse
    }
    It 'never infers attachment absence in the original source' {
        $p=New-BW4k7v2a8Fixture
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).OriginalPreMoveAttachmentCountKnown | Should -BeFalse
    }
    It 'classifies HASATTACH without any visible Outlook attachment objects' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.DestinationAttachmentsCount=0
        $p.Snapshot.AttachmentSummaries=@()
        $r=Test-OPA265BW4k7v2a8FlagsAndAttachments @p
        $r.Attribution | Should -BeExactly 'HasAttachBitSetButNoAttachmentObjectsVisible'
    }
    It 'reports contradiction between PR_HASATTACH and empty collection' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.DestinationAttachmentsCount=0;$p.Snapshot.AttachmentSummaries=@()
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'PrHasAttachDisagreesWithAttachmentCount'
    }
    It 'reports contradiction when PR_HASATTACH Boolean is false but flag is set' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.PrHasAttach=$false
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'PrHasAttachDisagreesWithMessageFlag'
    }
    It 'blocks missing PR_HASATTACH property rather than assuming false' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.PrHasAttachAvailable=$false;$p.Snapshot.PrHasAttach=$null
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons | Should -Contain 'PrHasAttachUnavailable'
    }
    It 'does not classify absent PR_HASATTACH as proof no attachments' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.PrHasAttachAvailable=$false
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).DestinationPrHasAttachAvailable | Should -BeFalse
    }
    It 'rejects missing attachment enumeration completeness' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.AttachmentCountReadComplete=$false
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Status |
            Should -BeExactly 'ObservedMismatchOrIncompleteReadRequiresManualReview'
    }
    It 'rejects attachment count inconsistent with returned rows' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.AttachmentSummaries=@()
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'AttachmentMetadataIncomplete'
    }
    It 'rejects more than sixteen attachment objects in a bounded diagnostic' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.DestinationAttachmentsCount=17
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'AttachmentCountNotVerified'
    }
    It 'rejects negative attachment count' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.DestinationAttachmentsCount=-1
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'AttachmentCountNotVerified'
    }
    It 'flags changed original source size' {
        $p=New-BW4k7v2a8Fixture
        $p.Manifest.SourceSizeBytes=1953
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'OperatorObservedSizeDeltaNotStable'
    }
    It 'flags changed destination size' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.DestinationSizeBytes=2200
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'OperatorObservedSizeDeltaNotStable'
    }
    It 'records exactly 124-byte previously observed size drift' {
        $p=New-BW4k7v2a8Fixture
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).ObservedSizeDeltaBytes | Should -Be 124
    }
    It 'does not attribute 124 bytes to attachments without source inventory' {
        $p=New-BW4k7v2a8Fixture
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).SizeDeltaRootCauseProven | Should -BeFalse
    }
    It 'flags another MAPI bit transition as not the observed event' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.DestinationRawMapiFlags=9
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'OperatorObservedFlagDeltaNotStable'
    }
    It 'flags a missing Outlook restart' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.OutlookRestartConfirmed=$false
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'NewOutlookProcessNotConfirmed'
    }
    It 'flags source count nonzero' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.SourceMatches=1
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'OriginalSourceZeroDestinationOneNotVerified'
    }
    It 'flags target count zero' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.DestinationMatches=0
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'OriginalSourceZeroDestinationOneNotVerified'
    }
    It 'flags wrong pinned target EntryId or folder' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.DestinationIdentityMatchesPinned=$false
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'DestinationEntryIdOrFolderMismatch'
    }
    It 'flags changed semantic Body hash after previous success' {
        $p=New-BW4k7v2a8Fixture
        $p.Snapshot.SemanticSha256MatchesManifest=$false
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'SyntheticSemanticContentChanged'
    }
    It 'flags claimant with wrong target StoreId' {
        $p=New-BW4k7v2a8Fixture
        $p.Claim.TargetStoreId='OTHER'
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'ClaimAndManifestIdentityMismatch'
    }
    It 'flags claimant with wrong source EntryId' {
        $p=New-BW4k7v2a8Fixture
        $p.Claim.SourceEntryId='OTHER'
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).Reasons |
            Should -Contain 'ClaimAndManifestIdentityMismatch'
    }
    It 'does not report semantic success as production safety' {
        $p=New-BW4k7v2a8Fixture
        $r=Test-OPA265BW4k7v2a8FlagsAndAttachments @p
        $r.SemanticContentPreservedByCurrentWitness | Should -BeTrue
        $r.SEM001ProductionIntegrityProven | Should -BeFalse
    }
    It 'never waives unknown MAPI flag drift' {
        $p=New-BW4k7v2a8Fixture
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).AnyMapiFlagDriftWaived | Should -BeFalse
    }
    It 'never enables Move retry' {
        $p=New-BW4k7v2a8Fixture
        (Test-OPA265BW4k7v2a8FlagsAndAttachments @p).OldMoveMayBeRetried | Should -BeFalse
    }
    It 'never enables production writer' {
        $p=New-BW4k7v2a8Fixture
        $r=Test-OPA265BW4k7v2a8FlagsAndAttachments @p
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'pins exact original SuiteId manifest and claim hashes' {
        $script:controller | Should -Match '1a6683eb-3136-46eb-a1a8-ed8ece33b52c'
        $script:controller | Should -Match '77311b1df742545e15c01d755858b31395e76446fd4d43497775b2bed98bc2f1'
        $script:controller | Should -Match 'ff4093e90fb7663d514085f087ea2cd46fde6c7c6bdb23b36f38ba41c1aa21a2'
    }
    It 'pins original destination EntryId and Move return SHA' {
        $script:controller | Should -Match '00000000D2D5FCF473B27142BB218ABB3C07996824002000'
        $script:controller | Should -Match '9a89be00eeb85163afd557494bf16b7999c45f388fd7a25c59c35ccc65bf62cc'
    }
    It 'only reads original exact synthetic subject in default Drafts and PST folder' {
        $script:controller | Should -Match 'GetDefaultFolder\(16\)'
        $script:controller | Should -Match '\$drafts\.Items\.Restrict'
        $script:controller | Should -Match '\$targetFolder\.Items\.Restrict'
    }
    It 'does not touch any other mailbox message body' {
        $script:controller | Should -Match '\$ns.GetItemFromID\(\$ExpectedDestinationEntryId'
        $script:controller | Should -Match '\$item\.Body'
    }
    It 'records only attachment metadata and not filename or content' {
        $script:controller | Should -Match 'HiddenPropertyAvailable'
        $script:controller | Should -Match 'AttachMethodAvailable'
        $script:controller | Should -Match 'AttachFlagsAvailable'
        $script:controller | Should -Not -Match 'attachment\.FileName|attachment\.DisplayName|attachment\.SaveAsFile'
    }
    It 'forbids any Outlook COM writer or PST mount' {
        $script:controller | Should -Not -Match '\.(Save|Move|Send|Delete|AddStore|AddStoreEx|RemoveStore|CreateItem)\s*\('
        $script:controller | Should -Not -Match 'New-Object -ComObject'
    }
    It 'forbids evidence-file mutation or mailbox cleanup' {
        $script:controller | Should -Not -Match 'WriteAllText|WriteAllBytes|CreateDirectory|FileMode]::CreateNew|Remove-Item'
    }
    It 'does not leak raw Body or attachments from result' {
        $script:controller | Should -Match 'RawBodyAttachmentContentFileNamesOrSignaturesReturned=\$false'
        $script:controller | Should -Not -Match 'RawBody\s*='
    }
    It 'no source before-Move attachment count inferred from flags' {
        $script:controller | Should -Match 'SourceRawMapiFlags'
        $script:controller | Should -Match 'AttachmentCountReadComplete'
    }
}