#requires -Version 5.1
# ARCH2d real batch 10 synthetic CI only: uses ORIGINAL source core module and
# semantic verifier with fake MAPI MailItems; no Outlook process or real PST.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2dBatchCore.ps1')
    $script:run='77777777-8888-4999-aabb-cccccccccccc'
    $script:source=Join-Path $TestDrive 'info@stios.ru.pst'
    [IO.File]::WriteAllBytes($script:source,[byte[]]@(1,2,3,4))
    function New-ARCH2dWitness {
        param([string]$Subject='subject')
        $h={param([string]$Text) Get-OPA265ARCH2bTextSha256 -Text $Text}
        return [pscustomobject]@{
            Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
            ItemClass=43
            InternetMessageIdSha256=(& $h '<id@test.invalid>')
            SubjectSha256=(& $h $Subject)
            SenderSha256=(& $h 'someone@test.invalid')
            ToSha256=(& $h 'recipient@test.invalid')
            CcSha256=(& $h '');BccSha256=(& $h '')
            RecipientCount=0
            OrderedRecipientDigestSha256=(& $h '')
            BodySha256=(& $h 'body')
            BodyUtf16Length=4
            HtmlBodySha256=(& $h 'html')
            HtmlBodyUtf16Length=4
            ReceivedUtcTicks=637792704000000000
            SentUtcTicks=637792704000000000
            UnRead=$false;Importance=1;Sensitivity=0
            CategoriesSha256=(& $h '')
            AttachmentCount=0;Attachments=@()
            MailItemSizeDiagnosticBytes=1400
        }
    }
    function New-ARCH2dManifest {
        param([object]$Layout=(Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA))
        $rows=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le 10;$i++){
            $w=New-ARCH2dWitness -Subject ('Unique subject '+$i)
            $rows.Add([pscustomobject]@{
                Ordinal=$i
                SourceEntryId=('1234567890ABCDEF{0:D4}' -f $i)
                SemanticSignature=(Get-OPA265ARCH2dSemanticSignature -Witness $w)
                SourceSemanticWitness=$w
            })|Out-Null
        }
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d.PreMoveManifest.1'
            RunId=$script:run
            SourcePst=$script:source
            SourceStoreId='POP3'
            SourceFolderId='INBOX'
            ArchivePst=[string]$Layout.ArchivePst
            ArchiveFolder=[string]$Layout.ArchiveFolder
            ArchiveStoreId='ARCHIVE'
            ArchiveFolderId='ARCHIVE-INBOX'
            BatchSize=10
            IntentSha256=('a'*64)
            Items=@($rows.ToArray())
            WriterPermit=$false;ProductionReady=$false
        }
    }
    function New-ARCH2dResults {
        param([int]$Verified=10,[int]$Untouched=0)
        $res=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le 10;$i++){
            $status=if($i -le $Verified){'MovedAndSemanticallyMatched'}elseif($i -le ($Verified+$Untouched)){
                'NotAttemptedOriginalSourcePresent'
            }else{'ManualReviewRequired'}
            $res.Add([pscustomobject]@{
                Ordinal=$i
                Status=$status
                MoveClaimExists=($i -le $Verified)
            })|Out-Null
        }
        return @($res.ToArray())
    }
    function New-ARCH2dFakeNs {
        $ns=[pscustomobject]@{}
        $ns|Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {
            param([string]$eid,[string]$sid)
            return [pscustomobject]@{
                EntryID=$eid
                Parent=[pscustomobject]@{StoreID=$sid;EntryID='INBOX'}
            }
        }
        return $ns
    }
}
Describe 'ARCH2d ten REAL Inbox mail batch: synthetic no-Outlook safety regressions' {
    It 'derives NEW batch10 path, not historical ARCH2c4 pilot' {
        $layout=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        $layout.ArchivePst | Should -BeLike '*OutlookPOP3Archive-ARCH2d-RealBatch10*'
        $layout.ArchivePst | Should -Not -BeLike '*ARCH2c4-RealPilot*'
        $layout.BatchSize | Should -Be 10
    }
    It 'requires canonical lowercase run GUID' {
        {Get-OPA265ARCH2dLayout -RunId 'NOT-GUID' -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'rejects uppercase canonical run GUID variant' {
        {Get-OPA265ARCH2dLayout -RunId $script:run.ToUpperInvariant() -LocalAppData $env:LOCALAPPDATA} | Should -Throw
    }
    It 'verifies its unmodified layout against local root' {
        $layout=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        (Assert-OPA265ARCH2dLayout -Layout $layout) | Should -BeTrue
    }
    It 'refuses forged archive path' {
        $layout=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        $layout.ArchivePst=$script:source
        {Assert-OPA265ARCH2dLayout -Layout $layout} | Should -Throw
    }
    It 'rejects fewer than ten source EntryIDs' {
        {Assert-OPA265ARCH2dEntryIds -EntryIds @('1234567890ABCDEF')} | Should -Throw
    }
    It 'rejects more than ten source EntryIDs' {
        {Assert-OPA265ARCH2dEntryIds -EntryIds @(1..11|ForEach-Object{'1234567890ABCDEF{0:D4}' -f $_})} | Should -Throw
    }
    It 'requires ten distinct hex EntryIDs' {
        $list=@(1..10|ForEach-Object{'1234567890ABCDEF{0:D4}' -f $_})
        (Assert-OPA265ARCH2dEntryIds -EntryIds $list) | Should -BeTrue
    }
    It 'rejects duplicate EntryIDs' {
        $list=@(1..10|ForEach-Object{'1234567890ABCDEF{0:D4}' -f $_})
        $list[9]=$list[0]
        {Assert-OPA265ARCH2dEntryIds -EntryIds $list} | Should -Throw
    }
    It 'rejects malformed EntryID despite ten candidates' {
        $list=@(1..10|ForEach-Object{'1234567890ABCDEF{0:D4}' -f $_})
        $list[0]='NOT-HEX'
        {Assert-OPA265ARCH2dEntryIds -EntryIds $list} | Should -Throw
    }
    It 'derives unique per-item immutable claim names in run directory' {
        $layout=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        (Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal 1) | Should -BeLike '*move-01-claim.json'
        (Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal 10) | Should -BeLike '*move-10-claim.json'
    }
    It 'returns separate return observation path, never overwrites original claim' {
        $layout=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        (Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal 1 -Kind Return) | Should -BeLike '*move-01-return.json'
    }
    It 'rejects ordinal eleven' {
        $layout=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        {Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal 11} | Should -Throw
    }
    It 'derives content signature from full original supported witness, not provider size' {
        $w=New-ARCH2dWitness
        $sign1=Get-OPA265ARCH2dSemanticSignature -Witness $w
        $w.MailItemSizeDiagnosticBytes=1438
        $sign2=Get-OPA265ARCH2dSemanticSignature -Witness $w
        $sign1 | Should -BeExactly $sign2
    }
    It 'rejects missing semantic fields before manifest seal' {
        $w=New-ARCH2dWitness;$w.BodySha256='bad'
        {Get-OPA265ARCH2dSemanticSignature -Witness $w} | Should -Throw
    }
    It 'accepts exactly ten independently signed unique originals' {
        $l=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        (Assert-OPA265ARCH2dManifest -Manifest (New-ARCH2dManifest -Layout $l) -Layout $l -SourcePst $script:source -SourceStoreId 'POP3' -SourceFolderId 'INBOX') | Should -BeTrue
    }
    It 'fails closed on source/store mismatch' {
        $l=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        {Assert-OPA265ARCH2dManifest -Manifest (New-ARCH2dManifest -Layout $l) -Layout $l -SourcePst $script:source -SourceStoreId 'WRONG' -SourceFolderId 'INBOX'} | Should -Throw
    }
    It 'fails closed when archive is same store as source' {
        $l=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        $m=New-ARCH2dManifest -Layout $l;$m.ArchiveStoreId='POP3'
        {Assert-OPA265ARCH2dManifest -Manifest $m -Layout $l -SourcePst $script:source -SourceStoreId 'POP3' -SourceFolderId 'INBOX'} | Should -Throw
    }
    It 'fails closed on missing tenth item' {
        $l=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        $m=New-ARCH2dManifest -Layout $l;$m.Items=@($m.Items|Select-Object -First 9)
        {Assert-OPA265ARCH2dManifest -Manifest $m -Layout $l -SourcePst $script:source -SourceStoreId 'POP3' -SourceFolderId 'INBOX'} | Should -Throw
    }
    It 'fails closed on duplicate semantic selector in original manifest' {
        $l=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        $m=New-ARCH2dManifest -Layout $l
        $m.Items[9].SemanticSignature=$m.Items[0].SemanticSignature
        $m.Items[9].SourceSemanticWitness=$m.Items[0].SourceSemanticWitness
        {Assert-OPA265ARCH2dManifest -Manifest $m -Layout $l -SourcePst $script:source -SourceStoreId 'POP3' -SourceFolderId 'INBOX'} | Should -Throw
    }
    It 'fails closed on shuffled original ordinal numbering' {
        $l=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        $m=New-ARCH2dManifest -Layout $l;$m.Items[0].Ordinal=2
        {Assert-OPA265ARCH2dManifest -Manifest $m -Layout $l -SourcePst $script:source -SourceStoreId 'POP3' -SourceFolderId 'INBOX'} | Should -Throw
    }
    It 'fails closed on malformed source witness for one of ten' {
        $l=Get-OPA265ARCH2dLayout -RunId $script:run -LocalAppData $env:LOCALAPPDATA
        $m=New-ARCH2dManifest -Layout $l;$m.Items[5].SourceSemanticWitness.HtmlBodySha256='bad'
        {Assert-OPA265ARCH2dManifest -Manifest $m -Layout $l -SourcePst $script:source -SourceStoreId 'POP3' -SourceFolderId 'INBOX'} | Should -Throw
    }
    It 'requires one unique explicit Prepare approval phrase' {
        (Assert-OPA265ARCH2dApproval -Mode Prepare -RunId $script:run -Confirmed $true -ApprovalText ('PREPARE ARCH2D '+$script:run)) | Should -BeTrue
    }
    It 'requires one unique explicit MoveBatch approval phrase' {
        (Assert-OPA265ARCH2dApproval -Mode MoveBatch -RunId $script:run -Confirmed $true -ApprovalText ('MOVEBATCH ARCH2D '+$script:run)) | Should -BeTrue
    }
    It 'refuses missing confirmation flag even with correct words' {
        {Assert-OPA265ARCH2dApproval -Mode MoveBatch -RunId $script:run -Confirmed $false -ApprovalText ('MOVEBATCH ARCH2D '+$script:run)} | Should -Throw
    }
    It 'refuses unpinned approval from different RunId' {
        {Assert-OPA265ARCH2dApproval -Mode MoveBatch -RunId $script:run -Confirmed $true -ApprovalText 'MOVEBATCH ARCH2D wrong'} | Should -Throw
    }
    It 'treats original source EntryId present in original Inbox as one' {
        $n=New-ARCH2dFakeNs
        (Get-OPA265ARCH2dSourcePresence -Namespace $n -EntryId '1234567890ABCDEF' -StoreId 'POP3' -FolderId 'INBOX') | Should -Be 1
    }
    It 'treats unexpected provider exception as unknown, never absent' {
        $n=[pscustomobject]@{}
        $n|Add-Member -MemberType ScriptMethod -Name GetItemFromID -Value {
            param([string]$EntryId,[string]$StoreId)
            throw 'provider unexpectedly unavailable'
        }
        (Get-OPA265ARCH2dSourcePresence -Namespace $n -EntryId '1234567890ABCDEF' -StoreId 'POP3' -FolderId 'INBOX') | Should -Be -1
    }
    It 'independently approves exact ten semantic matches after restart' {
        $r=Get-OPA265ARCH2dReconcileDecision -ItemResults (New-ARCH2dResults) -DestinationItemCount 10 -RestartConfirmed $true
        $r.IndependentlyVerifiedAllTen | Should -BeTrue
        $r.Status | Should -BeExactly 'AllTenIndependentPostRestartSemanticMatches'
    }
    It 'does not approve without Outlook restart' {
        (Get-OPA265ARCH2dReconcileDecision -ItemResults (New-ARCH2dResults) -DestinationItemCount 10 -RestartConfirmed $false).IndependentlyVerifiedAllTen | Should -BeFalse
    }
    It 'does not approve when only nine moves verified' {
        (Get-OPA265ARCH2dReconcileDecision -ItemResults (New-ARCH2dResults -Verified 9 -Untouched 1) -DestinationItemCount 9 -RestartConfirmed $true).IndependentlyVerifiedAllTen | Should -BeFalse
    }
    It 'classifies verified partial six and four untouched without resume permission' {
        $r=Get-OPA265ARCH2dReconcileDecision -ItemResults (New-ARCH2dResults -Verified 6 -Untouched 4) -DestinationItemCount 6 -RestartConfirmed $true
        $r.Status | Should -BeExactly 'PartialBatchVerifiedButNoResumePermit'
        $r.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'blocks accidental duplicated archive row (eleven target mails)' {
        (Get-OPA265ARCH2dReconcileDecision -ItemResults (New-ARCH2dResults) -DestinationItemCount 11 -RestartConfirmed $true).IndependentlyVerifiedAllTen | Should -BeFalse
    }
    It 'blocks inconsistent source/destination count after exception' {
        (Get-OPA265ARCH2dReconcileDecision -ItemResults (New-ARCH2dResults -Verified 3 -Untouched 7) -DestinationItemCount 4 -RestartConfirmed $true).Status | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
    }
    It 'rejects nine planned reconciliation rows as incomplete' {
        {Get-OPA265ARCH2dReconcileDecision -ItemResults @((New-ARCH2dResults)|Select-Object -First 9) -DestinationItemCount 9 -RestartConfirmed $true} | Should -Throw
    }
    It 'requires real original ARCH2b semantic witness and original MAPI internet-message extractor' {
        (Get-Command Get-OPAInternetMessageId -CommandType Function -ErrorAction Stop).Name | Should -BeExactly 'Get-OPAInternetMessageId'
        (Get-Command Get-OPA265ARCH2bMailSemanticWitness -CommandType Function -ErrorAction Stop).Name | Should -BeExactly 'Get-OPA265ARCH2bMailSemanticWitness'
    }
    It 'main Archive/Resume/Auto remains blocked by original ARCH2a guard' {
        $app=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $app | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
    }
    It 'dedicated CLI has exactly five bounded stages, no production Auto' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Invoke-ARCH2d.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Plan','Inventory','Prepare','MoveBatch','Reconcile'\)"
        $s | Should -Not -Match "ValidateSet\('Auto'"
    }
    It 'MoveBatch has exactly one textual COM Move inside ten-item for loop' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2dBatchCore.ps1') -Raw -Encoding UTF8
        ([regex]::Matches($s,'\$item\.Move\(\$target\)')).Count | Should -Be 1
        $s | Should -Not -Match '\.(Copy|Delete|Send)\s*\('
        $s | Should -Match 'for\(\$i=0;\$i -lt 10;\$i\+\+\)'
    }
    It 'global attempt claim and individual claim precede actual COM Move' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2dBatchCore.ps1') -Raw -Encoding UTF8
        $global=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path $layout.GlobalClaimPath')
        $perItem=$s.IndexOf('Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2dItemClaimPath')
        $move=$s.IndexOf('$item.Move($target)')
        ($global -ge 0 -and $perItem -gt $global -and $move -gt $perItem) | Should -BeTrue
    }
    It 'Reconcile path cannot call Move/Copy/Delete/AddStoreEx after its read-only marker' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2dBatchCore.ps1') -Raw -Encoding UTF8
        $pos=$s.IndexOf('# Reconcile: read only')
        $pos | Should -BeGreaterThan 0
        $s.Substring($pos) | Should -Not -Match '\.(Move|Copy|Delete|AddStoreEx)\s*\('
    }
    It 'one-shot global batch claim must exist before Reconcile and cannot be recreated on resume' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2dBatchCore.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'ARCH2d global batch was already claimed'
        $s | Should -Match 'Read-OPA265ARCH2c4JsonSealed -Path \$layout.GlobalClaimPath'
    }
}
