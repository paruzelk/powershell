# Recovery and ambiguous worker outcomes — 2.6.1-PREVIEW1a

`Indeterminate` **never** means that an operation did not execute. It means the controller could not validate a complete response. A timeout can occur after a COM side effect but before the child writes its JSON response.

Worker 2.6.1 **does not implement MailItem.Move**, so it cannot autonomously modify PSTs and then reconcile them. For future worker-driven Move, the sequence must be: durable Move Started intent, bounded operation, durable Move Completed when proved, and after any unknown outcome independent comparison of source and archive item identities before retrying.

Until this future integration exists, archive and resume continue using FIX13b checkpoint/journal semantics. Do not erase `.steps.jsonl`, `.json`, DuplicateIndex or `.auto-storage.state` to force a restart. Preserve a backup and investigate any `VerificationFailed` or orphan journal.

`-KeepArtifacts` on `Invoke-OPAWorkerControlledOperation` retains diagnostic `request.json`/`response.json` in a temporary per-run folder. These files are **not durable recovery evidence** and can be removed by system cleanup. Do not rely on them for transactional recovery.
