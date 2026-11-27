# ARCH8b1 DEV — единая установка и обслуживание

После CI PASS использовать только в тестовой OU/RDS с тестовыми PST. ARCH8b CI: 4969/168 PASS. ARCH8b1 включает прежние ARCH8b1 и ARCH8b2. ProductionReady=False. Доменные изменения выполняются только по явному согласию администратора; CI не выполняет настоящий Install.

## Механизм

Штатная компьютерная политика Run these programs at user logon, созданная через Set-GPRegistryValue и New-GPLink. Это не GPP Scheduled Task; ручная схема ARCH8b с планировщиком доступна отдельно. Не включать оба механизма одновременно. Не требуется Loopback, не изменяются существующие настройки других GPO и SYSVOL XML, пароли не используются. Политика запускает минимальный PowerShell launcher в обычном интерактивном пользовательском сеансе; он проверяет SID группы до загрузки архиватора. Член группы получает существующий ARCH8b Quiet Auto, ожидание Outlook, восстановление pending, 500/unlimited, YearQuarter и 12 месяцев. Прочие пользователи завершают launcher до COM/Move. При удалении из группы требуется новый токен (полный выход и вход); текущая архивация не прерывается. RemoteApp/альтернативная оболочка, GPO Run-конфликты и видимость окон требуют отдельной проверки. Не обещается запуск на любом типе сеанса.

## Предпосылки

- Административная станция Windows PowerShell 5.1 (64-bit), RSAT ActiveDirectory и GroupPolicy, права создания группы/GPO/связи с выбранной OU и локального администрирования RDS. Kerberos WinRM уже настроен. Установщик не меняет firewall, WinRM, execution policy, RDS role и не запрашивает пароль.
- Проверить SHA256 официального GitHub ZIP и распаковать в защищённый рабочий каталог. BUILD-INFO.json и проверка пересылки хешей не заменяют доверенную проверку внешнего ZIP. Подпись скриптов согласно корпоративным правилам. Не использовать Bypass.
- Выбрать пилотные доменные member servers с RDS-RD-Server и одинаковыми Program Files/Windows directories. Не использовать DC. Не удалять архивы, pending и журналы.
- Выключить старую ручную GPP-схему на целевых RDS после завершения активных заданий. Не обновлять при активном ручном запуске; автоматический lease охватывает только новую управляемую обёртку.

## Быстрый старт

~~~powershell
.\Install-OPADomain.ps1 -WhatIf
~~~

Показывает обнаруженный домен и список OU, не изменяет AD/GPO и не вызывает WinRM. Указать реальную OU и хосты:

~~~powershell
$scope = @{
    TargetOU = 'OU=RDS,DC=example,DC=local'
    ComputerName = @('RDS01','RDS02')
}
.\Install-OPADomain.ps1 @scope -WhatIf
.\Install-OPADomain.ps1 @scope -Mode Install -ConfirmDomainDeployment -BatchSize 10 -AutoDevMaxBatches 1
~~~

Подтвердить операцию ShouldProcess. Для заранее проверенного автоматизированного запуска допускается -Confirm:$false при сохранённом -ConfirmDomainDeployment. По умолчанию GroupName POP3Archive, GpoName RDS - Outlook POP3 Archive (Pilot), GroupOU — контейнер Users текущего домена. -Domain задаёт другой доступный DNS-домен; имя пользователя/домена не зашито. Вместо ComputerName допускается явный -AllComputersInOU (все включённые компьютеры в OU и дочерних OU; любой не-RDS блокирует Install до изменений). TargetOU обязателен; domain root не допускается. Область домен/OU/группа/GPO/список серверов фиксируется SHA256 в ownership marker; расширение набора серверов требует отдельного контролируемого изменения области (пока не поддерживается автоматически). Группа создаётся пустой или используется существующая одноимённая security group выбранного домена. Учётные записи добавляет администратор:

~~~powershell
Add-ADGroupMember -Identity POP3Archive -Members 'testuser'
~~~

Выполнить штатное обновление компьютерной политики на пилотных RDS (например gpupdate /target:computer), дождаться репликации и полного нового входа тестового пользователя. Установщик не форсирует logoff, reboot или gpupdate. Проверить gpresult, реестр и личный журнал архивации. После малой пилотной партии и приёмки можно обновить параметры:

~~~powershell
.\Install-OPADomain.ps1 @scope -Mode Update -ConfirmDomainDeployment
~~~

По умолчанию BatchSize 500, AutoDevMaxBatches 0, OlderThanMonths 12, ArchiveGrouping YearQuarter, OutlookWaitMinutes 20. Update/Repair пересоздают желаемую конфигурацию из явно переданных/default параметров; не наследуют произвольно изменённые предыдущие значения. Перед обслуживанием сохранять используемый набор параметров, особенно ограничение пилота.

## Каталоги и права

- Program Files\OutlookPOP3Archive — Administrators (S-1-5-32-544) и SYSTEM (S-1-5-18) Full Control; SID POP3Archive Read & Execute. Файлы runtime и Core, BUILD-INFO, OPA-runtime.json с SHA256. Пользователям не назначается право записи.
- Program Files\OutlookPOP3Archive-Logon — только минимальный launcher, marker deployment.json и deployment.lock; Authenticated Users RX, Administrators и SYSTEM Full Control. Нет обычного доступа на запись; проверка группы перед обращением к основному коду. Shared read lease на весь управляемый запуск, эксклюзивная блокировка на обслуживание.
- Не удаляются и не перемещаются пользовательские PST/журналы. Каталоги с чужими marker, неожиданными файлами, reparse points или небезопасными ACL не перезаписываются. Repair исправляет безопасные расхождения; небезопасный владелец/право записи требуют ручного карантина. Новая версия сначала хешируется и устанавливается в отдельный staging directory, затем заменяется активный runtime; предыдущий каталог остаётся с уникальным суффиксом .previous.<guid>. При ошибке на стадии копирования может остаться staging, он не активируется. Операции на нескольких хостах не атомарны; PartialDeployment содержит результаты. После частичного Install/Update существующая политика может остаться активной на уже исправных хостах; Disable применяется отдельно.

## Обслуживание

~~~powershell
.\Install-OPADomain.ps1 @scope -Mode Audit
.\Install-OPADomain.ps1 @scope -Mode Repair -ConfirmDomainDeployment
.\Install-OPADomain.ps1 @scope -Mode Disable -ConfirmDomainDeployment
.\Install-OPADomain.ps1 @scope -Mode Uninstall -ConfirmDomainDeployment
~~~

Audit: AD/GPO и read-only WinRM, effective HKLM policy, ACL/manifest drift, installed commit, GPO permissions, logon value. ProbeFailed означает недоступность/ошибку, не успешный аудит. Install/Update/Repair не меняют чужие GPO, GPO link не Enforced; Authenticated Users GpoRead, только выбранные computer SID GpoApply. Проверяется readback; если unexpected Apply, Enabled=0 и отказ. Scope collision, GPO link outside intended OU или смена group SID требуют отдельного решения.

Disable: удаляет только собственный named Run value через disabled policy setting, Enabled=0; затем выключает local marker доступных хостов. Даже если сервер недоступен, сначала отключает центральную политику. Уже запущенные работы не прекращаются. Политика действует после refresh; offline или active host может потребовать повторного Disable. Uninstall делает то же и удаляет только активный маркированный runtime; сохраняет AD группу, GPO (выключены её значения архивации), disabled launcher/lease и предыдущие/незавершённые staging copies для ручной уборки после проверки. Не удаляет membership, почту, архивы и journals. Удаление группы и GPO — отдельное решение администратора, не выполняется автоматически. Повторный Install с тем же scope, действующей группой и проверенным ZIP возможен; одинаковая версия с точными ACL и SHA256 не требует нового backup.

## Полный интерфейс

| Ключ | По умолчанию |
|---|---|
| Mode | Install (Install, Update, Repair, Audit, Disable, Uninstall) |
| Domain | текущий домен |
| TargetOU | обязательно для изменения |
| ComputerName | явные short/FQDN имена, взаимоисключающе с AllComputersInOU |
| AllComputersInOU | false |
| GroupName | POP3Archive |
| GroupOU | UsersContainer домена |
| GpoName | RDS - Outlook POP3 Archive (Pilot) |
| OlderThanMonths | 12 (1..1200) |
| ArchiveGrouping | YearQuarter (Year/YearQuarter/YearMonth) |
| BatchSize | 500 (1..500) |
| AutoDevMaxBatches | 0 (0 unlimited, 1..100 bounded) |
| OutlookWaitMinutes | 20 (0..60) |
| ConfirmDomainDeployment | обязателен для изменений |
| WhatIf | read-only domain plan |
| Confirm | ShouldProcess |

## Проверка ARCH8c

Пилот на одном RDS: WhatIf, Install small cap, Audit, member/nonmember logon, delayed Outlook, no POP3, two sessions/users, GPO update, active run maintenance refusal, successful Update/Repair/Disable/Uninstall and re-install. Проверить effective ACL ordinary user, отсутствие записи в code, журнал и неизменный Outlook PID, сохранность всех PST и journals. Затем нагрузка 90+ GB. CI не эмулирует контроллер домена и не доказывает реальную регистрацию/применение GPO, remote ACL, PowerShell remoting size limits или все виды RDS logon. Microsoft references: https://learn.microsoft.com/en-us/powershell/module/grouppolicy/set-gpregistryvalue ; https://learn.microsoft.com/en-us/troubleshoot/windows-client/system-management-components/run-programs-automatically ; https://learn.microsoft.com/en-us/powershell/module/grouppolicy/set-gppermission .
