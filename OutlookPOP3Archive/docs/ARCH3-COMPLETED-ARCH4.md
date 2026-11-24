# ARCH3 — завершённый реальный контрольный тест и переход к ARCH4

## Контрольная точка: 24.11.2026

Подтверждено выводом оператора на сборке `OutlookPOP3Archive-2.6.5-ARCH3x2c-dev-g2955cc8a`, commit `2955cc8a6fbda131696516293643cc6f895d5285`, [GitHub Actions 45198163113](https://github.com/paruzelk/powershell/actions/runs/45198163113) (4732 Pester, 162 containers, zero failed/skipped). ZIP SHA-256 `499f1b29cf9bc37038125baeb88c7d2a260738dfb8fb7d97e32030a7f83a8854`.

Источник `info@stios.ru.pst` — прямо назначенный оператором **тестовый** POP3 PST; Outlook 2019, профиль Outlook, Windows PowerShell 5.1 STA. В этом источнике допустимы контролируемые реальные тесты; это не разрешение запуска на производственных PST. Не хранить исходные письма/вложения в GitHub.

| Этап | Подтверждение оператора |
|---|---|
| Status перед Move | NoRealTenWriterEntry; Claims/Invocations/MoveReturns = 0 |
| Audit | 10 полных оригинальных witness, 12 вложений; PhysicalSourcePstSizeFence=False; ReSelectedInboxCandidates=False |
| Move | TenOriginalRealPop3ComMovesReturnedIndependentOutlookRestartRequired; 10 |
| Durable receipts | Claims=10, Invocations=10, MoveReturns=10, FirstUnfinishedOrdinal=0 |
| Независимый перезапуск | PID 9840 → 13028, новое время запуска процесса |
| Review | TenOriginalMovesIndependentlyVerifiedAfterNewOutlookProcess; 10/10, 12 вложений, OriginalSourceEntryIdsAbsent=True, OriginalDestinationCount=10 |
| Seal | IndependentTenOriginalRestartVerifierSealedNoIndexOrJournalCommit; Verified=10 |
| Commit | TenOriginalPostRestartVerifiedReconciledAndIndexed; Verified=10, Reconciled=10, Indexed=10, Recovered=False |
| Status после Commit | ReviewSealed=True; CommitClaimed=True; CommitJournalPresent=True; CommitComplete=True |

### Идентификаторы завершённой операции (пользовательский вывод; не новые проверочные требования)

```text
RunId=093b5ce9-4a90-46fa-b6a5-7cdba61d2f15
PreflightDigest=d8e0d499093af718b3692e3124cb979d579678c4f71138774ec4b8419c3cc81f
WriterEntrySha256=129201185c16846cdc7e2d9d9fe80223277d5ae8a231b18b5b2db0a33dfde9f3
LastMoveReceiptSha256=428a329236794f28c4010c8ba09aa4341121bb2fdb5f31ecb427d1535ef16342
ReviewSha256=6979cf2b9e3ca12a64fb91c283d7c1940c36c43be5ddee798cd8fe452af2beb8
FinalSealSha256=82474e6749a305033abd39bb589f1598666fd2f519419e109a9c1951be79fb30
OriginalIndexSha256=27917ba36dde92eafdba0e92fd0b641106d482574f522a6586259b1ab003b2b8
OriginalCommitJournalSha256=2c4f6ef9a38a5d23e1df31a8cce1d43ad81263c59b648093a3c279efeecf0c78
TargetPst=info@stios.ru.Archive-2020-03.pst
```

ARCH3 завершён. Не выполнять повторно Prepare, Move, Seal или Commit этого RunId. Архивные доказательства и общий индекс не переписывать; прежние тестовые сценарии остаются регрессиями. `ProductionReady=False` — успешно подтверждён ограниченный реальный пилот, а не массовая производственная архивация.

## ARCH4: доработка основного архиватора, без новой специализированной серии пилотов

Использовать существующие `OutlookPOP3Archive.ps1`, `Move-OPAItemsWithLimit`, `Get-OPAArchiveCandidates`, `Get-OPAArchiveDestination`, `Test-OPAArchiveMoves`, `OperationJournal`, `DuplicateIndex` и рекурсивную выборку POP3. Не переносить жёсткие GUID/пути/числа/SHA исторического ARCH3 в новые операции.

**Аудит существующего кода:** основной цикл уже выбирает кандидатов по дате, выбирает год/квартал/часть PST, формирует транзакции и сохраняет исходный семантический witness до COM Move. После возврата COM он преждевременно записывает `Move Completed` и `DuplicateIndex`, а окончательный `Test-OPAArchiveMoves` выполняется позже в основном entrypoint. Старый Resume может считать completion/index доказательством. Кроме того, запасной candidate pool допускает ID вне первоначального durable PlannedItems. Эти места следует исправить в самом основном цикле, а не добавлять ещё один изолированный исторический маршрут.

Единый целевой результат ARCH4:

1. Явно выбрать один разрешённый тестовый POP3 PST в обычном Archive (профиль/StoreID/путь, без других учётных записей), параметры `-Limit 100` или `-Limit 500`, существующий cutoff и grouping. `-WhatIf` — без создания PST, индекса, журнала и Move. Без явного разрешения DEV writer остаётся закрытым.
2. Новый RunId/transaction для каждого пакета, single-writer на исходное хранилище/общий индекс; незавершённая операция не обходится созданием нового RunId. Записывать фактический план/попытку до действия; каждое выбранное письмо — конкретный EntryID с проверкой source scope и актуального cutoff. Пропавшее/перемещённое до попытки сообщение — `Skipped`, продолжать. Не менять состав уже заявленной операции задним числом.
3. Перед Move захватить полный ARCH2b witness (тело, HTML, адреса, пользовательские данные, SHA-256 байтов вложений) и persist/flush durable Intent. Исключение до claim — безопасный пропуск только для однозначно item-local ошибок; после claim неизвестный исход — STOP всего пакета, без повторного вызова.
4. После Move проверять полученный архивный объект, его реальный store/folder и исходный witness оригинальным verifier. Не писать подтверждённое completion/reconciled или DuplicateIndex, пока полное содержимое не проверено. Durable return отдельно от verification. Сохранить возможность независимой пакетной проверки после перезапуска Outlook, как в успешном ARCH3.
5. Повторный запуск: read-only reconciliation незавершённых операций по оригинальным witness и однозначным source/destination; восстанавливать только недостающий verified journal/index после проверки; не повторять неизвестный Move. Корректный статус для пакета с безопасно пропущенными письмами и возможность нового пакета без повторной архивации подтверждённых.
6. Никакого PST binary SHA, сравнения его длины, общего числа Inbox или глобального SHA изменяемого индекса в условиях допуска нового пакета. Физический размер архива допустим только для capacity/rollover, размер источника — телеметрия. Конфликт конкретной записи индекса проверять при записи; защищать общий индекс от конкурирующих writers.
7. CI: обязательный Windows PowerShell 5.1, PSScriptAnalyzer/Pester, BOM, end-to-end синтетические сценарии успешного пакета, исчезновения письма, ошибочного содержимого после Move, обрыва после claim/return/verify, незавершённой записи индекса и безопасного восстановления. Не умножать статические проверки текста и не повторять реальный ARCH3.
8. После готовой сборки — один реальный пакет до 100 сообщений с независимой проверкой, затем до 500. Результаты измерять verified count, skipped, unresolved, elapsed и логически перенесёнными байтами; не ожидать немедленного уменьшения физического PST. Следующие изменения только по фактическим результатам.

ARCH5 — проверить отправленные и пользовательские папки и полноценное годовое/квартальное распределение (переиспользуя уже имеющийся код); ARCH6 — эксплуатация больших PST, производительность и стабильный релиз. Не открывать Auto/Resume для production до подтверждения корректного восстановления.
