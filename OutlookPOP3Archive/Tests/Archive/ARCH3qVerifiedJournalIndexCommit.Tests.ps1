#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3qVerifiedJournalIndexCommit.ps1')
    $script:run='9d276dc4-a0e6-4e74-891f-81502fafe7db'
    $script:pin=@{
        RunId=$script:run
        IntentSha256='f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b'
        JournalSha256='a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'
    }
    function New-ARCH3qFakeReview {
        [pscustomobject]@{
            Schema='2.6.5-ARCH3p.IndependentRealOutlookOriginalVerifierReview.1'
            Status='IndependentRealOutlookRestartOriginalArchiveVerifierSourceAbsentArchiveOneFullSemanticMatch'
            RunId=$script:run
            OriginalMoveClaimSha256='2d43dc624c5f58293c74aafee0772af097f84d3fb1fd8940621e9db92006ae70'
            OriginalProviderInvocationSha256='ac0d0cde82869cc47e58d31d3ac677227a9cb03ef4982b69e859cd5009fd4bb9'
            OriginalMoveReceiptSha256='f76ef15fa88000ad747f5fba3b385c5b033ada3978828bbf7a6b71aa8140f2d8'
            OriginalSourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
            ObservedDestinationEntryId='00000000CB201CE90F11EB4AB6F01B5E5BEF7CED24002000'
            ArchivePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.Archive-2020-02.pst'
            OriginalWitnessSha256='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
            OriginalVerifierDestinationCount=1
            OriginalVerifierSourceIdAbsent=$true;OriginalVerifierSemanticMatch=$true
            OriginalArchiveVerifierUsed=$true;RealOutlookRestartConfirmed=$true
            ReopenedOutlookProcessId=13040;OriginalMoveOutlookProcessId=11168
            ReopenedOutlookProcessStartUtcTicks=[long]639306827738688879
            OriginalMoveOutlookProcessStartUtcTicks=[long]639300867186071455
            AutomaticMoveRetryAllowed=$false;DuplicateIndexWritten=$false
            OriginalOperationJournalReconciled=$false
            ArchiveFolderPath='\\Архив info@stios.ru 2020 ч.2\2020\Входящие'
        }
    }
    function New-ARCH3qFakeState {
        $entry=[pscustomobject]@{
            RunId=$script:run;SourceEntryId='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
            FullOriginalWitnessSha256='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
            SourceSealRunId='3773bcd7-5a07-4c31-8ce5-dfb16ddd30bf'
            SourceSealSha256='5f5a86b6c1aba8a3d2ee328a36a5632f8edf1e89fdda8e7fd728688fe881b2a4'
            ExistingArchivePart1='C:\fake\part1.pst'
            NewArchivePst='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.Archive-2020-02.pst'
            SourcePst='C:\fake\info@stios.ru.pst'
            OperationId='ARCH3b-2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
        }
        $event=[pscustomobject]@{
            SourceFolderPath='\\info@stios.ru\Входящие'
            InternetMessageId='<test@invalid>'
            Subject='ARCH3q fixture';Sender='synthetic@invalid';Size=[long]1024
        }
        return [pscustomobject]@{
            Intent=$entry;Layout=[pscustomobject]@{Root='C:\fake\protected';JournalPath='C:\fake\original-operation-journal.jsonl'}
            Journal=[pscustomobject]@{Events=@($event)}
            JournalPhase='Intent';IndexCount=500;ExistingIndexEntry=$null
            ProofExists=$false;ClaimExists=$false;SealExists=$false
            ProofPath='C:\fake\ARCH3q-IndependentReview.json'
            ClaimPath='C:\fake\ARCH3q-CommitClaim.json'
            SealPath='C:\fake\ARCH3q-IndexCommitted.json'
            Index=[pscustomobject]@{Entries=@()}
            JournalSha256=('a'*64)
        }
    }
}
Describe 'ARCH3q public mode and original safety chain are closed to Move' {
    It 'exposes Plan Seal Commit Recover Status Review, NOT Move or Resume' {
        $s=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3q.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Plan','Seal','Commit','Recover','Status','Review'\)"
        $s | Should -Not -Match "ValidateSet\([^)]*'Move'"
        $s | Should -Match 'ConfirmVerifiedCommit'
    }
    It 'retains utf8 BOM in all new PowerShell sources' {
        foreach($name in @('Invoke-ARCH3q.ps1','Core/Archive/ARCH3qState.ps1',
            'Core/Archive/ARCH3qEvidence.ps1','Core/Archive/ARCH3qVerifiedJournalIndexCommit.ps1')){
            $path=Join-Path $script:root $name
            $bytes=[IO.File]::ReadAllBytes($path)
            @($bytes[0..2]) | Should -Be @(239,187,191)
        }
    }
    It 'keeps original journal and index APIs instead of a new index writer' {
        $c=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3qVerifiedJournalIndexCommit.ps1') -Raw -Encoding UTF8
        $c | Should -Match 'Write-OPAOperationJournalEvent @args'
        $c | Should -Match 'Add-OPADuplicateEntry @params'
        $c | Should -Match 'Import-OPADuplicateIndex -ArchivePst'
        $c | Should -Match 'Sync-OPADuplicateJournalStreams'
        $c | Should -Match 'Close-OPADuplicateJournalStreams'
        $c | Should -Not -Match '\.Move\('
    }
    It 'original journal byte prefix SHA is still enforced after Reconciled' {
        $c=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3qState.ps1') -Raw -Encoding UTF8
        $c | Should -Match 'Get-OPAOperationJournalSha256 -Bytes \$prefix'
        $c | Should -Match 'ARCH3q original Intent byte prefix'
        $c | Should -Match 'Original.*DuplicateIndex'
    }
    It 'requires independently restarted original ARCH3p ArchiveVerifier before Seal' {
        $c=Get-Content -LiteralPath (Join-Path $script:root 'Core/Archive/ARCH3qVerifiedJournalIndexCommit.ps1') -Raw -Encoding UTF8
        $c | Should -Match 'Invoke-OPA265ARCH3pIndependentRestartReview -Chain \$chain'
        $c | Should -Match 'Assert-OPA265ARCH3qLiveReview -Review'
    }
}
Describe 'ARCH3q complete real original verifier result strict gate' {
    BeforeEach {$script:s=New-ARCH3qFakeState;$script:r=New-ARCH3qFakeReview}
    It 'accepts exact operator-observed original real result' {
        {Assert-OPA265ARCH3qLiveReview -Review $script:r -State $script:s} | Should -Not -Throw
    }
    It 'rejects a different destination EntryID' {
        $script:r.ObservedDestinationEntryId='00000000FFFFFFFFFFFFFFFF'
        {Assert-OPA265ARCH3qLiveReview -Review $script:r -State $script:s} | Should -Throw
    }
    It 'rejects source still present' {
        $script:r.OriginalVerifierSourceIdAbsent=$false
        {Assert-OPA265ARCH3qLiveReview -Review $script:r -State $script:s} | Should -Throw
    }
    It 'rejects missing original semantic match' {
        $script:r.OriginalVerifierSemanticMatch=$false
        {Assert-OPA265ARCH3qLiveReview -Review $script:r -State $script:s} | Should -Throw
    }
    It 'rejects same Outlook process instead of independent restart' {
        $script:r.ReopenedOutlookProcessId=11168
        {Assert-OPA265ARCH3qLiveReview -Review $script:r -State $script:s} | Should -Throw
    }
    It 'rejects old or equal Outlook process creation ticks' {
        $script:r.ReopenedOutlookProcessStartUtcTicks=[long]639300867186071455
        {Assert-OPA265ARCH3qLiveReview -Review $script:r -State $script:s} | Should -Throw
    }
}
Describe 'ARCH3q operator state gates only before irreversible original commit' {
    BeforeEach {
        $script:s=New-ARCH3qFakeState
        $script:r=New-ARCH3qFakeReview
        $script:claimed=0;$script:journalAppends=0;$script:indexCommits=0;$script:realChecks=0
        Mock Get-OPA265ARCH3qState {return $script:s}
        Mock Get-OPA265ARCH3qReviewSeal {return [pscustomobject]@{Review=$script:r}}
        Mock New-OPA265ARCH3qLiveChain {return [pscustomobject]@{Claim=$null}}
        Mock Invoke-OPA265ARCH3pIndependentRestartReview {$script:realChecks++;return $script:r}
        Mock Write-OPA265ARCH3cJsonOnce {
            $script:claimed++
            return ('a'*64)
        }
        Mock Write-OPAOperationJournalEvent {$script:journalAppends++;$script:s.JournalPhase='Reconciled'}
        Mock Assert-OPA265ARCH3qOriginalJournalReconciled {return $true}
        Mock Write-OPA265ARCH3qIndexAndSeal {$script:indexCommits++;return [pscustomobject]@{Status='INDEX-501-FAKE'}}
    }
    It 'Plan is read-only, no Outlook contact or original journal/index writes' {
        $a=Invoke-OPA265ARCH3qCommit -Mode Plan @script:pin
        $a.OriginalIndexEntryCount | Should -Be 500
        $a.WriterPermit | Should -BeFalse
        $script:realChecks | Should -Be 0
        $script:journalAppends | Should -Be 0
    }
    It 'Status is read-only before Seal' {
        $a=Invoke-OPA265ARCH3qCommit -Mode Status @script:pin
        $a.OriginalJournalPhase | Should -BeExactly 'Intent'
        $a.CommitClaimed | Should -BeFalse
    }
    It 'Seal fails without explicit operator ConfirmSeal' {
        {Invoke-OPA265ARCH3qCommit -Mode Seal @script:pin -Confirm:$false} | Should -Throw
        $script:realChecks | Should -Be 0
    }
    It 'Seal WhatIf does not contact real Outlook or write evidence' {
        $a=Invoke-OPA265ARCH3qCommit -Mode Seal @script:pin -ConfirmSeal -WhatIf -Confirm:$false
        $a.NoWrites | Should -BeTrue
        $script:realChecks | Should -Be 0
        $script:claimed | Should -Be 0
    }
    It 'Seal invokes original real ARCH3p verifier and writes only protected proof' {
        $a=Invoke-OPA265ARCH3qCommit -Mode Seal @script:pin -ConfirmSeal -Confirm:$false
        $a.ReviewSha256 | Should -BeExactly ('a'*64)
        $script:realChecks | Should -Be 1
        $script:claimed | Should -Be 1
        $script:journalAppends | Should -Be 0
        $script:indexCommits | Should -Be 0
    }
    It 'Commit fails without explicit ConfirmVerifiedCommit' {
        $script:s.ProofExists=$true
        {Invoke-OPA265ARCH3qCommit -Mode Commit @script:pin -ReviewSha256 ('b'*64) -Confirm:$false} | Should -Throw
    }
    It 'Commit WhatIf leaves original journal and index untouched' {
        $script:s.ProofExists=$true
        $a=Invoke-OPA265ARCH3qCommit -Mode Commit @script:pin -ReviewSha256 ('b'*64) -ConfirmVerifiedCommit -WhatIf -Confirm:$false
        $a.NoWrites | Should -BeTrue
        $script:realChecks | Should -Be 0
        $script:journalAppends | Should -Be 0
    }
    It 'Commit orders original real verifier, one claim, one Reconciled, then one index operation' {
        $script:s.ProofExists=$true
        $a=Invoke-OPA265ARCH3qCommit -Mode Commit @script:pin -ReviewSha256 ('b'*64) -ConfirmVerifiedCommit -Confirm:$false
        $a.Status | Should -BeExactly 'INDEX-501-FAKE'
        $script:realChecks | Should -Be 1
        $script:claimed | Should -Be 1
        $script:journalAppends | Should -Be 1
        $script:indexCommits | Should -Be 1
    }
    It 'Commit refuses existing irreversible claim before a second journal append' {
        $script:s.ProofExists=$true;$script:s.ClaimExists=$true
        {Invoke-OPA265ARCH3qCommit -Mode Commit @script:pin -ReviewSha256 ('b'*64) -ConfirmVerifiedCommit -Confirm:$false} | Should -Throw
        $script:journalAppends | Should -Be 0
    }
    It 'Recover refuses prior Intent-only state, no duplicate original Reconciled' {
        $script:s.ProofExists=$true;$script:s.ClaimExists=$true
        {Invoke-OPA265ARCH3qCommit -Mode Recover @script:pin -ReviewSha256 ('b'*64) -CommitClaimSha256 ('a'*64) -ConfirmRecovery -Confirm:$false} | Should -Throw
        $script:journalAppends | Should -Be 0
    }
    It 'Recover only from prior Reconciled reuses real verifier and only recovers index' {
        $script:s.ProofExists=$true;$script:s.ClaimExists=$true;$script:s.JournalPhase='Reconciled'
        Mock Read-OPA265ARCH3cPinnedJson {[pscustomobject]@{ReviewSha256=('b'*64)}}
        $a=Invoke-OPA265ARCH3qCommit -Mode Recover @script:pin -ReviewSha256 ('b'*64) -CommitClaimSha256 ('a'*64) -ConfirmRecovery -Confirm:$false
        $a.Status | Should -BeExactly 'INDEX-501-FAKE'
        $script:realChecks | Should -Be 1
        $script:journalAppends | Should -Be 0
        $script:indexCommits | Should -Be 1
    }
    It 'Recover never repeats original index append if final seal already exists' {
        $script:s.ProofExists=$true;$script:s.ClaimExists=$true;$script:s.JournalPhase='Reconciled'
        $script:s.IndexCount=501;$script:s.SealExists=$true
        {Invoke-OPA265ARCH3qCommit -Mode Recover @script:pin -ReviewSha256 ('b'*64) -CommitClaimSha256 ('a'*64) -ConfirmRecovery -Confirm:$false} | Should -Throw
        $script:indexCommits | Should -Be 0
    }
}
