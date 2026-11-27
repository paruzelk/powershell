# ARCH7a — эксплуатационный контракт Auto

> ARCH8a DEV: separately consented long Auto, exact local pinned single POP3 PST, batch 1..500 (default 500), 0 = no aggregate batch cap, optional 1..100 cap for pilot, original Safe/age-only/YearQuarter/attach-only and fresh-worker recovery, no blind retry, original 10/100 mode and RDS wrapper unchanged. CI expected 4947/168; production closed. [ARCH8a](2.6.5-arch8a.md). The long test mode is not a deployment permit.

> ARCH7c/d REAL PASS via ARCH7d2, [evidence](2.6.5-arch7d.md). ARCH7e adds explicit DEV Auto age-only defaults and all-POP3 dispatcher, not production permission. Shared-directory pending remains serialized (no migration); 10/100 cap, final 500/unlimited, persistent retry, full per-PST isolation and RDS acceptance remain outstanding. [ARCH7e](2.6.5-arch7e.md).

> ARCH7b3 accepted real 4/4 same Outlook, see [evidence](2.6.5-arch7b.md). ARCH7c DEV [recovery-only CLI](2.6.5-arch7c.md), supervisor/Auto still closed. Target requirements unchanged.

> ARCH7b implementation: [bounded same-Outlook verification](2.6.5-arch7b.md); CI and real acceptance pending. Target requirements unchanged.

25.11.2026. Последний исполняемый релиз ARCH6f3c3, 8910499e, 4862 Pester / 165 контейнеров PASS. Документационный этап. ProductionReady=False, Auto закрыт.

## Требования

- Windows Server RDS, Windows PowerShell 5.1 STA, классический Outlook (целевой Outlook 2019 x64). Запуск при входе пользователя и по расписанию в его интерактивной сессии, без SYSTEM, повышения прав или пароля.
- Автоматически обнаружить все POP3, исключить IMAP, Outbox, Deleted, Drafts, Junk; Inbox, Sent, пользовательские папки и письма корня включены. Цель — разделение PST до 90 ГБ и более на годовые архивы, квартальная группировка с сохранением иерархии.
- Возраст 12 месяцев по умолчанию; до исчерпания подходящих писем. Размер исходного PST — только статистика, не критерий отбора или завершения. Старые 40/35 ГБ опциональны, по умолчанию отключены. Прикладной cap архива отключён; корпоративная политика Outlook не меняется. Контроль свободного места обязателен. Принудительного сжатия нет, физическое уменьшение не гарантируется.
- Конфигурация в начале OutlookPOP3Archive.ps1, CLI override, без JSON/INI. Целевые defaults: Auto, 12, YearQuarter, DisableStoragePolicy=True, DisableArchivePstSizeLimit=True, IncludeRootMail=True, Safe, Continue. Batch 500 и 3 recovery attempts — начальные проектные значения, суммарного лимита нет.
- Работающий Outlook не закрывать, не перезапускать, не менять профиль, не закрывать окна пользователя и не отключать архивы. Архивы подключены, пользователь может работать. Если Outlook недоступен — отложенное подключение, без принудительного запуска. Абсолютное отсутствие нагрузки не гарантируется: throttling и RDS pilot.
- Только PowerShell worker может перезапускаться. Неопределённый Move сверить, не повторять вслепую. Durable claim/receipt, полный semantic witness, verification перед Reconciled/Index, permanent deferred ledger. Пропуск локальной ошибки вложения до Move без определения AV; неизвестная системная ошибка или несовпадение после Move блокирует PST. Продолжать остальные источники, где безопасно.
- Без видимых ошибок/диалогов, полная первопричина в защищённых журналах администратора. Состояния blocked/partial не считать успехом. Повторы ограничены, backoff. Выход пользователя — продолжение после следующего входа. Не удалять доказательства активных исключений.

## Аудит 8910499e

| Компонент | Текущее состояние | Требуемое изменение |
|---|---|---|
| Main / ARCH2aMoveOutcomeFence | Auto blocked; Analyze default; legacy 40/35, 10 GB cap, Fast | Не открывать старый writer; интегрировать age-only Auto |
| ComManager | GetActiveObject с fallback COM activation, профиль живого Outlook защищён | Attach-only в Auto |
| ARCH4Batch | pending/lease в каталоге PST; Resume требует новый Outlook StartUtcTicks | Новый verifier в отдельном STA worker без Outlook restart, доказать целостность |
| ARCH6Orchestration / controller | Один явный PST, Quit для Resume | Переиспользовать sequence без Quit |
| MailMover / ArchiveVerifier | Семантика, durable claim/receipt, journal/index commit | Сохранить обязательные проверки |
| ARCH6Deferred | Type1 local export deferral, optional historical Defender hold | Универсальная обработка и mixed recovery |
| AutoRecoveryPolicy / StoragePolicy | Legacy size-driven план и очистка | Age-only, защита зависимостей journal/ledger |
| Mutex/lease | Per-user mutex, directory-wide pending | Изоляция нескольких PST даже в одном каталоге; RDS concurrency |
| Logging | Write-Host, общий throw контроллера | Quiet, первопричина, итоговый статус |

## Доказательства и ограничения

ARCH6f3c1 real PASS: 20261125-135508-913b789a, Planned=500, Verified=Reconciled=Indexed=311, Unprocessed=189, MoveInvocations=0, PendingCleared=True, 124.4930864 s. Всего 1310/1500. Не повторять завершённые испытания. ARCH6f3c3 CI PASS, live deferral не принят; historical hold отказал по nonunique attachment metadata, Move/export отсутствуют. Удаление исходного вложения не доказано. Оставшиеся 190 не считать выполненными. OLE, Auto, 90GB и RDS не сертифицированы.

## Приёмка

Новый worker проверяет свежие COM объекты при неизменном Outlook PID/start time; это не эквивалент Outlook restart, отдельно доказать устойчивость в лаборатории при естественном restart. Mixed recovery различает returned/skipped/unprocessed/indeterminate; no blind replay. Повторный запуск не переносит уже архивированные или deferred письма. Multi-PST и RDS isolation. Полный успех только после исчерпания eligible, исключения учтены; blocked PST отдельно. Тихий режим, стабильные журналы, отсутствие остановки Outlook. Реальный тест с параллельной работой пользователя, затем 90+ GB. Production gate не открывать до acceptance.

Следующие этапы: ARCH7b verifier; ARCH7c mixed recovery; ARCH7d supervisor/worker; ARCH7e multi-PST/age-only defaults; ARCH7f quiet/log/throttle; ARCH7g RDS scheduler; ARCH8a live Auto; ARCH8b 90+ GB/RDS нагрузка; RC.


## ARCH8a3 — приоритет непрерывной архивации и изоляция отдельных писем (27.11.2026)

Обязательное требование заказчика: отдельные проблемные письма (одно, два, три и более) не должны останавливать весь цикл Auto лишь потому, что конкретная причина сбоя неизвестна. Цель — уменьшить логический объём основной POP3 PST по возрасту писем, а не получить побайтовый клон. Физическое уменьшение файла выполняется средствами Outlook.

- Изолированная ошибка чтения/проверки конкретного письма до Move: оставить его в источнике, записать ID, папку, причину или тип исключения/HResult в долговечный журнал, исключить из автоматического повторного отбора. Продолжить.
- Уже получен однозначный Move receipt, но проверка отдельного письма не прошла: сохранить исходные свидетельства, путь PST и EntryID, отдельный статус VerificationHeld. Не объявлять Verified, не индексировать как успешное перемещение; не повторять Move и не удалять письмо. Подтверждённые письма завершить, продолжить следующие партии.
- Неподдерживаемое вложение и антивирусные ошибки обрабатывать как ранее; не отключать антивирус. Никаких ручных подтверждений для отдельных исключений.
- Системные ошибки (невозможность установить источник/назначение, повреждение журналов, неопределённый Move без receipt, отказ долговечной записи, массовые сбои чтения) не маскировать под отдельный пропуск. Не выполнять слепой повтор Move. Существующий порог серии ошибок чтения/экспорта 10 и не менее половины партии сохраняется для системной диагностики.
- Verified, Reconciled, Indexed отражают только подтверждённые письма. Deferred включает пред-Move пропуски и отдельные VerificationHeld; NotMoved отражает только не перемещённые. Журнал исключений сохраняется и проверяется при последующих запусках.

Реализация ARCH8a3 DEV: политика включена в explicit long test scope; неизвестные локальные ошибки ограничены фазой получения и проверки свойств исходного письма до выбора назначения. Ошибки инфраструктуры, формирования свидетельства вне доказанной локальной стадии и новые ошибки после запечатывания частичной фиксации пока сохраняют защитную остановку. Не считать это полной приёмкой ТЗ до реальных испытаний, ARCH8b и RC.


## ARCH8b — централизованное развёртывание (27.11.2026)

Одна GPO для RDS и одна доменная группа безопасности POP3Archive. Администратор развёртывает подписанную/доверенную сборку в локальный защищённый от записи пользователями каталог на каждом RDS; задаёт SID группы в параметрах пользовательского задания GPP. При входе члена группы запускается скрытая пользовательская обёртка без пароля и повышения прав; членство повторно проверяется по текущему токену, не по имени группы. Outlook обнаруживается в текущем сеансе; ожидание его готовности ограничено, без запуска или перезапуска Outlook. Автоматически обрабатываются однозначно обнаруженные локальные POP3 delivery PST текущего активного профиля, 500 писем/партия, без общего лимита, 12 месяцев, YearQuarter, Safe, политика исключений ARCH8a3a. Не член группы — без COM/Move. Изменение членства действует после обновления токена (выход/вход). Существующий per-user mutex и directory lease сохраняются; межсерверная параллельность требует раздельных локальных PST и отдельной проверки RDS. Никаких изменений AD/GPO самим скриптом. Инструкция: docs/ARCH8b-RDS-GPO.md. До ARCH8c и RC только ограниченный пилот на тестовых PST, не массовое включение.


## ARCH8b1 — объединённый установщик и обслуживание

Требование: единый переносимый Install-OPADomain.ps1, режимы Install/Update/Repair/Audit/Disable/Uninstall, WhatIf. AD domain autodiscovery (или -Domain), explicit OU + computer scope, create/reuse security group POP3Archive, SID-based ACL, authenticated WinRM deployment. Для автоматической настройки применяется штатная компьютерная GPO Run these programs at user logon через Set-GPRegistryValue; отдельный минимальный launcher с проверкой группы до загрузки архиватора. GPO Apply только выбранным RDS computer accounts. Не создавать GPP XML вручную, не изменять loopback, не включать WinRM или RDS role автоматически. Ранее подготовленный GPP вариант сохраняется как альтернативный ручной способ, не одновременно. Программа не удаляет PST, журналы или членство в AD. Disable выключает собственные GPO values и локальный launcher, Uninstall удаляет только активный маркированный runtime, оставляет отключённый launcher и резервные версии для ручного обслуживания, группу и выделенную GPO. Не прерывать активную архивацию; lease охватывает управляемые запуски, ручные запуски вне этой обёртки перед обслуживанием должны быть завершены. Доменная приёмка ARCH8c обязательна. Инструкция: docs/ARCH8b1-DOMAIN-INSTALL.md.