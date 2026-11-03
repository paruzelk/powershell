#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7uSyntheticBatch265.ps1')
    $script:id='c6202ea3-e682-413c-81a2-d6d0be8ff312'
    $script:suite=New-OPA265BW4k7uSyntheticSuite -SuiteId $script:id
    $script:plan=Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $script:suite
    function New-BW4k7uLedger {
        New-OPA265BW4k7uSyntheticLedger -Suite $script:suite -CapacityPlan $script:plan
    }
}
Describe 'BW4k7u SYNTHETIC ONLY multi-item POP3 annual capacity, semantic risk and one-shot crash-model preflight' {
    It 'suite has exactly twelve synthetic cases' {
        (New-OPA265BW4k7uSyntheticSuite -SuiteId $script:id).Cases.Count | Should -Be 12
    }
    It 'suite manifest pinned lowercase sha' {
        $script:suite.ManifestSha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'suite source only in memory' {
        $script:suite.OutlookOrPstFilesAccessed | Should -BeFalse
    }
    It 'suite never writes disk claims' {
        $script:suite.DiskJournalOrClaimWritten | Should -BeFalse
    }
    It 'suite never reuses historic one-shot claim' {
        $script:suite.HistoricMoveClaimReused | Should -BeFalse
    }
    It 'suite never grants writer' {
        $script:suite.WriterPermit | Should -BeFalse
    }
    It 'suite never grants production' {
        $script:suite.ProductionReady | Should -BeFalse
    }
    It 'suite validates deterministic exact fixture manifest' {
        (Assert-OPA265BW4k7uSyntheticSuite -Suite $script:suite) | Should -BeTrue
    }
    It 'suite same ID produces same manifest' {
        $again=New-OPA265BW4k7uSyntheticSuite -SuiteId $script:id; $again.ManifestSha256 | Should -BeExactly $script:suite.ManifestSha256
    }
    It 'suite different ID yields a new manifest' {
        $next=New-OPA265BW4k7uSyntheticSuite; $next.ManifestSha256 | Should -Not -BeExactly $script:suite.ManifestSha256
    }
    It 'rejects invalid canonical suite id' {
        {New-OPA265BW4k7uSyntheticSuite -SuiteId 'not-a-guid'} | Should -Throw
    }
    It 'rejects uppercase GUID suite id' {
        {New-OPA265BW4k7uSyntheticSuite -SuiteId $script:id.ToUpperInvariant()} | Should -Throw
    }
    It 'rejects zero GUID suite id' {
        {New-OPA265BW4k7uSyntheticSuite -SuiteId '00000000-0000-0000-0000-000000000000'} | Should -Throw
    }
    It 'no customer mail allowed in suite' {
        $s=Copy-OPA265BW4k7uObject -Value $script:suite; $s.Cases[0].Body='user mail'; {Assert-OPA265BW4k7uSyntheticSuite -Suite $s} | Should -Throw
    }
    It 'tampered manifest sha rejected' {
        $s=Copy-OPA265BW4k7uObject -Value $script:suite; $s.ManifestSha256='0'*64; {Assert-OPA265BW4k7uSyntheticSuite -Suite $s} | Should -Throw
    }
    It 'fake writer true in suite rejected' {
        $s=Copy-OPA265BW4k7uObject -Value $script:suite; $s.WriterPermit=$true; {Assert-OPA265BW4k7uSyntheticSuite -Suite $s} | Should -Throw
    }
    It 'fixture count decreased rejected' {
        $s=Copy-OPA265BW4k7uObject -Value $script:suite; $s.FixtureCount=11; {Assert-OPA265BW4k7uSyntheticSuite -Suite $s} | Should -Throw
    }
    It 'suite has eight eligible MailItems' {
        @($script:suite.Cases | Where-Object {$_.Kind -eq 'Mail' -and $_.EligibleForArchive}).Count | Should -Be 8
    }
    It 'suite includes exactly two synthetic Sent Items' {
        @($script:suite.Cases | Where-Object {$_.Role -eq 'SentItems'}).Count | Should -Be 2
    }
    It 'suite includes two synthetic custom folder emails' {
        @($script:suite.Cases | Where-Object {$_.Role -eq 'UserMail'}).Count | Should -Be 2
    }
    It 'suite includes future 2026 email preserved' {
        @($script:suite.Cases | Where-Object {$_.Year -eq 2026 -and -not $_.EligibleForArchive}).Count | Should -Be 1
    }
    It 'suite includes three nonmail types' {
        @($script:suite.Cases | Where-Object {$_.Class -ne 43}).Count | Should -Be 3
    }
    It 'suite includes exact one synthetic NDR' {
        @($script:suite.Cases | Where-Object {$_.MessageClass -eq 'Report.IPM.Note.NDR'}).Count | Should -Be 1
    }
    It 'suite includes exact one synthetic read receipt' {
        @($script:suite.Cases | Where-Object {$_.MessageClass -eq 'Report.IPM.Note.IPNRN'}).Count | Should -Be 1
    }
    It 'suite includes exact one synthetic meeting request' {
        @($script:suite.Cases | Where-Object {$_.MessageClass -eq 'IPM.Schedule.Meeting.Request'}).Count | Should -Be 1
    }
    It 'sent fixture has Bcc recipient' {
        $s=@($script:suite.Cases | Where-Object {$_.Role -eq 'SentItems'})[0]; @($s.RecipientsBcc).Count | Should -Be 1
    }
    It 'custom nested folder path exact' {
        $s=@($script:suite.Cases | Where-Object {$_.Name -eq 'User2022Nested'})[0]; $s.SourceFolderPath | Should -BeExactly '\Projects\Alpha\2022'
    }
    It 'unicode body preserved' {
        $s=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2021Unicode'})[0]; $s.Body | Should -Match 'Привет'
    }
    It 'HTML fixture has html markup' {
        $s=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2024Html'})[0]; $s.HtmlBody | Should -Match '<html>'
    }
    It 'synthetic 1KiB attachment actual length' {
        $s=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2025Attachment1K'})[0]; [Convert]::FromBase64String($s.Attachments[0].BytesBase64).Length | Should -Be 1024
    }
    It 'synthetic 256KiB attachment actual length' {
        $s=@($script:suite.Cases | Where-Object {$_.Name -eq 'Sent2025Attachment256K'})[0]; [Convert]::FromBase64String($s.Attachments[0].BytesBase64).Length | Should -Be 262144
    }
    It 'actual byte SHA256 of synthetic attachment pinned' {
        $s=@($script:suite.Cases | Where-Object {$_.Name -eq 'Sent2025Attachment256K'})[0]; $raw=[Convert]::FromBase64String($s.Attachments[0].BytesBase64); (Get-OPA265BW4k7uByteHash -Bytes $raw) | Should -BeExactly $s.Attachments[0].PayloadSha256
    }
    It 'default plan eight allocations' {
        @($script:plan.Allocations).Count | Should -Be 8
    }
    It 'default plan four excluded preserved objects' {
        @($script:plan.PreservedObjects).Count | Should -Be 4
    }
    It 'planned years all earlier than 2026' {
        @($script:plan.Allocations | Where-Object {$_.Year -ge 2026}).Count | Should -Be 0
    }
    It 'planning never creates PST' {
        $script:plan.RealPstCreated | Should -BeFalse
    }
    It 'planning never allows Outlook Move' {
        $script:plan.OutlookMoveAllowed | Should -BeFalse
    }
    It 'planning retains user folder hierarchy' {
        $script:plan.FolderHierarchyRemainsUnchanged | Should -BeTrue
    }
    It 'allocated folder path equals source path' {
        @($script:plan.Allocations | Where-Object {$_.OriginalFolderPath -cne $_.ArchiveFolderPath}).Count | Should -Be 0
    }
    It 'year 2020 planned filename exact' {
        $p=@($script:plan.Allocations | Where-Object {$_.Year -eq 2020})[0]; $p.ArchivePstFileName | Should -BeExactly 'info@stios.ru.Archive-2020.pst'
    }
    It 'year 2025 planned filename exact' {
        $p=@($script:plan.Allocations | Where-Object {$_.Year -eq 2025})[0]; $p.ArchivePstFileName | Should -BeExactly 'info@stios.ru.Archive-2025.pst'
    }
    It 'current year remains in source' {
        $p=@($script:plan.PreservedObjects | Where-Object {$_.Year -eq 2026}); $p.Count | Should -Be 1; $p[0].Reason | Should -BeExactly 'CurrentYearRetained'
    }
    It 'all three nonmail remain in source' {
        @($script:plan.PreservedObjects | Where-Object {$_.Reason -eq 'NonMailPreservedRequiresClassSpecificProof'}).Count | Should -Be 3
    }
    It 'default cap from BW4k7r is 45 billion' {
        $script:plan.PlannedMaxPstBytes | Should -Be 45000000000
    }
    It 'default safety margin 3 billion' {
        $script:plan.PlannedSafetyMarginBytes | Should -Be 3000000000
    }
    It 'default usable estimated segment 42 billion' {
        $script:plan.EffectiveSimulatedSegmentBytes | Should -Be 42000000000
    }
    It 'artificial small cap induces 2025 rollover -02' {
        $p=Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $script:suite -SimulatedSegmentCapBytes 420000; $rows=@($p.Allocations | Where-Object {$_.Year -eq 2025}); @($rows | Where-Object {$_.ArchivePstFileName -eq 'info@stios.ru.Archive-2025-02.pst'}).Count | Should -Be 1
    }
    It 'artificial rollover indicates simulation' {
        $p=Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $script:suite -SimulatedSegmentCapBytes 420000; $p.ArtificialRolloverCapUsed | Should -BeTrue; $p.RealPstCreated | Should -BeFalse
    }
    It 'tiny artificial cap rejects oversized 256K fixture' {
        {Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $script:suite -SimulatedSegmentCapBytes 65536} | Should -Throw
    }
    It 'invalid artificial cap larger than safe segment rejects' {
        {Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $script:suite -SimulatedSegmentCapBytes 43000000000} | Should -Throw
    }
    It 'unsafe default margin rejects' {
        {Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $script:suite -MaxArchivePstSizeBytes 104857600 -SafetyMarginBytes 104857600} | Should -Throw
    }
    It 'age cutoff 2025 excludes all 2025 fixtures' {
        $p=Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $script:suite -ArchiveBeforeYear 2025; @($p.Allocations | Where-Object {$_.Year -ge 2025}).Count | Should -Be 0
    }
    It 'age cutoff 2025 ledger supports reduced count' {
        $p=Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $script:suite -ArchiveBeforeYear 2025; $l=New-OPA265BW4k7uSyntheticLedger -Suite $script:suite -CapacityPlan $p; @($l.Rows).Count | Should -Be @($p.Allocations).Count
    }
    It 'ledger default eight eligible rows' {
        @((New-BW4k7uLedger).Rows).Count | Should -Be 8
    }
    It 'ledger never writes real journal' {
        (New-BW4k7uLedger).DiskJournalOrClaimCreated | Should -BeFalse
    }
    It 'ledger never grants automatic retry' {
        (New-BW4k7uLedger).AutomaticRetryAllowed | Should -BeFalse
    }
    It 'ledger default state source only' {
        $l=New-BW4k7uLedger; @($l.Rows | Where-Object {$_.State -ne 'UnclaimedSourceOnly'}).Count | Should -Be 0
    }
    It 'ledger wrong suite plan rejects' {
        $other=New-OPA265BW4k7uSyntheticSuite; $p=Get-OPA265BW4k7uSyntheticCapacityPlan -Suite $other; {New-OPA265BW4k7uSyntheticLedger -Suite $script:suite -CapacityPlan $p} | Should -Throw
    }
    It 'ledger allocation wrong folder rejects' {
        $p=Copy-OPA265BW4k7uObject -Value $script:plan; $p.Allocations[0].ArchiveFolderPath='\Other'; {New-OPA265BW4k7uSyntheticLedger -Suite $script:suite -CapacityPlan $p} | Should -Throw
    }
    It 'ledger allocation wrong PST name rejects' {
        $p=Copy-OPA265BW4k7uObject -Value $script:plan; $p.Allocations[0].ArchivePstFileName='..\injected.pst'; {New-OPA265BW4k7uSyntheticLedger -Suite $script:suite -CapacityPlan $p} | Should -Throw
    }
    It 'ledger allocation duplicate case rejects' {
        $p=Copy-OPA265BW4k7uObject -Value $script:plan; $p.Allocations[1].CaseId=$p.Allocations[0].CaseId; {New-OPA265BW4k7uSyntheticLedger -Suite $script:suite -CapacityPlan $p} | Should -Throw
    }
    It 'intent sets only in-memory state' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $r=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent; $r.State | Should -BeExactly 'ModeledIntentNoDiskClaim'; $r.DurableClaimWritten | Should -BeFalse
    }
    It 'duplicate intent rejects' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent; {Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent} | Should -Throw
    }
    It 'claim cannot precede intent' {
        $l=New-BW4k7uLedger; {Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $l.Rows[0].CaseId -Phase Claim} | Should -Throw
    }
    It 'model Move cannot precede claim' {
        $l=New-BW4k7uLedger; {Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $l.Rows[0].CaseId -Phase ModelMove} | Should -Throw
    }
    It 'claim state leaves source and has attempt one' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Claim; $l.Rows[0].SourceExists | Should -BeTrue; $l.Rows[0].ModelAttemptCount | Should -Be 1
    }
    It 'duplicate claim rejects' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Claim; {Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Claim} | Should -Throw
    }
    It 'claimed-only reconciles to manual no retry' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Claim; $r=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Reconcile; $r.State | Should -BeExactly 'ManualReviewClaimedSourceStillPresentNoRetry'
    }
    It 'model Move leaves destination one without source' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Claim; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase ModelMove; $l.Rows[0].DestinationExists | Should -BeTrue; $l.Rows[0].SourceExists | Should -BeFalse
    }
    It 'second model Move fails no blind replay' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Claim; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase ModelMove; {Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase ModelMove} | Should -Throw
    }
    It 'reconciliation of modeled destination confirms content only' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Intent; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Claim; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase ModelMove; (Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Reconcile).State | Should -BeExactly 'SyntheticReconciledRiskReviewOnly'
    }
    It 'second reconciliation rejected' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; foreach($phase in @('Intent','Claim','ModelMove','Reconcile')){$null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase $phase}; {Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Reconcile} | Should -Throw
    }
    It 'same fixture witness matches significant fields' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Sent2025Attachment256K'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeTrue
    }
    It 'semantic synthetic class C unknown not auto waived' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Sent2025Attachment256K'})[0]; $r=Compare-OPA265BW4k7uSyntheticWitness -Before $x -After (Copy-OPA265BW4k7uObject -Value $x); $r.ProspectivePolicyCategory | Should -BeExactly 'C'; $r.ProspectiveSemanticPolicy.UndocumentedBitAutomaticallyWaived | Should -BeFalse
    }
    It 'semantic synthetic size drift recorded' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2020Plain'})[0]; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After (Copy-OPA265BW4k7uObject -Value $x)).ModeledMailItemSizeDelta | Should -Be 38
    }
    It 'semantic synthetic no real MAPI proof' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2020Plain'})[0]; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After (Copy-OPA265BW4k7uObject -Value $x)).RealOutlookPostMoveProof | Should -BeFalse
    }
    It 'changed subject is detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2020Plain'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.Subject='changed'; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeFalse
    }
    It 'changed plain body is detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2021Unicode'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.Body='tampered'; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeFalse
    }
    It 'changed HTML body is detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2024Html'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.HtmlBody='<html>other</html>'; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeFalse
    }
    It 'changed Sent Bcc recipient is detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Sent2023Unicode'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.RecipientsBcc=@('other@example.invalid'); (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeFalse
    }
    It 'changed sender is detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2020Plain'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.Sender='other@example.invalid'; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeFalse
    }
    It 'changed attachment payload exact bytes detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Sent2025Attachment256K'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.Attachments[0].BytesBase64=[Convert]::ToBase64String([byte[]](1,2,3)); (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).ExactAttachmentBytesAndSha256Matched | Should -BeFalse
    }
    It 'changed attachment digest detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2025Attachment1K'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.Attachments[0].PayloadSha256='0'*64; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeFalse
    }
    It 'changed folder path detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'User2022Nested'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.SourceFolderPath='\Else'; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeFalse
    }
    It 'changed category detected' {
        $x=@($script:suite.Cases | Where-Object {$_.Name -eq 'Inbox2020Plain'})[0]; $y=Copy-OPA265BW4k7uObject -Value $x; $y.Categories='different'; (Compare-OPA265BW4k7uSyntheticWitness -Before $x -After $y).SemanticFieldsMatched | Should -BeFalse
    }
    It 'reconcile tampered destination blocks without retry' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; foreach($phase in @('Intent','Claim','ModelMove')){$null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase $phase}; $l.Rows[0].DestinationFixture.Body='damage'; (Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Reconcile).State | Should -BeExactly 'BlockedSemanticMismatchNeverRetry'
    }
    It 'full batch model reconciles all eight' {
        $l=New-BW4k7uLedger; $r=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l; $r.AllEightSyntheticMailCasesReconciled | Should -BeTrue
    }
    It 'full batch has eight one-shot modeled attempts' {
        $l=New-BW4k7uLedger; $r=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l; $r.ModelAttemptCount | Should -Be 8
    }
    It 'full batch has eight modeled claims' {
        $l=New-BW4k7uLedger; $r=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l; $r.ModeledClaimCount | Should -Be 8
    }
    It 'full batch no physical move' {
        $l=New-BW4k7uLedger; $r=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l; $r.OutlookMoveExecuted | Should -BeFalse
    }
    It 'full batch never allows auto resume' {
        $l=New-BW4k7uLedger; $r=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l; $r.ResumeOrRetryAutomaticallyAllowed | Should -BeFalse
    }
    It 'full batch no durable crash proof' {
        $l=New-BW4k7uLedger; $r=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l; $r.ActualCrashOrRestartRecoveryProven | Should -BeFalse
    }
    It 'full batch cannot be run second time' {
        $l=New-BW4k7uLedger; $null=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l; {Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l} | Should -Throw
    }
    It 'fault AfterIntent preserves no claim' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $r=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l -FaultPoint AfterIntent -FaultCaseId $id; $l.Rows[0].ClaimPinnedInMemory | Should -BeFalse; $r.ResumeOrRetryAutomaticallyAllowed | Should -BeFalse
    }
    It 'fault AfterClaim leaves claimed source only' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l -FaultPoint AfterClaim -FaultCaseId $id; $l.Rows[0].SourceExists | Should -BeTrue; $l.Rows[0].ClaimPinnedInMemory | Should -BeTrue
    }
    It 'fault AfterMove leaves destination unreviewed' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l -FaultPoint AfterMove -FaultCaseId $id; $l.Rows[0].DestinationExists | Should -BeTrue; $l.Rows[0].IndependentlyReviewed | Should -BeFalse
    }
    It 'faulted batch must not automatically restart' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l -FaultPoint AfterClaim -FaultCaseId $id; {Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l} | Should -Throw
    }
    It 'after claim recovery cannot issue second Move' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l -FaultPoint AfterClaim -FaultCaseId $id; $null=Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Reconcile; {Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase ModelMove} | Should -Throw
    }
    It 'after move reconciliation allowed only read-only model' {
        $l=New-BW4k7uLedger; $id=$l.Rows[0].CaseId; $null=Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l -FaultPoint AfterMove -FaultCaseId $id; (Set-OPA265BW4k7uSyntheticPhase -Ledger $l -CaseId $id -Phase Reconcile).State | Should -BeExactly 'SyntheticReconciledRiskReviewOnly'
    }
    It 'inject fault unknown case rejected before model change' {
        $l=New-BW4k7uLedger; {Invoke-OPA265BW4k7uSyntheticBatch -Ledger $l -FaultPoint AfterClaim -FaultCaseId 'bad'} | Should -Throw; $l.BatchStatus | Should -BeExactly 'FreshSyntheticBatch'
    }
    It 'controller plan only no simulated Move' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1') -SuiteId $script:id -PlanOnly; $r.Status | Should -BeExactly 'SyntheticPlanOnlyNoSimulatedMoves'; $r.RecoveryReview | Should -BeNullOrEmpty
    }
    It 'controller WhatIf plan only no actual Move' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1') -SuiteId $script:id -WhatIf; $r.Status | Should -BeExactly 'WhatIfSyntheticPlanOnlyNoExternalContacts'
    }
    It 'controller default eight simulated verified' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1') -SuiteId $script:id; $r.RecoveryReview.AllEightSyntheticMailCasesReconciled | Should -BeTrue
    }
    It 'controller injection AfterClaim halts manual no auto retry' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1') -SuiteId $script:id -FaultPoint AfterClaim -FaultCaseName Inbox2020Plain; $r.Status | Should -BeExactly 'SyntheticFaultInjectedManualRecoveryNoAutomaticRetry'; $r.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'controller refuses non-eligible current-year injection' {
        {& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1') -SuiteId $script:id -FaultPoint AfterClaim -FaultCaseName Inbox2026Retained} | Should -Throw
    }
    It 'controller never reads real Outlook or registry' {
        $code=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1'); $code | Should -Not -Match 'GetActiveObject|GetNamespace|Get-ItemProperty|Get-Item -LiteralPath|New-ItemProperty'
    }
    It 'controller never calls MailItem Move or Save' {
        $code=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1'); $code | Should -Not -Match '[.](Move|Save|Delete|AddStoreEx|SetProperty)[ ]*[(]'
    }
    It 'worker never calls MailItem Move or Save' {
        $code=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../../Core/Worker/BW4k7uSyntheticBatch265.ps1'); $code | Should -Not -Match '[.](Move|Save|Delete|AddStoreEx|SetProperty)[ ]*[(]'
    }
    It 'controller preserves old BW4k7m Claim' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1') -SuiteId $script:id -PlanOnly; $r.OldBW4k7mIrreversibleClaimUntouched | Should -BeTrue
    }
    It 'controller SEM-001 risk is not automatically waived' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1') -SuiteId $script:id -PlanOnly; $r.OriginalBW4k7tSEM001PolicyNotWaived | Should -BeTrue
    }
    It 'controller never enables production' {
        $r=& (Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4k7uSyntheticMultiItemPreflight.ps1') -SuiteId $script:id -PlanOnly; $r.WriterPermit | Should -BeFalse; $r.ProductionReady | Should -BeFalse
    }
}
