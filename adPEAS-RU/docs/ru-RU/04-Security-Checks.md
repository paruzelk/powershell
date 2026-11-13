# Справочник проверок безопасности

Полный справочник проверок безопасности, выполняемых adPEAS v2.

---

## Фильтрация результатов (снижение шума)

Некоторые проверки исключают из результатов высокопривилегированные учётные записи, чтобы уменьшить шум и выделить находки, требующие действий. Это сделано намеренно: ожидается, что Domain Admins и Enterprise Admins имеют права DCSync, GenericAll или сброса пароля. Их включение скрыло бы действительно нетипичные разрешения.

### Проверки с фильтрацией

В следующих проверках высокопривилегированные учётные записи по умолчанию отфильтровываются:

| Проверка | Что исключается | Параметр отмены фильтра |
|-------|-----------------|-------------------|
| **Get-DangerousACLs** | Domain Admins, Enterprise Admins и SYSTEM с правами GenericAll/WriteDACL/WriteOwner/DCSync | `-IncludePrivileged` |
| **Get-PrivilegedGroupMembers** | Анализ ACL AdminSDHolder исключает ожидаемых привилегированных субъектов | `-IncludePrivileged` |
| **Get-PasswordResetRights** | Выводятся только находки Critical/High; привилегированные учётные записи с правом сброса имеют низкую серьёзность | `-IncludePrivileged` |
| **Get-LAPSPermissions** | Только серьёзности Critical/High/Medium; чтение LAPS группой Domain Admins ожидаемо | `-IncludePrivileged` |
| **Get-GPOPermissions** | Group Policy Creator Owners и Domain Admins с правами изменения GPO | `-IncludePrivileged` |
| **Get-ADCSVulnerabilities** | Domain Admins и Enterprise Admins с правом регистрации сертификатов | `-IncludePrivileged` |
| **Get-AddComputerRights** | Domain Admins и Account Operators с правом создания компьютеров | `-IncludePrivileged` |
| **Get-BitLockerRecoveryKeyAccess** | Привилегированные субъекты с делегированным чтением паролей восстановления — Domain Admins читают их по умолчанию | `-IncludePrivileged` |
| **Get-DeletedObjectAccess** | Субъекты Tier 0 и служебные группы Exchange с правом просмотра Deleted Objects: Administrators может иметь его по умолчанию, установка Exchange выдаёт его | `-IncludePrivileged` |

### Как работает фильтрация

adPEAS использует **классификацию по SID**, независимую от языка ОС (работает на английской, немецкой, французской и других локализациях):

1. **Test-IsPrivileged**: распределяет субъекты по категориям:
   - `Privileged`: Domain Admins (-512), Enterprise Admins (-519), Schema Admins (-518), Administrators (S-1-5-32-544), SYSTEM (S-1-5-18)
   - `Operator`: Account Operators, Server Operators, Backup Operators, Print Operators.
   - `BroadGroup`: Everyone, Authenticated Users, Domain Users.
   - `Standard`: обычные пользователи и группы.

2. **Test-IsExpectedInScope**: применяет фильтрацию с учётом контекста конкретной проверки:
   - Возвращает `Expected` для субъектов, которым право положено (исключаются из результатов).
   - Возвращает `Attention` для формально ожидаемых, но значимых для безопасности субъектов (жёлтая подсветка при `-IncludePrivileged`).
   - Возвращает `Finding` для субъектов, которым такого права быть НЕ должно (показываются всегда).

### Как увидеть все результаты

Для отображения всех результатов, включая привилегированные учётные записи, используйте `-IncludePrivileged`:

```powershell
# По умолчанию: только неожиданные/опасные находки
Get-DangerousACLs

# Все находки, включая Domain Admins и Enterprise Admins (жёлтая подсветка)
Get-DangerousACLs -IncludePrivileged
```

### Проверки без фильтрации

Следующие проверки намеренно показывают ВСЕ учётные записи независимо от уровня привилегий:

- **Get-KerberoastableAccounts** — Kerberoasting возможен и для административных учётных записей.
- **Get-ASREPRoastableAccounts** — отсутствие предварительной аутентификации опасно для любой записи.
- **Get-UnconstrainedDelegation** — неограниченное делегирование опасно независимо от типа записи.
- **Get-ConstrainedDelegation** — отображает все конфигурации делегирования.
- **Get-InactiveAdminAccounts** — цель проверки: найти неактивные административные записи.
- **Get-AdminPasswordNeverExpires** — цель проверки: найти административные записи с бессрочным паролем.

### Проверки только администраторов (adminCount=1)

Некоторые проверки ограничиваются учётными записями с `adminCount=1` — AD отмечает так записи, состоящие или ранее состоявшие в привилегированных группах:

| Проверка | Область LDAP | Дополнительная проверка |
|-------|------------|----------------------|
| **Get-InactiveAdminAccounts** | `adminCount=1` и только включённые записи | `Test-AccountActivity` для обнаружения неактивности |
| **Get-AdminPasswordNeverExpires** | `adminCount=1` и бессрочный пароль | `Test-IsPrivileged` для исключения устаревшего adminCount |
| **Get-AdminReversibleEncryption** | `adminCount=1` и обратимое шифрование | Нет (любая такая административная запись — находка) |

**Об оставшемся adminCount:** при исключении пользователя из привилегированной группы AD **не снимает автоматически** `adminCount=1`. Get-AdminPasswordNeverExpires с помощью `Test-IsPrivileged` проверяет, остаётся ли запись действительно привилегированной, а случаи устаревшего adminCount отмечает отдельно.

### Обработка отключённых учётных записей

adPEAS **не исключает отключённые учётные записи глобально**. Большинство проверок возвращает и включённые, и отключённые записи: отключённая запись остаётся риском для того, кто сможет включить её и воспользоваться ранее назначенными правами.

Исключение — проверки Kerberos. Они пропускают отключённые записи по причине работы протокола, а не предпочтений аудитора: на запрос билета для отключённого субъекта KDC отвечает KDC_ERR_CLIENT_REVOKED, поэтому получить билет для взлома и злоупотребить делегированием невозможно, пока запись отключена.

Проверки, запрашивающие из AD только включённые записи:

| Проверка | Причина |
|-------|-----|
| **Get-KerberoastableAccounts** | KDC не выдаёт сервисный билет для отключённой записи; хеш для подбора недоступен |
| **Get-ASREPRoastableAccounts** | Аналогично: AS-REP для отключённой записи не выдаётся |
| **Get-UnconstrainedDelegation** | Делегирование выполняет запись, способная пройти аутентификацию |
| **Get-ConstrainedDelegation** | То же для обеих рассматриваемых совокупностей |
| **Get-ResourceBasedConstrainedDelegation** | Аналогично |
| **Get-InactiveAdminAccounts** | Только включённые записи — цель: найти *действующих*, но не используемых администраторов |
| **Get-LAPSPermissions** | Только включённые компьютеры — пароли LAPS отключённых компьютеров не используются при текущем доступе |

Даже отключённая запись с SPN или делегированием представляет интерес, если её можно включить: для оценки нужно знать, кто может изменять запись. Это проверяют `Get-PasswordResetRights` и `Get-DangerousACLs`, а не запрос билета, который KDC не выдаёт.

---

## Обзор

adPEAS выполняет более 43 проверок безопасности, организованных в десять категорий. Все модули
выполняются по умолчанию, **кроме Shares**: его требуется явно запросить (`-Module Shares`), поскольку он открывает
SMB-соединение со всеми компьютерами Windows домена, что должно быть осознанным решением
оператора аудита.

| Модуль | Проверок | Назначение |
| ------------- | ------ | ----------------------------------------- |
| Domain | 5 | Конфигурация домена, доверия и политики |
| Creds | 7 | Способы раскрытия учётных данных |
| Rights | 6 | Анализ ACL и разрешений |
| Delegation | 3 | Ошибки настройки делегирования Kerberos |
| ADCS | 2 | Уязвимости служб сертификатов |
| Accounts | 9 | Привилегированные записи и параметры безопасности |
| GPO | 4 | Безопасность групповых политик |
| Computer | 6 | Безопасность компьютерных учётных записей |
| Application | 3 | Инфраструктура корпоративных приложений |
| Shares | 1 | Доступные общие ресурсы и учётные данные на них (только по запросу) |

---

## Модуль Domain

Анализирует конфигурацию домена и параметры его безопасности.

### Get-DomainInformation

**Назначение**: получает общую информацию о домене и его функциональном уровне.

**Что проверяется**:
- Функциональный уровень домена.
- Функциональный уровень леса.
- Контроллеры домена.
- Что остаётся после удаления объекта в лесу: срок хранения объектов-заглушек (`tombstoneLifetime` в `CN=Directory Service`, 60 дней при отсутствии настройки; значение меньше 180 дней нового леса — сигнал: более старая резервная копия уже не может быть восстановлена) и включена ли корзина AD (по `msDS-EnabledFeature` в контейнере Partitions; отключённая корзина при уровне леса 2008 R2 или выше — сигнал), а также срок хранения удалённых объектов при включённой корзине.
- Какая служба реплицирует SYSVOL: DFSR, FRS или обе, пока миграция не достигла состояния Eliminated. Данные читаются из набора реплик FRS и группы репликации DFSR для SYSVOL в `CN=System`, а также из глобального состояния в `msDFSR-Flags`. FRS — сигнал риска: технология устарела, и контроллер Windows Server 1709 или новее в такой домен добавить нельзя.

**Влияние на безопасность**: устаревшие функциональные уровни могут не поддерживать защитные механизмы и указывать на наличие старых уязвимых DC.

| Функциональный уровень | Серьёзность |
|-----------------|----------|
| Windows 2000/2003 | Критическая (EOL) |
| Windows 2008/R2 | Высокая (EOL) |
| Windows 2012/R2 | Средняя |
| Windows 2016 | Низкая |
| Windows 2019+ | Информационная |

**Использование**:
```powershell
Get-DomainInformation
```

---

### Get-DomainPasswordPolicy

**Назначение**: анализирует политику паролей домена по умолчанию.

**Что проверяется**:
- Максимальный срок действия пароля (отключён — пароли бессрочны).
- Минимальная длина пароля (меньше 8 — слабая политика).
- Требование сложности паролей.
- Порог блокировки учётной записи.
- Настройка обратимого шифрования.
- История паролей (`pwdHistoryLength`): значение 0 позволяет сразу вернуть пароль, заменённый при сбросе, — предупреждающий признак; стандартная настройка Microsoft запоминает 24 пароля.
- Детальные политики паролей Fine-Grained Password Policies: те же параметры (длина, сложность, обратимое шифрование, порог и продолжительность блокировки, окно наблюдения, минимальный и максимальный возраст, история паролей), приоритет и объекты применения.
- Без прав Domain Admin параметры политик по умолчанию прочитать нельзя; вместо этого определяются их имена и назначения: перечисляется Password Settings Container (содержит имена всех политик без атрибутов), `msDS-PSOApplied` на соответствующих пользователях и группах и `msDS-ResultantPSO` текущей учётной записи. Возвращаются имена и прямые назначения, но не настройки.

**Влияние на безопасность**: слабая парольная политика упрощает подбор паролей и атаки перебором без блокировки.

**Использование**:
```powershell
Get-DomainPasswordPolicy
```

---

### Get-DomainTrusts

**Назначение**: перечисляет доверительные отношения доменов и лесов.

**Что проверяется**:
- Направление доверия (входящее, исходящее, двустороннее).
- Тип доверия (лес, внешнее, сокращённое).
- Состояние фильтрации SID.
- Настройки выборочной аутентификации.
- Типы шифрования Kerberos, разрешённые между доверенными доменами, по `msDS-SupportedEncryptionTypes` объекта доверия. Если атрибут отсутствует, доверие использует RC4 без AES (KB4492348); изменение 2026 года, сделавшее AES типом по умолчанию для учётных записей, не распространяется на доверия. Отсутствие AES — предупреждающий признак.
- SID домена-партнёра (`securityIdentifier` в объекте доверия).
- Для доверия, при котором партнёр доверяет этому домену, — время последней смены пароля междоменной учётной записи `<flatName>$`. Доверяющий домен меняет его примерно раз в 30 дней; 90 дней и более — сигнал остановки ротации, когда ранее извлечённый ключ доверия остаётся действительным.

**Влияние на безопасность**: внешние доверия могут позволить горизонтальное перемещение по сети. Двусторонние доверия затрагивают оба домена. Отключённая фильтрация SID допускает атаки через SID History. Отсутствие AES оставляет RC4 на границе доверия; если для доверия с MIT Kerberos пароль выбран администратором, ключ доверия может быть подобран автономно по referral-билету.

**Использование**:
```powershell
Get-DomainTrusts
```

---

### Get-LDAPConfiguration

**Назначение**: проверяет настройки безопасности LDAP на контроллерах домена.

**Что проверяется**:
- Обязательность подписи LDAP.
- Принудительная привязка канала LDAP (channel binding).
- `dsHeuristics` в `CN=Directory Service` — одна строка на весь лес, не управляемая
  GPO. Четыре символа могут отключить защиту сразу на всех контроллерах домена:
  - символ 7: анонимные LDAP-операции за пределами rootDSE.
  - символ 8: анонимные вызовы интерфейса адресной книги NSPI.
  - символ 16: исключение групп Account, Server, Print или Backup Operators и
    их участников из защиты AdminSDHolder.
  - символ 21: отключение проверок уникальности UPN, SPN и псевдонимов SPN.

  Символ вне определённых спецификацией значений обозначается как неизвестный, без
  приписывания ему значения.

**Влияние на безопасность**: отсутствие подписи LDAP допускает атаки «человек посередине». Анонимный доступ позволяет разведку без учётных данных. Группа операторов, исключённая из AdminSDHolder, сохраняет назначенные ей и участникам права, а такие группы могут влиять на контроллеры домена. При отключённой проверке псевдонимов SPN субъект с правом записи SPN может присвоить своей записи имя службы сервера.

**Использование**:
```powershell
Get-LDAPConfiguration
```

---

### Get-SMBSigningStatus

**Назначение**: проверяет подпись SMB на контроллерах домена.

**Что проверяется**:
- Требование подписи SMB на контроллерах домена.
- Состояние включения подписи SMB.

**Влияние на безопасность**: без подписи SMB возможны атаки ретрансляции SMB, перехват и перенаправление аутентификации.

**Использование**:
```powershell
Get-SMBSigningStatus
```

---

## Модуль Creds

Выявляет способы раскрытия учётных данных.

### Get-LAPSCredentialAccess

**Назначение**: проверяет, может ли текущий пользователь читать пароли LAPS.

**Что проверяется**:
- Фактический доступ на чтение атрибутов пароля LAPS.
- У каких компьютеров текущему пользователю доступны пароли LAPS.

**Влияние на безопасность**: чтение паролей LAPS даёт доступ к учётным данным локальных администраторов соответствующих компьютеров и может позволить горизонтальное перемещение.

**Использование**:
```powershell
Get-LAPSCredentialAccess
```

---

### Get-BitLockerRecoveryKeyAccess

**Назначение**: проверяет, какие ключи восстановления BitLocker текущий пользователь может читать из AD.

**Что проверяется**:
- Доступные для чтения `msFVE-RecoveryPassword` у объектов `msFVE-RecoveryInformation` (дочерних объектов компьютера).
- 48-значный пароль восстановления, GUID восстановления/тома и время сохранения в AD.
- Компьютер, к которому относится ключ (определяется по родительскому DN).

**Как работает**: один запрос по поддереву с серверным фильтром `(&(objectClass=msFVE-RecoveryInformation)(msFVE-RecoveryPassword=*))` для всего домена. Фильтр наличия атрибута учитывает ACL, поэтому DC возвращает только объекты восстановления, пароль которых текущему пользователю действительно разрешено читать; отдельного перебора каждого компьютера нет. Если хранение ключей BitLocker в домене не применяется (нет схемы/объектов `msFVE-RecoveryInformation`), дорогостоящий запрос пропускается, а результат кешируется до конца сеанса.

**Влияние на безопасность**: чтение ключа нередко законно для служб поддержки и восстановления, поэтому отмечается как *подсказка*, а не находка. Прочитанный ключ позволяет разблокировать защищённый BitLocker том в автономном режиме при физическом доступе или наличии образа диска; чрезмерно широкое чтение может указывать на избыточное делегирование в OU компьютеров.

**Кто ещё может читать**: дополнительный раздел перечисляет субъектов с делегированным правом чтения `msFVE-RecoveryPassword` на контейнерах компьютеров (включая отключённые компьютеры: их пароль восстановления остаётся действительным для диска) через `Get-OUPermissions -CheckType BitLocker`. В схеме атрибут конфиденциальный, а чтение объектов `msFVE-RecoveryInformation` по умолчанию доступно лишь Domain Admins и SYSTEM; нужны **одновременно** `ReadProperty` и `ControlAccess` на этих объектах. Обе части права объединяются по контейнеру, а строка показывает, действует ли оно сейчас, блокируется конфиденциальным флагом (*подсказка*, станет действующим при снятии флага) или невозможно определить из-за недоступности схемы. Один `ControlAccess` без чтения ничего не даёт и не отображается. ACE, заданные непосредственно на одном компьютере или объекте восстановления, не выявляются. Привилегированные субъекты скрыты без `-IncludePrivileged`.

**Использование**:
```powershell
Get-BitLockerRecoveryKeyAccess

# Также показать привилегированных субъектов с делегированным чтением
Get-BitLockerRecoveryKeyAccess -IncludePrivileged
```

---

### Get-CredentialRoaming

**Назначение**: сообщает о пользователях, чьи мастер-ключи DPAPI и закрытые ключи сохраняются в AD, и о возможности чтения этого материала другими субъектами.

**Что проверяется**:
- Какие пользователи имеют синхронизированный материал учётных данных (`msPKIDPAPIMasterKeys`, `msPKIAccountCredentials`) и когда он синхронизирован (`msPKIRoamingTimeStamp`).
- Отмечены ли оба атрибута как конфиденциальные в схеме (`searchFlags`, бит 7, `fCONFIDENTIAL` = 128).
- Какие субъекты обладают **делегированным** чтением атрибутов на содержащих материал контейнерах.
- Есть ли привилегированные записи среди затронутых пользователей и субъектов с делегированными правами.

**Как работает**: используются два серверных фильтра наличия — `(msPKIDPAPIMasterKeys=*)` и `(msPKIAccountCredentials=*)`. Содержимое BLOB-атрибутов намеренно **не извлекается**: передаются только имя записи, DN и время. Для аудита шифротекст не нужен, а помещение DPAPI-ключей в Base64 в HTML-отчёт само создало бы выявляемую утечку. Оба атрибута исключены из отображения централизованно, поэтому их не выводят другие проверки. Флаг конфиденциальности однократно для леса определяется по двум объектам `attributeSchema`; имена объектов схемы (`ms-PKI-DPAPIMasterKeys`) отличаются от имён атрибутов, поэтому проверяются оба варианта. Результат определяется по менее защищённому атрибуту; если схема недоступна, состояние обозначается *неизвестным*, а не подтверждённо безопасным или опасным. Затем `Get-OUPermissions -CheckType CredentialRoaming` проверяет делегированные ACE чтения контейнеров, содержащих пользователей, один раз на контейнер, а не на пользователя: DACL контейнера уже содержит унаследованные права.

**Влияние на безопасность**: атрибуты содержат шифротекст, не открытый текст. Мастер-ключ запечатан предварительным ключом из пароля пользователя **и** резервным ключом домена, закрытые ключи запечатаны мастер-ключами. Само наличие такого материала — *подсказка*: закрытые ключи хранятся в AD, хотя не обязаны, и могут быть использованы после получения хеша пользователя либо резервного ключа домена. Если материал может читать низкопривилегированный субъект, это *находка*: без флага конфиденциальности чтение следует обычным ACE объекта пользователя, и в типовом домене любой аутентифицированный пользователь может собрать синхронизированный материал других пользователей обычным LDAP-чтением. Вместе с резервным ключом домена (доступным каждому администратору домена) это позволяет восстановить чужие закрытые ключи автономно, а сертификат клиентской аутентификации затем позволяет войти как этот пользователь без пароля. Эти ограничения не распространяются на субъекты с DCSync, копией `ntds.dit` либо резервной копией AD.

**Делегированное чтение**: конфиденциальный флаг регулирует общий доступ, но сам по себе ничего не говорит о делегированных правах, которые могут быть выданы ошибочно. Применимость ACE зависит от схемы: одна и та же ACE в одном лесу является *находкой*, в другом — пока не действующей *подсказкой*:

| ACE предоставляет | Атрибуты конфиденциальны | Оценка |
|---|---|---|
| `ReadProperty` | нет | действует сейчас — находка |
| `ReadProperty` | да | блокируется флагом — подсказка (начнёт действовать после его снятия) |
| `ReadProperty` + `ControlAccess` либо `GenericAll` | любое значение | действует сейчас — находка |

ACE с одним `ControlAccess`, ограниченным определённым атрибутом, учитывается как право: в типовом ACL `ReadProperty` обычно уже доступно всем аутентифицированным пользователям без отдельного делегирования. *Неограниченная* ACE `ControlAccess` («все расширенные права») здесь не заявляется — её анализирует `Get-DangerousACLs`. Чтение лишь `ms-PKI-RoamingTimeStamp` оценивается как Low и скрывается из отчёта по умолчанию: время — не учётные данные. Привилегированные субъекты скрыты без `-IncludePrivileged`.

**Не охватывается**: ACE, назначенная непосредственно объекту одного пользователя в обход контейнера, и делегирование на контейнере, пользователи которого никогда ничего не синхронизировали. Там пока нечего читать, но это станет видно при первой синхронизации.

**Использование**:
```powershell
Get-CredentialRoaming

# Также показать привилегированных субъектов с делегированным чтением
Get-CredentialRoaming -IncludePrivileged
```

---

### Get-CredentialExposure

**Назначение**: выявляет учётные данные в SYSVOL, сценариях NETLOGON и Group Policy Preferences.

**Что проверяется**:
- Пароли GPP в XML-файлах SYSVOL (атрибут cpassword, MS14-025).
- Пароли AutoAdminLogon в Registry.xml (открытый текст).
- Учётные данные, записанные непосредственно в сценариях NETLOGON/SYSVOL и файлах настроек (.bat, .cmd, .ps1, .psm1, .psd1, .vbs, .vbe, .kix, .txt, .ini, .inf, .conf, .cnf, .config, .json, .yml, .yaml, .reg, .vnc) и файлах комментариев GPO (.cmtx). Исключён GptTmpl.inf: в нём каждое совпадение относится к парольной политике; Registry.pol разбирается отдельно для поиска значений паролей.
- Расшифровываемые пароли VNC: файлы подключения VNC Viewer (.vnc, с указанным в них узлом), .ini UltraVNC и TightVNC, а также параметры реестра, раздаваемые политикой для RealVNC, TightVNC, TigerVNC и UltraVNC (REG_SZ/REG_BINARY). Все эти реализации VNC шифруют пароль одним опубликованным ключом DES, поэтому сохранённое значение фактически является паролем.
- Пароли из файлов ответов Windows (unattend XML, распознаваемых по корневому элементу): пароли администратора, локальных записей, автоматического входа, присоединения к домену; скрытые Windows SIM значения декодируются.
- Команды net use, содержащие пароли.
- Закодированные сценарии VBScript (.vbe, декодируются автоматически).
- Произвольные UNC-пути и локальные каталоги (автономный режим).

**Уровни достоверности обнаружения**:

| Уровень | Серьёзность | Примеры шаблонов |
|------|----------|-----------------|
| Уровень 1 (высокая достоверность) | Находка | GPP cpassword, `password=Secret123`, `net use ... /user:admin pass`, PSExec с `-p`, строки подключения |
| Уровень 2 (ниже достоверность) | Подсказка | Общие упоминания `password`, `credential`, парольные элементы XML |

**Влияние на безопасность**: GPP использует опубликованный ключ Microsoft AES, VNC — опубликованный DES; оба легко расшифровать. Учётные данные из сценариев SYSVOL доступны всем аутентифицированным пользователям домена.

**Запись, которой принадлежат учётные данные**: пароли GPP, значения AutoAdminLogon и команды `net use` сопровождаются строкой `accountInAD`. Она показывает, существует ли одноимённая доменная запись, включена ли она, привилегирована ли, а также менялся ли пароль после последней записи файла. Переменные, локальные и встроенные учётные записи, имена из другого домена или компьютера и записи из `Groups.xml` (по определению локальные) обозначаются отдельно, а не ищутся в AD. При отсутствии сеанса каталога строка не выводится.

**Использование**:
```powershell
# Сканирование доменных SYSVOL/NETLOGON
Get-CredentialExposure

# Произвольный UNC-путь (нужен отдельный сеанс Connect-adPEAS либо -Credential)
Get-CredentialExposure -Path "\\server\share"
```

---

### Get-PasswordInDescription

**Назначение**: выявляет пользовательские и компьютерные записи с возможными учётными данными в атрибутах description или info.

**Что проверяется**:
- Атрибуты description и info у пользователей.
- Атрибуты description и info у компьютеров.
- Присваивания пароля высокой достоверности (например, `password=Secret123`).
- Общие упоминания учётных данных для ручной проверки.

**Влияние на безопасность**: администраторы иногда записывают пароли прямо в description или info объектов AD. Все аутентифицированные пользователи домена могут читать эти атрибуты, что раскрывает пароли даже низкопривилегированным субъектам.

**Уровни достоверности обнаружения**:

| Уровень | Серьёзность | Примеры шаблонов |
|------|----------|-----------------|
| Уровень 1 (высокая достоверность) | Находка | `password=Secret123`, `pwd: admin`, `kennwort=pass` |
| Уровень 2 (ниже достоверность) | Подсказка | Общие упоминания `password`, `credentials`, `secret=...` |

**Шаблоны исключения** отсекают ложные срабатывания по текстам парольных политик, справочной информации и заглушкам.

**Использование**:
```powershell
Get-PasswordInDescription
```

---

### Get-DeletedObjectAccess

**Назначение**: проверяет, какие удалённые объекты читает текущий пользователь, остались ли в них учётные данные и кто ещё вправе их перечислять.

**Что проверяется**:
- Все удалённые объекты, перечисляемые текущим пользователем в контейнере Deleted Objects домена; контейнер определяется по well-known GUID, чтение выполняется с контролем показа удалённых (`1.2.840.113556.1.4.417`).
- Читает ли пользователь через членство в Administrators или благодаря делегированию на контейнере; второй вариант — *подсказка*.
- Текстовые атрибуты, проверяемые `Get-PasswordInDescription`, с теми же шаблонами из `Get-CredentialTextMatch`, и Unix-атрибуты пароля из `Get-UnixPasswordAccounts`.
- Субъекты вне Tier 0, которым разрешено перечислять контейнер: применимая к нему ACE с List Contents, общим чтением, полным контролем, а также владелец контейнера.

**Влияние на безопасность**: при включённой корзине AD удалённый объект сохраняет все атрибуты в Deleted Objects до истечения срока хранения удалённых объектов — по умолчанию 180 дней. Пароль, вписанный в описание служебной записи, остаётся после её удаления; проверки действующих объектов больше его не видят. По умолчанию контейнер перечисляют лишь SYSTEM и Administrators (наблюдение: обычный пользователь видит только DN). Microsoft описывает выдачу List Contents и Read Property для доступа службы поддержки к удалённым объектам. Удалённый объект сохраняет собственный дескриптор безопасности, поэтому обладатель права перечислять контейнер читает в каждом объекте лишь разрешённые его ACL поля. Широкая группа с таким правом — *находка*, прочий субъект — *подсказка*.

**Не охватывается**: ACL контейнера по умолчанию читают только администраторы; у обычного пользователя проверка сообщает об этом. Для восстановления удалённых объектов необходимо право Reanimate-Tombstones на корне раздела именования, о котором сообщают `Get-DangerousACLs` для домена и `Get-CriticalObjectACLs` для раздела конфигурации. Включение корзины и сроки хранения показываются `Get-DomainInformation`.

**Использование**:
```powershell
Get-DeletedObjectAccess

# Также перечислить Tier 0 и служебные группы Exchange
Get-DeletedObjectAccess -IncludePrivileged
```

---

### Get-KerberoastableAccounts

**Назначение**: находит учётные записи, уязвимые к Kerberoasting.

**Что проверяется**:
- Пользовательские записи с атрибутом servicePrincipalName.
- Состояние записи (включена, не krbtgt).
- Поддерживаемые типы шифрования.

**Влияние на безопасность**: для любого SPN можно запросить сервисный билет и подбирать его ключ автономно; слабые пароли могут быть подобраны за часы. Результат содержит хеши, совместимые с Hashcat.

**Примечание OPSEC**: проверка запрашивает билеты TGS у KDC. Используйте `-OPSEC` для её пропуска.

**Использование**:
```powershell
Get-KerberoastableAccounts
```

---

### Get-ASREPRoastableAccounts

**Назначение**: находит записи, уязвимые к AS-REP Roasting.

**Что проверяется**:
- Записи с флагом DONT_REQUIRE_PREAUTH.
- Состояние включения учётной записи.

**Влияние на безопасность**: AS-REP может быть запрошен без учётных данных и подобран автономно; выводятся хеши, совместимые с Hashcat.

**Примечание OPSEC**: проверка запрашивает AS-REP у KDC. Используйте `-OPSEC` для её пропуска.

**Использование**:
```powershell
Get-ASREPRoastableAccounts
```

---

### Get-UnixPasswordAccounts

**Назначение**: находит записи с паролями в Unix-атрибутах.

**Что проверяется**:
- `unixUserPassword` attribute
- `userPassword` attribute
- `msSFU30Password` attribute
- `sambaNTPassword` attribute (Samba NT hash)
- `sambaLMPassword` attribute (Samba LM hash)

**Влияние на безопасность**: эти атрибуты могут содержать пароли открытым текстом или слабые хеши (DES, MD5). Хеши Samba NT непосредственно применимы для Pass-the-Hash. Любой доменный пользователь может читать эти атрибуты.

**Использование**:
```powershell
Get-UnixPasswordAccounts
```

---

## Rights Module

Analyzes Access Control Lists and permissions.

### Get-DangerousACLs

**Purpose**: Identifies dangerous permissions on the domain root object.

**What it checks**:
- DCSync rights (DS-Replication-Get-Changes + Get-Changes-All)
- GenericAll (Full Control)
- GenericWrite
- WriteDacl
- WriteOwner

**Security Impact**: Non-privileged accounts with these rights can escalate to Domain Admin through DCSync attacks or by modifying privileged objects.

**Usage**:
```powershell
# Show non-privileged accounts with dangerous rights (default)
Get-DangerousACLs

# Include privileged accounts (Domain Admins, Enterprise Admins, etc.)
Get-DangerousACLs -IncludePrivileged
```

---

### Get-CriticalObjectACLs

**Purpose**: Finds principals outside Tier-0 that control the schema, the configuration partition, the partitions container, the RID Manager, the infrastructure object or a site.

**What it checks**:
- The schema naming context head, the configuration naming context head, `CN=Partitions` in the configuration naming context, `CN=RID Manager$,CN=System` and `CN=Infrastructure`
- Owner, GenericAll, GenericWrite, WriteDacl, WriteOwner and unrestricted WriteProperty on each
- The role transfer right of each object (Change-Schema-Master, Change-Domain-Master, Change-Rid-Master, Change-Infrastructure-Master) and all extended rights
- Reanimate-Tombstones on the configuration head - the right a restore of an object deleted from the configuration is checked against, certificate templates among them. By default only Enterprise Admins hold it there. Not on the schema head: schema objects cannot be deleted
- WriteProperty on `rIDAvailablePool` of the RID Manager
- WriteProperty on `gPLink` of every site - a GPO linked there reaches every computer of the site, domain controllers included
- Operator groups count as outside Tier-0

**Security Impact**: Schema control changes the default security descriptor of every new object in the forest; a role object under control moves its operations master role, and the RID pool can be exhausted.

**Usage**:
```powershell
Get-CriticalObjectACLs
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludePrivileged` | Include privileged accounts in output (shown in yellow) |

---

### Get-DangerousOUPermissions

**Purpose**: Scans all OUs for dangerous permissions.

**What it checks**:
- GenericAll on OUs containing privileged users
- Password reset rights on OUs
- Account control modification rights
- Group membership modification rights
- Object creation rights

**Security Impact**: Dangerous OU permissions enable attackers to reset passwords, modify group memberships, or create new privileged accounts within the OU.

**Usage**:
```powershell
Get-DangerousOUPermissions
```

---

### Get-PasswordResetRights

**Purpose**: Identifies who can reset passwords on privileged OUs.

**What it checks**:
- Accounts with User-Force-Change-Password right
- Accounts with AllExtendedRights on user objects
- Scope of password reset permissions

**Security Impact**: Password reset rights on admin accounts enable immediate account takeover without knowing the current password.

**Usage**:
```powershell
Get-PasswordResetRights
```

---

### Get-AddComputerRights

**Purpose**: Analyzes "Add Computer to Domain" permissions.

**What it checks**:
- `ms-DS-MachineAccountQuota` attribute (default: 10)
- ACLs on CN=Computers container
- GPO User Rights Assignment (SeMachineAccountPrivilege)

**Security Impact**: Creating rogue computer accounts enables RBCD attacks. Attackers can add a computer they control and configure delegation to compromise other resources.

**Usage**:
```powershell
# Show non-privileged accounts with add computer rights (default)
Get-AddComputerRights

# Include privileged accounts (Domain Admins, Account Operators, etc.)
Get-AddComputerRights -IncludePrivileged
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludePrivileged` | Include privileged accounts in output (shown in yellow) |

---

### Get-GPOUserRightsAssignment

**Purpose**: Compares the Windows user rights a GPO assigns against the set Windows ships, and reports the difference.

**Why a comparison**: the `[Privilege Rights]` section of `GptTmpl.inf` is absolute, not additive. The principals a GPO lists for a right become the complete set of holders on every computer the policy reaches. The GPO's list and the documented default list therefore describe the same thing, and the difference between them is what matters — in both directions.

**What it checks**:
- The `[Privilege Rights]` section of `GptTmpl.inf` in every GPO
- **Holders beyond the Windows default** — the escalation risk, reported at the right's own tier. Privilege-escalation/credential privileges (SeDebug, SeBackup, SeRestore, SeTakeOwnership, SeImpersonate, SeAssignPrimaryToken, SeCreateToken, SeTcb, SeLoadDriver, SeEnableDelegation, SeSyncAgent, SeManageVolume, SeSecurity, SeRelabel, SeTrustedCredManAccess) are Findings; logon rights (RDP / service / batch / interactive logon, change system time, shutdown) are Hints
- **Default holders the GPO removes** — reported as a Note. Usually deliberate hardening, occasionally a service about to break
- Rights granted to broad principals (Everyone, Authenticated Users, Domain Users) — escalated to Finding regardless of tier
- The correct baseline for the machines the policy reaches: domain controllers and member computers have different defaults, and a policy reaching both is measured against the union
- Whether the GPO currently applies at all (disabled half, no link)
- Maps each finding to the affected OUs / domain-wide scope via GPO links

**Why not a filter on the holder**: an identity filter — hide privileged SIDs, operator groups, service identities — fails in both directions. `Backup Operators` holding `SeDebugPrivilege` is not a Windows default and is a clean path to SYSTEM, and an identity filter hides it because the group looks privileged. Meanwhile which principals hold a right by default depends on the right, not on how privileged the holder looks.

**Baseline gaps are visible, not guessed**: a right whose default set is not established carries no baseline, and the finding says so. `SeServiceLogonRight` is that case — what holds it depends on which products are installed — and the check falls back to an identity filter for that one right.

**Security Impact**: A single GPO can grant a low-level privilege (e.g. SeDebugPrivilege → SYSTEM, SeBackupPrivilege → read SAM/NTDS) across every computer it applies to — a direct, often domain-wide privilege-escalation and lateral-movement path. `SeMachineAccountPrivilege` is covered separately by Get-AddComputerRights; `Se*Deny*` rights take access away and are not evaluated.

**Usage**:
```powershell
# Show the assignments that depart from the Windows default (default)
Get-GPOUserRightsAssignment

# Show every assignment, including the ones matching the default
Get-GPOUserRightsAssignment -IncludeDefaults
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludeDefaults` | Also report assignments that match the Windows default |
| `-IncludePrivileged` | Alias of `-IncludeDefaults`, kept so existing invocations keep working |

---

### Get-LAPSPermissions

**Purpose**: Identifies who can read LAPS passwords.

**What it checks**:
- Read permissions on `ms-Mcs-AdmPwd` (Legacy LAPS)
- Read permissions on `msLAPS-Password` (Windows LAPS)
- Non-privileged accounts with LAPS read access

**Security Impact**: Non-privileged accounts with LAPS read access can obtain local administrator passwords for computers, enabling lateral movement.

**Usage**:
```powershell
Get-LAPSPermissions
```

---

## Delegation Module

Identifies Kerberos delegation misconfigurations.

### Get-UnconstrainedDelegation

**Purpose**: Finds accounts with unconstrained delegation.

**What it checks**:
- User accounts with TRUSTED_FOR_DELEGATION flag
- Computer accounts with unconstrained delegation (excluding DCs)

**Security Impact**: Accounts can impersonate any user to any service. Attackers can use print spooler coercion or similar techniques to capture TGTs and impersonate any domain user.

**Usage**:
```powershell
Get-UnconstrainedDelegation
```

---

### Get-ConstrainedDelegation

**Purpose**: Finds accounts with constrained delegation.

**What it checks**:
- `msDS-AllowedToDelegateTo` attribute
- Protocol transition capability (S4U2Self)
- Delegation whose target SPN points at a Domain Controller

**Security Impact**: While more restricted than unconstrained, constrained delegation to a Domain Controller enables privilege escalation to Domain Admin. The service class in the SPN is not a limit: all SPNs registered to one host account share a single key, so a ticket issued for one service can be rewritten to another.

**Usage**:
```powershell
Get-ConstrainedDelegation
```

---

### Get-ResourceBasedConstrainedDelegation

**Purpose**: Finds Resource-Based Constrained Delegation (RBCD) configurations.

**What it checks**:
- `msDS-AllowedToActOnBehalfOfOtherIdentity` attribute
- Which accounts can delegate to which resources

**Security Impact**: RBCD can be exploited if an attacker can modify the `msDS-AllowedToActOnBehalfOfOtherIdentity` attribute on a computer object, enabling impersonation attacks.

**Usage**:
```powershell
Get-ResourceBasedConstrainedDelegation
```

---

## ADCS Module

Analyzes Active Directory Certificate Services.

### Get-CertificateAuthority

**Purpose**: Enumerates Certificate Authority infrastructure.

**What it checks**:
- CA servers and their configuration
- Published certificate templates
- Enrollment endpoints (HTTP, RPC)

**Security Impact**: Informational - provides an overview of the PKI infrastructure for further analysis. Identifies attack surface for ADCS exploits.

**Usage**:
```powershell
Get-CertificateAuthority
```

---

### Get-ADCSTemplate

**Purpose**: Lists all certificate templates and their configuration.

**What it checks**:
- Template name and OID
- Enrollment permissions
- Extended Key Usage (EKU)
- Authentication capability settings

**Security Impact**: Informational - required to understand which templates might be vulnerable. Templates with Client Authentication EKU are particularly interesting.

**Usage**:
```powershell
Get-ADCSTemplate
```

---

### Get-ADCSVulnerabilities

**Purpose**: Identifies vulnerable ADCS configurations.

**What it checks**:

| ESC   | Vulnerability                                            |
| ----- | -------------------------------------------------------- |
| ESC1  | Template allows enrollee-supplied SAN + client auth      |
| ESC2  | Template allows any purpose EKU                          |
| ESC3  | Enrollment agent template abuse (both the agent template and its target) |
| ESC4  | Template with vulnerable ACLs                            |
| ESC5  | Vulnerable PKI container permissions                     |
| ESC8  | Web enrollment detection (HTTP/HTTPS + NTLM/EPA config)  |
| ESC9  | No security extension + client auth                      |
| ESC13 | Issuance policy linked to AD group                       |
| ESC15 | Schema v1 + enrollee-supplied subject (CVE-2024-49019)   |

Two more are covered by other checks, because the misconfiguration does not live on a
template or a CA:

| ESC   | Vulnerability                                            | Check |
| ----- | -------------------------------------------------------- | ----- |
| ESC10 | Weak certificate mapping on the domain controllers - `StrongCertificateBindingEnforcement=0`, or the UPN bit in `CertificateMappingMethods` | `Get-GPORegistrySettings`, where Group Policy deploys them |
| ESC14 | Weak explicit mapping in `altSecurityIdentities`, and write access to that attribute on a privileged account | `Get-WeakCertificateMapping` |

**Deliberately not implemented**: ESC6 (`EDITF_ATTRIBUTESUBJECTALTNAME2`), ESC7
(`ManageCA` / `ManageCertificates`), ESC11 (`IF_ENFORCEENCRYPTICERTREQUEST`) and ESC16
(`DisableExtensionList`).

All four live in the registry of the CA host, under
`HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration`, and reading them needs
administrative access to that host - either remote registry as a local administrator, or
the `ICertAdminD2` RPC interface with `ManageCA`. adPEAS is built to run as an ordinary
domain user. A check that answers "cannot tell" in the normal case is worse than no check:
a quiet result reads as a clean domain. Where those rights do exist, Certipy reports all
four.

ESC12 (private key on a YubiHSM, extractable with shell access to the CA) is outside what
any directory scan can see.

**ESC5 Details**: Checks dangerous permissions on PKI container objects:
- `CN=Public Key Services` - Root PKI container
- `CN=Certificate Templates` - Allows creating/modifying templates
- `CN=Enrollment Services` - Controls enrollment services
- `CN=NTAuthCertificates` - Controls trusted CAs for Kerberos
- `CN=AIA` - Controls the CA certificates published for chain building
- `CN=CDP` - Controls where revocation lists are looked up
- `CN=OID` - Controls issuance policies (ESC13-related)

Dangerous rights: GenericAll, WriteDacl, WriteOwner, GenericWrite. If unprivileged users have these permissions, they can manipulate the entire PKI infrastructure.

**NTAuth Store**: Every certificate in `CN=NTAuthCertificates` names an issuer trusted to issue a certificate that logs on as any account. An Enterprise CA publishes its own certificate there, so each entry gets an `EnterpriseCA` row: the Enterprise CA of this forest that holds it, an earlier certificate of one (renewed since), or none - a third-party, standalone or removed CA, which is a *Hint* to verify. Expired and SHA1/MD5-signed entries are hints as well, and the section says when more than one CA is trusted. An issuer added on a single machine with `certutil -enterprise -addstore NTAuth` is not in the directory and cannot be seen.

**Security Impact**: ADCS vulnerabilities can allow any domain user to obtain certificates for any other user, including Domain Admins, leading to full domain compromise.

**Usage**:
```powershell
# Show non-privileged accounts with enrollment rights (default)
Get-ADCSVulnerabilities

# Include privileged accounts (Domain Admins, Enterprise Admins, etc.)
Get-ADCSVulnerabilities -IncludePrivileged
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludePrivileged` | Include privileged accounts in output (shown in yellow) |

---

## Accounts Module

Analyzes privileged account security.

### Get-PrivilegedGroupMembers

**Purpose**: Lists members of privileged groups.

**What it checks**:
- Domain Admins members
- Enterprise Admins members
- Schema Admins members
- Administrators members
- Account Operators members
- Backup Operators members
- Server Operators members
- Print Operators members

**Security Impact**: Identifies all accounts with elevated privileges. Large numbers of privileged accounts increase attack surface.

**Groups AdminSDHolder does not protect**: SDProp resets the DACL of the protected groups (Microsoft's list: Account Operators, Administrators, Backup Operators, Domain Admins, Domain Controllers, Enterprise Admins, Enterprise Key Admins, Key Admins, Print Operators, Read-only Domain Controllers, Replicator, Schema Admins, Server Operators) from the AdminSDHolder template, which the check reads. Every other privileged group keeps its own ACEs, so the check also reads the DACL and the owner of each privileged group without `adminCount=1`, of every group nested into one, and of the Exchange groups in `OU=Microsoft Exchange Security Groups`. It reports who may write the `member` attribute (or every attribute), use the Self-Membership validated write, change the DACL or owner, holds full control, or owns the group - explicit and inherited ACEs alike - through the same identity gate as the AdminSDHolder analysis. A holder is a *Finding* where a group it can take over is worth the domain (DnsAdmins, ESX Admins, the Exchange groups, a group reached from a tier-0 group) and a *Hint* where every such group is operator-level (Group Policy Creator Owners, Cert Publishers, Remote Management Users, Hyper-V Administrators, a group nested into Backup Operators). The groups read, and any that could not be read, are one object at the head of the section. Account Operators control every unprotected group through the default security descriptor of the group class; that is said in one line - a *Hint* while Account Operators has members - rather than once per group. A group that was protected once keeps a stale `adminCount=1` and is not read - except where character 16 of `dsHeuristics` takes Account, Server, Print or Backup Operators out of AdminSDHolder protection: those groups, and the groups reached only through them, are read whatever their `adminCount` says, and the summary object names them. Groups in another domain are not read.

**Who may take over a privileged account**: the check reads the DACL and the owner of every privileged user and managed service account of the domain it found - computers are left to `Get-NonDefaultComputerOwners`, which reads the explicit entries on every computer object. It reports who holds full control, may change the DACL or the owner, may write every attribute, holds all extended rights or the password reset right, or may write `msDS-KeyCredentialLink` (shadow credentials), `servicePrincipalName` (targeted Kerberoasting), `altSecurityIdentities` (certificate mapping), `userAccountControl` or the User-Account-Restrictions set, `scriptPath`, or - on a group managed service account - `msDS-GroupMSAMembership`, and who owns the account; explicit and inherited ACEs alike, through the same identity gate. A holder is a *Finding* where an account it can take over is in a group worth the domain (a tier-0 group or one nested into it, DnsAdmins, ESX Admins) and a *Hint* where every one is in operator-level groups only (Group Policy Creator Owners, Cert Publishers, Backup Operators, ...). How many accounts were read, how many of them AdminSDHolder protects, and which could not be read are one object at the head of the section. On an account AdminSDHolder protects (`adminCount=1`) a right the AdminSDHolder template grants the same trustee is reported once, with AdminSDHolder; what is on the account beyond the template is reported. Key Admins and Enterprise Key Admins write `msDS-KeyCredentialLink` by design; Account Operators control every account AdminSDHolder does not protect through the default security descriptor of the user class, which is said in one line.

**Usage**:
```powershell
# Show non-privileged accounts with group membership (default)
Get-PrivilegedGroupMembers

# Include privileged accounts (Domain Admins, etc.) in output
Get-PrivilegedGroupMembers -IncludePrivileged
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludePrivileged` | Include privileged accounts in output (shown in yellow) |

---

### Get-SIDHistoryInjection

**Purpose**: Detects accounts with privileged SIDs in sIDHistory (SID History Injection attack vector).

**What it checks**:
- User and computer accounts with sIDHistory attribute set
- Privileged SIDs in sIDHistory (Domain Admins, Enterprise Admins, Administrators, etc.)
- Operator group SIDs (Account Operators, Backup Operators, etc.)
- Non-privileged SIDs as migration artifacts (optional)

**Security Impact**: SID History Injection allows attackers to add privileged SIDs to an account's sIDHistory, granting those privileges without being a direct member of the privileged group. This is a critical persistence and privilege escalation technique.

| SID Type in sIDHistory | Severity |
|-----------------------|----------|
| Domain Admins (-512) | Critical |
| Enterprise Admins (-519) | Critical |
| Administrators (S-1-5-32-544) | Critical |
| Account Operators (S-1-5-32-548) | High |
| Backup Operators (S-1-5-32-551) | High |
| Non-privileged SIDs | Info (migration artifact) |

**Usage**:
```powershell
# Check for privileged SIDs only
Get-SIDHistoryInjection

# Include non-privileged SIDs (migration artifacts)
Get-SIDHistoryInjection -IncludeNonPrivileged
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludeNonPrivileged` | Also report accounts whose sIDHistory contains only non-privileged SIDs (domain migration artifacts). These are shown in a separate section as Hints. Without this switch, only accounts with privileged SIDs (Domain Admins, Operators, etc.) in sIDHistory are reported. |

**Output Properties**:
- `privilegedSIDHistory`: Formatted list of privileged SIDs found
- `privilegedSIDHistoryCount`: Number of privileged SIDs
- `sidHistoryInjectionRisk`: Risk level (CRITICAL for privileged SIDs)

---

### Get-ManagedServiceAccountSecurity

**Purpose**: Analyzes security of (Group) Managed Service Accounts.

**What it checks**:
- gMSA password readers (who can read the managed password)
- Constrained delegation configuration
- Password age and rotation status
- Delegated Managed Service Account (dMSA, Windows Server 2025) links, read from the accounts a dMSA replaces: pairings outside a regular migration, links the account does not return, privileged accounts replaced by a dMSA, and migrations started or completed
- Who may use each dMSA (msDS-GroupMSAMembership) and who owns that descriptor, judged like a gMSA's password readers - only where the scan can read the dMSAs, which by default takes an administrator

**Security Impact**: Overly permissive gMSA password readers can obtain service account credentials. Misconfigured delegation enables privilege escalation. A dMSA paired with an account receives that account's group memberships and keys from the KDC, so a pairing outside a migration hands the account to whoever controls the dMSA.

**Usage**:
```powershell
Get-ManagedServiceAccountSecurity
```

---

### Get-ProtectedUsersStatus

**Purpose**: Identifies privileged accounts not in Protected Users group.

**What it checks**:
- Membership of privileged accounts in Protected Users group
- Which admin accounts are missing protection
- For a Tier-0 account linked to an authentication policy silo or a policy: whether it actually applies - enforced, audit only, no policy, half an enrollment, superseded by the silo, or exempt as the built-in Administrator

**Security Impact**: Protected Users group provides: no NTLM authentication, no delegation, no DES/RC4 encryption, Kerberos TGT limited to 4 hours. Accounts outside this group are more vulnerable to credential theft.

**Usage**:
```powershell
Get-ProtectedUsersStatus
```

---

### Get-AuthenticationPolicySilos

**Purpose**: Checks whether authentication policy silos and authentication policies restrict anybody, and who can change them.

**What it checks**:
- Enforcement of each silo, and of each policy assigned directly to accounts - in audit mode the KDC logs and refuses nothing; for a silo member the silo's flag decides
- Silos without a policy, or without an enrolled account
- Incomplete enrollment: an account listed as a member without the silo assigned, or assigned without being listed - the KDC applies a silo only with both (MS-KILE 3.3.5.4)
- The built-in Administrator in a silo or under a policy - Windows always exempts it
- Sign-on and service conditions (`AllowedToAuthenticateFrom/To`, shown as SDDL) that admit a broad group such as Domain Computers
- Write access to silos and policies for principals outside Tier 0
- TGT lifetimes, shown in minutes
- Where a condition is set: whether the domain controllers support claims and Kerberos armoring - "KDC support for claims, compound authentication and Kerberos armoring", read from the Registry.pol of the GPOs that reach them, with GPO precedence per value. Without it the KDC cannot evaluate the conditions; the client half of the setting is not read

**Security Impact**: Silos keep Tier 0 accounts off ordinary machines. A silo that restricts nobody looks like that protection without providing it, and whoever can write to a silo or a policy decides which restrictions apply - including none. Silos and policies live in the configuration partition and are readable by every domain user.

**Usage**:
```powershell
Get-AuthenticationPolicySilos
```

---

### Get-RODCPasswordReplication

**Purpose**: Checks which privileged accounts a read-only Domain Controller may cache, or has cached, the password of.

**What it checks**:
- Each RODC's allow list (`msDS-RevealOnDemandGroup`) and deny list (`msDS-NeverRevealGroup`) against the token of every privileged account, primary group included - deny wins
- The privileged accounts whose secrets the RODC has received already (`msDS-RevealedUsers`)
- Whether the Denied RODC Password Replication Group is still on the RODC's deny list

**Security Impact**: An RODC stands where physical security is weakest, and every password it caches can be extracted from it. A privileged account it may cache is outside the Tier-0 boundary.

**Usage**:
```powershell
Get-RODCPasswordReplication
```

---

### Get-InactiveAdminAccounts

**Purpose**: Finds privileged accounts that haven't been used.

**What it checks**:
- Accounts inactive for 90+ days
- Accounts that have never logged on
- Enabled accounts with old passwords

**Security Impact**: Inactive admin accounts are forgotten attack vectors. They may have weak/known passwords and can be compromised without detection.

**Usage**:
```powershell
Get-InactiveAdminAccounts
```

---

### Get-AdminPasswordNeverExpires

**Purpose**: Identifies privileged accounts with non-expiring passwords.

**What it checks**:
- Password expiration flag on privileged accounts
- Which admin accounts bypass password rotation

**Security Impact**: Violates password rotation policies and increases exposure window. Compromised passwords remain valid indefinitely.

**Usage**:
```powershell
Get-AdminPasswordNeverExpires
```

---

### Get-AdminReversibleEncryption

**Purpose**: Finds privileged accounts storing passwords with reversible encryption.

**What it checks**:
- Reversible encryption flag on privileged accounts
- Which admin accounts have this dangerous setting

**Security Impact**: Passwords can be decrypted from ntds.dit if an attacker obtains the database.

**Usage**:
```powershell
Get-AdminReversibleEncryption
```

---

### Get-PasswordNotRequired

**Purpose**: Detects enabled user accounts with the PASSWD_NOTREQD flag set.

**What it checks**:
- Enabled user accounts with PASSWD_NOTREQD flag (UAC bit 32)
- Whether affected accounts are privileged or service accounts
- Last password change date for risk assessment

**Security Impact**: Accounts with the "Password Not Required" flag can bypass the domain password policy and may have an empty password. While the flag alone does not guarantee an empty password (a password may have been set later), it indicates a hygiene issue and potential attack vector.

**Usage**:
```powershell
Get-PasswordNotRequired
```

---

### Get-NonDefaultUserOwners

**Purpose**: Finds user accounts owned by non-default principals.

**What it checks**:
- User account owner attribute (nTSecurityDescriptor)
- Users owned by accounts other than Domain Admins

**Security Impact**: Object owners have implicit WriteDACL permission, allowing them to modify the object's security descriptor. If a low-privileged user owns a user account, they can grant themselves full control over that account, potentially leading to account takeover.

| Owner Type | Severity |
|------------|----------|
| Domain Admins | Expected (default) |
| Enterprise Admins | Expected |
| Regular user | Medium (privilege escalation risk) |
| Service account | Medium |

**Noise Reduction**: Exchange Health Mailboxes (`HealthMailbox*` in `CN=Monitoring Mailboxes,CN=Microsoft Exchange System Objects`) are filtered by default as they are expected to be owned by the Exchange server that created them.

**Usage**:
```powershell
# Default (excludes Exchange Health Mailboxes)
Get-NonDefaultUserOwners

# Include Exchange Health Mailboxes
Get-NonDefaultUserOwners -IncludeHealthMailboxes
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludeHealthMailboxes` | Include Exchange Health Mailboxes in output |

**Output Properties**:
- `Owner`: Name of the account that owns the user object
- `OwnerSID`: SID of the owner

**Common Causes**:
- User created by a non-admin via delegation
- Ownership explicitly changed post-creation
- Migration artifacts

---

### Get-LogonScriptPermissions

**Purpose**: Finds the logon scripts accounts run that a principal beyond the administrators may change.

**What it checks**:
- The `scriptPath` of every enabled account; a relative path is resolved to `\\<domain>\NETLOGON\<path>`
- The NTFS permissions of each distinct script and of the folder it is in, read over SMB from the domain's own name and enabled computers of the domain - the same reader the GPO script check uses
- Writers beyond the administrators and privileged accounts, how many accounts run the script, and the privileged accounts among them by name

**Security Impact**: Windows runs an account's logon script at every logon of that account, as that account. Whoever may change the script runs code as every account that has it set - an administrator among them with the administrator's rights. NETLOGON is the scripts folder of SYSVOL, and its file permissions are nobody's GPO permissions.

A local path exists on each computer and is not read; a path that could not be read is listed with the reason. The share permissions are not read.

**Usage**:
```powershell
Get-LogonScriptPermissions

# Make no SMB connection - the scripts are not read
Get-LogonScriptPermissions -OPSEC
```

**Output Properties**:
- `logonScript`: The script, as a UNC path
- `logonScriptRisk`: Who may change it and what that reaches
- `logonScriptPermissions`: One `path: Identity (Rights)` row per principal beyond the administrators that may write the script or its folder
- `runByAccounts`: How many enabled accounts run the script
- `runByPrivilegedAccounts`: The privileged accounts among them, operators included

---

## GPO Module

Analyzes Group Policy security.

**Locating a reported GPO in SYSVOL**: every finding that comes from a Group Policy names
the policy the same way, whichever check produced it, so it can be opened without guessing:

- `GPOName` - the display name. Convenient, but not unique and not a path.
- `GPOGUID` - the policy's identifier, and literally its folder name under
  `\\<domain>\SYSVOL\<domain>\Policies\`.
- `GPOPath` - the full path to that folder, as the directory records it in
  `gPCFileSysPath`. Read from LDAP rather than assembled from the GUID, so that it is the
  same string in every section: `gPCFileSysPath` names the domain, while adPEAS reads
  SYSVOL through one specific domain controller, and the two spell the same folder
  differently.

Checks that report a **setting found inside** a policy add one more row:

- `SourceFile` - the file inside the GPO folder the setting was read from, relative to it,
  for example `Machine\Registry.pol` or
  `MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf`. The leading `Machine` or `User`
  matters: both halves of a policy carry files of the same name and they reach different
  targets.

So the full path to the evidence behind such a finding is `<GPOPath>\<SourceFile>`.

Checks that report the **GPO object itself** - `Get-GPOPermissions`, the SMB and LDAP
signing checks, `Get-AddComputerRights` - have no `SourceFile`, because the policy is the
finding rather than a file inside it. They additionally show `distinguishedName`, which has
no counterpart among the setting-level findings. Under the hood these are native LDAP
objects and the three shared rows are relabelled for display only, so `displayName`, `Name`
and `gPCFileSysPath` keep their LDAP names as properties and in the JSON export.

One deliberate departure: the credential checks (`Get-CredentialExposure`) print the
complete path to the file as `FilePath` instead, because they also scan NETLOGON and a
caller-supplied `-Path`, where there is no GPO folder to be relative to - and for a finding
that does come from a GPO, that full path already contains the GUID.

**Dormant policies are held back by default**: a service provider who ships a library of
Group Policies and links a handful of them leaves the rest configured and applying nowhere.
Reporting their settings buries the policies that are live, so a finding whose policy is
not linked or not enabled is not listed. A count line gives the number and names how many
distinct GPOs it covers, and one card per reason names the policies held back:

```
[?] Analyzing LDAP Signing/Channel Binding via GPO (SYSVOL)... (Get-LDAPConfiguration)
[*] 4 finding(s) hidden:

Group:       Dormant policies - not linked
Reason:      Linked nowhere, so the settings reach no machine until the policy is linked.
Count:       3 policies
Policies:    Workstation Baseline V2              {11111111-1111-1111-1111-111111111111}
             DC Hardening V2                     {22222222-2222-2222-2222-222222222222}
             Member Server Baseline V2           {33333333-3333-3333-3333-333333333333}

[+] Found LDAP security configuration in 2 GPO(s):
    ... the active findings ...
```

**The held-back block comes first, before the active findings.** After the `[?] Analyzing`
line a reader sees what was held back and why, then `[+] Found ...` as the heading for the
policies actually reported. The `[+] Found` line heads the finding objects, not the dampening
block, so it sits directly above them.

Each reason is one **card** - a grey object in the console, a collapsible card in the HTML
report, folded by default and sorted behind the real findings. One card per reason, not per
policy: sixteen held-back GPOs become two or three cards. The policies live inside the card,
display name left and GUID on column 45 - both, because the name is what a reader recognises
and the GUID is the folder under `\\<domain>\SYSVOL\<domain>\Policies\` they need in order to
look. A name longer than the column pushes its GUID right rather than being truncated; a
cut-off GPO name is no longer findable in SYSVOL.

The count line counts findings and the card counts policies, which is why it names its unit
(`on N GPO(s)`) whenever the two numbers differ - ten registry values in one unlinked GPO are
one card line. Unlinked before disabled, since an unlinked policy is a cleanup candidate while
a disabled one is a switch somebody threw on purpose; within a card the policies sort by name,
so two runs against the same domain print the same thing. The list is not truncated - its
length is bounded by the number of policies in the domain, and cutting it off would leave
`-IncludeInactive` as the only way to learn the missing names, far more output than a cap saves.

**A configuration that exposes nothing is counted and named, not printed in full.** The same
reasoning in a second direction: adPEAS reports a right or a setting granted to somebody who
should not have it, so the opposite - a GPO that hardens - is worth a card and the policy
named, not a block per finding. It is the same card the dampening summary uses and sits in the
same place: before the active headline, grey, folded in the HTML report. Both checks are behind
`-IncludeDefaults` (aliased `-IncludePrivileged`, which `Invoke-adPEAS` passes, so the hint
naming it is reachable from a full scan), which lists them in full:

```
[*] 10 assignment(s) only remove default holders - hardening, or a service about to break on 2 GPO(s) (-IncludeDefaults to list)

Group:       Assignments that only remove default holders
Reason:      Hardening more often than not, occasionally a service about to break - never a grant.
Count:       10 assignment(s) on 2 GPO(s)
Policies:    WSUS Baseline V1                    {44444444-4444-4444-4444-444444444444}
             DC Hardening V2                     {22222222-2222-2222-2222-222222222222}
```

- `Get-GPOUserRightsAssignment`: an assignment that only *removes* default holders. Nine of
  those printed as full blocks ahead of two real findings is how the rule was arrived at. An
  assignment that adds *and* removes keeps its `RemovedFromDefault` row - there the removals
  are the rest of that right's holder set, not a separate claim.
- `Get-GPOPointAndPrint`: a configuration whose verdict is *Hardened* or *controls no driver
  installation*. Printing one meant eight rows agreeing in green with the `Exploitability`
  line above them. The User Configuration case stays visible: Windows ignores it (KB2307161),
  so it is not an exposure either, but somebody hardened and it does not take effect - a
  different statement from a hardening that works.

As with the dormant cards, the count line counts findings while the card counts policies -
several rights in one GPO, or both halves of one Point and Print policy - so it names its unit
(`on N GPO(s)`) whenever the two numbers differ.

It is held back, not dropped. `-IncludeInactive` on the individual check lists the dormant
findings in full, greyed, with `LinkedOUs` and `GPOStatus` on the row saying why. The switch is
deliberately not available on `Invoke-adPEAS`, so the hint naming it appears only when a check
was called directly.

Three things worth knowing about where the line is drawn:

- It applies to checks that report a **setting inside** a policy. The credential checks are
  exempt: a `cpassword` in `Groups.xml` is readable by Authenticated Users whether the
  policy is linked or not, so linkage has no bearing on the exposure. `Get-GPOPermissions`
  is exempt too - who may edit a dormant policy still matters, because editing it and then
  linking it is a two-step path - and it shows `LinkedOUs` and `GPOStatus` anyway.
- "Not linked or not enabled" is read from the directory: no enabled link, or the relevant
  configuration half switched off. It is **not** an RSoP answer. A WMI filter that matches
  nothing, security filtering on the Apply Group Policy right, Enforced and block
  inheritance are all invisible, and a policy linked to an OU holding no computer counts as
  active.
- Nothing is held back when the linkage could not be read. An enumeration that failed
  answers unknown, and a finding is never demoted on missing information.

Suppressing a finding also keeps it out of the HTML report and the JSON export, so a scan
comparison will show such a finding as gone once someone disables a link.

**Reading `EffectiveSetting`**: where several GPOs configure the same thing, this row says
which of them decides the value, and why. It replaced a `True`/`False` called
`IsEffectiveSetting`, which could not express the answer - a `False` meant either "a
higher-priority policy overrides this one" or "this policy reaches no machine at all", and
those call for completely different work.

| Row reads | Means |
|-----------|-------|
| `Yes - wins precedence on the Domain Controllers OU` | Linked at or below the Domain Controllers OU and first in link order. This is the value the DCs run with. |
| `Yes - wins precedence at the domain root` | Linked at the domain root, with no Domain Controllers OU policy outranking it. |
| `Yes - wins precedence on its site` | Linked to the site a domain controller is in, and nowhere above a domain controller. Site policies are applied before the domain's, so it decides only what no domain or OU policy configures - unless its link is enforced. |
| `Yes - applies on its linked OUs; no precedence comparison there` | Linked to ordinary OUs and applies to the machines in them. The caveat is literal: adPEAS does not compare link order below the domain level, so two policies on the same OU with opposite values are both reported this way. |
| `Yes - applies below its links, but not on the domain controllers: ...` | Linked above a domain controller, but a container on the way blocks inheritance and none of its links is enforced. It applies to the other machines below its links. |
| `No - overridden by '<name>' (link order <n>)` | Configured, reaches machines, but another policy wins. Read the named policy to see what actually applies. |
| `No - the policy is linked nowhere` | Configured and linked to nothing. It changes nothing today, and is worth cleaning up or linking. |
| `No - every link is disabled` | Linked, but every link is switched off, so it reaches nothing either. `GPOStatus` says the same in its own row. |

`EffectiveSetting` weighs linkage, enforcement and link order. In the LDAP and SMB signing
checks it reads the domain controllers the way the `reachesDomainControllers` row does:
where their computer objects actually are, the site each is in, and the containers that
block inheritance. Whether the policy's computer configuration is switched off is a
separate question, answered by `GPOStatus`.

### Get-GPOPermissions

**Purpose**: Identifies who can modify Group Policy Objects.

**What it checks**:
- Write permissions on GPO objects
- Non-privileged accounts with GPO edit rights
- Write access to each policy's folder in SYSVOL (`Policies\{GUID}`), the other half of a GPO
- GPO linkage to sensitive OUs
- Affected computer count (including Domain Controllers)
- Policies whose folder or `gpt.ini` is missing in SYSVOL on the domain controller read - a hint when the policy is linked, because a client that cannot open the `gpt.ini` of a policy in its scope aborts Group Policy processing (Event 1058); a note when it is not. A folder that is there but could not be read is reported as such, not as missing
- Folders in `SYSVOL\Policies` named for no policy object the account can read - left over from a deleted policy, or a policy hidden from the account by its security filtering (note)
- A policy that applies nowhere - nothing links it, or its links are disabled - while a broad group (Authenticated Users, Domain Users, Everyone, ...) may change it on the directory object or in its SYSVOL folder: the `oneLinkAway` row (hint) says that a single link applies whatever it then holds

**Security Impact**: GPO modification enables code execution on all computers where the GPO is linked. An attacker with GPO write access can deploy malware domain-wide.

**Usage**:
```powershell
# Show non-privileged accounts with GPO modification rights (default)
Get-GPOPermissions

# Include privileged accounts (Domain Admins, Group Policy Creator Owners, etc.)
Get-GPOPermissions -IncludePrivileged
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludePrivileged` | Include privileged accounts in output (shown in yellow) |

**Output Properties**:
- `VulnerableIdentity`: Account(s) with dangerous GPO permissions
- `Scope`: GPO scope (DOMAIN-WIDE, Linked to X OU(s), or NOT LINKED)
- `LinkedOUs`: Full DN of OUs where the GPO is linked
- `AffectedComputers`: Number of computers affected by this GPO

---

### Get-GPOLocalGroupMembership

**Purpose**: Analyzes GPO-defined local group memberships.

**What it checks**:
- Local Administrators group additions via GPO
- Remote Desktop Users additions
- Other privileged local group modifications
- Every member added, by SID: a broad group (Everyone, Domain Users, ...) raises the assignment; a Tier 0 principal holds the group's rights already and is not marked; every other principal - a user, a group of the domain, an operator group - is marked in the colour of the target group (red for Administrators and the operator groups, yellow for Backup Operators, Remote Desktop Users and the like). An assignment that adds Tier 0 principals only is a *Note*, unless it empties the group first

**Security Impact**: GPOs adding users to local admin groups can provide persistent privileged access across many systems.

**Usage**:
```powershell
Get-GPOLocalGroupMembership
```

---

### Get-GPOScheduledTasks

**Purpose**: Rates the scheduled tasks Group Policy Preferences deploy (`ScheduledTasks.xml` in SYSVOL) by what each task starts and as which account.

**What it checks**:
- Every Exec action of a task - regular and immediate tasks, both file formats - and the account it runs as, from the Preferences item or from the task's own principal
- Tasks running as SYSTEM, LOCAL SERVICE, NETWORK SERVICE or a privileged account
- Programs started from a directory in which every user may change files (`C:\Temp`, `C:\Users\Public`, ...) or add files (`C:\ProgramData`, `C:\Windows\Temp`, ...) by Windows default
- UNC paths: whoever can write the share, or answer for its server name, controls what the task runs. Who may write the share is not read - a task's command line names shares as programs, arguments, copy sources and wildcards, and the read broke on too many of them - so a task on a share is a hint, unless its account makes it a finding
- A task that runs as a Tier 0 account is a finding. SYSTEM and the operator accounts make a task a finding where its program lies in a directory every user may write by Windows default; otherwise they make it a hint
- `cmd.exe /c` lines with an unquoted program path containing a space, which cmd.exe splits at the first space. The program field of a task is not affected: the Task Scheduler quotes it itself
- Tasks of policies that are not linked or not enabled are held back and summarized, and so are task items with the action Delete: they remove the task they name, nothing runs

A password stored in a task (`cpassword`) is reported by `Get-CredentialExposure`.

**Console colours**: The program path (`Command`) is yellow on every task that runs, and red where a directory every user may write by Windows default makes the task a finding; it carries the card of a task that runs from a share as SYSTEM, an operator or a Tier 0 account. The account (`RunAs`) is red for a Tier 0 account, and yellow for an operator account and for SYSTEM, LOCAL SERVICE and NETWORK SERVICE. Every task rated a finding shows one of the two in red, so the headline is red only above a red row. The full sentence (`RiskReason`) is on the HTML card only.

**Security Impact**: A task runs on every computer the policy reaches. Whoever can replace what a SYSTEM task starts runs code as SYSTEM on all of them; for a task that runs as a privileged domain account, as that account - for a domain administrator, that is the domain.

**Usage**:
```powershell
Get-GPOScheduledTasks

# Also list the tasks of policies that are not linked or not enabled
Get-GPOScheduledTasks -IncludeInactive
```

**Parameters**:

| Parameter | Description |
|-----------|-------------|
| `-IncludeInactive` | Also list the tasks of policies that are not linked or not enabled |

---

### Get-GPOScriptPaths

**Purpose**: Detects Logon/Logoff/Startup/Shutdown scripts distributed via Group Policy.

**What it checks**:
- Startup/Shutdown scripts (run as SYSTEM in Machine context)
- Logon/Logoff scripts (run in user context)
- Scripts loaded from UNC paths (credential exposure risk)
- PowerShell scripts configured via psscripts.ini
- Who may write a script that runs from outside the policy's own folder - NETLOGON, SYSVOL outside a GPO folder, or a file share: the NTFS permissions of the file and of its folder are read over SMB from the domain's own name and enabled computers of the domain - by the DNS name the directory records, never by a short name, and never from an address or a host the domain does not know. SYSVOL and NETLOGON under the domain's own name are read on the domain controller the session uses: `\\<domain>` itself asks for a Kerberos ticket to `cifs/<domain>`, which no account carries. A principal beyond the administrators that may write them makes the script a finding and is named in `scriptPathPermissions`; a script in NETLOGON only administrators may change is a note, one on another server a hint (its administrators decide what runs). The share permissions are not read, and a local path is not read over the network.

**Security Impact**: GPO scripts execute automatically on target systems. Startup and Shutdown scripts run as SYSTEM, making them high-value targets for privilege escalation. Scripts loaded from UNC paths expose machine credentials on the network.

**Usage**:
```powershell
Get-GPOScriptPaths

# Make no SMB connection to the hosts a script path names
Get-GPOScriptPaths -OPSEC
```

**Output Properties**:
- `GPOName`: Name of the GPO deploying the script
- `GPOGUID`: The GPO's folder name under SYSVOL
- `GPOPath`: Full path to that folder
- `SourceFile`: The `scripts.ini` / `psscripts.ini` the entry was parsed from, relative to
  the GPO folder - not to be confused with `ScriptPath` below, which is the script that
  .ini points at
- `ScriptType`: Startup, Shutdown, Logon, or Logoff
- `ScriptPath`: Path to the script
- `Parameters`: Script parameters (if configured)
- `ExecutionContext`: SYSTEM or User
- `ScriptLanguage`: PowerShell, Batch, VBScript, etc.
- `HasUNCPath`: Whether the script is loaded from a network share
- `scriptRisk`: What the script's location is worth - the policy store, NETLOGON, a share or a local path, with who may change it or why that was not checked
- `scriptPathPermissions`: One `path: Identity (Rights)` row per principal beyond the administrators that may write the script or its folder (only present when there is one)

---

### Get-GPORegistrySettings

**Purpose**: Reports registry values a Group Policy deploys in a state that enables an attack.

**What it checks**:
- Every registry value a policy deploys, from all three places a policy writes one: Administrative Templates (`Registry.pol`), Group Policy Preferences (`Registry.xml`) and Security Options (`GptTmpl.inf`, section `[Registry Values]`)
- Against a fixed list of known dangerous settings (`adPEAS-RegistryKeys.ps1`): credential theft (WDigest, LM/NTLMv1, LM hashes, more cached logons than the default of 10, logon credentials delegated by CredSSP to any server), privilege escalation (AlwaysInstallElevated in both hives, UAC), Kerberos and certificates (Zerologon allow-list, ESC10, DES or RC4 among the allowed encryption types), switched-off defenses (Defender, LSA protection, Credential Guard, firewall, script block logging), remote access (RDP, WinRM unencrypted or with Basic authentication, unsolicited Remote Assistance), SMB, LDAP client signing, LLMNR and legacy protocols, updates over HTTP, and Office macros enabled without a prompt (every Office version and application)
- Only values set to the dangerous state. A hardening value that is missing is not a finding: a policy that does not configure a setting does not weaken it. A Preferences item that deletes its value or is switched off deploys nothing

**What it does not judge**: every other value - the settings of applications, and Windows settings without a rule. The check counts them ("N further registry value(s) from M policies are not on the list of this check - not judged"), and its all-clear reads "No known vulnerable registry setting is deployed via GPO". Values another check judges are not counted: Point and Print (`Get-GPOPointAndPrint`), SMB signing (`Get-SMBSigningStatus`), LDAP signing and channel binding (`Get-LDAPConfiguration`), LAPS (`Get-LAPSConfiguration`), and string values named like a password (`Get-CredentialExposure`). `-IncludeUnknown` lists them, one object per policy file with a row per value - read them with someone who knows the applications. A full scan counts them only; run the check on its own to list them.

**Usage**:
```powershell
Get-GPORegistrySettings

# Also list the settings of policies that are not linked or not enabled
Get-GPORegistrySettings -IncludeInactive

# Also list every deployed value the check does not judge, per policy file
Get-GPORegistrySettings -IncludeUnknown
```

**Output Properties**:
- `GPOName`, `GPOGUID`, `GPOPath`, `SourceFile`: the policy and the file inside it
- `RegistryKey`: hive, key and value name
- `ConfiguredValue`: the value the policy writes
- `VulnerabilityName`, `RiskReason`: what the value enables
- With `-IncludeUnknown`, per policy file: `RegistryValues`, one row `hive\key\value = data` per value not judged, without a severity. Long strings are cut at 100 characters; a binary value of `Registry.pol` reads `(binary)`

---

## Computer Module

Analyzes computer account security.

### Get-LAPSConfiguration

**Purpose**: Checks LAPS deployment status across the domain.

**What it checks**:
- Computers without LAPS configured
- LAPS schema presence vs. actual deployment

**Security Impact**: Computers without LAPS use shared or predictable local admin passwords, enabling pass-the-hash attacks for lateral movement.

**Usage**:
```powershell
Get-LAPSConfiguration
```

---

### Get-OutdatedComputers

**Purpose**: Finds computers running outdated operating systems.

**What it checks**:
Uses a central lifecycle database (`adPEAS-SoftwareLifecycle.ps1`) with EOL dates from Microsoft. Detection is dynamic — as dates pass, systems are automatically flagged.

| Operating System | EOL Date | Status (as of 2026) |
|-----------------|----------|---------------------|
| Windows XP | 2014-04-08 | EOL |
| Windows Vista | 2017-04-11 | EOL |
| Windows 7 | 2023-01-10 | EOL (incl. ESU) |
| Windows 8 / 8.1 | 2016/2023 | EOL |
| Windows 10 | 2025-10-14 | EOL |
| Windows Server 2003 | 2015-07-14 | EOL |
| Windows Server 2008 (R2) | 2023-01-10 | EOL (incl. ESU) |
| Windows Server 2012 (R2) | 2026-10-13 | EOL (incl. ESU) |
| Windows Server 2016 | 2027-01-12 | Approaching EOL |

**Security Impact**: End-of-life systems no longer receive security patches and are vulnerable to known exploits.

**Usage**:
```powershell
Get-OutdatedComputers
```

---

### Get-InfrastructureServers

**Purpose**: Identifies critical infrastructure servers.

**What it checks**:
- Domain Controllers
- Exchange Servers
- MSSQL Servers (via `MSSQLSvc/` SPN)
- SCCM/ConfigMgr Servers
- SCOM Servers
- Entra ID Connect (Azure AD Connect)

**Security Impact**: Informational - identifies high-value targets for attackers. Compromise of these systems often leads to domain compromise.

**Usage**:
```powershell
Get-InfrastructureServers
```

---

### Get-NonDefaultComputerOwners

**Purpose**: Finds computers owned by non-privileged users, and explicit permissions on computer objects held outside Tier-0.

**What it checks**:
- Computer object owner attribute
- Computers owned by regular users instead of Domain Admins
- Entries written on the computer object itself (not inherited) that give a principal outside Tier-0 full control, a generic write, a write on every attribute or on the DACL, the right to take ownership, all extended rights, the password reset right, or a write on `msDS-AllowedToActOnBehalfOfOtherIdentity`, `msDS-KeyCredentialLink`, `servicePrincipalName` or `dNSHostName`
- The entries the computer class writes for its creator, the owner, SELF and the operators are not reported; inherited entries are reported by the OU permission check where the delegation is defined

**Security Impact**: Computer owners can modify the object, potentially adding themselves to `msDS-AllowedToActOnBehalfOfOtherIdentity` and enabling RBCD attacks. An explicit write on that attribute or on `msDS-KeyCredentialLink`, a password reset right or all extended rights (which include reading the LAPS password) lead to administrative access to the computer the same way.

**Usage**:
```powershell
Get-NonDefaultComputerOwners
```

---

### Get-ComputerPasswordAge

**Purpose**: Finds active computers whose machine account password is not rotated.

**What it checks**:
- Enabled computers that logged on within the last 30 days (`-ActiveDays`) and whose machine account password is 90 days old or older (`-PasswordAgeDays`)
- A domain member and a Domain Controller change it every 30 days by default; one that does not has the change switched off (`DisablePasswordChange`), a non-Windows join tool that does not rotate, or is a clone
- Domain Controllers are reported as a finding, other computers as a hint

**Security Impact**: A machine account key that does not change never ages out. Whoever extracted it once can forge service tickets to the host; a Domain Controller's key replicates every password hash of the domain.

**Usage**:
```powershell
Get-ComputerPasswordAge
Get-ComputerPasswordAge -PasswordAgeDays 60 -ActiveDays 14
```

---

### Get-NetworkMap

**Purpose**: Maps the IP subnets the active computers of the domain are in, and the OUs they sit in - which networks hold which systems, without a scan.

**What it does**:
- Takes the enabled computers with a logon in the last 30 days (`lastLogonTimestamp`, `-ActiveDays`). The attribute is replicated with a delay of 9 to 14 days by default, so a shorter window misses computers in use.
- Resolves their DNS name (`dNSHostName`), only below the domain's own DNS name: the computer account may write the attribute, and a name outside the domain is counted instead of looked up.
- Takes the addresses from the AD-integrated DNS zones the names fall in, read over LDAP from the connected domain controller (`Get-DomainDNSZone`, `Get-DomainDNSRecord`) - every address of a name, and no DNS query. A name not found there is resolved by a DNS query to the domain controller (the session's `-DnsServer`, else the domain controller's address) and to no other server.
- Shows one object per /24 subnet: the number of computers, how many of them are domain controllers, servers and clients, the most specific subnet Sites and Services defines for the addresses with its site ("Not in Sites and Services" where none contains them), and the OU or container of each computer as a DN with the number of computers from it. The computers themselves are not listed.
- Lists the subnets Sites and Services defines that hold no active computer, in one object after the /24s: networks the domain knows of and the computers do not show, such as a VPN pool, a DMZ or a floor of appliances. A defined subnet inside one of the /24s is left out, that /24 covers it.
- Counts what it could not map: names outside the domain, computers without a DNS name or without a usable IPv4 address (loopback, APIPA, multicast), and IPv6-only computers. IPv6 is not mapped.

A subnet with domain controllers is a hint - the Tier-0 network - and adds nothing to the risk score.

**Parameters**:
- `-ActiveDays <n>`: how recent the last logon must be (default 30)
- `-ExportTargets <file>`: writes the subnets to the file, one per line in CIDR notation - the /24s, then the defined subnets without an active computer - as the target list of a scanner (`nmap -iL`, or `Get-Content <file> | Invoke-PortScan`); an existing file is overwritten. A full scan writes no file.
- `-OPSEC`: no DNS query; computers the zones do not hold are counted and not mapped

**Usage**:
```powershell
Get-NetworkMap
Get-NetworkMap -ActiveDays 60 -ExportTargets .\subnets.txt
```

---

## Application Module

Analyzes enterprise application infrastructure.

### Get-ExchangeInfrastructure

**Purpose**: Enumerates Exchange Server infrastructure.

**What it checks**:
- Exchange Organization presence (msExchOrganizationContainer)
- Exchange server versions via LDAP attributes and HTTP endpoint probing
- Extended Protection for Authentication (EPA) status on Exchange web endpoints
- Exchange Trusted Subsystem group membership (high-privilege service accounts)
- Exchange Windows Permissions group membership (can have DCSync rights via WriteDacl on domain root)
- Organization Management group membership (full Exchange admin control)

**Security Impact**: Exchange servers often have high privileges in AD. The "Exchange Windows Permissions" group has WriteDacl on the domain root by default, which can be abused for DCSync. "Exchange Trusted Subsystem" members can modify any Exchange object. Outdated Exchange versions have known vulnerabilities (ProxyLogon, ProxyShell). Missing EPA enables NTLM relay attacks against Exchange endpoints.

**Usage**:
```powershell
Get-ExchangeInfrastructure
```

---

### Get-SCCMInfrastructure

**Purpose**: Enumerates SCCM/MECM infrastructure using LDAP queries against Active Directory.

**What it checks**:
- System Management container presence
- SCCM site codes and site hierarchy via `mSSMSSite` AD objects
- Management Points and site type determination (CAS / Primary / Secondary) via `mSSMSManagementPoint` objects with XML capabilities parsing
- SCCM server identification via SPNs (SMS*, SMSSQLBKUP*)
- SCCM client count via CmRcService SPN (compromise blast radius)
- PXE/WDS boot servers (connectionPoint, intellimirrorSCP objects)
- SCCM service accounts
- SCCM-related security groups

**Security Impact**: SCCM can deploy software to all managed systems. A Central Administration Site (CAS) controls the entire hierarchy and is a Tier 0 asset. PXE boot servers can be targeted for credential theft or OS deployment manipulation. The number of SCCM clients indicates the blast radius of a potential compromise.

**Usage**:
```powershell
Get-SCCMInfrastructure
```

---

### Get-SCOMInfrastructure

**Purpose**: Enumerates SCOM infrastructure.

**What it checks**:
- SCOM management servers
- Agent configuration
- RunAs accounts

**Security Impact**: SCOM runs agents on many systems with local admin rights. RunAs accounts are often overly privileged. Compromise enables lateral movement.

**Usage**:
```powershell
Get-SCOMInfrastructure
```

---

## Shares Module

Searches the shares of the domain's computers. **Not part of a default scan** - run it with
`-Module Shares`, or call `Invoke-ShareHunt` directly.

### Invoke-ShareHunt

**Purpose**: Finds the shares this account can read and searches them for credentials.

**Why it is not in a default scan**: it opens an SMB connection to every Windows computer
of the domain and reads files off the shares it finds. That is the loudest thing adPEAS
does, and a monitored network will notice it, so it is a decision for whoever runs the scan
rather than a default. `-OPSEC` skips it entirely.

**What it does**, in four steps, each bounded so a large domain finishes:

1. **The computers**: enabled Windows computers with a logon in the last 30 days
   (`-ActiveDays`), by `dNSHostName` - only a name below the domain's own DNS name, since
   the computer account may write that attribute itself. Or the computers named with
   `-ComputerName`, or anything piped in: a name, a list of them, or the objects a
   `Get-Domain*` function returns, which are read by their `dNSHostName`. A name given that
   way is not checked against the domain's DNS name - the caller named it on purpose. An
   empty pipeline searches nothing and does not fall back to the domain, so
   `Get-DomainComputer -OperatingSystem '*Server 2012*' | Invoke-ShareHunt` in a domain with
   no such computer sweeps nothing rather than everything.
2. **Who answers on port 445**: one sweep with a deadline per *block* of hosts rather than
   per host, so a few hundred dead addresses cost one timeout each block instead of one
   each.
3. **Their shares**, enumerated through `NetShareEnum` at level 1 - the level an ordinary
   account may call - in a runspace pool with one deadline for the whole pass, because a
   host that completes the TCP handshake and then stalls the RPC call would otherwise block
   for tens of seconds. Of those, the shares worth reading: disk shares only, without the
   shares Windows creates for itself (`-IncludeAdmin`) - told by the flag Windows sets on
   them, by name, and by the shape of a drive share - and without SYSVOL and NETLOGON, which
   `Get-CredentialExposure` reads with the policy each file belongs to (`-IncludeSysvol`).
   Each is probed for whether this account can list its root. A **hidden** share is
   searched: a dollar at the end of the name means not browsable, not administrative, and
   `Software$` or `Profiles$` is an ordinary share somebody kept out of the browse list.
4. **The readable shares**, walked breadth-first - the files that carry credentials sit near
   the top of a share - under four limits: depth 10 (`-MaxDepth`), 50000 files
   (`-MaxEntries`), 600 seconds per share (`-ShareTimeoutSeconds`) and 60 minutes for all
   of them together (`-MaxMinutes`). The first two defaults are generous on purpose: a small
   share is far below either, and a file server is the interesting case. Files over 1024 KB
   (`-MaxFileSizeKB`) are counted, not read. Directories named with `-ExcludeFolder` are
   skipped on every share, on top of the Windows directories that are always skipped
   (`Windows`, `WinSxS`, `Program Files`, `Program Files (x86)`, `ProgramData`,
   `$Recycle.Bin`, `System Volume Information`, `Recovery`, `PerfLogs`) - for the directory
   that turns out to be worth nothing and takes the budget anyway. Every candidate file is analysed by the same functions the SYSVOL scan uses, so a
   Group Policy Preferences password, a Winlogon value, an answer file, a VNC password, a
   `net use` line and a password assignment are found the same way here as there.

**What it shows while it runs**: the console carries one progress line through all six
phases - looking for the active computers, checking port 445 (with how many have answered so
far), enumerating shares, probing each share, collecting the files of each share, and
searching each file by name. There is no item threshold on the per-share phases: one share on
an unresponsive host can take as long as thirty on a healthy one, and what the display is for
is saying which host is being waited for. The search is counted over all the shares together,
because what a reader wants there is how much of it is done.

**Exports**: `-ExportShares <file>` writes the readable shares, one UNC path per line, to
work from or to feed another tool. `-ExportFindings <file>` writes the whole result as JSON:
the limits the run used, what it could not reach, every readable share with how far its walk
got, and every finding with its file and its decrypted value. The findings file is written
even when nothing was found - an empty result is a result, and the limits beside it are what
makes it comparable with the next run. **It carries the credentials in clear text**, because
that is what was found; treat it as the finding it is. Inside `Invoke-adPEAS -Outputfile` the
rows reach the ordinary Text, HTML and JSON report as well; the two parameters are what a
standalone call needs.

**`-ShareName`**: searches the shares of that name instead of whatever the computers offer,
and enumerates nothing - it goes straight to `\\<computer>\<name>`. That is shorter, and it
is the one way in where a server refuses `NetShareEnum` (Win32 5) but serves the share
itself, which is a common configuration. A name given there is searched whatever it is, so
`-ShareName C$` needs no `-IncludeAdmin` and `-ShareName SYSVOL` no `-IncludeSysvol`. Names
are literal - there is no listing to match a wildcard against, so give several names.

**`-ListSharesOnly`**: stops after the list of readable shares - no file is read and no
credential is searched for. The first pass over an unknown domain, where the list of shares
this account can reach is the answer to "where would I even look", and it comes back in the
time the sweep and the enumeration take. The report says that nothing was read, so the
absence of credentials is not mistaken for a result.

**What it says about what it did not cover**: every limit reached and everything left out is
counted - computers outside the domain's name or without one, hosts that do not answer,
hosts that did not list their shares and why, administrative and SYSVOL shares, shares it
may list but not read, files it could not read, and files over the size limit. A share whose
walk was stopped carries `notFullySearched` with the reason; a share without that row was
walked to its end. The all-clear is a note, never "secure": a share is read only as far as
this account and the limits allowed.

**Security Impact**: a password in a script or configuration file on a share is readable by
everyone who can read the share - usually far more people than the account it belongs to was
meant for - and unlike SYSVOL nobody reviews who that is.

**Usage**:
```powershell
Invoke-ShareHunt
Invoke-ShareHunt -ComputerName fs01.contoso.com, fs02.contoso.com -MaxDepth 8
Invoke-ShareHunt -ActiveDays 14 -MaxMinutes 20
Invoke-ShareHunt -ListSharesOnly
'fs01.contoso.com' | Invoke-ShareHunt -ListSharesOnly
Get-DomainComputer -OperatingSystem '*Server*' | Invoke-ShareHunt
Invoke-ShareHunt -ComputerName fs01.contoso.com -ShareName Finance
Invoke-ShareHunt -ShareName Finance, 'Profiles$'
Invoke-ShareHunt -ExportShares .\shares.txt -ExportFindings .\shares.json
Invoke-PortScan -Target 10.1.2.0/24 -Port 445 -PassThru | Invoke-ShareHunt
Invoke-ShareHunt -ComputerName fs01.contoso.com -ExcludeFolder Archive, 'Build Output'
Invoke-adPEAS -Module Shares
```

---

## Navigation

- [Previous: Authentication-Methods](03-Authentication-Methods.md)
- [Next: BloodHound-Collector](05-BloodHound-Collector.md)
- [Back to Home](00-Home.md)