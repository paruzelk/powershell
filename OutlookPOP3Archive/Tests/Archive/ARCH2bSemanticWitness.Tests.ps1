#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2bSemanticWitness.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Archive/ArchiveVerifier.ps1')
    $script:main=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
    $script:mover=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
    $script:txSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ArchiveTransaction.ps1') -Raw -Encoding UTF8
    $script:verifierSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ArchiveVerifier.ps1') -Raw -Encoding UTF8
    $script:witnessSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2bSemanticWitness.ps1') -Raw -Encoding UTF8
    function Get-OPAInternetMessageId { param([object]$Item) return [string]$Item.MessageId }
    function Read-OPAStepJournal { param([object]$Transaction) return $script:stepFixture }
    function Test-OPAMoveCompletionStep { param([object]$Step) return ([string]$Step.Step -eq 'Move Completed' -or [string]$Step.Step -eq 'Move Reconciled') }
    function New-ARCH2bFakeCollection {
        param([object[]]$Items=@())
        $c=[pscustomobject]@{ Count=$Items.Count; Entries=@($Items) }
        $c | Add-Member -MemberType ScriptMethod -Name Item -Value {
            param([int]$index) return $this.Entries[$index-1]
        }
        return $c
    }
    function New-ARCH2bFakeAttachment {
        param([string]$FileName='тест.bin',[byte[]]$Payload=[byte[]]@(0,1,2,255))
        $a=[pscustomobject]@{ Type=1; Size=[int64]$Payload.Length; FileName=$FileName; Content=$Payload }
        $a | Add-Member -MemberType ScriptMethod -Name SaveAsFile -Value {
            param([string]$file) [IO.File]::WriteAllBytes($file,[byte[]]$this.Content)
        }
        return $a
    }
    function New-ARCH2bFakeMail {
        param([object[]]$Attachments=@(),[string]$Subject='Тема Ω',
              [string]$Body='Текст письма',[string]$Html='<p>Текст письма</p>',
              [int64]$Size=1500)
        [pscustomobject]@{
            Class=43; Subject=$Subject; Body=$Body; HTMLBody=$Html
            SenderEmailAddress='sender@example.test'
            To='Кому <to@example.test>';CC='';BCC=''
            MessageId='<test@example.test>'
            ReceivedTime=[datetime]'2024-01-02T09:00:00Z'
            SentOn=[datetime]'2024-01-02T08:00:00Z'
            UnRead=$false;Importance=1;Sensitivity=0;Categories=''
            Size=$Size
            Recipients=(New-ARCH2bFakeCollection -Items @())
            Attachments=(New-ARCH2bFakeCollection -Items $Attachments)
        }
    }
    function New-ARCH2bSourceFixture {
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail)
        return $w
    }
    function New-ARCH2bTxFixture {
        return [pscustomobject]@{
            TransactionId='T-ARCH2b';Path='C:\no-real-journal.json'
            State=[pscustomobject]@{
                PlannedItems=@([pscustomobject]@{
                    EntryId='SOURCE-ID';Subject='Тема Ω'
                    SourceFolderPath='\\POP3\Inbox';InternetMessageId='<test@example.test>'
                    Sender='sender@example.test';Size=[int64]1500
                })
            }
        }
    }
}
Describe 'ARCH2b original source semantic witness derived from BW4j verified by-value attachment hashing' {
    It 'hashes Unicode text deterministically' {
        (Get-OPA265ARCH2bTextSha256 -Text 'Привет Ω') | Should -BeExactly (Get-OPA265ARCH2bTextSha256 -Text 'Привет Ω')
    }
    It 'hashes different Body contents differently' {
        (Get-OPA265ARCH2bTextSha256 -Text 'a') | Should -Not -BeExactly (Get-OPA265ARCH2bTextSha256 -Text 'b')
    }
    It 'returns the SHA256 of empty string without normalizing it' {
        (Get-OPA265ARCH2bTextSha256 -Text '') | Should -BeExactly 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    }
    It 'captures a no-attachment synthetic mail without writing an archive PST' {
        $w=New-ARCH2bSourceFixture
        $w.Schema | Should -BeExactly '2.6.5-ARCH2b.MailSemanticWitness.1'
        $w.AttachmentCount | Should -Be 0
        $w.Attachments.Count | Should -Be 0
    }
    It 'validates a complete supported source witness schema' {
        (Test-OPA265ARCH2bWitnessSchema -Witness (New-ARCH2bSourceFixture)) | Should -BeTrue
    }
    It 'compares identical source and destination semantic content as match' {
        $w=New-ARCH2bSourceFixture
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $w -Destination $w).CriticalContentMatches | Should -BeTrue
    }
    It 'returns a diagnostic status for same content with changed MailItem.Size' {
        $w=New-ARCH2bSourceFixture
        $w2=New-ARCH2bSourceFixture
        $w2.MailItemSizeDiagnosticBytes=1624
        $r=Compare-OPA265ARCH2bMailSemanticWitness -Source $w -Destination $w2
        $r.CriticalContentMatches | Should -BeTrue
        $r.ProviderSizeDifferenceIsNotAutomaticCorruption | Should -BeTrue
    }
    It 'does not infer that a size match means content is intact' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.BodySha256=Get-OPA265ARCH2bTextSha256 -Text 'CHANGED'
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).CriticalContentMatches | Should -BeFalse
    }
    It 'blocks Body SHA mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.BodySha256=Get-OPA265ARCH2bTextSha256 -Text 'another'
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentBodySha256'
    }
    It 'blocks HTMLBody SHA mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.HtmlBodySha256=Get-OPA265ARCH2bTextSha256 -Text '<p>other</p>'
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentHtmlBodySha256'
    }
    It 'blocks sender mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.SenderSha256=Get-OPA265ARCH2bTextSha256 -Text 'new@example.test'
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentSenderSha256'
    }
    It 'blocks To mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.ToSha256=Get-OPA265ARCH2bTextSha256 -Text 'another'
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentToSha256'
    }
    It 'blocks Bcc mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.BccSha256=Get-OPA265ARCH2bTextSha256 -Text 'secret'
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentBccSha256'
    }
    It 'blocks recipient count mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.RecipientCount=1
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentRecipientCount'
    }
    It 'blocks unread flag mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.UnRead=$true
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentUnRead'
    }
    It 'blocks ReceivedTime mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.ReceivedUtcTicks++
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentReceivedUtcTicks'
    }
    It 'blocks SentOn mismatch' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.SentUtcTicks++
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentSentUtcTicks'
    }
    It 'blocks categories change' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $d.CategoriesSha256=Get-OPA265ARCH2bTextSha256 -Text 'new'
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'DifferentCategoriesSha256'
    }
    It 'rejects an incomplete original witness rather than passing' {
        $s=New-ARCH2bSourceFixture;$d=New-ARCH2bSourceFixture
        $s.BodySha256=''
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).Status | Should -BeExactly 'CriticalMailContentOrAttachmentDifferenceBlocked'
    }
    It 'rejects malformed hash in the original witness schema' {
        $s=New-ARCH2bSourceFixture;$s.HtmlBodySha256='123'
        (Test-OPA265ARCH2bWitnessSchema -Witness $s) | Should -BeFalse
    }
    It 'rejects incorrect attachment count in original witness schema' {
        $s=New-ARCH2bSourceFixture;$s.AttachmentCount=1
        (Test-OPA265ARCH2bWitnessSchema -Witness $s) | Should -BeFalse
    }
    It 'rejects absent user UnRead flag' {
        $s=New-ARCH2bSourceFixture;$s.UnRead=$null
        (Test-OPA265ARCH2bWitnessSchema -Witness $s) | Should -BeFalse
    }
    It 'hashes actual disposable bytes through SaveAsFile not MAPI MailItem.Size' {
        $attachment=New-ARCH2bFakeAttachment
        $mail=New-ARCH2bFakeMail -Attachments @($attachment)
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -MaxAttachmentBytes 4096
        $w.AttachmentCount | Should -Be 1
        $w.Attachments[0].PayloadByteCount | Should -Be 4
        $w.Attachments[0].PayloadSha256 | Should -BeExactly '3d1f57c984978ef98a18378c8166c1cb8ede02c03eeb6aee7e2f121dfeee3e56'
    }
    It 'never stores original attachment filename in journal witness' {
        $attachment=New-ARCH2bFakeAttachment -FileName 'private-note.txt'
        $mail=New-ARCH2bFakeMail -Attachments @($attachment)
        $w=Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -MaxAttachmentBytes 4096
        $json=ConvertTo-Json -InputObject $w -Depth 10
        $json | Should -Not -Match 'private-note.txt'
        $json | Should -Not -Match 'Текст письма'
    }
    It 'refuses unsupported embedded attachment type before Move' {
        $attachment=New-ARCH2bFakeAttachment
        $attachment.Type=5
        $mail=New-ARCH2bFakeMail -Attachments @($attachment)
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -MaxAttachmentBytes 4096} | Should -Throw
    }
    It 'refuses attachment exceeding explicit per-attachment maximum' {
        $attachment=New-ARCH2bFakeAttachment -Payload ([byte[]](1..16))
        $attachment.Size=1048577
        $mail=New-ARCH2bFakeMail -Attachments @($attachment)
        {Get-OPA265ARCH2bMailSemanticWitness -Mail $mail -MaxAttachmentBytes 4096} | Should -Throw
    }
    It 'compares real byte SHA if attachment payload differs but message size same' {
        $a=New-ARCH2bFakeAttachment -Payload ([byte[]]@(1,2,3,4))
        $b=New-ARCH2bFakeAttachment -Payload ([byte[]]@(1,2,3,5))
        $s=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($a)) -MaxAttachmentBytes 4096
        $d=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($b)) -MaxAttachmentBytes 4096
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'Attachment1DifferentPayloadSha256'
    }
    It 'allows same bytes of attachment with changed provider MailItem.Size' {
        $a=New-ARCH2bFakeAttachment -Payload ([byte[]]@(1,2,3,4))
        $s=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($a) -Size 1900) -MaxAttachmentBytes 4096
        $d=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($a) -Size 1980) -MaxAttachmentBytes 4096
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).CriticalContentMatches | Should -BeTrue
    }
    It 'blocks attachment filename change even with same bytes' {
        $a=New-ARCH2bFakeAttachment -FileName 'old.txt'
        $b=New-ARCH2bFakeAttachment -FileName 'new.txt'
        $s=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($a)) -MaxAttachmentBytes 4096
        $d=Get-OPA265ARCH2bMailSemanticWitness -Mail (New-ARCH2bFakeMail -Attachments @($b)) -MaxAttachmentBytes 4096
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $s -Destination $d).IssueCodes | Should -Contain 'Attachment1DifferentNameUtf8Sha256'
    }
}
Describe 'ARCH2b integration into actual Archive/Resume and verifier (no writer permit)' {
    It 'main entrypoint dot-sources new semantic witness before real MailMover' {
        $new=$script:main.IndexOf('Core\Archive\ARCH2bSemanticWitness.ps1')
        $old=$script:main.IndexOf('Core\Archive\MailMover.ps1')
        $new | Should -BeGreaterThan 0
        $old | Should -BeGreaterThan $new
    }
    It 'main Archive and Resume require a source semantic witness in final verifier' {
        @([regex]::Matches($script:main,'-ExpectedMoves \$expectedMoves -RequireSemanticWitness')).Count | Should -Be 2
    }
    It 'main DEV Archive/Resume/Auto writer closure has not been removed' {
        $script:main | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
    }
    It 'main mover captures exact saved source semantic witness before COM Move' {
        $capture=$script:mover.IndexOf('Get-OPA265ARCH2bMailSemanticWitness -Mail $item')
        $move=$script:mover.IndexOf('$item.Move($dest.Folder)')
        $capture | Should -BeGreaterThan 0
        $move | Should -BeGreaterThan $capture
    }
    It 'main mover persists semantic witness in durable Move Started before Outlook call' {
        $script:mover | Should -Match 'SemanticWitness \$sourceSemanticWitness -WriteCheckpoint'
        $script:mover | Should -Match 'Sync-OPAStepJournalStreams'
    }
    It 'pre-Move semantic capture failure stops packet rather than falling through Skipped' {
        $script:mover | Should -Match 'if \(\$semanticPreflightBlocked\)'
        $script:mover | Should -Match 'stop the transaction before claiming or moving'
    }
    It 'transaction step journal contains only hash witnesses rather than raw Body' {
        $script:txSource | Should -Match 'SourceSemanticWitness'
        $script:txSource | Should -Match '\$stepEntry\['
        $script:witnessSource | Should -Match 'BodySha256'
        $script:witnessSource | Should -Not -Match 'BodyText\s*='
    }
    It 'normal verifier gets original pre-Move semantic snapshot from original journal' {
        $script:verifierSource | Should -Match "Step -ceq 'Move Started'"
        $script:verifierSource | Should -Match 'SourceSemanticWitness'
    }
    It 'normal verifier checks full content independently via semantic comparison' {
        $script:verifierSource | Should -Match 'Compare-OPA265ARCH2bMailSemanticWitness'
        $script:verifierSource | Should -Match 'Get-OPA265ARCH2bMailSemanticWitness -Mail \$Item'
    }
    It 'normal verifier does not block solely on MailItem.Size when semantic witness is provided' {
        $script:verifierSource | Should -Match 'if \(\$null -ne \$Expected.SourceSemanticWitness\)'
        $script:verifierSource | Should -Match 'elseif \(\$null -ne \$Expected.Size'
    }
    It 'normal verifier exposes a separate strict RequireSemanticWitness option' {
        $script:verifierSource | Should -Match '\[switch\]\$RequireSemanticWitness'
        $script:verifierSource | Should -Match 'ARCH2b_PREMOVE_SEMANTIC_WITNESS_MISSING_OR_INVALID'
    }
    It 'normal verifier rejects missing witness even with existing target ID' {
        $s=New-ARCH2bSourceFixture
        $missing=[pscustomobject]@{
            Class=43;Subject='Тема Ω';SenderEmailAddress='sender@example.test'
            MessageId='';Size=1500
        }
        $expected=[pscustomobject]@{
            Subject='Тема Ω';Sender='sender@example.test'
            InternetMessageId='';Size=1500
            SourceSemanticWitness=$s
        }
        $script:destinationWitness=New-ARCH2bSourceFixture
        Mock Get-OPA265ARCH2bMailSemanticWitness { $script:destinationWitness }
        (Test-OPAArchiveItemFingerprint -Item $missing -Expected $expected) | Should -BeTrue
        $script:destinationWitness.BodySha256=Get-OPA265ARCH2bTextSha256 -Text 'wrong'
        (Test-OPAArchiveItemFingerprint -Item $missing -Expected $expected) | Should -BeFalse
    }
    It 'original source witness is attached to completion from persisted Move Started' {
        $script:stepFixture=@(
            [pscustomobject]@{Step='Move Started';EntryId='SOURCE-ID';SourceSemanticWitness=(New-ARCH2bSourceFixture)}
            [pscustomobject]@{Step='Move Completed';EntryId='SOURCE-ID';ArchiveEntryId='DEST';ArchivePst='C:\archive.pst';TargetFolderPath='\\Archive\2024'}
        )
        $result=@(Get-OPAExpectedMovesFromTransaction -Transaction (New-ARCH2bTxFixture) -DuplicateIndex ([pscustomobject]@{Entries=@()}))
        $result.Count | Should -Be 1
        (Test-OPA265ARCH2bWitnessSchema -Witness $result[0].SourceSemanticWitness) | Should -BeTrue
    }
    It 'completion from old transaction without original source witness is not fabricated' {
        $script:stepFixture=@(
            [pscustomobject]@{Step='Move Started';EntryId='SOURCE-ID'}
            [pscustomobject]@{Step='Move Completed';EntryId='SOURCE-ID';ArchiveEntryId='DEST';ArchivePst='C:\archive.pst';TargetFolderPath='\\Archive\2024'}
        )
        $result=@(Get-OPAExpectedMovesFromTransaction -Transaction (New-ARCH2bTxFixture) -DuplicateIndex ([pscustomobject]@{Entries=@()}))
        $result.Count | Should -Be 1
        $result[0].SourceSemanticWitness | Should -BeNullOrEmpty
    }
    It 'duplicate original Move Started claims trigger stop instead of witness rebaseline' {
        $script:stepFixture=@(
            [pscustomobject]@{Step='Move Started';EntryId='SOURCE-ID';SourceSemanticWitness=(New-ARCH2bSourceFixture)}
            [pscustomobject]@{Step='Move Started';EntryId='SOURCE-ID';SourceSemanticWitness=(New-ARCH2bSourceFixture)}
            [pscustomobject]@{Step='Move Completed';EntryId='SOURCE-ID';ArchiveEntryId='DEST';ArchivePst='C:\archive.pst';TargetFolderPath='\\Archive\2024'}
        )
        {Get-OPAExpectedMovesFromTransaction -Transaction (New-ARCH2bTxFixture) -DuplicateIndex ([pscustomobject]@{Entries=@()})} | Should -Throw
    }
    It 'semantic comparison never authorizes production or retry' {
        $w=New-ARCH2bSourceFixture
        $r=Compare-OPA265ARCH2bMailSemanticWitness -Source $w -Destination $w
        $r.ProductionReady | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.OriginalMoveMayBeRetried | Should -BeFalse
    }
}
