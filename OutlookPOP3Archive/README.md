# OutlookPOP3Archive — 2.6.3-PREVIEW1

Application: `0.9.4-rc1-build2.6.3-PREVIEW1`. Target: Windows PowerShell 5.1, Outlook 2016/2019.

**Status:** 2.6.3-PREVIEW1 development candidate: read-only interrupted Move reconciliation; CI pending. Production `Archive`, `Resume`, `Plan` and `Auto` still use the existing FIX13b Outlook COM code. Mail movement is **not delegated** to a worker. Keep FIX13b as the tested archiving baseline.

## Purpose and safety rules

- Archive old messages from **POP3** PST stores only; IMAP accounts are never archived.
- `Sent Items` and recursively nested user mail folders are included; Sent-like folders use `SentOn` when available. Deleted, Drafts, Junk subtrees are excluded by default; **Outbox is always excluded**.
- Selection defaults to 12 months; `-OlderThanMonths 0` requires `-IgnoreAge` for Plan/Archive/Auto.
- Archive PSTs rotate by year and part (`Archive-YYYY.pst`, `Archive-YYYY-02.pst`, etc.) with `MaxArchivePstSizeGB` and `SafetyMarginGB`.
- Every move is journaled; Resume uses the persisted plan and independent Outlook COM verification to avoid unverified duplicate moves. Safe mode strengthens journal flush durability.
- Auto uses high/target watermark plus a durable, per-source verified logical-progress ledger (`*.auto-storage.state`). Compact is **advisory only**, never executed automatically.
- Never delete transaction checkpoints, step journals, duplicate indexes or Auto progress state to clear an error.

## Common commands

```powershell
.\Invoke-CI.ps1
.\OutlookPOP3Archive.ps1 -Mode Analyze -ProfileName 'Outlook'
.\OutlookPOP3Archive.ps1 -Mode Plan -ProfileName 'Outlook' -Limit 50
.\OutlookPOP3Archive.ps1 -Mode Auto -ProfileName 'Outlook' -WhatIf
.\OutlookPOP3Archive.ps1 -Mode Archive -ProfileName 'Outlook' -Limit 50 -DurabilityMode Safe
.\OutlookPOP3Archive.ps1 -Mode Resume -ProfileName 'Outlook' -Transaction '<TransactionId>'
```

## Worker 2.6.3 (diagnostic only)

```powershell
.\Invoke-OPAWorkerSelfTest.ps1
.\Invoke-OPAWorkerSelfTest.ps1 -IncludeOutlookProbe -TimeoutSeconds 30
```

`Invoke-OPAWorkerControlledOperation` provides an outcome with `Status` (`Succeeded`, `Failed` or `Indeterminate`), `FailureKind`, `WorkerProcessId`, `RequestId`, deadline and duration. Timeout, crash and invalid response are **Indeterminate** and always require reconciliation before any future mutation retry. It never automatically retries; worker operations remain `Ping`, `Echo`, `Fail`, `Crash`, `Delay`, and opt-in read-only `ProbeOutlook`.

**Important:** A worker kill cannot prove a COM side effect did not finish. A future worker-driven `MailItem.Move` needs durable intent, independent source/destination reconciliation, and explicit safety gates before production use. Outlook.exe is not killed by this worker host.

See `docs/TESTING.md`, `docs/ARCHITECTURE.md`, `docs/RECOVERY.md`, `docs/CONFIGURATION.md`, `docs/OPERATION-JOURNAL.md` and `docs/RELEASING.md`.

## 2.6.2 Durable Operation Journal preview

An optional diagnostic-only API `Core/Worker/WorkerOperationJournal.ps1` writes a flushed `Intent` before dispatching the STA Worker and a second durable event after a confirmed outcome. Replay refuses automatic retry after an indeterminate worker result, missing completion, corrupted journal or truncated tail. It does not route real mail moves, and a worker success is not evidence that `MailItem.Move()` occurred.

Before publishing a release package, Windows PowerShell 5.1 must pass `Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'` including PSScriptAnalyzer/Pester. Produce only the OutlookPOP3Archive project ZIP using `New-OPABuildPackage.ps1` after that check; `docs/RELEASING.md` contains the checklist.

## 2.6.3 read-only interrupted Move evidence

`Core/Archive/MoveReconciliation.ps1` scans caller-selected, already mounted POP3 source and destination folders, verifies identities against the durable MailMove Intent, and classifies source-only, destination candidate, both present, missing, ambiguous and incomplete states. Even a unique destination fingerprint is **not proof** of a completed Move. The API never moves mail, writes journal completion, or enables automatic retry; it is not wired into the existing FIX13b production Resume/Auto path. See `docs/2.6.3-interrupted-move.md`.

## Live COM integration test (disposable PSTs)

`Core/Diagnostics/Invoke-OPA263LivePstTest.ps1` creates two **new temporary PSTs** and runs controlled copy/move diagnostics on a message cloned from the specified **test-only** donor PST. The donor's original message is never moved/deleted, but Outlook Copy temporarily writes a duplicate to its folder (if interrupted that duplicate may remain). The script is opt-in with `-Execute` and leaves its journal/PST evidence intact. The new reconciliation module still never issues a retry. Details: `docs/2.6.3-interrupted-move.md`.

## 2.6.3 independent process restart verification

The opt-in live COM harness leaves an unresolved Intent and both temporary PSTs mounted. To check restart replay with a **fresh PowerShell process**, run `Core/Diagnostics/Test-OPA263RestartReadOnly.ps1` against the specific generated `*.operations.jsonl` file. The script attaches to already running Outlook, locates stores by persisted StoreID/PST path, resolves existing folders and independently classifies their contents. It never writes to a PST, attaches a new store, changes the journal, retries a Move, or marks a transaction completed. See `docs/TESTING.md`.

### 2.6.4-LIVE5 (test-only independent crash journal review)

Read-only synthetic-only LIVE4 run reconciliation: see [LIVE5 runbook](docs/2.6.4-live5-independent-reconciliation.md). No automatic recovery, Worker production activation, or journal completion. Windows PS5.1 CI 583/39 pending.

### 2.6.4-LIVE6 (opt-in synthetic-only journal resolution)

See [LIVE6 runbook](docs/2.6.4-live6-controlled-journal-resolution.md). Only explicit pinned, independently confirmed post-Move crash evidence allows ONE journal-only Reconciled append. Otherwise read-only review. No MailItem.Move, production Worker enablement, or automatic retry. Windows PS5.1 CI 614/40 pending.

### 2.6.4-LIVE6a — separate manual size evidence gate

After cross-PST Move, MAPI MailItem.Size can differ from its original source-side value. The LIVE6a [read-only review runbook](docs/2.6.4-live6a-cross-pst-size-review.md) reports both sizes and prohibits any journal write without additional explicit approval and the exact destination byte count. Native Windows CI 631/40 pending; production Worker remains disabled.

### 2.6.5 bounded Worker canary (DEV only)

[Operational runbook](docs/2.6.5-bounded-worker-canary.md). The Archive/Resume CLI now includes a strictly bounded, explicit -WhatIf -WorkerPilot -ConfirmDevWorkerPilot **Ping-only** process isolation canary and stops before any COM/PST/transaction mutation. It does not archive/resume or enable real mail Move through Worker. Default FIX13b production path and worker integration flags remain unchanged. Native Windows CI target: 674 Pester tests in 41 containers.

### 2.6.5-BW2 isolated read-only Outlook probe (DEV)

[Runbook](docs/2.6.5-bw2-synthetic-readonly-probe.md). Explicit -WorkerPilotProbeSynthetic plus existing BW1 strict -WhatIf/consent gates permits a single isolated child Worker to **read only** exact previously-created LIVE3 synthetic source/archive folders and journal/claim identity, including a LIVE6a Reconciled journal. No Move, PST mutation, production archive routing, or automatic retry. Windows CI 718/42 pending.

### 2.6.5-BW2a - fail-closed diagnostic hotfix (DEV)

[Runbook](docs/2.6.5-bw2a-failclosed-diagnostics.md). First real BW2 read-only canary stopped safely but masked the original Worker error. This DEV hotfix surfaces bounded status and COM stage without auto retry, Move, PST changes or production integration. Windows CI target 732/43.

### 2.6.5-BW2b - strict source fingerprint evidence (DEV)

[Diagnostic runbook](docs/2.6.5-bw2b-source-fingerprint-evidence.md). After BW2a confirmed a real Outlook source MailItem fingerprint mismatch, BW2b reports *separately* source EntryID equality (plus exact SHA-256 hashes) and source MailItem.Size compared with durable Intent. Strict fail-closed guards remain intact; no size waiver, no automatic retry, Move or production activation. Windows CI 756/44 target.

### 2.6.5-BW2c source size review (DEV)

[Runbook](docs/2.6.5-bw2c-explicit-source-size-consent.md). Explicit, manually pinned *read-only only* acknowledgment of the proven source MailItem.Size drift 1436 to 1808 on the one pre-Move LIVE4 synthetic fixture, preserving strict EntryID/RunId/OperationId/journal checks. Neither automatically retries nor performs Move or journal updates. Native Windows CI target 784/45.

### 2.6.5-BW3 — crash-safe one-shot synthetic Worker (DEV)

[Runbook](docs/2.6.5-bw3-crash-safe-synthetic-one-shot.md). Dedicated **operator-only** synthetic Move controller with filesystem-only -Review, then explicit -Execute/-ConfirmBW3SyntheticMove and operator-pinned journal SHA256. For a **NEW** LIVE3 synthetic fixture only: durable controller dispatch claim before child, durable Worker attempt claim before one Move, no retry and no automatic journal completion. Production Archive/Resume/Auto and FIX13b remain unchanged. Windows PS5.1 CI target 822/46. Real Outlook Move is **not executed or authorized by building this DEV stage**.

### 2.6.5-BW3a — automatic PID assignment hotfix (DEV)

[Runbook](docs/2.6.5-bw3a-reserved-pid-crash.md). The first manually approved BW3 synthetic run stopped after durably recording its dispatch claim but before launching the Worker because controller code attempted to assign read-only PowerShell `$PID`. BW3a uses `$workerProcessId`; adds native Windows AST guards. **Never replay RunId e2399ba1-38e9-48e8-bf43-d39cc1c19edb**. New one-shot test needs a new operator-approved fixture and a separate approval; production remains off. Windows CI target 837/47.

### 2.6.5-BW3b — independent post-Move synthetic evidence audit (DEV, read-only)

[Runbook](docs/2.6.5-bw3b-independent-postmove-audit.md). A dedicated native Windows PowerShell 5.1 -Review-only inspector checks the ONE already successful BW3a synthetic Move: Worker-request correlation, exact durable claims and unchanged Intent journal, archived MailItem EntryID via independent COM lookup, class, parent folder, Subject/InternetMessageId and source=0/archive=1. No Move, store mount, journal write or implicit archive-size consent. Production FIX13b unchanged. Native Windows CI target 880/48.

### 2.6.5-BW3c — Russian PST path hotfix for independent read-only audit

[Runbook](docs/2.6.5-bw3c-unicode-path-fix.md). The first real BW3b audit stopped before COM: native Windows PowerShell 5.1 misread a BOM-less UTF-8 Cyrillic SourcePst literal as ANSI. BW3c replaces it with the EXACT same run-specific pinned Unicode path built from ASCII-only code points and adds 12 regression tests. Native Windows CI target 892/49. No Worker dispatch, MailItem.Move, PST modification or journal write. Production unchanged.

### Обязательное ТЗ по кодировке PowerShell

[Техническое задание — ТЗ-ENC-001](docs/TECHNICAL_SPECIFICATION.md): **весь новый и изменённый PowerShell-код** (`.ps1`, `.psm1`, `.psd1`) должен быть сохранён в **UTF-8 с BOM (EF BB BF)**, включая файлы, содержащие только ASCII. Windows PowerShell 5.1 без BOM может искажать Unicode/кириллицу. Настройка редактора — `.editorconfig`. `Invoke-CI.ps1` проверяет байты **до Pester** и отклоняет новые либо изменённые BOM-less файлы. Для 82 старых неизменённых файлов действует фиксированный переходный SHA-256; журналы JSON/JSONL не перекодировать автоматически. Production FIX13b остаётся без изменений.

### 2.6.5-BW3d - archived synthetic size evidence (DEV, read-only)

[Runbook](docs/2.6.5-bw3d-synthetic-size-readonly-audit.md). The previously confirmed synthetic BW3a Move has +8 bytes archive MAPI size drift (Intent 1436, archived 1444). BW3d reruns independent BW3b proof, reads only the existing archived synthetic MailItem Body/Attachments/MessageClass/size and optional PR_MESSAGE_SIZE, checks original durable artifact SHA256 before/after and outputs diagnostic text hashes. No new Move, size consent, content-byte-equivalence claim or Reconciled; production FIX13b unchanged. Native PS5.1 CI target 942/51 and mandatory UTF-8 BOM source gate.

### 2.6.5-BW3e - exact synthetic archived Body tail audit (DEV, read-only)

[Runbook](docs/2.6.5-bw3e-synthetic-body-tail-readonly-audit.md). The BW3d observed Body UTF8 SHA256 agrees with the fixture baseline text followed by exactly SPACE (32), CR (13), LF (10). BW3e independently rereads only the pinned archived synthetic MailItem and checks the entire Body text, length, final three Unicode code units and UTF8 SHA256. Runs existing BW3d/BW3b read-only identity/claims checks and rehashes all original evidence; raw Body is not printed. The +8-byte archived size drift is NOT automatically explained, approved or reconciled. Mandatory UTF-8 BOM source gate; Windows PS5.1 CI target 980/52. Production FIX13b unchanged.

### 2.6.5-BW3f - manual size decision dossier (DEV, read-only)

[Runbook](docs/2.6.5-bw3f-human-size-decision-dossier.md). For the exact already-confirmed historical synthetic BW3a Move, BW3f reruns BW3e/BW3d/BW3b read-only audits, hashes all six original journal/request/scope/dispatch/attempt/controller files before and after, and emits a **no-consent human review dossier**. Original Intent=1436, archive=1444 (+8 bytes, cause undetermined), Body baseline+SPACE/CR/LF, zero attachments. A passing dossier **does not** approve size drift, establish byte equality or authorize Reconciled. Mandatory UTF-8 BOM; Windows PS5.1 CI target 1030/53; production unchanged.

### 2.6.5-BW3g - one-time separate manual +8 byte acceptance (DEV only)

[Runbook](docs/2.6.5-bw3g-durable-manual-size-acceptance.md). Following explicit operator acceptance for the single historical synthetic RunId, BW3g adds read-only `-Review` and a one-shot explicit `-Record -ExactSizeAcceptance ...` command. Only a NEW standalone UTF-8 JSON consent file is written, via FileMode.CreateNew and forced flush. It pins historical evidence and six original SHA256s but does not modify the unresolved Intent, claims or PST and cannot authorize Reconciled or production. PowerShell code UTF-8 BOM, Windows PS5.1 CI target 1084/54.

### 2.6.5-BW3g1 — PowerShell switch `-Record` collision hotfix (DEV)

The actual BW3g read-only check PASSED. The subsequent explicit one-shot `-Record` attempt STOPPED before disk creation because PowerShell 5.1 treats switch parameter `$Record` and local `$record` as the **same case-insensitive variable**. BW3g1 renames only the object local to `$sizeAcceptanceEntry`. Check whether the exact acceptance JSON path exists using read-only `Test-Path`; never delete a present/partial file or automatically retry. Re-run `-Review` using BW3g1 after CI; new `-Record` requires a new separate operator approval after confirming absence and evidence integrity. Mandatory source BOM; native Windows PS5.1 test gate target 1090/55. Original PST, journal Intent and claims unchanged by hotfix.

### 2.6.5-BW3h — independent read-only seven-evidence chain audit (DEV)

[Runbook](docs/2.6.5-bw3h-independent-chain-readonly-audit.md). BW3h rechecks exact original Intent and six durable claims/fixture files plus separately recorded **single-synthetic +8 byte acceptance JSON** hard-pinned to its user-observed SHA256. It reruns BW3g1 → BW3f → BW3e → BW3d → BW3b read-only Outlook audit and rehashes all seven files before/after. No new approval or journal Reconciled, no Move, file writes or production change. PS5.1 CI target 1142/56; UTF-8 BOM source.

### 2.6.5-BW3i — journal reconciliation preflight READ-ONLY (DEV)

[Runbook](docs/2.6.5-bw3i-journal-reconciliation-readonly-preflight.md). BW3i reruns BW3h (all seven user-verified historical evidence files) and independently reviews original single-Intent journal append safety and existing LIVE6 `-Review` only. It verifies absence of any `live6-resolution.claim`, the journal's pinned bytes, and the exact hypothetical next `Reconciled` sequence 2, but never writes, creates a claim, moves mail or grants journal permission. Historical manual +8-byte size consent is not permission for `Reconciled`. Windows PowerShell 5.1 DEV CI target: 1212 tests / 57 containers. All new PS code UTF-8 with BOM.

### 2.6.5-BW3i1 — legacy LIVE6 cannot certify historical BW3a crash provenance (READ ONLY)

[Runbook](docs/2.6.5-bw3i1-legacy-live6-compatibility-readonly.md). Local BW3i: Pester 1212/57 PASS, actual Outlook `-Review` STOP at old LIVE6 classification. Historical BW3a Worker one-shot was **not** a LIVE4 controlled-crash fixture and lacks the three legacy crash-specific artifacts. BW3i1 strictly checks that mismatch (including the exact failed LIVE6 read-only schema), the seven intact BW3h evidence files and unchanged original Intent; it issues a **blocked executor** compatibility verdict. Never run `LIVE6 -Execute` for BW3a, fabricate crash artifacts, append Reconciled or create a new Move. DEV CI target 1250/58, mandatory UTF-8 BOM.

### BW3j — separate BW3a scoped journal resolution DESIGN (read-only DEV)

[Runbook](docs/2.6.5-bw3j-bw3-scoped-journal-resolution-readonly-design.md). Verified BW3i1 proved legacy LIVE6 inapplicable. BW3j (no LIVE4/LIVE5/LIVE6 calls) rechecks one exact historical synthetic Intent, both currently absent resolution claim slots, all seven original evidence SHA256s and the full read-only BW3h Outlook chain. Outputs ONLY an in-memory design contract: hypothetical Reconciled sequence 2, **no writer, no journal-write permission**, no Move or production. Native Windows PowerShell 5.1 DEV CI target 1301 tests / 59 containers, mandatory UTF-8 BOM.

### BW3k - isolated TEMP-only synthetic journal one-shot crash tests (DEV)

[Runbook](docs/2.6.5-bw3k-sandbox-oneshot-journal-crash-test.md). BW3k creates NEW synthetic journal fixtures strictly under OS TEMP. A durable CreateNew claim fences retries; exclusive journal lock and pinned SHA256 precede append of synthetic Reconciled sequence 2; replay is verified. Crash injection after claim, partial append and after append preserves evidence and blocks retry. No historical BW3a RunId/PST/Intent path is accepted, no Outlook COM, no MailItem.Move, no real journal writer or historical authorization. Native PS5.1 CI target: 1355 tests / 60 containers. New PS sources UTF-8 BOM.

### BW3l — historical BW3a Intent byte-copy Reconciled rehearsal (DEV, ORIGINAL READ ONLY)

[Runbook](docs/2.6.5-bw3l-historical-intent-copy-rehearsal.md). Reruns BW3j independent Outlook review and validates seven durable hashes and pinned one-Intent bytes; constructs a new exact byte-copy in a fresh OS TEMP OPA-BW3l-Copy-{GUID} folder, appends Reconciled only to that COPY using a permanent CreateNew claim, exclusive lock and SHA256 check. Original journal/PST/claims NEVER opened for write; no historical-run writer or permit. Offline regression target 1429 Pester tests / 61 containers on native Windows PowerShell 5.1; UTF-8 BOM.

### BW3m — independent historical journal writer security review (ORIGINAL READ ONLY)

[Runbook](docs/2.6.5-bw3m-historical-writer-security-review.md). BW3m re-runs BW3l/BW3j on exact historical Outlook evidence, then independently reads the NEW TEMP COPY claim, original one-Intent byte prefix, terminal Reconciled and recovery replay. All seven ORIGINAL hashes and one original Intent revalidated before/after. No original journal writer, claim creation, PST write, Move, retry or production. +62 fail-closed PS5.1 tests; expected 1491/62; UTF-8 BOM. -Review writes a NEW isolated TEMP COPY through BW3l only.

### BW4a — Option B historic Intent isolation for future Worker Archive/Resume (DEV)

[Runbook](docs/2.6.5-bw4a-option-b-historical-worker-fence.md). After BW3m local 1491/62 and actual Outlook PASS, Option B preserves the original single historical BW3a Intent. Adds a strictly opt-in -WorkerPilotReviewHistoricalFence (Archive/Resume only) **before COM, Worker dispatch or MailMover** and standalone no-Outlook -Review. Verifies seven historical immutable SHA256s, exact one Intent, absence of resolution claims; blocks historic RunId/OperationId/EntryID/journal identity and shared PST pending BW4b per-item fencing. Unrelated new candidates are NOT authorized by BW4a. No new journal, claim, PST write or production activation. Native PS5.1 CI target 1572/63, 81 new tests; TZ-ENC-001 enforced.

## BW4c DEV read-only Outlook/MAPI per-item review

The opt-in `-WorkerPilotReviewOutlookPerItem` route reads ONE exact synthetic candidate from an already-running Outlook profile using two MAPI lookup paths and verifies historical BW3a evidence before and after. It never mounts a PST or calls Move, and is not externally independent evidence. See [BW4c read-only guide](docs/2.6.5-bw4c-outlook-dual-path-readonly.md). Original historical Intent remains unresolved and quarantined; Worker Archive/Resume/Auto remains disabled.
