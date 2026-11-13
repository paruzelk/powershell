# <a id="troubleshooting"></a>Диагностика неполадок

Типовые проблемы и решения для adPEAS v2.

---

## <a id="connection-issues"></a>Проблемы подключения

### <a id="error-cannot-connect-to-domain-controller"></a>Ошибка: «Не удаётся подключиться к контроллеру домена»

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

### <a id="error-the-user-name-or-password-is-incorrect"></a>Ошибка: «Неверное имя пользователя или пароль»

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

### <a id="error-kerberos-authentication-failed"></a>Ошибка: «Не удалось пройти аутентификацию Kerberos»

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

## <a id="pivoting-and-tunneling"></a>Промежуточные узлы и туннели

### <a id="using-adpeas-through-a-network-tunnel"></a>Работа adPEAS через сетевой туннель

В adPEAS нет встроенного SOCKS-прокси или клиента туннелирования. Класс .NET `LdapConnection` не поддерживает прокси-соединения, а реализация полного протокола SOCKS неоправданно усложнила бы проект при наличии готовых специализированных инструментов.

Вместо этого используйте **локальную переадресацию портов** подходящим средством. adPEAS соединяется с адресом, указанным в `-Server`, включая `localhost` или локальный IP туннеля.

---

### <a id="recommended-setup"></a>Рекомендуемая конфигурация

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

# Ligolo-ng — сетевой туннель
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

### <a id="why-use-forcesimplebind-over-a-tunnel"></a>Почему через туннель рекомендуется ForceSimpleBind?

**Аутентификация Kerberos через туннели проблематична** по нескольким причинам:

| Проблема | Объяснение |
|-------|-------------|
| **Несовпадение SPN** | Билет Kerberos связан с целевым именем узла (например, `ldap/dc01.contoso.com`). При подключении к `127.0.0.1` SPN не совпадает, и возникает `LDAP_LOCAL_ERROR` (код 82). |
| **Разрешение DNS** | Kerberos использует DNS для поиска KDC; через туннель DNS может работать некорректно. |
| **Требуется порт 88** | Для Kerberos нужно отдельное TCP-соединение к KDC: порт 88 также должен быть проброшен. |
| **Изоляция сеансов PTT** | Pass-the-Ticket внедряет билет в сеанс Windows LSA. При изменении сетевого пути билет может быть непригоден для LDAP-подключения. |

**Рекомендация:** используйте `-ForceSimpleBind` при пробросе отдельных портов. При полном сетевом туннеле (интерфейс Ligolo-ng) Kerberos может работать при правильном DNS.

---

### <a id="required-ports"></a>Необходимые порты

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

### <a id="troubleshooting-tunnel-connections"></a>Диагностика туннельных соединений

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

### <a id="slow-connections-timeouts"></a>Медленные соединения и тайм-ауты

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

## <a id="authentication-method-issues"></a>Проблемы способов аутентификации

### <a id="nt-hash-authentication-not-working"></a>Аутентификация по NT-хешу не работает

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

### <a id="certificate-pkinit-authentication-not-working"></a>Аутентификация сертификатом (PKINIT) не работает

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

### <a id="kirbiccache-import-not-working"></a>Не импортируется Kirbi/Ccache

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

## <a id="query-issues"></a>Проблемы запросов

### <a id="error-access-denied-on-specific-objects"></a>Ошибка «Доступ запрещён» для отдельных объектов

**Признаки**:
- Одни объекты возвращаются, другие нет.
- «Недостаточно прав доступа».

**Причина**: используемая учётная запись не имеет прав чтения.

**Решения**:

1. **Использовать запись с большими правами**
   ```powershell
   Connect-adPEAS -Domain "contoso.com" -Credential (Get-Credential)
    # Указать запись с дополнительными правами
   ```

2. **Иногда это штатное поведение**
    - Некоторые объекты защищены, например AdminSDHolder.
    - Документируйте, что прочитать не удалось.

---

### <a id="error-the-search-filter-is-invalid"></a>Ошибка «Неверный поисковый фильтр»

**Признаки**:
- Ошибка синтаксиса LDAP-фильтра.
- Неожиданно пустой результат.

**Решения**:

1. **Проверить синтаксис фильтра**
   ```powershell
    # Правильно: все скобки закрыты
   Get-DomainUser -LDAPFilter "(sAMAccountName=admin)"

    # Неправильно: пропущена закрывающая скобка
   Get-DomainUser -LDAPFilter "(sAMAccountName=admin"
   ```

2. **Экранировать специальные символы**
   ```powershell
    # Символы, требующие экранирования: * ( ) \ NUL
    # Для * используйте \2a, для ( — \28, для ) — \29, для \ — \5c
   Get-DomainUser -LDAPFilter "(description=*\2a*)"
   ```

---

### <a id="no-results-returned"></a>Результат пуст

**Признаки**:
- Запрос возвращает $null либо пустой массив.
- Ожидаемые объекты не найдены.

**Решения**:

1. **Проверить существование объекта**
   ```powershell
   Get-DomainUser -Identity "username"
   ```

2. **Проверить базу поиска**
   ```powershell
    # Возможно, поиск выполняется не в той OU
   Get-DomainUser -SearchBase "DC=contoso,DC=com"
   ```

3. **Проверить подключение**
   ```powershell
   Get-adPEASSession -TestConnection
   ```

---

## <a id="performance-issues"></a>Проблемы производительности

### <a id="queries-taking-too-long"></a>Запросы выполняются слишком долго

**Признаки**:
- Тайм-ауты.
- Медленный отклик.

**Решения**:

1. **Обратиться к конкретному DC**
   ```powershell
   Connect-adPEAS -Domain "contoso.com" -Server "dc01.contoso.com" -UseWindowsAuth
   ```

2. **Ограничить выборку**
   ```powershell
    # Указать более точный фильтр
   Get-DomainUser -LDAPFilter "(&(objectCategory=person)(adminCount=1))"
   ```

3. **Проверить сетевую задержку**
   ```powershell
   Test-Connection dc01.contoso.com
   ```

---

## <a id="output-issues"></a>Проблемы вывода

### <a id="colors-not-displaying"></a>Не отображаются цвета

**Признаки**:
- ANSI-коды выводятся как текст.
- Отсутствует цветной вывод.

**Решения**:

1. **Использовать Windows Terminal или ConEmu**
    - Устаревшая cmd.exe не поддерживает ANSI.
    - Windows Terminal имеет полноценную поддержку.

2. **Включить VirtualTerminal**
   ```powershell
    # На Windows 10 и новее
   Set-ItemProperty HKCU:\Console VirtualTerminalLevel -Type DWORD 1
   ```

3. **Сохранить отчёт в файл**
   ```powershell
   Invoke-adPEAS -Outputfile .\report
   ```

---

### <a id="file-output-not-created"></a>Файл отчёта не создан

**Признаки**:
- Файл не появился.
- Ошибка «Невозможно записать файл».

**Решения**:

1. **Проверить существование пути**
   ```powershell
    # Использовать существующий каталог
   Invoke-adPEAS -Outputfile "C:\existing\path\report"
   ```

2. **Проверить права записи**
    - Проверьте право записи в целевой каталог.
    - Попробуйте другой каталог.

3. **Закрыть открытый файл**
    - Если файл открыт другой программой, запись может не сработать.

---

### <a id="functions-not-available-after-loading-adpeas"></a>Функции недоступны после загрузки adPEAS

**Признаки**:
- Логотип отображается правильно.
- `Invoke-adPEAS` не распознаётся.

**Причина**: сценарий запущен напрямую, а не загружен через dot-sourcing.

**Решение**:
- Используйте dot-sourcing: `. .\adPEAS.ps1`.
- НЕ запускайте `.\adPEAS.ps1` напрямую (функции останутся в области сценария).
- После dot-sourcing доступны `Invoke-adPEAS`, `Connect-adPEAS` и остальные функции.

---

## <a id="diagnostic-commands"></a>Диагностические команды

### <a id="check-powershell-version"></a>Проверить версию PowerShell

```powershell
$PSVersionTable.PSVersion
# Требуется версия 5.1 или новее
```

### <a id="check-net-framework-version"></a>Проверить версию .NET Framework

```powershell
[System.Environment]::Version
# либо
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" | Select-Object Version
```

### <a id="test-network-connectivity"></a>Проверить сетевую доступность

```powershell
# Проверить LDAP
Test-NetConnection -ComputerName dc01.contoso.com -Port 389

# Проверить LDAPS
Test-NetConnection -ComputerName dc01.contoso.com -Port 636

# Проверить Kerberos
Test-NetConnection -ComputerName dc01.contoso.com -Port 88
```

### <a id="verify-dns-resolution"></a>Проверить разрешение DNS

```powershell
Resolve-DnsName contoso.com
Resolve-DnsName _ldap._tcp.contoso.com -Type SRV
```

### <a id="check-current-session"></a>Проверить текущий сеанс

```powershell
Get-adPEASSession
Get-adPEASSession -TestConnection
```

### <a id="enable-verbose-output"></a>Включить подробный вывод

```powershell
# Показывать подробные сообщения в консоли
$VerbosePreference = "Continue"
Connect-adPEAS -Domain "contoso.com" -UseWindowsAuth -Verbose
```

### <a id="enable-verbose-logging-to-file"></a>Записывать подробный журнал в файл

Для диагностики сохраняйте подробные сообщения с временными отметками в файл:

```powershell
# Записывать подробные сообщения в файл вывода (с временными метками)
# -VerboseLogging автоматически включает -Verbose для консоли
Invoke-adPEAS -Domain "contoso.com" -UseWindowsAuth -Outputfile .\debug_report -VerboseLogging

# Пример строк файла с временными метками:
# 2026-01-14 18:42:15 [Verbose] [Get-DomainUser] Querying users...
# 2026-01-14 18:42:16 [Verbose] [Invoke-LDAPSearch] Filter: (objectClass=user)
```

**Параметры:**
- `-Outputfile` — обязательно: путь к файлу результата (текстовый файл для журнала).
- `-VerboseLogging` — пишет подробный журнал в файл и автоматически включает `-Verbose` в консоли.

**Примечание:** `-VerboseLogging` без `-Outputfile` выводит предупреждение. Подробные сообщения остаются в консоли, но запись журнала в файл пропускается.

---

## <a id="getting-help"></a>Получение помощи

Если проблему не удалось решить:

1. **Включите подробный вывод** и сохраните результат.
2. **Проверьте воспроизводимость** с минимальными параметрами.
3. **Создайте issue** на GitHub, указав:
   - Версию PowerShell.
   - Версию Windows.
   - Текст ошибки.
   - Действия для воспроизведения.

---

## <a id="navigation"></a>Навигация

- [Назад: система оценки рисков](10-Risk-Scoring-System.md)
- [Далее: часто задаваемые вопросы](12-FAQ.md)
- [На главную](00-Home.md)