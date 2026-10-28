#requires -Version 5.1
# BW4e1: run the REAL BW4e diagnostic wrapper with a synthetic BW4d-only stub.
# No actual Outlook COM/PST/journal access in these regression tests.
BeforeAll {
    $script:realDiagnostic=Join-Path $PSScriptRoot '../../Core/Diagnostics/Test-OPA265BW4eFreshSyntheticReadOnly.ps1'
    $script:realBw4c=Join-Path $PSScriptRoot '../../Core/Worker/BW4cOutlookReadOnlyCapture265.ps1'
    $script:realBw4e=Join-Path $PSScriptRoot '../../Core/Worker/BW4eFreshSyntheticCandidate265.ps1'
}
Describe 'BW4e1 live wrapper switch -Review cannot collide with $bw4dSnapshot result' {
    BeforeEach {
        $root=Join-Path $TestDrive ('BW4e1-'+[guid]::NewGuid().ToString('N'))
        $diag=Join-Path $root 'Core/Diagnostics'
        $worker=Join-Path $root 'Core/Worker'
        [void][IO.Directory]::CreateDirectory($diag)
        [void][IO.Directory]::CreateDirectory($worker)
        $script:target=Join-Path $diag 'Test-OPA265BW4eFreshSyntheticReadOnly.ps1'
        Copy-Item -LiteralPath $script:realDiagnostic -Destination $script:target
        Copy-Item -LiteralPath $script:realBw4c -Destination (Join-Path $worker 'BW4cOutlookReadOnlyCapture265.ps1')
        Copy-Item -LiteralPath $script:realBw4e -Destination (Join-Path $worker 'BW4eFreshSyntheticCandidate265.ps1')
        $fake=@'
#requires -Version 5.1
[CmdletBinding()]
param(
 [string]$RunId,[string]$SourcePst,[string]$ExpectedJournalSha256,
 [string]$Mode,[string]$Transaction,[string]$FolderEntryId,
 [string]$CandidateEntryId,[string]$ExpectedProfileName,
 [int]$MaxFolderItems,[string]$HistoryRoot,[int]$MaxHistoryRuns,
 [switch]$Review,[switch]$ConfirmExistingOutlookReadOnly
)
if (-not $Review -or -not $ConfirmExistingOutlookReadOnly) { throw 'Stub must retain explicit read-only consent.' }
[pscustomobject][ordered]@{
 Schema='2.6.5-BW4d.IndependentJournalReplayReviewReadOnly.1'
 Status='IndependentReadOnlyJournalAndOutlookEvidenceReviewedNoMovePermit'
 CandidateStatus='BlockedKnownPriorLive3Live4OperationEvidence'
 CandidateEntryId='00aabbcc'
 InternetMessageId='<opa264-live3-77854a93-ecfd-42c7-b58e-2948fe9afa88@example.invalid>'
 SourceStoreId='MOCK_POP3_STORE'
 SourceItemFingerprintSha256=('b'*64)
 SearchKeySha256=('a'*64)
 HistoricalOperationMatches=@('OPA264-LIVE3-77854a93ecfd42c7b58e2948fe9afa88:e249f73b-8cdf-4672-92e3-5c49f8feaca0:Intent')
 SyntheticLive3Identity=$true
 HistoryEvidenceFilesUnchanged=$true
 HistoryCatalogComplete=$false
 IndependentlyAuthenticatedExternalMAPIContent=$false
 ReplaySafetyProven=$false
 SevenHistoricalEvidenceHashesUnchanged=$true
 HistoricJournalEventCount=1
 HistoricJournalPhase='Intent'
 HistoricalJournalChanged=$false
 HistoricalClaimCreated=$false
 WorkerDispatchAllowed=$false
 OutlookMoveExecuted=$false
 CanRetryPreviousMove=$false
 ProductionReady=$false
 RunDirectoriesScanned=7
 JournalsScanned=5
 HistoryEvidenceSnapshotSha256=('c'*64)
}
'@
        $fakePath=Join-Path $diag 'Test-OPA265BW4dHistoryReplayReadOnly.ps1'
        [IO.File]::WriteAllText($fakePath,$fake,(New-Object Text.UTF8Encoding($true)))
        $script:run=[ordered]@{
            RunId='a7b51427-7494-43f4-bc96-64915f6bee7e'
            SourcePst='C:\FAKE-UNIT-TEST\source.pst'
            ExpectedJournalSha256=('d'*64)
            Mode='Archive'
            FolderEntryId='00bbccdd'
            CandidateEntryId='00AABBCC'
            ExpectedProfileName='Outlook'
            CandidateReviewId='49bf59da-6d84-4e36-8b6d-0d9857b8eed1'
            ExpectedInternetMessageId='<opa264-live3-77854a93-ecfd-42c7-b58e-2948fe9afa88@example.invalid>'
            ExpectedSearchKeySha256=('a'*64)
            ExpectedContentFingerprintSha256=('b'*64)
            Review=$true
            ConfirmExistingOutlookReadOnly=$true
        }
    }
    It 'executes the actual wrapper without PSCustomObject-to-SwitchParameter conversion' {
        $out=& $script:target @run
        $out.Schema | Should -BeExactly '2.6.5-BW4e.FreshSyntheticCandidatePreMoveReadOnly.1'
        $out.Status | Should -BeExactly 'BlockedPreviouslyUsedSyntheticOrKnownOperation'
    }
    It 'retains no Move, no Worker and no previous-operation retry for a known LIVE3 item' {
        $out=& $script:target @run
        $out.WorkerDispatchAllowed | Should -BeFalse
        $out.CanRetryPreviousMove | Should -BeFalse
        $out.CanInvokeMailMove | Should -BeFalse
        $out.OutlookMoveExecuted | Should -BeFalse
        $out.HistoricJournalPhase | Should -BeExactly 'Intent'
        $out.HistoryEvidenceFilesUnchanged | Should -BeTrue
    }
    It 'requires the explicit -Review switch rather than treating the object as consent' {
        $script:run.Review=$false
        { & $script:target @run } | Should -Throw '*requires -Review*'
    }
    It 'rejects the historic RunId as the candidate review GUID before attempting the BW4d stub' {
        $script:run.CandidateReviewId=$script:run.RunId
        { & $script:target @run } | Should -Throw '*distinct new nonempty candidate*'
    }
    It 'has no assignment to a case-insensitive parameter named Review in the real wrapper AST' {
        $tokens=$null
        $errors=$null
        $ast=[System.Management.Automation.Language.Parser]::ParseFile($script:target,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $reassign=@($ast.FindAll({
            param($node)
            if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
            if ($node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }
            return [string]::Equals(
                [string]$node.Left.VariablePath.UserPath,
                'Review',
                [StringComparison]::OrdinalIgnoreCase
            )
        },$true))
        $reassign.Count | Should -Be 0
    }
}
