## 2.6.5-BW3f - read-only human size decision dossier (2026-10-27; CI pending)

- BW3e local Windows PS5.1 Pester 980/52 PASS and Outlook live read-only Body tail PASS: 50-character assigned fixture Body plus SPACE/CR/LF (53), SHA256 matched; archive size 1444 versus 1436 Intent, +8 remains unexplained/unapproved.
- New dev-only Test-OPA265BW3fManualSizeDecisionDossier.ps1 -Review reruns BW3e -> BW3d -> BW3b and fingerprints original journal/request/scope/dispatch/attempt/controller files before and after. Pure classifier checks exact historical identities, success fields, typed booleans and Unicode arrays; forged size waiver, content byte equivalence or journal completion fails closed.
- Produces a read-only manual evidence packet. HumanSizeDecisionRecorded=False, SizeDifferenceApproved=False, ManualJournalDecisionAuthorized=False, WriteableReconciliationPermitIssued=False, JournalReconciled=False. Any future waiver or journal write requires distinct explicit user authorization and safety review.
- +50 new Pester tests; Windows PowerShell 5.1 CI target 1030 tests / 53 containers, mandatory UTF-8 with BOM for all new code.
- No additional Move, PST mutation, claim creation/deletion, automatic retry, production Worker or FIX13b changes.

## 2.6.5-BW3e - exact archived synthetic Body trailing Unicode proof (2026-10-27; CI pending)

- Historical BW3d read-only Outlook check: 942/51 local PASS, but Body hash differs from fixture literal, archived MAPI size 1444 against Intent 1436. User independently reproduced observed SHA256 for exact literal + SPACE + CR + LF.
- New BW3e independent read-only inspector requires BW3d (which reruns BW3b), pinned RunId/OperationId/WorkerRequestId/journal, and single exact archive EntryID, then checks *entire* Body text plus exactly U+0020/U+000D/U+000A, length and SHA256.
- No raw Body output; original six journal/claim/request/scope files rehashed before and after COM getters; no code path for Move, journal writes or size consent.
- +38 native PowerShell 5.1 Pester cases (target 980/52); all new code and tests strictly UTF-8 BOM (TZ-ENC-001).
- Trailing whitespace does NOT establish when it was added or explain eight additional provider MAPI size bytes. Journal remains unresolved; no Reconciled, retries or production changes.

## 2.6.5-BW3d - independent archived synthetic +8-byte size evidence (2026-10-27; CI pending)

- BW3c independently verified previous BW3a Move (source=0, archive=1, EntryID correlated, immutable Intent) but Intent size 1436 differs from archived MailItem.Size 1444. No size approval exists.
- New read-only Test-OPA265BW3dSyntheticSizeAudit.ps1 invokes previous BW3b audit and then inspects the exact synthetic archived Body, zero attachments, MessageClass, MailItem.Size, optional MAPI PR_MESSAGE_SIZE. Reports diagnostic UTF8 text hashes and CRLF-only normalized comparison, never claiming stored-byte equivalence.
- Strict pinned old run/operation/WorkerRequestId/archived EntryID/POP3 PST/journal; hashes six durable files before and after COM. Fail closed for duplicate mail, unexpected content, wrong size or corrupted evidence.
- All new PowerShell sources have UTF-8 BOM. +41 Pester cases, expected native Windows PS5.1 gate 942 tests in 51 containers.
- No MailItem.Move, automatic size waiver, journal Reconciled, PST writes, production Worker or FIX13b changes.

## ТЗ-ENC-001 — обязательная кодировка PowerShell UTF-8 с BOM (2026-10-27)

- В `docs/TECHNICAL_SPECIFICATION.md` формализовано требование для всех новых/изменённых `.ps1`, `.psm1`, `.psd1`: UTF-8 с BOM `EF BB BF`, независимо от наличия кириллицы.
- Добавлен `.editorconfig` с `charset = utf-8-bom`. В `Invoke-CI.ps1` введён ранний fail-closed байтовый контроль и проверка корректности UTF-8.
- Зафиксирован неизменяемый переходный SHA-256 для 82 старых BOM-less файлов. Их изменение возможно только после миграции конкретного файла в BOM. Девять новых Pester-тестов кодировки, локальный и Windows CI на 901 тест/50 контейнеров.
- JSON, JSONL, журналы и PST исключены из автоматической BOM-конверсии. Маршруты Archive/Resume и production FIX13b не изменены.

## 2.6.5-BW3c — native PS5.1 Cyrillic SourcePst audit hotfix (2026-10-27; CI pending)

- User's BW3b 880/48 native Windows CI PASS, but its first live read-only audit stopped at exact source-PST parameter check without Outlook COM.
- Root cause: native Windows PowerShell 5.1 decodes a UTF-8-without-BOM .ps1 as ANSI; embedded Cyrillic in exact SourcePst check was corrupted. CI had not compared that path with the real operator-provided Unicode input.
- BW3c retains the same fully pinned source PST, RunId, OperationId, WorkerRequestId, archive EntryID and journal SHA256. It constructs the Cyrillic folder name from ASCII-only [char] Unicode code points in the pinned proof, without relaxing -cne case-sensitive scope validation.
- Existing 43 offline evidence tests now use the common pinned identity; +12 dedicated native PS5.1 charset and safety regressions. Windows CI target 892/49.
- No new Move, no new fixture, no journal modifications and no automatic Reconciled. Production FIX13b unchanged and production Worker disabled.

## 2.6.5-BW3b — independent synthetic post-Move audit (2026-10-27; CI pending)

- BW3a real Outlook one-shot Worker returned Succeeded for RunId a7b51427-7494-43f4-bc96-64915f6bee7e; independent LIVE3 read-only inspector observed source 0/archive 1; both durable dispatch/Move claims exist and original journal SHA256 unchanged.
- Dedicated DEV-only `Test-OPA265BW3bIndependentMoveAudit.ps1 -Review` for that one historical RunId, worker RequestId and archive destination EntryID. Strictly read-only: no MailItem.Move, no PST store modifications, no journal writes.
- Correlate immutable Intent, full dispatch record, attempt claim, controller result, WorkerRequestId, expected archive EntryID and exact synthetic POP3 test scope. Reject missing/foreign claims, extra fields, changed journal, wrong folder/store/subject/InternetMessageId, missing/duplicate mail.
- New direct Outlook archive EntryID lookup and before/after raw durable evidence comparison. Source 0/archive 1 + exact archived EntryID yields an identity-only classification; archive MAPI size drift is reported but NEVER automatically approved. Content byte equality is not asserted.
- +43 offline tests. Target native Windows PS5.1 CI 880/48; production FIX13b, Archive/Resume/Auto, RealMailMoveViaWorker=False and ProductionReady=False unchanged.

## 2.6.5-BW3a - reserved PID hotfix, no replay of claimed synthetic run (2026-10-27; CI pending)

- User BW3 real operator-approved one-shot controller hit PowerShell read-only automatic variable `$PID` while executing case-insensitive `$pid=0` **AFTER** flushing `bw3-dispatch.claim` and **BEFORE** any Worker invocation.
- Historical RunId e2399ba1-38e9-48e8-bf43-d39cc1c19edb is permanently claimed. Preserve the dispatch claim and original Intent, do not retry with old/new scripts even when the independent read-only observation shows no Move.
- BW3a renames the controller-local variable to `$workerProcessId` in initialization, assignment and reporting. 15 new AST/static regression tests prevent regression; Windows CI target 837 tests/47 containers.
- No change to one-shot claim order, Outlook scopes, Worker Move, journal policy, or production FIX13b. ProductionReady=False, RealMailMoveViaWorker=False. New fixture/Move will require separate explicit approval.

## 2.6.5-BW3 — crash-safe one-shot synthetic Worker dispatch (2026-10-26; DEV CI pending)

- BW2c real Windows read-only PRE-MOVE and POST-MOVE canaries PASS with unchanged original journal SHA256. Old RunIds never reused for Move.
- Dedicated BW3 controller supplies read-only fixture -Review and explicit -Execute/-ConfirmBW3SyntheticMove with operator-pinned journal SHA256. Does not modify production Archive/Resume/Auto route or FIX13b.
- Strict new fixture scope, complete durable Intent and original SHA; durable CreateNew+Flush(true) dispatch claim BEFORE Worker start, then child durable CreateNew+Flush(true) attempt claim BEFORE sole synthetic MailItem.Move.
- Native Win PS5.1 STA child attaches to existing TEST Outlook and unique POP3+disposable-PST synthetic folders only; checks EntryID, Parent, InternetMessageId, Subject, untouched Intent size, source=1/archive=0; no size waiver, existing Inbox or PST mounting.
- Any error/timeout/invalid response is permanent stop for that RunId; no automatic retry, no Completed/Reconciled write, independent fresh read-only review always required.
- Legacy LIVE3/LIVE4 entry points refuse BW3-dispatched fixture, preventing simultaneous claims/races.
- 38 new offline tests, Windows CI target 822 tests / 46 containers. Real BW3 Outlook execution NOT performed. Production Worker Move disabled.

## 2.6.5-BW2c — single-fixture read-only source MAPI size consent (2026-10-26; CI pending)

- User BW2b pre-Move read-only probe observed unchanged SourceEntryId, but Intent.Size=1436 vs source MailItem.Size=1808 (+372). Previous LIVE6a +8 destination size approval is unrelated.
- New explicit paired switches acknowledge exactly 1808 observed SOURCE bytes only for pinned pre-Move RunId 77854a93-...; OperationId, original journal SHA256, stored Intent.Size, matching EntryID, synthetic folder and POP3 identity remain mandatory. Both parent and child independently validate. Original source-size mismatch still fails without consent.
- Read-only inspection ONLY, no durable Intent edits, no journal resolution, PST/Outlook modifications, retry or real MailItem.Move. No other RunId can use this consent.
- Added 28 offline regression tests; Windows PS5.1 target 784 tests, 45 containers. Production flags unchanged.

## 2.6.5-BW2b - independent source EntryID/size evidence (2026-10-26; DEV CI pending)

- Real Windows BW2a 732/43 CI PASS. BW2a real pre-Move synthetic probe stopped at source MailItem identity: EntryID or Size differs from durable Intent. Which component differs remains unknown.
- BW2b keeps strict fail-closed matching and adds both comparison booleans, Intent/observed sizes, signed delta and SHA256 hashes of raw EntryIDs instead of echoing raw EntryID strings. A size mismatch is NOT auto-approved.
- No new Outlook COM scope, MailItem.Move, journal append, PST writes, automatic retry or fallback to FIX13b. Production flags remain false.
- 24 offline regression tests; native Windows PS5.1 CI target 756 tests / 44 containers.

## 2.6.5-BW2a - fail-closed child Worker diagnostic fix (2026-10-26; CI pending)

- Native Windows BW2 718/42 CI PASS. First real read-only synthetic pre-Move probe safely stopped with a generic Worker error.
- Underlying child status, exit code and original error were hidden; BW2a reports them in bounded printable text, while preserving fail-closed no-retry policy.
- Child labels narrow read-only COM inspection stages, not new mutation logic.
- Original synthetic fixture scope, journal SHA256, no PST edits, no MailItem.Move and FIX13b remain unchanged.
- 14 new offline tests; native Windows PS5.1 expected 732 tests/43 containers. Outlook cause pending real inspection.

## 2.6.5-BW2 — isolated synthetic-only Outlook read-only probe (2026-10-26; CI pending)

- Real Windows BW1 Archive/Resume one-Ping worker canaries PASS. New explicit BW2 opt-in inspects only exact existing LIVE3 synthetic folders from an isolated native Windows PS5.1 STA Worker.
- Supports unresolved Intent (NoMoveObserved) and completed LIVE6a Reconciled (MoveConfirmed) with durable claim/EntryID and immutable journal SHA256.
- Parent and child independently validate fixture, output and identity; only an already-running TEST Outlook profile, POP3 DeliveryStore and exactly two synthetic folders may be examined. No Inbox, new PST mount, MailItem.Move, journal mutation, automatic retries, or fallback to Archive/Resume.
- 44 new offline tests; Windows CI target 718 tests / 42 containers.
- Default FIX13b production path unchanged; RealMailMoveViaWorker=False, ProductionReady=False.

## 2.6.5 — opt-in bounded Archive/Resume Worker canary (2026-10-26; DEV CI pending)

- LIVE6a real Outlook review, explicit +8-byte cross-PST size consent, one-shot synthetic Reconciled journal append and subsequent independent AlreadyReconciled check PASS. Archived mail was not moved again.
- Main Archive/Resume entry supports a strictly gated read-only WorkerPilot switch. Requires explicit -ConfirmDevWorkerPilot, -WhatIf, -Mode Archive or Resume, -ProfileName Outlook, -Limit 1, exactly one Ping operation, and bounded 1..30-second timeout. Resume additionally requires an explicit GUID -Transaction.
- Canary exits before Outlook COM, transaction/PST creation, journal writes and MailMover. Failed/indeterminate responses stop; no retry and no fallback to legacy mail Move.
- Default FIX13b is unchanged. RealMailMoveViaWorker remains false; no Auto Worker; production remains unpromoted.
- Added 43 offline tests; native Windows PS5.1 gate expected 674/41.

## 2.6.4-LIVE6a — cross-PST store-computed MailItem.Size safety fix (2026-10-26; CI pending)

- User's LIVE6 real Outlook pre-Move review PASS; post-Move review rejected because source-side durable Intent.Size differed from archive MailItem.Size after the cross-PST Move. Journal was not changed.
- Source-side and archive-side MAPI message sizes are now independently reported as exact observed values. A mismatch cannot be silently accepted: Execute requires new explicit size-difference consent plus an exact separately pinned destination byte count.
- Existing run-specific synthetic message ID/subject, StoreIDs, folder EntryIDs, source-empty/archive-one, original SHA-256 journal, exclusive claim, and no-Worker retry protections remain.
- Persist source/archive size evidence and explicit drift approval in single-use durable claim. Added 17 offline tests; expected Windows PS5.1 CI 631/40.
- No live Execute performed; no production routing changes.

## 2.6.4-LIVE6 — controlled journal resolution (2026-10-26; Windows CI pending)

- LIVE5 real Outlook independently confirmed source=1/archive=0 pre-Move and source=0/archive=1 post-Move crash, with unchanged journals and no re-Move.
- LIVE6 introduces explicitly approved synthetic-only manual journal Reconciled append ONLY after independently re-observed MoveConfirmed, exact target MailItem.EntryID, pinned original SHA256 and durable exclusive claim + compare-and-append.
- Refuses NoMoveObserved, corrupt/torn/ambiguous/stale journal, unapproved Outlook profiles, missing target identity, concurrent claim, and repeat writes. Subsequent read-only review returns AlreadyReconciled.
- 31 new offline fail-closed tests; expected native Windows PS5.1 614 tests / 40 containers. No production Archive/Resume/Auto changes and no automatic retry.

## 2.6.4-LIVE5 — independent journal reconciliation (2026-10-26; pending Windows CI)

- User confirmed LIVE4 Windows PS5.1 Pester 551/38 PASS and two real synthetic-only crash scenarios (before Move: 1/0; after Move before response: 0/1).
- New read-only LIVE5 journal replay, durable Intent fingerprint validation, independent LIVE4 Outlook re-inspection, explicit NoMoveObserved/MoveConfirmed/AmbiguousDuplicate/MissingItem/Ambiguous/InspectionFailed decisions and SHA-256 journal stability check.
- 32 offline regression tests; expected LIVE5 Pester 583/39, NOT yet independently run on Windows.
- No automatic retry, journal commit, PST mutation, production integration, or build version bump; FIX13b and 2.6.3-PREVIEW1 remain unchanged.

﻿## 2.6.4-LIVE4 (2026-10-26; real synthetic Worker crash windows DEV)

- User-confirmed LIVE3C native Windows 5.1 CI PASS 523 tests in 37 containers, and real one-shot cross-PST synthetic-only MailItem.Move PASS: source 1->0; archive 0->1; exact synthetic match; claim and response present; no normal production Worker enable.
- Add separate test-only LIVE4 controlled crash Worker + parent-owned controller: WorkerStartedBeforeMove and AfterMoveBeforeResponse durable, RunId/OperationId/PID verified crash barriers; kill only launched child, never Outlook; parent dispatch claim precedes spawn; no retry or optimistic journal completion.
- Add read-only independent LIVE4 crash recovery probe; validates controller/barrier/claim, then exact synthetic source/archive matches. No automatic reconciliation or Move; production gates remain closed.
- Block direct LIVE3 diagnostic Worker from replay of a LIVE4 dispatched RunId; LIVE4 Worker also refuses pre-existing crash barrier/controller results.
- Add 28 offline regression tests in one additional container. LIVE4 native Windows CI target **551 tests / 38 containers** (PENDING), real Outlook crash windows NOT YET RUN.
- Preserve prior claimed RunIds. For each crash scenario, create a fresh synthetic test fixture in existing test POP3 PST with a new disposable archive. No repeated 7 GB backup/restore exercise.

## 2.6.4-LIVE3C (2026-10-26; Microsoft Outlook new unsent mail Save placement DEV)

- User-confirmed LIVE3B native Windows PowerShell 5.1 CI PASS: 517/37; real Outlook fixture reported SourceItemsNotOne and UnexpectedParentFolder before any Worker Move or journal Intent.
- Microsoft MailItem.Save documentation allows new mail to be saved in default Drafts. The fixture now validates the exact newly created RunId-stamped mail, performs an explicit one-item staging Move into the GUID-scoped source folder only when needed, verifies parent StoreID + EntryID and 1/0 folder counts, then writes durable Intent.
- Worker still performs exactly one independently claimed archive Move later; fingerprint now checks stable parent MAPI folder identity rather than visual FolderPath. Fixture response discloses FixtureStagingMoveExecuted. Existing Inbox/2019/2020 archives not touched by test.
- Add 6 offline tests for folder identity, placement ordering and one staging Move; Windows CI target 523/37 PENDING. Old incomplete fixtures remain untouched, fresh RunId on every attempt.

## 2.6.4-LIVE3b (2026-10-26; real Outlook synthetic mail identity fix DEV)

- LIVE3 native Windows PowerShell 5.1 CI user-verified PASS: 507 Pester / 37 containers. First real Outlook synthetic fixture failed at the aggregated identity check BEFORE durable journal/request/marker and BEFORE any Move.
- Remove unstable SenderEmailAddress and PST-dependent strict Size requirements from synthetic fixture, one-shot Worker and independent inspector. Keep exact folder/store/EntryId plus run-unique InternetMessageId and Subject. Source fixture now reports the specific failed identity predicate instead of an opaque combined error.
- Add 10 regression Pester tests for unsent mail identity, forged Intent and zero Size, target 517/37 native CI PENDING.
- Do not reuse incomplete first fixture RunId; new GUID fixture is isolated. No full PST re-backup, no LIVE2B dependency, production Worker remains disabled.

## 2.6.4-LIVE3 (2026-10-23; user-directed return to Move/Worker roadmap DEV)

- User confirmed existing Outlook profile and POP3 PST are intentional test data; historical mail risk accepted. Do not require new profile, another byte-for-byte backup, or LIVE2B mismatch follow-up to develop the archiver.
- LIVE2 real Outlook temporary PST mount/read/detach succeeded; one CountMismatch (9 folders on both sides) was observed, potentially because inbox contents changed. User has not tested LIVE2B; that diagnostic branch is deferred.
- Add a separate test-only fixture for an existing uniquely bound POP3 PST: one GUID-scoped synthetic folder and one synthetic MailItem, new temporary destination PST, durable MailMove Intent. Existing Inbox mail is never selected.
- Add one-shot diagnostic Worker invoking MailItem.Move on only the exact synthetic fingerprinted item after a durable claim, plus separate read-only source/destination folder observation.
- Add 17 offline safety and path tests; LIVE3 target 507 tests in 37 containers, native Windows CI PENDING. Production Archive/Resume/Auto and standard Worker allowlist unchanged.

## 2.6.4-LIVE2 (2026-10-23; test-only Outlook cloned backup restore drill DEV)

- LIVE1 exact-source native Windows PowerShell 5.1 CI user-confirmed 478 tests/35 containers PASS.
- User created a reference POP3 PST backup with SHA256-matched byte copy; original unchanged. This is not yet a functional Outlook restore test.
- Add immutable reference backup guard, one-shot RunId-specific TEMP restored PST clone, distinct -Review/-PrepareClone/-ProbeClone actions, Outlook-closed cloning and full SHA256 verification.
- The opt-in restore probe uses the CURRENT test Outlook profile; requires unique source POP3 DeliveryStore, opens only an exact temporary clone using Unicode AddStoreEx, compares read-only folder structure/counts and detaches only that confirmed clone.
- Add 12 offline Pester tests; LIVE2 expected 490 tests in 36 containers (not yet run). No MailItem.Move, journal completion, Worker retry or production Archive/Resume/Auto changes.

## 2.6.4-LIVE1 (2026-10-23; existing test POP3 PST backup gate DEV)

- User confirmed the current Outlook profile is the dedicated test context; the selected info@stios.ru.pst maps uniquely to the POP3 DeliveryStore. Read-only audit measured 9 folders and 26,310 Inbox items (~7,200.98 MB PST). Existing 2019/2020 archives are protected.
- User-reported 2.6.4-G Windows PS5.1 CI PASS: 464 tests/34 containers, and separately independently pinned extracted ZIP audit ExactContentMatch. Live Outlook PST Move/crash tests not yet executed.
- Added safe scripts to list current mounted PSTs, verify a specified POP3 source StoreID and folder scope, preview cleanup of ONLY old opa263_archive*.pst, and (optionally) enforce an isolated profile.
- Added preview/explicit-approval backup flow for existing PST while Outlook is closed: copy into a distinct local directory via .partial and CreateNew, flush, SHA-256 verify, then publish to new .pst. Never changes or overwrites source or archive files.
- Added 14 offline backup guard tests; LIVE1 Windows CI target 478 tests / 35 containers, currently unverified. No existing PST MailItem.Move and no production Worker integration.

## 2.6.4-G (2026-10-23; source/package integrity and release gate DEV)

- User-reported Windows PowerShell 5.1 Pester CI PASS for F: 442 tests in 33 containers, zero failures/skips. G Windows CI is pending.
- Added offline SHA-256 inventory of source files and byte-level verification of every ZIP entry against source, exact single root/stem, externally pinned Git commit and SHA-256, BUILD-INFO and safe Worker flags.
- Added standalone read-only package/DEV-readiness audit and 22 new offline tests. Expected G CI: 464 tests in 34 containers, zero failures/skips.
- Blocked formal release, tag, merge-to-stable and production Archive/Resume/Auto Worker integration until REAL isolated Outlook COM crash/restart/reconciliation and PST identity tests are completed with human review and version metadata bumped.
- Source application version intentionally remains 2.6.3-PREVIEW1 as an integration baseline; no production MailMove or journal Auto/Reconciled route changes.

## 2.6.4-F (2026-10-23; machine-readable crash evidence audit DEV)

- User-reported Windows PowerShell 5.1 Pester PASS for stage E: 409 tests in 32 containers, zero failures/skips. F native CI remains pending.
- Added pure, fail-closed JSON-ready audit validator for 2.6.4-D read-only reconciliation and optional 2.6.4-E PST identity stability evidence; strict RunId/OperationId correlation, safety flags, controlled crash-barrier classification and privacy-limited output.
- Added opt-in read-only diagnostic CLI invoking existing 2.6.4-D fresh Outlook recovery scan, no MailMove or journal mutation; it reports evidence but cannot prove Move correctness or production readiness.
- Added four-window diagnostic evidence coverage, but ProductionReady remains false unconditionally pending REAL isolated Outlook crash/restart tests.
- Added 33 non-COM audit tests; full Windows CI target 442 in 33 containers, pending. Production Archive/Resume/Auto remain unchanged.

## 2.6.4-E (2026-10-23; test-only PST detach/reopen identity stability DEV)

- User-reported Windows PS5.1 CI PASS on 2.6.4-D: 381 tests in 31 containers; E has not yet passed Windows CI.
- Added disposable identity observation and fail-closed comparison of StoreID, FolderID, folder path and synthetic MailItem EntryID after reattaching two NEW PSTs.
- Added a separate triple-opt-in diagnostic CLI with durable one-shot identity-probe claim; refuses prior Worker operations, default Outlook stores, nonmatching or missing PSTs. Never deletes, retries, moves mail or rewrites journals.
- Added 28 synthetic no-Outlook Pester tests; target 409 tests in 32 containers. Real detach/reopen COM testing remains pending in a dedicated isolated Outlook test profile.
- Production Archive/Resume/Auto and FIX13b remain unchanged. Unicode PST AddStoreEx uses olStoreUnicode=2.

## 2.6.4-D (2026-10-23; independent read-only restart recovery DEV)

- User-reported 2.6.4-C Windows PowerShell 5.1 CI PASS: 358 tests in 30 containers; this does NOT validate the D source.
- Added an independent recovery-only STA CLI that attaches to already running Outlook, checks the two exact mounted disposable PSTs and scans source/target folders read-only.
- Added strict claim, barrier, journal and response identity checks with fail-closed classification. Does not retry Move, append a terminal event, mount/detach PSTs or terminate processes.
- Fixed B2 disposable fixture AddStoreEx parameter: 2 is olStoreUnicode; 3 is olStoreANSI, per Microsoft OlStoreType documentation.
- Added 23 offline recovery/regression tests; full Windows CI target is 381 in 31 containers, CI pending. No live Outlook COM experiment in this increment.

## 2.6.4-C (2026-10-23; controlled crash injection DEV)

- User-reported B2 Windows PS5.1 Pester PASS: 334 tests in 29 containers; C testing still pending.
- Added strict run-scoped, PID-correlated and durably flushed controlled crash barriers; parent may terminate only its own test Worker process.
- Supports opt-in AfterIntentBeforeDispatch, WorkerStartedBeforeMove, AfterMoveBeforeResponse and AfterResponseBeforeTerminal (diagnostic-report boundary; no journal terminal) windows. DuringMove is not deterministically injectable.
- Added 24 offline crash barrier tests: expected full Windows CI 358 tests in 30 containers. No live Outlook MailMove has been executed in C.
- Production WorkerProtocol, Archive, Resume and Auto remain unchanged on FIX13b; no retries or automatic journal completion.

## 2.6.4-B2 (2026-10-23; disposable fixture and owned-worker controller DEV)

- User-reported Windows PS5.1 Pester PASS on exact preceding 2.6.4-B increment: 320 tests in 28 containers, zero failures/skips; this does NOT certify B2.
- Added opt-in NEW two-PST fixture generator, synthetic test mail, durable single Intent and last-written scope marker. No production/user mail copied.
- Added parent-owned bounded test-only Worker controller with one-shot dispatch claim and fail-closed Indeterminate result. No retries, no Completed/Reconciled.
- Added 14 offline safety tests, target 334 tests in 29 containers. B2 Windows CI and real Outlook testing PENDING; no production routing changes.

## 2.6.4-B (2026-10-23; isolated test-only scope DEV; Windows CI pending)

- Added diagnostic-only WorkerTestMove.ps1: fixed run-unique TEMP PST scope, identity/fingerprint check, one verified Intent, durable one-shot claim, one MailItem.Move call.
- Added separate opt-in Windows PowerShell 5.1 STA test-worker entry point. The regular Worker allowlist, Archive/Resume/Auto and FIX13b remain unchanged.
- Added 16 new non-COM tests (target: 320 cases in 28 containers) and a safety runbook. Windows CI and live disposable-PST fixture gate are PENDING.
- This is a development ZIP only. Application version remains at 2.6.3-PREVIEW1 as an integration baseline, not a new 2.6.3 release.

## 2.6.4-A (2026-10-23; staged crash-protocol DESIGN ONLY)

- Added pure WorkerCrashProtocol.ps1: eight crash windows, safe correlation plans, timeline invariant checks and fail-closed read-only replay directives.
- Added 23 non-COM Pester tests: worker/journal timing, unknown outcomes, missing/corrupt journals, identity conflicts, no executable MailMove/Kill/journal write.
- Interim feature CI test count 304 in 27 containers. Application version remains at 2.6.3-PREVIEW1 solely as the 2.6.4-A integration baseline; do not publish this branch as a new 2.6.3 release.
- Does not change Worker protocol allowlist, archive/resume/auto integration, production FIX13b or operation-journal schemas. See docs/2.6.4-crash-window-protocol.md and GitHub Issue #4.

## 2.6.3-PREVIEW1 (2026-10-23; DEV, exact-source build gate pending Windows CI)

- Fixed false-positive restart read-only safety test: old raw-text negative regex matched a harmless `New-Object -ComObject` reference in a comment. New test inspects PowerShell CommandAst/InvokeMemberExpressionAst nodes instead; still forbids executable COM construction, PST store mutations, mail moves/copies/deletes, and operation-journal writes.
- User Windows CI of preceding source `053c37ef`: 280 tests passed and 1 test failed in 26 containers; CI correctly failed. Latest source requires a new full Windows CI and exact-source package verification.

- Hardened the project-only packager: a full Git SourceCommit must accompany an independently pinned SHA-256 of all packaged source file identities and bytes. Prevents mislabeled archives assembled from old extracted trees.
- CI now checks expected **26 containers and 281 tests** from `RELEASE.json`; added 3 source-integrity regression tests.
- Previous `gd4bc6974` ZIP was generated from older `g8e4be719` directory (272 tests/25 containers, 70 source files), therefore not verified as source commit `d4bc6974` despite its filename and SourceCommit metadata.

- 272 Pester tests in 25 containers passed for source `8e4be719`; user also verified all four real Outlook COM scenarios with disposable PSTs, two matching destination fingerprints, stable MailItem.Size=375442 and blocked retry.
- Added a standalone **read-only new-process replay** of the preserved journal and mounted source/archive PSTs with strict StoreID/PST/folder identities and unchanged SHA-256; six regression tests. This latest addition requires a fresh CI run.

- Added independent read-only MailMove Intent reconciliation with source/target snapshots, fingerprint and store/path validation.
- All outcomes fail closed with no automatic retry or journal mutation; legacy/partial Intents are not treated as proof.
- Added Pester tests for false duplicates, missing messages, incomplete MAPI enumeration and mismatched identities.
- Removed obsolete version-prefixed 2.6.2 design filename from active package; content retained under docs/OPERATION-JOURNAL.md.
- Corrected malformed MoveReconciliation test fixture: `EntryID` and `EntryId` are duplicate keys in case-insensitive PowerShell hash literals.
- Fixed critical CI false-positive: 229 tests passed but a Pester container could fail discovery while old CI printed PASS. CI now checks run Result, failed containers and blocks, discovered container count, and test parse errors.
- Added 12 CI release-gate regression tests, including a failed discovery container with zero failing It tests.
- Added an opt-in Outlook COM integration harness operating on two fresh, disposable PSTs, with a copied donor test message and four crash-window observation scenarios. The donor test PST can temporarily receive a copied message.
- Live Outlook test on prior commit: first three scenarios PASS (SourceOnly / DestinationCandidate / BothPresent) and MailItem.Size remained 375442 bytes across the first Move; Ambiguous FAIL because the second plain Copy() did not produce a second matching destination item. Changed diagnostic duplicate staging to Copy -> Move into disposable source -> Move back into disposable archive and added diagnostic snapshot/fingerprint counts. Needs re-test on Windows.
- Worker Move still disabled; FIX13b remains the production archive engine. Full PS5.1 CI required for each new revision.

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
