# OutlookPOP3Archive — RC1.2 / BUILD 2.5.7

Application: `0.9.3-rc1-build2.5.7-FIX13b`  
Transaction schema: `2.5.4`  
Target: Windows PowerShell 5.1 + Outlook 2016/2019 (Office 16.x)

## FIX13b — Auto Storage Progress and Compact assessment

The source PST's **physical file length usually does not decrease** after an Outlook `MailItem.Move`, even when Outlook has logically freed content. FIX13b stops using the unchanged PST length as the sole signal to repeatedly archive more mail.

- Auto writes one per-source `OutlookPOP3Archive-Transactions/<source-name>.auto-storage.state` file, recording only completed **independently verified** Auto moves; the archive checkpoint cleanup never deletes it. This file must be backed up together with the transaction data.
- Each later Auto run subtracts credited logical bytes from the current physical gap between PST size and configured Target. Once credited logical bytes meet this goal but the PST still exceeds HighWatermark, it reports **`CompactRequired`** and does not start another archive.
- After `-AutoMaxEmptyBatches 2` (default) consecutive completed batches with no logical bytes transferred, Auto returns **`AutoPaused`**; investigate eligible-mail selection before any further Auto activity.
- A real observed PST file shrink greater than 1 MiB resets the accounting epoch. Reads made by `Plan` and `Auto -WhatIf` do **not** write or delete state.
- A damaged `.auto-storage.state` file stops the decision safely. Never delete/rename the state blindly as a way to unpause Auto. Inspect transaction history, source and archive PSTs first.
- FIX13b **never performs Compact**, calls no Outlook compaction COM methods, and does not promise a specific reclaimed byte amount. Use the regular backed-up PST maintenance procedure outside the script only after independent verification.
- `-DisableStoragePolicy` bypasses the Auto high-watermark and progress guard by deliberate administrator choice. Avoid it for unattended scheduling.

## Purpose

OutlookPOP3Archive archives old messages from POP3 Outlook PST stores into capacity-managed archive PST files. IMAP stores are excluded. Multiple Outlook profiles are supported.

## BUILD 2.5.7

This build is a cleanup/reliability release following the 2.5.5 durability validation.

### Fixed

- Fixed Resume/Archive finalization failure when `Transaction.State.Performance` did not exist on a loaded transaction.
- `Performance` is now initialized for new transactions and updated through the dictionary API for Windows PowerShell 5.1 compatibility.
- Fixed the `HashSet[string]` `SkippedEntryIds` conversion path so it uses safe PowerShell 5.1 enumeration instead of `.ToArray()`.
- Preserved `DurabilityMode` (`Fast` / `Safe`) and stored-mode restoration on Resume.

### Reliability

- FIX10 adds post-Move capacity rollover, permanent Outbox exclusion, Junk opt-in, correct DASL filters and Auto retry quarantine.
- FIX9 verification checks the actual source and archive folders through Outlook COM; journal/index entries alone cannot establish `Verified=True`.
- Logical freed bytes are reconstructed from unique completed items after Resume, including interrupted transfers that were reconciled from the archive.
- Independent verification can be slower on large PST files; it deliberately fails closed when folders cannot be read or a message cannot be uniquely identified.

- Append-only transaction step journal (`*.steps.jsonl`).
- Safe mode force-flushes each journal append, minimizing the window of journal loss on OS/process failure.
- Fast mode keeps the performance-oriented flush strategy.
- Resume reconciles transaction steps with DuplicateIndex.
- Skipped EntryIDs are retained for recovery; the detailed skipped-item report remains bounded.

### Archive policy

- POP3 only; IMAP is never archived.
- Age-based selection is the primary archive criterion.
- Deleted Items, Drafts, and Junk are disabled by default; Outbox is always excluded.
- `-ArchiveJunk` is required to include Junk in the source folder pool.
- `OlderThanMonths=0` requires explicit `-IgnoreAge` for Archive/Plan/Auto.
- Auto Resume attempts are limited by `-AutoMaxResumeAttempts` (default: 3). A blocked Auto never discards checkpoints or starts a replacement Archive; manual Resume is available.
- Archive PST capacity is controlled by maximum size and safety margin.
- Archive naming uses `Archive-YYYY.pst`, then `-02`, `-03`, etc.

### Performance

- Journal and checkpoint writes are batched where the durability mode permits.
- DuplicateIndex uses a HashSet for source-ID lookups.
- Archive display-name operations are cached.
- PST physical size remains the capacity source of truth; logical `Item.Size` is telemetry only.

## Usage

Analyze the selected Outlook profile:

```powershell
.\OutlookPOP3Archive.ps1 -Mode Analyze -ProfileName "Outlook"
```

Archive with the default Fast durability mode:

```powershell
.\OutlookPOP3Archive.ps1 -Mode Archive -ProfileName "Outlook" -Limit 500
```

Archive with Safe durability:

```powershell
.\OutlookPOP3Archive.ps1 -Mode Archive -ProfileName "Outlook" -Limit 500 -DurabilityMode Safe
```

Resume a specific interrupted transaction:

```powershell
.\OutlookPOP3Archive.ps1 -Mode Resume -ProfileName "Outlook" -Transaction "<TransactionId>"
```

## Validation

Run `Invoke-CI.ps1` on Windows PowerShell 5.1 with Pester and PSScriptAnalyzer installed. The CI checks include PowerShell parser errors, the PS 5.1 `ConvertTo-Json -InputObject` rule, generic collection safety checks, PSScriptAnalyzer, and Pester tests.

## Known limitation

A COM `MailItem.Move()` that hangs indefinitely cannot be interrupted by `try/catch`. True hard timeout/isolation remains planned for the 2.6 worker-process design.

## Project hygiene

The release package contains production source, tests, CI configuration and release documentation only. Backup files (`*.bak`, `*.backup`, `*.old`), ad-hoc patch scripts, test result dumps, temporary files and previous release packages are not part of the project.


## 2.5.7 — Reliability Hardening

This build strengthens recovery without replacing the 2.5.6 archive architecture.

### Transaction durability
- Every Move has `Move Started` intent and `Move Completed` confirmation.
- Resume treats only completed Move records (or legacy `Move n/n`) as completed.
- A DuplicateIndex write failure after Outlook has already moved the message is fatal for the current batch; the primary step journal is synchronized before the error is propagated.

### Capacity
- Physical archive PST size remains the final authority.
- After every successful Move, actual physical size is compared with the safe capacity.
- If the heuristic underestimated growth, the current Move is retained and the transaction records `Capacity Rollover Required`; the next item is forced onto a new archive part.

### Auto / diagnostics
- `-AutoTargetMinimum` controls the minimum target-driven batch size and defaults to 50.
- Average message size is calculated only from `Completed` transactions.
- Selection errors retain up to 20 concrete examples.
- FIX11 and later preserve orphan `*.steps.jsonl` files when their checkpoint is missing; Auto blocks until the orphan journal is investigated.
- `-Transaction` without `-Mode Resume` is rejected.

### Known limitation
`MailItem.Move()` is an Outlook COM call and can still hang indefinitely. True timeout/isolation is deliberately deferred to the 2.6.x worker-process design.

FIX9a corrected the independent verifier test dependency on Test-OPAStateHasKey; FIX10 changes archive policy and Auto safety. Refer to TEST-FIX10.md.

FIX10a: fixed UTF-8 BOM for PS5.1 regression test; unified full-depth POP3 folder traversal for Plan/Archive/Resume. Default Sent Items and its nested mail folders are included; sent-like messages prefer SentOn. Outbox and descendants are never archived; Deleted Items, Drafts and Junk subtrees remain excluded unless their opt-in flags are set. Folder scanning errors are fatal instead of silently omitting subfolders.

## FIX11 — Auto safety and transparent age diagnostics

- Auto now blocks new archives when unsupported checkpoints, orphan step journals, or multiple unfinished transactions are present; manual investigation is required.
- Automatic retention removes **only Completed** checkpoints, and respects Auto `-WhatIf`. Failed/unsupported/unknown transaction states and orphan step journals are retained.
- Optimized Plan selection reports `Excluded by age: not fully counted` rather than a misleading zero when Restrict/Sort did not examine the whole folder.
- Resume and POP3 folder traversal behavior remain unchanged from FIX10a.

## FIX12a — archive capacity edge cases and behavioral tests

- Behavioral Pester tests exercise actual `Get-OPAArchiveDestination` with real temporary PST-sized files and mocked Outlook COM operations: initial part, reuse, rollover to `-02` and `-03`, reused part after Resume, different years, part `-100`, and missing registered files.
- A new part is not created if even the default projected physical growth cannot fit under the safe capacity; after PST initialization, the file size is checked again before allowing Move.
- Registered archive PST parts missing from disk cause a fail-closed error instead of silently creating an empty replacement.
- Post-Move physical size is classified as `WithinSafe`, `RolloverNext`, or `HardLimitExceeded`. Beyond the hard maximum, the completed Move is recorded, the transaction is flagged VerificationFailed (so Auto will not retry it), then the batch stops with an explicit error; no automatic rollback of the already moved item occurs.
- These checks do **not** mathematically guarantee a PST will never exceed its maximum: Outlook may commit physical size changes asynchronously. A safety margin and post-Move checks reduce risk.
- No change to the FIX9a independent verification or the FIX8b Resume transaction model.
