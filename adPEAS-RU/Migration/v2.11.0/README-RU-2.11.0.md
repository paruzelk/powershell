# adPEAS-RU 2.11.0 MIG4 — быстрый старт и все параметры

**MIG4 PREVIEW.** ZIP содержит четыре автономных PowerShell-скрипта и
adPEAS.exe; старая обёртка Run-AD-Audit-RU.ps1 в архив не входит.

## Быстрый запуск (Windows PowerShell 5.1)

~~~powershell
cd 'C:\Tools\adPEAS-RU'
Import-Module .\adPEAS.ps1 -Force
Invoke-adPEAS -Domain stios.local -UseWindowsAuth -OPSEC -Outputfile '.\AD-Audit-MIG4' -Format All
Disconnect-adPEAS
~~~

Создаются AD-Audit-MIG4.html, AD-Audit-MIG4.txt и AD-Audit-MIG4.json.
Outputfile принимает имя без расширения.

**LDAPS с проверкой сертификата:**

~~~powershell
Import-Module .\adPEAS.ps1 -Force
Connect-adPEAS -Domain stios.local -UseWindowsAuth -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEAS -OPSEC -Outputfile '.\AD-Audit-LDAPS' -Format All
Disconnect-adPEAS
~~~

В исходном Connect-adPEAS проверка TLS-сертификата **отключена по умолчанию**.
Используйте -IgnoreSSLErrors:$false для её включения.

**Выборочные разделы:**

~~~powershell
Invoke-adPEAS -Domain stios.local -UseWindowsAuth -Module Domain,Accounts,GPO,Rights -OPSEC -Outputfile '.\AD-Audit-Selected' -Format All
~~~

**Другая учётная запись:**

~~~powershell
Invoke-adPEAS -Domain stios.local -Credential (Get-Credential) -OPSEC -Outputfile '.\AD-Audit-Alternate' -Format All
~~~

## Параметры Invoke-adPEAS — оригинал 2.11.0

Общая форма (параметры аутентификации имеют взаимоисключающие наборы):

~~~text
Invoke-adPEAS [-Domain <String>] [-Server <String>] [-UseLDAPS]
  [-UseWindowsAuth | -Credential <PSCredential> | -Username <String> -Password <Object> | -Certificate <String> [-CertificatePassword <Object>]]
  [-Outputfile <String>] [-Module <String[]>] [-ExcludeModule <String[]>]
  [-OPSEC] [-NoColor] [-VerboseLogging] [-InactiveDays <Int32>]
  [-IncludePrivileged] [-TimeoutSeconds <Int32>] [-Format <Text|HTML|JSON|All>]
  [-OutputAppend] [-License <String>] [-Statistics]
~~~

| Ключ | Тип/умолчание | Назначение |
|---|---|---|
| -Domain | String | Имя домена AD для нового соединения |
| -Server | String | FQDN/IP контроллера домена |
| -UseLDAPS | Switch | LDAPS, порт 636 |
| -UseWindowsAuth | Switch | Аутентификация пользователя Windows |
| -Credential | PSCredential | Альтернативная учётная запись |
| -Username | String | Имя при аутентификации с паролем |
| -Password | String или SecureString | Пароль, вместе с Username |
| -Certificate | String | PFX/PKCS#12 либо Base64 |
| -CertificatePassword | String или SecureString | Пароль PFX, по умолчанию пустой |
| -Outputfile | String | Путь отчёта без расширения |
| -Module | String[] | Выбрать модули |
| -ExcludeModule | String[] | Исключить модули |
| -OPSEC | Switch, выключен | Пропустить активные/массовые проверки |
| -NoColor | Switch | Отключить ANSI |
| -VerboseLogging | Switch | Расширенный лог; для файла нужен Outputfile |
| -InactiveDays | Int32, 90 | Порог неактивности 1–3650 дней |
| -IncludePrivileged | Switch | Показывать ожидаемые привилегированные назначения |
| -TimeoutSeconds | Int32, 30 | Тайм-аут 5–600 секунд |
| -Format | Text/HTML/JSON/All | По умолчанию All |
| -OutputAppend | Switch | Дополнение отчёта с JSON; нужен Outputfile и JSON/All |
| -License | String | Путь к лицензии |
| -Statistics | Switch | LDAP-статистика |

Модули: Domain, Creds, Rights, Delegation, ADCS, Accounts, GPO,
Computer, Application, Shares, Bloodhound.

Shares по умолчанию не запускается: подключается по SMB к компьютерам
домена. OPSEC уменьшает активность, но **не обеспечивает полностью
пассивный** аудит.

## Параметры Connect-adPEAS — оригинал 2.11.0

~~~text
Connect-adPEAS -Domain <String> [-Server <String>] [-UseLDAPS]
  [-IgnoreSSLErrors[:$true|:$false]] [-DnsServer <String>] [-PatchHostsFile] [-Quiet]
  [-UseWindowsAuth | -Credential <PSCredential> | -Username <String> -Password <Object> |
    -Certificate <String> [-CertificatePassword <Object>] [-ForcePassTheCert] |
    -Username <String> -NTHash <String> | -Username <String> -AES256Key <String> |
    -Username <String> -AES128Key <String> | -Kirbi <String> | -Ccache <String>]
  [-ForceNTLM] [-ForceSimpleBind] [-ForceKerberos] [-BuildCompletionCache]
  [-License <String>] [-TimeoutSeconds <Int32>]
~~~

| Ключ | Назначение |
|---|---|
| -Domain | Явно указанный FQDN домена |
| -Server | Контроллер домена |
| -UseLDAPS | Использовать TLS |
| -IgnoreSSLErrors | По умолчанию TRUE; :$false включает проверку сертификата |
| -DnsServer | Пользовательский DNS |
| -PatchHostsFile | Изменение hosts, требует разрешений |
| -Quiet | Уменьшить вывод |
| -UseWindowsAuth | Вход текущего пользователя |
| -Credential | PSCredential |
| -Username | Пользователь для парольной/ключевой аутентификации |
| -Password | Пароль |
| -Certificate | Путь или Base64 PFX |
| -CertificatePassword | Пароль PFX |
| -ForcePassTheCert | Клиентский сертификат Schannel вместо PKINIT |
| -NTHash | NT-хеш (32 hex) |
| -AES256Key | AES-256 (64 hex) |
| -AES128Key | AES-128 (32 hex) |
| -Kirbi | Билет Kerberos: файл/Base64 |
| -Ccache | Кеш Kerberos: файл/Base64 |
| -ForceNTLM | Вход через NTLM |
| -ForceSimpleBind | Простой LDAP bind |
| -ForceKerberos | Только Kerberos |
| -BuildCompletionCache | Предварительный кеш имён |
| -License | Файл лицензии |
| -TimeoutSeconds | 5–600 секунд, по умолчанию 30 |

Не смешивайте разные наборы аутентификации.

## Помощь, конвертация и проверка соединения

~~~powershell
Import-Module .\adPEAS.ps1 -Force
Get-Command Invoke-adPEAS -Syntax
Get-Help Invoke-adPEAS -Full
Get-Command Connect-adPEAS -Syntax
Get-adPEASSession -TestConnection
Convert-adPEASReport -InputJson '.\AD-Audit-MIG4.json' -OutputPath '.\recreated' -Format HTML
~~~

**Статус:** миграция текстов DOC6j через сравнение оригинальных
источников 2.11.0, плюс отдельный RU HTML-слой. Логика аудита, SID,
LDAP-атрибуты, команды исправления и JSON-поля не переводятся.
Полная проверка в живом AD и тесты браузера относятся к MIG5.
