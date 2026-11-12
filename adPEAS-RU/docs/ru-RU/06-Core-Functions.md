# Справочник основных функций

Справочник основных функций получения данных adPEAS v2.

---

## Обзор

Основные функции получают и обрабатывают данные Active Directory по LDAP, служат основой проверок безопасности и могут использоваться самостоятельно.

### Функции получения данных

| Функция | Назначение |
|----------|---------|
| [Get-DomainUser](#get-domainuser) | Запрос учётных записей пользователей |
| [Get-DomainComputer](#get-domaincomputer) | Запрос учётных записей компьютеров |
| [Get-DomainGroup](#get-domaingroup) | Запрос групп и состава участников |
| [Get-DomainGPO](#get-domaingpo) | Запрос объектов групповой политики |
| [Get-DomainObject](#get-domainobject) | Универсальный запрос объектов AD |
| [Get-ObjectACL](#get-objectacl) | Получение списков управления доступом ACL |
| [Get-CertificateTemplate](#get-certificatetemplate) | Запрос шаблонов сертификатов |

### Функции изменения и создания

Подробно о функциях `Set-*` и `New-*` (изменения, методы атак, последующая очистка) см. [справочник модулей Set- и New-](07-Set-Modules.md).

| Функция | Назначение |
|----------|---------|
| [Set-DomainObject](07-Set-Modules.md#set-domainobject) | Изменение объектов AD (атрибутов и ACL) — низкоуровневая базовая функция |
| [Set-DomainUser](07-Set-Modules.md#set-domainuser) | Изменение пользователей (пароль, SPN, делегирование и др.) |
| [Set-DomainComputer](07-Set-Modules.md#set-domaincomputer) | Изменение компьютеров (RBCD, делегирование и др.) |
| [Set-DomainGroup](07-Set-Modules.md#set-domaingroup) | Изменение групп (добавление или удаление участников) |
| [Set-DomainGPO](07-Set-Modules.md#set-domaingpo) | Изменение атрибутов и привязок GPO |
| [Set-CertificateTemplate](07-Set-Modules.md#set-certificatetemplate) | Изменение настроек шаблонов сертификатов |
| [Move-DomainObject](07-Set-Modules.md#move-domainobject) | Перемещение или переименование любого объекта AD (ModifyDN) |
| [New-DomainUser](07-Set-Modules.md#new-domainuser) | Создание учётных записей пользователей |
| [New-DomainComputer](07-Set-Modules.md#new-domaincomputer) | Создание учётных записей компьютеров |
| [New-DomainGroup](07-Set-Modules.md#new-domaingroup) | Создание групп |
| [New-DomainGPO](07-Set-Modules.md#new-domaingpo) | Создание объектов групповой политики |

---

## Get-DomainUser

Получает объекты пользователей AD (обёртка Get-DomainObject).

> **Примечание.** По умолчанию атрибуты преобразуются в удобный вид (время в `DateTime`, UAC как флаги, SID с разрешёнными именами). `-Raw` возвращает исходные LDAP-значения без преобразования.

### Синтаксис

```powershell
Get-DomainUser
    [-Identity <String>]
    [-LDAPFilter <String>]
    [-SearchBase <String>]
    [-Properties <String[]>]
    [-SPN]
    [-AdminCount]
    [-Unconstrained]
    [-Constrained]
    [-RBCD]
    [-TrustedToAuth]
    [-DisallowDelegation]
    [-PreauthNotRequired]
    [-PasswordNotRequired]
    [-PasswordNeverExpires]
    [-PasswordMustChange]
    [-Enabled]
    [-Disabled]
    [-LockedOut]
    [-SmartcardRequired]
    [-AccountExpired]
    [-AccountNeverExpires]
    [-DESOnly]
    [-ReversibleEncryption]
    [-GMSA]
    [-ShowGMSADetails]
    [-ShowOwner]
    [-ResolveGroups]
    [-Raw]
    [-ResultLimit <Int>]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Параметры

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-Identity` | String | Идентификатор пользователя (sAMAccountName, DN, SID либо DOMAIN\user); поддерживаются подстановочные символы. |
| `-LDAPFilter` | String | Произвольный LDAP-фильтр для специальных запросов. |
| `-SearchBase` | String | Альтернативная база поиска (DN); по умолчанию DN домена. |
| `-Properties` | String[] | Массив имён атрибутов, возвращаемых запросом. |
| `-SPN` | Switch | Только пользователи с SPN (потенциальные цели Kerberoasting). |
| `-AdminCount` | Switch | Только пользователи с adminCount=1 (привилегированные учётные записи). |
| `-Unconstrained` | Switch | Пользователи с неограниченным делегированием (флаг TRUSTED_FOR_DELEGATION). |
| `-Constrained` | Switch | Пользователи с ограниченным делегированием (атрибут msDS-AllowedToDelegateTo). |
| `-RBCD` | Switch | Пользователи с RBCD (атрибут msDS-AllowedToActOnBehalfOfOtherIdentity). |
| `-TrustedToAuth` | Switch | Пользователи с переходом протокола / S4U2Self (флаг TRUSTED_TO_AUTH_FOR_DELEGATION). |
| `-DisallowDelegation` | Switch | Пользователи, для которых делегирование ЗАПРЕЩЕНО (установлен флаг NOT_DELEGATED). |
| `-PreauthNotRequired` | Switch | Пользователи с флагом DONT_REQ_PREAUTH (возможная AS-REP Roasting). |
| `-PasswordNotRequired` | Switch | Пользователи с установленным флагом PASSWD_NOTREQD. |
| `-PasswordNeverExpires` | Switch | Пользователи с установленным флагом DONT_EXPIRE_PASSWORD. |
| `-PasswordMustChange` | Switch | Пользователи с pwdLastSet=0 (обязательная смена пароля при следующем входе). |
| `-Enabled` | Switch | Только включённые учётные записи (флаг ACCOUNTDISABLE не установлен). |
| `-Disabled` | Switch | Только отключённые учётные записи (установлен флаг ACCOUNTDISABLE). |
| `-LockedOut` | Switch | Только заблокированные пользователи (lockoutTime > 0). |
| `-SmartcardRequired` | Switch | Пользователи с установленным флагом SMARTCARD_REQUIRED. |
| `-AccountExpired` | Switch | Пользователи, у которых срок действия accountExpires истёк. |
| `-AccountNeverExpires` | Switch | Пользователи, у которых accountExpires равен 0 или не задан. |
| `-DESOnly` | Switch | Пользователи с флагом USE_DES_KEY_ONLY (слабое шифрование). |
| `-ReversibleEncryption` | Switch | Пользователи с флагом ENCRYPTED_TEXT_PWD_ALLOWED (риск безопасности). |
| `-GMSA` | Switch | Только управляемые учётные записи служб: MSA, gMSA и dMSA. |
| `-ShowGMSADetails` | Switch | Дополнительные сведения MSA/gMSA: доступ к паролю, ротация, SPN. Использовать вместе с -GMSA. |
| `-ShowOwner` | Switch | Добавить в возвращаемые объекты свойства Owner и OwnerSID. |
| `-ResolveGroups` | Switch | Добавить `memberOfNested`: основную группу, все группы по цепочке вложенности (с указанием промежуточной группы) и универсальные группы других доменов леса из глобального каталога (GC). Дополнительно один запрос на учётную запись, при обращении к GC — два. |
| `-Raw` | Switch | Вернуть необработанные объекты DirectoryEntry без преобразований. |
| `-ResultLimit` | Int | Ограничить число возвращаемых записей; по умолчанию 0 (без ограничений). |
| `-Domain` | String | Целевой домен (FQDN). |
| `-Server` | String | Определённый контроллер домена для запроса. |
| `-Credential` | PSCredential | Объект PSCredential для аутентификации. |

### Примеры

```powershell
# Получить конкретного пользователя
Get-DomainUser -Identity "administrator"

# Все группы пользователя: memberOf и memberOfNested (основная группа и вложенность)
Get-DomainUser -Identity "jdoe" -ResolveGroups

# Все пользователи со SPN (возможная Kerberoasting)
Get-DomainUser -SPN

# Все привилегированные пользователи
Get-DomainUser -AdminCount

# Пользователи с неограниченным делегированием
Get-DomainUser -Unconstrained

# Пользователи с ограниченным делегированием
Get-DomainUser -Constrained

# Пользователи с переходом протокола (S4U2Self)
Get-DomainUser -TrustedToAuth

# Пользователи с RBCD
Get-DomainUser -RBCD

# Пользователи без обязательной предварительной аутентификации Kerberos (AS-REP Roasting)
Get-DomainUser -PreauthNotRequired

# Все gMSA с дополнительными сведениями
Get-DomainUser -GMSA -ShowGMSADetails

# Отключённые учётные записи
Get-DomainUser -Disabled

# Заблокированные пользователи
Get-DomainUser -LockedOut

# Пользователи с бессрочным паролем
Get-DomainUser -PasswordNeverExpires -Enabled

# Пользователи из определённого OU
Get-DomainUser -SearchBase "OU=Admins,DC=contoso,DC=com"

# Произвольный LDAP-фильтр
Get-DomainUser -LDAPFilter "(description=*admin*)"

# Комбинация нескольких фильтров
Get-DomainUser -SPN -Enabled -AdminCount
```

### Возвращаемые свойства

Распространённые возвращаемые свойства:

- `sAMAccountName` - Имя входа
- `distinguishedName` - Полный путь DN
- `userPrincipalName` - Имя UPN (user@domain.com)
- `objectSid` - Идентификатор безопасности (SID)
- `memberOf` - Членство в группах
- `memberOfNested` - С `-ResolveGroups`: группы, отсутствующие в `memberOf`, включая основную (`Domain Users (primary group)`) и вложенные (`Server Operators (via Tier1)`). Универсальная группа другого домена леса поступает из глобального каталога с указанием домена (`Enterprise Admins (contoso.com, via Tier0)`). Каждая запись содержит `Name`, `Membership`, `Via`, `Domain`, `DistinguishedName` и `SID`. Не обнаруживаются локальные группы других доменов и группы других лесов.
- `userAccountControl` - Флаги учётной записи
- `pwdLastSet` - Дата последнего изменения пароля
- `lastLogon` - Время последнего входа
- `servicePrincipalName` - SPN (если заданы)
- `msDS-AllowedToDelegateTo` - Цели делегирования

---

## Get-DomainComputer

Получает учётные записи компьютеров AD (обёртка Get-DomainObject).

> **Примечание.** По умолчанию атрибуты преобразуются в удобный вид (время в `DateTime`, UAC как флаги, SID с разрешёнными именами). `-Raw` возвращает исходные LDAP-значения без преобразования.

### Синтаксис

```powershell
Get-DomainComputer
    [-Identity <String>]
    [-LDAPFilter <String>]
    [-SearchBase <String>]
    [-Properties <String[]>]
    [-OperatingSystem <String>]
    [-SPN]
    [-Unconstrained]
    [-Constrained]
    [-RBCD]
    [-TrustedToAuth]
    [-LAPS]
    [-Enabled]
    [-Disabled]
    [-HighValueSPN]
    [-KnownSPN <String>]
    [-ShowOwner]
    [-Raw]
    [-ResultLimit <Int>]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Параметры

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-Identity` | String | Идентификатор компьютера (имя, DN, SID); допускаются подстановочные символы. |
| `-LDAPFilter` | String | Произвольный LDAP-фильтр для специальных запросов. |
| `-SearchBase` | String | Альтернативная база поиска (DN); по умолчанию DN домена. |
| `-Properties` | String[] | Массив имён атрибутов, возвращаемых запросом. |
| `-OperatingSystem` | String | Фильтр по ОС (например, "Windows Server 2019", "*2016*"); поддерживаются подстановочные символы. |
| `-SPN` | Switch | Только компьютеры с SPN. |
| `-Unconstrained` | Switch | Компьютеры с неограниченным делегированием (контроллеры домена исключаются). |
| `-Constrained` | Switch | Компьютеры с ограниченным делегированием (атрибут msDS-AllowedToDelegateTo). |
| `-RBCD` | Switch | Компьютеры с RBCD (атрибут msDS-AllowedToActOnBehalfOfOtherIdentity). |
| `-TrustedToAuth` | Switch | Компьютеры с переходом протокола / S4U2Self. |
| `-LAPS` | Switch | Компьютеры с включённым LAPS (устаревший Microsoft LAPS или Windows LAPS). |
| `-Enabled` | Switch | Только включённые учётные записи компьютеров. |
| `-Disabled` | Switch | Только отключённые учётные записи компьютеров. |
| `-HighValueSPN` | Switch | Компьютеры с критически важными службами (MSSQL, Exchange, SCCM, CA и др.). |
| `-KnownSPN` | String | Фильтр по типу службы. Допустимые значения: `MSSQL`, `Exchange`, `SCCM`, `WSUS`, `ADFS`, `CA`, `SCOM`, `Backup`, `HyperV`, `RDP`, `WinRM`, `HTTP`, `FTP`. |
| `-ShowOwner` | Switch | Добавить в возвращаемые объекты свойства Owner и OwnerSID. |
| `-Raw` | Switch | Вернуть необработанные объекты DirectoryEntry без преобразований. |
| `-ResultLimit` | Int | Ограничить число возвращаемых записей; по умолчанию 0 (без ограничений). |
| `-Domain` | String | Целевой домен (FQDN). |
| `-Server` | String | Определённый контроллер домена для запроса. |
| `-Credential` | PSCredential | Объект PSCredential для аутентификации. |

### Значения KnownSPN

| Значение | Описание |
|-------|-------------|
| `MSSQL` | Экземпляры SQL Server (MSSQLSvc/*) |
| `Exchange` | Серверы Exchange (без контроллеров домена) |
| `SCCM` | Серверы SCCM/MECM |
| `WSUS` | Серверы WSUS |
| `ADFS` | Службы федерации AD FS |
| `CA` | Центры сертификации |
| `SCOM` | System Center Operations Manager |
| `Backup` | Серверы резервного копирования (Windows Backup, Veeam) |
| `HyperV` | Узлы Hyper-V |
| `RDP` | Серверы с RDP (TERMSRV/*) |
| `WinRM` | Серверы с WinRM (WSMAN/*) |
| `HTTP` | Веб-серверы (HTTP/*) |
| `FTP` | FTP-серверы (FTP/*) |

### Примеры

```powershell
# Получить определённый компьютер
Get-DomainComputer -Identity "DC01"

# Отобрать компьютеры по ОС
Get-DomainComputer -OperatingSystem "Windows Server 2019"
Get-DomainComputer -OperatingSystem "*Server*"

# Компьютеры с неограниченным делегированием (без контроллеров домена)
Get-DomainComputer -Unconstrained

# Компьютеры с ограниченным делегированием
Get-DomainComputer -Constrained

# Компьютеры с RBCD
Get-DomainComputer -RBCD

# Компьютеры с LAPS
Get-DomainComputer -LAPS

# Все высокоценные цели
Get-DomainComputer -HighValueSPN

# Только серверы SQL
Get-DomainComputer -KnownSPN MSSQL

# Серверы Exchange (только включённые)
Get-DomainComputer -KnownSPN Exchange -Enabled

# Центры сертификации
Get-DomainComputer -KnownSPN CA

# Контроллеры домена
Get-DomainComputer -LDAPFilter "(userAccountControl:1.2.840.113556.1.4.803:=8192)"

# Компьютеры из определённого OU
Get-DomainComputer -SearchBase "OU=Servers,DC=contoso,DC=com"
```

### Возвращаемые свойства

Распространённые возвращаемые свойства:

- `name` - Имя компьютера
- `dNSHostName` - Полное доменное имя FQDN
- `operatingSystem` - Название ОС
- `operatingSystemVersion` - Версия ОС
- `userAccountControl` - Флаги учётной записи
- `ms-Mcs-AdmPwd` - Пароль LAPS (если доступен для чтения)
- `ms-Mcs-AdmPwdExpirationTime` - Срок действия пароля устаревшего LAPS
- `msLAPS-PasswordExpirationTime` - Срок действия пароля Windows LAPS
- `msDS-AllowedToDelegateTo` - Цели ограниченного делегирования

---

## Get-DomainGroup

Получает группы AD и состав участников (обёртка Get-DomainObject).

> **Примечание.** По умолчанию атрибуты преобразуются в удобный вид (время в `DateTime`, UAC как флаги, SID с разрешёнными именами). `-Raw` возвращает исходные LDAP-значения без преобразования.

### Синтаксис

```powershell
Get-DomainGroup
    [-Identity <String>]
    [-LDAPFilter <String>]
    [-SearchBase <String>]
    [-Properties <String[]>]
    [-AdminCount]
    [-GroupScope <String>]
    [-GroupCategory <String>]
    [-ShowMembers]
    [-Recurse]
    [-ShowOwner]
    [-Raw]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Параметры

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-Identity` | String | Идентификатор группы (sAMAccountName, DN, SID либо DOMAIN\group); допускаются подстановочные символы. |
| `-LDAPFilter` | String | Произвольный LDAP-фильтр для специальных запросов. |
| `-SearchBase` | String | Альтернативная база поиска (DN); по умолчанию DN домена. |
| `-Properties` | String[] | Массив имён атрибутов, возвращаемых запросом. |
| `-AdminCount` | Switch | Только группы с adminCount=1 (привилегированные группы). |
| `-GroupScope` | String | Фильтр по области действия группы. Допустимые значения: `DomainLocal`, `Global`, `Universal`. |
| `-GroupCategory` | String | Фильтр по категории группы. Допустимые значения: `Security`, `Distribution`. |
| `-ShowMembers` | Switch | Вместо самой группы вернуть DN непосредственных участников (атрибут `member`). Требуется -Identity; если совпало несколько групп, берётся первая. |
| `-Recurse` | Switch | Подразумевает -ShowMembers и возвращает всех участников: непосредственных, вложенных любой глубины и пользователей, для которых группа (или вложенная группа) является основной. Для каждого участника возвращаются `Name`, `ObjectClass`, `Membership` (`Direct`, `Nested`, `Primary group`), `Via`, `Domain`, `DistinguishedName` и `SID`. Участники из других доменов леса получаются из глобального каталога (однократное подключение); универсальные группы других доменов разворачиваются. Для глобальной группы другого домена доступны лишь участники, для которых она основная; выводится предупреждение с названием группы. |
| `-ShowOwner` | Switch | Добавить в возвращаемые объекты свойства Owner и OwnerSID. |
| `-Raw` | Switch | Вернуть необработанные объекты DirectoryEntry без преобразований. |
| `-Domain` | String | Целевой домен (FQDN). |
| `-Server` | String | Определённый контроллер домена для запроса. |
| `-Credential` | PSCredential | Объект PSCredential для аутентификации. |

### Примеры

```powershell
# Получить определённую группу
Get-DomainGroup -Identity "Domain Admins"

# Поиск группы по SID
Get-DomainGroup -Identity "S-1-5-21-*-512"

# Все привилегированные группы
Get-DomainGroup -AdminCount

# Глобальные группы безопасности
Get-DomainGroup -GroupScope Global -GroupCategory Security

# Универсальные группы
Get-DomainGroup -GroupScope Universal

# Группы рассылки
Get-DomainGroup -GroupCategory Distribution

# Непосредственные участники (DN)
Get-DomainGroup -Identity "Domain Admins" -ShowMembers

# Все участники, включая вложенные группы и основные группы, с указанием цепочки членства
Get-DomainGroup -Identity "Domain Admins" -ShowMembers -Recurse

# Группы, содержащие заданный текст в описании
Get-DomainGroup -LDAPFilter "(description=*admin*)"

# Только группы безопасности
Get-DomainGroup -GroupCategory Security
```

### Возвращаемые свойства

Распространённые возвращаемые свойства:

- `name` - Имя группы
- `sAMAccountName` - Имя для совместимости с Windows до 2000
- `distinguishedName` - Полный путь DN
- `objectSid` - SID группы
- `member` - Непосредственные участники
- `memberOf` - Родительские группы
- `groupType` - Флаги типа группы
- `adminCount` - Признак привилегированной группы

---

## Get-DomainGPO

Получает объекты групповой политики с возможностью расширенного анализа.

> **Примечание.** По умолчанию атрибуты преобразуются в удобный вид (время в `DateTime`, UAC как флаги, SID с разрешёнными именами). `-Raw` возвращает исходные LDAP-значения без преобразования.

### Синтаксис

```powershell
Get-DomainGPO
    [-Identity <String>]
    [-LDAPFilter <String>]
    [-SearchBase <String>]
    [-Properties <String[]>]
    [-AppliedToOU <String>]
    [-Enabled]
    [-Disabled]
    [-ShowLinkedOU]
    [-ShowDangerousSettings]
    [-ShowPermissions]
    [-Raw]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Параметры

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-Identity` | String | Идентификатор GPO (displayName, DN или GUID). |
| `-LDAPFilter` | String | Произвольный LDAP-фильтр для специальных запросов. |
| `-SearchBase` | String | Альтернативная база поиска (DN). |
| `-Properties` | String[] | Массив имён атрибутов, возвращаемых запросом. |
| `-AppliedToOU` | String | Получить GPO, привязанные к заданному OU (в формате DN). |
| `-Enabled` | Switch | Только включённые GPO (flags=0, активны все параметры). |
| `-Disabled` | Switch | Только полностью отключённые GPO (flags=3: отключены параметры компьютера и пользователя). |
| `-ShowLinkedOU` | Switch | Добавить OU, к которым привязана GPO. |
| `-ShowDangerousSettings` | Switch | Проверить GPO на опасные настройки (задания, сценарии, реестр и др.). |
| `-ShowPermissions` | Switch | Добавить разрешения на GPO (кто может редактировать). |
| `-Raw` | Switch | Вернуть необработанные объекты DirectoryEntry без преобразований. |
| `-Domain` | String | Целевой домен (FQDN). |
| `-Server` | String | Определённый контроллер домена для запроса. |
| `-Credential` | PSCredential | Объект PSCredential для аутентификации. |

### Примеры

```powershell
# Все объекты групповой политики
Get-DomainGPO

# Определённая GPO по имени
Get-DomainGPO -Identity "Default Domain Policy"

# Поиск GPO по GUID
Get-DomainGPO -Identity "{6AC1786C-016F-11D2-945F-00C04fB984F9}"

# GPO и связанные с ними OU
Get-DomainGPO -ShowLinkedOU

# GPO, привязанные к конкретному OU
Get-DomainGPO -AppliedToOU "OU=Servers,DC=contoso,DC=com"

# Анализ опасных настроек GPO
Get-DomainGPO -ShowDangerousSettings

# Разрешения GPO (кто может изменять)
Get-DomainGPO -Identity "Default Domain Policy" -ShowPermissions

# Только включённые GPO
Get-DomainGPO -Enabled

# GPO с указанной строкой в имени
Get-DomainGPO -LDAPFilter "(displayName=*Security*)"

# Полный анализ GPO
Get-DomainGPO -ShowLinkedOU -ShowDangerousSettings -ShowPermissions
```

### Обнаружение опасных настроек

При `-ShowDangerousSettings` функция анализирует следующие параметры GPO:

- **Запланированные задачи**: Немедленные задания, сценарии входа и выхода
- **Сценарии запуска**: Сценарии запуска компьютера/пользователя
- **Настройки реестра**: Записи автозапуска, изменения служб
- **Членство в группах**: Изменения локальных администраторов
- **Параметры безопасности**: LAPS, политики паролей
- **Развёртывание файлов**: Пакеты MSI, копирование файлов
- **Конфигурация служб**: Учётные записи служб и типы запуска

### Возвращаемые свойства

Распространённые возвращаемые свойства:

- `displayName` - Отображаемое имя GPO
- `name` - GUID групповой политики
- `distinguishedName` - Полный путь DN
- `gPCFileSysPath` - Путь в SYSVOL
- `whenCreated` - Дата создания
- `whenChanged` - Дата последнего изменения
- `LinkedOUs` - OU, к которым привязана GPO (с -ShowLinkedOU)
- `DangerousSettings` - Найденные проблемы безопасности (с -ShowDangerousSettings)
- `Permissions` - Разрешения на редактирование (с -ShowPermissions)

---

## Get-DomainObject

Универсальная функция запроса любого объекта AD; основа остальных функций Get-Domain*.

> **Примечание.** По умолчанию атрибуты преобразуются в удобный вид (время в `DateTime`, UAC как флаги, SID с разрешёнными именами). `-Raw` возвращает исходные LDAP-значения без преобразования.

### Синтаксис

```powershell
Get-DomainObject
    [-Identity <String>]
    [-LDAPFilter <String>]
    [-SearchBase <String>]
    [-Properties <String[]>]
    [-ObjectClass <String>]
    [-Scope <String>]
    [-IsEnabled]
    [-IsDisabled]
    [-PasswordNeverExpires]
    [-PasswordNotRequired]
    [-PasswordMustChange]
    [-TrustedForDelegation]
    [-TrustedToAuthForDelegation]
    [-NotDelegated]
    [-HasSPN]
    [-AdminCount]
    [-LockedOut]
    [-SmartcardRequired]
    [-AccountExpired]
    [-AccountNeverExpires]
    [-PreauthNotRequired]
    [-DESOnly]
    [-ReversibleEncryption]
    [-ShowOwner]
    [-Raw]
    [-IncludeDeleted]
    [-ResultLimit <Int>]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Параметры

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-Identity` | String | sAMAccountName, DistinguishedName, SID, ObjectGUID или DOMAIN\name; допускаются подстановочные символы. |
| `-ObjectClass` | String | Фильтр по классу объекта (например, "user", "computer", "group", "organizationalUnit"). |
| `-LDAPFilter` | String | Произвольный LDAP-фильтр для специальных запросов. |
| `-Properties` | String[] | Массив имён атрибутов, возвращаемых запросом. |
| `-SearchBase` | String | Альтернативная база поиска (DN); по умолчанию DN домена. |
| `-Scope` | String | Область поиска: Subtree (по умолчанию), OneLevel или Base. |
| `-IsEnabled` | Switch | Только включённые учётные записи (флаг ACCOUNTDISABLE НЕ установлен). |
| `-IsDisabled` | Switch | Только отключённые учётные записи (флаг ACCOUNTDISABLE установлен). |
| `-PasswordNeverExpires` | Switch | Только записи с флагом PASSWORD_NEVER_EXPIRES. |
| `-PasswordNotRequired` | Switch | Только записи с флагом PASSWORD_NOT_REQUIRED. |
| `-PasswordMustChange` | Switch | Только записи с pwdLastSet=0. |
| `-TrustedForDelegation` | Switch | Только записи с флагом TRUSTED_FOR_DELEGATION. |
| `-TrustedToAuthForDelegation` | Switch | Только записи с флагом TRUSTED_TO_AUTH_FOR_DELEGATION. |
| `-NotDelegated` | Switch | Только записи с флагом NOT_DELEGATED. |
| `-HasSPN` | Switch | Только записи с заполненным атрибутом servicePrincipalName. |
| `-AdminCount` | Switch | Только записи с adminCount=1. |
| `-LockedOut` | Switch | Только заблокированные учётные записи (lockoutTime > 0). |
| `-SmartcardRequired` | Switch | Только записи с флагом SMARTCARD_REQUIRED. |
| `-AccountExpired` | Switch | Только записи с истёкшим сроком accountExpires. |
| `-AccountNeverExpires` | Switch | Только записи с accountExpires=0 или без заданного срока. |
| `-PreauthNotRequired` | Switch | Только записи с флагом DONT_REQ_PREAUTH (возможная AS-REP Roasting). |
| `-DESOnly` | Switch | Только записи с флагом USE_DES_KEY_ONLY. |
| `-ReversibleEncryption` | Switch | Только записи с флагом ENCRYPTED_TEXT_PWD_ALLOWED. |
| `-ShowOwner` | Switch | Добавить в возвращаемые объекты свойства Owner и OwnerSID. |
| `-Raw` | Switch | Вернуть исходные значения LDAP без преобразований. |
| `-IncludeDeleted` | Switch | Передать LDAP-контроль показа удалённых объектов: добавить удалённые записи и контейнер Deleted Objects в пределах разрешений учётной записи на перечисление и чтение. |
| `-ResultLimit` | Int | Ограничить число возвращаемых записей; по умолчанию 0 (без ограничений). |
| `-Domain` | String | Целевой домен (FQDN). |
| `-Server` | String | Определённый контроллер домена для запроса. |
| `-Credential` | PSCredential | Объект PSCredential для аутентификации. |

### Примеры

```powershell
# Корневой объект домена
Get-DomainObject -Identity "DC=contoso,DC=com"

# Любой объект по SID
Get-DomainObject -Identity "S-1-5-21-1234567890-1234567890-1234567890-500"

# Объекты указанного класса
Get-DomainObject -LDAPFilter "(objectClass=organizationalUnit)"

# Все OU
Get-DomainObject -ObjectClass organizationalUnit

# Объекты раздела конфигурации
Get-DomainObject -SearchBase "CN=Configuration,DC=contoso,DC=com"

# Объекты схемы
Get-DomainObject -SearchBase "CN=Schema,CN=Configuration,DC=contoso,DC=com" -LDAPFilter "(lDAPDisplayName=servicePrincipalName)"

# Включённые учётные записи с SPN
Get-DomainObject -HasSPN -IsEnabled

# Учётные записи с небезопасным делегированием
Get-DomainObject -TrustedForDelegation

# Учётные записи без обязательной предварительной аутентификации (AS-REP Roasting)
Get-DomainObject -PreauthNotRequired

# Удалённые объекты, доступные для чтения текущей учётной записи
Get-DomainObject -SearchBase "CN=Deleted Objects,DC=contoso,DC=com" -Scope OneLevel -IncludeDeleted
```

---

## Get-ObjectACL

Получает списки управления доступом ACL объектов AD.

### Синтаксис

```powershell
Get-ObjectACL
    [-Identity <String>]
    [-DistinguishedName <String>]
    [-Trustee <String[]>]
    [-ExcludeTrustee <String[]>]
    [-Rights <String[]>]
    [-ExtendedRight <String[]>]
    [-DangerousOnly]
    [-WriteOnly]
    [-ExtendedRightsOnly]
    [-ExplicitOnly]
    [-AllowOnly]
    [-DenyOnly]
    [-IncludeObjectInfo]
    [-NoResolveGUIDs]
    [-NoResolveSIDs]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Параметры

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-Identity` | String | Идентификатор объекта (sAMAccountName, DN, SID); набор параметров по умолчанию. |
| `-DistinguishedName` | String | DN объекта для запроса (альтернатива -Identity). |
| `-Trustee` | String[] | Оставить только ACE для указанных субъектов доступа (имя или SID). |
| `-ExcludeTrustee` | String[] | Исключить из результатов указанных субъектов доступа. |
| `-Rights` | String[] | Фильтр по правам AD. ValidateSet: GenericAll, GenericRead, GenericWrite, GenericExecute, CreateChild, DeleteChild, ListChildren, Self, ReadProperty, WriteProperty, DeleteTree, ListObject, ExtendedRight, Delete, ReadControl, WriteDacl, WriteOwner, Synchronize. |
| `-ExtendedRight` | String[] | Фильтр по определённым расширенным правам (например, "User-Force-Change-Password"). |
| `-DangerousOnly` | Switch | Только опасные ACE (GenericAll, WriteDacl, WriteOwner и др.). |
| `-WriteOnly` | Switch | Только ACE, предоставляющие права записи. |
| `-ExtendedRightsOnly` | Switch | Только ACE с расширенными правами. |
| `-ExplicitOnly` | Switch | Исключить унаследованные ACE, показать только явно назначенные. |
| `-AllowOnly` | Switch | Только разрешающие ACE (Allow), исключить Deny. |
| `-DenyOnly` | Switch | Только запрещающие ACE (Deny), исключить Allow. |
| `-IncludeObjectInfo` | Switch | Добавить сведения о целевом объекте. |
| `-NoResolveGUIDs` | Switch | Не преобразовывать GUID в имена (быстрее). |
| `-NoResolveSIDs` | Switch | Не преобразовывать SID в имена (быстрее). |
| `-Domain` | String | Целевой домен (FQDN). |
| `-Server` | String | Определённый контроллер домена для запроса. |
| `-Credential` | PSCredential | Объект PSCredential для аутентификации. |

### Примеры

```powershell
# ACL корня домена
Get-ObjectACL -Identity "DC=contoso,DC=com"

# Только опасные ACE
Get-ObjectACL -DistinguishedName "DC=contoso,DC=com" -DangerousOnly

# ACL определённого пользователя
Get-ObjectACL -Identity "administrator"

# Только права записи на OU
Get-ObjectACL -DistinguishedName "OU=Admins,DC=contoso,DC=com" -WriteOnly

# Фильтр по конкретному субъекту доступа
Get-ObjectACL -Identity "Domain Admins" -Trustee "S-1-5-21-*-512"

# Только явные (неунаследованные) разрешающие ACE
Get-ObjectACL -Identity "administrator" -ExplicitOnly -AllowOnly

# Быстрый запрос без разрешения GUID/SID в имена
Get-ObjectACL -Identity "DC=contoso,DC=com" -NoResolveGUIDs -NoResolveSIDs
```

---

## Get-CertificateTemplate

Получает шаблоны сертификатов из AD CS.

> **Примечание.** По умолчанию атрибуты преобразуются в удобный вид (время в `DateTime`, UAC как флаги, SID с разрешёнными именами). `-Raw` возвращает исходные LDAP-значения без преобразования.

### Синтаксис

```powershell
Get-CertificateTemplate
    [-Identity <String>]
    [-LDAPFilter <String>]
    [-Properties <String[]>]
    [-SearchBase <String>]
    [-ShowAll]
    [-EnrolleeSuppliesSubject]
    [-NoSecurityExtension]
    [-ClientAuthentication]
    [-ExportableKey]
    [-NoManagerApproval]
    [-EnrollmentAllowed]
    [-Export]
    [-ExportPath <String>]
    [-Raw]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Параметры

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-Identity` | String | Имя шаблона сертификата или OID. |
| `-LDAPFilter` | String | Произвольный LDAP-фильтр для специальных запросов. |
| `-Properties` | String[] | Массив имён атрибутов, возвращаемых запросом. |
| `-SearchBase` | String | Альтернативная база поиска (DN). |
| `-ShowAll` | Switch | Показать все шаблоны, включая отключённые. |
| `-EnrolleeSuppliesSubject` | Switch | Фильтр шаблонов, в которых заявитель самостоятельно задаёт имя субъекта (CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT). |
| `-NoSecurityExtension` | Switch | Фильтр шаблонов без расширения szOID_NTDS_CA_SECURITY_EXT (признак ESC9/ESC10). |
| `-ClientAuthentication` | Switch | Фильтр шаблонов с EKU Client Authentication либо Smartcard Logon. |
| `-ExportableKey` | Switch | Фильтр шаблонов, допускающих экспорт закрытого ключа. |
| `-NoManagerApproval` | Switch | Фильтр шаблонов, не требующих одобрения менеджера УЦ. |
| `-EnrollmentAllowed` | Switch | Фильтр шаблонов, разрешающих выдачу (автоматическую или ручную). |
| `-Export` | Switch | Экспортировать настройки шаблона как исходные значения LDAP (для резервной копии/восстановления). |
| `-ExportPath` | String | Путь к файлу экспорта настроек шаблона. |
| `-Raw` | Switch | Вернуть исходные значения LDAP без преобразований. |
| `-Domain` | String | Целевой домен (FQDN). |
| `-Server` | String | Определённый контроллер домена для запроса. |
| `-Credential` | PSCredential | Объект PSCredential для аутентификации. |

### Примеры

```powershell
# Все шаблоны сертификатов
Get-CertificateTemplate

# Конкретный шаблон
Get-CertificateTemplate -Identity "User"

# Шаблоны с указанием субъекта заявителем (признак ESC1)
Get-CertificateTemplate -EnrolleeSuppliesSubject -ClientAuthentication

# Шаблоны без расширения безопасности (признак ESC9/ESC10)
Get-CertificateTemplate -NoSecurityExtension

# Шаблоны, разрешающие выдачу с экспортируемым ключом
Get-CertificateTemplate -EnrollmentAllowed -ExportableKey

# Экспорт шаблона для резервной копии
Get-CertificateTemplate -Identity "VulnTemplate" -Export -ExportPath "C:\backup\"
```

### Возвращаемые свойства

- `name` - Имя шаблона
- `displayName` - Отображаемое имя
- `msPKI-Certificate-Name-Flag` - Флаги имени
- `msPKI-Enrollment-Flag` - Флаги выдачи сертификата
- `pKIExtendedKeyUsage` - OID расширенных назначений ключа EKU
- `msPKI-Certificate-Application-Policy` - Политики применения
- `nTSecurityDescriptor` - ACL (кому разрешено получать сертификат)

---

## Справочник LDAP-фильтров

### Типовые фильтры

| Назначение | Фильтр |
|---------|--------|
| Все пользователи | `(objectCategory=person)` |
| Все компьютеры | `(objectCategory=computer)` |
| Все группы | `(objectCategory=group)` |
| Включённые учётные записи | `(!(userAccountControl:1.2.840.113556.1.4.803:=2))` |
| Отключённые учётные записи | `(userAccountControl:1.2.840.113556.1.4.803:=2)` |
| Есть SPN | `(servicePrincipalName=*)` |
| Без предварительной аутентификации | `(userAccountControl:1.2.840.113556.1.4.803:=4194304)` |
| Неограниченное делегирование | `(userAccountControl:1.2.840.113556.1.4.803:=524288)` |
| Контроллеры домена | `(userAccountControl:1.2.840.113556.1.4.803:=8192)` |
| Срок действия пароля не истекает | `(userAccountControl:1.2.840.113556.1.4.803:=65536)` |
| AdminCount=1 | `(adminCount=1)` |
| Заблокированные учётные записи | `(lockoutTime>=1)` |
| Требуется смарт-карта | `(userAccountControl:1.2.840.113556.1.4.803:=262144)` |

### Флаги UserAccountControl

| Флаг | Значение | Описание |
|------|-------|-------------|
| ACCOUNTDISABLE | 2 | Учётная запись отключена |
| PASSWD_NOTREQD | 32 | Пароль не требуется |
| NORMAL_ACCOUNT | 512 | Тип учётной записи по умолчанию |
| DONT_EXPIRE_PASSWORD | 65536 | Срок действия пароля не истекает |
| SMARTCARD_REQUIRED | 262144 | Для входа требуется смарт-карта |
| TRUSTED_FOR_DELEGATION | 524288 | Неограниченное делегирование |
| NOT_DELEGATED | 1048576 | Делегирование запрещено |
| USE_DES_KEY_ONLY | 2097152 | Только шифрование DES |
| DONT_REQ_PREAUTH | 4194304 | Без предварительной аутентификации Kerberos |
| TRUSTED_TO_AUTH_FOR_DELEGATION | 16777216 | Переход протокола (S4U2Self) |

### Объединение фильтров

```powershell
# Пользователи со SPN (возможная Kerberoasting)
Get-DomainUser -LDAPFilter "(&(objectCategory=person)(servicePrincipalName=*))"

# Включённые пользователи, не состоящие в Protected Users
Get-DomainUser -LDAPFilter "(&(objectCategory=person)(!(userAccountControl:1.2.840.113556.1.4.803:=2))(!(memberOf=CN=Protected Users,CN=Users,DC=contoso,DC=com)))"

# Компьютеры с LAPS (устаревший Microsoft LAPS либо Windows LAPS)
Get-DomainComputer -LDAPFilter "(|(ms-Mcs-AdmPwdExpirationTime=*)(msLAPS-PasswordExpirationTime=*))"
```

---

## Навигация

- [Назад: сборщик BloodHound](05-BloodHound-Collector.md)
- [Далее: модули Set- и New-](07-Set-Modules.md)
- [На главную](00-Home.md)
