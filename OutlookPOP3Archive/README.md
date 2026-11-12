# OutlookPOP3Archive — 2.6.3-PREVIEW1

### ARCH3a — продолжаем существующий архиватор, а не создаём новый (DEV)

**[ADR ARCH3-001](docs/ADR-ARCH3-001-reuse-existing-archiver.md)** фиксирует обязательное архитектурное решение: сохранить существующий `OutlookPOP3Archive.ps1` и уже написанные `ArchiveGrouping` (Year/YearQuarter/YearMonth), `ArchivePlanner` (рекурсивные POP3 Inbox/Sent/пользовательские папки), `SystemFolders` (Outbox исключён), `MailMover` (годовые PST/лимиты/rollover), `ArchiveTransaction`, `OperationJournal`, `DuplicateIndex`, `ArchiveVerifier`. Проверенные ARCH2d5 claims, SHA-квитанции и независимую сверку **интегрировать в один исходный движок**, не писать третий архиватор. Уже реализованное семантическое сравнение в legacy `ArchiveVerifier` при `-RequireSemanticWitness` сохраняется; необходимо усилить сквозной приёмкой после перезапуска и безопасной работой с прерываниями.

[ARCH3a read-only аудит и пример маршрутизации](docs/2.6.5-arch3a-existing-pipeline-audit.md): `Invoke-ARCH3a.ps1 -Mode Plan`, `-Mode Audit`, `-Mode RoutingExamples -SourcePst <path>`. Ни один режим не открывает PST, не вызывает COM Move и не изменяет журналы. Массовый Archive/Resume/Auto и production permit по-прежнему закрыты.


### ARCH2d5 — проверяемая реальная партия из 100 писем, SHA-256 цепочка (DEV)

После успешного реального ARCH2d4 `10/10` — [операторский протокол ARCH2d5](docs/2.6.5-arch2d5-real-batch100.md). `Invoke-ARCH2d5.ps1` поддерживает Plan/Inventory/Prepare/MoveBatch/Evidence/Reconcile для **ровно 100 настоящих** писем существующего POP3 Inbox в **новый** PST назначения. Для каждого исходного письма заранее сохраняются SHA256 Body/HTML/получателей/состояния/байтов вложений, затем второй полный read-only preflight; перед каждым реальным COM Move — immutable force-flushed claim. SHA256 квитанции включается в следующую заявку; каждые десять писем завершаются checkpoint, затем создаётся финальная печать, чей **SHA256 оператор сохраняет независимо от PST** и передаёт для Reconcile. При любом сбое — STOP без повторного Move/Resume. `Evidence` читает лишь журналы; `Reconcile` проверяет архив после реального перезапуска Outlook. Старые ARCH2c4a/ARCH2d PST/заявки не изменяются. Массовый Archive/Resume/Auto остаётся заблокированным.


### ARCH2d4 — независимая read-only экспертиза завершённых и частичных партий (DEV)

После реального ARCH2d `10/10` добавлен [ARCH2d4 диагностический протокол](docs/2.6.5-arch2d4-readonly-forensics.md): `Invoke-ARCH2d4.ps1 -Mode Plan/Evidence/LiveAudit`. `Evidence` сверяет операторские SHA256 исходного manifest и batch claim, а также все десять индивидуальных заявок/квитанций, их SHA-связи, порядок и идентификаторы без Outlook. `LiveAudit` только читает уже подключённые PST через существующий Outlook и повторно сравнивает оригинальные Body, HTML, получателей, статус и SHA256 фактических байтов поддерживаемых вложений (кратковременные защищённые TEMP-копии). **Без** COM Move, Delete, Save, Copy, AddStoreEx и записи прежних доказательств. Неполные и повреждённые квитанции требуют ручной проверки; отдельные квитанции старого ARCH2d не имеют внешних исторических SHA pin, поэтому проверяется только их текущая внутренняя согласованность. Возобновление/повтор запрещены; массовые Archive/Resume/Auto остаются закрыты.


### ARCH2d3 — синтетические аварийные сценарии, без Outlook (DEV)

После реального ARCH2d `10/10` (RunId `23ee0a5b-4780-45a2-9ef6-e12992b418f4`) добавлен [ARCH2d3 тестовый протокол](docs/2.6.5-arch2d3-fault-injection.md): 57 сценариев (19 отказов × письма 1, 5, 10) с реальными force-flushed `CreateNew` журналами **только в отдельном синтетическом scratch-каталоге**, фальшивыми COM состояниями и обязательным `AutomaticRetryAllowed=False`. Проверяются обрывы до и после COM, частичные журналы, неоднозначность исхода, несоответствия семантических SHA-256. Основной ARCH2d и сохранённая фактическая партия не запускаются повторно; никаких новых реальных Move/PST в CI. `Invoke-ARCH2d3.ps1 -Mode Plan` только читает; для локального моделирования `-Mode Simulate -SandboxRoot <existing scratch>`. ARCH2d4 — будущая независимая классификация аварийных исходов; до неё 100-письменный production-тест не разрешён.


### ARCH2d — ограниченная партия из 10 реальных POP3 писем (DEV)

[Операторский протокол ARCH2d](docs/2.6.5-arch2d-bounded-real-batch10.md). Новый `Invoke-ARCH2d.ps1` выбирает строго 10 реальных писем `info@stios.ru.pst\Входящие`, сохраняет исходный SHA256 Body/HTML/Recipients/State/байтов вложений, создаёт один новый **целевой архивный** PST, фиксирует глобальный batch claim и отдельный force-flushed claim **до каждого** реального `MailItem.Move()`. `MoveBatch` запускается ровно один раз; при любой ошибке останавливается без retry, весь результат независимо проверяется после перезапуска Outlook. Успешный ARCH2c4a RunId и его файлы не используются и не изменяются. Основные режимы `Archive/Resume/Auto` запрещены. CI не означает готовности к 90 ГБ.


### ARCH2c4a — hotfix загрузки зависимостей

Исправлена обнаруженная при реальном `Prepare` ошибка `Get-OPAInternetMessageId is not recognized`. Операторский `Invoke-ARCH2c4.ps1` теперь загружает исходные `Core/Runtime/ComManager.ps1` и `Core/Archive/ArchiveSelector.ps1` *до* `ARCH2bSemanticWitness.ps1`. Добавлена интеграционная регрессия, вызывающая реальный исходный семантический witness с эмуляцией существующего Unicode-письма и вложения. При ранее наблюдавшемся исключении код завершался **до** создания PST, намерения и Move: RunId `18585296-c1f6-4859-97d1-1f9d272b9e07` можно сохранить после read-only проверки отсутствия артефактов. Основной Archive/Resume/Auto закрыт. См. [runbook ARCH2c4](docs/2.6.5-arch2c4-real-pop3-one-shot.md).


## ARCH2c4 — один реальный перенос из POP3 Inbox (строго DEV)

[Пошаговый операторский протокол ARCH2c4](docs/2.6.5-arch2c4-real-pop3-one-shot.md). В отличие от ARCH2c3, источник — существующий `info@stios.ru.pst` и выбранное реальное письмо. Предыдущие удалённые BW4k test PST не требуются. Новый отдельный PST создаётся только **как архив результата**, с неизменяемой заявкой, свежим SHA-256 Body/HTML/Recipients/вложений и единственным разрешённым `MailItem.Move()`. После перезапуска Outlook — только независимая read-only сверка. Есть глобальная заявка, запрещающая вторую попытку даже с новым RunId. Основной `Archive/Resume/Auto` по-прежнему закрыт. Поддержка этого одноразового эксперимента не означает готовность 90 ГБ архивации.


## ARCH2c3 — реальный Outlook COM: одноразовый PST, только чтение

Подготовлен [операторский протокол ARCH2c3](docs/2.6.5-arch2c3-disposable-com-probe.md): `Plan` без Outlook, `Inventory` уже смонтированного изолированного PST, `Probe` одного синтетического by-value вложения через реальный `Attachment.SaveAsFile` в приватном TEMP (ARCH2c2) с независимой SHA-256 проверкой, и `PostRestartProbe` после реального перезапуска Outlook. Нет подключения/создания PST, MailItem.Copy/Move/Delete/Save и удаления источника. **CI не имеет Outlook и не выполняет реальный COM**: DEV, целевые 3804 теста/128 контейнеров. `Archive`, `Resume`, `Auto` запрещены ARCH2a до отдельной приёмки.


## ARCH2c2 — защищённые временные файлы и эксклюзивная lease (DEV)

[ARCH2c2 runbook](docs/2.6.5-arch2c2-private-acl-lease.md). Основной witness вложений использует каталог с приватным Windows DACL, созданным атомарно, и временную `.opa-lease` с `FileShare.None`. При обычном завершении каталог очищается **без рекурсии**; для аварийных остатков существует только read-only инвентаризация с `LeaseState`, не автоматическое удаление. Это подэтап ARCH2c с синтетическими проверками (цель: 3778 тестов/127 контейнеров). Нет реального Outlook/PST CI, нет разрешения на production. `Archive`, `Resume`, `Auto` остаются заблокированы защитой ARCH2a.


## ARCH2c1 — временные копии вложений изолированы (DEV / NO WRITER)

Новый подэтап ARCH2c1: [runbook](docs/2.6.5-arch2c1-temp-isolation.md). Изменён реальный `Core/Archive/ARCH2bSemanticWitness.ps1`: каждая проверка содержимого вложений использует собственный GUID workspace в TEMP, при обычных исключениях удаляет копии и **нерекурсивно** удаляет пустой workspace. Добавлена read-only инвентаризация workspace, которые могли остаться после аварии; автоматического удаления чужих/активных/непроверенных каталогов нет. Реальный Outlook COM и crash/restart еще не сертифицированы. `Archive`, `Resume`, `Auto` остаются закрыты защитой ARCH2a, включая `-WhatIf`.


## ARCH2b — встроенная в основной архиватор проверка содержимого (DEV)

**Текущая линия 2.6.5-ARCH2b:** [полный runbook](docs/2.6.5-arch2b-semantic-verifier.md). Теперь оригинальный `MailItem` получает pre-Move свидетельство (Subject, адреса/Recipients, Body/HTMLBody, даты, UnRead и SHA256 байтов вложений), которое записывается в `Move Started` до COM. `ArchiveVerifier.ps1` независимо сверяет целевой PST с исходным witness, а `MailItem.Size` хранится только диагностически. Это **встраивание ранее проверенного BW4j/BW4k подхода**, не новая MAPI-форензика. Неподдерживаемые вложения и отсутствие оригинальных хешей блокируют проверку.

**ВНИМАНИЕ:** `Archive`, `Resume`, `Auto` в этом DEV-билде всё ещё **заблокированы** защитой ARCH2a; не отключать guard и не запускать на 90 ГБ до живого disposable PST acceptance. `Attachment.SaveAsFile` использует временный файл для чтения бинарных байтов; авария может оставить временную копию вложения. Следующий шаг ARCH2c — контролируемый полный интеграционный тест, cleanup и recovery.



## ARCH2a — защита основного Move/Resume от неоднозначного COM-исхода

**Новый DEV-билд 2.6.5-ARCH2a:** [описание и ограничения](docs/2.6.5-arch2a-move-outcome-fence.md). Это реальное изменение основного `MailMover.ps1`: завершение batch при исключении `MailItem.Move()`, надёжная запись `Move Started` до COM, `Move Indeterminate` вместо `Skipped`, отказ от `Resume` по неполному/неоднозначному original journal. До интеграции полного семантического verifier в ARCH2b режимы **`-Mode Archive`, `-Mode Resume`, `-Mode Auto` заблокированы на входе**, включая `-WhatIf`. Existing `Analyze` / `Plan` остаются доступны. Это **не production RC** и **не разрешение архивировать 90 ГБ**. Не удалять этот guard ради обхода.

Восстановление контекста проекта: [PROJECT-HANDOFF-ARCH1](docs/PROJECT-HANDOFF-ARCH1.md), [ADR COM boundary](docs/ADR-ARCH1-OUTLOOK-COM-BOUNDARY.md), [DELIVERY-ROADMAP](docs/DELIVERY-ROADMAP.md). Никакого нового BW4k7v2a9 из-за необъяснённого `MailItem.Size` или `PR_MESSAGE_FLAGS`.



## Обязательное направление после BW4k7v2a8: ARCH1, не продолжение MAPI форензики

**ПЕРЕД СЛЕДУЮЩИМ БИЛДОМ:** читать [постоянный handoff](docs/PROJECT-HANDOFF-ARCH1.md), [ADR COM boundary и stop-rule](docs/ADR-ARCH1-OUTLOOK-COM-BOUNDARY.md), [roadmap до RC](docs/DELIVERY-ROADMAP.md) и [фактический аудит основного кода](docs/ARCH1-IMPLEMENTATION-AUDIT.md). При потере контекста **не возвращаться к новым BW4k7v2a9 и исследованию Size/FLAGS без конкретной потери пользовательских данных**. Функциональный следующий этап — ARCH2: отладка основного `MailMover.ps1`, исключение неоднозначного silent skip и интеграция уже имеющихся семантических проверок в `ArchiveVerifier.ps1`.

**Важно:** по существующему коду есть прямой режим `-Mode Archive`, который вызывает `MailItem.Move()` и может менять письма даже при `RELEASE.Integration.ArchiveWorkerEnabled=false`. ARCH1 только читает код, не разрешает production. Это **отдельная внешняя DEV-сборка 2.6.5-ARCH1**, но внутренний `Core/Version.ps1` / `RELEASE.Build=2.6.3-PREVIEW1` пока сохраняется ради совместимости существующих тестов; синхронизация внутреннего build — отдельная задача перед RC.

**Read-only аудит:**
~~~powershell
.\Core\Diagnostics\Invoke-OPA265ARCH1DeliveryReadinessAudit.ps1 -Mode Plan | Format-List
$arch1 = .\Core\Diagnostics\Invoke-OPA265ARCH1DeliveryReadinessAudit.ps1 -Mode Audit
$arch1.Readiness | Format-List *
$arch1.Readiness.AuditRows | Format-Table -AutoSize
~~~



Application: `0.9.4-rc1-build2.6.3-PREVIEW1`. Target: Windows PowerShell 5.1, Outlook 2016/2019.

**Status:** 2.6.3-PREVIEW1 development candidate: read-only interrupted Move reconciliation; CI pending. Production `Archive`, `Resume`, `Plan` and `Auto` still use the existing FIX13b Outlook COM code. Mail movement is **not delegated** to a worker. Keep FIX13b as the tested archiving baseline.

**New diagnostic BW4k7v2a1 (existing Outlook test profile):** For a one-item pilot without a second Outlook profile, see [existing-profile runbook](docs/2.6.5-bw4k7v2a1-existing-profile-pilot.md). The script attaches one new Unicode disposable PST to the existing `Outlook` POP3 profile and creates one item only in an explicitly identified folder. Requires exact approval; no old PST writes, no Move/Send/Delete, no production worker.

**NEW BW4k7v2a2 read-only forensic diagnostic:** The real BW4k7v2a1 test returned a post-save target-identity mismatch for suite `2c15cb7c-4c09-4bcf-bca1-9fec458af3a5`; this does not identify the original predicate or prove a wrong PST. Do not retry its CreatePilot. [Read-only forensic runbook](docs/2.6.5-bw4k7v2a2-failed-pilot-readonly-forensics.md) reads only the named disposable test PST folder and original intent, never saves, mounts or moves mail.

**NEW BW4k7v2a3 read-only Drafts forensic:** The previous BW4k7v2a2 real Outlook test proved zero messages in the expected disposable test PST folder, while the first MailItem.Save had returned without error. [Exact-subject existing-Store Drafts runbook](docs/2.6.5-bw4k7v2a3-drafts-location-readonly.md) searches only the failed SuiteId synthetic Subject in currently mounted store-specific Drafts folders; it never writes, mounts, retries or scans unrelated mail content.

**BW4k7v2a4 DEV (single synthetic one-shot Move experiment):** After the prior BW4k7v2a3 read-only diagnosis found the original test letter in default Drafts, this new [two-consent one-shot Move runbook](docs/2.6.5-bw4k7v2a4-one-shot-move.md) creates a **new** GUID-scoped disposable PST and **one new synthetic default Draft** (which can sync to IMAP), records a SHA256-sealed original content witness, then requires a separate explicit approval and writes a durable claim **before one** MailItem.Move. Old test fixture and original POP3 mail never selected; no retries; production Archive/Resume/Auto still disabled.

**NEW BW4k7v2a5 read-only failed CreatePilot count forensics:** Operator BW4k7v2a4 `CreatePilot` failed after an actual MailItem.Save and verified parent StoreID/FolderID, inside combined `source.Count == 1 && target.Count == 0` assertion. The original SuiteId `7451b8f5-6404-4496-ae7b-5b1cdfb9063a` is quarantined; [new original-suite numeric Restrict-vs-manual count diagnostic](docs/2.6.5-bw4k7v2a5-failed-createpilot-count-readonly.md) performs only read-only, bounded direct Subject enumeration of existing default Drafts and exact disposable PST test folder. No original attempts or messages replayed, created, moved, or deleted.

**BW4k7v2a6 read-only semantic Body investigation:** The live BW4k7v2a5 operator output conclusively found the original new synthetic Draft with correct source and destination cardinalities but `BodyMatchesExpected=False`. New [pinned original-suite read-only Body integrity forensic](docs/2.6.5-bw4k7v2a6-body-integrity-readonly.md) compares deterministic expected Body with SHA-256, UTF-8 byte lengths, CR/LF patterns and two MAPI readbacks. It never prints observed Body or signatures, never writes Outlook or moves any mail. Any Body mismatch remains a SEM-001 blocker, not a move waiver.

**BW4k7v2a7 DEV new one-time synthetic Outlook Move:** The real BW4k7v2a6 result found an exact 82-byte source template prefix plus a 3-character whitespace suffix after `MailItem.Save()`, with stable twice-read actual Body SHA256. [New isolated one-shot runbook](docs/2.6.5-bw4k7v2a7-postsave-synthetic-baseline.md) captures the actual post-Save Body as immutable pre-Move witness via EntryID (not immediate Items.Restrict), allows only narrow known three-character synthetic fixture suffix, and independently checks source-one/target-zero before separate operator-approved Move. Old Suites preserved; SEM-001 not waived; production remains disabled.

**BW4k7v2a8 original one-shot MAPI attachment forensics:** Actual operator BW4k7v2a7 cross-store `MailItem.Move()` from new test Drafts to disposable PST succeeded and independently reconciled after Outlook restart (source 0, destination 1, full tested semantic content SHA preserved). **PR_MESSAGE_FLAGS 9 → 25** (only `MSGFLAG_HASATTACH` bit 0x10 changed), **MailItem.Size 1952 → 2076** (+124 bytes), so SEM-001 remains blocked. [New read-only original-fixture diagnostic](docs/2.6.5-bw4k7v2a8-readonly-attachment-attribution.md) pins original manifest/claim/return SHA hashes and destination EntryID, checks `PR_HASATTACH`, actual `Attachments.Count`, optional hidden/method flags and `PR_MESSAGE_SIZE` without exposing attachment names, file bytes or email bodies. No Move/retry, no PST write, no source attachment inventory invention, no production worker.

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

## BW4d DEV: read-only prior LIVE3/LIVE4 replay fence

Use the explicit `-WorkerPilotReviewHistoryReplay` opt-in route to compare the BW4c exact MailItem readback with the available bounded LOCAL TEMP LIVE3/LIVE4 operation journals. Prior synthetic IDs remain blocked even if the journal is missing. Zero matches is not Move permission; no production Worker or historical writer. See [BW4d guide](docs/2.6.5-bw4d-history-replay-readonly.md).

## BW4d1 Outlook folder ID diagnostics (DEV hotfix)

The same explicit -WorkerPilotReviewHistoryReplay route now compares hexadecimal Outlook EntryIDs and StoreIDs without hex-letter-case false negatives, and distinguishes folder identity failures precisely. It does not fall back to another store or allow a Move. See [BW4d1 guide](docs/2.6.5-bw4d1-folder-id-hotfix.md).

## BW4e read-only fresh synthetic candidate evidence (DEV)

The explicit `-WorkerPilotReviewFreshSynthetic` route re-reads an already selected, NEW disposable synthetic test mail and cross-checks exact prior BW4c InternetMessageId, PR_SEARCH_KEY SHA256 and content-field SHA256, then invokes BW4d replay-history quarantine. It never proves complete history, issues a Move permit, or enables production Worker. See [BW4e guide](docs/2.6.5-bw4e-fresh-synthetic-premoval-readonly.md).

## BW4e1 DEV read-only -Review switch hotfix

The BW4e diagnostic no longer overwrites the case-insensitive `[switch]$Review` parameter with its PSCustomObject BW4d result. Use the same `-WorkerPilotReviewFreshSynthetic` command from BW4e; a previously used LIVE3 item is correctly blocked. See [BW4e1 guide](docs/2.6.5-bw4e1-review-switch-collision-hotfix.md). No journal writes, Worker, retry or Move.

## BW4e2 DEV: targeted read-only MAPI lookup in large POP3 Inbox

For an Inbox larger than 5000 messages, do NOT increase the original full-enumeration limit. The explicit `-WorkerPilotUseTargetedMessageIdReadOnly` switch replaces the second read path with exact `Items.Restrict` on the already observed MAPI InternetMessageId, requires exactly one match and preserves BW4d/BW4e historical no-Move rules. See [BW4e2 procedure](docs/2.6.5-bw4e2-targeted-large-folder-readonly.md). Outlook support must be checked locally; CI alone does not authorize Move.

## BW4f exact disposable test fixture scope (read-only DEV)

The opt-in `-WorkerPilotReviewFreshFixtureScope` route requires exact operator-created test subject/body GUID, no attachments and both BW4e2 Outlook read paths with preserved BW3a and LIVE3/4 evidence. A positive match is **never** a Move permit; production Archive/Resume/Auto Worker remains disabled. See [BW4f procedure](docs/2.6.5-bw4f-exact-fresh-fixture-scope-readonly.md).

## BW4g — DEV-only explicit disposable one-shot cross-PST Move

Separate native PowerShell 5.1 STA script `Core/Diagnostics/Invoke-OPA265BW4gOneShotDisposableMove.ps1` accepts read-only `-Review` and an explicitly approved `-Execute -ConfirmOneShotDisposableMove`. Runs BW4f + BW4e2 + BW4d original historical checks, requires a new empty GUID-named disposable PST/folder and writes a durable no-retry claim before one `MailItem.Move`. Production Archive/Resume/Auto Worker stays disabled. See [BW4g instructions](docs/2.6.5-bw4g-one-shot-disposable-move.md).

## BW4g1 — isolated one-shot disposable Move (BW4f3 merged)

BW4g1 integrates locally verified BW4f3 exact trailing-space test fixture recognition into the isolated BW4g experimental one-shot cross-PST Move controller. `-Review` is read-only. `-Execute -ConfirmOneShotDisposableMove` writes an immutable once-only user claim BEFORE one `MailItem.Move`, with no automatic retry, no historical journal updates or production Worker activation. Use only a NEW empty test PST and the exact operator synthetic GUID. See [BW4g1 usage](docs/2.6.5-bw4g1-merged-one-shot.md).

## BW4h — independent read-only post-Move reconciliation

After one confirmed BW4g1 `MailItem.Move` return, run BW4h to hash and validate the persistent claim, recheck original BW3a Intent and seven evidence files, independently verify zero source and exactly one destination message, and compare pinned identity/fingerprints. Any size/content or SearchKey drift requires manual review; **never retry Move** or modify the original historical journal. See `docs/2.6.5-bw4h-independent-move-reconciliation.md`.

## BW4h1 — diagnostic-only MAPI Size vs content drift

After BW4h confirms zero source/one destination but reports `MoveObservedButMAPIFieldFingerprintDriftNeedsManualReview`, BW4h1 re-runs all read-only historical and claim checks, recomputes exactly the five-field BW4c SHA256, and scans a bounded ±256 observed `MailItem.Size` window to test whether only message size explains the hash mismatch. No Move, no acceptance record or journal writes, and no source byte-equality claim. See `docs/2.6.5-bw4h1-field-drift-readonly.md`.

## BW4h2 — durable before/after field evidence for FUTURE disposable moves

BW4h2 has a separate opt-in SourceReview, one-shot SourceCapture and read-only DestinationCompare. Capture a new disposable fixture **before** any BW4g Move claim: Size, per-field SHA256 for Subject/Sender/Body/ReceivedUtcTicks and overall five-field content SHA256. The write-once file is stored only under per-user AppData, not in source PST or historical journals. After a separately authorized Move, DestinationCompare requires its independently preserved SHA256 pin and exact old BW4g claim and reports content-vs-MAPI-size drift without ever retrying Move. Already-moved BW4g1 TestId cannot be retrospectively captured. See `docs/2.6.5-bw4h2-durable-five-field-evidence.md`.

## BW4i — exact disposable one-fixture controlled Size drift acknowledgment

BW4i never runs MailItem.Move. For existing TestId `841545a1-b5fa-4c69-964a-8c0318981d52`, an explicit read-only `Review` re-runs BW4h2 source-zero/destination-one, individual Subject/Sender/Body/ReceivedTime SHA256 and known exact `8760 → 8798` bytes with pinned pre-Move source and irreversible attempt claim. Only a separately explicit `Accept -ConfirmExactSizeDrift` can create a per-user immutable manual acknowledgment JSON; `Verify` requires independently saved decision SHA256 and re-audits. The acknowledgment is not journal reconciliation, a general Size waiver, byte-for-byte proof or production authorization. See `docs/2.6.5-bw4i-exact-size-drift-acknowledgment.md`.

## BW4j — multi-format synthetic suite (DEV safety foundation)

BW4j adds `NewPlan`, `SourceReview`, `SourceCapture`, `DestinationReview` for five fresh disposable messages including Cyrillic, HTML and 1 KiB / 256 KiB attachments. SHA256 is computed independently for plain body, HTML body and attachment bytes. The suite and each source witness are saved once, never overwritten. The full source-zero/target-one read-only comparison is available after a **separately authorized** move. No automated sending, draft generation, new multi-message one-shot Move controller or crash/resume batch automation is enabled in this build. Original BW3a journal and prior BW4g/BW4i witnesses remain quarantined. See `docs/2.6.5-bw4j-multiformat-suite-readonly.md`.

## BW4j6 — GitHub Actions isolated synthetic engine (experimental)

Checkpoint branch `checkpoint/outlookpop3archive-2.6.5-bw4j-ci-pass-g5e458c92` pins previous BW4j (commit `5e458c921aa3c1aaf9aad5cc4bc124984d788cd5`). This BW4j6 branch adds synthetic-only one-shot move claims, independent SHA256 receipts and five-item summary, crash injection and fail-closed never-retry. Its mandatory matrix runs only on GitHub Actions Windows PS5.1 runner; no Outlook COM or PST accessed. Synthetic +38 Size delta is a hypothesis based on prior two real mails, not empirical evidence for HTML/attachments/large mail. Final real Outlook testing requires a separate gated build after CI and manual confirmation. See `docs/2.6.5-bw4j6-synthetic-ci-rollforward.md`.

## SEM-001 — Outlook-standard logical-message preservation (normative requirement)

**Effective 2026-11-02.** Archive complete Outlook MailItem objects by supported COM/MAPI operations, **not** by byte-identical PST or all-MAPI-property copying. A changed `MailItem.Size`/`PR_MESSAGE_SIZE` is a separate diagnostic signal and cannot alone reject or approve an archive. Completion requires independent source-zero/target-one verification plus content (subject/sender/recipients, plain/HTML, headers, dates/class, important read/status flags) and **attachment bytes SHA-256**. Outgoing POP3 **Sent Items** and user folders must be preserved in yearly archive PSTs with safe size-aware rollover. Never automatically retry `Move` after an attempt claim/crash; keep journal and original witness immutable. Physical shrinking/Compact is independent of successful logical archival.

BW4k7a real `Attachment1K` source size changed **8122 -> 8634 (+512)**, while both live reads verified the exact 1024-byte attachment SHA-256 and all other BW4j witness fields; **no Move, Claim, size waiver or production permit**. BW4k7b adds a read-only semantic integrity policy, **not** a generic waiver or executable archival worker. Requirements: [technical specification](docs/TECHNICAL_SPECIFICATION.md), [SEM-001 normative policy](docs/SEMANTIC-INTEGRITY-POLICY.md), [architecture](docs/ARCHITECTURE.md), [testing](docs/TESTING.md).

## BW4k7c — isolated +512 source-size manual acknowledgment (DEV only)

[Runbook](docs/2.6.5-bw4k7c-exact-source-size-decision.md). Adds strict `Review` / explicit-once `Accept` / independent `Verify` for the already documented original `Attachment1K` source `8122 -> 8634` (+512 bytes). Requires immutable original five-source witnesses and all three past Move Claims, verifies full existing BW4k7b source semantic evidence twice before optional separate UTF-8 BOM CreateNew / Flush(true) SHA256 decision record. `-WhatIf` makes no decision write. **No source witness reset, journal writer, global size waiver, MailItem.Move, auto-retry, or production enablement.**

## BW4k7d — read-only recipient/flags evidence

[Runbook](docs/2.6.5-bw4k7d-recipients-flags-readonly.md). Exact previously accepted Attachment1K decision SHA `29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6` verified before/after. Outlook recipients and significant user state hashed via two read-only witnesses, never Move, Capture, journal write, existing decision rewrite, or production.

## BW4k7e — immutable semantic source snapshot (DEV)

[Runbook](docs/2.6.5-bw4k7e-immutable-semantic-source.md). Adds new separate original recipient and user-state SHA256 snapshot only, pinned to verified BW4k7c size decision and BW4k7d two Outlook source reads. `Review` and `Verify` only read; explicit operator-once `Capture` writes BOM JSON CreateNew/Flush(true), never modifies existing original source witnesses/Claim/journals or executes Move. No production enablement.

## BW4k7f — pre-existing empty target PST read-only gate

[Runbook](docs/2.6.5-bw4k7f-empty-target-no-move.md): exact original Attachment1K source-one/target-zero, two independent BW4k7e immutable source snapshot verifications and existing uniquely mounted empty disposable PST/folder. No target creation/mount, no claim or MailItem.Move, no retry or production. Verified semantic snapshot SHA-256 `fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac`.

## BW4k7g — test-only Attachment1K one-shot Move and independent post-Move audit

[Runbook](docs/2.6.5-bw4k7g-one-shot-attachment-move.md). Re-verifies BW4k7f and exact immutable BW4k7c (+512) and BW4k7e (recipients/state) source evidence. `Review` and `Execute -WhatIf` are read-only; only an independently and explicitly operator-approved `Execute` may durably create one irreversible SHA-256 Claim in the existing BW4k1 claim location, then invoke exactly one Outlook MailItem.Move. Never retry an attempted Move. Separate independent read-only postmove source-zero/destination-one, To/Cc/Bcc/user-state/body/attachment SHA audit. Not production-ready.

## BW4k7h — read-only post-Move raw MAPI flags vs Outlook user-state attribution

[Runbook](docs/2.6.5-bw4k7h-postmove-state-attribution.md): user-reported BW4k7g real disposable Attachment1K postmove audit has source=0/destination=1; complete body, recipient and attachment SHA match but **FullUserStateSha256Matches=False**. BW4k7h independently rechecks the *immutable* original BW4k7e SHA and irreversible BW4k7g Claim, recomputes archived user's exact ten COM state fields and MAPI flag digest, and substitutes **only original PR_MESSAGE_FLAGS=65555** to isolate a raw-provider-flag change. No automatic semantic waiver, no Move/Claim write or retry, no production.

## BW4k7i — read-only archived mail integrity after true Outlook restart

[Runbook](docs/2.6.5-bw4k7i-reopen-integrity-readonly.md). Original disposable Attachment1K real Move Claim and its postmove content/recipient SHA comparison remain immutable; full raw MAPI flags changed from 0x00010013 to 0x00000011. Known MSGFLAG_UNMODIFIED=0x00000002 is a storage modification-state bit, but 0x00010000 remains unknown and **not waived**. New Review/Capture/VerifyAfterReopen diagnostic stores ONE separate UTF8-BOM immutable evidence baseline (FileMode.CreateNew+Flush(true)) and requires a truly new OUTLOOK.EXE StartTime before repeating read-only source-zero/target-one, body/attachment/recipients/user-state audit; never repeat Move or enable production.

## BW4k7j — read-only PR_MESSAGE_FLAGS documented vs unresolved bit investigation

[Runbook](docs/2.6.5-bw4k7j-mapi-flag-investigation.md). Microsoft [MS-OXCMSG] defines `mfUnmodified=0x00000002` for `PR_MESSAGE_FLAGS`, but the **different-property** constant `STORE_HTML_OK=0x00010000` cannot identify the unknown `PR_MESSAGE_FLAGS` bit `0x00010000`. The exact original Attachment1K archive and immutable Claim/BW4k7i reopened baseline SHA are verified again, all changed bits classified individually with no automatic waiver. **No Move, Capture, Claim edits, producer, or production permit.**

## BW4k7v2a read-only pristine test-PST precreation gate (DEV)

BW4k7v2a adds an Outlook-visible, bounded read-only inventory of every folder in the exact account-free dedicated test PST before the one permitted pilot is created. Any existing item or incomplete scan blocks the pilot; the original failed old PST/working-profile Draft remains quarantined. No production Archive/Resume/Auto or MailItem.Move permission. See [BW4k7v2a guide](docs/2.6.5-bw4k7v2a-pristine-inventory.md). CI target: 3370 tests / 114 containers (Windows PowerShell 5.1).
