#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7Attachment1KEvidence265.ps1')
    function New-OPA265BW4k7Synthetic {
        $suite='74912f94-d523-4856-9efd-d5528a92426f'
        $id='87e72fd0-9e77-4098-a403-cbe99870b9e7'
        $orig=[pscustomobject]@{
            EntryId='SRC-ENTRY';FolderEntryId='SRC-FOLDER'
            StoreId='SRC-STORE';Size=7024
            Attachments=@([pscustomobject]@{Index=1;FileName='sample.bin';ByteCount=1024;Sha256=('d'*64)})
        }
        $rows=New-Object 'System.Collections.Generic.List[object]'
        foreach($spec in @(Get-OPA265BW4k3PropertySpecs)){
            $v=ConvertTo-OPA265BW4k3HashedValue -Value ([string]$spec.Name)
            $rows.Add([pscustomobject][ordered]@{
                Name=$spec.Name;Tag=$spec.Tag;Kind=$v.Kind;Available=$true
                ByteCount=$v.ByteCount;Sha256=$v.Sha256;Scalar=$v.Scalar
            })
        }
        $snapshot=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k3.BoundedReadOnlyMapiPropertySnapshot.1'
            SuiteId=$suite;TestId=$id;EntryId='SRC-ENTRY'
            FolderEntryId='SRC-FOLDER'
            StoreIdSha256=(Get-OPA265BW4jTextHash -Value 'SRC-STORE')
            Rows=@($rows.ToArray())
            PropertyCount=15;AvailableCount=15
            OutlookMoveExecuted=$false;ProductionReady=$false
        }
        $record=[pscustomobject][ordered]@{
            Schema='2.6.5-BW4k7.ImmutableAttachment1KSourceMapiEvidence.1'
            SuiteId=$suite;TestId=$id;CaseName='Attachment1K'
            PlanSha256=('a'*64)
            OriginalEvidenceSha256=('b'*64)
            FiveEvidenceSetSha256=('c'*64)
            SourceEntryId='SRC-ENTRY'
            SourceFolderEntryId='SRC-FOLDER'
            SourceStoreIdSha256=$snapshot.StoreIdSha256
            SourceSize=7024;CapturedUtc=[datetime]::UtcNow.ToString('o')
            Snapshot=$snapshot
            OutlookMoveExecuted=$false;ProductionReady=$false
        }
        [pscustomobject]@{
            SuiteId=$suite;TestId=$id;Original=$orig;Record=$record
            Pins=@{
                Original=$orig;SuiteId=$suite;TestId=$id
                OriginalEvidenceSha256=('b'*64)
                ExpectedPlanSha256=('a'*64)
                ExpectedFiveEvidenceSetSha256=('c'*64)
            }
        }
    }
}
Describe 'BW4k7 original Attachment1K immutable 15-property pre-Move evidence' {
    BeforeEach {
        $script:caseData=New-OPA265BW4k7Synthetic
        $script:pins=$script:caseData.Pins
        $script:root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    }
    It 'pins the exact original Attachment1K TestId' {
        $script:caseData.TestId | Should -BeExactly '87e72fd0-9e77-4098-a403-cbe99870b9e7'
    }
    It 'accepts exact 15-property original Attachment1K snapshot' {
        (Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins) | Should -BeTrue
    }
    It 'rejects an original mail without the expected attachment' {
        $script:caseData.Original.Attachments=@()
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*by-value*'
    }
    It 'rejects an undersized original attachment' {
        $script:caseData.Original.Attachments[0].ByteCount=1023
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*by-value*'
    }
    It 'rejects a malformed original attachment SHA256' {
        $script:caseData.Original.Attachments[0].Sha256='not-sha256'
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*by-value*'
    }
    It 'rejects wrong source SHA' {
        $script:caseData.Record.OriginalEvidenceSha256='f'*64
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*OriginalEvidenceSha256*'
    }
    It 'rejects changing HTML case identity' {
        $script:caseData.Record.CaseName='UnicodePlain'
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*CaseName*'
    }
    It 'rejects wrong source POP3 mail EntryId' {
        $script:caseData.Record.SourceEntryId='OTHER'
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*SourceEntryId*'
    }
    It 'rejects tampered old five-source seal' {
        $script:caseData.Record.FiveEvidenceSetSha256='f'*64
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*FiveEvidenceSetSha256*'
    }
    It 'rejects false production or Move capability' {
        $script:caseData.Record.ProductionReady=$true
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*cannot claim Move*'
    }
    It 'rejects extra MAPI evidence fields' {
        $script:caseData.Record | Add-Member -NotePropertyName AllowRetry -NotePropertyValue $true
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*property count*'
    }
    It 'rejects modified MAPI property order' {
        $script:caseData.Record.Snapshot.Rows[0].Tag='0xFFFFFFFF'
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*spec order*'
    }
    It 'rejects wrong HTML snapshot digest for available property' {
        $script:caseData.Record.Snapshot.Rows[14].Sha256='oops'
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*bounded property digest*'
    }
    It 'rejects fabricated available count' {
        $script:caseData.Record.Snapshot.AvailableCount=14
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*available property count*'
    }
    It 'accepts unavailable property only without fake digest' {
        $s=$script:caseData.Record.Snapshot
        $s.Rows[14].Kind='UnavailableOrError'
        $s.Rows[14].Available=$false
        $s.Rows[14].Sha256=''
        $s.Rows[14].Scalar=''
        $s.AvailableCount=14
        (Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins) | Should -BeTrue
        $s.Rows[14].Sha256='f'*64
        { Assert-OPA265BW4k7Attachment1KRecord -Record $script:caseData.Record @pins } | Should -Throw '*unavailable property*'
    }
    It 'refuses wrong Attachment1K evidence path' {
        $path=Get-OPA265BW4k7Attachment1KSnapshotPath -SuiteId $script:caseData.SuiteId -TestId $script:caseData.TestId -LocalAppData $script:root
        $path | Should -Match 'BW4k7-SourceSnapshots'
        { Get-OPA265BW4k7Attachment1KSnapshotPath -SuiteId $script:caseData.SuiteId -TestId ([guid]::NewGuid().ToString('D')) -LocalAppData $script:root } | Should -Throw '*Attachment1K fixture*'
    }
    It 'creates one immutable BOM snapshot and prevents second write' {
        $p=Get-OPA265BW4k7Attachment1KSnapshotPath -SuiteId $script:caseData.SuiteId -TestId $script:caseData.TestId -LocalAppData $script:root
        $w=Write-OPA265BW4k7Attachment1KSnapshotOnce -Record $script:caseData.Record -Path $p -LocalAppData $script:root
        $w.SnapshotSha256 | Should -Match '^[a-f0-9]{64}$'
        $w.SnapshotPath | Should -BeExactly $p
        ([IO.File]::ReadAllBytes($p))[0] | Should -Be 239
        { Write-OPA265BW4k7Attachment1KSnapshotOnce -Record $script:caseData.Record -Path $p -LocalAppData $script:root } | Should -Throw
    }
    It 'refuses arbitrary output redirection' {
        $p=Join-Path $script:root 'foreign.json'
        { Write-OPA265BW4k7Attachment1KSnapshotOnce -Record $script:caseData.Record -Path $p -LocalAppData $script:root } | Should -Throw '*cannot be redirected*'
    }
    It 'blocks missing pre-existing first and second immutable Move claims' {
        { Assert-OPA265BW4k7HistoricCompletedMoves -SuiteId $script:caseData.SuiteId -LocalAppData $script:root } | Should -Throw '*claim changed*'
    }
    It 'blocks a different suite from using pinned old claim evidence' {
        { Assert-OPA265BW4k7HistoricCompletedMoves -SuiteId ([guid]::NewGuid().ToString('D')) -LocalAppData $script:root } | Should -Throw '*one exact suite*'
    }
    It 'has no writer or Move in Review and requires exact Attachment1K' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7Attachment1KPreMoveMapi.ps1') -Raw -Encoding UTF8
        $src | Should -Match "'Attachment1K'"
        $src | Should -Match 'Assert-OPA265BW4k1PinnedSource'
        $src | Should -Match 'Assert-OPA265BW4k7HistoricCompletedMoves'
        $src | Should -Match 'if\(\$Mode -ceq'
        $src | Should -Match 'Write-OPA265BW4k7Attachment1KSnapshotOnce'
        $src | Should -Not -Match '(?i)\$mail\.(Move|Save|Send|Delete)\('
        $src | Should -Match 'ProductionReady=\$false'
    }
}
