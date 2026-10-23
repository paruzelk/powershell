# OutlookPOP3Archive — Durable Operation Journal (2.6.2 diagnostic baseline)

**Status:** 2.6.2-preview1 published as a diagnostic preview; 2.6.3 adds a separate read-only MailMove evaluator. The feature branch now includes the exact 2.6.1-PREVIEW1a source tree published to `develop` on 2026-10-22. **Do not merge this feature into `main` or deploy to Outlook until the 2.6.2 integration and Windows CI/fault-injection tests pass.**

## Objective

Prevent automatic repeat of Outlook `Move()` after process termination, power loss, or a checkpoint/journal gap. A crash can occur **after** PST changed but **before** the transaction checkpoint was written. A completed operation must be established from durable evidence, not just a missing source item or an absence of a checkpoint record.

## Required protocol (planned MailMover integration)

1. Assign stable `OperationId` and `Sequence` for a planned source item, and persist an `Intent` with source EntryId, planned target PST, and transaction ID; return **only after durable flush**.
2. Call Outlook `Move()` **once**. If COM throws, do not assume nothing changed. Classify as ambiguous until independently checked.
3. Persist `Completed` with the actual archive EntryId and flush before treating the move as committed. Continue using the existing checkpoint/duplicate-index mechanisms.
4. During restart, replay the new operation journal **before** selecting or moving any messages. A surviving `Intent` without a `Completed` record is **Indeterminate**. Stop automatic resume and new archival work until PST/source/duplicate-index evidence is reconciled.
5. Once reconciliation conclusively verifies a destination copy, emit `Reconciled` (with actual archive EntryId). If reconciliation cannot distinguish moved vs not moved, retain `Indeterminate`; **never blindly call `Move()` a second time**.
6. The journal and existing 2.5.x/2.6.1 step journal are separate. Do not implicitly convert legacy `.steps.jsonl` into verified operation completions.

## File format / failure policy

- `<TransactionId>.operations.jsonl`; each newline-delimited envelope stores `Payload` (Base64 of UTF-8 JSON) and SHA-256 of exactly those bytes.
- Single-writer append with `FileStream.Flush(true)`; no full-journal rewrite per message.
- Reader verifies every **complete** line, event schema and monotonic sequence. A corrupted complete line, duplicate terminal event, mixed transaction IDs or missing Intent raises an error (fail closed).
- A partial **unterminated** final line is preserved and surfaced as `TrailingPartial`. A writer refuses to append until the tail has been examined. Neither corrupted nor indeterminate records may be silently trimmed or deleted by auto cleanup.
- The journal is used by an opt-in **diagnostic-only** dispatcher `Core/Worker/WorkerOperationJournal.ps1`; production Archive/Resume/Auto and MailMover do not call it.

## Acceptance before integration / release

- Verify compatibility with Windows PowerShell 5.1, Pester and PSScriptAnalyzer.
- Fault injection: terminate between Intent, COM Move, completion and checkpoint; retry startup must never duplicate a moved email.
- Corruption and tail truncation tests; journal remains an audit record.
- Cover multiple POP3 accounts/profiles and archive PST rotation by year; IMAP accounts excluded.
- Confirm compatibility with `DurabilityMode`, `DuplicateIndex`, transaction schema and 2.6.1 worker-control flow.
- Follow existing project release discipline: validated source and tests, full CI, then promotion to stable `main` and a version tag. Do not label this development branch a release.

## 2.6.2 implementation: correlated diagnostic worker journal

- `Core/Worker/WorkerProtocol.ps1`, `WorkerHost.ps1`, and `WorkerControl.ps1` now optionally accept a **caller-generated GUID RequestId**, retaining the existing default behavior for older callers.
- `Invoke-OPAWorkerJournaledOperation` obtains an exclusive file handle for `<journal>.lock`, replays the current journal and fails closed on corruption, unresolved or failed operations.
- Before launching the worker, it writes a durable `Intent` with `OperationKind=WorkerDiagnostic`, `OperationId=RequestId` and a strictly advancing `Sequence`. Only then does it invoke the existing bounded STA worker using that same RequestId.
- A validated outcome produces `WorkerSucceeded`, `WorkerFailed`, or `Indeterminate`; each record is SHA-256 verified and `FileStream.Flush(true)` completes before reporting journal commit.
- If the worker returns but terminal recording fails, the controller reports `Indeterminate` even if the in-memory worker result says `Succeeded`; the incomplete Intent remains as evidence. A mismatch between the intended RequestId and the worker result is also `Indeterminate`.
- Subsequent automatic dispatch is refused for `Indeterminate`, `WorkerFailed`, any truncated journal or mismatched transaction. Diagnostic success can continue to the next sequence.
- `WorkerSucceeded` is never interpreted as proof of a moved mail item. `OperationKind=MailMove` requires the actual destination `ArchiveEntryId` in a `Completed` or independently verified `Reconciled` record. Only manual reconciliation may follow an explicit `Indeterminate`.
- This implementation leaves worker `MailItem.Move` forbidden. Actual Outlook COM reconciliation and Auto/Resume/MailMover integration belong to later roadmap gates (2.6.3/2.6.4).

### Diagnostic example

```powershell
. .\Core\Worker\WorkerOperationJournal.ps1
$journal = Get-OPAWorkerOperationJournalPath -TransactionDirectory 'C:\OPA-Test' -TransactionId 'diag-20261022-01'
$result = Invoke-OPAWorkerJournaledOperation -JournalPath $journal -TransactionId 'diag-20261022-01' -Operation Ping -TimeoutSeconds 15
$result | Format-List
Get-OPAWorkerOperationJournalState -JournalPath $journal | Format-List
```

**Test gate:** Pester scenarios cover pre-dispatch Intent, exact RequestId, success/failure/timeout outcomes, orphaned Intent after simulated kill, torn final line, cross-transaction reuse and concurrent writer. Tests are committed but Windows PowerShell 5.1 CI must still run before this preview is considered verified.
