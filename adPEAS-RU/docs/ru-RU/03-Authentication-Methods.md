# Методы аутентификации adPEAS v2

В adPEAS доступны способы подключения от текущей записи Windows
до Kerberos по сертификату или заранее подготовленному билету.
Для обычного внутреннего аудита выбирайте
`-UseWindowsAuth` либо `-Credential`,
`-UseLDAPS` и **`-IgnoreSSLErrors:$false`**.

## Обзор способов

| Способ | Параметры `Connect-adPEAS` | Kerberos / альтернативный механизм |
|---|---|---|
| Интегрированная Windows-аутентификация | `-UseWindowsAuth` | SSPI, выбор обрабатывается Windows |
| PowerShell PSCredential | `-Credential` | Сначала Kerberos, затем NTLM и SimpleBind при разрешённом fallback |
| Имя и пароль | `-Username` / `-Password` | Kerberos → NTLM → SimpleBind |
| Только NTLM | `-ForceNTLM` | NTLM, без Kerberos |
| NT-хеш (Overpass-the-Hash) | `-Username` / `-NTHash` | Kerberos, без fallback |
| AES256 (Pass-the-Key) | `-Username` / `-AES256Key` | Kerberos, без fallback |
| AES128 (Pass-the-Key) | `-Username` / `-AES128Key` | Kerberos, без fallback |
| Сертификат PKINIT | `-Certificate` | Kerberos PKINIT |
| Сертификат Schannel | `-Certificate` / `-ForcePassTheCert` | Прямой TLS/LDAPS, без Kerberos |
| Билет Kirbi | `-Kirbi` | Импорт билета Kerberos |
| Кэш Ccache | `-Ccache` | Импорт билета Kerberos |

При импорте билетов (PTT) используется
`LsaConnectUntrusted`; по описанию исходного
проекта это не требует прав администратора.
На практике совместимость зависит от окружения
и политики защиты Windows.

---

## Архитектура Kerberos-first

Для парольной аутентификации используется следующая схема:

1. Выполнение `AS-REQ/AS-REP` для получения TGT.
2. При необходимости перебор доступных EType:
   AES256 (18) → AES128 (17) → RC4 (23), если KDC
   возвращает `KDC_ERR_ETYPE_NOSUPP` (14).
3. Запрос билетов сервисов LDAP и CIFS (`TGS-REQ/TGS-REP`).
4. Импорт билетов в сеанс Windows (PTT).
5. LDAP/CIFS с Kerberos; при ошибке — предусмотренный
   fallback, если он не запрещён.

Для заранее заданных NT-хешей и AES-ключей
тип шифрования фиксирован — автоматически
заменять один ключ другим нельзя.

### Определение salt через PA-ETYPE-INFO2

Для AES-ключей, производных от пароля,
используется salt, зависящий от `REALM` и
написания имени пользователя. Часть имени
чувствительна к регистру. Чтобы избежать
несовпадения, adPEAS запрашивает у KDC
`PA-ETYPE-INFO2` при ответе
`KDC_ERR_PREAUTH_REQUIRED` (25), затем
использует salt, предоставленный KDC.
Для RC4 на базе NT-хеша salt не нужен.

### Приоритет альтернативных способов

При поддерживаемом парольном подключении
после неуспешного Kerberos возможны
**NTLM impersonation**, затем **LDAP SimpleBind**.
NTLM поддерживает LDAP Signing, в отличие от
простого неподписанного bind. При `Require signing`
простой LDAP-bind без необходимых защит
может не пройти.

Флаги управления:

| Флаг | Результат |
|---|---|
| `-ForceSimpleBind` | Пропустить Kerberos и NTLM |
| `-ForceNTLM` | NTLM в режиме `runas /netonly`; только пароль/PSCredential |
| `-ForceKerberos` | Запретить fallback |
| `-ForcePassTheCert` | Schannel вместо PKINIT |

Используйте принудительный режим только после
проверки совместимости и требований безопасности.

---

## Интегрированная Windows-аутентификация

~~~powershell
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false
~~~

Использует SSPI и текущую запись/билеты Windows.
Подходит для доменной рабочей станции либо сеанса
с корректными доменными билетами.

## PSCredential

~~~powershell
$cred = Get-Credential
Connect-adPEAS -Domain 'example.local' -Credential $cred `
    -UseLDAPS -IgnoreSSLErrors:$false
~~~

Преимущество — не оставлять пароль открытым текстом
в истории PowerShell.

## Имя пользователя и пароль

~~~powershell
$secure = Read-Host 'Пароль' -AsSecureString
Connect-adPEAS -Domain 'example.local' -Username 'auditor' `
    -Password $secure -UseLDAPS -IgnoreSSLErrors:$false
~~~

Поддерживаются `username`, `DOMAIN\username`
и `username@domain.com`. В оригинале
`-Password` также допускает обычную строку,
но для реального аудита это нежелательно.

## NTLM impersonation

`-ForceNTLM` применяет Windows `LogonUser`
с `LOGON32_LOGON_NEW_CREDENTIALS`, аналогично
`runas /netonly`, не заменяя текущие билеты Kerberos.
LDAP/SMB используют сетевую аутентификацию NTLM
и сохраняют возможность LDAP Signing.
Учитывайте, что NTLM может быть запрещён
политиками домена.

~~~powershell
$cred = Get-Credential
Connect-adPEAS -Domain 'example.local' -Credential $cred `
    -ForceNTLM
~~~

---

## Аутентификация с NT-хешем и AES-ключами

Эти режимы предназначены для **отдельно
разрешённых специализированных испытаний**,
когда у проверяющего уже есть законно
полученный аутентификационный материал.
Обычная инвентаризация AD их не требует.

- `-NTHash`: NT-хеш, 32 шестнадцатеричных символа;
  используется RC4-HMAC (etype 23) при Kerberos.
- `-AES256Key`: 64 hex (32 байта),
  AES256-CTS-HMAC-SHA1-96 (etype 18).
- `-AES128Key`: 32 hex (16 байт),
  AES128-CTS-HMAC-SHA1-96 (etype 17).

Для вывода AES-ключей из пароля используются
PBKDF2-HMAC-SHA1 (4096 итераций), DK и salt,
зависящий от REALM и учётной записи.
При уже готовом AES-ключе salt включён
в результат вычисления.
Все эти наборы требуют Kerberos и не
поддерживают стандартный парольный fallback.

Не помещайте реальные хеши, ключи и билеты в
репозитории, протоколы тестирования, историю
терминала либо примеры отчётов.

---

## Сертификаты: PKINIT

Для PKINIT нужен сертификат X.509 в
PKCS#12 (`.pfx` / `.p12`) **с закрытым ключом**,
соответствующий требованиям сопоставления
учётной записи и допустимого EKU.

~~~powershell
Connect-adPEAS -Domain 'example.local' -Certificate 'C:\Certs\audit.pfx' `
    -CertificatePassword (Read-Host 'Пароль PFX' -AsSecureString) `
    -UseLDAPS -IgnoreSSLErrors:$false
~~~

Вместо пути функция может принимать Base64-кодированный
PFX. При отсутствии пароля `-CertificatePassword`
можно не указывать. PKINIT использует Kerberos
на порту 88; простой bind не заменяет PKINIT.

### Дополнительные сведения: PAC и UnPAC-the-Hash

Исходный проект описывает возможность после PKINIT
получить дополнительные учётные сведения из PAC:
через запрос User-to-User (`U2U`),
`PAC_CREDENTIAL_INFO`, ключ ответа AS-REP и
`NTLM_SUPPLEMENTAL_CREDENTIAL`.
Этот механизм относится к **специализированной
проверке**. Он доступен не для каждого билета
и не применяется к обычному входу по паролю
или готовому ключу.

### Источники сертификатов и Shadow Credentials

Сертификаты могут выдаваться AD CS в рамках
разрешённого шаблона. Отдельно исходный проект
содержит операции изменения
`msDS-KeyCredentialLink` (Shadow Credentials),
которые **меняют объект AD** и могут создавать
путь к аутентификации другого субъекта.
Не выполняйте `Set-DomainUser -AddShadowCredential`
или очистку ключей на продуктивных учётных
записях без явного разрешения и плана отката.

В оригинальном руководстве для Shadow Credentials
заявлено требование DFL 2016+.
Для контроля изменений следует отслеживать
событие **5136** (изменение атрибута).
Сертификаты AD CS дополнительно отслеживаются
в журналах УЦ, например события 4886/4887.

---

## Pass-the-Cert через Schannel

`-ForcePassTheCert` использует сертификат клиента
в TLS handshake с LDAPS (обычно 636) без
Kerberos, TGT/TGS и PTT.

~~~powershell
Connect-adPEAS -Domain 'example.local' -Certificate 'C:\Certs\audit.pfx' `
    -CertificatePassword (Read-Host 'Пароль PFX' -AsSecureString) `
    -ForcePassTheCert -IgnoreSSLErrors:$false
~~~

Это отдельный механизм сопоставления
сертификатов Schannel. Сертификаты Shadow
Credentials, привязанные через
`msDS-KeyCredentialLink`, не эквивалентны
сертификатам для Schannel.
TLS и корректное сопоставление сертификата
остаются обязательными.

---

## Готовые билеты Kirbi и Ccache

`-Kirbi` принимает путь к файлу `.kirbi`
либо Base64-билет Kerberos.
`-Ccache` принимает путь к файлу
MIT Kerberos `.ccache` либо Base64.
Источник билета должен быть законным,
билет — действительным и соответствующим
домену и запрошенному сервису.
Эти режимы не выполняют автоматический
парольный fallback.

---

## Дополнительные параметры соединения

~~~powershell
# Конкретный DC и DNS
Connect-adPEAS -Domain 'example.local' -Server 'dc01.example.local' `
    -UseWindowsAuth -UseLDAPS -IgnoreSSLErrors:$false `
    -DnsServer '192.0.2.53' -TimeoutSeconds 60

# Проверка обязательного Kerberos, без альтернативных механизмов
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -ForceKerberos -UseLDAPS -IgnoreSSLErrors:$false
~~~

- `-TimeoutSeconds`: 5–600, по умолчанию 30.
- `-DnsServer`: пользовательский DNS для поиска DC.
- `-BuildCompletionCache`: дополнительные LDAP-запросы
  ради Tab-дополнения.
- `-PatchHostsFile`: изменение системного `hosts`,
  нужны повышенные права; выполняется только при
  отдельном разрешении.
- `-IgnoreSSLErrors`: в оригинальной функции
  **включён по умолчанию**; для защищённого аудита
  явный `-IgnoreSSLErrors:$false`.
- `-Quiet`: уменьшение объёма сообщений.

## Работа с сессией

~~~powershell
Get-adPEASSession
Get-adPEASSession -TestConnection
Disconnect-adPEAS
~~~

В информации о сессии отображаются домен,
DC, метод аутентификации, LDAP/LDAPS и
учётная запись; при отдельных успешных
операциях PKINIT возможны дополнительные
данные о полученном NT-хеше.
Храните такие сведения как конфиденциальные.

## Расширенные сценарии аутентификации (DOC5)

### NTLM impersonation и альтернативы Kerberos

При парольной аутентификации Kerberos запрашивает TGT, затем билеты сервисов LDAP/CIFS. Если KDC отвечает KDC_ERR_ETYPE_NOSUPP (14), adPEAS перебирает AES256 (etype 18), AES128 (17) и RC4-HMAC (23). При KDC_ERR_PREAUTH_REQUIRED (25) поле PA-ETYPE-INFO2 сообщает корректный salt для AES, зависящий от realm и регистра имени. Для готового NT-хеша salt не требуется. После неуспешного Kerberos для парольных режимов предусмотрены NTLM impersonation и SimpleBind. Готовые хеши и AES-ключи не поддерживают такой fallback.

ForceNTLM использует LogonUser и LOGON32_LOGON_NEW_CREDENTIALS (аналог runas /netonly), позволяя избежать целенаправленной замены существующих Kerberos-билетов текущей записи. NTLM совместим с LDAP Signing, если доменная политика его разрешает.

~~~powershell
$cred = Get-Credential
Connect-adPEAS -Domain 'example.local' -Credential $cred -ForceNTLM -UseLDAPS -IgnoreSSLErrors:$false
Get-adPEASSession
Disconnect-adPEAS
~~~

### NT-хеш и ключи AES128/AES256

| Параметр | Формат | Метод |
|---|---|---|
| -NTHash | 32 шестнадцатеричных символа | Kerberos RC4-HMAC |
| -AES128Key | 32 шестнадцатеричных символа | Kerberos AES128 |
| -AES256Key | 64 шестнадцатеричных символа | Kerberos AES256 |

~~~powershell
# Примеры формы, не действительные секреты.
Connect-adPEAS -Domain 'example.local' -Username 'auditor' -NTHash '<32_hex_chars>'
Connect-adPEAS -Domain 'example.local' -Username 'auditor' -AES128Key '<32_hex_chars>'
Connect-adPEAS -Domain 'example.local' -Username 'auditor' -AES256Key '<64_hex_chars>'
~~~

При использовании этих параметров Kerberos обязателен. Настоящие хеши, AES-ключи и билеты нельзя хранить в общих отчётах, GitHub и истории консоли.

### PKINIT: защищённый PFX и Base64

Параметр Certificate принимает путь к PFX или Base64. CertificatePassword нужен, если контейнер зашифрован. PKINIT требует Kerberos на TCP/88 и корректного сопоставления сертификата с записью AD.

~~~powershell
Connect-adPEAS -Domain 'example.local' -Certificate 'C:\Certs\auditor.pfx' -CertificatePassword (Read-Host 'Пароль PFX' -AsSecureString) -UseLDAPS -IgnoreSSLErrors:$false
$pfxBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Certs\auditor.pfx'))
Connect-adPEAS -Domain 'example.local' -Certificate $pfxBase64 -CertificatePassword (Read-Host 'Пароль PFX' -AsSecureString) -UseLDAPS -IgnoreSSLErrors:$false
~~~

UnPAC-the-Hash при определённых конфигурациях может извлекать NT-хеш из PAC_CREDENTIAL_INFO после PKINIT через U2U; это не универсальная возможность. Изменение msDS-KeyCredentialLink (Shadow Credentials), также упоминаемое в оригинале, является **записью в AD**, а не обычной проверкой соединения: требуется отдельное разрешение и план восстановления.

### Pass-the-Cert, Kirbi и Ccache

ForcePassTheCert использует клиентский TLS-сертификат через LDAPS, а не Kerberos TGT/TGS. Сертификат Shadow Credentials не следует считать подходящим для Schannel без проверки сопоставления субъекта.

~~~powershell
Connect-adPEAS -Domain 'example.local' -Server 'dc01.example.local' -Certificate 'C:\Certs\auditor.pfx' -CertificatePassword (Read-Host 'Пароль PFX' -AsSecureString) -ForcePassTheCert -IgnoreSSLErrors:$false
Connect-adPEAS -Domain 'example.local' -Kirbi 'C:\Tickets\auditor.kirbi'
Connect-adPEAS -Domain 'example.local' -Ccache 'C:\Tickets\auditor.ccache'
~~~

Kirbi и Ccache принимают также Base64-билеты. Используйте только законно полученные, действительные билеты с правильным realm. Импорт билета не выполняет парольный fallback.

### Выбор режима при ограничениях сети

| Сценарий | Режим | Условие |
|---|---|---|
| Доменная Windows-сессия | UseWindowsAuth | SSPI и текущие права |
| Отдельная аудиторская запись | Credential | Не хранить пароль открытым текстом |
| Kerberos обязателен | ForceKerberos | Нет перехода на NTLM/SimpleBind |
| Сохранить существующие билеты | ForceNTLM | NTLM разрешён политикой |
| Порт 88 закрыт, есть подходящий сертификат | ForcePassTheCert | LDAPS/Schannel |
| Порт 88 закрыт, разрешён парольный bind | ForceSimpleBind | LDAPS и проверенный сертификат |
| Готовый билет | Kirbi или Ccache | Проверить срок и realm |

~~~powershell
$cred = Get-Credential
Connect-adPEAS -Domain 'example.local' -Credential $cred -ForceKerberos -UseLDAPS -IgnoreSSLErrors:$false
Get-adPEASSession -TestConnection
Disconnect-adPEAS
~~~

## Навигация

[Быстрый запуск](02-Quick-Start.md) ·
[Проверки безопасности](04-Security-Checks.md) ·
[Справочник ключей](../../README_RU.md) ·
[Главная](00-Home.md)
