#requires -Version 5.1
# ARCH3b: pure model of source->existing Year/part/folder route and
# fail-closed hypothetical crash phases. No Outlook COM/PST in CI.
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3bOriginalMoverContract.ps1')
    $script:source='C:\SyntheticNoPst\info@stios.ru.pst'
    $script:tx='20261112-163000-aabbccdd'
    $script:store='ORIGINAL_POP3_STORE_ID_0123456789'
    function New-ARCH3bOriginalCandidate {
        param([string]$EntryId='00000000E1878292411BC64291BD506DCEFD2A35040A3C00',
              [datetime]$ArchiveDate=([datetime]'2020-02-12T12:30:00'),
              [string]$Name='Входящие',
              [string]$Path='\\POP3 Store\Входящие')
        return [pscustomobject]@{
            EntryID=$EntryId
            ArchiveDate=$ArchiveDate
            ReceivedTime=$ArchiveDate
            SourceFolderPath=$Path
            FolderName=$Name
            InternetMessageId='<original@synthetic.invalid>'
            Subject='Test Message'
            Size=[int64]4301
        }
    }
    function New-ARCH3bPhaseList {
        param([object]$Contract)
        $list=New-Object 'System.Collections.Generic.List[object]'
        foreach($phase in @('PrepareIntent','DestinationReady','SourceWitnessAnchored','MoveClaimed','MoveReturned','IndependentContentVerified','IndexCommitted')){
            $list.Add([pscustomobject]@{
                TransactionId=[string]$Contract.TransactionId
                OperationId=[string]$Contract.OperationId
                Phase=$phase
                SourceWitnessSha256=('a'*64)
                DurablyFlushedBeforeMove=$true
                DestinationEntryId='00000000E1878292411BC64291BD506DCEFD2A3540093C00'
                FullSemanticMatch=$true
                OutlookRestartConfirmed=$true
                IndexMatchesReceipt=$true
            })|Out-Null
        }
        return @($list.ToArray())
    }
    function New-ARCH3bContract {
        param([object]$Candidate=(New-ARCH3bOriginalCandidate),
              [int]$Part=1,[string]$Grouping='Year',
              [string]$TransactionId=$script:tx)
        return (New-OPA265ARCH3bOperationContract -Candidate $Candidate -TransactionId $TransactionId -SourcePst $script:source -SourceStoreId $script:store -ArchiveGrouping $Grouping -ArchivePart $Part)
    }
    $script:candidate=New-ARCH3bOriginalCandidate
    $script:contract=New-ARCH3bContract -Candidate $script:candidate
}
Describe 'ARCH3b reuse original MailMover contract, not new routing implementation' {
    It 'returns known schema, original candidate ID and fully bound operation' {
        $script:contract.Schema | Should -BeExactly '2.6.5-ARCH3b.OperationContract.1'
        $script:contract.SourceEntryId | Should -BeExactly $script:candidate.EntryID
        $script:contract.SourceStoreId | Should -BeExactly $script:store
    }
    It 'uses exact original Get-OPAArchivePartPath, not a copied naming formula' {
        $expected=Get-OPAArchivePartPath -SourcePst $script:source -Year 2020 -Part 1
        $script:contract.PlannedArchivePst | Should -BeExactly $expected
        $script:contract.PlannedArchivePst | Should -BeLike '*info@stios.ru.Archive-2020.pst'
    }
    It 'uses original nested folder Get-OPAArchiveTargetPath' {
        $candidate=New-ARCH3bOriginalCandidate -Name 'Договоры' -Path '\\POP3 Store\Проекты\Договоры'
        $x=New-ARCH3bContract -Candidate $candidate
        $x.PlannedTargetFolderPath | Should -BeExactly '2020\Проекты\Договоры'
        $x.PlannedTargetFolderPath | Should -BeExactly (Get-OPAArchiveTargetPath -ReceivedTime $candidate.ArchiveDate -SourceFolderName $candidate.FolderName -SourceFolderPath $candidate.SourceFolderPath -Grouping Year)
    }
    It 'uses original date for yearly routing' {
        $script:contract.ArchiveYear | Should -Be 2020
        $script:contract.ArchiveGrouping | Should -BeExactly 'Year'
    }
    It 'allows original YearQuarter and YearMonth and None without reimplementing them' {
        foreach($mode in @('None','YearQuarter','YearMonth')){
            $x=New-ARCH3bContract -Grouping $mode
            $expect=Get-OPAArchiveTargetPath -ReceivedTime $script:candidate.ArchiveDate -SourceFolderName $script:candidate.FolderName -SourceFolderPath $script:candidate.SourceFolderPath -Grouping $mode
            $x.PlannedTargetFolderPath | Should -BeExactly $expect
        }
    }
    It 'preserves original rollover naming for archive part two' {
        $x=New-ARCH3bContract -Part 2
        $x.PlannedArchivePst | Should -BeLike '*info@stios.ru.Archive-2020-02.pst'
    }
    It 'original SentOn-selected date produces a 2020 archive instead of 2021' {
        $c=New-ARCH3bOriginalCandidate -ArchiveDate ([datetime]'2020-12-31T23:50:00') -Name 'Отправленные' -Path '\\POP3 Store\Отправленные'
        $x=New-ARCH3bContract -Candidate $c
        $x.ArchiveYear | Should -Be 2020
        $x.PlannedTargetFolderPath | Should -BeExactly '2020\Отправленные'
    }
    It 'operation identity uses full SHA256 and stable original transaction inputs' {
        $script:contract.ContractSha256 | Should -Match '^[a-f0-9]{64}$'
        $script:contract.OperationId | Should -BeExactly ('ARCH3b-'+$script:contract.ContractSha256)
        (New-ARCH3bContract).ContractSha256 | Should -BeExactly $script:contract.ContractSha256
    }
    It 'operation identity differs for another original EntryID' {
        $c=New-ARCH3bOriginalCandidate -EntryId 'FEDCBA0987654321123412345678AAAA'
        (New-ARCH3bContract -Candidate $c).OperationId | Should -Not -BeExactly $script:contract.OperationId
    }
    It 'operation identity differs across transaction boundaries' {
        (New-ARCH3bContract -TransactionId '20261112-180000-aabbccde').ContractSha256 | Should -Not -BeExactly $script:contract.ContractSha256
    }
    It 'operation identity binds exact source folder path' {
        $c=New-ARCH3bOriginalCandidate -Path '\\POP3 Store\Почта\Входящие'
        (New-ARCH3bContract -Candidate $c).ContractSha256 | Should -Not -BeExactly $script:contract.ContractSha256
    }
    It 'operation identity binds target archive part and grouping mode' {
        (New-ARCH3bContract -Part 2).ContractSha256 | Should -Not -BeExactly $script:contract.ContractSha256
        (New-ARCH3bContract -Grouping YearQuarter).ContractSha256 | Should -Not -BeExactly $script:contract.ContractSha256
    }
    It 'operation identity binds year, not just subject or size' {
        $c=New-ARCH3bOriginalCandidate -ArchiveDate ([datetime]'2021-02-12T12:30:00')
        (New-ARCH3bContract -Candidate $c).ContractSha256 | Should -Not -BeExactly $script:contract.ContractSha256
    }
    It 'deterministic canonical hash disambiguates differently segmented values' {
        (Get-OPA265ARCH3bDigest -Parts @('12','3')) | Should -Not -BeExactly (Get-OPA265ARCH3bDigest -Parts @('1','23'))
    }
    It 'does not trust missing original selector EntryID' {
        $c=New-ARCH3bOriginalCandidate -EntryId ''
        {New-ARCH3bContract -Candidate $c} | Should -Throw
    }
    It 'does not trust duplicate or malformed original selector EntryID' {
        $c=New-ARCH3bOriginalCandidate -EntryId 'BAD_ID'
        {New-ARCH3bContract -Candidate $c} | Should -Throw
    }
    It 'rejects missing original folder path or source StoreID' {
        $c=New-ARCH3bOriginalCandidate -Path ''
        {New-ARCH3bContract -Candidate $c} | Should -Throw
        {New-OPA265ARCH3bOperationContract -Candidate $script:candidate -TransactionId $script:tx -SourcePst $script:source -SourceStoreId ''} | Should -Throw
    }
    It 'rejects another original PST extension' {
        {New-OPA265ARCH3bOperationContract -Candidate $script:candidate -TransactionId $script:tx -SourcePst 'C:\SyntheticNoPst\archive.txt' -SourceStoreId $script:store} | Should -Throw
    }
    It 'rejects invalid transaction id and invalid archive part' {
        {New-ARCH3bContract -TransactionId '..\bad'} | Should -Throw
        {New-ARCH3bContract -Part 0} | Should -Throw
    }
    It 'validated original candidate reproduces every pinned route and identity' {
        (Assert-OPA265ARCH3bOperationContract -Contract $script:contract -Candidate $script:candidate) | Should -BeTrue
    }
    It 'detects a forged destination path in operator input' {
        $x=$script:contract.PSObject.Copy()
        $x.PlannedArchivePst='C:\Different\Output.pst'
        {Assert-OPA265ARCH3bOperationContract -Contract $x -Candidate $script:candidate} | Should -Throw
    }
    It 'detects source-folder drift after snapshot' {
        $c=New-ARCH3bOriginalCandidate -Path '\\POP3 Store\Перемещено'
        {Assert-OPA265ARCH3bOperationContract -Contract $script:contract -Candidate $c} | Should -Throw
    }
    It 'rejects direct writer or retry permit smuggled into dry-run contract' {
        $x=$script:contract.PSObject.Copy()
        $x.WriterPermit=$true
        {Assert-OPA265ARCH3bOperationContract -Contract $x -Candidate $script:candidate} | Should -Throw
    }
    It 'read-only preview detects two original emails by year without opening PST' {
        $a=New-ARCH3bOriginalCandidate
        $b=New-ARCH3bOriginalCandidate -EntryId 'FEDCBA0987654321123412345678AAAA' -ArchiveDate ([datetime]'2021-08-03')
        $p=New-OPA265ARCH3bBatchPreview -Candidates @($a,$b) -TransactionId $script:tx -SourcePst $script:source -SourceStoreId $script:store -ArchiveGrouping Year
        $p.PlannedItems | Should -Be 2
        $p.YearCounts.Count | Should -Be 2
        $p.Items[0].ArchiveYear | Should -Be 2020
        $p.Items[1].ArchiveYear | Should -Be 2021
        $p.PstOpened | Should -BeFalse
        $p.JsonWritten | Should -BeFalse
    }
    It 'rejects duplicate original EntryIDs in a batch preview' {
        {New-OPA265ARCH3bBatchPreview -Candidates @($script:candidate,$script:candidate) -TransactionId $script:tx -SourcePst $script:source -SourceStoreId $script:store} | Should -Throw
    }
    It 'rejects a batch preview exceeding 10000 originals before creating any PST' {
        $list=New-Object 'System.Collections.Generic.List[object]'
        for($i=0;$i -lt 10001;$i++){[void]$list.Add($script:candidate)}
        {New-OPA265ARCH3bBatchPreview -Candidates $list.ToArray() -TransactionId $script:tx -SourcePst $script:source -SourceStoreId $script:store} | Should -Throw
    }
}
Describe 'ARCH3b fail-closed phase sequence model does not authorize a COM Move' {
    It 'empty evidence means before Move, no writer or retry permit' {
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events @()
        $s.Status | Should -BeExactly 'BeforeMoveContractOnlyNoWriterPermit'
        $s.WriterPermit | Should -BeFalse
        $s.AutomaticMoveRetryAllowed | Should -BeFalse
    }
    It 'valid synthetic full sequence stays hypothetical and not production certified' {
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events @(New-ARCH3bPhaseList -Contract $script:contract)
        $s.Status | Should -BeExactly 'HypotheticalVerifiedAndIndexedNotLiveCertified'
        $s.AcceptedPhaseCount | Should -Be 7
        $s.ProductionReady | Should -BeFalse
        $s.IndependentRuntimeContentVerified | Should -BeFalse
    }
    It 'source witness anchored is required before MoveClaimed' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events @($events[0],$events[1],$events[3])
        $s.Status | Should -BeExactly 'InvalidEvidenceManualReviewNoRetry'
    }
    It 'durable Prepare intent MUST precede destination PST creation' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events @($events[1])
        $s.IssueCodes | Should -Contain 'PhaseMissingDuplicateOrOutOfOrder'
    }
    It 'missing SHA256 of original source witness is a hard failure' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $events[2].SourceWitnessSha256=''
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events $events
        $s.IssueCodes | Should -Contain 'SourceWitnessNotAnchored'
    }
    It 'no MoveClaim without durable flush' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $events[3].DurablyFlushedBeforeMove=$false
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events $events
        $s.IssueCodes | Should -Contain 'MoveClaimWithoutDurableFlush'
    }
    It 'claim with no return is never retry authorized' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events @($events[0..3])
        $s.Status | Should -BeExactly 'OneShotMoveClaimPresentOutcomeUnconfirmed'
        $s.AutomaticMoveRetryAllowed | Should -BeFalse
    }
    It 'indeterminate COM outcome without return forces manual review' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $ab=@($events[0..3])+@([pscustomobject]@{Phase='MoveIndeterminate';OperationId=$script:contract.OperationId;TransactionId=$script:tx})
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events $ab
        $s.Status | Should -BeExactly 'IndeterminateMoveManualReviewNoRetry'
    }
    It 'MoveReturn without post-restart independent content comparison is not completion' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events @($events[0..4])
        $s.Status | Should -BeExactly 'MoveReturnedIndependentVerificationPending'
    }
    It 'invalid destination EntryID in receipt is a hard failure' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $events[4].DestinationEntryId=''
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events $events
        $s.IssueCodes | Should -Contain 'InvalidDestinationEntryID'
    }
    It 'Outlook restart and full semantic match are both required' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $events[5].OutlookRestartConfirmed=$false
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events $events
        $s.IssueCodes | Should -Contain 'IndependentReconcileNotConfirmed'
        $events[5].OutlookRestartConfirmed=$true
        $events[5].FullSemanticMatch=$false
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events $events
        $s.IssueCodes | Should -Contain 'IndependentReconcileNotConfirmed'
    }
    It 'index committed before independent content verification is rejected' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events (@($events[0..4])+@($events[6]))
        $s.IssueCodes | Should -Contain 'PhaseMissingDuplicateOrOutOfOrder'
    }
    It 'index must be tied to verified receipt' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $events[6].IndexMatchesReceipt=$false
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events $events
        $s.IssueCodes | Should -Contain 'IndexNotLinkedToVerifiedReceipt'
    }
    It 'duplicate MoveClaim is always rejected' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events (@($events[0..3])+@($events[3]))
        $s.IssueCodes | Should -Contain 'PhaseMissingDuplicateOrOutOfOrder'
    }
    It 'events from a different original OperationId are rejected' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $events[1].OperationId='ARCH3b-FORGED'
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events $events
        $s.IssueCodes | Should -Contain 'IdentityMismatch'
    }
    It 'evidence after a COM-indeterminate state cannot be considered safe' {
        $events=New-ARCH3bPhaseList -Contract $script:contract
        $bad=[pscustomobject]@{Phase='MoveIndeterminate';OperationId=$script:contract.OperationId;TransactionId=$script:tx}
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events (@($events[0..3])+@($bad)+@($events[4]))
        $s.IssueCodes | Should -Contain 'EvidenceAfterIndeterminateMove'
    }
    It 'null synthetic evidence fails closed with no retry or writer' {
        $s=Test-OPA265ARCH3bPhaseEvidence -Contract $script:contract -Events @($null)
        $s.Status | Should -BeExactly 'InvalidEvidenceManualReviewNoRetry'
        $s.WriterPermit | Should -BeFalse
    }
}
Describe 'ARCH3b source compatibility and always-on development safety' {
    It 'original top-level Archive/Resume/Auto writer fence is unchanged' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
    }
    It 'original MailMover COM code remains unmodified and still protected by ARCH2a' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $s | Should -Match '\$moved = \$item\.Move\(\$dest\.Folder\)'
        $s | Should -Match 'Move Indeterminate'
    }
    It 'bridge contains zero direct COM Move, AddStoreEx, Delete or original journal writer calls' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3bOriginalMoverContract.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '\.(Move|AddStoreEx|Delete|Save|Copy)\s*\('
        $s | Should -Not -Match 'Write-OPA265ARCH2c4JsonOnce'
        $s | Should -Match 'Get-OPAArchivePartPath -SourcePst'
    }
    It 'the stage does NOT claim to have carried out any real COM Moves' {
        $script:contract.WriterPermit | Should -BeFalse
        $script:contract.PstOpened | Should -BeFalse
        $script:contract.OriginalSourceWitnessStillRequired | Should -BeTrue
    }
    It 'the ARCH3-001 ADR is present and insists on existing legacy production pipeline' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'docs/ADR-ARCH3-001-reuse-existing-archiver.md') -Raw -Encoding UTF8
        $s | Should -Match 'OutlookPOP3Archive.ps1'
        $s | Should -Match 'ARCH3b'
    }
}
