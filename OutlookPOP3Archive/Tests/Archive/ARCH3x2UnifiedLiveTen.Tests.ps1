#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1')
    $script:run='093b5ce9-4a90-46fa-b6a5-7cdba61d2f15'
    function New-OPAARCH3x2FakeBundle {
        $m=New-Object 'System.Collections.Generic.List[object]'
        $r=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le 10;$i++){
            $sid='00000000'+('{0:X8}' -f $i)
            $aid='ABCDEF00'+('{0:X8}' -f $i)
            [void]$m.Add([pscustomobject]@{SourceEntryId=$sid;OriginalOperationId=('ARCH3b-'+('a'*63)+[string]$i);TargetFolderPath='2020\Входящие'})
            [void]$r.Add([pscustomobject]@{SourceEntryId=$sid;ArchiveEntryId=$aid})
        }
        return [pscustomobject]@{
            Prepared=[pscustomobject]@{Manifest=[pscustomobject]@{RunId=$script:run;Rows=@($m.ToArray())}}
            Receipts=@($r.ToArray())
            Writer=[pscustomobject]@{OutlookProcessId=1234}
        }
    }
}
Describe 'ARCH3x1b+ARCH3x2 unified bounded live ten and original independent postrestart commit' {
    It 'new live pinned ten module exists and preserves full original ARCH2b witness' {
        Test-Path (Join-Path $script:root 'Core/Archive/ARCH3x1bPinnedLiveTen.ps1') | Should -BeTrue
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x1bPinnedLiveTen.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Get-OPA265ARCH2bMailSemanticWitness -Mail'
        $s | Should -Match 'Assert-OPA265ARCH3iFullWitnessPinned -Witness'
        $s | Should -Match 'Compare-OPA265ARCH2bMailSemanticWitness -Source'
    }
    It 'ARCH3x1b resolves only the ten originally sealed EntryIDs, never reselects by Inbox sort' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x1bPinnedLiveTen.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'GetItemFromID\(\[string\]\$r.SourceEntryId'
        $s | Should -Not -Match 'Get-OPAArchiveCandidates|New-OPA265ARCH3uTenPreview|Sort-Object ArchiveDate'
    }
    It 'ARCH3x1b permits ordinary PST growth, shrink, compaction and ordinary folder-count changes' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x1bPinnedLiveTen.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match 'LengthBytes -ne|FileInfo|Get-FileHash|Inbox.Items.Count'
    }
    It 'ARCH3x1b checks existing Part2 with the ORIGINAL live semantic ArchiveVerifier' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x1bPinnedLiveTen.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Get-OPA265ARCH3w1HistoricalEvidence -Part2'
        $s | Should -Match 'Test-OPA265ARCH3w1LiveOriginalPart2 -SourcePst'
        $s | Should -Match 'OriginalArchiveVerifierPart2Passed=\$true'
    }
    It 'ARCH3x1 old real Move entry now delegates to the new pinned ten semantic audit' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Get-OPA265ARCH3x1bPartsProof -Manifest'
        $s | Should -Match 'Get-OPA265ARCH3x1bPinnedTenLiveAudit -Manifest'
    }
    It 'ARCH3x1 preflight contains no source physical byte-size writer fence' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '\$audit.ObservedSourcePstLengthBytes'
        $s | Should -Not -Match '\$full.SourcePstLengthGrowthBytes'
        $s | Should -Not -Match 'SourcePstLengthBytes\]\s*-ne'
        $s | Should -Match 'PhysicalSourcePstSizeFence=\$false'
    }
    It 'ARCH3x1 still durably claims before original COM provider invocation and receipts' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1') -Raw -Encoding UTF8
        $s.IndexOf('New-OPA265ARCH3iPrivateEvidenceDirectory -Layout $layout') | Should -BeLessThan $s.IndexOf('$archive=New-OPAArchivePst -Namespace')
        $s.IndexOf("$"+'claimSha=Write-OPA265ARCH3cJsonOnce') | Should -BeLessThan $s.IndexOf('Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall -Mail')
    }
    It 'ARCH3x2 public entry has all six explicit modes without COM Move and no production switches' {
        $s=Get-Content (Join-Path $script:root 'Invoke-ARCH3x2.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Status','Plan','Review','Seal','Commit','Recover'\)"
        $s | Should -Match 'ConfirmVerifiedCommit'
        $s | Should -Match 'ConfirmRecovery'
        $s | Should -Not -Match '\.Move\('
    }
    It 'ARCH3x2 checks new real Outlook process and original POP3 scope' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'OutlookProcessStartUtcTicks -le'
        $s | Should -Match 'Get-OPA265ARCH2bTextSha256 -Text'
        $s | Should -Match 'Open-OPA265ARCH2dSession -Layout'
    }
    It 'ARCH3x2 original ArchiveVerifier verifies exactly ten and does not pin current Inbox total' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Test-OPAArchiveMoves -Namespace'
        $s | Should -Match '-ExpectedMoved 10 -ExpectedMoves'
        $s | Should -Match '-RequireSemanticWitness'
        $s | Should -Not -Match 'SourceItemsBefore'
    }
    It 'ARCH3x2 compares destination 10 full Body/HTML/attachment witnesses before original verifier' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Compare-OPA265ARCH2bMailSemanticWitness -Source'
        $s | Should -Match 'Assert-OPA265ARCH3iFullWitnessPinned -Witness'
        $s | Should -Match 'OriginalTenFullSemanticMatches=10'
    }
    It 'ARCH3x2 uses independently pinned claim, invocation and return SHA chain for all ten' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Get-OPA265ARCH3x1ReadOnlyStatus -Layout'
        $s | Should -Match 'ProviderInvocationSha256 -cne'
        $s | Should -Match 'PreviousMoveReceiptSha256'
        $s | Should -Match 'LastReceiptSha256'
    }
    It 'ARCH3x2 independent review cannot access original COM mover' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '\$mail.Move\(|\$item.Move\(|Invoke-OPA265ARCH3x1OneOriginalMailMoverProviderCall -Mail'
    }
    It 'ARCH3x2 preserves original protected ARCH3w1 journal unmodified' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Read-OPAOperationJournal -Path \(\[string\]\$Bundle.Prepared.Layout.JournalPath\)'
        $s | Should -Match 'Write-OPAOperationJournalEvent -Path \$Layout.CommitJournalPath'
        $s | Should -Not -Match 'Write-OPAOperationJournalEvent -Path \$Bundle.Prepared.Layout.JournalPath'
    }
    It 'ARCH3x2 original journal writes all ten Intent before any Reconciled' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $a=$s.IndexOf('Write-OPAOperationJournalEvent -Path $Layout.CommitJournalPath')
        $b=$s.IndexOf('-Phase Reconciled -SourceEntryId')
        $a | Should -BeGreaterThan 0
        $b | Should -BeGreaterThan $a
    }
    It 'ARCH3x2 requires separately confirmed protected review seal before index mutation' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'ConfirmReviewSeal'
        $s | Should -Match 'ConfirmVerifiedCommit'
        $s | Should -Match 'Get-OPA265ARCH3x2IndexState'
        $s | Should -Match 'Get-OPA265ARCH3x2FinishIndexAndJournal'
    }
    It 'ARCH3x2 writes original shared index only after ten verified journal reconciled' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $i=$s.IndexOf("if("+ '$state.Reconciled -ne 10)')
        $j=$s.IndexOf('Add-OPADuplicateEntry -Index $index.Index')
        $i | Should -BeGreaterThan 0
        $j | Should -BeGreaterThan $i
        $s | Should -Match 'Sync-OPADuplicateJournalStreams'
        $s | Should -Match 'OriginalIndexAdded=10'
    }
    It 'ARCH3x2 protected status is read-only and no Outlook on an unused RunId' {
        Mock Get-OPA265ARCH3x2Layout {return [pscustomobject]@{Root=(Join-Path $TestDrive 'absent-review');RunId=$script:run;ReviewSealPath=(Join-Path $TestDrive 'absent-review\seal.json');CommitClaimPath=(Join-Path $TestDrive 'absent-review\claim.json');CommitJournalPath=(Join-Path $TestDrive 'absent-review\journal.jsonl');CommitSealPath=(Join-Path $TestDrive 'absent-review\completed.json')}}
        Mock Open-OPA265ARCH2dSession {throw 'Unexpected live Outlook'}
        $r=Invoke-OPA265ARCH3x2RealTen -Mode Status -RunId $script:run
        $r.LiveOutlookContacted | Should -BeFalse
        $r.CommitComplete | Should -BeFalse
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
    It 'ARCH3x2 Plan with ten returned receipts never invokes Outlook' {
        Mock Get-OPA265ARCH3x2PinnedReturned {return [pscustomobject]@{Writer=[pscustomobject]@{OutlookProcessId=1234}}}
        Mock Open-OPA265ARCH2dSession {throw 'Unexpected live Outlook'}
        $r=Invoke-OPA265ARCH3x2RealTen -Mode Plan -RunId $script:run -SealSha256 ('a'*64) -ManifestSha256 ('b'*64) -JournalSha256 ('c'*64)
        $r.ReturnedTen | Should -Be 10
        $r.LiveOutlookContacted | Should -BeFalse
        Should -Invoke Open-OPA265ARCH2dSession -Exactly -Times 0
    }
    It 'ARCH3x2 journal-state returns zero for missing commit journal without creating files' {
        $b=New-OPAARCH3x2FakeBundle
        $l=[pscustomobject]@{CommitJournalPath=(Join-Path $TestDrive 'missing.jsonl')}
        $r=Get-OPA265ARCH3x2CommitJournalState -Bundle $b -Layout $l
        $r.Intents | Should -Be 0
        $r.Reconciled | Should -Be 0
        Test-Path $l.CommitJournalPath | Should -BeFalse
    }
    It 'ARCH3x2 original journal-state accepts correct append-only prefix, no COM' {
        $b=New-OPAARCH3x2FakeBundle
        $l=[pscustomobject]@{CommitJournalPath=(Join-Path $TestDrive 'three-intents.jsonl')}
        for($i=0;$i -lt 3;$i++){
            [void](Write-OPAOperationJournalEvent -Path $l.CommitJournalPath -TransactionId ('ARCH3x2-'+$script:run) -OperationId ([string]$b.Prepared.Manifest.Rows[$i].OriginalOperationId) -Sequence ([long]($i+1)) -Phase Intent -SourceEntryId ([string]$b.Prepared.Manifest.Rows[$i].SourceEntryId))
        }
        $r=Get-OPA265ARCH3x2CommitJournalState -Bundle $b -Layout $l
        $r.Intents | Should -Be 3
        $r.Reconciled | Should -Be 0
    }
    It 'ARCH3x2 journal-state rejects a foreign journal transaction before recovery' {
        $b=New-OPAARCH3x2FakeBundle
        $l=[pscustomobject]@{CommitJournalPath=(Join-Path $TestDrive 'foreign-intent.jsonl')}
        [void](Write-OPAOperationJournalEvent -Path $l.CommitJournalPath -TransactionId 'foreign' -OperationId ([string]$b.Prepared.Manifest.Rows[0].OriginalOperationId) -Sequence 1 -Phase Intent -SourceEntryId ([string]$b.Prepared.Manifest.Rows[0].SourceEntryId))
        {Get-OPA265ARCH3x2CommitJournalState -Bundle $b -Layout $l} | Should -Throw
    }
    It 'ARCH3x2 journal-state refuses Reconciled before all ten Intent events' {
        $b=New-OPAARCH3x2FakeBundle
        $l=[pscustomobject]@{CommitJournalPath=(Join-Path $TestDrive 'premature-reconciled.jsonl')}
        [void](Write-OPAOperationJournalEvent -Path $l.CommitJournalPath -TransactionId ('ARCH3x2-'+$script:run) -OperationId ([string]$b.Prepared.Manifest.Rows[0].OriginalOperationId) -Sequence 11 -Phase Reconciled -SourceEntryId ([string]$b.Prepared.Manifest.Rows[0].SourceEntryId) -ArchiveEntryId ([string]$b.Receipts[0].ArchiveEntryId))
        {Get-OPA265ARCH3x2CommitJournalState -Bundle $b -Layout $l} | Should -Throw
    }
    It 'ARCH3x2 recovery has explicit approval and can only finish index/journal' {
        $s=Get-Content (Join-Path $script:root 'Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1') -Raw -Encoding UTF8
        $s | Should -Match "if\(\$Mode -ceq 'Commit'\)"
        $s | Should -Match 'ConfirmRecovery'
        $s | Should -Match 'OnlyJournalAndIndexNoMove'
    }
    It 'all new and changed PowerShell files are UTF8 BOM and core writer switches remain closed' {
        foreach($p in @('Core/Archive/ARCH3x1bPinnedLiveTen.ps1','Core/Archive/ARCH3x1RealTenOriginalMailMover.ps1','Core/Archive/ARCH3x2TenIndependentReviewCommit.ps1','Invoke-ARCH3x2.ps1','Tests/Archive/ARCH3x2UnifiedLiveTen.Tests.ps1')){
            $bytes=[IO.File]::ReadAllBytes((Join-Path $script:root $p))
            (@($bytes[0],$bytes[1],$bytes[2]) -join ',') | Should -BeExactly '239,187,191'
        }
        $main=Get-Content (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $main | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
    }
}
