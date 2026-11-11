# НАЧНИ ЗДЕСЬ — OutlookPOP3Archive: контекст и запрет повторять MAPI-исследования

**CURRENT DELIVERY BUILD: ARCH2a**, см. [no-blind-retry/mutating-mode closure](2.6.5-arch2a-move-outcome-fence.md). После ARCH1 аудита оператор подтвердил **3660 tests / 123 containers PASS**, `LegacyMoveFailureContinuePatternDetected=True`, `LegacyVerifierIncludesFullBodyHtmlAttachmentWitness=False`. ARCH2a **исправляет основной COM-exception catch**: `Move Started` durable checkpoint/flush перед COM; `Move Indeterminate` и STOP при исключении; full-journal unresolved claim блокирует Resume. Основные CLI writer modes Archive/Resume/Auto **закрыты даже с -WhatIf**, пока ARCH2b не интегрирует полный content/attachment verifier. Не использовать более старый ARCH1 handoff как доказательство, что старый `MoveFailed` catch всё ещё существует в ARCH2a — это исторический результат на исходнике ARCH1. Не считать его исправление доказательством общей production готовности.

**СЛЕДУЮЩИЙ ШАГ:** ARCH2b — интегрировать уже проверенные BW4k semantic+attachment-byte witnesses в реальный основной `ArchiveVerifier.ps1` и всю Archive/Resume последовательность; затем новый изолированный end-to-end набор. Не создавать отдельную ветку исследования флагов MAPI.



**Актуально с 2026-11-11.** Это главный handoff-файл проекта. Читать ПЕРЕД созданием следующей ветки или плана. **Ветка разработки после BW4k7v2a8 — ARCH, не BW.** Редактировать файл после значимых интеграционных результатов.

## Цель пользователя

Рабочий **Windows PowerShell 5.1 / Outlook 2019 COM** архиватор приблизительно **90 ГБ POP3-почты**, группировка по годам (2025, 2024, 2023 и т.д.) в Unicode PST; сохранить иерархию Inbox, Sent данного POP3-аккаунта и пользовательских папок; исключить Outbox и иные выбранные служебные папки; журнал/возобновление, выявление дубликатов, идемпотентность, `-WhatIf`, безопасность содержимого и вложений; корректный лимит размера/части PST. Рабочая версия для долгого использования, не бесконечные эксперименты.

**Правила:** все новые/изменённые PowerShell-файлы строго UTF-8 BOM `EF BB BF` (с неизменяемым legacy-исключением), Windows PowerShell 5.1 в GitHub Actions, PSScriptAnalyzer + Pester, JSON release gates, архив ZIP **только с OutlookPOP3Archive**, commit hash в ZIP, SHA-256, checkpoint. Не утверждать полноту CI-реальных Outlook тестов: GitHub Actions не содержит Outlook/MAPI mailbox.

## Уже сделано — не переделывать заново

- BW4j набор из **пяти** типов: `PlainSmall`, `UnicodePlain`, `HtmlBody`, `Attachment1K`, `Attachment256K`. Все пять исходных snapshot/witness проверены; реальные Move для первых **четырёх** и независимая сохранность проверяемого контента; **Attachment256K не имеет подтверждённого реального Move**. Повторять эти четыре однократных Move запрещено.
- BW4k7g/i: `Attachment1K` реальный Move, исходник 0, цель 1, проверены 1024 байта и SHA-256 вложения, HTML/body и получатели. Незнакомый изменившийся `0x00010000` не классифицирован как безопасный; это **не** повод начать новую бесконечную ветку.
- BW4k7p/q/r/s/u: POP3 область определялась read-only. Было **26605** Inbox объектов (26602 MailItem и 3 других типа), предварительно **21985** подходящих писем 2020–2025, **4617** писем 2026 оставлялись вне предложенного архива. Не-MAIL элементы `Report.IPM.Note.NDR`, `Report.IPM.Note.IPNRN`, `IPM.Schedule.Meeting.Request` нельзя автоматически терять. Sent POP3 ранее пуст; 144 Sent в ином хранилище не переносить без явного выбора аккаунта. Это **историческая** инвентаризация, не актуальная live count.
- BW4k7v2a6/a7: Outlook добавлял три пробельных символа при **первом Save** нового синтетического Draft. Фактически сохранённое письмо было закреплено как эталон **до Move**. Последующий реальный `SuiteId=1a6683eb-3136-46eb-a1a8-ed8ece33b52c` Move прошёл: source 0, target 1, семантический SHA совпал после нового OUTLOOK.EXE. `MailItem.Size` 1952→2076, `PR_MESSAGE_FLAGS` 9→25 (0x10 HASATTACH). Production не разрешён.
- BW4k7v2a8 — только read-only forensic уже перемещённого письма. **Ничего не перемещать повторно; не создавать BW4k7v2a9 ради +124 байт.**
- Исторические SuiteId, в частности `7451b8f5-6404-4496-ae7b-5b1cdfb9063a` и `1a6683eb-3136-46eb-a1a8-ed8ece33b52c`, и их claims/evidence неизменяемы. Все повторы `CreatePilot` после failed Save/intent и `MovePilot` после claim запрещены.

## Критический факт исходного кода (ARCH1)

`Core/Archive/MailMover.ps1` — существующий основной механизм `$item.Move($dest.Folder)`, **в обработчике COM-ошибки регистрирует `MoveFailed` и продолжает цикл**. Это требует аудита неоднозначного исхода Move. Существующий `Core/Archive/ArchiveVerifier.ps1` проверяет identity/fingerprint, но не имеет полной проверенной сравнительной схемы `Body`, `HTMLBody` и SHA-256 байтов вложений. Годовая группировка уже есть в `Core/Archive/ArchiveGrouping.ps1`, но CLI default `-ArchiveGrouping YearQuarter` и `-MaxArchivePstSizeGB 10`; нельзя объявлять годовой production архив реализованным только по наличию функции `Year`. Журналы и дедупликация реализованы в исходном коде, их end-to-end safety ещё надо подтвердить.

`RELEASE.json` по-прежнему хранит внутренний `Build=2.6.3-PREVIEW1` и `Integration.ArchiveWorkerEnabled=false`, `ResumeWorkerEnabled=false`, `AutoWorkerEnabled=false`. **Это НЕ гарантирует, что legacy CLI `-Mode Archive` не может модифицировать сообщения. НЕ запускать на реальном 90GB PST без отдельного safety gate.** `2.6.5-ARCH1` пока означает внешнюю DEV упаковку/аудит, а не промоушен основного runtime.

## Как принимать решения, если контекст потерян

1. **Не повторять пять отдельных тестов и не исследовать MAPI Size/Flags заново.** Читай [ADR](ADR-ARCH1-OUTLOOK-COM-BOUNDARY.md). Ни одно изменение системного байта само по себе не доказывает порчу. Значимые пользовательские свойства и бинарные вложения проверяются обязательно; неизвестный риск не снимается автоматически.
2. **Следующая задача ARCH2 — основной код, не очередной diagnostics-файл.** Привести legacy Move exception handling к строгому протоколу claim/indeterminate/reconcile/no blind retry, интегрировать уже существующие BW4k semantic witnesses с основным ArchiveVerifier, обеспечить end-to-end проверку. **Выбор между Move и Copy/Verify/Delete — архитектурное решение ПОСЛЕ контролируемого safety-теста; копия не делает операцию атомарной.**
3. Далее архивирование по годам с правильным POP3 Sent и пользовательскими папками, лимиты Unicode PST/части, resume после аварий и маленький безопасный batch на disposable PST, потом RC.
4. Никогда не путать «запущено 3625+ Pester» с «проверен 90GB источник». Тестовый PST можно уничтожать только в специально оговорённых новых suite, **старые зафиксированные evidence оставлять**.
5. При любом новом MAPI drift формулировать: доказана ли потеря **пользовательского** содержимого, может ли наш код обойти её на уровне доступных COM API и какой конкретный критерий остановки/решения? Если нет — записать факт и вернуться к ARCH2.

**Порядок чтения:** этот файл → [ADR-ARCH1](ADR-ARCH1-OUTLOOK-COM-BOUNDARY.md) → [DELIVERY-ROADMAP](DELIVERY-ROADMAP.md) → [ARCH1-IMPLEMENTATION-AUDIT](ARCH1-IMPLEMENTATION-AUDIT.md) → [SEM-001](SEMANTIC-INTEGRITY-POLICY.md).

**Текущий ARCH1 audit (только исходники, никаких Outlook/MAPI операций):**

~~~powershell
.\Core\Diagnostics\Invoke-OPA265ARCH1DeliveryReadinessAudit.ps1 -Mode Plan | Format-List
$audit = .\Core\Diagnostics\Invoke-OPA265ARCH1DeliveryReadinessAudit.ps1 -Mode Audit
$audit.Readiness | Format-List *
$audit.Readiness.AuditRows | Format-Table -AutoSize
~~~
