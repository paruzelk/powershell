# OutlookPOP3Archive — 2.6.3-PREVIEW1

Application: `0.9.4-rc1-build2.6.3-PREVIEW1`. Target: Windows PowerShell 5.1, Outlook 2016/2019.

**Status:** 2.6.3-PREVIEW1 development candidate: read-only interrupted Move reconciliation; CI pending. Production `Archive`, `Resume`, `Plan` and `Auto` still use the existing FIX13b Outlook COM code. Mail movement is **not delegated** to a worker. Keep FIX13b as the tested archiving baseline.

## Purpose and safety rules

- Archive old messages from **POP3** PST stores only; IMAP accounts are never archived.
- `Sent Items` and recursively nested user mail folders are included; Sent-like folders use `SentOn` when available. Deleted, Drafts, Junk subtrees are excluded by default; **Outbox is always excluded**.
- Selection defaults to 12 months; `-OlderThanMonths 0` requires `-IgnoreAge` for Plan/Archive/Auto.
- Archive PSTs rotate by year and part (`Archive-YYYY.pst`, `Archive-YYYY-02.pst`, etc.) with `MaxArchivePstSizeGB` and `SafetyMarginGB`.
- Every move is journaled; Resume uses the persisted plan and independent Outlook COM verification to avoid unverified duplicate moves. Safe mode strengthens journal flush durability.
- Auto uses high/target watermark plus a durable, per-source verified logical-progress ledger (`*.auto-storage.state`). Compact is **advisory only**, never executed automatically.
- Never delete transaction checkpoints, step journals, duplicate indexes or Auto progress state to clear an error.

## Common commands

```powershell
.\Invoke-CI.ps1
.\OutlookPOP3Archive.ps1 -Mode Analyze -ProfileName 'Outlook'
.\OutlookPOP3Archive.ps1 -Mode Plan -ProfileName 'Outlook' -Limit 50
.\OutlookPOP3Archive.ps1 -Mode Auto -ProfileName 'Outlook' -WhatIf
.\OutlookPOP3Archive.ps1 -Mode Archive -ProfileName 'Outlook' -Limit 50 -DurabilityMode Safe
.\OutlookPOP3Archive.ps1 -Mode Resume -ProfileName 'Outlook' -Transaction '<TransactionId>'
```

## Worker 2.6.3 (diagnostic only)

```powershell
.\Invoke-OPAWorkerSelfTest.ps1
.\Invoke-OPAWorkerSelfTest.ps1 -IncludeOutlookProbe -TimeoutSeconds 30
```

`Invoke-OPAWorkerControlledOperation` provides an outcome with `Status` (`Succeeded`, `Failed` or `Indeterminate`), `FailureKind`, `WorkerProcessId`, `RequestId`, deadline and duration. Timeout, crash and invalid response are **Indeterminate** and always require reconciliation before any future mutation retry. It never automatically retries; worker operations remain `Ping`, `Echo`, `Fail`, `Crash`, `Delay`, and opt-in read-only `ProbeOutlook`.

**Important:** A worker kill cannot prove a COM side effect did not finish. A future worker-driven `MailItem.Move` needs durable intent, independent source/destination reconciliation, and explicit safety gates before production use. Outlook.exe is not killed by this worker host.

See `docs/TESTING.md`, `docs/ARCHITECTURE.md`, `docs/RECOVERY.md`, `docs/CONFIGURATION.md`, `docs/OPERATION-JOURNAL.md` and `docs/RELEASING.md`.

## 2.6.2 Durable Operation Journal preview

An optional diagnostic-only API `Core/Worker/WorkerOperationJournal.ps1` writes a flushed `Intent` before dispatching the STA Worker and a second durable event after a confirmed outcome. Replay refuses automatic retry after an indeterminate worker result, missing completion, corrupted journal or truncated tail. It does not route real mail moves, and a worker success is not evidence that `MailItem.Move()` occurred.

Before publishing a release package, Windows PowerShell 5.1 must pass `Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'` including PSScriptAnalyzer/Pester. Produce only the OutlookPOP3Archive project ZIP using `New-OPABuildPackage.ps1` after that check; `docs/RELEASING.md` contains the checklist.

## 2.6.3 read-only interrupted Move evidence

`Core/Archive/MoveReconciliation.ps1` scans caller-selected, already mounted POP3 source and destination folders, verifies identities against the durable MailMove Intent, and classifies source-only, destination candidate, both present, missing, ambiguous and incomplete states. Even a unique destination fingerprint is **not proof** of a completed Move. The API never moves mail, writes journal completion, or enables automatic retry; it is not wired into the existing FIX13b production Resume/Auto path. See `docs/2.6.3-interrupted-move.md`.
