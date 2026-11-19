#requires -Version 5.1
BeforeAll {
    $script:root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:root 'Core/Archive/ARCH3pIndependentPostRestartOriginalVerifier.ps1')
    $script:run='9d276dc4-a0e6-4e74-891f-81502fafe7db'
    $script:intent='f0860d55c5939498094832a8b924dbca9b65532cf53f8234f4aeda97ab631a2b'
    $script:journal='a19f113a6454b1d17333c9a53fc22d065876754b9fbab3167087487d0b2b981e'
    $script:entry='00000000E1878292411BC64291BD506DCEFD2A35E4FC3B00'
    $script:full='8782b410253f54cc5374661077cdfc9279bcfba12805f0dab42b461320cb999c'
    $script:part2='C:\Users\bogoderov_e\Documents\Файлы Outlook\info@stios.ru.Archive-2020-02.pst'
    $script:contract='2c40d67d8cbb82688bfec65b7ac6944cc993840bb180181eb495472ee26cec88'
    function New-ARCH3pFakeEvidence {
        $sha=@{'ARCH3o-WriterEntry.json'=('a'*64);'ARCH3o-DestinationReady.json'=('b'*64);
            'ARCH3o-MoveClaimed.json'=('c'*64);'ARCH3o-ProviderInvocation.json'=('d'*64);
            'ARCH3o-MoveReturned.json'=('e'*64)}
        $claim=[pscustomobject]@{
            Schema='2.6.5-ARCH3o.RealOneShotMoveClaim.1';RunId=$script:run
            IntentSha256=$script:intent;JournalSha256=$script:journal
            WriterEntrySha256=$sha['ARCH3o-WriterEntry.json'];DestinationReadySha256=$sha['ARCH3o-DestinationReady.json']
            SourceEntryId=$script:entry;OriginalWitnessSha256=$script:full
            NewArchivePst=$script:part2;DestinationStoreId='NEW-STORE'
            DestinationFolderEntryId='00000000ABCDABCDABCDABCDABCDABCD'
            OutlookProcessId=11168;OutlookProcessStartUtcTicks=[long]639300867186071455
            OperatorApprovedOneRealMove=$true;AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $writer=[pscustomobject]@{
            Schema='2.6.5-ARCH3o.WriterEntry.1';RunId=$script:run
            IntentSha256=$script:intent;JournalSha256=$script:journal;SourceEntryId=$script:entry
            OriginalWitnessSha256=$script:full;NewArchivePst=$script:part2
            AutomaticRetryAllowed=$false
        }
        $ready=[pscustomobject]@{
            Schema='2.6.5-ARCH3o.DestinationReady.1';RunId=$script:run
            WriterEntrySha256=$sha['ARCH3o-WriterEntry.json']
            OriginalWitnessSha256=$script:full;NewArchivePst=$script:part2
            DestinationStoreId=$claim.DestinationStoreId;DestinationFolderEntryId=$claim.DestinationFolderEntryId
        }
        $invoke=[pscustomobject]@{
            Schema='2.6.5-ARCH3o.ProviderInvocation.1';RunId=$script:run
            ClaimSha256=$sha['ARCH3o-MoveClaimed.json']
            SourceEntryId=$script:entry;NewArchivePst=$script:part2
            DestinationFolderEntryId=$claim.DestinationFolderEntryId;AutomaticRetryAllowed=$false
        }
        $receipt=[pscustomobject]@{
            Schema='2.6.5-ARCH3o.MoveReturned.1';RunId=$script:run
            SourceEntryId=$script:entry;NewArchivePst=$script:part2
            OriginalWitnessSha256=$script:full;OriginalContractSha256=$script:contract
            MoveClaimSha256=$sha['ARCH3o-MoveClaimed.json']
            ProviderInvocationSha256=$sha['ARCH3o-ProviderInvocation.json']
            DestinationStoreId=$claim.DestinationStoreId
            DestinationFolderEntryId=$claim.DestinationFolderEntryId
            ArchiveEntryId='00000000FEDCBA9876543210FEDCBA9876543210'
            IndependentPostRestartVerified=$false;DuplicateIndexWritten=$false;OriginalJournalReconciled=$false
        }
        $intentRecord=[pscustomobject]@{
            SourceSealRunId='3773bcd7-5a07-4c31-8ce5-dfb16ddd30bf'
            SourceSealSha256='5f5a86b6c1aba8a3d2ee328a36a5632f8edf1e89fdda8e7fd728688fe881b2a4'
            SourceEntryId=$script:entry;SourceStoreIdSha256='store-hash'
            SourceFolderEntryId='00000000FAFAFAFAFAFAFAFAFAFAFAFA'
            FullOriginalWitnessSha256=$script:full;NewArchivePst=$script:part2
            OriginalContractSha256=$script:contract
            ExistingArchivePart1='C:\Fake\part1.pst'
            SourcePst='C:\Fake\info@stios.ru.pst'
        }
        $sealed=[pscustomobject]@{
            OriginalWitness=[pscustomobject]@{Schema='2.6.5-ARCH2b.MailSemanticWitness.1'}
            SourceEntryId=$script:entry;SourceFolderEntryId=$intentRecord.SourceFolderEntryId
            SourceStoreIdSha256=$intentRecord.SourceStoreIdSha256
        }
        return [pscustomobject]@{
            Sha=$sha
            Writer=$writer;Ready=$ready;Claim=$claim;Invocation=$invoke
            Receipt=$receipt;Intent=$intentRecord;Sealed=$sealed
            Status=[pscustomobject]@{
                EvidenceSha256=$sha;OriginalJournalIntentPreserved=$true;AutomaticRetryAllowed=$false;WriterPermit=$false
                WriterEntryExists=$true;DestinationReadyExists=$true;MoveClaimed=$true
                ProviderInvocationExists=$true;MoveReturnedReceiptExists=$true
            }
        }
    }
    function New-ARCH3pFakeReview {
        param([string]$Dir)
        $e=New-ARCH3pFakeEvidence
        $p1=Join-Path $Dir 'info@stios.ru.Archive-2020.pst'
        $p2=Join-Path $Dir 'info@stios.ru.Archive-2020-02.pst'
        [IO.File]::WriteAllBytes($p1,(New-Object byte[] 271360))
        [IO.File]::WriteAllText($p2,'simulated-new-archive')
        $e.Intent.ExistingArchivePart1=$p1
        $e.Intent.SourcePst=(Join-Path $Dir 'info@stios.ru.pst')
        $e.Claim.NewArchivePst=$p2
        $e.Receipt.NewArchivePst=$p2
        $e.Writer.NewArchivePst=$p2
        $e.Ready.NewArchivePst=$p2
        $e.Invocation.NewArchivePst=$p2
        return [pscustomobject]@{
            Status=$e.Status;OriginalIntent=$e.Intent;Claim=$e.Claim
            Sealed=$e.Sealed;MoveReturned=$e.Receipt
            MoveClaimSha256=$e.Sha['ARCH3o-MoveClaimed.json']
            ProviderInvocationSha256=$e.Sha['ARCH3o-ProviderInvocation.json']
            MoveReceiptSha256=$e.Sha['ARCH3o-MoveReturned.json']
        }
    }
}
Describe 'ARCH3p pinned immutable original ARCH3o provider and journal evidence chain' {
    BeforeEach {
        $script:e=New-ARCH3pFakeEvidence
        Mock Get-OPA265ARCH3oOneShotStatus {return $script:e.Status}
        Mock Get-OPA265ARCH3jLayout {return [pscustomobject]@{Root=$TestDrive;IntentPath='C:\fake\intent.json'}}
        Mock Read-OPA265ARCH3cPinnedJson {
            if($Path -like '*ARCH3o-WriterEntry.json'){return $script:e.Writer}
            if($Path -like '*ARCH3o-DestinationReady.json'){return $script:e.Ready}
            if($Path -like '*ARCH3o-MoveClaimed.json'){return $script:e.Claim}
            if($Path -like '*ARCH3o-ProviderInvocation.json'){return $script:e.Invocation}
            if($Path -like '*ARCH3o-MoveReturned.json'){return $script:e.Receipt}
            return $script:e.Intent
        }
        Mock Get-OPA265ARCH3jSealedSource {return $script:e.Sealed}
        Mock Assert-OPA265ARCH3iFullWitnessPinned {return $script:full}
    }
    It 'accepts original five-stage SHA chain with immutable full ARCH2b witness' {
        $r=Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal
        $r.MoveClaimSha256 | Should -BeExactly ('c'*64)
        $r.ProviderInvocationSha256 | Should -BeExactly ('d'*64)
        $r.MoveReturned.ArchiveEntryId | Should -Match '^0000'
    }
    It 'refuses forged RunId before any protected evidence read' {
        {Get-OPA265ARCH3pClaimChain -RunId ([guid]::NewGuid().ToString('D')) -IntentSha256 $script:intent -JournalSha256 $script:journal} | Should -Throw
        Should -Invoke Get-OPA265ARCH3oOneShotStatus -Exactly -Times 0
    }
    It 'refuses rebaselining original Intent SHA' {
        {Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 ('f'*64) -JournalSha256 $script:journal} | Should -Throw
    }
    It 'refuses modified original Journal SHA' {
        {Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 ('f'*64)} | Should -Throw
    }
    It 'refuses missing ProviderInvocation even when MoveClaimed exists' {
        $script:e.Status.ProviderInvocationExists=$false
        {Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal} | Should -Throw
    }
    It 'refuses modified MoveClaim hash' {
        $script:e.Sha['ARCH3o-MoveClaimed.json']='f'*64
        {Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal} | Should -Throw
    }
    It 'rejects mismatched ProviderInvocation destination folder' {
        $script:e.Invocation.DestinationFolderEntryId='WRONG'
        {Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal} | Should -Throw
    }
    It 'rejects modified original full semantic witness' {
        $script:e.Ready.OriginalWitnessSha256='f'*64
        {Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal} | Should -Throw
    }
    It 'allows missing MoveReturned only with durable claim and ProviderInvocation but no replay' {
        $script:e.Status.MoveReturnedReceiptExists=$false
        $r=Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal
        $r.MoveReturned | Should -BeNullOrEmpty
        $r.MoveReceiptSha256 | Should -BeExactly ''
    }
    It 'rejects changed original receipt provider hash when receipt exists' {
        $script:e.Receipt.ProviderInvocationSha256='f'*64
        {Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal} | Should -Throw
    }
    It 'requires an operator-supplied claim hash when specified to match' {
        {Get-OPA265ARCH3pClaimChain -RunId $script:run -IntentSha256 $script:intent -JournalSha256 $script:journal -ExpectedMoveClaimSha256 ('f'*64)} | Should -Throw
    }
}
Describe 'ARCH3p original ArchiveVerifier fresh REAL Outlook restart safety gates (fake COM only)' {
    BeforeEach {
        $script:chain=New-ARCH3pFakeReview -Dir $TestDrive
        $script:sourceCount=10
        $script:archiveItem=[pscustomobject]@{Class=43;EntryID='00000000FEDCBA9876543210FEDCBA9876543210';Subject='FAKE'}
        $coll=[pscustomobject]@{Count=1}
        $coll | Add-Member -MemberType ScriptMethod -Name Item -Value {param($i)return $script:archiveItem}
        $script:folder=[pscustomobject]@{
            EntryID=$script:chain.Claim.DestinationFolderEntryId;StoreID='NEW-STORE'
            FolderPath='\\ArchiveRoot\2020\Входящие';Items=$coll
        }
        $inbox=[pscustomobject]@{
            EntryID=$script:chain.OriginalIntent.SourceFolderEntryId
            FolderPath='\\info@stios.ru\Входящие'
            Items=[pscustomobject]@{Count=$script:sourceCount}
        }
        $script:archive=[pscustomobject]@{StoreID='NEW-STORE';FilePath=$script:chain.Claim.NewArchivePst}
        # The ORIGINAL ArchiveVerifier works with a COM-like Store that
        # implements GetRootFolder; the synthetic test facade must too.
        $script:archive | Add-Member -MemberType ScriptMethod -Name GetRootFolder -Value {
            return [pscustomobject]@{Name='ArchiveRoot';FolderPath='\\ArchiveRoot'}
        }
        $script:session=[pscustomobject]@{
            Scope=[pscustomobject]@{Approved=$true}
            SourceStore=[pscustomobject]@{StoreID='OLD-POP3'}
            Inbox=$inbox;Namespace=[pscustomobject]@{}
            DefaultStoreId='DEFAULT'
            Accounts=@([pscustomobject]@{DeliveryStoreId='OLD-POP3'})
            OutlookProcessId=67890
            OutlookProcessStartUtcTicks=[long]639300867186071456
        }
        $script:chain.OriginalIntent.SourceStoreIdSha256=Get-OPA265ARCH2bTextSha256 -Text 'OLD-POP3'
        $script:verifierCalls=0
        Mock Get-OPA265ARCH2dLayout {return [pscustomobject]@{ArchivePst='fake'}}
        Mock Open-OPA265ARCH2dSession {return $script:session}
        Mock Close-OPA265ARCH2dSession {}
        Mock Release-OPA265ARCH2c4Com {}
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$true;EntryCount=500}}
        Mock Get-OPA265ARCH3pMountedPart2 {return $script:archive}
        Mock Get-OPAFolderByPath {return $script:folder}
        Mock Get-OPA265ARCH2bMailSemanticWitness {return [pscustomobject]@{Schema='FAKE'}}
        Mock Assert-OPA265ARCH3iFullWitnessPinned {return $script:full}
        Mock Compare-OPA265ARCH2bMailSemanticWitness {return [pscustomobject]@{CriticalContentMatches=$true;IssueCodes=@()}}
        Mock Get-OPAInternetMessageId {return '<fake@example.invalid>'}
        Mock Test-OPAArchiveMoves {
            $script:verifierCalls++
            return [pscustomobject]@{
                Verified=$true;EntryIdsVerified=$true;SemanticWitnessRequired=$true
                AllRequiredOriginalSemanticWitnessesPresent=$true;ExpectedMoved=1
                ExpectedEntryIdsChecked=1;TargetCount=1
                ObservedSourceCount=$script:sourceCount
                MissingEntryIds=@();WarningEntryIds=@()
            }
        }
        Mock Write-OPAOperationJournalEvent {throw 'NEVER reconcile before independent receipt'}
        Mock Add-OPADuplicateEntry {throw 'NEVER write shared index before review'}
    }
    It 'calls ORIGINAL ArchiveVerifier and proves source ID absent + exact ONE target and full semantics' {
        $r=Invoke-OPA265ARCH3pIndependentRestartReview -Chain $script:chain
        $r.Status | Should -BeExactly 'IndependentRealOutlookRestartOriginalArchiveVerifierSourceAbsentArchiveOneFullSemanticMatch'
        $r.OriginalVerifierSemanticMatch | Should -BeTrue
        $r.RealOutlookRestartConfirmed | Should -BeTrue
        $r.DuplicateIndexWritten | Should -BeFalse
        $script:verifierCalls | Should -Be 1
        Should -Invoke Write-OPAOperationJournalEvent -Exactly -Times 0
        Should -Invoke Add-OPADuplicateEntry -Exactly -Times 0
    }
    It 'rejects SAME Outlook PID even with different timestamps' {
        $script:session.OutlookProcessId=11168
        {Invoke-OPA265ARCH3pIndependentRestartReview -Chain $script:chain} | Should -Throw
        $script:verifierCalls | Should -Be 0
    }
    It 'rejects older/equal Outlook process creation time even with different PID' {
        $script:session.OutlookProcessStartUtcTicks=[long]639300867186071455
        {Invoke-OPA265ARCH3pIndependentRestartReview -Chain $script:chain} | Should -Throw
    }
    It 'rejects archive folder with two items BEFORE original verifier' {
        $script:folder.Items.Count=2
        {Invoke-OPA265ARCH3pIndependentRestartReview -Chain $script:chain} | Should -Throw
        $script:verifierCalls | Should -Be 0
    }
    It 'rejects archive item full semantic content mismatch before original verifier' {
        Mock Compare-OPA265ARCH2bMailSemanticWitness {return [pscustomobject]@{CriticalContentMatches=$false;IssueCodes=@('DifferentHtmlBodySha256')}}
        {Invoke-OPA265ARCH3pIndependentRestartReview -Chain $script:chain} | Should -Throw
        $script:verifierCalls | Should -Be 0
    }
    It 'rejects the original ArchiveVerifier returning missing source ID/target mismatch' {
        Mock Test-OPAArchiveMoves {
            return [pscustomobject]@{Verified=$false;EntryIdsVerified=$false;TargetCount=1;
                MissingEntryIds=@('STILL_IN_SOURCE');ExpectedMoved=1;ExpectedEntryIdsChecked=1}
        }
        {Invoke-OPA265ARCH3pIndependentRestartReview -Chain $script:chain} | Should -Throw
    }
    It 'rejects index drift BEFORE original verifier' {
        Mock Get-OPA265ARCH3jIndexSafety {return [pscustomobject]@{Approved=$false;EntryCount=500}}
        {Invoke-OPA265ARCH3pIndependentRestartReview -Chain $script:chain} | Should -Throw
        $script:verifierCalls | Should -Be 0
    }
    It 'reconciles unknown COM return after restart when ProviderInvocation exists but MoveReturned is missing' {
        $script:chain.MoveReturned=$null
        $script:chain.MoveReceiptSha256=''
        $r=Invoke-OPA265ARCH3pIndependentRestartReview -Chain $script:chain
        $r.MoveReceiptWasMissingButProviderInvocationPresent | Should -BeTrue
        $r.OriginalArchiveVerifierUsed | Should -BeTrue
        $r.AutomaticMoveRetryAllowed | Should -BeFalse
    }
}
Describe 'ARCH3p no writer API and original verifier strict result' {
    It 'public operator script exposes ONLY Plan Review Status, not Move or journal/index commit' {
        $cli=Get-Content -LiteralPath (Join-Path $script:root 'Invoke-ARCH3p.ps1') -Raw -Encoding UTF8
        $cli | Should -Match "ValidateSet\('Plan','Review','Status'\)"
        $cli | Should -Not -Match "ValidateSet\('Plan','Review','Move'"
    }
    It 'strict original verifier result fails when observed source count changes' {
        $bad=[pscustomobject]@{
            Verified=$true;EntryIdsVerified=$true;SemanticWitnessRequired=$true
            AllRequiredOriginalSemanticWitnessesPresent=$true
            ExpectedMoved=1;ExpectedEntryIdsChecked=1;TargetCount=1;ObservedSourceCount=9
            MissingEntryIds=@();WarningEntryIds=@()
        }
        {Test-OPA265ARCH3pOriginalVerifierResult -Verified $bad -SourceCountBefore 10 -SourceEntryId $script:entry} | Should -Throw
    }
}
