#requires -Version 5.1
# ARCH3c test fixtures use OS TEMP only; NO existing user PST or Outlook.
BeforeAll {
    $script:projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:projectRoot 'Core/Archive/ARCH3cDurableOperationLedger.ps1')
    $script:source='C:\ARCH3C-NONEXISTENT\info@stios.ru.pst'
    $script:store='ARCH3C-SYNTHETIC-STORE-ONLY'
    function New-ARCH3cFixture {
        param([string]$InjectStopAfter='None')
        $guid=[guid]::NewGuid().ToString('N')
        $tx='ARCH3C-SYNTHETIC-'+$guid
        $root=Join-Path ([IO.Path]::GetTempPath()) ('ARCH3C-SYNTHETIC-'+$guid)
        $candidate=[pscustomobject]@{
            EntryID='00000000E1878292411BC64291BD506DCEFD2A35040A3C00'
            ArchiveDate=[datetime]'2020-02-12T12:30:00'
            SourceFolderPath='\\POP3 Store\Входящие'
            FolderName='Входящие'
        }
        $contract=New-OPA265ARCH3bOperationContract -Candidate $candidate -TransactionId $tx -SourcePst $script:source -SourceStoreId $script:store -ArchiveGrouping Year
        $layout=Get-OPA265ARCH3cLayout -Contract $contract -ScratchRoot $root
        return [pscustomobject]@{Contract=$contract;Root=$root;Layout=$layout;Injected=$InjectStopAfter}
    }
    $script:written=@()
}
AfterAll {
    foreach($f in @($script:written)){
        if($null -ne $f -and $f.Root -and [IO.Directory]::Exists([string]$f.Root)){
            Remove-Item -LiteralPath ([string]$f.Root) -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}
Describe 'ARCH3c immutable synthetic ledger and ORIGINAL operation journal integration' {
    BeforeEach {
        $f=New-ARCH3cFixture
        $script:written+=,$f
    }
    It 'uses canonical ARCH3b identity tied to source Year/PST and StoreID' {
        $f.Contract.OperationId | Should -Match '^ARCH3b-[a-f0-9]{64}$'
        $f.Contract.PlannedArchivePst | Should -BeLike '*info@stios.ru.Archive-2020.pst'
        $f.Contract.WriterPermit | Should -BeFalse
    }
    It 'requires an exact synthetic transaction marker before any disk writes' {
        $x=$f.Contract.PSObject.Copy()
        $x.TransactionId='NORMAL-PRODUCTION-TRANSACTION'
        {Get-OPA265ARCH3cLayout -Contract $x -ScratchRoot $f.Root} | Should -Throw
        (Test-Path -LiteralPath $f.Root) | Should -BeFalse
    }
    It 'refuses a path outside temporary storage' {
        {Get-OPA265ARCH3cLayout -Contract $f.Contract -ScratchRoot 'C:\Users\NOT_SYNTHETIC'} | Should -Throw
    }
    It 'requires explicit synthetic write approval' {
        {Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$false} | Should -Throw
        (Test-Path -LiteralPath $f.Root) | Should -BeFalse
    }
    It 'writes seven immutable stage files and SHA anchored final seal only in synthetic TEMP' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        $w.StageCount | Should -Be 7
        $w.FinalSealSha256 | Should -Match '^[a-f0-9]{64}$'
        $w.Status | Should -BeExactly 'SevenDurableSyntheticStagesAndOriginalOperationJournalSealedNoCom'
    }
    It 'integrates ORIGINAL append-only OperationJournal Intent and Reconciled phases' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        $j=Read-OPAOperationJournal -Path $f.Layout.OperationJournal
        $j.Events.Count | Should -Be 2
        $j.Events[0].Phase | Should -BeExactly 'Intent'
        $j.Events[1].Phase | Should -BeExactly 'Reconciled'
        $j.Events[0].OperationId | Should -BeExactly $f.Contract.OperationId
        $j.Events[1].TransactionId | Should -BeExactly $f.Contract.TransactionId
    }
    It 'reuses ORIGINAL Resolve-OPAOperationRecovery on real durable synthetic journal' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        $j=Read-OPAOperationJournal -Path $f.Layout.OperationJournal
        $recovery=Resolve-OPAOperationRecovery -Journal $j
        $recovery.Resolved.Count | Should -Be 1
        $recovery.Resolved[0].Status | Should -BeExactly 'Reconciled'
    }
    It 'original journal is cryptographically linked from externally pinned final SHA256' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        $review=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root -ExternallyPinnedFinalSealSha256 $w.FinalSealSha256
        $review.Status | Should -BeExactly 'SyntheticDurableStageAndOriginalJournalChainFullyPinnedNoOutlook'
        $review.StageCount | Should -Be 7
        $review.OriginalOperationJournalEventCount | Should -Be 2
        $review.Issues.Count | Should -Be 0
    }
    It 'full synthetic seal WITHOUT external SHA256 pin cannot be certified' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root
        $r.FinalSealExternallyPinned | Should -BeFalse
        $r.Status | Should -Not -BeExactly 'SyntheticDurableStageAndOriginalJournalChainFullyPinnedNoOutlook'
    }
    It 'wrong externally supplied SHA256 rejects intact stage chain' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root -ExternallyPinnedFinalSealSha256 ('0'*64)
        $r.FinalSealExternallyPinned | Should -BeFalse
        $r.Issues | Should -Contain 'InvalidOrUnpinnedFinalSeal'
    }
    It 'CreateNew + Flush(true) never overwrites previous stage on restart' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        $p=Get-OPA265ARCH3cStagePath -Layout $f.Layout -Stage MoveClaimed
        $before=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
        {Write-OPA265ARCH3cJsonOnce -Path $p -Record ([pscustomobject]@{Changed=$true})} | Should -Throw
        (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash | Should -BeExactly $before
    }
    It 'full synthetic operation cannot be invoked twice with same directory' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        {Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true} | Should -Throw
    }
    It 'indeterminate synthetic crash after claim remains permanently unrepeatable' {
        {Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true -InjectStopAfter MoveClaimed} | Should -Throw
        (Test-Path -LiteralPath (Get-OPA265ARCH3cStagePath -Layout $f.Layout -Stage MoveClaimed)) | Should -BeTrue
        (Test-Path -LiteralPath (Get-OPA265ARCH3cStagePath -Layout $f.Layout -Stage MoveReturned)) | Should -BeFalse
        {Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true} | Should -Throw
    }
    It 'crash at PrepareIntent is partial, not a clean certificate' {
        {Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true -InjectStopAfter PrepareIntent} | Should -Throw
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root
        $r.StageCount | Should -Be 1
        $r.FinalSealPresent | Should -BeFalse
        $r.ProductionReady | Should -BeFalse
    }
    It 'crash after MoveReturned is NOT independent content verification' {
        {Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true -InjectStopAfter MoveReturned} | Should -Throw
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root
        $r.StageCount | Should -Be 5
        $r.OriginalOperationJournalEventCount | Should -Be 1
        $r.IndependentLivePstVerified | Should -BeFalse
    }
    It 'crash after synthetic reconcile stage does not permit production writer' {
        {Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true -InjectStopAfter IndependentContentVerified} | Should -Throw
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root
        $r.StageCount | Should -Be 6
        $r.FinalSealPresent | Should -BeFalse
        $r.WriterPermit | Should -BeFalse
    }
    It 'real Outlook PST file is never created even though planned destination is resolved' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        (Test-Path -LiteralPath $f.Contract.PlannedArchivePst) | Should -BeFalse
        $w.PstOpened | Should -BeFalse
    }
    It 'tampered middle-stage SHA is rejected by prior/next chain and pinned final seal' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        $p=Get-OPA265ARCH3cStagePath -Layout $f.Layout -Stage MoveClaimed
        $json=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json
        $json.SourceWitnessSha256='b'*64
        [IO.File]::WriteAllText($p,($json|ConvertTo-Json -Depth 12 -Compress))
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root -ExternallyPinnedFinalSealSha256 $w.FinalSealSha256
        $r.FinalSealExternallyPinned | Should -BeFalse
        $r.Issues.Count | Should -BeGreaterThan 0
    }
    It 'truncated original OperationJournal cannot be treated as independent verification' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        [IO.File]::AppendAllText($f.Layout.OperationJournal,'{"torn":')
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root -ExternallyPinnedFinalSealSha256 $w.FinalSealSha256
        $r.Issues | Should -Contain 'OriginalOperationJournalInvalidOrTorn'
    }
    It 'tampered original OperationJournal SHA mismatches external final seal' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        [IO.File]::AppendAllText($f.Layout.OperationJournal,[Environment]::NewLine)
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root -ExternallyPinnedFinalSealSha256 $w.FinalSealSha256
        $r.FinalSealExternallyPinned | Should -BeFalse
    }
    It 'deleted final seal is never restored automatically and never a PASS' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        [IO.File]::Delete($f.Layout.FinalSeal)
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root -ExternallyPinnedFinalSealSha256 $w.FinalSealSha256
        $r.Issues | Should -Contain 'FinalSealMissing'
        $r.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'forged full operation identity fails closed before writing synthetic files' {
        $x=$f.Contract.PSObject.Copy()
        $x.OperationId='ARCH3b-'+('f'*64)
        {Get-OPA265ARCH3cLayout -Contract $x -ScratchRoot $f.Root} | Should -Throw
    }
    It 'no real legacy duplicate index or transaction state touched' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        (Get-ChildItem -LiteralPath $f.Root -File).Count | Should -Be 9
        $w.OutlookContacted | Should -BeFalse
        $w.WriterPermit | Should -BeFalse
        $w.ProductionReady | Should -BeFalse
    }
    It 'synthetic missing stage prefix is fail-closed rather than certified' {
        $w=Invoke-OPA265ARCH3cSyntheticWrite -Contract $f.Contract -ScratchRoot $f.Root -ConfirmSyntheticWrite:$true
        [IO.File]::Delete((Get-OPA265ARCH3cStagePath -Layout $f.Layout -Stage SourceWitnessAnchored))
        $r=Test-OPA265ARCH3cSyntheticEvidence -Contract $f.Contract -ScratchRoot $f.Root -ExternallyPinnedFinalSealSha256 $w.FinalSealSha256
        $r.FinalSealExternallyPinned | Should -BeFalse
        $r.Issues | Should -Contain 'NonPrefixStageSequence'
    }
}
Describe 'ARCH3c source policy and old archiver cannot silently become production' {
    It 'writes real file evidence only to TEMP with explicit synthetic-only prefix' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3cDurableOperationLedger.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'ARCH3C-SYNTHETIC'
        $s | Should -Match 'FileMode]::CreateNew'
        $s | Should -Match '\$fs.Flush\(\$true\)'
    }
    It 'uses original Write-OPAOperationJournalEvent, Read-OPAOperationJournal, Resolve-OPAOperationRecovery' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3cDurableOperationLedger.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Write-OPAOperationJournalEvent -Path'
        $s | Should -Match 'Read-OPAOperationJournal -Path'
        $s | Should -Match 'Resolve-OPAOperationRecovery -Journal'
    }
    It 'original MailMover COM Move and ARCH2a production fence remain unchanged' {
        $m=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/MailMover.ps1') -Raw -Encoding UTF8
        $p=Get-Content -LiteralPath (Join-Path $script:projectRoot 'OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $m | Should -Match '\$moved = \$item\.Move\(\$dest\.Folder\)'
        $p | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed -Mode \$Mode'
    }
    It 'adapter never directly changes Outlook, PST files, old transaction or duplicate index' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3cDurableOperationLedger.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '\.Move\('
        $s | Should -Not -Match 'AddStoreEx|Add-OPADuplicateEntry|Save-OPAArchiveTransaction'
    }
    It 'read-only verification cannot claim real independent mail content matches' {
        $s=Get-Content -LiteralPath (Join-Path $script:projectRoot 'Core/Archive/ARCH3cDurableOperationLedger.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'IndependentLivePstVerified=\$false'
        $s | Should -Match 'LiveMailMoved=\$false'
        $s | Should -Match 'ProductionReady=\$false'
    }
}
