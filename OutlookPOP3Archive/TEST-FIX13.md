# OutlookPOP3Archive FIX13b — testing instructions

## Overview
FIX13 adds Auto progress bookkeeping based on independently verified moved messages and treats Compact only as a recommendation. Neither `Invoke-CI.ps1` nor `Plan` or `Auto -WhatIf` moves messages or performs Compact.

**Windows PowerShell 5.1 / Outlook 2019**, on the test machine:

```powershell
.\Invoke-CI.ps1
```

Expected **151 Passed, 0 Failed** (142 from FIX13a plus 9 new FIX13b Int64 regression tests). The Pester suite itself can operate without Outlook. Some tests intentionally print fallback-sort warnings; those are not CI failures.

## Read-only integration checks

```powershell
.\OutlookPOP3Archive.ps1 -Mode Plan -ProfileName 'Outlook' -Limit 50
.\OutlookPOP3Archive.ps1 -Mode Auto -ProfileName 'Outlook' -WhatIf
```

Current test PST is only ~7 GB with High=40 GB; expected `NoAction`, and **no new `.auto-storage.state` file**. Run no mutating Auto or Compact to force the feature. Auto guard scenarios are simulated in Pester with sparse files under TestDrive.

## Decision logic

- `ArchiveRequired`: physical PST > HighWatermark and remaining target is positive.
- `CompactRequired`: physical PST > HighWatermark and verified Auto logical removal has matched the measured gap to Target; no new Auto batch.
- `AutoPaused`: physical PST > HighWatermark and the configured number of consecutive completed Auto batches has transferred zero logical bytes.
- `NoAction`: physical PST at/below HighWatermark.

A verified completed Auto batch (also when completed by a later manual Resume) updates `<source PST basename>.auto-storage.state` using atomic file replacement **before** persisting the transaction's `Completed` status. A crash in this window causes Auto Resume, not an untracked new batch. The same transaction ID is not credited twice.

## Remaining limitations

- Real Outlook tests for complex nested folder structures and Sent Items remain deferred until a suitable test PST is available.
- Real in-use PST size changes and Compact effectiveness are not tested here.
- Outlook COM `MailItem.Move()` can block indefinitely; worker-process isolation is planned for 2.6.x.
- The progress sidecar is not a prediction of exact Compact reclaimable space. Do not automatically compact PST files.
- Very old completed checkpoints may be removed by the configured Completed-only retention policy; the ledger is retained separately. Preserve it with backups.

## FIX13a correction

In FIX13 the `reports physical shrink separately from logical bytes moved` test expected 2 MB unmatched even though the test supplies 2 MB logically freed and 1 MB physically reclaimed. The intended value is **1 MB**, computed by `max(0, LogicalFreedBytes - PhysicalReductionBytes)`. The production implementation was correct; the FIX13a change corrects the test and adds zero-shrink and over-shrink regression cases. The measure is a diagnostic approximation, not a guaranteed Compact recovery forecast.

## FIX13b Windows PowerShell 5.1 Int64 overload regression

FIX13a raised `Math.Max` Int32 binding error during `Plan` for a 7.03 GB source PST versus a 35 GB target. FIX13b uses the explicitly typed Int64 `Math.Max([int64]0, [int64]difference)` overload for byte arithmetic in storage policy, reclaim estimates and archive telemetry/capacity diagnostics.

Run these commands from the extracted FIX13b root **before any real Archive**:

```powershell
.\Invoke-CI.ps1
.\OutlookPOP3Archive.ps1 -Mode Plan -ProfileName 'Outlook' -Limit 50
.\OutlookPOP3Archive.ps1 -Mode Auto -ProfileName 'Outlook' -WhatIf
```

Expected: 151 tests and zero failures; Plan/Auto must report `NoAction` for the 7.03 GB source with High=40 GB and Target=35 GB. These commands do not move mail. On failure, preserve the full console output and do not launch Archive.
