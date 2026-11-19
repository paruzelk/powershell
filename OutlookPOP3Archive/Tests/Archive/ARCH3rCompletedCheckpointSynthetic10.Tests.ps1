#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3rTenItemSyntheticIntegration.ps1')
    $script:checkpoint=@{
        RunId='9d276dc4-a0e6-4e74-891f-81502fafe7db'
        IntentSha256='f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b'
        JournalSha256='a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'
        ReviewSha256='3c455f4da4ee32fd9f0d046ac5e36cc3d013c0913cf86ddee69d359f700831c3'
        CommitClaimSha256='fc0e51d828d3b82fb3e46b22bdca6ff50f54f86366d1f9ec5ff5c937e221527a'
        CommitSealSha256='0fa26ba60ebe9685a6b13c5f989b1c5a840f54d5bc8302f87679b4e7dc6e67f0'
    }
}
Describe 'ARCH3r original completed REAL pilot immutable historical checkpoint' {
    It 'rejects a different operator RunId before reading the original journal/index' {
        $p=$script:checkpoint.Clone();$p.RunId='00000000-0000-0000-0000-000000000000'
        {Assert-OPA265ARCH3rRealCheckpointPins @p} | Should -Throw
    }
    It 'rejects modified completed original OperationJournal Intent SHA' {
        $p=$script:checkpoint.Clone();$p.JournalSha256=('f'*64)
        {Assert-OPA265ARCH3rRealCheckpointPins @p} | Should -Throw
    }
    It 'rejects modified independent ARCH3p/ARCH3q ReviewSeal SHA' {
        $p=$script:checkpoint.Clone();$p.ReviewSha256=('f'*64)
        {Assert-OPA265ARCH3rRealCheckpointPins @p} | Should -Throw
    }
    It 'rejects modified original final commit seal SHA' {
        $p=$script:checkpoint.Clone();$p.CommitSealSha256=('f'*64)
        {Assert-OPA265ARCH3rRealCheckpointPins @p} | Should -Throw
    }
    It 'accepts exactly the real completed source, journal and index pins' {
        {Assert-OPA265ARCH3rRealCheckpointPins @script:checkpoint} | Should -Not -Throw
    }
    It 'public ARCH3r modes never expose Move Resume Archive or a production writer' {
        $cli=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3r.ps1') -Raw -Encoding UTF8
        $cli | Should -Match "ValidateSet\('Plan','Audit','Synthetic10'\)"
        $cli | Should -Not -Match "ValidateSet\([^)]*'Move'"
        $cli | Should -Not -Match "ValidateSet\([^)]*'Resume'"
    }
    It 'every new PowerShell source is UTF8 with BOM EF BB BF' {
        foreach($relative in @('Invoke-ARCH3r.ps1','Core/Archive/ARCH3rCompletedPilotCheckpoint.ps1',
            'Core/Archive/ARCH3rTenItemSyntheticIntegration.ps1')){
            $b=[IO.File]::ReadAllBytes((Join-Path $script:root $relative))
            $b[0] | Should -Be 239
            $b[1] | Should -Be 187
            $b[2] | Should -Be 191
        }
    }
}
Describe 'ARCH3r original ten independent FULL semantic fixtures, no Outlook' {
    It 'creates exactly ten distinct original SourceEntryIds and DestinationEntryIds' {
        $rows=@(New-OPA265ARCH3rTenSyntheticPlan)
        $rows.Count | Should -Be 10
        @($rows.SourceEntryId | Select-Object -Unique).Count | Should -Be 10
        @($rows.ArchiveEntryId | Select-Object -Unique).Count | Should -Be 10
    }
    It 'original ARCH2b full witness schema accepts each synthetic letter and attachment payload' {
        $rows=@(New-OPA265ARCH3rTenSyntheticPlan)
        foreach($x in $rows){
            (Test-OPA265ARCH2bWitnessSchema -Witness $x.SourceWitness) | Should -BeTrue
            $x.OriginalSourceWitnessDigest | Should -Match '^[a-f0-9]{64}$'
        }
        @($rows | Where-Object {$_.SourceWitness.AttachmentCount -gt 0}).Count | Should -BeGreaterThan 0
    }
    It 'different synthetic messages have different body and HTML SHA' {
        $one=New-OPA265ARCH3rSyntheticWitness -Number 1
        $two=New-OPA265ARCH3rSyntheticWitness -Number 2
        $one.BodySha256 | Should -Not -BeExactly $two.BodySha256
        $one.HtmlBodySha256 | Should -Not -BeExactly $two.HtmlBodySha256
    }
    It 'original full comparer matches two separately reconstructed copies of one synthetic mail' {
        $left=New-OPA265ARCH3rSyntheticWitness -Number 4
        $right=New-OPA265ARCH3rSyntheticWitness -Number 4
        $result=Compare-OPA265ARCH2bMailSemanticWitness -Source $left -Destination $right
        $result.CriticalContentMatches | Should -BeTrue
        @($result.IssueCodes).Count | Should -Be 0
    }
    It 'original full comparer detects modified virtual HTML sha' {
        $left=New-OPA265ARCH3rSyntheticWitness -Number 4
        $right=New-OPA265ARCH3rSyntheticWitness -Number 4
        $right.HtmlBodySha256='f'*64
        (Compare-OPA265ARCH2bMailSemanticWitness -Source $left -Destination $right).CriticalContentMatches | Should -BeFalse
    }
    It 'original full comparer detects changed attachment payload sha independent of size' {
        $left=New-OPA265ARCH3rSyntheticWitness -Number 4
        $right=New-OPA265ARCH3rSyntheticWitness -Number 4
        $right.Attachments[0].PayloadSha256='f'*64
        $comparison=Compare-OPA265ARCH2bMailSemanticWitness -Source $left -Destination $right
        $comparison.CriticalContentMatches | Should -BeFalse
        @($comparison.IssueCodes | Where-Object {$_ -like '*PayloadSha256'}).Count | Should -BeGreaterThan 0
    }
    It 'rejects duplicate source selector before allocating any synthetic writer workspace' {
        $dirsBefore=@([IO.Directory]::GetDirectories($TestDrive)).Count
        {Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault DuplicateSource} | Should -Throw
        @([IO.Directory]::GetDirectories($TestDrive)).Count | Should -Be $dirsBefore
    }
    It 'rejects duplicate destination selector before allocating any synthetic writer workspace' {
        $dirsBefore=@([IO.Directory]::GetDirectories($TestDrive)).Count
        {Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault DuplicateDestination} | Should -Throw
        @([IO.Directory]::GetDirectories($TestDrive)).Count | Should -Be $dirsBefore
    }
    It 'rejects attempts to write synthetic files outside OS TEMP' {
        $outside=[IO.Path]::GetPathRoot($TestDrive)
        {Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $outside} | Should -Throw
    }
}
Describe 'ARCH3r 10 synthetic claimed operations original journal/index and independent TEMP readback' {
    It 'successfully reconciles ten simulated original journal operations and appends 10 index entries' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive
        $r.Status | Should -BeExactly 'AllTenSyntheticFullSemanticAndOriginalJournalIndexReadbackPassedNoLiveWriter'
        $r.SyntheticPlannedMessages | Should -Be 10
        $r.SyntheticMoveClaims | Should -Be 10
        $r.SyntheticProviderInvocations | Should -Be 10
        $r.SyntheticFullSemanticComparisons | Should -Be 10
        $r.OriginalOperationJournalEventCount | Should -Be 20
        $r.OriginalOperationJournalReconciledCount | Should -Be 10
        $r.OriginalOperationJournalIndeterminateCount | Should -Be 0
        $r.OriginalSharedIndexEntryCount | Should -Be 10
        $r.OriginalArchiveVerifierOutlookCOMExecuted | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'uses original durable CreateNew MoveClaim and ProviderInvocation SHA at all ten items' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive
        foreach($i in 1..10){
            $c=Join-Path $r.SyntheticWorkspace ('SYNTH-MoveClaim-'+$i+'.json')
            $p=Join-Path $r.SyntheticWorkspace ('SYNTH-ProviderInvocation-'+$i+'.json')
            [IO.File]::Exists($c) | Should -BeTrue
            [IO.File]::Exists($p) | Should -BeTrue
            $ch=(Get-FileHash -LiteralPath $c -Algorithm SHA256).Hash.ToLowerInvariant()
            $record=Read-OPA265ARCH3cPinnedJson -Path $c -ExpectedSha256 $ch
            $record.AutomaticMoveRetryAllowed | Should -BeFalse
        }
    }
    It 'cannot overwrite an existing synthetic irreversible claim file through original writer' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive
        $path=Join-Path $r.SyntheticWorkspace 'SYNTH-MoveClaim-1.json'
        $old=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        {Write-OPA265ARCH3cJsonOnce -Path $path -Record ([pscustomobject]@{Inject='RETRY'})} | Should -Throw
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -BeExactly $old
    }
    It 'original DuplicateIndex readback contains ten unique source/archive pairings' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive
        $idx=Import-OPADuplicateIndex -ArchivePst (Join-Path $r.SyntheticWorkspace 'SYNTHETIC-NOT-A-REAL-PST.pst')
        @($idx.Entries).Count | Should -Be 10
        foreach($n in 1..10){
            $source=('{0:X32}' -f $n)
            $archive=('{0:X32}' -f (40960+$n))
            $found=Test-OPADuplicateEntry -Index $idx -SourceEntryId $source
            $found.ArchiveEntryId | Should -BeExactly $archive
        }
    }
    It 'provider unknown stops before original Reconciled and original index writes' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault ProviderUnknown -FaultAt 4
        $r.Status | Should -BeExactly 'SimulatedProviderUnknownOriginalJournalIntentOnlyNoReplay'
        $r.SyntheticMoveClaims | Should -Be 4
        $r.OriginalOperationJournalReconciledCount | Should -Be 0
        $r.OriginalSharedIndexEntryCount | Should -Be 0
        $r.AutomaticMoveRetryAllowed | Should -BeFalse
    }
    It 'crash after claim but before provider stops without retry or Reconciled' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault AfterClaimBeforeProvider -FaultAt 4
        $r.Status | Should -BeExactly 'SimulatedAfterClaimUnknownNoAutomaticRetry'
        $r.SyntheticMoveClaims | Should -Be 4
        $r.SyntheticProviderInvocations | Should -Be 3
        $r.OriginalOperationJournalEventCount | Should -Be 10
        $r.OriginalSharedIndexEntryCount | Should -Be 0
    }
    It 'HTML drift blocks all ten original journal reconciliations and index appends' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault HtmlDrift -FaultAt 4
        $r.Status | Should -BeExactly 'SimulatedCriticalContentMismatchNoOriginalJournalOrIndexCommit'
        $r.SyntheticFullSemanticComparisons | Should -Be 4
        $r.OriginalOperationJournalReconciledCount | Should -Be 0
        $r.OriginalSharedIndexEntryCount | Should -Be 0
    }
    It 'attachment SHA drift blocks all journal and index commits, even when size unchanged' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault AttachmentDrift -FaultAt 4
        $r.Status | Should -BeExactly 'SimulatedCriticalContentMismatchNoOriginalJournalOrIndexCommit'
        $r.SyntheticFullSemanticComparisons | Should -Be 4
        $r.OriginalSharedIndexEntryCount | Should -Be 0
    }
    It 'partial Reconciled journal after third simulated item never auto-appends index' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault AfterJournalReconciled -FaultAt 3
        $r.Status | Should -BeExactly 'SimulatedPartiallyReconciledOriginalJournalNoIndexNoAutoRetry'
        $r.OriginalOperationJournalEventCount | Should -Be 13
        $r.OriginalOperationJournalReconciledCount | Should -Be 3
        $r.OriginalSharedIndexEntryCount | Should -Be 0
    }
    It 'partial index append after two items has 20 journal events but only 2 entries' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault AfterIndexAppend -FaultAt 2
        $r.Status | Should -BeExactly 'SimulatedPartialOriginalIndexAppendNoAutoReplay'
        $r.OriginalOperationJournalEventCount | Should -Be 20
        $r.OriginalOperationJournalReconciledCount | Should -Be 10
        $r.OriginalSharedIndexEntryCount | Should -Be 2
    }
    It 'does not allow a corrupt synthetic old claim to be reread as valid SHA' {
        $r=Invoke-OPA265ARCH3rSyntheticTen -SyntheticTempRoot $TestDrive -InjectFault ProviderUnknown -FaultAt 1
        $path=Join-Path $r.SyntheticWorkspace 'SYNTH-MoveClaim-1.json'
        $wrong='f'*64
        {Read-OPA265ARCH3cPinnedJson -Path $path -ExpectedSha256 $wrong} | Should -Throw
    }
}
