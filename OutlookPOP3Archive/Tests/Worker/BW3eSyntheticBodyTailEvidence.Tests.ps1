#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3bIndependentAudit265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3dSyntheticSizeEvidence265.ps1')
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1')
}
Describe 'BW3e exact synthetic SPACE CR LF Body tail without size waiver or MailItem.Move' {
    BeforeEach {
        $script:p=Get-OPA265BW3ePinnedTailEvidence
        $script:baseline=$script:p.FixtureBody
        $script:candidate=$script:baseline+[char]32+[char]13+[char]10
        $script:previous=[pscustomobject]@{
            Schema='2.6.5-BW3d.SyntheticSizeReadOnlyEvidence.1'
            Status='UnexpectedSyntheticContentStopAndInvestigate'
            Decision='SizeDifferenceUnapprovedManualDecisionRequired'
            RunId=$script:p.RunId
            OperationId=$script:p.OperationId
            WorkerRequestId=$script:p.WorkerRequestId
            JournalSha256=$script:p.JournalSha256
            ArchiveEntryIdMatchesWorker=$true
            IntentSizeBytes=1436L
            ObservedArchiveSizeBytes=1444L
            SizeDifferenceBytes=8L
            PinnedEightByteDriftObserved=$true
            ExpectedSyntheticBodyUtf8Sha256=(Get-OPA265BW3dUtf8TextSha256 -Text $script:baseline)
            ObservedBodyUtf8Sha256=$script:p.ExpectedBodySha256
            BodyTextMatchesFixtureExactly=$false
            BodyTextMatchesAfterTrailingCrLfTrim=$false
            ExpectedAttachmentCount=0
            ObservedAttachmentCount=0
            AttachmentsCountMatchesFixture=$true
            MessageClassMatchesFixture=$true
            PrMessageSizeAvailable=$true
            PrMessageSizeBytes=1444L
            PrMessageSizeMatchesMailItemSize=$true
            EvidenceSufficientForContentByteEquality=$false
            EvidenceSufficientForAutomaticSizeApproval=$false
            ArchiveSizeDifferenceApproved=$false
            RequiresManualSizeReview=$true
            ManualJournalDecisionAuthorized=$false
            OnlySyntheticFoldersInspected=$true
            OutlookReadOnlyInspectionExecuted=$true
            OutlookMoveExecuted=$false
            JournalChanged=$false
            JournalCompleted=$false
            JournalReconciled=$false
            AutomaticRetryAllowed=$false
            ProductionReady=$false
            NextAction='PreserveIntentClaimsAndRequestIndependentSizeDecision'
        }
    }
    It 'retains the already observed exact RunId and OperationId' {
        $script:p.RunId | Should -BeExactly 'a7b51427-7494-43f4-bc96-64915f6bee7e'
        $script:p.OperationId | Should -BeExactly '9bd83da2-d47e-404f-a4fd-792852b58dec'
    }
    It 'retains pinned WorkerRequestId and archive EntryID' {
        $script:p.WorkerRequestId | Should -BeExactly '24553e9c-fa09-497f-b42d-4329ebe27021'
        $script:p.ArchiveEntryId | Should -BeExactly '00000000953C628FC9EAC24E97DBE040019A969924002000'
    }
    It 'retains unchanged original journal SHA256 and exact Unicode source PST' {
        $script:p.JournalSha256 | Should -BeExactly '5a68dbc4186c69eff13e49c7d69a19f16eba86e04969bb5aea3be0327820a648'
        $script:p.SourcePst | Should -BeExactly (Get-OPA265BW3bPinnedIdentity).SourcePst
    }
    It 'pins previously observed 1436 to 1444 size drift, without approval' {
        $script:p.ArchiveSizeBytes | Should -Be 1444
        $script:p.IntentSizeBytes | Should -Be 1436
        $script:p.SizeDifferenceBytes | Should -Be 8
    }
    It 'recomputes user-observed BODY SHA256 for exactly SPACE+CR+LF' {
        (Get-OPA265BW3dUtf8TextSha256 -Text $script:candidate) | Should -BeExactly '82d1b1508ec29fab365b819df44c5ef24ba2dd9a68612579d474daa4949ff29e'
    }
    It 'rejects fake previous BW3d schema' {
        $script:previous.Schema='Wrong'
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'accepts exact previous stopped BW3d inspection only for this RunId' {
        (Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p) | Should -BeTrue
    }
    It 'rejects previous evidence that claims unexpected content is already resolved' {
        $script:previous.Status='SizeDriftStructureConsistentManualReviewPending'
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects a different WorkerRequestId' {
        $script:previous.WorkerRequestId=[guid]::NewGuid().ToString('D')
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects a different original journal hash' {
        $script:previous.JournalSha256='a'*64
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects any changed pinned source PST' {
        $script:p.SourcePst='C:\Other.pst'
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects a changed pinned 8-byte size difference' {
        $script:p.SizeDifferenceBytes=0
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects a changed observed body SHA in earlier independent snapshot' {
        $script:previous.ObservedBodyUtf8Sha256='f'*64
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects previous snapshot with new attachments' {
        $script:previous.ObservedAttachmentCount=1
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects prior approval of size drift' {
        $script:previous.ArchiveSizeDifferenceApproved=$true
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects prior journal completion and auto retry' {
        $script:previous.JournalCompleted=$true
        $script:previous.AutomaticRetryAllowed=$true
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'rejects previous positive byte-equivalence claim' {
        $script:previous.EvidenceSufficientForContentByteEquality=$true
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'returns exactly Unicode code units 32 13 10' {
        $units=@(Get-OPA265BW3eTailCodeUnits -Text $script:candidate -Count 3)
        ($units -join ',') | Should -BeExactly '32,13,10'
    }
    It 'does not trim any code units when extracting the suffix' {
        $units=@(Get-OPA265BW3eTailCodeUnits -Text ($script:baseline+[char]13+[char]10))
        ($units -join ',') | Should -BeExactly '46,13,10'
    }
    It 'handles shorter than three code units without a false positive' {
        $units=@(Get-OPA265BW3eTailCodeUnits -Text ([string][char]13) -Count 3)
        ($units -join ',') | Should -BeExactly '13'
    }
    It 'does not claim success based solely on matching tail after altered body' {
        $v=Get-OPA265BW3eTailVerdict -BodyText ('changed '+$script:candidate) -Previous $script:previous -Pinned $script:p
        $v.Status | Should -Be 'UnexpectedBodyTailStopAndInvestigate'
        $v.TailSpaceCrLfConfirmed | Should -BeFalse
        $v.ArchiveSizeDifferenceApproved | Should -BeFalse
    }
    It 'confirms precisely the whole baseline plus SPACE CR LF' {
        $v=Get-OPA265BW3eTailVerdict -BodyText $script:candidate -Previous $script:previous -Pinned $script:p
        $v.Status | Should -BeExactly 'SyntheticBodyTailSpaceCrLfConfirmed'
        $v.BodyTextMatchesExactBaselinePlusSpaceCrLf | Should -BeTrue
        $v.TrailingSpaceBeforeCrLfObserved | Should -BeTrue
        $v.NormalizedByRemovingExactlyThreeSuffixCharsMatchesBaseline | Should -BeTrue
        ($v.ObservedTailUnicodeCodeUnits -join ',') | Should -BeExactly '32,13,10'
    }
    It 'rejects BODY baseline followed by only CR LF' {
        $v=Get-OPA265BW3eTailVerdict -BodyText ($script:baseline+[char]13+[char]10) -Previous $script:previous -Pinned $script:p
        $v.Status | Should -Be 'UnexpectedBodyTailStopAndInvestigate'
    }
    It 'rejects BODY baseline followed by TWO spaces and CR LF' {
        $v=Get-OPA265BW3eTailVerdict -BodyText ($script:baseline+'  '+[char]13+[char]10) -Previous $script:previous -Pinned $script:p
        $v.Status | Should -Be 'UnexpectedBodyTailStopAndInvestigate'
    }
    It 'rejects BODY baseline followed by SPACE LF only' {
        $v=Get-OPA265BW3eTailVerdict -BodyText ($script:baseline+' '+[char]10) -Previous $script:previous -Pinned $script:p
        $v.Status | Should -Be 'UnexpectedBodyTailStopAndInvestigate'
    }
    It 'reports expected body length and observed body length without Body contents' {
        $v=Get-OPA265BW3eTailVerdict -BodyText $script:candidate -Previous $script:previous -Pinned $script:p
        $v.ExpectedBaselineBodyLength | Should -Be $script:baseline.Length
        $v.ObservedBodyLength | Should -Be ($script:baseline.Length+3)
        $v.PSObject.Properties.Name | Should -Not -Contain 'BodyText'
    }
    It 'always leaves eight-byte difference unapproved even when tail exact' {
        $v=Get-OPA265BW3eTailVerdict -BodyText $script:candidate -Previous $script:previous -Pinned $script:p
        $v.UnapprovedSizeDifferenceBytes | Should -Be 8
        $v.SizeDifferenceCauseEstablished | Should -BeFalse
        $v.ArchiveSizeDifferenceApproved | Should -BeFalse
        $v.ManualJournalDecisionAuthorized | Should -BeFalse
    }
    It 'never asserts that before-Move Body hash was captured' {
        $v=Get-OPA265BW3eTailVerdict -BodyText $script:candidate -Previous $script:previous -Pinned $script:p
        $v.BeforeMoveActualBodyHashAvailable | Should -BeFalse
        $v.WhenTailWasIntroducedEstablished | Should -BeFalse
        $v.ContentByteEqualityVerified | Should -BeFalse
    }
    It 'keeps journal, retry and production gates all closed after confirmation' {
        $v=Get-OPA265BW3eTailVerdict -BodyText $script:candidate -Previous $script:previous -Pinned $script:p
        $v.JournalChanged | Should -BeFalse
        $v.JournalCompleted | Should -BeFalse
        $v.JournalReconciled | Should -BeFalse
        $v.AutomaticRetryAllowed | Should -BeFalse
        $v.OutlookMoveExecuted | Should -BeFalse
        $v.ProductionReady | Should -BeFalse
    }
    It 'requires exactly 1444 archive bytes in earlier BW3d proof' {
        $script:previous.ObservedArchiveSizeBytes=1443
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'forbids a previous BW3d result with unavailable PR size property' {
        $script:previous.PrMessageSizeAvailable=$false
        { Assert-OPA265BW3ePriorSizeEvidence -Previous $script:previous -Pinned $script:p } | Should -Throw
    }
    It 'retains exact BOM for both new scripts and this test' {
        foreach($rel in @('Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1','Core/Diagnostics/Test-OPA265BW3eSyntheticBodyTailAudit.ps1','Tests/Worker/BW3eSyntheticBodyTailEvidence.Tests.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $bytes=[IO.File]::ReadAllBytes($path)
            ($bytes[0..2] -join ',') | Should -BeExactly '239,187,191'
        }
    }
    It 'keeps the read-only audit free of Move Save Delete and journal writes' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3eSyntheticBodyTailAudit.ps1') -Raw
        $src | Should -Not -Match '(?i)\.Move\(|\.Save\(|\.Delete\(|AddStoreEx\(|Write-OPAOperationJournalEvent|Write-OPA264Live6ReconciledLocked|Invoke-OPAWorkerControlledOperation|SetProperty\('
    }
    It 'runs prior BW3d and BW3b before any archive Body inspection' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3eSyntheticBodyTailAudit.ps1') -Raw
        $src | Should -Match "'Test-OPA265BW3dSyntheticSizeAudit.ps1'"
        ($src.IndexOf("'Test-OPA265BW3dSyntheticSizeAudit.ps1'") -lt $src.IndexOf('$body=[string]$mail.Body')) | Should -BeTrue
    }
    It 'pins input RunId, path and hash before Outlook COM access' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3eSyntheticBodyTailAudit.ps1') -Raw
        ($src.IndexOf('$RunId -cne [string]$pinned.RunId') -lt $src.IndexOf("GetActiveObject('Outlook.Application')")) | Should -BeTrue
        ($src.IndexOf('$SourcePst -cne [string]$pinned.SourcePst') -lt $src.IndexOf("GetActiveObject('Outlook.Application')")) | Should -BeTrue
    }
    It 'rehashes all six original durable evidence files after COM getters' {
        $src=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW3eSyntheticBodyTailAudit.ps1') -Raw
        $src | Should -Match '[$]originalHashes'
        $src | Should -Match '[$]extra[.]DispatchClaimPath'
        $src | Should -Match '[$]extra[.]ControllerResultPath'
        $src | Should -Match 'foreach[(][$]path in [$]evidenceFiles[)]'
    }
    It 'does not load BW3e from production Archive Resume or Auto' {
        $production=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../OutlookPOP3Archive.ps1') -Raw
        $production | Should -Not -Match 'BW3eSyntheticBodyTail'
    }
    It 'parses new PS5.1 code with zero AST parsing failures' {
        foreach($rel in @('Core/Worker/BW3eSyntheticBodyTailEvidence265.ps1','Core/Diagnostics/Test-OPA265BW3eSyntheticBodyTailAudit.ps1')) {
            $path=Join-Path (Join-Path $PSScriptRoot '../..') $rel
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
