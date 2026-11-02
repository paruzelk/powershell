#requires -Version 5.1
BeforeAll {
    . (Join-Path $PSScriptRoot '../../Core/Worker/BW4j5SyntheticReconcile265.ps1')
    function New-BW4j6PesterSandbox {
        $root=Join-Path $TestDrive ('OPA265-BW4j6-SYNTH-'+[guid]::NewGuid().ToString('N'))
        New-OPA265BW4j4Sandbox -SandboxRoot $root
    }
}
Describe 'BW4j4 separate immutable rollback-safe synthetic suite' {
    BeforeEach { $script:s=New-BW4j6PesterSandbox }
    It 'creates exactly five deterministic new fake mail files with unique GUIDs' {
        $m=Get-OPA265BW4j4Manifest -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256
        @($m.Fixtures).Count | Should -Be 5
        @($m.Plan.Cases.TestId|Select-Object -Unique).Count | Should -Be 5
    }
    It 'starts with original source only and no claims or receipts' {
        $m=Get-OPA265BW4j4Manifest -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256
        foreach($case in @($m.Plan.Cases)){
            $state=Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $case.TestId
            $state.State | Should -BeExactly 'PendingUnclaimed'
            $state.SourceExists | Should -BeTrue
            $state.ClaimExists | Should -BeFalse
        }
    }
    It 'does not accept real POP3 PST directory as a synthetic sandbox' {
        {Assert-OPA265BW4j4SandboxRoot -SandboxRoot 'C:\Users\test\Documents\Файлы Outlook\info@stios.ru.pst'} | Should -Throw
    }
    It 'rejects wrong leaf name or UNC paths' {
        {Assert-OPA265BW4j4SandboxRoot -SandboxRoot 'C:\Temp\RegularDirectory'} | Should -Throw
        {Assert-OPA265BW4j4SandboxRoot -SandboxRoot '\\server\share\OPA265-BW4j6-SYNTH-11111111111111111111111111111111'} | Should -Throw
    }
    It 'rejects second initialization, preserving the source inventory' {
        {New-OPA265BW4j4Sandbox -SandboxRoot $script:s.SandboxRoot} | Should -Throw
    }
    It 'rejects manifest SHA not independently pinned' {
        {Get-OPA265BW4j4Manifest -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 ('0'*64)} | Should -Throw
    }
    It 'proves simulated fixture is not production-capable' {
        $m=Get-OPA265BW4j4Manifest -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256
        $m.SyntheticOnly | Should -BeTrue
        $m.OutlookCOMAllowed | Should -BeFalse
        $m.PstAccessAllowed | Should -BeFalse
        $m.ProductionReady | Should -BeFalse
    }
    It 'rejects fixture TestId that was not in the suite' {
        {Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId '841545a1-b5fa-4c69-964a-8c0318981d52'} | Should -Throw
    }
}
Describe 'BW4j4 atomic one-shot claim and no retry under synthetic faults' {
    BeforeEach {
        $script:s=New-BW4j6PesterSandbox
        $script:m=Get-OPA265BW4j4Manifest -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256
        $script:id=[string]$script:m.Plan.Cases[0].TestId
    }
    It 'requires explicit operator synthetic consent' {
        {Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot:$false} | Should -Throw '*explicit isolated synthetic confirmation required*'
    }
    It 'emits one claim before simulated local rename and never invokes Outlook' {
        $r=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot
        $r.Status | Should -BeExactly 'SyntheticFileMovedRequiresIndependentReconciliation'
        $r.MoveAttempts | Should -Be 1
        $r.OutlookMoveExecuted | Should -BeFalse
        $r.ClaimSha256 | Should -Match '^[a-f0-9]{64}$'
        $state=Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id
        $state.State | Should -BeExactly 'MoveObservedAwaitIndependentReconciliation'
    }
    It 'rejects repetition even after a successful synthetic move' {
        $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot
        {Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot} | Should -Throw '*NEVER retry*'
    }
    It 'injected after-claim crash persists one claim, source intact and blocks automatic replay' {
        {Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot -CrashPoint AfterClaim} | Should -Throw '*INJECTED CRASH after durable claim*'
        $state=Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id
        $state.State | Should -BeExactly 'ClaimedSourceStillPresentNeverRetry'
        {Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot} | Should -Throw '*NEVER retry*'
    }
    It 'injected after-move crash has one destination and is safe for read-only reconciliation only' {
        {Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot -CrashPoint AfterMove} | Should -Throw '*INJECTED CRASH after atomic synthetic move*'
        $state=Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id
        $state.State | Should -BeExactly 'MoveObservedAwaitIndependentReconciliation'
        (Get-OPA265BW4j5Reconciliation -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id).Status | Should -BeExactly 'SyntheticMoveConfirmedModelOnlyNoOutlookProof'
    }
    It 'refuses claimed source still present to be accepted as completed move' {
        {Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot -CrashPoint AfterClaim} | Should -Throw
        {Get-OPA265BW4j5Reconciliation -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id} | Should -Throw
    }
}
Describe 'BW4j5 independent synthetic five-format/attachment evidence' {
    BeforeEach {
        $script:s=New-BW4j6PesterSandbox
        $script:m=Get-OPA265BW4j4Manifest -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256
        $script:id=[string]$script:m.Plan.Cases[3].TestId
    }
    It 'calculates actual binary bytes SHA of 1024-byte attachment from Base64 input' {
        $row=Get-OPA265BW4j4FixtureRow -Manifest $script:m -TestId $script:id
        $paths=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $script:id
        $mail=Get-Content -LiteralPath $paths.Source -Encoding UTF8 -Raw | ConvertFrom-Json
        $w=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $script:m.Plan.SuiteId
        $w.Attachments.Count | Should -Be 1
        $w.Attachments[0].ByteCount | Should -Be 1024
        $w.Attachments[0].Sha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'calculates binary hash for 256KiB attachment with exactly 262144 decoded bytes' {
        $id=$script:m.Plan.Cases[4].TestId
        $row=Get-OPA265BW4j4FixtureRow -Manifest $script:m -TestId $id
        $p=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $id
        $mail=Get-Content -LiteralPath $p.Source -Encoding UTF8 -Raw | ConvertFrom-Json
        $w=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $script:m.Plan.SuiteId
        $w.Attachments[0].ByteCount | Should -Be 262144
        $w.Attachments[0].Sha256 | Should -Match '^[a-f0-9]{64}$'
    }
    It 'compares HTML separately from plain Body, and excludes real MAPI conclusions' {
        $id=$script:m.Plan.Cases[2].TestId
        $row=Get-OPA265BW4j4FixtureRow -Manifest $script:m -TestId $id
        $p=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $id
        $mail=Get-Content -LiteralPath $p.Source -Encoding UTF8 -Raw | ConvertFrom-Json
        $a=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $script:m.Plan.SuiteId
        $b=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $script:m.Plan.SuiteId -Destination
        $r=Compare-OPA265BW4j5FieldWitness -Before $a -After $b
        $r.HtmlBodyMatches | Should -BeTrue
        $r.BodyMatches | Should -BeTrue
        $r.RealOutlookMAPIObserved | Should -BeFalse
        $r.SyntheticSizeDelta | Should -Be 38
    }
    It 'reports injected HTML corruption without accepting it as size-only' {
        $row=Get-OPA265BW4j4FixtureRow -Manifest $script:m -TestId $script:id
        $p=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $script:id
        $mail=Get-Content -LiteralPath $p.Source -Encoding UTF8 -Raw | ConvertFrom-Json
        $a=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $script:m.Plan.SuiteId
        $b=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $script:m.Plan.SuiteId -Destination
        $b.HtmlBodySha256=('0'*64)
        (Compare-OPA265BW4j5FieldWitness -Before $a -After $b).Status | Should -BeExactly 'BLOCKED_SyntheticContentOrAttachmentDrift'
    }
    It 'reports changed bytewise attachment digest' {
        $row=Get-OPA265BW4j4FixtureRow -Manifest $script:m -TestId $script:id
        $p=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $script:id
        $mail=Get-Content -LiteralPath $p.Source -Encoding UTF8 -Raw | ConvertFrom-Json
        $a=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $script:m.Plan.SuiteId
        $b=Get-OPA265BW4j5FieldWitness -Mail $mail -Case $row.Case -SuiteId $script:m.Plan.SuiteId -Destination
        $b.Attachments[0].Sha256=('f'*64)
        (Compare-OPA265BW4j5FieldWitness -Before $a -After $b).AttachmentsMatch | Should -BeFalse
    }
    It 'cannot reconcile unclaimed input' {
        {Get-OPA265BW4j5Reconciliation -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id} | Should -Throw
    }
    It 'rechecks unchanged sealed target bytes and original claim after one-shot move' {
        $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot
        $r=Get-OPA265BW4j5Reconciliation -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id
        $r.Status | Should -BeExactly 'SyntheticMoveConfirmedModelOnlyNoOutlookProof'
        $r.AttachmentsMatch | Should -BeTrue
        $r.RealMAPIFieldEqualityProven | Should -BeFalse
        $r.CanWriteHistoricalJournal | Should -BeFalse
    }
    It 'detects target payload tampering with one extra byte after move' {
        $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot
        $p=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $script:id
        [IO.File]::AppendAllText($p.Target,'X')
        {Get-OPA265BW4j5Reconciliation -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id} | Should -Throw '*differs from independent source manifest*'
    }
    It 'creates receipt once and independently rechecks its original claim hash' {
        $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id -ConfirmIsolatedSyntheticOneShot
        $r=Write-OPA265BW4j5ReceiptOnce -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id
        $r.ReceiptSha256 | Should -Match '^[a-f0-9]{64}$'
        {Write-OPA265BW4j5ReceiptOnce -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id} | Should -Throw '*already exists*'
        $state=Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $script:id
        $state.State | Should -BeExactly 'ReceiptExistsReadOnlyVerify'
    }
}
Describe 'BW4j5 five-message summary and BW4j6 crash/duplicates fail closed' {
    BeforeEach {
        $script:s=New-BW4j6PesterSandbox
        $script:m=Get-OPA265BW4j4Manifest -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256
    }
    It 'reports pending five without claiming successful moves' {
        $summary=Get-OPA265BW4j5SuiteSummary -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256
        $summary.IndependentlyReconciled | Should -Be 0
        $summary.PendingOrUnreconciled | Should -Be 5
        $summary.AllFiveSyntheticItemsReconciled | Should -BeFalse
    }
    It 'completes all five independent synthetic receipts without asserting real Outlook proofs' {
        foreach($case in @($script:m.Plan.Cases)){
            $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $case.TestId -ConfirmIsolatedSyntheticOneShot
            $null=Write-OPA265BW4j5ReceiptOnce -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $case.TestId
        }
        $summary=Get-OPA265BW4j5SuiteSummary -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256
        $summary.AllFiveSyntheticItemsReconciled | Should -BeTrue
        $summary.IndependentlyReconciled | Should -Be 5
        $summary.RealPstTouched | Should -BeFalse
        $summary.OutlookUsed | Should -BeFalse
    }
    It 'detects double source and destination as blocked unsafe state' {
        $id=$script:m.Plan.Cases[1].TestId
        $null=Invoke-OPA265BW4j4OneShotSyntheticMove -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $id -ConfirmIsolatedSyntheticOneShot
        $p=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $id
        [IO.File]::Copy($p.Target,$p.Source)
        (Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $id).State | Should -BeExactly 'BLOCKED_DuplicateSourceAndDestination'
    }
    It 'flags unclaimed destination as unsafe, no fallback movement' {
        $id=$script:m.Plan.Cases[1].TestId
        $p=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $id
        [IO.File]::Move($p.Source,$p.Target)
        (Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $id).State | Should -BeExactly 'BLOCKED_UnclaimedMove'
    }
    It 'reports missing both copies as blocked loss condition' {
        $id=$script:m.Plan.Cases[1].TestId
        $p=Get-OPA265BW4j4Paths -Root $script:s.SandboxRoot -TestId $id
        [IO.File]::Delete($p.Source)
        (Get-OPA265BW4j4State -SandboxRoot $script:s.SandboxRoot -ExpectedManifestSha256 $script:s.ManifestSha256 -TestId $id).State | Should -BeExactly 'BLOCKED_MissingSourceAndDestination'
    }
}
Describe 'BW4j6 static safety and GitHub Actions-only matrix gate' {
    BeforeAll {
        $script:matrix=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../Core/Diagnostics/Invoke-OPA265BW4j6SyntheticMatrix.ps1'))
        $script:worker=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../../Core/Worker/BW4j4SyntheticOneShot265.ps1'))
    }
    It 'has no Outlook COM activation or real MailItem.Move in synthetic writer' {
        $script:worker | Should -Not -Match "GetActiveObject\('Outlook.Application'\)"
        $script:worker | Should -Not -Match '\$mail\.Move\('
        $script:worker | Should -Not -Match '\.AddStoreEx\('
    }
    It 'has explicit synthetic runner gate requiring GitHub Actions' {
        $script:matrix | Should -Match 'GITHUB_ACTIONS'
        $script:matrix | Should -Match 'RequireGitHubActions'
    }
    It 'models plus 38 but never asserts five live Outlook identical deltas' {
        $script:matrix | Should -Match 'RealOutlookSizeDeltaForFiveMessagesProven=\$false'
        $script:matrix | Should -Match 'AssumedSyntheticSizeDelta=38'
    }
    It 'implements both crash injections and fault recovery without retries' {
        $script:matrix | Should -Match 'CrashPoint AfterClaim'
        $script:matrix | Should -Match 'CrashPoint AfterMove'
        $script:matrix | Should -Match 'NEVER retry'
    }
    It 'does not alter original historic BW3a Intent or BW4g/BW4i claims' {
        $script:matrix | Should -Not -Match 'Write-OPAOperationJournal'
        $script:matrix | Should -Not -Match 'Write-OPA265BW4gOneShotClaim'
        $script:matrix | Should -Not -Match 'Write-OPA265BW4iDecisionOnce'
    }
}
