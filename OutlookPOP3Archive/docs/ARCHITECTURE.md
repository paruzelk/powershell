# Architecture — 2.6.1-PREVIEW1a

The main `OutlookPOP3Archive.ps1` still invokes the FIX13b in-process Outlook COM archiver and normal transaction pipeline. `Core/Archive/MailMover.ps1`, `ArchiveTransaction.ps1` and `StoragePolicy.ps1` are unchanged from 2.6.0-PREVIEW1a.

The separate diagnostic boundary consists of `WorkerProtocol.ps1` (JSON 1.0 request/response, GUID, allowlist), `WorkerHost.ps1` (spawns Windows PowerShell 5.1 STA, bounds runtime, checks PID/exit status), `WorkerControl.ps1` (3-state outcomes and recovery disposition) and `OutlookPOP3Archive.Worker.ps1` (read-only opt-in Outlook probe plus synthetic operations).

Statuses:

- `Succeeded`: validated successful worker response and process exit 0.
- `Failed`: validated structured worker error response, or host failed before worker launched.
- `Indeterminate`: worker started, but timed out, crashed, produced invalid/missing response or failed protocol/process correlation.

Any indeterminate outcome requires **independent reconciliation**. This does not yet constitute a durable mutating COM transaction journal; it must be added and tested before worker-driven Move.

The worker is a process-isolation boundary only, not a security sandbox. No arbitrary code execution endpoints are provided.
