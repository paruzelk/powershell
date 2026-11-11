# ARCH1 — фактический аудит готовности к рабочему архивированию

> **ИСТОРИЧЕСКИЙ снимок кода, не текущее состояние ARCH2a.** В ARCH2a старый `MoveFailed` / `continue` заменён на `Move Indeterminate` и `throw`, плюс full-journal Resume fence. При этом основной `ArchiveVerifier.ps1` всё ещё неполон и writer modes закрыты. См. [ARCH2a](2.6.5-arch2a-move-outcome-fence.md).



**Проверено в исходниках коммита BW4k7v2a8 `ed32971f09577a6d589820892e99a3827f4e431e`, 2026-11-11.** Это **статический** аудит наличия функций и явных опасных участков, а не Outlook live acceptance или утверждение работы на 90GB. Результат можно пересчитать [read-only скриптом](../Core/Diagnostics/Invoke-OPA265ARCH1DeliveryReadinessAudit.ps1).

| Компонент | Код найден | Что действительно установлено | Недостающий доказанный критерий |
|---|---|---|---|
| `OutlookPOP3Archive.ps1` | Да | `-Mode Archive/Resume/Plan/Analyze/Auto` есть; по умолчанию `Analyze` | Нельзя считать опасные режимы выключенными лишь по `RELEASE.Integration=false`; нужен новый safety gate |
| `Core/Archive/MailMover.ps1` | Да | Использует `$item.Move($dest.Folder)`; после COM MoveFailed добавляет skipped row и `continue` | Устранить неопределённый outcome как «обычный пропуск», независимое read-only reconciliation до следующего writer |
| `Core/Archive/ArchiveVerifier.ps1` | Да | Проверяет размещение/identity и некоторые fingerprints | **Нет полной интегрированной Body/HTMLBody/attachment-byte SHA проверенной модели**; встроить уже имеющиеся BW4k witnesses |
| `Core/Archive/ArchiveGrouping.ps1` | Да | `Year` реализован как режим группировки | CLI default `YearQuarter`; подтвердить годовые PST/parts в end-to-end |
| `Core/Archive/ArchivePlanner.ps1` | Да | Рекурсивный обход допустимых POP3-папок | Проявить Inbox, POP3 Sent, Custom/вложенные, Outbox и не-MailItem в одном end-to-end наборе |
| `Core/Archive/SystemFolders.ps1` | Да | Выделены Outbox/служебные папки | Не переносить чужую отправленную почту; проверка исключений в живом профиле |
| `Core/Archive/OperationJournal.ps1` | Да | Отдельная append-only модель Intent/Outcome | Связать с реальным Archive Writer и безопасным возобновлением после неоднозначных исходов |
| `Core/Archive/DuplicateIndex.ps1` | Да | Дедупликация и append-only delta index | Корреляция с физическим архивом и аварийным восстановлением |
| `Core/Worker/WorkerControl.ps1` | Да | Изолированные контролируемые probe/synthetic операции | Не доказано, что production Archive/Resume исполняются в STA Worker |
| `RELEASE.json` | Да | `ArchiveWorkerEnabled=false`, `ResumeWorkerEnabled=false`, `AutoWorkerEnabled=false` | Это переключатели интеграции Worker, не автоматическая блокировка legacy CLI |
| `docs/SEMANTIC-INTEGRITY-POLICY.md` | Да | Уже запрещает использовать `MailItem.Size` как единственный критерий ошибки и побайтовое равенство всех PST | Не смягчать: добавить явный **stop-rule** и перевести критерии в проверяемый Archive Worker |

## Специальная опасность — MoveFailed

В текущем `MailMover.ps1` есть шаблон:

~~~powershell
try {
    $moved = $item.Move($dest.Folder)
    $moveCompleted = $true
}
catch {
    # ... skipped with Reason='MoveFailed' and continue ...
}
~~~

Это **не доказывает конкретную потерю письма**, но COM исключение не всегда позволяет установить, успел ли провайдер физически завершить перемещение. Если его считать простым skipped item и затем повторять автоматически, возможны дубликаты и нарушение инвариантов. ARCH2 должен сначала доказать fence и reconciliation, затем менять модель допуска записи. Прямой writer без завершённого acceptance gate нельзя применять к 90GB набору.

## Специальная опасность — сравнение неполной модели

`ArchiveVerifier.ps1` не содержит прямого сравнения `Body`, `HTMLBody` или `Attachments`; наличие отдельных BW4k проверок НЕ означает, что основной производственный цикл ими пользуется. До фактической интеграции в main worker релизный статус должен быть **uncertified**. Планировать reuse, а не заново писать и исследовать MAPI.

## Живые тесты, которые уже есть

Пять оригинальных BW4j source witnesses, четыре подтверждённых реальных Move (PlainSmall/UnicodePlain/HtmlBody/Attachment1K), в том числе байтовая проверка 1K; отдельный BW4k7v2a7 disposable Draft Move source0/dest1 с семантическим SHA. Не утверждать, что 256K Move или полнофункциональный годовой batch были проверены. Отдельно первоначальная read-only POP3 инвентаризация сообщала о 26605 Inbox объектах, 21985 письмах 2020–2025 и 3 не-MailItem объектах. Исторические числа не подменяют новую live инвентаризацию перед production.

## Что входит в ARCH1, что не входит

**Входит:** ADR/roadmap/handoff, детальный аудит, read-only машина `Invoke-OPA265ARCH1DeliveryReadinessAudit.ps1` (`Plan`/`Audit`), Pester и CI-гейт на сохранение этого решения; только чтение кода проекта и release JSON.

**Не входит:** изменения текущего `MailMover`, `ArchiveVerifier`, Outlook COM, создание PST, новый Move, удаление писем, production Archive/Resume/Auto activation, толкование каждого MAPI бита.

**Выход ARCH1:** статическое состояние зафиксировано и передано на **ARCH2** с конкретными рисками, независимо от того, будет ли потерян диалоговый контекст. См. [roadmap](DELIVERY-ROADMAP.md).
