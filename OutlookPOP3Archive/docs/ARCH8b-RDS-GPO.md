# ARCH8b DEV — развёртывание через GPO и группу POP3Archive

Это инструкция для пилота после успешного CI. ARCH8a3a: 21228 verified, 40 deferred, AllSourcesExhausted и ExitCode=0, без перезапуска Outlook. Реальная приёмка GPO, нескольких RDS-сеансов и PST 90+ ГБ относится к ARCH8c. ProductionReady=False. Не включайте массово рабочие PST до приёмки.

## 1. Подготовка AD

Выполнить на административной станции с RSAT/модулем ActiveDirectory и делегированными правами. Если группа уже существует, использовать её, не создавать вторую. Выбрать OU для группы по правилам организации.

~~~powershell
Import-Module ActiveDirectory
New-ADGroup -Name 'POP3Archive' -SamAccountName 'POP3Archive' -GroupScope Global -GroupCategory Security
$group = Get-ADGroup -Identity 'POP3Archive'
$group.SID.Value
Add-ADGroupMember -Identity 'POP3Archive' -Members 'testuser'
~~~

testuser — тестовая учётная запись; заменить реальной тестовой. Записать точный SID группы, а не SID пользователя. Группа не даёт административных прав. Удаление из группы: Remove-ADGroupMember -Identity 'POP3Archive' -Members 'testuser' (подтвердить). Требуется полный выход/вход, не только RDP disconnect/reconnect; gpupdate сам по себе не обновляет токен. Не завершать текущий процесс принудительно: уже начатая архивация может работать до завершения с прежним токеном.

## 2. Установка сборки

Распаковать проверенный CI ZIP на каждом выбранном RDS, например C:\Program Files\OutlookPOP3Archive. Администраторы/SYSTEM — изменение; обычные пользователи — чтение и выполнение; не давать пользователям запись в код или каталог установки. Все файлы сборки включая Core должны быть рядом. Запускать локальную копию, не скрипт из общей UNC-папки. Не использовать ExecutionPolicy Bypass: соблюдать доменную политику подписи/доверия, проверить SHA256 ZIP, подписать по правилам организации при необходимости. Обновление только после завершения активных заданий; не заменять файлы запущенного набора. PST и каталоги транзакций не переносить и не очищать.

## 3. Проверка без Outlook/записи

Запуск Windows PowerShell 5.1 STA. SID ниже — пример, заменить фактическим SID группы:

~~~powershell
$sid = (Get-ADGroup POP3Archive).SID.Value
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -STA -File 'C:\Program Files\OutlookPOP3Archive\Invoke-OPARdsAutoDev.ps1' -ConfirmDevAutoArchive -ConfirmDevGpoArchive -ArchiveGroupSid $sid -WhatIf
~~~

На RDS RSAT не обязателен: передать SID строкой. WhatIf проверяет синтаксис/параметры, не членство и не Outlook. Ожидается 500, MaxBatches=0, 12 месяцев, YearQuarter, 20 минут, Quiet=True. Для первого реального пилота можно указать -BatchSize 10 -AutoDevMaxBatches 1; после приёмки убрать оба ключа.

## 4. GPMC — одна политика

- Создать GPO RDS - Outlook POP3 Archive (Pilot); связать с OU только пилотных RDS-компьютеров. Если user policy уже применяется через loopback, не изменять существующий режим без аудита. Иначе включить Configure user Group Policy loopback processing mode, Merge, по Computer Configuration > Policies > Administrative Templates > System > Group Policy. Сохранить Read/Apply для нужных компьютеров/пользователей; отбор группы выполнять Item-level targeting, не лишать компьютер права Read/Apply.
- User Configuration > Preferences > Control Panel Settings > Scheduled Tasks > New > Scheduled Task (Windows Vista and later). Action Update (не Replace). Name OutlookPOP3Archive-%LogonDomain%-%LogonUser%.
- General: account %LogonDomain%\%LogonUser%; Run only when user is logged on; без Run with highest privileges; Hidden; Windows Server 2016 compatible. Не SYSTEM, не пароль, не Run whether user is logged on or not.
- Triggers: At log on, Specific user %LogonDomain%\%LogonUser%, Delay task for 2 minutes. При первом применении GPP задание может зарегистрироваться уже после события logon. Для первого пилота вручную запустить зарегистрированное задание или выполнить следующий logon. Если нужен автоматический старт сразу при первой регистрации, добавить At task creation/modification с задержкой 2 минуты; учитывать, что Update при GPO refresh также может дать запуск. IgnoreNew и внутренние mutex/lease остаются обязательными. Не включать бесконечные внешние рестарты.
- Actions > Start a program. Program/script: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe (уточнить WindowsDirectory). Add arguments (заменить SID):
~~~
-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File "C:\Program Files\OutlookPOP3Archive\Invoke-OPARdsAutoDev.ps1" -ConfirmDevAutoArchive -ConfirmDevGpoArchive -ArchiveGroupSid S-1-5-21-111-222-333-2001
~~~
- Start in: C:\Program Files\OutlookPOP3Archive (без кавычек в отдельном поле).
- Conditions: отключить условия простоя/питания; Settings: Do not start a new instance (IgnoreNew), снять Stop the task if it runs longer than, снять If the running task does not end when requested, force it to stop; не включать Restart on failure. Не прерывать задачу при refresh.
- Common: оставить Run in logged-on user's security context **выключенным** для GPP Scheduled Task (CSE регистрирует задачу как SYSTEM, но principal самой задачи — интерактивный пользователь); Item-level targeting > Security Group > User in group STIOS\POP3Archive (выбрать группу через Browse). Не Apply once. Не использовать Remove this item when it is no longer applied, если это переводит Update в Replace и прерывает активные задачи. После удаления пользователя из группы уже существующая задача без нового токена не меняет членство; на новом токене wrapper вернёт 41 и ничего не архивирует. Удалить неактуальные задачи административно после завершения текущих работ.
- Альтернатива: GPO User Configuration, привязанный к OU пользователей, с ILT Security Group AND Computer Name/RDS host group. Не смешивать два способа на одном хосте. Реальные диалоги GPMC проверить на Server 2016/RSAT.

Microsoft:
- https://learn.microsoft.com/en-us/troubleshoot/windows-server/group-policy/user-gpp-scheduled-task-item-fails-apply
- https://learn.microsoft.com/en-us/troubleshoot/windows-server/group-policy/apply-group-policy-objects-rds
- https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn789189%28v%3Dws.11%29

## 5. Синтаксис обёртки

| Ключ | По умолчанию в GPO pilot | Назначение |
|---|---|---|
| ConfirmDevAutoArchive | обязателен | явное согласие на DEV |
| ConfirmDevGpoArchive | обязателен | включить групповую область |
| ArchiveGroupSid | обязателен | SID группы безопасности |
| BatchSize | 500 | 1..500 |
| AutoDevMaxBatches | 0 | 0 без ограничения; 1..100 ограничение |
| OlderThanMonths | 12 | 1..1200 |
| ArchiveGrouping | YearQuarter | Year / YearQuarter / YearMonth |
| OutlookWaitMinutes | 20 | 0..60; проверка каждые 15 секунд, 0 одна проверка |
| WhatIf | выключен | параметры без COM/записей |
| ExpectedUserSid | запрещён в GPO mode | только прежний ARCH7g режим с фиксированным SID |

В основном CLI эквивалент: -Mode Auto -ConfirmDevAutoArchive -ConfirmDevLongArchive -RdsArchiveGroupSid <SID> -Quiet. Обёртка дополнительно ждёт Outlook до начала Auto. Legacy ARCH7g fixed SID и ARCH8a pinned PST остаются без изменений. Не используется каталог произвольных PST: только однозначно обнаруженные POP3 delivery PST текущего профиля. Размер PST не критерий отбора. Нет запуска Outlook, смены профиля, сжатия PST, автоматической повторной попытки неопределённого Move.

## 6. Диагностика

Task Scheduler History/Last Run Result: 0 — исчерпано/нет POP3; 10 — достигнут заданный лимит; 20 — частично/блокировка; 30 — ошибка конфигурации/сеанса; 40 — Outlook не готов к окончанию ожидания; 41 — нет группы в текущем токене. Проверки до Auto отражаются только в коде задачи; Auto пишет приватный журнал %LOCALAPPDATA%\OutlookPOP3Archive-ARCH7f. Оригинальные step/operation/deferred/held журналы в OutlookPOP3Archive-Transactions не ротируются. Quiet и WindowStyle Hidden подавляют вывод PS; отсутствие любых нативных диалогов Outlook не доказано.

~~~powershell
whoami /groups
gpresult /r /scope:user
Get-ScheduledTask | Where-Object TaskName -like 'OutlookPOP3Archive-*' | Get-ScheduledTaskInfo
Get-ChildItem "$env:LOCALAPPDATA\OutlookPOP3Archive-ARCH7f" -Filter *.jsonl | Sort-Object LastWriteTime -Descending | Select-Object -First 5
~~~

## 7. Реальная приёмка ARCH8c

1. Тестовая группа/пользователь и 10 писем, ограничить 1 партию. Проверить запуск из GPP, отсутствие лишних окон, отчёт, PID Outlook, работа при задержанном запуске Outlook и отсутствие POP3.
2. Пользователь вне группы: не получает задания; если задача осталась, код 41 на новом токене, без Outlook/Move. Повторный logon/refresh при активном задании не запускает вторую архивацию.
3. Два разных тестовых пользователя RDS одновременно, затем два сеанса одного пользователя на одном хосте. Проверить изоляцию и отсутствие дублирования. Mutex локален серверу; один PST нельзя совместно открывать на нескольких серверах.
4. Реальное тестовое PST 90+ ГБ, 500/unlimited, измерение нагрузки CPU/RAM/диска, длительности и отзывчивости Outlook; сохранять архивы, pending, журналы. При закрытии Outlook или выходе из сеанса не убивать процессы вручную; на новом входе штатный Resume существующего pending до нового Move. Непарные claims остаются блокирующим системным исключением.
5. После прохождения ARCH8c, RC и принятия рисков — массовое развёртывание. Не считать ARCH8b доказательством production readiness.
