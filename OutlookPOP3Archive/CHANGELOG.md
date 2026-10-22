## 2.6.3-PREVIEW1 (2026-10-22; DEV, Windows CI pending)

- Added independent read-only MailMove Intent reconciliation with source/target snapshots, fingerprint and store/path validation.
- All outcomes fail closed with no automatic retry or journal mutation; legacy/partial Intents are not treated as proof.
- Added Pester tests for false duplicates, missing messages, incomplete MAPI enumeration and mismatched identities.
- Removed obsolete version-prefixed 2.6.2 design filename from active package; content retained under docs/OPERATION-JOURNAL.md.
- Worker Move still disabled; FIX13b remains the production archive engine. Full PS5.1 CI required.

## 2.6.2-PREVIEW1 (2026-10-22; candidate pending full CI)

- Introduced append-only SHA-256 Durable Operation Journal for diagnostic Worker; controller-supplied RequestId, durable Intent and terminal outcome, exclusive journal lock and fail-closed replay.
- Independent PowerShell restart, Worker crash and truncated-tail fault injection tested successfully by the user on the preceding development snapshot; Pester worker journal suite 11 passed, 0 failed.
- Distinguished diagnostic-only unresolved events from potential PST reconciliation requirements; malformed journal tails conservatively require manual reconciliation.
- Hardened the release gate: Core/Version, RELEASE, MANIFEST, current docs and test version checks; mandatory Pester/PSScriptAnalyzer and reviewed source-only ZIP packaging with SHA-256.
- Updated dynamic Worker SelfTest version display; Transaction schema 2.5.4, DuplicateIndex schema 1.2 and Worker protocol 1.0 are unchanged.
- Production Archive/Resume/Auto and real MailItem.Move continue using FIX13b; 2.6.2 does not activate Worker COM mutations.
- Full Windows PowerShell 5.1 CI and packaging verification required before promotion.

## 2.6.1-PREVIEW1a (2026-10-22)

- Fixed the Windows PowerShell 5.1 CI manifest validator: version fields are now generated as four separate output lines rather than one concatenated array expression.
- Added a PS5.1-compatible shared manifest guard and seven behavioral Pester tests, including rejection of collapsed, missing, duplicate and stale metadata.
- Preserved worker, Archive, Resume and Auto implementations from PREVIEW1; packaging/version metadata updated only.

## 2.6.1-PREVIEW1 (2026-10-22)

- Added typed worker control results (`Succeeded`, `Failed`, `Indeterminate`) with deadlines, elapsed time, spawned PID, exit code and request correlation.
- Timeout, abrupt crash and invalid/missing response are fail-closed: no automatic retries, recovery disposition `ReconcileBeforeRetry`.
- Validated STA/timestamps and response process PID; added optional preserved diagnostic request artifacts.
- Release CI gate checks Core/Version.ps1, MANIFEST.txt, RELEASE.json, README.md and rejects obsolete release documents.
- Removed legacy root-level FIX test plans and duplicate build notes from release ZIP; active tests and transaction-related code retained.
- Existing Archive/Resume/Auto, transaction schema and DuplicateIndex schema remain unchanged; worker mail mutations still disabled.

## 2.6.0-PREVIEW1a — CI version-test correction (2026-10-22)

- Fixed `Tests/Core/Version.Tests.ps1` still expecting 0.9.3 after the 0.9.4 version bump.
- The format check is release-neutral and validates that the manifest matches the declared application version.
- Worker operations, Outlook Archive/Resume/Auto logic, transaction schemas, and worker protocol are unchanged.
- CI target remains 170 Pester tests (169 passed / 1 failed in PREVIEW1 before this correction).

## 2.6.0-PREVIEW1a (2026-10-22)

- Introduced a separate Windows PowerShell 5.1 STA worker executable path,
  versioned JSON request/response envelopes with GUID correlation, atomic
  staging, validated results and structured failures.
- Added explicit synthetic process self-test and opt-in read-only Outlook COM
  `ProbeOutlook`; no COM Move is delegated, and the legacy Archive/Resume/Auto
  behavior from FIX13b remains unchanged.
- Added host deadline and best-effort termination of the **spawned child only**;
  process crashes or timeouts do not silently count as success.
- Added 19 Pester tests; expected 170 total (previously 151).
- Deferred durable mutating-operation recovery, reconciliation and production
  routing to later 2.6.x phases.

## 2.5.7-FIX13b (2026-10-22)

- Fix Windows PowerShell 5.1 `Math.Max(0, <byte difference>)` overload resolution in `Get-OPAStoragePolicyDecision`. At a 7.03 GB source and 35 GB target the negative intermediate is ~-28 GB and previously caused an Int32 conversion error in Plan.
- Use explicit Int64 operands for physical-vs-target and cumulative logical progress, storage reclaim diagnostics, archive PST growth telemetry, and remaining destination capacity diagnostics.
- Add nine behavioral regression tests using mocked PST file sizes up to 45 GB; no real large file or Outlook needed. Protect low-PST NoAction, between-target/high NoAction, high-PST ArchiveRequired, CompactRequired, 64-bit reclaim telemetry, negative 64-bit archive growth and destination overcapacity.
- Expected CI suite: 151 Pester tests, 0 failures. Full CI must be run on Windows PowerShell 5.1; this packaging environment does not provide that runtime.

## 2.5.7-FIX13a (2026-10-22)

- Corrected the Pester expectation for `UnmatchedLogicalReductionBytes`: 2 MB logical freed less 1 MB observed physical PST shrink equals 1 MB still unmatched (the production formula was already correct).
- Added regression tests for shrink larger than logical reduction and no observed shrink; Compact remains assessment-only.
- Retains all FIX13 Auto progress, Resume and capacity controls, with no production logic changes.
- Expected Pester count: 142 tests (140 original + 2 boundary cases).

## 2.5.7-FIX13 (2026-10-21)

- Added durable, per-source `*.auto-storage.state` progress ledger, independent of the removable Completed checkpoints. Only independently verified Auto batches (including Auto Resume) are credited.
- Logical reduction is subtracted from the remaining objective on future Auto runs while the physical PST has not shrunk. Auto stops with `CompactRequired` once the logical target is reached instead of repeatedly moving more old mail because the PST file stays large.
- `AutoPaused` after two consecutive independently verified batches moving no logical bytes (`-AutoMaxEmptyBatches` changes this threshold).
- Safeguard ordering: the ledger is updated after verification but BEFORE saving the Completed checkpoint. A failed ledger write leaves the checkpoint pending for safe Resume; transaction IDs prevent re-credit on repeated verification.
- Physical shrink greater than 1 MiB resets the accounting epoch on the next successful Auto batch; Plan and WhatIf never modify this state.
- Corrupt/foreign progress sidecars fail closed. Manual Archive is unaffected; Auto decisions never touch IMAP sources.
- Archive Report separates logical moved bytes, observed physical size reduction, physical growth and a non-predictive Compact review indicator. Compact remains assessment-only and is never invoked.
- Added 23 Pester tests using sparse temporary PST files and simulated completed transactions. No live Outlook/PST needed for unit tests.
- FIX12a remains the latest integration-tested baseline until FIX13 passes Windows PowerShell 5.1 CI and non-mutating checks.

## 2.5.7-FIX12a (2026-10-21)

- Corrected duplicate `New-OPAArchivePst` invocation when selecting a brand-new first archive part. Reuse the same Outlook Store object for initialization and destination folder creation.
- Updated the legacy FIX10 capacity assertion to verify the FIX12 tri-state post-Move handling: `RolloverNext` continues while `HardLimitExceeded` marks `VerificationFailed` and throws.
- Regression coverage retained: first-part allocation must open the PST only once; existing-part reuse must also open it once.
- Fix addresses the two CI failures reported for FIX12 (115 passed, 2 failed); PS5.1/Pester execution of FIX12a is still required.

## 2.5.7-FIX12 (2026-10-21)

- Behavioral capacity tests with real temporary part files and mocked Outlook COM to verify choice of existing/archive parts, rollover to -02/-03, continuity across a simulated Resume and independence of archive years.
- Post-Move physical size classification: WithinSafe, RolloverNext, HardLimitExceeded. A detected hard-limit overrun stops the batch after journaling the successful Move and marks VerificationFailed; Auto refuses automatic retry. No claim of absolute prevention of asynchronous PST growth.
- Reject projected-oversized messages before creating the first archive PST part, and recheck measured size after PST initialization before Move.
- Fail closed when a transaction refers to an archive PST part that no longer exists on disk; never silently re-create it.
- Detect archive parts numbered 100+ correctly.
- Maintains FIX11 Auto, FIX10a folder policy, FIX9a verification and FIX8b Resume.

## 2.5.7-FIX11 (2026-10-21)

- Fail-closed Auto selection for unsupported/multiple unfinished checkpoints and orphan step journals.
- Conservative cleanup preserves all unresolved checkpoints and orphan journals. Auto -WhatIf no longer deletes old Completed checkpoints.
- Planner marks age-exclusion counts as incomplete when optimized scans terminate early.
- New behavior tests for Auto selection and cleanup; no changes to MailMover/Resume.

## 2.5.7-FIX10a — Sent mail and nested folder policy; PS5.1 encoding (2026-10-21)

- Fixed FIX10Safety.Tests.ps1 UTF-8 encoding for Windows PowerShell 5.1.
- Unified full-depth source folder enumeration across Plan, Archive and Resume, with fail-closed errors if nested enumeration is unavailable.
- Includes Sent Items and all eligible nested POP3 mail folders; preserves complete source folder hierarchy under Year/Quarter in target PST.
- Excludes the Outbox subtree unconditionally and excludes Deleted Items, Drafts and Junk subtrees by default (configurable except Outbox).
- Uses SentOn for Sent Items and descendants when resolving archive age, including when the default Sent folder is renamed.
- Adds FolderHierarchy.Tests.ps1 with nested Sent hierarchy, excluded subtrees, custom folder handling, SentOn selection and target path tests.
- Does not change transaction schema or FIX9a Resume/recovery algorithms.

## 2.5.7-FIX10 — Policy, Rollover & Auto Safety (2026-10-21)

- FIX9a is the verified regression baseline. Independent Outlook item verification and Resume reconciliation are retained.
- After a post-Move safe-capacity overrun, the candidate loop continues. The destination selector re-checks the physical PST and creates the next archive part when necessary. Size growth can still be asynchronous in Outlook; safe margin remains mandatory.
- Outbox is always excluded (even if a partial well-known ID map is present); Junk is excluded by default and can be included via `-ArchiveJunk`.
- Plan and Archive exclude non-mail Outlook folders using `DefaultItemType` when available.
- DASL date Restrict filters quote the property URI separately from the comparison and format UTC timestamps invariantly, and enforce the exact age cutoff in managed code.
- With no cutoff, candidate selection uses chronological Sort or scans the entire folder if sorting fails (instead of an arbitrary prefix).
- `-OlderThanMonths 0` now requires an explicit `-IgnoreAge` switch in Plan/Archive/Auto.
- Auto persists per-checkpoint retry counts in `.auto-retry` sidecars. After `-AutoMaxResumeAttempts` (default 3), Auto fails closed, leaving all transaction files intact and allowing manual Resume.
- New transactions persist Deleted/Drafts/Junk folder policies so subsequent Resume respects the original policy.
- Added FIX10 regression tests covering folder policy, DASL syntax, selection fallback, retry guard, transaction state and rollover logic.
- Does not implement worker-process isolation for COM Move hangs or independently prove the physical archive PST size never briefly exceeds its safety margin.

## 2.5.7-FIX9a — CI dependency correction (2026-10-21)

- IndependentVerifier.Tests.ps1 now imports ArchiveTransaction.ps1 before ArchiveVerifier.ps1, matching production.
- Added regression coverage for Test-OPAStateHasKey with OrderedDictionary and PSCustomObject.
- No change to mail-moving, verification, resume or on-disk schema.

## 2.5.7-FIX9 — Independent Verification & Recovery Accounting (2026-10-21)

- Archive verification observes source and destination Outlook folders; DuplicateIndex alone is no longer accepted as verification evidence.
- Completed move identities are reconstructed from the full step journal and DuplicateIndex and constrained to the persisted plan.
- Destination EntryID is checked in its archive store and recorded target folder; stale IDs may be verified only by a **unique** InternetMessageId plus size/subject/sender fingerprint.
- Reported `Source left` now uses observed Outlook item counts, not source-before minus completed.
- LogicalFreedBytes and per-PST LogicalAddedBytes are reconciled from unique completed planned items after Archive/Resume; Resume also reconstructs accumulated logical bytes before moving new items.
- Reports distinguish new COM moves, recovered archive moves, and repaired journal steps.
- Added behavioral Pester tests with an Outlook-like mock for the independent verifier and accounting.
- Does not address COM Move hangs, source lock races, or full recovery when InternetMessageId is absent. Fail-closed behavior is intentional.

## 2.5.7-FIX8b — deterministic Resume (2026-10-21)

- Resume works only on persisted PlannedItems; replacement candidates are prohibited.
- Validate plan IDs and counts before any Move.
- Count confirmed source IDs only when archive IDs are available and unique.
- A missing planned source message is reconciled from the recorded archive folder if uniquely identified by InternetMessageId and additional properties; ambiguous cases stop safely.
- Phase performance reports newly completed moves, not cumulative transaction total.
- Implements fail-closed archive-side fingerprint reconciliation for Move Started with missing Move Completed (still requires Outlook integration verification).

## 2.5.7-FIX7a — PS5.1 generic List CI corrections

Correct the two List[string] array conversions flagged in FIX7 CI. No movement logic changed.

## 2.5.7-FIX7a — Recovery Safety Baseline (2026-10-20)
- Protect active transaction step journals from orphan cleanup (correct checkpoint path).
- Quarantine malformed unterminated JSONL tail before truncating; preserve valid unterminated JSON.
- Propagate DuplicateIndex append failures rather than suppressing them.
- No fix for Resume candidate substitution in this build. DO NOT test Resume until FIX8b.

## 2.5.7-FIX5
- Fix: durability-mode detection now handles both ordered-dictionary state from a new transaction and PSCustomObject state loaded from a checkpoint.
- Fix: Resume now correctly detects the stored durability mode when inheriting it without an explicit `-DurabilityMode` argument.
- Adds regression tests for dictionary and PSCustomObject state key detection.

## 2.5.7-FIX4
- Fix: archive startup now recognizes the schema 1.2 append-only `DuplicateIndex.jsonl` as a valid index when the optional legacy `DuplicateIndex.json` base is absent. Previously the stale guard rejected a valid journal and stopped before moving any messages.
- Preserves the FIX3 COM lifetime fix.

## 2.5.7-FIX3
- Fix: avoid releasing the source Outlook Items COM object at the end of candidate selection. DIAG1 regression test moved and verified 50/50 items on ADMIN-5.
- Retains the other 2.5.7 reliability changes.

# CHANGELOG

## 2.5.7 — 2026-10-08

### Reliability Hardening
- Added explicit `Move Started` / `Move Completed` transaction events.
- Resume completion logic ignores `Move Started` and remains compatible with legacy `Move n/n` records.
- DuplicateIndex append failure after a successful Move now stops the batch after forcing the primary step journal to disk.
- Added a post-Move physical archive-size guard; the already moved item is retained and the next item rolls to a new PST part.
- Partial verified phases remain `Running` until the transaction target is actually completed, preventing premature `Completed` status during capacity rollover.
- Auto cleanup now removes orphan `*.steps.jsonl` journals when the checkpoint is absent and the retention period has elapsed.
- `Get-OPAAverageMessageSize` uses only `Completed` transactions.
- Added `-AutoTargetMinimum` (default 50) for target-driven Auto sizing.
- Selection diagnostics retain up to 20 concrete errors.
- `-Transaction` is valid only with `-Mode Resume`.
- Fixed a Windows PowerShell 5.1 HashSet materialization path by using `@($hashSet)` instead of `.ToArray()`.

### Preserved
- `DurabilityMode Fast/Safe`.
- Stored durability mode restoration on Resume.
- Transaction schema `2.5.4` for backward compatibility.

## 2.5.6 — 2026-10-08

- Fixed missing `Performance` state on Resume/Archive finalization.
- Initialized transaction performance counters for new transactions.
- Used dictionary-safe performance updates for Windows PowerShell 5.1.
- Removed the unsafe `HashSet[string].ToArray()` conversion path from skipped EntryID handling.

## 2.5.5
- Added validated `DurabilityMode Fast/Safe` implementation.
- Added stored-mode restoration on Resume.
- Added durability reporting.


### FIX7a — Resume completion accounting
- Restrict Resume completed-item tracking to EntryIDs present in the transaction PlannedItems.
- Prevent stale or unrelated inline Move steps from inflating Completed items and Executed counts.
- Keep DuplicateIndex reconciliation scoped to the current transaction and its planned source IDs.
