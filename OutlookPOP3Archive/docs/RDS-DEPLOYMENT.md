# Развёртывание на RDS: планировщик заданий и GPO

**Важно:** текущая ARCH6f3c3 и документационная ARCH7a не готовы для production Auto. Не включать пользовательские задачи до RC/production acceptance. Тестовый Invoke-OPAArchiveBatches.ps1 способен закрыть Outlook; не использовать его в планировщике.

## Подготовка сервера

1. Проверить SHA-256 ZIP принятого релиза. Установить в постоянный локальный каталог C:\Program Files\OutlookPOP3Archive. Администраторы/SYSTEM — запись, пользователи — чтение/выполнение; PST и логи вне каталога программы.
2. Windows PowerShell 5.1 STA, классический Outlook с действующим профилем POP3. Работать в интерактивной сессии пользователя, не SYSTEM, S4U, service account, highest privileges. Не хранить пароли в задаче/GPO. Не менять ExecutionPolicy в обход политики организации.
3. Проверить резервное копирование, ACL и свободное место под архивы, отсутствие конкурирующих архиваторов. Копия открытого PST не гарантированно корректная резервная копия. Не удалять старые pending/journal.
4. Вручную в пользовательской сессии: проверить версию PowerShell, STA и обнаружение ящиков. Сейчас доступны Analyze/Plan, writer только тестовый.

~~~powershell
Set-Location 'C:\Program Files\OutlookPOP3Archive'
$PSVersionTable
[Threading.Thread]::CurrentThread.GetApartmentState()
.\OutlookPOP3Archive.ps1 -Mode Analyze
.\OutlookPOP3Archive.ps1 -Mode Plan -OlderThanMonths 12
~~~

## Планировщик вручную (после допуска)

taskschd.msc → Создать задачу (не простую).

| Вкладка | Значение |
|---|---|
| Общие | OutlookPOP3Archive-имя пользователя; учётная запись самого пользователя; выполнять только для вошедшего пользователя; без наивысших прав |
| Триггеры | При входе конкретного пользователя; задержка 1–5 минут, пример 2 минуты; дополнительное расписание при необходимости |
| Действия | Запуск программы, путь и аргументы ниже |
| Условия | Не требовать простоя; прочие условия по политике сервера |
| Параметры | Не запускать новый экземпляр (IgnoreNew); не прерывать длительный worker произвольным таймаутом; внешние повторы только после приёмки recovery |
| До RC | Не включать задачу |

Программа:
~~~text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
~~~
Аргументы:
~~~text
-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File "C:\Program Files\OutlookPOP3Archive\OutlookPOP3Archive.ps1" -Mode Auto
~~~
Рабочий каталог:
~~~text
C:\Program Files\OutlookPOP3Archive
~~~

Для другого возраста добавить -OlderThanMonths 24. WindowStyle Hidden скрывает консоль, но не блокирует диалоги Outlook; отсутствие диалогов — критерий приёмки Auto.

## Создание через PowerShell (после допуска)

Пример запуска из интерактивной сессии целевого пользователя. При регистрации администратором задайте User явно. Защитный флаг предотвращает регистрацию до принятия production.

~~~powershell
$ProductionAccepted = $false
if (-not $ProductionAccepted) { throw 'Auto production gate not accepted.' }
$User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$Name = 'OutlookPOP3Archive-' + ($User -replace '[^a-zA-Z0-9_.-]', '_')
$InstallDir = 'C:\Program Files\OutlookPOP3Archive'
$Exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Args = '-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'OutlookPOP3Archive.ps1') + '" -Mode Auto'
$Action = New-ScheduledTaskAction -Execute $Exe -Argument $Args -WorkingDirectory $InstallDir
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $User -RandomDelay (New-TimeSpan -Minutes 5)
$Principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings
Get-ScheduledTask -TaskName $Name
Get-ScheduledTaskInfo -TaskName $Name
~~~

Не использовать Force вслепую. После приёмки: Start-ScheduledTask -TaskName $Name; проверить Get-ScheduledTaskInfo, итоговый журнал, отсутствие pending и неизменный Outlook PID/start time. LastTaskResult=0 недостаточен для доказательства архива. Внешний restart policy (RestartCount 3, RestartInterval 5 минут) включать только после проверки exit codes/backoff; он не заменяет внутренний recovery.

## Массовая установка через GPO/GPP (после допуска)

1. GPMC: отдельный GPO, связать с OU пилотных RDS пользователей. Если user settings применяются по OU терминальных серверов, проверить существующую loopback policy, не менять вслепую.
2. User Configuration → Preferences → Control Panel Settings → Scheduled Tasks → New → Scheduled Task (At least Windows 7). Action Update, не Replace.
3. Уникальное имя на пользователя, пример OutlookPOP3Archive-%LogonDomain%-%LogonUser%. Учётная запись вошедшего пользователя средствами GPP, только когда пользователь вошёл, Limited. Пароль не сохранять.
4. At log on, задержка/разнесение запусков, действие и аргументы из ручной инструкции, IgnoreNew, без произвольного принудительного таймаута. Item-level targeting по RDS хостам/группам. До RC не разворачивать включённую задачу.
5. Проверить фактический Principal.UserId/LogonType и сессию на одном пользователе, затем нескольких одновременно. Расширять постепенно. Диагностика: gpupdate /target:user, gpresult /h "%TEMP%\OPA-gpresult.html" (cmd.exe), Microsoft-Windows-TaskScheduler/Operational.

## Журналы и диагностика

DEV: каталог OutlookPOP3Archive-Transactions рядом с PST, ARCH4.pending, ARCH6-run-*.jsonl, checkpoints/steps/operation journal, ARCH6-deferred-*.jsonl, optional ARCH6-threat-*.jsonl. Не удалять доказательства, на которые ссылаются pending/deferred. Будущие per-user supervisor/worker logs: точный путь и retention в ARCH7f. Не логировать тело/вложения, защищать метаданные. Не отключать антивирус.

Целевая реакция: Outlook недоступен — повтор с backoff; local attachment failure — deferred; unknown Move — reconcile, не retry; повреждённый журнал — блокировать конкретный PST; logoff — продолжить при следующем входе. Это требования, не гарантии DEV.

## Остановка и откат

Disable-ScheduledTask -TaskName $Name запрещает новые старты; дать текущей операции завершить безопасную границу, не убивать Outlook/worker во время Move. Сверить pending. Откатывать код только с проверкой совместимости форматов; не откатывать PST/индекс по отдельности, не удалять pending или архивы. Unregister-ScheduledTask -TaskName $Name -Confirm после безопасной остановки. Для GPO отключить/удалить элемент политики, проверить фактическую задачу.

## Справка Microsoft

- [New-ScheduledTaskPrincipal](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal)
- [New-ScheduledTaskTrigger](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger)
- [New-ScheduledTaskSettingsSet](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset)
- [Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask)

Инструкция не является подтверждением реального развёртывания; проверить cmdlets, GPP и UI на целевом сервере.
