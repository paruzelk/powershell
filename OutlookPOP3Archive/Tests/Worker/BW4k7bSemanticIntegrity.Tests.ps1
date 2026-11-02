#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7bSemanticIntegrity265.ps1')
    function New-BW4k7bLiveDossier {
        [pscustomobject]@{
            Schema='2.6.5-BW4k7a.Attachment1KOriginalSizeDriftReadOnlyReview.1'
            Status='OnlySourceMailItemSizeDriftUnapproved'
            SuiteId='74912f94-d523-4856-9efd-d5528a92426f'
            TestId='87e72fd0-9e77-4098-a403-cbe99870b9e7'
            CaseName='Attachment1K'
            OriginalSourceEvidenceSha256='0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0'
            FiveEvidenceSetSha256='ce76abc7f4752e1a2b477730fad69e82332398560b73355aec82f2203e24a3d3'
            OriginalSourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35A46D3C00'
            SourceFolderEntryId='00000000E1878292411BC64291BD506DCEFD2A3582800000'
            OriginalSize=8122
            CurrentSize=8634
            DeltaSize=512
            OriginalAttachmentByteCount=1024
            CurrentAttachmentByteCount=1024
            OriginalAttachmentSha256='8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'
            CurrentAttachmentSha256='8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9'
            AttachmentByteExactMatch=$true
            OtherFieldMismatchCount=0
            OtherFieldMismatchNames=@()
            ReadOnlyWitnessCount=2
            SourceMapiPropertyCount=15
            SourceMapiAvailableCount=12
            LiveMapiMessageSize='8634'
            LiveMapiMessageFlags='65555'
            OriginalThreeMoveClaimsUnchanged=$true
            OriginalSevenHistoricalHashesUnchanged=$true
            OriginalWitnessUnchanged=$true
            SizeDriftAccepted=$false
            AttemptClaimWritten=$false
            OutlookMoveExecuted=$false
            CanRetryMove=$false
            ProductionReady=$false
        }
    }
    function New-BW4k7bSyntheticMove {
        $s='74912f94-d523-4856-9efd-d5528a92426f'
        $id='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        $case=[pscustomobject]@{Name='Attachment1K';TestId=$id;ExpectedAttachmentCount=1;MinimumAttachmentBytes=1024}
        $src=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4j.MultiFormatMailWitness.1'
            SuiteId=$s;CaseName='Attachment1K';TestId=$id
            ProfileName='Outlook';EntryId='SRC-ENTRY';FolderEntryId='SRC-FOLDER'
            StoreId='SRC-STORE';InternetMessageId='<synthetic@example.test>'
            SearchKeySha256=('a'*64)
            SubjectUtf8Sha256=('b'*64);SenderUtf8Sha256=('c'*64)
            BodyUtf8Sha256=('d'*64);HtmlBodyUtf8Sha256=('e'*64)
            SubjectLength=48;BodyLength=120;HtmlBodyLength=300;Size=8122
            ReceivedUtcTicks=639291968050000000
            Attachments=@([pscustomobject][ordered]@{
                Index=1;FileName='synthetic.bin';ByteCount=1024;Sha256=('f'*64)
            })
            OutlookMoveExecuted=$false;ProductionReady=$false
        }
        $dst=$src | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $dst.EntryId='DST-ENTRY'
        $dst.FolderEntryId='DST-FOLDER'
        $dst.StoreId='DST-STORE'
        $dst.Size=8634
        [pscustomobject]@{Source=$src;Destination=$dst;Case=$case;SuiteId=$s}
    }
}
Describe 'BW4k7b SEM-001 original 1 KiB live source size-drift evidence, no waiver' {
    BeforeEach {
        $script:r=New-BW4k7bLiveDossier
    }
    It 'accepts exactly the original source evidence for read-only semantic classification' {
        (Assert-OPA265BW4k7bExactReadOnlySourceDossier -Report $script:r) | Should -BeTrue
    }
    It 'reports content witness matched while explicitly withholding every write permit' {
        $v=Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r
        $v.Status | Should -BeExactly 'ContentWitnessMatchedSourceSizeDriftStillUnapproved'
        $v.WriterPermit | Should -BeFalse
        $v.SizeDriftAccepted | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
    }
    It 'never asserts source-to-destination comparison for the unmoved attachment' {
        $v=Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r
        $v.CrossStoreDestinationVerified | Should -BeFalse
        $v.SourceMailMoveAttempted | Should -BeFalse
        $v.PhysicalPstDurabilityProven | Should -BeFalse
    }
    It 'does not claim recipients or flags were fully captured' {
        $v=Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r
        $v.ContentCoverageIncludesFullRecipients | Should -BeFalse
        $v.SemanticFlagMaskDefinedForProduction | Should -BeFalse
    }
    It 'does not equate old +38 byte target changes to current +512 source drift' {
        $script:r.DeltaSize=38
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*Size/MAPI*'
    }
    It 'refuses a changed current live message size' {
        $script:r.CurrentSize=8635
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*Size/MAPI*'
    }
    It 'refuses an inconsistent current PR_MESSAGE_SIZE' {
        $script:r.LiveMapiMessageSize='9000'
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*Size/MAPI*'
    }
    It 'refuses changed live MAPI flags until independently investigated' {
        $script:r.LiveMapiMessageFlags='1'
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*Size/MAPI*'
    }
    It 'refuses changed attachment bytes even if size is unchanged' {
        $script:r.CurrentAttachmentSha256=('a'*64)
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*attachment*'
    }
    It 'refuses changed original attachment SHA-256' {
        $script:r.OriginalAttachmentSha256=('a'*64)
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*attachment*'
    }
    It 'refuses changed attachment size' {
        $script:r.CurrentAttachmentByteCount=1025
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*attachment*'
    }
    It 'refuses false attachment matching assertion' {
        $script:r.AttachmentByteExactMatch=$false
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*attachment*'
    }
    It 'refuses any changed original content witness field' {
        $script:r.OtherFieldMismatchCount=1
        $script:r.OtherFieldMismatchNames=@('HtmlBodyUtf8Sha256')
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*semantic source*'
    }
    It 'refuses an altered historical claim seal' {
        $script:r.OriginalThreeMoveClaimsUnchanged=$false
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*historical chain*'
    }
    It 'refuses original source evidence changes' {
        $script:r.OriginalSourceEvidenceSha256=('b'*64)
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*identity/evidence*'
    }
    It 'refuses false legacy journal quarantine' {
        $script:r.OriginalSevenHistoricalHashesUnchanged=$false
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*historical chain*'
    }
    It 'refuses an existing write attempt' {
        $script:r.AttemptClaimWritten=$true
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*AttemptClaimWritten*'
    }
    It 'refuses an invented size acceptance' {
        $script:r.SizeDriftAccepted=$true
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*SizeDriftAccepted*'
    }
    It 'refuses an invented production-ready assertion' {
        $script:r.ProductionReady=$true
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*ProductionReady*'
    }
    It 'requires 2 stable live witnesses for source diagnosis' {
        $script:r.ReadOnlyWitnessCount=1
        {Get-OPA265BW4k7bSourceSemanticVerdict -Report $script:r} | Should -Throw '*Size/MAPI*'
    }
}
Describe 'BW4k7b SEM-001 synthetic cross-store semantic comparison, read-only' {
    BeforeEach {
        $script:c=New-BW4k7bSyntheticMove
        $script:inputs=@{
            Source=$script:c.Source;Destination=$script:c.Destination
            Case=$script:c.Case;SuiteId=$script:c.SuiteId
            SourceMessageIdMatches=0;DestinationMessageIdMatches=1
            CompleteSourceAndDestinationScans=$true
        }
    }
    It 'recognizes matching content despite 512 extra bytes in target, never issues writer permit' {
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'CapturedSemanticContentMatchedReadOnlyNoWriterPermit'
        $v.DeltaSize | Should -Be 512
        $v.WriterPermit | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
    }
    It 'recognizes unchanged logical content at identical sizes without declaring MAPI byte equality' {
        $script:c.Destination.Size=8122
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.SizeEqual | Should -BeTrue
        $v.BytewiseAllMapiEqualityRequired | Should -BeFalse
        $v.WriterPermit | Should -BeFalse
    }
    It 'does not treat source/target EntryId equality as normal cross-PST identity' {
        $script:c.Destination.EntryId='SRC-ENTRY'
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_StoreOrMessageIdentityMismatch'
    }
    It 'does not treat source/target folder equality as normal cross-PST identity' {
        $script:c.Destination.FolderEntryId='SRC-FOLDER'
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_StoreOrMessageIdentityMismatch'
    }
    It 'blocks same source and target StoreID' {
        $script:c.Destination.StoreId='SRC-STORE'
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_StoreOrMessageIdentityMismatch'
    }
    It 'blocks InternetMessageId changed' {
        $script:c.Destination.InternetMessageId='<different@example.test>'
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_StoreOrMessageIdentityMismatch'
    }
    It 'blocks changed search key without a new separately approved identity rule' {
        $script:c.Destination.SearchKeySha256=('7'*64)
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_StoreOrMessageIdentityMismatch'
    }
    It 'blocks changed Body despite equal reported message size' {
        $script:c.Destination.Size=8122
        $script:c.Destination.BodyUtf8Sha256=('9'*64)
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_MailContentOrAttachmentMismatch'
    }
    It 'blocks changed HTMLBody digest' {
        $script:c.Destination.HtmlBodyUtf8Sha256=('9'*64)
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_MailContentOrAttachmentMismatch'
    }
    It 'blocks changed sender' {
        $script:c.Destination.SenderUtf8Sha256=('9'*64)
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_MailContentOrAttachmentMismatch'
    }
    It 'blocks changed received time' {
        $script:c.Destination.ReceivedUtcTicks=639291968050000001
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_MailContentOrAttachmentMismatch'
    }
    It 'blocks changed attachment payload SHA' {
        $script:c.Destination.Attachments[0].Sha256=('9'*64)
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_MailContentOrAttachmentMismatch'
        $v.AttachmentBytesMatch | Should -BeFalse
    }
    It 'blocks changed attachment length' {
        $script:c.Destination.Attachments[0].ByteCount=1025
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_MailContentOrAttachmentMismatch'
    }
    It 'blocks a second destination match' {
        $script:inputs.DestinationMessageIdMatches=2
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_IncompleteOrAmbiguousSourceTargetScan'
    }
    It 'blocks original source mail remaining after claimed move' {
        $script:inputs.SourceMessageIdMatches=1
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_IncompleteOrAmbiguousSourceTargetScan'
    }
    It 'blocks missing explicit complete-scan witness' {
        $script:inputs.CompleteSourceAndDestinationScans=$false
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.Status | Should -BeExactly 'STOP_IncompleteOrAmbiguousSourceTargetScan'
    }
    It 'never pretends it captured full recipients and user flags' {
        $v=Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs
        $v.RecipientCoverageComplete | Should -BeFalse
        $v.SemanticFlagCoverageComplete | Should -BeFalse
        $v.ContentOnlyEvidenceInsufficientForProduction | Should -BeTrue
    }
    It 'refuses malformed invented destination witness schema' {
        $script:c.Destination | Add-Member -NotePropertyName AllowMove -NotePropertyValue $true
        {Compare-OPA265BW4k7bSyntheticMoveContentReadOnly @inputs} | Should -Throw '*schema*'
    }
    It 'read-only diagnostic has no Claim writer or MailItem.Move' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7bSemanticSourceReview.ps1') -Raw -Encoding UTF8
        $src | Should -Match 'Invoke-OPA265BW4k7aAttachmentSizeDriftReview'
        $src | Should -Match 'Get-OPA265BW4k7bSourceSemanticVerdict'
        $src | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\s*\('
        $src | Should -Not -Match 'Write-OPA265BW4'
    }
}
