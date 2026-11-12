#requires -Version 5.1
# ARCH2d5: fully synthetic 100-real-message-policy fixture. All sealed JSON
# files are under Pester TestDrive only; no live Outlook/PST in CI.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2d5Batch100Core.ps1')
    $script:run='77777777-8888-4999-aabb-cccccccccccc'
    $script:source='C:\Synthetic\info@stios.ru.pst'
    function New-ARCH2d5Witness {
        param([int]$Ordinal)
        $h={param([string]$s) Get-OPA265ARCH2bTextSha256 -Text $s}
        $subject=('Синтетическое письмо '+$Ordinal)
        $body=('Тело тестового письма Ω '+$Ordinal)
        $html=('<p>Синтетическое письмо '+$Ordinal+'</p>')
        [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
            ItemClass=43
            InternetMessageIdSha256=(& $h ('<message-'+$Ordinal+'@invalid.test>'))
            SubjectSha256=(& $h $subject)
            SenderSha256=(& $h 'from@invalid.test')
            ToSha256=(& $h 'to@invalid.test')
            CcSha256=(& $h '')
            BccSha256=(& $h '')
            RecipientCount=0
            OrderedRecipientDigestSha256=(& $h '')
            BodySha256=(& $h $body)
            BodyUtf16Length=$body.Length
            HtmlBodySha256=(& $h $html)
            HtmlBodyUtf16Length=$html.Length
            ReceivedUtcTicks=[int64](637792704000000000 + $Ordinal*10000000)
            SentUtcTicks=[int64](637792704000000000 + $Ordinal*10000000)
            UnRead=$false;Importance=1;Sensitivity=0
            CategoriesSha256=(& $h '')
            AttachmentCount=0;Attachments=@()
            MailItemSizeDiagnosticBytes=1400
        }
    }
    function New-ARCH2d5Fixture {
        param([ValidateRange(0,100)][int]$Through=100)
        $dir=Join-Path $TestDrive ('OPA-ARCH2d5-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        $layout=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d5.Layout.1'
            RunId=$script:run;Root=$dir;RunDirectory=$dir
            ArchivePst=Join-Path $dir 'synthetic-output-never-created.pst'
            ArchiveFolder='OPA265-ARCH2d5-SYNTH-ONLY'
            IntentPath=Join-Path $dir 'prepare-intent.json'
            ManifestPath=Join-Path $dir 'pre-move-manifest.json'
            GlobalClaimPath=Join-Path $dir 'ARCH2d5-BATCH100-ONCE-CLAIM.json'
            FinalSealPath=Join-Path $dir 'batch-final-seal.json'
            AccountEmail='info@stios.ru';ProfileName='Outlook'
            BatchSize=100;WriterPermit=$false;ProductionReady=$false
        }
        $rows=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le 100;$i++){
            $w=New-ARCH2d5Witness -Ordinal $i
            $rows.Add([pscustomobject][ordered]@{
                Ordinal=$i
                SourceEntryId=('1234567890ABCDEF{0:D4}' -f $i)
                SemanticSignature=Get-OPA265ARCH2dSemanticSignature -Witness $w
                SourceSemanticWitness=$w
            })|Out-Null
        }
        $intent=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d5.PrepareIntent.1'
            RunId=$script:run;SourcePst=$script:source
            SourceStoreId='SOURCE_STORE_0000001'
            SourceFolderId='INBOX_FOLDER_000001'
            DestinationPst=[string]$layout.ArchivePst
            PlannedCount=100
            SourceEntryIds=@($rows.ToArray()|ForEach-Object{[string]$_.SourceEntryId})
            NewTargetOnly=$true;AutomaticPrepareRetryAllowed=$false
        }
        $intentSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.IntentPath -Value $intent
        $manifest=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d5.PreMoveManifest.1'
            RunId=$script:run
            IntentSha256=$intentSha
            SourcePst=$script:source
            SourceStoreId='SOURCE_STORE_0000001'
            SourceFolderId='INBOX_FOLDER_000001'
            ArchivePst=[string]$layout.ArchivePst
            ArchiveFolder=[string]$layout.ArchiveFolder
            ArchiveStoreId='ARCHIVE_STORE_000001'
            ArchiveFolderId='ARCHIVE_FOLDER_00001'
            PrepareOutlookProcessId=4122
            PrepareOutlookProcessStartUtcTicks=[int64]637792704000000000
            BatchSize=100;Items=@($rows.ToArray())
            WriterPermit=$false;ProductionReady=$false
        }
        $manifestSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.ManifestPath -Value $manifest
        $global=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d5.BatchOnceClaim.1'
            RunId=$script:run;ManifestSha256=$manifestSha
            SourcePst=$script:source;PlannedCount=100
            MoveProcessId=4122
            MoveProcessStartUtcTicks=[int64]637792704000000000
            ClaimedBeforeAnyMove=$true
            AutomaticRetryAllowed=$false;ProductionReady=$false
        }
        $globalSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.GlobalClaimPath -Value $global
        $lastReturn='';$lastCheckpoint=''
        $checkpointHashes=New-Object 'System.Collections.Generic.List[string]'
        for($i=1;$i -le $Through;$i++){
            $row=$rows[$i-1]
            $claim=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.IndividualClaim.1'
                RunId=$script:run;Ordinal=$i
                ManifestSha256=$manifestSha
                BatchClaimSha256=$globalSha
                SourceEntryId=[string]$row.SourceEntryId
                SourceStoreId='SOURCE_STORE_0000001'
                ArchiveStoreId='ARCHIVE_STORE_000001'
                ArchiveFolderId='ARCHIVE_FOLDER_00001'
                PreviousReceiptSha256=$lastReturn
                PreviousCheckpointSha256=$lastCheckpoint
                ClaimedBeforeMove=$true
                AutomaticRetryAllowed=$false
            }
            $claimSha=Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5ItemPath -Layout $layout -Ordinal $i) -Value $claim
            $receipt=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.MoveReturn.1'
                RunId=$script:run;Ordinal=$i;ClaimSha256=$claimSha
                PreviousReceiptSha256=$lastReturn
                DestinationEntryId=('FEDCBA0987654321{0:D4}' -f $i)
                ArchiveStoreId='ARCHIVE_STORE_000001'
                ArchiveFolderId='ARCHIVE_FOLDER_00001'
                IndependentRestartReviewRequired=$true
                ProductionReady=$false
            }
            $lastReturn=Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5ItemPath -Layout $layout -Ordinal $i -Kind Return) -Value $receipt
            if($i % 10 -eq 0){
                $cp=[pscustomobject][ordered]@{
                    Schema='2.6.5-ARCH2d5.CheckpointSeal.1'
                    RunId=$script:run;ThroughOrdinal=$i
                    ManifestSha256=$manifestSha
                    BatchClaimSha256=$globalSha
                    LastReceiptSha256=$lastReturn
                    PreviousCheckpointSha256=$lastCheckpoint
                    SealedAfterReceipt=$true
                }
                $lastCheckpoint=Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5CheckpointPath -Layout $layout -ThroughOrdinal $i) -Value $cp
                $checkpointHashes.Add($lastCheckpoint)|Out-Null
            }
        }
        $finalSha=''
        if($Through -eq 100){
            $final=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d5.BatchFinalSeal.1'
                RunId=$script:run
                ManifestSha256=$manifestSha
                BatchClaimSha256=$globalSha
                CompletedCount=100
                LastReceiptSha256=$lastReturn
                LastCheckpointSha256=$lastCheckpoint
                CheckpointSha256=@($checkpointHashes.ToArray())
                IndependentRestartReviewRequired=$true
                ProductionReady=$false
            }
            $finalSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.FinalSealPath -Value $final
        }
        return [pscustomobject][ordered]@{
            Layout=$layout
            Manifest=$manifest
            ManifestSha256=$manifestSha
            BatchClaimSha256=$globalSha
            FinalSealSha256=$finalSha
            Rows=@($rows.ToArray())
        }
    }
    function Test-ARCH2d5Chain {
        param([object]$Fixture,[string]$FinalSha='')
        $base=Read-OPA265ARCH2d5BaseEvidence -Layout $Fixture.Layout -SourcePst $script:source -ManifestSha256 $Fixture.ManifestSha256 -BatchClaimSha256 $Fixture.BatchClaimSha256
        Read-OPA265ARCH2d5FullChain -Layout $Fixture.Layout -Base $base -FinalSealSha256 $FinalSha
    }
    function New-ARCH2d5CopyFixture {
        param([object]$Fixture)
        $new=Join-Path $TestDrive ('OPA-ARCH2d5-COPY-'+[guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $Fixture.Layout.RunDirectory -Destination $new -Recurse -Force
        $l=$Fixture.Layout.PSObject.Copy()
        foreach($key in @('Root','RunDirectory')){$l.$key=$new}
        foreach($key in @('IntentPath','ManifestPath','GlobalClaimPath','FinalSealPath')){
            $l.$key=Join-Path $new ([IO.Path]::GetFileName([string]$Fixture.Layout.$key))
        }
        # Original archived path is bound by external manifest; changing it
        # invalidates provenance, so keep ArchivePst/ArchiveFolder unchanged.
        return [pscustomobject]@{
            Layout=$l;ManifestSha256=$Fixture.ManifestSha256
            BatchClaimSha256=$Fixture.BatchClaimSha256
            FinalSealSha256=$Fixture.FinalSealSha256
            Manifest=$Fixture.Manifest
        }
    }
    $script:full=New-ARCH2d5Fixture
}
Describe 'ARCH2d5 real batch100 bounded identity, one-shot safety and cryptographic chain' {
    It 'creates an isolated new root different from old ARCH2c4 and ARCH2d' {
        $l=Get-OPA265ARCH2d5Layout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        $l.Root | Should -BeLike '*ARCH2d5-RealBatch100'
        $l.Root | Should -Not -BeLike '*ARCH2d-RealBatch10'
        $l.BatchSize | Should -Be 100
    }
    It 'rejects noncanonical RunId' {
        {Get-OPA265ARCH2d5Layout -RunId 'not-a-guid' -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'accepts only exactly hundred unique source EntryIDs' {
        $ids=@(1..100|ForEach-Object{'1234567890ABCDEF{0:D4}' -f $_})
        (Assert-OPA265ARCH2d5EntryIds -EntryIds $ids) | Should -BeTrue
        {Assert-OPA265ARCH2d5EntryIds -EntryIds $ids[0..98]} | Should -Throw
        {Assert-OPA265ARCH2d5EntryIds -EntryIds ($ids+@('1234567890ABCDEF0101'))} | Should -Throw
    }
    It 'rejects a duplicate original even if other 99 are distinct' {
        $ids=@(1..100|ForEach-Object{'1234567890ABCDEF{0:D4}' -f $_})
        $ids[99]=$ids[98]
        {Assert-OPA265ARCH2d5EntryIds -EntryIds $ids} | Should -Throw
    }
    It 'enforces exact operator approval phrase and flag for Prepare and MoveBatch' {
        (Assert-OPA265ARCH2d5Approval -Action Prepare -RunId $script:run -Confirmed $true -ApprovalText ('PREPARE ARCH2D5 '+$script:run)) | Should -BeTrue
        (Assert-OPA265ARCH2d5Approval -Action MoveBatch -RunId $script:run -Confirmed $true -ApprovalText ('MOVEBATCH ARCH2D5 '+$script:run)) | Should -BeTrue
        {Assert-OPA265ARCH2d5Approval -Action MoveBatch -RunId $script:run -Confirmed $false -ApprovalText ('MOVEBATCH ARCH2D5 '+$script:run)} | Should -Throw
    }
    It 'checkpoints must be multiples of ten between 10 and 100' {
        $l=$script:full.Layout
        (Get-OPA265ARCH2d5CheckpointPath -Layout $l -ThroughOrdinal 100) | Should -BeLike '*checkpoint-100-seal.json'
        {Get-OPA265ARCH2d5CheckpointPath -Layout $l -ThroughOrdinal 55} | Should -Throw
        {Get-OPA265ARCH2d5CheckpointPath -Layout $l -ThroughOrdinal 0} | Should -Throw
    }
    It 'per-item 100 claim and return paths are separate and unique' {
        $l=$script:full.Layout
        (Get-OPA265ARCH2d5ItemPath -Layout $l -Ordinal 1) | Should -BeLike '*move-001-claim.json'
        (Get-OPA265ARCH2d5ItemPath -Layout $l -Ordinal 100 -Kind Return) | Should -BeLike '*move-100-return.json'
        {Get-OPA265ARCH2d5ItemPath -Layout $l -Ordinal 101} | Should -Throw
    }
    It 'sealed manifest must contain exactly 100 full original semantic witnesses' {
        $f=$script:full
        (Assert-OPA265ARCH2d5Manifest -Manifest $f.Manifest -Layout $f.Layout -SourcePst $script:source -SourceStoreId 'SOURCE_STORE_0000001' -SourceFolderId 'INBOX_FOLDER_000001') | Should -BeTrue
    }
    It 'rejects an altered real source path before cryptographic audit' {
        $f=$script:full
        {Read-OPA265ARCH2d5BaseEvidence -Layout $f.Layout -SourcePst 'C:\WRONG\info@stios.ru.pst' -ManifestSha256 $f.ManifestSha256 -BatchClaimSha256 $f.BatchClaimSha256} | Should -Throw
    }
    It 'operator pinned manifest and global SHA must match exactly' {
        $f=$script:full
        {Read-OPA265ARCH2d5BaseEvidence -Layout $f.Layout -SourcePst $script:source -ManifestSha256 ('0'*64) -BatchClaimSha256 $f.BatchClaimSha256} | Should -Throw
        {Read-OPA265ARCH2d5BaseEvidence -Layout $f.Layout -SourcePst $script:source -ManifestSha256 $f.ManifestSha256 -BatchClaimSha256 ('0'*64)} | Should -Throw
    }
    It 'recomputes original intent SHA from anchored manifest and rejects tampering' {
        $f=New-ARCH2d5Fixture -Through 0
        [IO.File]::WriteAllText($f.Layout.IntentPath,'{"Schema":"tampered"}')
        {Read-OPA265ARCH2d5BaseEvidence -Layout $f.Layout -SourcePst $script:source -ManifestSha256 $f.ManifestSha256 -BatchClaimSha256 $f.BatchClaimSha256} | Should -Throw
    }
    It 'validates complete 100 receipts in an externally pinned final seal' {
        $f=$script:full
        $c=Test-ARCH2d5Chain -Fixture $f -FinalSha $f.FinalSealSha256
        $c.AllHundredChainVerified | Should -BeTrue
        $c.LinkedItems | Should -Be 100
        $c.Claimed | Should -Be 100
        $c.Returned | Should -Be 100
        $c.CheckpointCount | Should -Be 10
        $c.Problems.Count | Should -Be 0
    }
    It 'every one of 100 original claims/receipts is linked by prior receipt SHA and checkpoint' {
        $c=Test-ARCH2d5Chain -Fixture $script:full -FinalSha $script:full.FinalSealSha256
        @($c.Items|Where-Object{$_.EvidenceStatus -cne 'ClaimReturnChainLinked'}).Count | Should -Be 0
        $c.Items[99].ClaimStatus | Should -BeExactly 'ValidChainLink'
        $c.Items[99].ReturnStatus | Should -BeExactly 'ValidChainLink'
    }
    It 'final seal without externally received SHA is not a clean certificate' {
        $c=Test-ARCH2d5Chain -Fixture $script:full
        $c.FinalSealValid | Should -BeTrue
        $c.FinalSealExternallyPinned | Should -BeFalse
        $c.AllHundredChainVerified | Should -BeFalse
    }
    It 'wrong externally supplied final seal hash makes clean PASS impossible' {
        $c=Test-ARCH2d5Chain -Fixture $script:full -FinalSha ('0'*64)
        $c.AllHundredChainVerified | Should -BeFalse
        $c.Problems | Should -Contain 'InvalidFinalSealOrHash'
    }
    It 'a torn final seal is rejected despite 100 intact receipts' {
        $f=New-ARCH2d5CopyFixture -Fixture $script:full
        [IO.File]::WriteAllBytes($f.Layout.FinalSealPath,[byte[]]@(123,34,100))
        $c=Test-ARCH2d5Chain -Fixture $f -FinalSha $f.FinalSealSha256
        $c.AllHundredChainVerified | Should -BeFalse
    }
    It 'changing just the fifth return breaks following SHA-linked claims and external final seal' {
        $f=New-ARCH2d5CopyFixture -Fixture $script:full
        $p=Get-OPA265ARCH2d5ItemPath -Layout $f.Layout -Ordinal 5 -Kind Return
        $v=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json
        $v.DestinationEntryId='1234567890ABCDEF9999'
        [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 10))
        $c=Test-ARCH2d5Chain -Fixture $f -FinalSha $f.FinalSealSha256
        $c.AllHundredChainVerified | Should -BeFalse
        $c.Problems.Count | Should -BeGreaterThan 0
    }
    It 'changing original claim ordinal is detected as incorrect on the exact item' {
        $f=New-ARCH2d5CopyFixture -Fixture $script:full
        $p=Get-OPA265ARCH2d5ItemPath -Layout $f.Layout -Ordinal 8
        $v=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json
        $v.Ordinal=3
        [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 10))
        $c=Test-ARCH2d5Chain -Fixture $f -FinalSha $f.FinalSealSha256
        $c.Items[7].ClaimStatus | Should -BeExactly 'Invalid'
        $c.AllHundredChainVerified | Should -BeFalse
    }
    It 'duplicate destination returned EntryID is rejected even if receipt JSON is valid' {
        $f=New-ARCH2d5CopyFixture -Fixture $script:full
        $p=Get-OPA265ARCH2d5ItemPath -Layout $f.Layout -Ordinal 7 -Kind Return
        $v=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json
        $v.DestinationEntryId='FEDCBA09876543210006'
        [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 10))
        $c=Test-ARCH2d5Chain -Fixture $f -FinalSha $f.FinalSealSha256
        $c.Items[6].ReturnStatus | Should -BeExactly 'Invalid'
        $c.AllHundredChainVerified | Should -BeFalse
    }
    It 'a missing middle receipt is not recreated and no clean certification can occur' {
        $f=New-ARCH2d5CopyFixture -Fixture $script:full
        [IO.File]::Delete((Get-OPA265ARCH2d5ItemPath -Layout $f.Layout -Ordinal 50 -Kind Return))
        $c=Test-ARCH2d5Chain -Fixture $f -FinalSha $f.FinalSealSha256
        $c.Returned | Should -Be 99
        $c.AllHundredChainVerified | Should -BeFalse
        $c.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'a missing tenth checkpoint prevents a fully anchored receipt chain' {
        $f=New-ARCH2d5CopyFixture -Fixture $script:full
        [IO.File]::Delete((Get-OPA265ARCH2d5CheckpointPath -Layout $f.Layout -ThroughOrdinal 100))
        $c=Test-ARCH2d5Chain -Fixture $f -FinalSha $f.FinalSealSha256
        $c.CheckpointCount | Should -Be 9
        $c.AllHundredChainVerified | Should -BeFalse
    }
    It 'truncated SHA string cannot satisfy operator anchored final verification' {
        $f=$script:full
        {Test-ARCH2d5Chain -Fixture $f -FinalSha 'abc'} | Should -Throw
    }
    It 'simulates five moved and ninety-five untouched as partial, no clean seal' {
        $f=New-ARCH2d5Fixture -Through 5
        $c=Test-ARCH2d5Chain -Fixture $f
        $c.Claimed | Should -Be 5
        $c.Returned | Should -Be 5
        $c.LinkedItems | Should -Be 5
        $c.AllHundredChainVerified | Should -BeFalse
        $c.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'simulates fifty moved and fifty untouched with only five checkpoint seals' {
        $f=New-ARCH2d5Fixture -Through 50
        $c=Test-ARCH2d5Chain -Fixture $f
        $c.LinkedItems | Should -Be 50
        $c.CheckpointCount | Should -Be 5
        $c.AllHundredChainVerified | Should -BeFalse
    }
    It 'simulates 99 returned with no final seal and no automatic resume' {
        $f=New-ARCH2d5Fixture -Through 99
        $c=Test-ARCH2d5Chain -Fixture $f
        $c.LinkedItems | Should -Be 99
        $c.FinalSealPresent | Should -BeFalse
        $c.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'force-flushed immutable global claim cannot be overwritten on restart' {
        $f=$script:full
        $p=$f.Layout.GlobalClaimPath
        $before=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p))
        {Write-OPA265ARCH2c4JsonOnce -Path $p -Value ([pscustomobject]@{Schema='different'})} | Should -Throw
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) | Should -BeExactly $before
    }
    It 'a sealed receipt cannot be overwritten with revised copy' {
        $p=Get-OPA265ARCH2d5ItemPath -Layout $script:full.Layout -Ordinal 100 -Kind Return
        $before=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p))
        {Write-OPA265ARCH2c4JsonOnce -Path $p -Value ([pscustomobject]@{Schema='replayed'})} | Should -Throw
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) | Should -BeExactly $before
    }
    It 'a real operator Plan is no COM/no source PST needed' {
        $r=Invoke-OPA265ARCH2d5Pilot -Mode Plan -RunId $script:run -SourcePst $script:source
        $r.Status | Should -BeExactly 'OneHundredRealPop3PilotPlanNoOutlookNoDiskWrites'
        $r.BatchSize | Should -Be 100
    }
    It 'Prepare -WhatIf has no COM, no PST, no journal writes even without approval' {
        $r=Invoke-OPA265ARCH2d5Pilot -Mode Prepare -RunId $script:run -SourcePst $script:source -WhatIf
        $r.Status | Should -BeExactly 'WhatIfNoOutlookNoPstNoJournalWrites'
    }
    It 'MoveBatch -WhatIf has no COM, no PST, no journal writes even without approval' {
        $r=Invoke-OPA265ARCH2d5Pilot -Mode MoveBatch -RunId $script:run -SourcePst $script:source -WhatIf
        $r.Status | Should -BeExactly 'WhatIfNoOutlookNoPstNoJournalWrites'
    }
    It 'real batch100 core contains exactly one one-shot Outlook COM Move' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2d5Batch100Core.ps1') -Raw -Encoding UTF8
        ([regex]::Matches($s,'\$moved=\$mail\.Move\(\$target\)')).Count | Should -Be 1
        $s | Should -Not -Match '\.(Copy|Delete|Save|Send)\s*\('
        $s | Should -Match 'for\(\$i=0;\$i -lt 100;\$i\+\+\)'
    }
    It 'global immutable once-claim strictly precedes every individual claim and COM Move' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2d5Batch100Core.ps1') -Raw -Encoding UTF8
        $a=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path $layout.GlobalClaimPath')
        $b=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5ItemPath')
        $c=$s.IndexOf('$moved=$mail.Move($target)')
        ($a -ge 0 -and $b -gt $a -and $c -gt $b) | Should -BeTrue
    }
    It 'all ten checkpoint seals are written only after return receipts' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2d5Batch100Core.ps1') -Raw -Encoding UTF8
        $r=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5ItemPath -Layout $layout -Ordinal $ordinal -Kind Return)')
        $cp=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2d5CheckpointPath')
        $final=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path $layout.FinalSealPath')
        ($r -ge 0 -and $cp -gt $r -and $final -gt $cp) | Should -BeTrue
    }
    It 'main archival Archive, Resume, Auto still fail-closed by original ARCH2a' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
    }
    It 'old ten-item code is imported unchanged rather than rewritten' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2d5Batch100Policy.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'ARCH2dBatchCore.ps1'
        $s | Should -Match 'Read-OPA265ARCH2d5FullChain'
    }
    It 'new dedicated operator entrypoint provides no Auto or Resume' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Invoke-ARCH2d5.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Plan','Inventory','Prepare','MoveBatch','Evidence','Reconcile'\)"
        $s | Should -Not -Match "ValidateSet\('Auto'"
    }
}
