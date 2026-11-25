# ARCH7a — эксплуатационный контракт Auto

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
