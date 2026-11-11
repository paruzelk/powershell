# Recovery and ambiguous worker outcomes — 2.6.3-PREVIEW1

## ARCH2a runtime no-blind-retry fence (2026-11-11)

The previous legacy `MoveFailed` catch/continue has been replaced with `Move Indeterminate` + immediate throw after durable `Move Started`. Before actual COM the step journal and checkpoint are saved and explicitly flushed to disk. A future Resume must scan the **full original step journal** and reject missing/unterminated journal, a missing original plan, repeated `Move Started` or any attempt without a closing `Move Completed`. A visible source message is **not** sufficient to retry. This is a safety improvement, not a finished autonomous reconciliation protocol. Current DEV CLI Archive/Resume/Auto are blocked at entrypoint. See [ARCH2a runbook](2.6.5-arch2a-move-outcome-fence.md).

## ARCH1 unresolved Move safety reminder (2026-11-11)

The main `Core/Archive/MailMover.ps1` currently has a `MoveFailed` handler that records skipped/continues after COM `MailItem.Move()` failure. An exception or timeout can leave move outcome ambiguous: **do not classify it as a harmless retryable skip**. ARCH2 must integrate write-once intent/claim, fail-closed reconciliation and complete content/attachment witnesses with the normal Archive/Resume path. The existing diagnostic Worker switches set to false are **not** a safety switch for direct legacy CLI. Do not run on 90GB data until this gap is closed. [Project handoff](PROJECT-HANDOFF-ARCH1.md), [ADR](ADR-ARCH1-OUTLOOK-COM-BOUNDARY.md).


`Indeterminate` **never** means that an operation did not execute. It means the controller could not validate a complete response. A timeout can occur after a COM side effect but before the child writes its JSON response.

Worker 2.6.2 **does not implement MailItem.Move**, so it cannot autonomously modify PSTs and then reconcile them. For future worker-driven Move, the sequence must be: durable Move Started intent, bounded operation, durable Move Completed when proved, and after any unknown outcome independent comparison of source and archive item identities before retrying.

Until this future integration exists, archive and resume continue using FIX13b checkpoint/journal semantics. Do not erase `.steps.jsonl`, `.json`, DuplicateIndex or `.auto-storage.state` to force a restart. Preserve a backup and investigate any `VerificationFailed` or orphan journal.

`-KeepArtifacts` on `Invoke-OPAWorkerControlledOperation` retains diagnostic `request.json`/`response.json` in a temporary per-run folder. These files are **not durable recovery evidence** and can be removed by system cleanup. Do not rely on them for transactional recovery.

### Separate diagnostic operation journal (2.6.2)

`<TransactionId>.operations.jsonl` contains a durable `Intent`, then a validated diagnostic Worker outcome. When replay sees an incomplete `Intent`, a committed `Indeterminate` or an unterminated tail, automatic retry is refused. The source journal must be preserved without trimming. An unresolved `WorkerDiagnostic` alone does not require reading a PST, but a torn tail may conceal a MailMove intent and conservatively returns `RequiresPstReconciliation=True`. A successful diagnostic operation may advance its sequence after a new PowerShell process starts; no real Outlook Move is driven by this journal in 2.6.2.

### 2.6.3 safety policy

Use `Resolve-OPAInterruptedMoveEvidence` only for manual review of an unresolved MailMove Intent with persisted StoreID, source/target paths, archive PST and a complete message fingerprint. A unique destination match is a candidate, not proof of move completion. Never append Reconciled automatically.

### SEM-001 recovery and metadata-only size drift (normative 2026-11-02)

Do **not** retry Outlook `MailItem.Move()` after a persisted attempt claim, a timeout, crash or ambiguous response. Reconcile read-only with original immutable message witness and exact source/target PST scope. Conclusive successful completion requires one archive item, zero original items and preserved significant content + **attachment byte SHA-256**, not equality of `MailItem.Size` or all MAPI properties. Different EntryID/RecordKey or a logged size delta do not authorize a writer; changed/missing required content, missing recipients or unknown semantic flags keep the operation indeterminate. Do not erase claims or rebaseline original evidence to bypass drift. Record logical completion and physical PST compact/durability separately. See [SEM-001](SEMANTIC-INTEGRITY-POLICY.md).
