# Architecture — 2.6.3-PREVIEW1

## 2026-11-11 ARCH2a fail-closed main Move and Resume enforcement

[ARCH2a runbook](2.6.5-arch2a-move-outcome-fence.md). Legacy main `MailMover.ps1` no longer continues after a claimed COM `MailItem.Move()` failure; `Move Started` is persisted and force-flushed before COM, `Move Indeterminate` stops the batch, and resumed work rejects any incomplete full original step journal. `OutlookPOP3Archive.ps1` closes `Archive`, `Resume`, `Auto` before Outlook initialization. The existing `ArchiveVerifier.ps1` still does **not** have complete BW4k Body/HTML/byte-SHA attachment integration, so production writer and 90GB use stay blocked. See roadmap ARCH2b.

## 2026-11-11 ARCH1 delivery-first decision

The current archive runtime is **NOT** the newly tested BW4k one-shot worker. `OutlookPOP3Archive.ps1` directly dispatches existing `Core/Archive/MailMover.ps1`. Old `MailItem.Move()` catches a COM error as `MoveFailed` and continues; the present `ArchiveVerifier.ps1` lacks complete Body/HTMLBody/attachment byte-SHA witness integration. `RELEASE.Integration.*WorkerEnabled=false` does **NOT** disable this legacy direct Archive CLI. Production is not certified.

[Binding ADR: Outlook COM boundary](ADR-ARCH1-OUTLOOK-COM-BOUNDARY.md); [handoff](PROJECT-HANDOFF-ARCH1.md); [roadmap](DELIVERY-ROADMAP.md); [source audit](ARCH1-IMPLEMENTATION-AUDIT.md). No more MAPI-size or flags-only BW branches; provider behavior recorded, actual user data and recovery safety are the acceptance criteria. Next substantive work: ARCH2 main mover/semantic verifier/recovery integration, then Year, folders, Resume and RC.



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

## SEM-001 — Logical-mail semantic integrity contract (normative since 2026-11-02)

Archive Outlook **MailItem objects** through supported Outlook COM/MAPI semantics; do not demand that physical PST bytes, all MAPI properties or `MailItem.Size` / `PR_MESSAGE_SIZE` stay identical across stores. This is **not** a global size-drift waiver: changes alone prove neither loss nor integrity. Independent read-only reconciliation must verify correct source/target store and folder, source-zero/target-one, immutable content identity, sender/recipients including POP3 Sent Items, timestamps, plain/HTML bodies, message class and each attachment's exact byte-count/SHA-256, transport headers and defined user-visible status bits. Cross-store EntryID and RecordKey can differ; PR_MESSAGE_FLAGS requires a pinned semantic bit mask; unavailable mandatory evidence fails closed. The existing BW4j synthetic witness does **not** cover production-grade recipient/flag completeness.

The future Worker must durably persist Intent/claim, attempt exactly one Move, independently read and reconcile, then commit only on conclusive evidence. Indeterminate Move, crash or mismatch **never** triggers automatic retry. Annual PST rollover/capacity and physical Compact are separate responsibilities. The BW4k7a 8122->8634 +512-byte **source-side** drift remains unapproved, despite identical 1024-byte attachment SHA and all other witness fields. New BW4k7b policy code is **read-only / diagnostic** with no writer permit.

See [normative semantic integrity policy](SEMANTIC-INTEGRITY-POLICY.md) and [technical specification](TECHNICAL_SPECIFICATION.md).
