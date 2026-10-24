# Configuration — 2.6.2-PREVIEW1

Use `-Mode Analyze` for account discovery and `-Mode Plan` to inspect selected POP3 folders before moving mail. `-ProfileName 'Outlook'` selects a profile. `-OlderThanMonths 12` is the default; zero requires `-IgnoreAge`. POP3 Sent Items and nested folders are included. `-ArchiveDeletedItems`, `-ArchiveDrafts`, `-ArchiveJunk` are explicit opt-ins; Outbox remains excluded.

Capacity defaults: `-MaxArchivePstSizeGB 10`, `-SafetyMarginGB 0.5`. Automatic policy defaults: `SourceHigh 40 GB`, `Target 35 GB`. Worker timeout for diagnostic calls: `-TimeoutSeconds 15` (1–300 in API). `Invoke-OPAWorkerSelfTest.ps1` accepts 1–120 seconds. Check `Get-Help .\OutlookPOP3Archive.ps1` or the main script parameters for exact CLI flags.

For tests, import `Core/Worker/WorkerProtocol.ps1`, `WorkerHost.ps1`, then `WorkerControl.ps1`; call `Invoke-OPAWorkerControlledOperation`. This API allows only approved non-mutating/synthetic operations. `KeepArtifacts` is opt-in and should be cleaned up after debugging.

### 2.6.2 opt-in diagnostics

For durable *diagnostic* operations, dot-source `Core/Worker/WorkerOperationJournal.ps1` and use `Get-OPAWorkerOperationJournalPath`, `Invoke-OPAWorkerJournaledOperation`, and `Get-OPAWorkerOperationJournalState`. Use a dedicated diagnostic transaction directory, not a production transaction journal. This API never delegates `MailItem.Move()`. The three Worker flags in `RELEASE.json` remain disabled.
