# Testing — 2.6.3-PREVIEW1

## ARCH1 delivery tests and context-restoration gate (2026-11-11)

New `Tests/Runtime/ARCH1DeliveryReadiness.Tests.ps1` checks a **static source-only** readiness classifier and zero Outlook/COM writers. It is NOT a live mailbox acceptance test. New [handoff](PROJECT-HANDOFF-ARCH1.md), [ADR](ADR-ARCH1-OUTLOOK-COM-BOUNDARY.md), [roadmap](DELIVERY-ROADMAP.md) and [implementation audit](ARCH1-IMPLEMENTATION-AUDIT.md) are normative for future tests and releases. The operator has already completed 4/5 original BW4j real fixture Move tests (Attachment256K not independently proven), and an additional BW4k7v2a7 synthetic Move; do not repeat historical one-shot claims.

**ARCH2's mandatory next test:** prove ambiguous COM Move outcome is never treated as an automatically retryable skip, including timeout/crash; integrate pre/post Body/HTML and SHA256 of actual bytes of attachments into the production-capable archiving path. Unexplained provider Size/flags drift only authorizes new diagnostics when user content/recovery is demonstrably at risk. No broad implicit flag waiver. Live 90GB/archive end-to-end NOT yet certified.


Run from the OutlookPOP3Archive directory under Windows PowerShell 5.1 (Pester 5+ and PSScriptAnalyzer both installed).

```powershell
.\Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'
.\Invoke-OPAWorkerSelfTest.ps1
.\Invoke-OPAWorkerSelfTest.ps1 -IncludeOutlookProbe -TimeoutSeconds 30
Invoke-Pester -Path .\Tests\Worker\WorkerOperationJournal.Tests.ps1 -Output Detailed
.\OutlookPOP3Archive.ps1 -Mode Plan -ProfileName 'Outlook' -Limit 50
.\OutlookPOP3Archive.ps1 -Mode Auto -ProfileName 'Outlook' -WhatIf
```

Release CI must reject stale Core/Version, MANIFEST, RELEASE, README or active documentation headers, obsolete package files, parser/PS5.1 compatibility errors, analyzer findings, missing analyzers and failed/skipped Pester tests. For packaged ZIP generation see `docs/RELEASING.md` and `New-OPABuildPackage.ps1`. The standalone ZIP must contain only the OutlookPOP3Archive project and SHA-256.

### Already validated on preceding 2.6.2 dev snapshot

- Non-mutating Worker SelfTest: Ping, Echo, Fail, Delay, controlled result classification. Opt-in STA Outlook COM probe: 2 accounts and 4 stores; no mail moved.
- Durable diagnostic journal: `Intent → WorkerSucceeded` recorded and replayed; synthetic Worker Crash captured as `Indeterminate` and automatic retry blocked; truncated journal tail retained with append and dispatch blocked.
- Real restart of PowerShell: successful diagnostic replay and next monotonically numbered operation; indeterminate diagnostic replay still blocked.
- `Tests/Worker/WorkerOperationJournal.Tests.ps1`: 11 Passed, 0 Failed in Pester 6.2.0, including torn journal completion test.

The earlier snapshot does **not** certify new release-pipeline changes or this metadata-bumped preview. Run full CI again before publishing.

### Not covered yet

Real Worker-driven COM `MailItem.Move()`, production Archive/Resume integration, post-move PST reconciliation, OS power-loss under COM mutation and Outlook Compact are not yet verified. FIX13b remains the active mail-moving engine.

## 2.6.3 additional tests — run under Windows PowerShell 5.1

```powershell
Invoke-Pester -Path .\Tests\Archive\MoveReconciliation.Tests.ps1 -Output Detailed
.\Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'
```

No real Outlook MailItem.Move is exercised; validate read-only observation against disposable PSTs before proceeding.

### CI regression gate added after first 2.6.3 DEV run

The first local 2.6.3 CI run reported `229 passed, 0 failed` **but one failed test discovery container** due to duplicate case-insensitive `EntryID`/`EntryId` keys in a new Pester fixture. This was a CI **failure** and must never be described as a successful build. The test fixture has been corrected. The updated `Invoke-CI.ps1` rejects invalid test source during the parser pass and uses the full Pester result (`Result`, `FailedContainersCount`, `FailedBlocksCount`, `Containers`, `InconclusiveCount`, `NotRunCount`), not just `FailedCount`. `Tests/Core/PesterReleaseGate.Tests.ps1` regression-tests the false-positive. Re-run full CI before packaging. 

### Real Outlook COM integration (disposable PSTs only)

Use `Core/Diagnostics/Invoke-OPA263LivePstTest.ps1 -SeedPstPath '<absolute path to designated TEST PST>' -Execute` in Windows PowerShell 5.1 STA while Outlook is open. This creates two new temporary PSTs, clones one eligible message from the designated test PST, and simulates a missing journal completion after a real first Move. Preserve the temp journal and report for review; note that Outlook Copy temporarily modifies the donor test PST. Full CI before running:

```powershell
.\Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'
```

### Live COM regression retest after second-copy staging fix

The first live COM integration test passed `SourceOnly`, `DestinationCandidate`, and `BothPresent`, but not `Ambiguous` because the extra bare `Copy()` was not observed as a second matching destination item. Re-run full CI on the **new** commit and then run the opt-in live harness on a newly created pair of disposable PSTs. Confirm `DestinationFingerprintMatches=2` in the generated `report.json` (or examine per-field comparisons if still 1). The harness does not repair original operation journals.

### Independent-process restart gate (read-only)

After a successful opt-in live COM harness run, leave Outlook and both disposable PSTs mounted. Open a **new** Windows PowerShell 5.1 STA process, go to the same source checkout and run:

```powershell
powershell.exe -NoProfile -STA -File .\Core\Diagnostics\Test-OPA263RestartReadOnly.ps1 `
  -JournalPath '<exact persisted Temp OPA263-Live-.../live-....operations.jsonl>' `
  -ExpectedStatus 'Ambiguous'
```

The result must report `Ambiguous`, `DestinationMatches=2`, no automatic retry, and unchanged journal SHA-256. The script does not create, attach, detach or modify Outlook stores. If stores were detached, Outlook was restarted into a different profile or MAPI StoreID changed, the verifier MUST fail closed rather than searching other PSTs. Windows full CI must be rerun for any source code change.

## 2.6.3 source-mismatch incident and enforced CI inventory

A local package labeled `d4bc6974` was built from an older `g8e4be719` extracted directory. It executed 272 tests/25 containers and selected 70 source files, while the pinned commit had 26 test files and 71 project files. This is **not** validated provenance; do not publish that ZIP as a release. The corrected pipeline requires **26** test containers, **281** Pester tests (three added source-integrity regressions), and a SHA256 over the entire release source inventory. For exact-source Git packages, use `-ExpectedSourceInventorySha256` from the separately verified commit.

## Mandatory UTF-8 BOM gate (TZ-ENC-001)

See [technical specification](TECHNICAL_SPECIFICATION.md). All new or modified PowerShell `.ps1`, `.psm1`, `.psd1` files MUST be UTF-8 with the `EF BB BF` byte-order mark, including ASCII-only source. `Invoke-CI.ps1` verifies actual source bytes and strict UTF-8 decoding **before** loading other scripts or running Pester. The 82 preexisting files lacking BOM are tolerated only while their canonical whole-set SHA-256 remains exactly unchanged; any edit to one requires migrating that file to BOM. This requirement deliberately excludes worker protocol JSON, journals and PST data, which must retain their specified byte formats.

## SEM-001 — Mandatory logical-message integrity and separate MAPI metadata acceptance

The **normative** matrix is [SEMANTIC-INTEGRITY-POLICY.md](SEMANTIC-INTEGRITY-POLICY.md). A passing synthetic/test result must verify significant message fields (including recipients for future production), text and HTML, dates/class, attachment byte lengths and SHA-256, message correlation and source-zero/destination-one independent reconciliation. Treat size-only changes as *metadata diagnostics*, **never** as generic matched bytes or automatic writer permit. Test changed Body/HTML, changed attachment SHA/name/count, recipient/flag mismatch, duplicate target, unavailable mandatory data, interrupted Move, and cross-store EntryID/RecordKey changes. Include failures for stale source witness, historic Claim changes, size drift without independent checks, and ambiguous journal state.

BW4k7a **real disposable** Attachment1K source drift: 8122 -> 8634 (+512) while SHA-256 of the original 1024-byte attachment is identical, all other BW4j witness fields match, two live source witnesses agree and all three old one-shot claims remain intact. No original witness recapture, claim, Move, retry or size consent. The BW4k7b synthetic semantic policy is read-only; it must not silently claim full recipient/flag coverage or production readiness. Run full native Windows PowerShell 5.1 BOM/PSScriptAnalyzer/Pester + BW4j6 synthetic fault matrix on the exact release commit before publishing ZIP.

## BW4k7c one-fixture source Size acknowledgment regression

27 additional synthetic Windows PowerShell 5.1 tests (2192 total, 92 containers) validate original exact identity/size/attachment SHA, rejected wrong source evidence, manual approval phrase, invalid decision or injected writer flags, correct BOM CreateNew+Flush(true) immutable file, duplicate-write refusal, no redirected evidence, independent exact hash verification and no journal/Move in controller. The test suite does **not** run a real Accept or Move on Outlook; user decides whether to record a standalone size-only acknowledgment after local `Review`. See [runbook](2.6.5-bw4k7c-exact-source-size-decision.md) and [SEM-001](SEMANTIC-INTEGRITY-POLICY.md).

## BW4k7d read-only semantic mail recipient/flag regression

31 new tests cover complete ordered recipients (To/Cc/Bcc), stable SHA256 digests, read/unread, categories, priority, MAPI READ and HASATTACH bits, missing properties and double-read consistency. Expected 2223 Pester tests / 93 containers. The previously recorded size decision is immutable, no new Move permitted. See [BW4k7d guide](2.6.5-bw4k7d-recipients-flags-readonly.md).

## BW4k7e immutable semantic source snapshot tests

25 new PowerShell 5.1 tests (target **2248 tests / 94 containers**) validate exact previous BW4k7d recipient/state SHA, unchanged previous 3 Move claims, SHA-pinned BW4k7c decision, write-once BOM JSON `FileMode.CreateNew` + `Flush(true)`, verified readback, `-WhatIf`, schema strictness, no raw addresses, no source baseline rewrite and no Move/production permission. Only synthetic CI; no COM Move in Actions. [Runbook](2.6.5-bw4k7e-immutable-semantic-source.md).

## BW4k7f no-Move empty target gate

Expected CI **2276 Pester tests / 95 containers**. 28 synthetic tests enforce immutable original Attachment1K recipient/state SHA, unique source message with pinned EntryID, exact source-one/target-zero destination folder and distinct store, no duplicate folder, no stale current fixture Claim, no hidden PST creation/mount/Move, and same full read-only checks under `-WhatIf`. Full Windows PowerShell 5.1 BOM/PSScriptAnalyzer/Pester plus BW4j6 fault matrix before ZIP release; no real Outlook inside CI. [BW4k7f runbook](2.6.5-bw4k7f-empty-target-no-move.md).

## BW4k7g one-shot disposable mail and postmove semantic audit (SEM-001)

39 synthetic Pester tests (expected **2315 tests/96 containers**) cover exact +512-only provider Size drift, unchanged original message/content/attachment SHA, manual size decision and original immutable recipient-state snapshot, durable `FileMode.CreateNew/Flush(true)` one-attempt Claim in the prior BW4k1 path (cross-version retry fencing), explicit approval, single call to `MailItem.Move()`, `-WhatIf` with no claim, and independent destination full To/Cc/Bcc/user-state hash and source-zero/target-one checks. GitHub Actions native Windows PowerShell 5.1 + Analyzer + Pester + original 5/5 BW4j6 synthetic fault matrix; no Outlook/PST in CI. Actual user disposable Move never runs as part of CI. [BW4k7g guide](2.6.5-bw4k7g-one-shot-attachment-move.md).

## BW4k7h post-Move state attribution, SEM-001

24 new synthetic Pester tests (expected **2339 tests in 97 containers**) validate byte-for-byte compatibility with original BW4k7d state SHA canonicalization, original full MAPI flags substitution, XOR bit reporting, changed user-visible Categories/To/FlagStatus detection, READ/HASATTACH significant bits, double independent-read stability, read-only controller and immutable Claim/evidence SHA fence. GitHub Actions full native Windows PowerShell 5.1 + BOM + PSScriptAnalyzer + Pester + 5/5 BW4j6 synthetic matrix; no real Outlook/PST in CI. No new Move, Claim writer or archival production flag. [BW4k7h guide](2.6.5-bw4k7h-postmove-state-attribution.md).

## BW4k7i read-only reopen integrity (SEM-001)

32 new synthetic Pester tests (expected **2371 tests in 98 containers**) verify exact original irreversible Claim/recipient snapshot SHA, source-zero/destination-one, body/attachment/recipient integrity, known MSGFLAG_UNMODIFIED 0x2 vs unknown 0x00010000, one immutable BOM/Flush(true) evidence capture, no claim/journal/PST writes and true Outlook restart StartUtcTicks before repeated compare. GitHub Actions native Windows PS5.1 Pester/PSScriptAnalyzer/BOM and full original 5/5 BW4j6 matrix; no actual Outlook/PST process-restart tests in CI. Operator uses read-only [BW4k7i runbook](2.6.5-bw4k7i-reopen-integrity-readonly.md).

## BW4k7j Microsoft MAPI raw flag classification, SEM-001

32 new Pester synthetic cases (expected 2403 tests in 99 containers) verify documented `mfUnmodified` 0x2, unchanged READ/HASATTACH, exact observed 0x00010002 XOR, unidentified PR_MESSAGE_FLAGS 0x00010000, separate-property STORE_HTML_OK collision, strict no-waiver policies, alternate dangerous flag mutations, BW4k7i immutable reopened SHA, and a read-only controller with no Move/Claim file writer. Full native Windows PowerShell 5.1/Pester/PSScriptAnalyzer/TZ-ENC-001/SEM-001/BW4j6 5-of-5 synthetic CI; actual PST/Outlook writes never performed by CI. [Runbook](2.6.5-bw4k7j-mapi-flag-investigation.md).
