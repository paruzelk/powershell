# <a id="architecture"></a>Архитектура

Технический обзор архитектуры adPEAS v2.

---

## <a id="design-principles"></a>Принципы проектирования

### <a id="1-zero-external-dependencies"></a>1. Без внешних зависимостей

adPEAS использует только встроенные классы .NET Framework:

- `System.DirectoryServices.Protocols.LdapConnection` — единый интерфейс LDAP (запросы и изменения).
- `System.DirectoryServices.Protocols.SearchRequest` — поисковые LDAP-запросы.
- `System.DirectoryServices.Protocols.ModifyRequest` — изменение LDAP (Set-DomainObject).
- `System.DirectoryServices.ActiveDirectorySecurity` — разбор и изменение ACL.
- `System.Security.Principal` — работа с SID.
- `System.Security.Cryptography` — криптография Kerberos.
- `System.Net` — сетевые операции.

**Примечание**: adPEAS v2 использует **единую архитектуру LdapConnection**. Все LDAP-операции (запросы, чтение схемы и изменения) выполняются через `System.DirectoryServices.Protocols.LdapConnection` вместо прежнего сочетания `DirectoryEntry`/`DirectorySearcher`. Это обеспечивает:
- Улучшенную поддержку LDAPS (встроенная работа с SSL/TLS).
- Единообразное поведение всех операций.
- Доступ к разделам Configuration и Schema.
- Единый механизм аутентификации.

### <a id="2-standalone-deployment"></a>2. Автономное развёртывание

Итоговый продукт — один файл .ps1:

- Во время сборки объединяются все модули.
- Не нужны дополнительные файлы или зависимости.
- Удобно переносить и запускать.
- Работает на Windows с PowerShell 5.1 и новее.

### <a id="3-auth-agnostic-architecture"></a>3. Независимость от способа аутентификации

Аутентификация выполняется однократно при соединении. Все последующие операции не зависят от выбранного способа входа.

### <a id="4-layered-design"></a>4. Многоуровневая структура

Получение данных, анализ безопасности и форматирование вывода чётко разделены.

---

## <a id="module-architecture"></a>Архитектура модулей

```
+-------------------------------------------------------+
|                      adPEAS.ps1 (Main)                |
|                    Orchestration Layer                |
+---------------------------+---------------------------+
                            |
        +-------------------+-------------------+
        |                   |                   |
+-------v-------+   +-------v-------+   +-------v-------+
|    Helpers    |   |     Core      |   |    Checks     |
+---------------+   +---------------+   +---------------+
| Convert*      |<--| Get-Domain*   |<--| Security      |
| Ensure*       |   | Invoke-LDAP*  |   | Analyses      |
| Test-*        |   | Connect-*     |   | Findings      |
| Kerberos*     |   | Set-Domain*   |   |               |
+-------+-------+   +-------+-------+   +-------+-------+
        |                   |                   |
        +-------------------+-------------------+
                            |
                    +-------v-------+
                    |   Reporting   |
                    +---------------+
                    | Text Export   |
                    | Console Out   |
                    +---------------+
```

---

## <a id="data-flow"></a>Поток данных

```
1. User Input (Parameters)
         |
         v
2. Authentication (Connect-adPEAS)
         |
         v
3. LDAP Connection ($Script:LdapConnection)
         |
         v
4. Data Caching ($Script:LDAPContext)
         |
         v
5. Check Execution (Check Modules)
         |
         v
6. Finding Generation
         |
         v
7. Output Formatting (Show-* functions)
         |
         v
8. Report (Console/File)
```

---

## <a id="module-hierarchy"></a>Иерархия модулей

### <a id="call-hierarchy"></a>Иерархия вызовов

```
Check Module
    |
    +-> Get-DomainUser / Get-DomainGroup / Get-DomainComputer / Get-DomainGPO
    |       |
    |       +-> Get-DomainObject
    |               |
    |               +-> Invoke-LDAPSearch
    |                       |
    |                       +-> $Script:LdapConnection (LdapConnection)
    |
    +-> Get-ObjectACL (ACL analysis checks)
    +-> Get-CertificateTemplate / Get-CertificateAuthority (ADCS checks)
```

### <a id="rules"></a>Правила

1. **Модули проверок**: вызывают Get-Domain*, Get-ObjectACL, Get-CertificateTemplate и Get-CertificateAuthority.
2. **Функции Get-Domain**: вызывают только Get-DomainObject.
3. **Get-DomainObject**: вызывает только Invoke-LDAPSearch.
4. **Invoke-LDAPSearch**: использует только `$Script:LdapConnection`.
5. **Set-DomainObject**: отправляет `ModifyRequest` через `$Script:LdapConnection`.

---

## <a id="session-management"></a>Управление сеансом

### <a id="session-variables"></a>Переменные сеанса

| Переменная | Тип | Назначение |
|----------|------|---------|
| `$Script:LdapConnection` | LdapConnection | Используется для ВСЕХ операций LDAP (чтение и изменение) |
| `$Script:LDAPContext` | Hashtable | Метаданные сеанса: домен, сервер, сведения об аутентификации |
| `$Script:LDAPCredential` | PSCredential | Хранимые учётные данные |
| `$Script:SIDResolutionCache` | Hashtable | Кеш преобразования SID в имена |

### <a id="unified-ldapconnection-architecture"></a>Единая архитектура LdapConnection

Все LDAP-операции выполняются через `$Script:LdapConnection`:

```
+-------------------------------------------------------+
|                    Connect-LDAP                       |
|                Creates LdapConnection                 |
+---------------------------+---------------------------+
                            |
                            v
+-------------------------------------------------------+
|           $Script:LdapConnection                      |
|        (System.DirectoryServices.Protocols)           |
+---------------------------+---------------------------+
                            |
        +-------------------+-------------------+
        |                   |                   |
        v                   v                   v
+---------------+   +---------------+   +---------------+
| SearchRequest |   | ModifyRequest |   |  Anonymous    |
| (Queries)     |   | (Set-*)       |   |  Bind Test    |
+---------------+   +---------------+   +---------------+
```

**Подключение к глобальному каталогу**: `Connect-LDAP -AsGlobalCatalog` создаёт второе соединение с GC (порт 3268 для LDAP, 3269 для LDAPS). `ConvertFrom-SID` использует его для разрешения SID из других доменов леса. Соединение GC кешируется в `$Script:GCConnection` и закрывается через `Disconnect-adPEAS`. Если GC недоступен, SID возвращается в формате на основе RID.

### <a id="ldapcontext-structure"></a>Структура LDAPContext

```powershell
$Script:LDAPContext = @{
    Domain              = "contoso.com"
    DomainDN            = "DC=contoso,DC=com"
    Server              = "dc01.contoso.com"
    Protocol            = "LDAP"           # or "LDAPS"
    Port                = 389              # or 636
    AuthMethod          = "Kerberos"       # or "NTLM Impersonation", "SimpleBind", "WindowsSSPI"
    KerberosUsed        = $true
    AuthenticatedUser   = "CONTOSO\john.doe"
    SchemaNamingContext = "CN=Schema,CN=Configuration,DC=contoso,DC=com"
    ConfigurationNamingContext = "CN=Configuration,DC=contoso,DC=com"
    DomainSID           = "S-1-5-21-..."
    AnonymousAccessEnabled = $false        # Security check result
}
```

---

## <a id="authentication-flow"></a>Последовательность аутентификации

### <a id="kerberos-first-design"></a>Приоритет Kerberos

```
+-------------------+
| Connect-adPEAS    |
| (Entry Point)     |
+---------+---------+
          |
          v
+-------------------+      Success      +-------------------+
| Invoke-Kerberos   |------------------>| Import-Kerberos   |
| Auth (TGT)        |                   | Ticket (PTT)      |
+---------+---------+                   +---------+---------+
          |                                       |
          | Failure                               v
          v                             +-------------------+
+-------------------+                   | Connect-LDAP      |
| NTLM              |                   | (Kerberos auth)   |
| Impersonation     |                   +---------+---------+
| (Fallback 1)      |                             |
+---------+---------+                             |
          |                                       |
          | Failure                               |
          v                                       |
+-------------------+                             |
| SimpleBind        |                             |
| (Fallback 2)      |                             |
+---------+---------+                             |
          |                                       |
          +-------------------+-------------------+
                              |
                              v
                    +-------------------+
                    | $Script:LDAP      |
                    | Connection        |
                    +-------------------+
```

### <a id="authentication-methods"></a>Способы аутентификации

| Способ | Попытка Kerberos | Резервный способ |
|--------|-----------------|----------|
| Windows Auth | SSPI (автоматически) | Нет |
| PSCredential | TGT + TGS + PTT | Имперсонация NTLM → SimpleBind |
| Имя пользователя/пароль | TGT + TGS + PTT | Имперсонация NTLM → SimpleBind |
| Хеш NT | TGT (RC4) + TGS + PTT | Нет |
| Ключ AES256 | TGT (AES256) + TGS + PTT | Нет |
| Ключ AES128 | TGT (AES128) + TGS + PTT | Нет |
| Сертификат | PKINIT + TGS + PTT | Нет |
| Kirbi | PTT | Нет |
| Ccache | PTT | Нет |

---

## <a id="output-architecture"></a>Архитектура вывода

### <a id="unified-rendermodel-pipeline"></a>Единый конвейер RenderModel

adPEAS использует единый конвейер формирования представления: одна модель данных управляет выводом в консоль и HTML:

```
+----------------------------------------------------------+
|                    Check Module                          |
|           Returns structured finding objects             |
+---------------------------+------------------------------+
                            |
                            v
+----------------------------------------------------------+
|              Get-RenderModel (Model Builder)             |
|    - Object type detection (User/Computer/GPO/Cert)      |
|    - Attribute ordering and classification               |
|    - Delegates to AttributeTransformers per attribute    |
|    - Returns: { Primary, Extended, PostObject } model    |
+---------------------------+------------------------------+
                            |
              +-------------+-------------+
              |                           |
              v                           v
+---------------------------+  +---------------------------+
| Render-ConsoleObject      |  | Render-HtmlObject         |
| - ANSI color codes        |  | - HTML table rows         |
| - Prefix ([!],[+],etc.)   |  | - Severity CSS classes    |
| - Multivalue alignment    |  | - Tooltip integration     |
| - AlignAt column layout   |  | - Collapsible sections    |
+---------------------------+  +---------------------------+
              |                           |
              v                           v
+---------------------------+  +---------------------------+
| Write-adPEASOutput        |  | Export-HTMLReport         |
| - Console + Text file     |  | - Full HTML report        |
+---------------------------+  +---------------------------+
```

**Основные компоненты:**

| Компонент | Файл | Назначение |
|-----------|------|---------|
| `Get-RenderModel` | `Get-RenderModel.ps1` | Создаёт независимую от рендерера модель данных из объектов AD |
| `AttributeTransformers` | `AttributeTransformers.ps1` | Преобразования атрибутов (memberOf, UAC, SPN и др.) |
| `Get-AttributeSeverity` | `AttributeTransformers.ps1` | Классифицирует значения атрибутов по значимости для безопасности |
| `Render-ConsoleObject` | `Render-ConsoleObject.ps1` | Отображает модель в консоли с цветами |
| `Render-HtmlObject` | `Render-HtmlObject.ps1` | Формирует строки HTML-таблиц и всплывающие подсказки |
| `Write-adPEASOutput` | `Write-adPEASOutput.ps1` | Низкоуровневый вывод (ANSI, запись в файл, префиксы) |

**Структура RenderModel:**

```powershell
@{
    Primary = @(           # Always-visible attributes (severity != Standard)
        @{ Name; RowType; OverallSeverity; Values = @(
            @{ Display; Severity; FindingId; RawValue; Metadata }
        )}
    )
    Extended = @(          # Collapsible attributes (severity == Standard)
        # Та же структура, что и Primary
    )
    PostObject = @(        # Post-object lines (e.g., activityStatus)
        @{ Text; Severity }
    )
}
```

### <a id="semantic-output-functions"></a>Семантические функции вывода

Модули проверок используют обёртки, передающие данные в конвейер RenderModel:

```powershell
# Показать объект AD со всеми свойствами
Show-Object $user
# Внутри: Get-RenderModel -> Render-ConsoleObject + Render-HtmlObject

# Показать текст находки
Show-Line "Finding text" -Class Finding
# Внутри: Write-adPEASOutput с соответствующим форматированием

# Заголовки разделов
Show-Header "Analyzing Security"
# Внутри: Write-adPEASOutput с классом Header

# Заголовки подразделов
Show-SubHeader "Searching for accounts..."
# Внутри: Write-adPEASOutput с классом SubInfo
```

**Доступные функции** (определены в `adPEAS-Messages.ps1`):
- `Show-Header` — заголовок раздела с декоративными линиями.
- `Show-SubHeader` — заголовок подраздела.
- `Show-Line` — строка вывода с необязательным оформлением.
- `Show-KeyValue` — пары ключ-значение с выравниванием.
- `Show-Object` — вывод объекта AD через RenderModel.
- `Show-Logo` — логотип adPEAS.

---

## <a id="check-module-pattern"></a>Шаблон модуля проверки

Модули проверок используют общий шаблон:

```powershell
function Get-SecurityCheck {
    [CmdletBinding()]
    param(
        [string]$Domain,
        [string]$Server,
        [PSCredential]$Credential
    )

    begin {
        Write-Verbose "[Get-SecurityCheck] Starting check"
    }

    process {
        # 1. Обеспечить наличие подключения
        if (-not (Ensure-LDAPConnection @PSBoundParameters)) {
            return
        }

        # 2. Показать заголовок раздела
        Show-SubHeader "Analyzing security configuration..."

        # 3. Получить данные через Get-Domain*
        $data = Get-DomainUser -LDAPFilter "(condition=*)" @PSBoundParameters

        # 4. Проанализировать и вывести находки
        foreach ($item in $data) {
            if ($item.IsVulnerable) {
                Show-Object $item
            }
        }

        # 5. Итоговое сообщение
        if ($findings.Count -eq 0) {
            Show-Line "No issues found" -Class Note
        }
    }

    end {
        Write-Verbose "[Get-SecurityCheck] Check completed"
    }
}
```

---

## <a id="security-considerations"></a>Соображения безопасности

### <a id="opsec-mode"></a>Режим OPSEC

При указании `-OPSEC`:
- Пропускается Kerberoasting (нет запросов TGS).
- Пропускается AS-REP Roasting (нет AS-REQ без предварительной аутентификации).
- Пропускается сбор BloodHound (создаёт много LDAP-запросов).
- Нет SMB-соединений с файловыми серверами из путей сценариев GPO или NETLOGON для сценариев входа учётных записей (не проверяются NTFS-права сценария из NETLOGON/общего ресурса и файла, на который ссылается scriptPath).
- Выполняется только пассивное перечисление.

### <a id="credential-handling"></a>Обращение с учётными данными

- Учётные данные хранятся только в `$Script:LDAPCredential`.
- Очищаются при Disconnect-adPEAS.
- Никогда не записываются на диск.
- Никогда не выводятся в подробный журнал.

### <a id="sid-based-checks"></a>Проверки по SID

Проверка субъектов использует SID, а не имена:
- Не зависит от языка ОС.
- Надёжна (имена могут совпадать).
- Быстрее (для известных SID не требуется разрешать имя).

---

## <a id="performance-optimizations"></a>Оптимизация производительности

### <a id="caching"></a>Кеширование

| Кеш | Назначение |
| ---------------- | ------------------------------- |
| Разрешение SID | Без повторных LDAP-поисков |
| Схема LAPS | Одна проверка схемы на сеанс |
| Членство в группах | Рекурсивное раскрытие участников |

### <a id="ldap-query-optimization"></a>Оптимизация LDAP-запросов

- Фильтрация на сервере (LDAP-фильтры, а не клиентский Where-Object).
- Страничная выдача больших наборов через `PageResultRequestControl`.
- Выбор атрибутов для адресных запросов (только внутреннее использование).
- Единый `LdapConnection` для LDAP и LDAPS.
- Настраиваемые тайм-ауты (Operation и Send).
- Доступ ко всем разделам (Domain, Configuration, Schema) через `-SearchBase`.

---

## <a id="error-handling"></a>Обработка ошибок

### <a id="two-level-approach"></a>Два уровня

**Критические ошибки** (скрипт останавливается):
- Сбой LDAP-соединения.
- Ошибка аутентификации.
- Недоступность всех контроллеров домена.

**Некритические ошибки** (продолжить работу):
- Ошибка чтения одного объекта.
- Отказ в правах на конкретный объект.
- Тайм-аут одного запроса.

### <a id="error-display"></a>Отображение ошибок

```powershell
try {
    # Операция
} catch {
    Write-Log "[FunctionName] Error: $_" -Level Error
}
```

---

## <a id="navigation"></a>Навигация

- [Назад: вспомогательные функции](08-Helper-Functions.md)
- [Далее: оценка рисков](10-Risk-Scoring-System.md)
- [На главную](00-Home.md)