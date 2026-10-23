# Architecture — 2.6.3-PREVIEW1

The main `OutlookPOP3Archive.ps1` still invokes the FIX13b in-process Outlook COM archiver and normal transaction pipeline. `Core/Archive/MailMover.ps1`, `ArchiveTransaction.ps1` and `StoragePolicy.ps1` are unchanged from 2.6.0-PREVIEW1a.

The separate diagnostic boundary consists of `WorkerProtocol.ps1` (JSON 1.0 request/response, GUID, allowlist), `WorkerHost.ps1` (spawns Windows PowerShell 5.1 STA, bounds runtime, checks PID/exit status), `WorkerControl.ps1` (3-state outcomes and recovery disposition) and `OutlookPOP3Archive.Worker.ps1` (read-only opt-in Outlook probe plus synthetic operations).

Statuses:

- `Succeeded`: validated successful worker response and process exit 0.
- `Failed`: validated structured worker error response, or host failed before worker launched.
- `Indeterminate`: worker started, but timed out, crashed, produced invalid/missing response or failed protocol/process correlation.

An indeterminate diagnostic outcome blocks automatic retry; a durable `Intent` and terminal event are now recorded by `Core/Worker/WorkerOperationJournal.ps1`. This **still is not a journal integrated into mutating Outlook COM operations**, so independently verified `MailItem.Move()` reconciliation must be implemented and tested before worker-driven archiving.

The worker is a process-isolation boundary only, not a security sandbox. No arbitrary code execution endpoints are provided.

## 2.6.2 isolated operation journal

`Core/Archive/OperationJournal.ps1` appends Base64-encoded SHA-256-protected JSONL events, calls `FileStream.Flush(true)`, and refuses to overwrite or trim broken records. The diagnostic controller holds an exclusive `.lock` file handle, persists `Intent` with transaction ID, sequence and caller-owned GUID, then executes the bounded worker and commits a validated outcome. Replay blocks retry on incomplete, corrupt, failed or unknown operations. `WorkerSucceeded` never means that mail has been moved. The separate existing archive transaction/step journal and DuplicateIndex remain in use on the in-process FIX13b path.

## Read-only 2.6.3 evidence review

`Core/Archive/MoveReconciliation.ps1` evaluates a verified MailMove Intent against complete source/destination folder snapshots. Incomplete scans, identity mismatches and fingerprint collisions block decisions. No status permits automatic retry or journal mutation.
