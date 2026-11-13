# Диагностика неполадок

Типовые проблемы и решения для adPEAS v2.

---

## Проблемы подключения

### Ошибка: «Не удаётся подключиться к контроллеру домена»

**Признаки**:
- Тайм-аут подключения.
- «Сервер не работает».
- «Сервер RPC недоступен».

**Причины и решения**:

1. **Сетевая доступность**
   ```powershell
    # Проверить доступность соединения
   Test-NetConnection -ComputerName dc01.contoso.com -Port 389
   Test-NetConnection -ComputerName dc01.contoso.com -Port 636
   ```

2. **Разрешение DNS**
   ```powershell
    # Проверить DNS
   Resolve-DnsName contoso.com
   Resolve-DnsName dc01.contoso.com

    # Использовать определённый DNS-сервер
   Connect-adPEAS -Domain "contoso.com" -DnsServer "10.0.0.1" -UseWindowsAuth
   ```

3. **Брандмауэр блокирует LDAP**
    - Проверьте доступность TCP 389 (LDAP) либо 636 (LDAPS).
    - Для Kerberos необходимо открыть TCP 88.
    - При необходимости TCP 3268 (GC) или 3269 (GC по SSL) для SID других доменов.

4. **Указать DC явно**
   ```powershell
   Connect-adPEAS -Domain "contoso.com" -Server "dc01.contoso.com" -UseWindowsAuth
   ```

---

### Ошибка: «Неверное имя пользователя или пароль»

**Признаки**:
- Сбой аутентификации.
- «Ошибка входа: неверное имя пользователя или пароль».

**Решения**:

1. **Проверить учётные данные**
   ```powershell
    # Проверить учётные данные интерактивно
   $cred = Get-Credential
   Connect-adPEAS -Domain "contoso.com" -Credential $cred
   ```

2. **Проверить формат имени пользователя**
   ```powershell
    # Проверить разные форматы
   Connect-adPEAS -Domain "contoso.com" -Username "CONTOSO\john.doe" -Password "pass"
   Connect-adPEAS -Domain "contoso.com" -Username "john.doe@contoso.com" -Password "pass"
   Connect-adPEAS -Domain "contoso.com" -Username "john.doe" -Password "pass"
   ```

3. **Запись заблокирована или отключена**
    - Проверьте, не заблокирована ли учётная запись.
    - Проверьте, не отключена ли она.

---

### Ошибка: «Не удалось пройти аутентификацию Kerberos»

**Признаки**:
- "KRB5KDC_ERR_PREAUTH_FAILED"
- "KRB5KDC_ERR_C_PRINCIPAL_UNKNOWN"
- Тайм-аут порта Kerberos 88.

**Решения**:

1. **Порт 88 заблокирован — используйте SimpleBind либо NTLM**
   ```powershell
    # Пропустить Kerberos, привязаться к LDAP напрямую
   Connect-adPEAS -Domain "contoso.com" -Username "john.doe" -Password "pass" -ForceSimpleBind

    # Либо использовать имперсонацию NTLM (существующие билеты Kerberos сохраняются)
   Connect-adPEAS -Domain "contoso.com" -Username "john.doe" -Password "pass" -ForceNTLM
   ```

2. **DNS не разрешает имя DC**
   ```powershell
    # Использовать определённый DNS-сервер
   Connect-adPEAS -Domain "contoso.com" -DnsServer "10.0.0.1" -Username "john.doe" -Password "pass"
   ```

3. **Неправильная синхронизация времени**
    - Kerberos требует расхождения часов с DC не более пяти минут.
    - Проверьте системное время.

4. **Субъект не найден**
    - Убедитесь, что имя пользователя существует в домене.
    - Проверьте опечатки в имени домена.

---

## Промежуточные узлы и туннели

### Работа adPEAS через сетевой туннель

В adPEAS нет встроенного SOCKS-прокси или клиента туннелирования. Класс .NET `LdapConnection` не поддерживает прокси-соединения, а реализация полного протокола SOCKS неоправданно усложнила бы проект при наличии готовых специализированных инструментов.

Вместо этого используйте **локальную переадресацию портов** подходящим средством. adPEAS соединяется с адресом, указанным в `-Server`, включая `localhost` или локальный IP туннеля.

---

### Рекомендуемая конфигурация

**Схема:**

```
┌──────────┐    Tunnel     ┌─────────────┐    Internal    ┌──────────┐
│ Attacker │ ◄════════════►│ Pivot Host  │ ──────────────►│   DC     │
│ Machine  │  (chisel,     │ (internal)  │   Port 389/636 │ Port 389 │
│          │   ligolo,     │             │   Port 88      │ Port 88  │
│          │   socat)      │             │                │          │
└──────────┘               └─────────────┘                └──────────┘
     │
     │ adPEAS connects to localhost / tunnel IP
     ▼
  Connect-adPEAS -Server "127.0.0.1" ...
```

**Шаг 1: создать туннель** (примеры для распространённых инструментов)

```bash
# Chisel (обратный туннель)
# На промежуточном узле:
chisel server -p 8080 --reverse
# На проверяющем компьютере:
chisel client pivot-host:8080 R:389:dc01.contoso.com:389 R:88:dc01.contoso.com:88

# Ligolo-ng
# Ligolo создаёт полноценный туннельный интерфейс — не нужны отдельные пробросы портов
# Все порты доступны через IP туннельного интерфейса

# Проброс SSH
ssh -L 389:dc01.contoso.com:389 -L 88:dc01.contoso.com:88 user@pivot-host

# Socat (простой TCP-ретранслятор на промежуточном узле)
socat TCP-LISTEN:389,fork TCP:dc01.contoso.com:389 &
socat TCP-LISTEN:88,fork TCP:dc01.contoso.com:88 &
```

**Шаг 2: подключить adPEAS через туннель**

```powershell
# SimpleBind через туннель (обычно надёжнее всего)
Connect-adPEAS -Domain "contoso.com" -Server "127.0.0.1" -Username "john.doe" -Password "P@ssw0rd" -ForceSimpleBind

# LDAPS (если туннель перенаправляет порт 636)
Connect-adPEAS -Domain "contoso.com" -Server "127.0.0.1" -Username "john.doe" -Password "P@ssw0rd" -UseLDAPS -IgnoreSSLErrors -ForceSimpleBind

# Сертификат через туннель (если сертификат есть — нужен только порт 636)
Connect-adPEAS -Domain "contoso.com" -Server "127.0.0.1" -Certificate "user.pfx" -ForcePassTheCert

# Интерфейс Ligolo-ng (полноценный сетевой туннель)
Connect-adPEAS -Domain "contoso.com" -Server "10.10.10.10" -DnsServer "10.10.10.10" -Username "john.doe" -Password "P@ssw0rd"
```

---

### Почему через туннель рекомендуется ForceSimpleBind?

**Аутентификация Kerberos через туннели проблематична** по нескольким причинам:

| Проблема | Объяснение |
|-------|-------------|
| **Несовпадение SPN** | Билет Kerberos связан с целевым именем узла (например, `ldap/dc01.contoso.com`). При подключении к `127.0.0.1` SPN не совпадает, и возникает `LDAP_LOCAL_ERROR` (код 82). |
| **Разрешение DNS** | Kerberos использует DNS для поиска KDC; через туннель DNS может работать некорректно. |
| **Требуется порт 88** | Для Kerberos нужно отдельное TCP-соединение к KDC: порт 88 также должен быть проброшен. |
| **Изоляция сеансов PTT** | Pass-the-Ticket внедряет билет в сеанс Windows LSA. При изменении сетевого пути билет может быть непригоден для LDAP-подключения. |

**Рекомендация:** используйте `-ForceSimpleBind` при пробросе отдельных портов. При полном сетевом туннеле (интерфейс Ligolo-ng) Kerberos может работать при правильном DNS.

---

### Необходимые порты

Убедитесь, что туннель перенаправляет нужные порты:

| Порт | Протокол | Назначение | Обязателен? |
|------|----------|-------------|------------|
| 389 | TCP | LDAP | Да (либо 636) |
| 636 | TCP | LDAPS | Альтернатива порту 389 |
| 88 | TCP | Kerberos | Только при Kerberos |
| 3268 | TCP | Глобальный каталог (LDAP) | Необязательно — SID других доменов/леса |
| 3269 | TCP | Глобальный каталог (LDAPS) | Необязательно — SID других доменов/леса (SSL) |
| 445 | TCP | SMB/CIFS | Только для SMB-проверок (`Get-SMBSigningStatus`) |
| 53 | UDP | DNS | Необязательно — имена, не найденные `Get-NetworkMap` в зонах AD (нет при `-OPSEC`) |

**Минимум для перечисления:** TCP 389 (LDAP) и учётные данные SimpleBind.

---

### Диагностика туннельных соединений

**Признак: `LDAP_LOCAL_ERROR` (код 82) после TGT+TGS Kerberos**

Билет Kerberos получен успешно, но локально завершилось ошибкой LDAP-подключение Negotiate. Обычно SPN сервисного билета не совпадает с целью соединения.

```powershell
# Исправление: пропустить Kerberos и использовать SimpleBind
Connect-adPEAS -Domain "contoso.com" -Server "127.0.0.1" -Username "john.doe" -Password "P@ssw0rd" -ForceSimpleBind
```

**Признак: тайм-аут соединения**

Туннель не перенаправляет нужный порт.

```powershell
# Проверить, работает ли туннель
Test-NetConnection -ComputerName 127.0.0.1 -Port 389
```

**Признак: «сервер недоступен» или нет результатов**

DNS-имя домена может не разрешаться через туннель.

```powershell
# Указать IP DC напрямую и параметр DnsServer
Connect-adPEAS -Domain "contoso.com" -Server "127.0.0.1" -DnsServer "127.0.0.1" -Username "john.doe" -Password "P@ssw0rd" -ForceSimpleBind
```

**Признак: ошибка проверки сертификата LDAPS**

Сертификат выдан на DNS-имя контроллера домена, а не на `127.0.0.1` или `localhost`.

```powershell
# Игнорировать несовпадение имени сертификата
Connect-adPEAS -Domain "contoso.com" -Server "127.0.0.1" -UseLDAPS -IgnoreSSLErrors -Username "john.doe" -Password "P@ssw0rd" -ForceSimpleBind
```

### Медленные соединения и тайм-ауты

**Признак: `The operation was aborted because the client side timeout limit was exceeded`**

При высоких задержках (SOCKS, VPN, несколько промежуточных узлов) LDAP-запрос может превысить стандартные 30 секунд, особенно при сложном анализе ACL.

**Решение: увеличить тайм-аут**

```powershell
# Увеличить до 120 секунд (рекомендуется для туннеля)
Invoke-adPEAS -Domain "contoso.com" -Server "127.0.0.1" -Username "john.doe" -Password "P@ssw0rd" -ForceSimpleBind -TimeoutSeconds 120

# Или вызвать Connect-adPEAS напрямую
Connect-adPEAS -Domain "contoso.com" -Server "127.0.0.1" -Username "john.doe" -Password "P@ssw0rd" -ForceSimpleBind -TimeoutSeconds 120

# Максимум: 600 секунд (10 минут) для крайне медленного канала
Connect-adPEAS -Domain "contoso.com" -TimeoutSeconds 600 -Username "john.doe" -Password "P@ssw0rd" -ForceSimpleBind
```

**Дополнительные советы для медленного подключения:**
- Запускайте только необходимые модули: `-Module Domain,Accounts` (без тяжёлого анализа ACL).
- Используйте `-OPSEC` (меньше запросов).
- Проверки Rights (ACL) чаще превышают тайм-аут; можно ограничиться `-Module Domain,Accounts,Creds`.

---

## Проблемы способов аутентификации

### Аутентификация по NT-хешу не работает

**Признаки**:
- «Сбой Overpass-the-Hash».
- Полный отказ аутентификации (для входа по хешу резервного способа нет).

**Решения**:

1. **Проверить формат хеша**
   ```powershell
    # Должно быть 32 шестнадцатеричных символа
   $hash = "32ED87BDB5FDC5E9CBA88547376818D4"
   if ($hash.Length -ne 32) { Write-Error "Invalid hash length" }
   ```

2. **RC4 отключён в домене**
    - При отключённом RC4 аутентификация по NT-хешу не работает.
    - Вместо него используйте ключ AES256.
   ```powershell
   Connect-adPEAS -Domain "contoso.com" -Username "john.doe" -AES256Key "..."
   ```

3. **PTT блокируется политикой безопасности**
    - adPEAS использует `LsaConnectUntrusted`, права администратора НЕ требуются.
    - В редких случаях строгая политика блокирует доступ к LSA.
    - NT-хеш/AES не имеют резервного метода — Kerberos (88) должен быть доступен.
    - Для пароля возможен обход через `-ForceSimpleBind`.

---

### Аутентификация сертификатом (PKINIT) не работает

**Признаки**:
- «Сбой аутентификации PKINIT».
- «Сертификат непригоден для входа».

**Решения**:

1. **Проверить требования к сертификату**
    - Должен содержать закрытый ключ.
    - Нужен EKU Smart Card Logon либо Client Auth.
    - В SAN должен быть UPN или другой идентификатор.

2. **Проверить пароль сертификата**
   ```powershell
    # Убедиться, что PFX читается
   $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new("user.pfx", "password")
   $cert.Subject
   ```

3. **Истёк или отозван сертификат**
    - Проверьте даты действия сертификата.
    - Проверьте, не отозвал ли его УЦ.

---

### Не импортируется Kirbi/Ccache

**Признаки**:
- «Не удалось импортировать билет».
- «Доступ запрещён».

**Решения**:

1. **Ограничивающая политика LSA**
    - adPEAS использует `LsaConnectUntrusted` без административных прав.
    - Изредка политика безопасности блокирует доступ к LSA.
    - Попробуйте другой сеанс или компьютер.

2. **Билет просрочен**
    - Проверьте время окончания действия.
    - Запросите новый билет.

3. **Неправильный тип билета**
    - Убедитесь, что это TGT (служба krbtgt).
    - Либо сервисный билет для LDAP.

---

## Query Issues

### Error: "Access denied" on specific objects

**Symptoms**:
- Some objects return, others don't
- "Insufficient access rights"

**Cause**: The authenticated account lacks read permissions.

**Solutions**:

1. **Use account with more privileges**
   ```powershell
   Connect-adPEAS -Domain "contoso.com" -Credential (Get-Credential)
   # Enter an account with more access
   ```

2. **This is expected behavior**
   - Some objects are protected (e.g., AdminSDHolder)
   - Document what couldn't be read

---

### Error: "The search filter is invalid"

**Symptoms**:
- LDAP filter syntax error
- Empty results unexpectedly

**Solutions**:

1. **Check filter syntax**
   ```powershell
   # Correct: parentheses balanced
   Get-DomainUser -LDAPFilter "(sAMAccountName=admin)"

   # Wrong: missing parenthesis
   Get-DomainUser -LDAPFilter "(sAMAccountName=admin"
   ```

2. **Escape special characters**
   ```powershell
   # Characters to escape: * ( ) \ NUL
   # Use \2a for *, \28 for (, \29 for ), \5c for \
   Get-DomainUser -LDAPFilter "(description=*\2a*)"
   ```

---

### No Results Returned

**Symptoms**:
- Query returns $null or empty array
- Expected objects not found

**Solutions**:

1. **Verify object exists**
   ```powershell
   Get-DomainUser -Identity "username"
   ```

2. **Check search base**
   ```powershell
   # Might be searching wrong OU
   Get-DomainUser -SearchBase "DC=contoso,DC=com"
   ```

3. **Verify connection**
   ```powershell
   Get-adPEASSession -TestConnection
   ```

---

## Performance Issues

### Queries Taking Too Long

**Symptoms**:
- Timeouts
- Slow response

**Solutions**:

1. **Target specific DC**
   ```powershell
   Connect-adPEAS -Domain "contoso.com" -Server "dc01.contoso.com" -UseWindowsAuth
   ```

2. **Limit result set**
   ```powershell
   # Add more specific filter
   Get-DomainUser -LDAPFilter "(&(objectCategory=person)(adminCount=1))"
   ```

3. **Check network latency**
   ```powershell
   Test-Connection dc01.contoso.com
   ```

---

## Output Issues

### Colors Not Displaying

**Symptoms**:
- ANSI codes showing as text
- No color output

**Solutions**:

1. **Use Windows Terminal or ConEmu**
   - Legacy cmd.exe doesn't support ANSI
   - Windows Terminal has full support

2. **Enable VirtualTerminal**
   ```powershell
   # In Windows 10+
   Set-ItemProperty HKCU:\Console VirtualTerminalLevel -Type DWORD 1
   ```

3. **Output to file instead**
   ```powershell
   Invoke-adPEAS -Outputfile .\report
   ```

---

### File Output Not Created

**Symptoms**:
- No file created
- "Cannot write to file" error

**Solutions**:

1. **Check path exists**
   ```powershell
   # Use existing directory
   Invoke-adPEAS -Outputfile "C:\existing\path\report"
   ```

2. **Check write permissions**
   - Ensure you can write to the target directory
   - Try different location

3. **Close file if open**
   - If file is open in another program, writing fails

---

### Functions Not Available After Loading adPEAS

**Symptoms**:
- Logo displays correctly
- `Invoke-adPEAS` not recognized

**Cause**: Script was executed instead of dot-sourced

**Solution**:
- Use dot-sourcing to load adPEAS: `. .\adPEAS.ps1`
- Do NOT run `.\adPEAS.ps1` directly (functions stay in script scope)
- After dot-sourcing, `Invoke-adPEAS`, `Connect-adPEAS` and other functions are available

---

## Diagnostic Commands

### Check PowerShell Version

```powershell
$PSVersionTable.PSVersion
# Requires 5.1 or higher
```

### Check .NET Framework Version

```powershell
[System.Environment]::Version
# or
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" | Select-Object Version
```

### Test Network Connectivity

```powershell
# Test LDAP
Test-NetConnection -ComputerName dc01.contoso.com -Port 389

# Test LDAPS
Test-NetConnection -ComputerName dc01.contoso.com -Port 636

# Test Kerberos
Test-NetConnection -ComputerName dc01.contoso.com -Port 88
```

### Verify DNS Resolution

```powershell
Resolve-DnsName contoso.com
Resolve-DnsName _ldap._tcp.contoso.com -Type SRV
```

### Check Current Session

```powershell
Get-adPEASSession
Get-adPEASSession -TestConnection
```

### Enable Verbose Output

```powershell
# Display verbose messages in console
$VerbosePreference = "Continue"
Connect-adPEAS -Domain "contoso.com" -UseWindowsAuth -Verbose
```

### Enable Verbose Logging to File

For detailed troubleshooting, write verbose messages to a file with timestamps:

```powershell
# Write verbose messages to output file (timestamped)
# -VerboseLogging automatically enables -Verbose for console output
Invoke-adPEAS -Domain "contoso.com" -UseWindowsAuth -Outputfile .\debug_report -VerboseLogging

# Output text file contains timestamped entries like:
# 2026-01-14 18:42:15 [Verbose] [Get-DomainUser] Querying users...
# 2026-01-14 18:42:16 [Verbose] [Invoke-LDAPSearch] Filter: (objectClass=user)
```

**Parameters:**
- `-Outputfile` - Required: Path to output file (text format needed for logging)
- `-VerboseLogging` - Writes verbose log messages to the output file AND automatically enables `-Verbose` for console output

**Note:** `-VerboseLogging` without `-Outputfile` will show a warning. Verbose messages will still appear in the console, but file logging is skipped.

---

## Getting Help

If you cannot resolve an issue:

1. **Enable verbose mode** and capture the output
2. **Check if the issue is reproducible** with minimal parameters
3. **Open an issue** on GitHub with:
   - PowerShell version
   - Windows version
   - Error message
   - Steps to reproduce

---

## Navigation

- [Previous: Risk-Scoring-System](10-Risk-Scoring-System.md)
- [Next: FAQ](12-FAQ.md)
- [Back to Home](00-Home.md)