# Часто задаваемые вопросы об adPEAS v2.9.0

Ответы относятся к закреплённой версии
adPEAS 2.9.0 и русской обёртке adPEAS-RU.
Полный синтаксис основных ключей —
в начале [README_RU.md](../../README_RU.md).

## Общие вопросы

### Что такое adPEAS?

**adPEAS (Active Directory Privilege Escalation Awesome Scripts)**
— инструмент на PowerShell для поиска ошибочных
конфигураций безопасности, опасных прав и
путей повышения привилегий в AD. Предназначен
для разрешённых аудитов и тестирования на проникновение.

### Чем adPEAS отличается от PowerView и ADModule?

| Свойство | adPEAS v2 | PowerView | ADModule |
|---|---|---|---|
| Внешние модули | Не нужны | Не нужны | RSAT |
| Автономный файл | Да | Да | Нет |
| Kerberos / сертификаты / ключи | Расширенный набор | Ограничено | Ограничено |
| Систематические проверки безопасности | Да | В основном перечисление | Не специализирован для аудита |
| OPSEC | Есть | Нет отдельного режима | Нет |
| Формирование отчётов | TXT, HTML, JSON | В основном исходные данные | В основном исходные данные |

Количество проверок зависит от версии и
выбранных модулей; старые числа из
английского FAQ не следует считать
текущей спецификацией.

### Заменяет ли adPEAS BloodHound?

**Нет.** adPEAS оценивает конфигурацию и
выводит конкретные находки с рекомендациями.
BloodHound строит граф связей и путей атак.
Инструменты дополняют друг друга; adPEAS
может экспортировать данные BloodHound CE.

### Какая версия PowerShell нужна?

Для проверенной русской сборки — **Windows
PowerShell 5.1**. PowerShell Core 6+ не
гарантирован из-за зависимостей от
.NET Framework и особенностей Windows.

### Нужны ли RSAT и модуль ActiveDirectory?

**Нет.** Используются классы .NET,
включая `System.DirectoryServices.Protocols`.

### Можно ли запустить с компьютера вне домена?

Да, если есть сетевой маршрут, DNS и
учётные данные:

~~~powershell
$cred = Get-Credential
Connect-adPEAS -Domain 'example.local' -Credential $cred `
    -UseLDAPS -IgnoreSSLErrors:$false
~~~

При необходимости задайте `-Server` и
`-DnsServer`; сертификат DC должен быть
доверенным для выбранного имени.

### Поддерживает ли прокси/туннель?

Встроенного SOCKS-клиента нет.
Исходный проект описывает работу через
локальные перенаправления портов (например SSH),
но это не заменяет настройку DNS, Kerberos,
сертификатов LDAPS и прав.
Для медленных каналов доступен `-TimeoutSeconds`,
5–600 секунд:

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false -TimeoutSeconds 120
~~~

Подробнее: [Решение проблем](11-Troubleshooting.md).

---

## Аутентификация

### Какой способ выбрать?

| Ситуация | Предпочтительный параметр |
|---|---|
| Доменный компьютер | `-UseWindowsAuth` |
| Другая учётная запись | `-Credential` |
| Сертификат собственной учётной записи | `-Certificate` |
| Требуется Schannel без Kerberos | `-Certificate` и `-ForcePassTheCert` |
| Специализированная разрешённая проверка по хешу/ключу | `-NTHash`, `-AES128Key`, `-AES256Key` |
| Уполномоченная проверка с билетом | `-Kirbi` или `-Ccache` |

Для обычной внутренней инвентаризации не
требуются хеши, ключи или импорт билетов.

### Почему сначала Kerberos?

Это нативный механизм аутентификации Windows.
При парольных способах adPEAS пробует Kerberos,
затем NTLM impersonation и SimpleBind,
если fallback разрешён и они поддерживаются.
Режимы NT-хеша и AES требуют Kerberos.

### Как использовать SimpleBind?

Функция поддерживает `-ForceSimpleBind`,
но простой bind без TLS не следует применять
для передачи пароля. Предпочитайте безопасную
обёртку с LDAPS и проверкой сертификата.

### Как применить NTLM, не меняя билеты Kerberos?

С учётными данными можно выбрать `-ForceNTLM`.
Он работает как `runas /netonly` и не заменяет
текущий кэш билетов. Политики AD могут
запрещать NTLM.

### Можно ли подключиться по сертификату?

Да, через PKINIT (`-Certificate`) либо
Schannel (`-ForcePassTheCert`). Для PKINIT
нужен Kerberos, для Schannel — TLS/LDAPS.
Требования к сертификату и сопоставлению
учётной записи различаются.

### Можно ли использовать NT-хеш, AES-ключ, Kirbi/Ccache?

Реализация поддерживает эти методы для
специализированных тестов с явным разрешением.
Реальные секреты не следует указывать
непосредственно в командной строке.
[Подробнее](03-Authentication-Methods.md).

---

## Вопросы по проверкам

### Что делает OPSEC?

Пропускает некоторые активные операции:
Kerberoasting, AS-REP Roasting, BloodHound
collection, а также определённые SMB-чтения
файловых серверов и NETLOGON, названных
в GPO или путях входа пользователя.

LDAP-перечисление других данных продолжает
работать. OPSEC не означает отсутствия
сетевых соединений или отсутствия журналов.

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -OPSEC
~~~

### Можно ли выбрать только определённые разделы?

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' `
    -Module Domain,Rights,GPO

# Исключить из общего аудита несколько модулей
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' `
    -ExcludeModule Bloodhound,Computer

# В исходной функции ExcludeModule вычитается из Module
Invoke-adPEAS -Module Domain,Rights,GPO -ExcludeModule GPO -OPSEC
~~~

Доступны `Domain`, `Creds`, `Rights`,
`Delegation`, `ADCS`, `Accounts`,
`GPO`, `Computer`, `Application`,
`Shares`, `Bloodhound`.

### Какие AD CS ESC проверки реализованы?

В исходном FAQ перечислены:
**ESC1**, **ESC2**, **ESC3**, **ESC4**,
**ESC8**, **ESC9**, **ESC13**, **ESC15**.
Например, ESC8 анализирует HTTP/HTTPS,
NTLM и EPA веб-эндпоинтов выдачи, ESC9 —
отсутствие расширения безопасности сертификата,
ESC13 — issuance policy, связанную с группой,
ESC15 — старую версию схемы шаблона и
CVE-2024-49019.

**ESC6 и ESC7** оригинал не включает в
эту LDAP-проверку, поскольку для них
требуется чтение конфигурации УЦ через
другие протоколы (RPC/DCOM).

~~~powershell
Get-ADCSVulnerabilities
~~~

---

## Выходные файлы

### Как сохранить результаты?

~~~powershell
# Русская обёртка, все три формата
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -Format All

# Исходная функция: базовое имя без расширения
Invoke-adPEAS -Outputfile '.\Reports\audit' -Format All -OPSEC
Invoke-adPEAS -Outputfile '.\Reports\audit-text' -Format Text -NoColor -OPSEC
Invoke-adPEAS -Outputfile '.\Reports\audit-html' -Format HTML -OPSEC
~~~

**Исправление старого FAQ:** формат `All` в
актуальном проекте создаёт **TXT, HTML и JSON**,
а не только TXT и HTML.

### Как объединить результаты нескольких запусков?

У исходной `Invoke-adPEAS` есть ключ `-OutputAppend`.
Он добавляет данные новых модулей к существующему JSON
и пересоздаёт общий HTML; необходим `-Outputfile`:

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEAS -Module Domain -OPSEC -Outputfile '.\\Reports\\combined'
Invoke-adPEAS -Module Accounts -OPSEC -Outputfile '.\\Reports\\combined' -OutputAppend
Disconnect-adPEAS
~~~

Русская обёртка `Run-AD-Audit-RU.ps1` не имеет ключа
`-OutputAppend`; для последовательного объединения
используйте исходные функции.

### Почему не отображаются цвета?

Старые терминалы могут не обрабатывать
ANSI-последовательности. Используйте
Windows Terminal либо `-NoColor` в
`Invoke-adPEAS`. В обёртке отдельного
ключа `-NoColor` нет.

### Что означают значки?

| Метка | Значение |
|---|---|
| `[?]` | Заголовок и справка |
| `[!]` | Находка / риск |
| `[+]` | Признак для изучения |
| `[*]` | Информация |
| `[#]` | Защищённая конфигурация |

### Можно ли проверить несколько доменов?

Да, **последовательно**, создавая новую
сессию для следующего домена:

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEAS -Outputfile '.\Reports\example' -Format All -OPSEC
Disconnect-adPEAS

Connect-adPEAS -Domain 'other.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEAS -Outputfile '.\Reports\other' -Format All -OPSEC
Disconnect-adPEAS
~~~

---

## Версии и обновления

### Какую сборку выбрать?

| Файл | Сценарий |
|---|---|
| `adPEAS.ps1` | Разработка, анализ и отладка |
| `adPEAS_min.ps1` | Обычный запуск |
| `adPEAS_ultra.ps1` | Минимальный объём |
| `adPEAS_obf.ps1` | Обфусцированная поставка |

### Как обновить модуль?

Получите новую проверенную сборку, завершите
старую сессию PowerShell, замените файлы и
импортируйте снова:

~~~powershell
Remove-Module adPEAS -ErrorAction SilentlyContinue
Import-Module .\adPEAS.ps1 -Force
~~~

Старые сохранённые HTML не обновляются;
для нового перевода создайте новый отчёт.

---

## Правовые вопросы

### Законно ли использование?

Да, при наличии права проводить аудит
соответствующих систем и соблюдении
действующих законов и лицензии автора.
Для профессиональных работ необходимо
письменное разрешение владельца,
согласованная область проверки и
правила взаимодействия.

### Нужна ли коммерческая лицензия?

Лицензия adPEAS является **source-available**.
Внутреннее некоммерческое использование
своей организации допускается в обозначенных
автором случаях. Услуги клиентам и
платные работы требуют коммерческой лицензии.
[Условия](../../license/LICENSE.md).

## Дополнительные вопросы исходного FAQ (DOC5)

### Можно ли использовать NT-хеш при аудите?

Оригинальная функция принимает NTHash (32 шестнадцатеричных символа), но это специализированная аутентификация Kerberos, для которой нет парольного NTLM/SimpleBind fallback. Для обычного разрешённого аудита предпочтительны Credential и LDAPS с проверкой сертификата.

~~~powershell
# Только формат параметра, а не действительные учётные данные.
Connect-adPEAS -Domain 'example.local' -Username 'auditor' -NTHash '<32_hex_chars>'
~~~

### Можно ли подключиться по сертификату, если TCP/88 закрыт?

PKINIT зависит от Kerberos. Режим ForcePassTheCert использует сертификат через TLS/LDAPS (обычно TCP/636) и работает иначе, чем PKINIT. Сертификат должен корректно сопоставляться с учётной записью; сертификат Shadow Credentials не является универсальной заменой Schannel-сертификата.

~~~powershell
Connect-adPEAS -Domain 'example.local' -Certificate 'C:\Certs\auditor.pfx' -CertificatePassword (Read-Host 'Пароль PFX' -AsSecureString) -ForcePassTheCert -IgnoreSSLErrors:$false
~~~

### Как работает совместное использование Module и ExcludeModule?

Module определяет исходный набор категорий, а ExcludeModule исключает указанные категории из него. Это важно для воспроизводимости и сравнения отчётов разных запусков.

~~~powershell
Invoke-adPEAS -Module ADCS -OPSEC
Invoke-adPEAS -Module Domain,Accounts,Creds -OPSEC
Invoke-adPEAS -ExcludeModule Bloodhound -OPSEC
Invoke-adPEAS -Module Domain,Rights,GPO -ExcludeModule GPO -OPSEC
~~~

### Какие проверки AD CS не охватывает LDAP?

В английском FAQ отмечаются ограничения ESC6 и ESC7: для оценки некоторых настроек CA требуется реестр/RPC или DCOM/RPC, а не только LDAP. Отсутствие этих находок в отчёте не доказывает отсутствие небезопасных настроек центра сертификации.

~~~powershell
Get-ADCSVulnerabilities
~~~

### Есть ли встроенная поддержка SOCKS и что с туннелями?

Встроенного SOCKS-клиента нет. При работе через имеющийся туннель отдельно проверяйте DNS, Kerberos, маршрут до контроллера и соответствие имени SAN сертификата LDAPS. Использование 127.0.0.1 вместо FQDN контроллера может нарушить проверку TLS. Для медленных подключений есть TimeoutSeconds.

~~~powershell
$cred = Get-Credential
Connect-adPEAS -Domain 'example.local' -Server 'dc01.example.local' -Credential $cred -UseLDAPS -IgnoreSSLErrors:$false -TimeoutSeconds 120
~~~

### Нужны ли письменное разрешение и коммерческая лицензия?

Для профессионального аудита предварительно согласуйте владельца инфраструктуры, область, временное окно, допустимую нагрузку, порядок обращения с паролями и отчётами. Возможность технически запустить инструмент без лицензии не отменяет коммерческих условий автора. Для воспроизводимости сохраняйте SHA-256 архива и сведения о версии, указанной в отчёте.

## Навигация

[Решение проблем](11-Troubleshooting.md) ·
[Главная](00-Home.md) ·
[Синтаксис ключей](../../README_RU.md)
