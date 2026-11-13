# Быстрый запуск adPEAS-RU 2.9.0

Это руководство позволяет провести первый разрешённый аудит
Active Directory, создать отчёт и исследовать его результаты.
**Полный перечень ключей** находится в начале
[README_RU.md](../../README_RU.md).

## Шаг 1. Откройте Windows PowerShell 5.1

Для русской версии перейдите в каталог `adPEAS-RU`:

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local'
~~~

Обёртка создаст HTML, TXT и JSON в `Reports`.
`OPSEC` и `LDAPS` включены по умолчанию, TLS-сертификат DC
проверяется. Результат зависит от разрешений аудиторской
учётной записи и доступных служб.

## Шаг 2. Выберите тип запуска

### Прямой запуск одной командой (совместим с v1)

~~~powershell
Import-Module .\adPEAS.ps1 -Force
Invoke-adPEAS -Domain 'example.local' -UseWindowsAuth
~~~

**Важное отличие:** у прямого `Invoke-adPEAS` нет
включённого по умолчанию `-OPSEC` и явной проверки
TLS как у русской обёртки. Для обычного аудита используйте
обёртку либо двухшаговое подключение ниже.

### Сессия v2 (рекомендуется при использовании исходных функций)

~~~powershell
Import-Module .\adPEAS.ps1 -Force

Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false

Invoke-adPEAS -OPSEC
Get-DomainUser -Identity 'audit.account'
Get-adPEASSession -TestConnection
Disconnect-adPEAS
~~~

При повторных вызовах сессия сохраняется. Перед запуском
отдельных функций можно проверить их синтаксис через
`Get-Command <Имя> -Syntax`.

### Сессия с Tab-дополнением

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false -BuildCompletionCache
Get-DomainUser -Identity adm
Get-DomainGroup -Identity 'Domain Admins'
Get-DomainGPO -Identity 'Default Domain Policy'
~~~

Кэш строится через дополнительные LDAP-запросы и
увеличивает время первоначального подключения.

## Сценарии аудита

### 1. Доменный компьютер

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local'
~~~

Использует текущую запись Windows.

### 2. Компьютер вне домена

~~~powershell
$cred = Get-Credential
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -Credential $cred
~~~

Нужны DNS и сетевой доступ до контроллера.
Не записывайте пароль открытым текстом в скриптах.

### 3. Определённый контроллер домена

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' `
    -Server 'dc01.example.local'
~~~

### 4. Зашифрованный LDAP

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -UseLDAPS
~~~

Для корректной проверки сертификата используйте
FQDN, доверенный УЦ, действующий срок и SAN.

### 5. OPSEC и что он исключает

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -OPSEC
~~~

OPSEC исключает определённые активные операции:
запросы Kerberoast и AS-REP Roasting, сбор BloodHound,
а также отдельные обращения SMB к файловым серверам
по ссылкам GPO и NETLOGON ради проверки NTFS-прав.
Это **не полная изоляция от LDAP или сети**.

### 6. Показывать привилегированных субъектов

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -IncludePrivileged
~~~

В исходной логике часть ожидаемых привилегированных
назначений без этого флага скрыта, чтобы выделить
необычные права. При включении они могут показываться
как информационные / ожидаемые, а не как уязвимости.

### 7. Только нужные модули

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' `
    -Module Domain,Accounts,GPO,ADCS -Format All

.\Run-AD-Audit-RU.ps1 -Domain 'example.local' `
    -ExcludeModule Shares,Bloodhound
~~~

Допустимые имена: `Domain`, `Creds`, `Rights`,
`Delegation`, `ADCS`, `Accounts`, `GPO`,
`Computer`, `Application`, `Shares`, `Bloodhound`.

### 8. Форматы результата

~~~powershell
# В обёртке каталог задаётся отдельно от формата
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -Format HTML
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -Format JSON
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -Format Text
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -Format All

# В исходной функции путь задаётся базовым именем без расширения
Invoke-adPEAS -Format HTML -Outputfile '.\Reports\audit' -OPSEC
~~~

| Формат | Результат |
|---|---|
| `All` | TXT + HTML + JSON |
| `Text` | Текстовый отчёт; в исходной функции могут быть ANSI-цвета |
| `HTML` | Интерактивные карточки, фильтры, поиск, справка |
| `JSON` | Машинные данные для сравнения и повторной генерации |

### 9. Подробное логирование исходной функции

~~~powershell
Invoke-adPEAS -Module Domain,GPO -Outputfile '.\Reports\verbose-audit' `
    -VerboseLogging -NoColor -OPSEC
~~~

`-VerboseLogging` включает `-Verbose` и отправляет
подробные сообщения в текстовый отчёт. Этот флаг
**не поддерживается** русской обёрткой.

### 10. Инкрементальный аудит

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEAS -Module Domain -Outputfile '.\Reports\audit' -OPSEC
Invoke-adPEAS -Module Accounts -Outputfile '.\Reports\audit' `
    -OutputAppend -OPSEC
Invoke-adPEAS -Module Rights,GPO -Outputfile '.\Reports\audit' `
    -OutputAppend -OPSEC
Disconnect-adPEAS
~~~

`-OutputAppend` объединяет новые находки с существующим
JSON-кэшем; HTML заново формируется из совмещённых данных,
а TXT дополняется новыми строками. Без `-OutputAppend`
существующие файлы перезаписываются.

### 11. Пересоздание отчёта офлайн

~~~powershell
Import-Module .\adPEAS.ps1 -Force
Convert-adPEASReport -InputJson '.\Reports\audit.json' `
    -OutputPath '.\Reports\audit-new' -Format All

Convert-adPEASReport -InputJson '.\Reports\audit.json' `
    -OutputPath '.\Reports\audit-html' -Format HTML

Convert-adPEASReport -InputJson '.\Reports\audit.json' `
    -OutputPath '.\Reports\audit-text' -Format Text -NoColor

Convert-adPEASReport -InputJson '.\Reports\audit.json' `
    -OutputPath '.\Reports\audit-json' -Format JSON
~~~

LDAP-соединение не требуется, если JSON уже доступен.
Это удобно для проверки обновлённого русского оформления.

### 12. Сравнение двух запусков

~~~powershell
Compare-adPEASReport -Baseline '.\Reports\before.json' `
    -Current '.\Reports\after.json' -OutputPath '.\Reports\diff'
~~~

Сравнение выделяет новые, устранённые и изменившиеся
находки, а также статистику.

### 13. BloodHound CE

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEASCollector -CollectionMethod DCOnly `
    -OutputPath '.\Reports\bloodhound.zip'
Disconnect-adPEAS
~~~

По умолчанию `DCOnly` собирает доступные LDAP-данные.
Можно указать `ACL`, `ObjectProps`, `Trusts`,
`Container`, `CertServices`. Сборщик **не является**
частью режима OPSEC: оценивайте сетевую нагрузку и
используйте его только с разрешения.

## Отдельные проверки

После подключения доступны функции вроде:

~~~powershell
Get-KerberoastableAccounts
Get-ASREPRoastableAccounts
Get-UnconstrainedDelegation
Get-ConstrainedDelegation
Get-DomainTrusts
Get-PrivilegedGroupMembers
Get-DangerousACLs
Get-ADCSVulnerabilities
Get-NetworkMap
~~~

В оригинальном руководстве также приведён
`Invoke-ShareHunt` (поиск доступных ресурсов)
и `Invoke-PortScan` для отдельно разрешённого
исследования сети. Оба могут создавать дополнительную
нагрузку и не должны запускаться по умолчанию.
Некоторые проверки имеют собственные `-IncludeInactive`
или `-IncludeDefaults` — сверяйтесь с
`Get-Command <Имя> -Syntax`.

## Чтение результатов

Оригинальный вывод использует обозначения:

| Знак | Смысл |
|---|---|
| `[?]` | Заголовок раздела |
| `[!]` | Находка или риск |
| `[+]` | Признак, заслуживающий внимания |
| `[*]` | Информация |
| `[#]` | Защищённая конфигурация |

Обновлённый русский HTML содержит раскрываемые
пояснения Impact/Attack/Remediation, а также оригинальный
английский текст для сверки. Не трактуйте защищённые
настройки и предупреждения как доказанную компрометацию.

## Завершение сессии

~~~powershell
Get-adPEASSession
Get-adPEASSession -TestConnection
Disconnect-adPEAS
~~~

## Дополнительные практические примеры оригинала (DOC5)

### Сессия v2 и Tab-дополнение

В исходном справочнике приведены два эквивалентных стиля: однокомандный вызов Invoke-adPEAS с параметрами подключения или многократное использование соединения, созданного Connect-adPEAS. Второй позволяет после полного аудита запускать нужные проверки без повторного создания сессии.

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth -UseLDAPS -IgnoreSSLErrors:$false -BuildCompletionCache
Invoke-adPEAS -OPSEC
Get-DomainUser -Identity 'aud'
Get-DomainGroup -Identity 'Domain Admins'
Get-DomainGPO -Identity 'Default Domain Policy'
Disconnect-adPEAS
~~~

BuildCompletionCache дополнительно перечисляет объекты для Tab-дополнения и увеличивает первоначальный объём запросов. Запись [TAB] в исходных примерах означает нажатие клавиши, а не буквальный параметр.

### Все варианты формата и подробное логирование

Outputfile исходной функции задаёт базовое имя отчёта без расширения. При Format All формируются TXT, HTML и JSON. NoColor позволяет читать текст в редакторах без ANSI-последовательностей; VerboseLogging автоматически включает подробный вывод в консоль и сохраняет диагностические сообщения с временем в TXT.

~~~powershell
Invoke-adPEAS -Domain 'example.local' -UseWindowsAuth -OPSEC -Outputfile '.\Reports\audit' -Format All
Invoke-adPEAS -Domain 'example.local' -UseWindowsAuth -OPSEC -Outputfile '.\Reports\text' -Format Text -NoColor
Invoke-adPEAS -Domain 'example.local' -UseWindowsAuth -OPSEC -Outputfile '.\Reports\html' -Format HTML
Invoke-adPEAS -Domain 'example.local' -UseWindowsAuth -OPSEC -Outputfile '.\Reports\diagnostic' -VerboseLogging
~~~

В русской обёртке Run-AD-Audit-RU.ps1 параметры пути и диагностики отличаются от исходной функции. Не передавайте VerboseLogging обёртке как будто это её собственный ключ.

### Инкрементальные проверки, офлайн-отчёт и сравнение

OutputAppend добавляет результаты новых модулей к JSON-кэшу с тем же Outputfile и пересоздаёт объединённый HTML. Без этого ключа готовые файлы могут перезаписываться.

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEAS -Module Domain -Outputfile '.\Reports\audit' -OPSEC
Invoke-adPEAS -Module Creds,Rights -Outputfile '.\Reports\audit' -OutputAppend -OPSEC
Invoke-adPEAS -Module ADCS,Delegation -Outputfile '.\Reports\audit' -OutputAppend -OPSEC
Disconnect-adPEAS

Convert-adPEASReport -InputJson '.\Reports\audit.json' -OutputPath '.\Reports\rebuilt' -Format All
Convert-adPEASReport -InputJson '.\Reports\audit.json' -OutputPath '.\Reports\rebuilt_html' -Format HTML
Convert-adPEASReport -InputJson '.\Reports\audit.json' -OutputPath '.\Reports\rebuilt_text' -Format Text -NoColor
Convert-adPEASReport -InputJson '.\Reports\audit.json' -OutputPath '.\Reports\rebuilt_json' -Format JSON

Compare-adPEASReport -Baseline '.\Reports\scan_q1.json' -Current '.\Reports\scan_q2.json'
Compare-adPEASReport -Baseline '.\Reports\scan_jan.json' -Current '.\Reports\scan_apr.json' -OutputPath '.\Reports\diff_report'
~~~

Конвертация из JSON не требует активного LDAP, но не обновляет собранные данные. При сравнении необходимо одинаковое покрытие модулей и полномочий; разницу в режимах OPSEC нельзя выдавать за улучшение безопасности.

### Повторение отдельной проверки и диагностика команд

В полном консольном аудите имя функции проверки показывается в скобках после заголовка раздела. Можно найти нужную функцию и запустить её отдельно. В HTML и текстовом отчёте её имя намеренно опускается для более читаемого представления; при прямом вызове оно уже известно оператору.

~~~powershell
Get-Command Get-KerberoastableAccounts -Syntax
Get-Command Get-DomainTrusts -Syntax
Get-adPEASSession
Get-adPEASSession -TestConnection
~~~

Для некоторых проверок доступны IncludeInactive и IncludeDefaults — значения необходимо сверять по синтаксису самой функции. Invoke-PortScan с явно заданными целями может использоваться без сессии, но является активным сетевым сканированием и требует согласования нагрузки.


## Навигация

[Установка](01-Installation.md) ·
[Аутентификация](03-Authentication-Methods.md) ·
[Полный перечень параметров](../../README_RU.md) ·
[Главная](00-Home.md)
