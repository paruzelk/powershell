# Testing — 2.6.3-PREVIEW1

Run from the OutlookPOP3Archive directory under Windows PowerShell 5.1 (Pester 5+ and PSScriptAnalyzer both installed).

```powershell
.\Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'
.\Invoke-OPAWorkerSelfTest.ps1
.\Invoke-OPAWorkerSelfTest.ps1 -IncludeOutlookProbe -TimeoutSeconds 30
Invoke-Pester -Path .\Tests\Worker\WorkerOperationJournal.Tests.ps1 -Output Detailed
.\OutlookPOP3Archive.ps1 -Mode Plan -ProfileName 'Outlook' -Limit 50
.\OutlookPOP3Archive.ps1 -Mode Auto -ProfileName 'Outlook' -WhatIf
```

Release CI must reject stale Core/Version, MANIFEST, RELEASE, README or active documentation headers, obsolete package files, parser/PS5.1 compatibility errors, analyzer findings, missing analyzers and failed/skipped Pester tests. For packaged ZIP generation see `docs/RELEASING.md` and `New-OPABuildPackage.ps1`. The standalone ZIP must contain only the OutlookPOP3Archive project and SHA-256.

### Already validated on preceding 2.6.2 dev snapshot

- Non-mutating Worker SelfTest: Ping, Echo, Fail, Delay, controlled result classification. Opt-in STA Outlook COM probe: 2 accounts and 4 stores; no mail moved.
- Durable diagnostic journal: `Intent → WorkerSucceeded` recorded and replayed; synthetic Worker Crash captured as `Indeterminate` and automatic retry blocked; truncated journal tail retained with append and dispatch blocked.
- Real restart of PowerShell: successful diagnostic replay and next monotonically numbered operation; indeterminate diagnostic replay still blocked.
- `Tests/Worker/WorkerOperationJournal.Tests.ps1`: 11 Passed, 0 Failed in Pester 6.2.0, including torn journal completion test.

The earlier snapshot does **not** certify new release-pipeline changes or this metadata-bumped preview. Run full CI again before publishing.

### Not covered yet

Real Worker-driven COM `MailItem.Move()`, production Archive/Resume integration, post-move PST reconciliation, OS power-loss under COM mutation and Outlook Compact are not yet verified. FIX13b remains the active mail-moving engine.

## 2.6.3 additional tests — run under Windows PowerShell 5.1

```powershell
Invoke-Pester -Path .\Tests\Archive\MoveReconciliation.Tests.ps1 -Output Detailed
.\Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'
```

No real Outlook MailItem.Move is exercised; validate read-only observation against disposable PSTs before proceeding.

### CI regression gate added after first 2.6.3 DEV run

The first local 2.6.3 CI run reported `229 passed, 0 failed` **but one failed test discovery container** due to duplicate case-insensitive `EntryID`/`EntryId` keys in a new Pester fixture. This was a CI **failure** and must never be described as a successful build. The test fixture has been corrected. The updated `Invoke-CI.ps1` rejects invalid test source during the parser pass and uses the full Pester result (`Result`, `FailedContainersCount`, `FailedBlocksCount`, `Containers`, `InconclusiveCount`, `NotRunCount`), not just `FailedCount`. `Tests/Core/PesterReleaseGate.Tests.ps1` regression-tests the false-positive. Re-run full CI before packaging. 

### Real Outlook COM integration (disposable PSTs only)

Use `Core/Diagnostics/Invoke-OPA263LivePstTest.ps1 -SeedPstPath '<absolute path to designated TEST PST>' -Execute` in Windows PowerShell 5.1 STA while Outlook is open. This creates two new temporary PSTs, clones one eligible message from the designated test PST, and simulates a missing journal completion after a real first Move. Preserve the temp journal and report for review; note that Outlook Copy temporarily modifies the donor test PST. Full CI before running:

```powershell
.\Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'
```
