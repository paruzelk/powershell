#requires -Version 5.1
# ARCH2d4: real immutable writer + bounded exact historical receipt schema.
# All fixtures exclusively in Pester TestDrive. No Outlook or PST contact.
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Diagnostics/ARCH2d4LiveAudit.ps1')
    $script:run='77777777-8888-4999-aabb-cccccccccccc'
    $script:source='C:\Synthetic\info@stios.ru.pst'
    function New-ARCH2d4Witness {
        param([int]$Index)
        $h={param([string]$x) Get-OPA265ARCH2bTextSha256 -Text $x}
        return [pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2b.MailSemanticWitness.1'
            ItemClass=43
            InternetMessageIdSha256=(& $h ('<original-'+$Index+'@invalid.test>'))
            SubjectSha256=(& $h ('Тема Ω '+$Index))
            SenderSha256=(& $h 'sender@invalid.test')
            ToSha256=(& $h 'to@invalid.test')
            CcSha256=(& $h '')
            BccSha256=(& $h '')
            RecipientCount=0
            OrderedRecipientDigestSha256=(& $h '')
            BodySha256=(& $h ('Body '+$Index))
            BodyUtf16Length=[int](('Body '+$Index).Length)
            HtmlBodySha256=(& $h ('<p>Body '+$Index+'</p>'))
            HtmlBodyUtf16Length=[int](('<p>Body '+$Index+'</p>').Length)
            ReceivedUtcTicks=[int64](637792704000000000+$Index*10000000)
            SentUtcTicks=[int64](637792704000000000+$Index*10000000)
            UnRead=$false;Importance=1;Sensitivity=0
            CategoriesSha256=(& $h '')
            AttachmentCount=0;Attachments=@()
            MailItemSizeDiagnosticBytes=1400
        }
    }
    function New-ARCH2d4Fixture {
        param(
            [int]$Claims=10,
            [int]$Receipts=10,
            [switch]$MissingFifthClaim,
            [switch]$DuplicateFifthDestination
        )
        $dir=Join-Path $TestDrive ('OPA-ARCH2d4-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        $layout=[pscustomobject][ordered]@{
            RunId=$script:run
            Root=$dir
            RunDirectory=$dir
            ArchivePst=Join-Path $dir 'synthetic-target.pst'
            ArchiveFolder='ARCH_FOLDER'
            IntentPath=Join-Path $dir 'prepare-intent.json'
            ManifestPath=Join-Path $dir 'pre-move-manifest.json'
            GlobalClaimPath=Join-Path $dir 'ARCH2d-BATCH-ONCE-CLAIM.json'
            BatchSize=10
        }
        $rows=New-Object 'System.Collections.Generic.List[object]'
        for($i=1;$i -le 10;$i++){
            $w=New-ARCH2d4Witness -Index $i
            $rows.Add([pscustomobject][ordered]@{
                Ordinal=$i
                SourceEntryId=('1234567890ABCDEF{0:D4}' -f $i)
                SemanticSignature=Get-OPA265ARCH2dSemanticSignature -Witness $w
                SourceSemanticWitness=$w
            })|Out-Null
        }
        $entries=@($rows.ToArray()|ForEach-Object{$_.SourceEntryId})
        $intent=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d.PrepareIntent.1'
            RunId=$script:run
            SourcePst=$script:source
            SourceStoreId='POP3_SOURCE_STORE_LONG'
            SourceFolderId='INBOX_FOLDER_LONG'
            DestinationPst=[string]$layout.ArchivePst
            PlannedCount=10
            SourceEntryIds=$entries
            NewTargetOnly=$true
            AutomaticPrepareRetryAllowed=$false
        }
        $intentSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.IntentPath -Value $intent
        $manifest=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d.PreMoveManifest.1'
            RunId=$script:run
            IntentSha256=$intentSha
            SourcePst=$script:source
            SourceStoreId='POP3_SOURCE_STORE_LONG'
            SourceFolderId='INBOX_FOLDER_LONG'
            ArchivePst=[string]$layout.ArchivePst
            ArchiveFolder=[string]$layout.ArchiveFolder
            ArchiveStoreId='ARCHIVE_STORE_LONG'
            ArchiveFolderId='ARCHIVE_FOLDER_LONG'
            PrepareOutlookProcessId=1400
            PrepareOutlookProcessStartUtcTicks=[int64]637792704000000000
            BatchSize=10
            Items=@($rows.ToArray())
            WriterPermit=$false;ProductionReady=$false
        }
        $manifestSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.ManifestPath -Value $manifest
        $claim=[pscustomobject][ordered]@{
            Schema='2.6.5-ARCH2d.BatchOnceClaim.1'
            RunId=$script:run
            ManifestSha256=$manifestSha
            OriginalSourcePst=$script:source
            PlannedCount=10
            MoveProcessId=1450
            MoveProcessStartUtcTicks=[int64]637792714000000000
            OneBatchAttemptClaimedBeforeFirstComMove=$true
            AutomaticResumeOrRetryAllowed=$false
            ProductionReady=$false
        }
        $batchSha=Write-OPA265ARCH2c4JsonOnce -Path $layout.GlobalClaimPath -Value $claim
        $hashes=New-Object 'System.Collections.Generic.List[string]'
        for($i=1;$i -le $Claims;$i++){
            if($i -eq 5 -and $MissingFifthClaim){continue}
            $row=$rows[$i-1]
            $ic=[pscustomobject][ordered]@{
                Schema='2.6.5-ARCH2d.IndividualMoveClaim.1'
                RunId=$script:run;Ordinal=$i
                ManifestSha256=$manifestSha
                BatchClaimSha256=$batchSha
                SourceEntryId=[string]$row.SourceEntryId
                SourceStoreId='POP3_SOURCE_STORE_LONG'
                ArchiveStoreId='ARCHIVE_STORE_LONG'
                ArchiveFolderId='ARCHIVE_FOLDER_LONG'
                ClaimedBeforeComMove=$true
                AutomaticRetryAllowed=$false
            }
            $sha=Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal $i) -Value $ic
            $hashes.Add($sha)|Out-Null
            if($i -le $Receipts){
                $destinationId=if($i -eq 5 -and $DuplicateFifthDestination){
                    'FEDCBA09876543210004'
                }else{'FEDCBA0987654321{0:D4}' -f $i}
                $receipt=[pscustomobject][ordered]@{
                    Schema='2.6.5-ARCH2d.MoveReturnObservation.1'
                    RunId=$script:run;Ordinal=$i
                    ClaimSha256=$sha
                    DestinationEntryId=$destinationId
                    DestinationStoreId='ARCHIVE_STORE_LONG'
                    DestinationFolderId='ARCHIVE_FOLDER_LONG'
                    IndependentPostRestartVerificationRequired=$true
                    ProductionReady=$false
                }
                [void](Write-OPA265ARCH2c4JsonOnce -Path (Get-OPA265ARCH2dItemClaimPath -Layout $layout -Ordinal $i -Kind Return) -Value $receipt)
            }
        }
        return [pscustomobject]@{
            Layout=$layout
            ManifestSha256=$manifestSha
            BatchClaimSha256=$batchSha
            Manifest=$manifest
            Rows=@($rows.ToArray())
            ClaimHashes=@($hashes.ToArray())
        }
    }
    function Get-ARCH2d4Evidence {
        param([object]$Fixture)
        Read-OPA265ARCH2d4Evidence -Layout $Fixture.Layout -SourcePst $script:source -ManifestSha256 $Fixture.ManifestSha256 -BatchClaimSha256 $Fixture.BatchClaimSha256
    }
    function New-ARCH2d4Decision {
        param([int]$Ordinal=1,[string]$Claim='ValidInternalLinkage',[string]$Return='ValidInternalLinkage')
        [pscustomobject]@{
            Ordinal=$Ordinal
            ClaimStatus=$Claim
            ReturnStatus=$Return
            IssueCodes=@()
        }
    }
}
Describe 'ARCH2d4 anchored evidence and independent per-item receipt forensic rules' {
    It 'accepts all ten original claims and ten valid receipts, never promotes self-hash to external pin' {
        $f=New-ARCH2d4Fixture
        $e=Get-ARCH2d4Evidence -Fixture $f
        $e.AllTenClaimAndReturnInternallyConsistent | Should -BeTrue
        $e.Claimed | Should -Be 10
        $e.Receipts | Should -Be 10
        $e.LinkedPairs | Should -Be 10
        $e.PerItemReceiptsExternallyHashPinned | Should -BeFalse
    }
    It 'reports ten item receipt hashes and preserves complete source IDs without mail subjects or bodies' {
        $f=New-ARCH2d4Fixture
        $e=Get-ARCH2d4Evidence -Fixture $f
        $e.Items.Count | Should -Be 10
        $e.Items[0].ReturnCurrentSha256 | Should -Match '^[a-f0-9]{64}$'
        $e.Items[0].ClaimCurrentSha256 | Should -Match '^[a-f0-9]{64}$'
        $e.Items[0].SourceEntryId | Should -BeExactly $f.Rows[0].SourceEntryId
    }
    It 'rejects forged externally operator-pinned original manifest SHA' {
        $f=New-ARCH2d4Fixture
        {Read-OPA265ARCH2d4Evidence -Layout $f.Layout -SourcePst $script:source -ManifestSha256 ('0'*64) -BatchClaimSha256 $f.BatchClaimSha256} | Should -Throw
    }
    It 'rejects forged operator-pinned global batch claim SHA' {
        $f=New-ARCH2d4Fixture
        {Read-OPA265ARCH2d4Evidence -Layout $f.Layout -SourcePst $script:source -ManifestSha256 $f.ManifestSha256 -BatchClaimSha256 ('0'*64)} | Should -Throw
    }
    It 'rejects noncanonical SHA pins rather than recomputing them' {
        $f=New-ARCH2d4Fixture
        {Read-OPA265ARCH2d4Evidence -Layout $f.Layout -SourcePst $script:source -ManifestSha256 'ABC' -BatchClaimSha256 $f.BatchClaimSha256} | Should -Throw
    }
    It 'rejects altered original intent SHA even if current file was edited with valid JSON' {
        $f=New-ARCH2d4Fixture
        [IO.File]::WriteAllText($f.Layout.IntentPath,'{"Schema":"changed"}')
        {Get-ARCH2d4Evidence -Fixture $f} | Should -Throw
    }
    It 'rejects changed original manifest file from a prior real batch' {
        $f=New-ARCH2d4Fixture
        [IO.File]::WriteAllText($f.Layout.ManifestPath,'{"Schema":"changed"}')
        {Get-ARCH2d4Evidence -Fixture $f} | Should -Throw
    }
    It 'rejects torn original global claim instead of inferring no attempt' {
        $f=New-ARCH2d4Fixture
        [IO.File]::WriteAllBytes($f.Layout.GlobalClaimPath,[byte[]]@(123,34,97))
        {Get-ARCH2d4Evidence -Fixture $f} | Should -Throw
    }
    It 'rejects missing original anchored manifest' {
        $f=New-ARCH2d4Fixture
        [IO.File]::Delete($f.Layout.ManifestPath)
        {Get-ARCH2d4Evidence -Fixture $f} | Should -Throw
    }
    It 'classifies six valid pairs and remaining four never attempted as partial, not a clean full pass' {
        $f=New-ARCH2d4Fixture -Claims 6 -Receipts 6
        $e=Get-ARCH2d4Evidence -Fixture $f
        $e.AllTenClaimAndReturnInternallyConsistent | Should -BeFalse
        $e.LinkedPairs | Should -Be 6
        $e.Items[6].EvidenceStatus | Should -BeExactly 'NotClaimed'
    }
    It 'reports missing ninth receipt with intact tenth claim and marks claim-without-return' {
        $f=New-ARCH2d4Fixture -Claims 10 -Receipts 9
        $e=Get-ARCH2d4Evidence -Fixture $f
        $e.Items[9].EvidenceStatus | Should -BeExactly 'ClaimWithoutValidReturn'
        $e.Receipts | Should -Be 9
    }
    It 'detects non-prefix claim sequence and non-prefix return sequence' {
        $f=New-ARCH2d4Fixture -MissingFifthClaim
        $e=Get-ARCH2d4Evidence -Fixture $f
        $e.AllTenClaimAndReturnInternallyConsistent | Should -BeFalse
        @($e.Issues|Where-Object{$_ -match 'NonPrefixClaimSequence'}).Count | Should -BeGreaterThan 0
        @($e.Issues|Where-Object{$_ -match 'NonPrefixReturnSequence'}).Count | Should -BeGreaterThan 0
    }
    It 'detects duplicate returned destination EntryID across two receipts' {
        $f=New-ARCH2d4Fixture -DuplicateFifthDestination
        $e=Get-ARCH2d4Evidence -Fixture $f
        @($e.Issues|Where-Object{$_ -match 'InvalidOrTornReturnReceipt'}).Count | Should -BeGreaterThan 0
    }
    It 'detects malformed individual claim JSON and does not treat it as unattempted' {
        $f=New-ARCH2d4Fixture
        $p=Get-OPA265ARCH2dItemClaimPath -Layout $f.Layout -Ordinal 5
        [IO.File]::WriteAllBytes($p,[byte[]]@(123,34,88))
        $e=Get-ARCH2d4Evidence -Fixture $f
        $e.Items[4].ClaimStatus | Should -BeExactly 'Invalid'
        $e.Items[4].EvidenceStatus | Should -BeExactly 'InvalidEvidenceManualReview'
    }
    It 'detects mismatch in return claim SHA instead of marking it valid' {
        $f=New-ARCH2d4Fixture
        $p=Get-OPA265ARCH2dItemClaimPath -Layout $f.Layout -Ordinal 2 -Kind Return
        $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json
        $v.ClaimSha256='0'*64
        [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 12))
        $e=Get-ARCH2d4Evidence -Fixture $f
        $e.Items[1].ReturnStatus | Should -BeExactly 'Invalid'
    }
    It 'detects return receipt changed to another folder even if still valid JSON' {
        $f=New-ARCH2d4Fixture
        $p=Get-OPA265ARCH2dItemClaimPath -Layout $f.Layout -Ordinal 2 -Kind Return
        $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json
        $v.DestinationFolderId='WRONG'
        [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 12))
        (Get-ARCH2d4Evidence -Fixture $f).Items[1].ReturnStatus | Should -BeExactly 'Invalid'
    }
    It 'detects receipt tampering of RunId to another case' {
        $f=New-ARCH2d4Fixture
        $p=Get-OPA265ARCH2dItemClaimPath -Layout $f.Layout -Ordinal 4 -Kind Return
        $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json
        $v.RunId='another-run'
        [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 12))
        (Get-ARCH2d4Evidence -Fixture $f).Items[3].ReturnStatus | Should -BeExactly 'Invalid'
    }
    It 'detects receipt without item claim' {
        $f=New-ARCH2d4Fixture
        $p=Get-OPA265ARCH2dItemClaimPath -Layout $f.Layout -Ordinal 5
        [IO.File]::Delete($p)
        $e=Get-ARCH2d4Evidence -Fixture $f
        $e.Items[4].IssueCodes | Should -Contain 'ReceiptWithoutItemClaim'
    }
    It 'detects an individual claim claiming wrong original EntryID' {
        $f=New-ARCH2d4Fixture
        $p=Get-OPA265ARCH2dItemClaimPath -Layout $f.Layout -Ordinal 5
        $v=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json
        $v.SourceEntryId='1234567890ABCDEF9999'
        [IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 12))
        (Get-ARCH2d4Evidence -Fixture $f).Items[4].ClaimStatus | Should -BeExactly 'Invalid'
    }
    It 'rejects oversized per-item journal beyond 1MiB without unbounded parse' {
        $f=New-ARCH2d4Fixture
        $p=Get-OPA265ARCH2dItemClaimPath -Layout $f.Layout -Ordinal 5
        [IO.File]::WriteAllBytes($p,(New-Object byte[] 1048577))
        (Get-ARCH2d4Evidence -Fixture $f).Items[4].ClaimStatus | Should -BeExactly 'Invalid'
    }
    It 'reports evidence-only without Outlook contact and no physical PST examination' {
        $f=New-ARCH2d4Fixture
        $e=Get-ARCH2d4Evidence -Fixture $f
        $report=Get-OPA265ARCH2d4PublicEvidenceReport -Evidence $e
        $report.Status | Should -BeExactly 'TenClaimsAndReceiptsInternallyConsistentNoLiveVerification'
        $report.OutlookContacted | Should -BeFalse
        $report.SourceOrArchivePstOpenedByTool | Should -BeFalse
    }
    It 'never emits original raw Body or recipients in evidence report' {
        $f=New-ARCH2d4Fixture
        $r=Get-OPA265ARCH2d4PublicEvidenceReport -Evidence (Get-ARCH2d4Evidence -Fixture $f)
        $r.PSObject.Properties.Name | Should -Not -Contain 'Manifest'
        $r.PSObject.Properties.Name | Should -Not -Contain 'GlobalClaim'
        $r.PerItemReceiptsExternallyHashPinned | Should -BeFalse
    }
    It 'read-only plan does not require attached Outlook or existing synthetic PST' {
        $r=Invoke-OPA265ARCH2d4Audit -Mode Plan -RunId $script:run -SourcePst $script:source
        $r.Status | Should -BeExactly 'ReadOnlyExistingTenMessageForensicPlanNoOutlookNoDiskWrites'
        $r.AutomaticRetryAllowed | Should -BeFalse
    }
}
Describe 'ARCH2d4 pure per-item live forensic decision matrix' {
    It 'classifies anchored original claimed and receipt-linked moved content' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision) -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true
        $r.Status | Should -BeExactly 'MovedContentMatchedReceiptLinked'
        $r.ConfirmedMoved | Should -BeTrue
    }
    It 'does not silently accept moved content with missing receipt' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision -Return Missing) -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true
        $r.Status | Should -BeExactly 'MovedContentMatchedReceiptMissingManualReview'
        $r.ConfirmedMoved | Should -BeFalse
        $r.IssueCodes | Should -Contain 'MoveReturnReceiptMissing'
    }
    It 'does not trust invalid receipt even when destination matches source fully' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision -Return Invalid) -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true
        $r.Status | Should -BeExactly 'ManualReviewRequired'
        $r.IssueCodes | Should -Contain 'MovedButInvalidReturnReceipt'
    }
    It 'accepts missing claim/receipt only as never attempted with original still present' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision -Claim Missing -Return Missing) -SourcePresence 1 -MatchingDestinationCount 0
        $r.Status | Should -BeExactly 'UnattemptedSourcePresentNoRetryPermit'
        $r.Untouched | Should -BeTrue
        $r.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'claimed but original still present is indeterminate, not a safe retry' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision -Return Missing) -SourcePresence 1 -MatchingDestinationCount 0
        $r.Status | Should -BeExactly 'ManualReviewRequired'
        $r.IssueCodes | Should -Contain 'ClaimedButOriginalStillPresent'
    }
    It 'original source unknown MAPI provider never counted as absent' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision) -SourcePresence -1 -MatchingDestinationCount 1 -FullSemanticContentMatches $true
        $r.ConfirmedMoved | Should -BeFalse
        $r.IssueCodes | Should -Contain 'UnknownSourceEntryIdProvider'
    }
    It 'missing original and missing archive triggers manual review' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision) -SourcePresence 0 -MatchingDestinationCount 0
        $r.Status | Should -BeExactly 'ManualReviewRequired'
        $r.IssueCodes | Should -Contain 'OriginalMissingAndNoArchiveMatch'
    }
    It 'same original and matching archive simultaneously cannot be clean' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision) -SourcePresence 1 -MatchingDestinationCount 1 -FullSemanticContentMatches $true
        $r.ConfirmedMoved | Should -BeFalse
        $r.IssueCodes | Should -Contain 'OriginalStillPresentAndDestinationMatches'
    }
    It 'duplicate signature in archive blocks confirmation' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision) -SourcePresence 0 -MatchingDestinationCount 2 -FullSemanticContentMatches $true
        $r.ConfirmedMoved | Should -BeFalse
        $r.IssueCodes | Should -Contain 'DuplicateDestinationSignature'
    }
    It 'semantic mismatch blocks confirmation even with receipt' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision) -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $false
        $r.IssueCodes | Should -Contain 'DestinationSemanticDifference'
        $r.ConfirmedMoved | Should -BeFalse
    }
    It 'missing claim but moved mail never counts as verified' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision -Claim Missing -Return Missing) -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true
        $r.IssueCodes | Should -Contain 'MovedWithoutIndividualClaim'
    }
    It 'incomplete folder scan prevents live verification' {
        $r=Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision) -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true -DestinationScanComplete $false
        $r.IssueCodes | Should -Contain 'DestinationScanIncomplete'
    }
    It 'never certifies a batch with a single missing receipt' {
        $f=New-ARCH2d4Fixture -Claims 10 -Receipts 9
        $e=Get-ARCH2d4Evidence -Fixture $f
        $d=New-Object 'System.Collections.Generic.List[object]'
        foreach($x in $e.Items){
            $d.Add((Get-OPA265ARCH2d4ItemDecision -EvidenceItem $x -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true))|Out-Null
        }
        $res=Get-OPA265ARCH2d4BatchDecision -ItemDecisions @($d.ToArray()) -Evidence $e -DestinationCount 10 -UnexpectedDestinationCount 0 -DuplicateDestinationCount 0 -OutlookRestartConfirmed $true
        $res.FullyVerified | Should -BeFalse
        $res.Status | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
        $res.MatchedContentWithMissingReceipt | Should -Be 1
    }
    It 'classifies ten linked receipts + full content as consistent while noting missing external receipt pins' {
        $f=New-ARCH2d4Fixture
        $e=Get-ARCH2d4Evidence -Fixture $f
        $d=New-Object 'System.Collections.Generic.List[object]'
        foreach($x in $e.Items){
            $d.Add((Get-OPA265ARCH2d4ItemDecision -EvidenceItem $x -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true))|Out-Null
        }
        $res=Get-OPA265ARCH2d4BatchDecision -ItemDecisions @($d.ToArray()) -Evidence $e -DestinationCount 10 -UnexpectedDestinationCount 0 -DuplicateDestinationCount 0 -OutlookRestartConfirmed $true
        $res.FullyVerified | Should -BeTrue
        $res.Status | Should -BeExactly 'AllTenLiveSemanticMatchesReceiptsInternallyConsistent'
        $res.ClaimsAndReceiptsExternallyHashPinned | Should -BeFalse
    }
    It 'classifies 5 confirmed/5 original unattempted as partial, no resume permit' {
        $f=New-ARCH2d4Fixture -Claims 5 -Receipts 5
        $e=Get-ARCH2d4Evidence -Fixture $f
        $d=New-Object 'System.Collections.Generic.List[object]'
        foreach($x in $e.Items){
            if($x.Ordinal -le 5){
                $d.Add((Get-OPA265ARCH2d4ItemDecision -EvidenceItem $x -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true))|Out-Null
            }else{
                $d.Add((Get-OPA265ARCH2d4ItemDecision -EvidenceItem $x -SourcePresence 1 -MatchingDestinationCount 0))|Out-Null
            }
        }
        $res=Get-OPA265ARCH2d4BatchDecision -ItemDecisions @($d.ToArray()) -Evidence $e -DestinationCount 5 -UnexpectedDestinationCount 0 -DuplicateDestinationCount 0 -OutlookRestartConfirmed $true
        $res.Status | Should -BeExactly 'PartialBatchReadOnlyClassifiedNoResumePermit'
        $res.VerifiedWithLinkedReceipt | Should -Be 5
        $res.Unattempted | Should -Be 5
        $res.AutomaticRetryAllowed | Should -BeFalse
    }
    It 'refuses all-ten verification without independent Outlook restart' {
        $f=New-ARCH2d4Fixture
        $e=Get-ARCH2d4Evidence -Fixture $f
        $d=@(foreach($x in $e.Items){
            Get-OPA265ARCH2d4ItemDecision -EvidenceItem $x -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true
        })
        $res=Get-OPA265ARCH2d4BatchDecision -ItemDecisions $d -Evidence $e -DestinationCount 10 -UnexpectedDestinationCount 0 -DuplicateDestinationCount 0 -OutlookRestartConfirmed $false
        $res.FullyVerified | Should -BeFalse
    }
    It 'refuses all-ten verification if another unexpected destination mail exists' {
        $f=New-ARCH2d4Fixture
        $e=Get-ARCH2d4Evidence -Fixture $f
        $d=@(foreach($x in $e.Items){Get-OPA265ARCH2d4ItemDecision -EvidenceItem $x -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true})
        $res=Get-OPA265ARCH2d4BatchDecision -ItemDecisions $d -Evidence $e -DestinationCount 11 -UnexpectedDestinationCount 1 -DuplicateDestinationCount 0 -OutlookRestartConfirmed $true
        $res.FullyVerified | Should -BeFalse
        $res.Status | Should -BeExactly 'ManualReviewRequiredNoAutomaticRetry'
    }
    It 'refuses all-ten verification if destination contains duplicate mail' {
        $f=New-ARCH2d4Fixture
        $e=Get-ARCH2d4Evidence -Fixture $f
        $d=@(foreach($x in $e.Items){Get-OPA265ARCH2d4ItemDecision -EvidenceItem $x -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true})
        (Get-OPA265ARCH2d4BatchDecision -ItemDecisions $d -Evidence $e -DestinationCount 11 -UnexpectedDestinationCount 0 -DuplicateDestinationCount 1 -OutlookRestartConfirmed $true).FullyVerified | Should -BeFalse
    }
    It 'no batch decision can carry fewer than ten exact identities' {
        $f=New-ARCH2d4Fixture
        $e=Get-ARCH2d4Evidence -Fixture $f
        $d=@(1..9|ForEach-Object{Get-OPA265ARCH2d4ItemDecision -EvidenceItem (New-ARCH2d4Decision -Ordinal $_) -SourcePresence 0 -MatchingDestinationCount 1 -FullSemanticContentMatches $true})
        {Get-OPA265ARCH2d4BatchDecision -ItemDecisions $d -Evidence $e -DestinationCount 9 -UnexpectedDestinationCount 0 -DuplicateDestinationCount 0 -OutlookRestartConfirmed $true} | Should -Throw
    }
}
Describe 'ARCH2d4 read-only production safety static fences' {
    It 'auditor contains zero direct COM write methods and no PST mount' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/ARCH2d4LiveAudit.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match '\.(Move|Copy|Save|Delete|AddStoreEx|RemoveStore)\s*\('
        $s | Should -Not -Match 'Write-OPA265ARCH2c4JsonOnce'
    }
    It 'evidence module contains zero journal writes and no Outlook process startup' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/ARCH2d4EvidencePolicy.ps1') -Raw -Encoding UTF8
        $s | Should -Not -Match 'Write-OPA265ARCH2c4JsonOnce'
        $s | Should -Not -Match 'GetActiveObject\s*\('
        $s | Should -Not -Match '\.(Move|Copy|Save|Delete|AddStoreEx)\s*\('
    }
    It 'original real ARCH2d MoveBatch code remains separated and unchanged' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Archive/ARCH2dBatchCore.ps1') -Raw -Encoding UTF8
        ([regex]::Matches($s,'\$item\.Move\(\$target\)')).Count | Should -Be 1
        $s | Should -Match 'ARCH2d global batch was already claimed'
    }
    It 'new operator entrypoint has three read-only modes, none of which include MoveBatch' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Invoke-ARCH2d4.ps1') -Raw -Encoding UTF8
        $s | Should -Match "ValidateSet\('Plan','Evidence','LiveAudit'\)"
        $s | Should -Not -Match "ValidateSet\('Plan','Inventory','Prepare','MoveBatch','Reconcile'\)"
    }
    It 'original production writer gate still blocks Archive/Resume/Auto' {
        $s=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw -Encoding UTF8
        $s | Should -Match 'Assert-OPA265ARCH2aDevelopmentWriterClosed'
    }
}
