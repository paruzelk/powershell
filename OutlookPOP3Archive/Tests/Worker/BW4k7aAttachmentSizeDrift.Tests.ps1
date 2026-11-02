#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7aAttachmentSizeDriftReadOnly265.ps1')
    function New-BW4k7aFixture {
        $suite='74912f94-d523-4856-9efd-d5528a92426f'
        $tid='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        $case=[pscustomobject]@{
            Name='Attachment1K';TestId=$tid;ExpectedAttachmentCount=1
            MinimumAttachmentBytes=1024
        }
        $w=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4j.MultiFormatMailWitness.1'
            SuiteId=$suite;CaseName='Attachment1K';TestId=$tid
            ProfileName='Outlook';EntryId='EXACT-SOURCE';FolderEntryId='EXACT-INBOX'
            StoreId='EXACT-POP3';InternetMessageId='<synthetic@example.test>'
            SearchKeySha256=('a'*64)
            SubjectUtf8Sha256=('b'*64);SenderUtf8Sha256=('c'*64)
            BodyUtf8Sha256=('d'*64);HtmlBodyUtf8Sha256=('e'*64)
            SubjectLength=48;BodyLength=120;HtmlBodyLength=300;Size=12000
            ReceivedUtcTicks=639291968050000000
            Attachments=@([pscustomobject][ordered]@{
                Index=1;FileName='synthetic.bin';ByteCount=1024;Sha256=('f'*64)
            })
            OutlookMoveExecuted=$false;ProductionReady=$false
        }
        $clone=$w | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        [pscustomobject]@{Source=$w;Current=$clone;Case=$case;SuiteId=$suite}
    }
}
Describe 'BW4k7a source-only exact 1KiB attachment size-drift diagnosis, no consent' {
    BeforeEach {
        $script:sample=New-BW4k7aFixture
        $script:args=@{
            Original=$script:sample.Source;Current=$script:sample.Current
            Case=$script:sample.Case;SuiteId=$script:sample.SuiteId
        }
    }
    It 'classifies exactly one MailItem.Size drift as unapproved' {
        $script:sample.Current.Size=12007
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.Status | Should -BeExactly 'OnlySourceMailItemSizeDriftUnapproved'
        $r.DeltaSize | Should -Be 7
        $r.OnlySizeDrift | Should -BeTrue
    }
    It 'also classifies negative source size drift without permission' {
        $script:sample.Current.Size=11992
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.DeltaSize | Should -Be -8
        $r.SizeDriftAccepted | Should -BeFalse
    }
    It 'does not blanket-accept plus 38 bytes seen in earlier target PSTs' {
        $script:sample.Current.Size=12038
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.Status | Should -BeExactly 'OnlySourceMailItemSizeDriftUnapproved'
        $r.SizeDriftAccepted | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'classifies unchanged original witness without pretending Move readiness' {
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.Status | Should -BeExactly 'NoCurrentSourceWitnessDrift'
        $r.OnlySizeDrift | Should -BeFalse
        $r.CanRetryMove | Should -BeFalse
    }
    It 'pins all original attachment bytes by SHA and name on size-only drift' {
        $script:sample.Current.Size=12007
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.AttachmentByteExactMatch | Should -BeTrue
        $r.OriginalAttachmentSha256 | Should -BeExactly ('f'*64)
        $r.CurrentAttachmentByteCount | Should -Be 1024
    }
    It 'blocks changed attachment SHA even when mail size drift is present' {
        $script:sample.Current.Size=12007
        $script:sample.Current.Attachments[0].Sha256=('9'*64)
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.Status | Should -BeExactly 'STOP_OtherWitnessFieldDrift'
        $r.OtherFieldMismatchNames | Should -Contain 'Attachment.Sha256'
        $r.AttachmentByteExactMatch | Should -BeFalse
        $r.OnlySizeDrift | Should -BeFalse
    }
    It 'blocks changed by-value attachment byte count' {
        $script:sample.Current.Attachments[0].ByteCount=1025
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.OtherFieldMismatchNames | Should -Contain 'Attachment.ByteCount'
    }
    It 'blocks changed attachment filename' {
        $script:sample.Current.Attachments[0].FileName='unexpected.bin'
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.OtherFieldMismatchNames | Should -Contain 'Attachment.FileName'
    }
    It 'blocks missing attachment instead of allowing size-only exception' {
        $script:sample.Current.Attachments=@()
        {Compare-OPA265BW4k7aSourceWitnessReadOnly @args} | Should -Throw '*attachment cardinality*'
    }
    It 'blocks changed subject digest even if size is same' {
        $script:sample.Current.SubjectUtf8Sha256=('1'*64)
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.Status | Should -BeExactly 'STOP_OtherWitnessFieldDrift'
        $r.OtherFieldMismatchNames | Should -Contain 'SubjectUtf8Sha256'
    }
    It 'blocks changed message body digest during size drift' {
        $script:sample.Current.Size=12003
        $script:sample.Current.BodyUtf8Sha256=('2'*64)
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.OtherFieldMismatchNames | Should -Contain 'BodyUtf8Sha256'
    }
    It 'blocks source entry ID drift' {
        $script:sample.Current.EntryId='OTHER'
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.OtherFieldMismatchNames | Should -Contain 'EntryId'
    }
    It 'blocks source StoreId drift' {
        $script:sample.Current.StoreId='OTHER'
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.OtherFieldMismatchNames | Should -Contain 'StoreId'
    }
    It 'blocks ReceivedUtcTicks drift' {
        $script:sample.Current.ReceivedUtcTicks=639291968060000000
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.OtherFieldMismatchNames | Should -Contain 'ReceivedUtcTicks'
    }
    It 'fails closed when fixture suite ID is changed' {
        $script:args.SuiteId=[guid]::NewGuid().ToString('D')
        {Compare-OPA265BW4k7aSourceWitnessReadOnly @args} | Should -Throw '*fixed Attachment1K*'
    }
    It 'fails closed for wrong fixture TestId' {
        $script:args.Case.TestId=[guid]::NewGuid().ToString('D')
        {Compare-OPA265BW4k7aSourceWitnessReadOnly @args} | Should -Throw '*fixed Attachment1K*'
    }
    It 'fails closed when source witness changes the schema shape' {
        $script:sample.Source | Add-Member -NotePropertyName AllowMove -NotePropertyValue $true
        {Compare-OPA265BW4k7aSourceWitnessReadOnly @args} | Should -Throw '*schema*'
    }
    It 'never grants Move, Claim write or production readiness' {
        $script:sample.Current.Size=12038
        $r=Compare-OPA265BW4k7aSourceWitnessReadOnly @args
        $r.ClaimWritten | Should -BeFalse
        $r.OutlookMoveExecuted | Should -BeFalse
        $r.CanRetryMove | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'diagnostic invokes both pinned read-only witnesses and their stability guard' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7aAttachmentSizeDriftReview.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Get-OPA265BW4jMailWitness @opts'
        $s | Should -Match 'Assert-OPA265BW4k1PinnedSource -Original \$one -Current \$two'
    }
    It 'diagnostic requires three immutable previous claims and exact historical Intent' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7aAttachmentSizeDriftReview.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Assert-OPA265BW4k7HistoricCompletedMoves'
        $s | Should -Match 'SevenHistoricalEvidenceHashesUnchanged'
        $s | Should -Match 'ExpectedFiveEvidenceSetSha256'
    }
    It 'diagnostic never uses MailItem.Move, Save or a Claim writer' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7aAttachmentSizeDriftReview.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\s*\('
        $s | Should -Not -Match 'Write-OPA265BW4'
        $s | Should -Not -Match '\bAddStoreEx\s*\('
    }
    It 'diagnostic reports MAPI message size and flags without accepting difference' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7aAttachmentSizeDriftReview.ps1') -Raw -Encoding UTF8
        $s | Should -Match "PR_MESSAGE_SIZE"
        $s | Should -Match "PR_MESSAGE_FLAGS"
        $s | Should -Match 'SizeDriftAccepted=\$false'
    }
}
