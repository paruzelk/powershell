# Система оценки рисков

Документация контекстной системы оценки риска, используемой в HTML-отчётах adPEAS v2.

> **Сопровождение:** все значения модели определяются централизованно:
> - **PowerShell:** `src/modules/Core/adPEAS-ScoringDefinitions.ps1`
> - **JavaScript:** автоматически формируется из PowerShell при сборке через `ConvertTo-ScoringJavaScript`

---

## Обзор

Система оценки adPEAS v2 вычисляет риск с учётом нескольких факторов, а не только названия находки. Это позволяет определять приоритет исправления по реальной эксплуатируемости и последствиям.

### Формула оценки

```
FINAL_SCORE = (BASE × IMPACT × EXPLOITABILITY × SECURITY) + CORRELATION
```

| Компонент | Диапазон | Описание |
|-----------|-------|-------------|
| **BASE** | 0-100 | Исходная серьёзность типа находки |
| **IMPACT** | 1.0-2.0 | Коэффициент привилегий затронутой учётной записи |
| **EXPLOITABILITY** | 0.72-3.64 | Произведение четырёх факторов: возраст пароля, минимальная длина, сложность, шифрование |
| **SECURITY** | 0.003-1.3 | Существующие защитные меры, применяемые перемножением |
| **CORRELATION** | 0-15, or 0-30 for a non-privileged account | Надбавка за несколько находок у одной записи |

**Итоговая оценка ограничивается интервалом 0–100.**

Эти диапазоны следуют из таблиц в
`src/modules/Core/adPEAS-ScoringDefinitions.ps1`, а не задаются отдельными числами:

- **EXPLOITABILITY** перемножает возраст пароля (1.0–1.6), минимальную длину
  (0.8–1.4), сложность (1.0–1.25) и тип шифрования (0.9–1.3). Отсюда нижняя граница
  0.72 и верхняя 3.64: фактор может как увеличивать, так и уменьшать оценку.
  Он применяется только к атакам, требующим подбора пароля (Kerberoast, AS-REP,
  отсутствие предварительной аутентификации).
- **SECURITY** перемножает подходящие меры защиты. Для находки с подбором пароля
  отключённая запись (0.1), требующая смарт-карту (0.15) и состоящая в
  Protected Users (0.2), даёт произведение 0.003. Одно значение
  таблицы больше единицы — `USE_DES_KEY_ONLY` = 1.3, повышающее оценку,
  поскольку DES слабый алгоритм, а не защита. Оно осталось здесь по историческим
  причинам; логичнее отнести его к эксплуатируемости, но перенос изменил бы оценки.
  Поэтому запись и причина её расположения документированы.
- **CORRELATION** добавляет 5 за каждую дополнительную находку (до 15) привилегированной записи
  и 8 (до 30) — непривилегированной: сочетание четырёх проблем у обычной записи
  заслуживает особого внимания, поэтому надбавка выше.

Поскольку компоненты перемножаются, арифметика достигает верхней границы 100 намного
раньше теоретического максимума. Оценка 100 означает «не ниже верхней границы шкалы»,
а не «точно 100».

---

## Базовые оценки по типам находок

Базовый балл представляет собственный риск типа уязвимости. Затем он корректируется с учётом контекста.

### Прямая компрометация (база 80–100)

Такие проблемы могут привести к немедленной компрометации домена.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `dcsync` | 100 | Get-DangerousACLs | DCSync rights - immediate domain compromise |
| `replication rights` | 100 | Get-DangerousACLs | Same as DCSync |
| `esc1` | 90 | Get-ADCSVulnerabilities | ADCS ESC1 - enrollee supplies subject + client auth |
| `esc2` | 80 | Get-ADCSVulnerabilities | ADCS ESC2 - any purpose or SubCA template |
| `esc3` | 75 | Get-ADCSVulnerabilities | ADCS ESC3 - certificate request agent |
| `esc4` | 70 | Get-ADCSVulnerabilities | ADCS ESC4 - dangerous template ACL |
| `esc13` | 70 | Get-ADCSVulnerabilities | ADCS ESC13 - issuance policy linked to AD group |
| `esc6` | 65 | Get-ADCSVulnerabilities | ADCS ESC6 - EDITF_ATTRIBUTESUBJECTALTNAME2 on CA |
| `esc7` | 65 | Get-ADCSVulnerabilities | ADCS ESC7 - dangerous CA permissions |
| `esc8` | 70 | Get-ADCSVulnerabilities | ADCS ESC8 - NTLM relay to web enrollment |
| `esc9` | 60 | Get-ADCSVulnerabilities | ADCS ESC9 - template without security extension |
| `esc10` | 60 | Get-ADCSVulnerabilities | ADCS ESC10 - weak certificate mapping |
| `esc15` | 30 | Get-ADCSVulnerabilities | ADCS ESC15 - schema v1 template with enrollee subject |
| `unconstrained delegation` | 85 | Get-UnconstrainedDelegation | Can capture TGTs |
| `sid history` | 80 | Get-SIDHistoryInjection | SID History injection |

### Раскрытие учётных данных (база 40–60)

Проблемы, раскрывающие учётные данные или разрешающие доступ к ним.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `laps credential` | 55 | Get-LAPSCredentialAccess | LAPS password readable |
| `laps access` | 45 | Get-LAPSPermissions | LAPS password read permissions |
| `laps password` | 55 | Get-LAPSCredentialAccess | LAPS password readable |
| `gpp password` | 50 | Get-CredentialExposure | Group Policy Preferences password |
| `cpassword` | 50 | Get-CredentialExposure | GPP cpassword attribute |
| `cleartext credential` | 50 | Get-CredentialExposure | Cleartext credentials found |
| `plaintext credential` | 50 | Get-CredentialExposure | Plaintext credentials found |
| `credential exposure` | 45 | Get-CredentialExposure | Generic credential exposure |
| `autoadminlogon` | 45 | Get-CredentialExposure | AutoAdminLogon credentials |
| `password in script` | 45 | Get-GPOScheduledTasks | Password in scheduled task script |
| `sensitive information` | 40 | Get-CredentialExposure | Sensitive data exposure |
| `net use` | 40 | Get-CredentialExposure | Net use with credentials |

### Требуется подбор пароля (база 30–50)

Проблемы, требующие автономного подбора пароля.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `kerberoastable` | 35 | Get-KerberoastableAccounts | Kerberoastable service account |
| `kerberoast` | 35 | Get-KerberoastableAccounts | Kerberoastable service account |
| `asrep roast` | 30 | Get-ASREPRoastableAccounts | AS-REP roastable account |
| `as-rep roast` | 30 | Get-ASREPRoastableAccounts | AS-REP roastable account |
| `preauth not required` | 30 | Get-ASREPRoastableAccounts | Pre-authentication disabled |

### Злоупотребление делегированием (база 50–55)

Проблемы настройки делегирования Kerberos.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `rbcd` | 55 | Get-ResourceBasedConstrainedDelegation | Resource-Based Constrained Delegation |
| `resource-based constrained` | 55 | Get-ResourceBasedConstrainedDelegation | RBCD abuse |
| `constrained delegation` | 50 | Get-ConstrainedDelegation | Constrained delegation configured |

### Злоупотребление ACL (база 40–60)

Проблемы, связанные с опасными записями ACL.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `genericall` | 60 | Get-DangerousACLs | Full control over object |
| `writedacl` | 55 | Get-DangerousACLs | Can modify permissions |
| `writeowner` | 55 | Get-DangerousACLs | Can change ownership |
| `genericwrite` | 50 | Get-DangerousACLs | Can write to object |
| `password reset` | 50 | Get-PasswordResetRights | Can reset passwords |
| `reset password` | 50 | Get-PasswordResetRights | Can reset passwords |
| `gpo permission` | 50 | Get-GPOPermissions | Can modify GPOs |
| `dangerous permission` | 45 | Get-DangerousACLs | Other dangerous ACL |
| `laps permission` | 45 | Get-LAPSPermissions | Can read LAPS passwords |
| `gpo link` | 45 | Get-GPOPermissions | Can link GPOs |
| `ou permission` | 40 | Get-DangerousOUPermissions | Dangerous OU permissions |

### Слабые настройки (база 25–45)

Проблемы, связанные с небезопасной конфигурацией.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `local admin` | 45 | Get-GPOLocalGroupMembership | Added to local admins via GPO |
| `computer owner` | 40 | Get-NonDefaultComputerOwners | Non-default computer owner |
| `local group` | 40 | Get-GPOLocalGroupMembership | GPO local group membership |
| `password not required` | 35 | Get-PasswordNotRequired | PASSWD_NOTREQD flag |
| `add computer` | 35 | Get-AddComputerRights | Can add computers to domain |
| `laps not configured` | 35 | Get-LAPSConfiguration | LAPS not deployed |
| `reversible encryption` | 30 | Get-AdminReversibleEncryption | Reversible encryption enabled |
| `inactive admin` | 30 | Get-InactiveAdminAccounts | Inactive admin account |
| `orphaned admin` | 30 | Get-InactiveAdminAccounts | Orphaned admin account |
| `smb signing` | 30 | Get-SMBSigningStatus | SMB signing not required |
| `machineaccountquota` | 15 | Get-AddComputerRights | MachineAccountQuota > 0 |
| `kds root key` | 30 | Get-ManagedServiceAccountSecurity | KDS root key issues |
| `password never expires` | 25 | Get-AdminPasswordNeverExpires | Password never expires |
| `ldap signing` | 25 | Get-LDAPConfiguration | LDAP signing not required |
| `channel binding` | 25 | Get-LDAPConfiguration | Channel binding not required |

### Управляемые служебные записи (база 20–25)

Риски настройки служебных учётных записей.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `gmsa password readable` | 55 | Get-ManagedServiceAccountSecurity | gMSA password retrievable |
| `managed service account` | 25 | Get-ManagedServiceAccountSecurity | MSA configuration issue |
| `smsa` | 20 | Get-ManagedServiceAccountSecurity | sMSA configuration issue |

### Инфраструктура (база 30–45)

Проблемы компонентов инфраструктуры.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `exchange` | 45 | Get-ExchangeInfrastructure | Exchange infrastructure finding |
| `unsupported os` | 40 | Get-OutdatedComputers | Unsupported operating system |
| `scom` | 35 | Get-SCOMInfrastructure | SCOM infrastructure |
| `sccm site hierarchy` | 30 | Get-SCCMInfrastructure | SCCM multi-site hierarchy |
| `sccm pxe` | 25 | Get-SCCMInfrastructure | PXE boot server exposure |
| `sccm client` | 20 | Get-SCCMInfrastructure | SCCM client deployment scope |
| `aging os` | 15 | Get-OutdatedComputers | Aging operating system (nearing EOL) |
| `unix password` | 30 | Get-UnixPasswordAccounts | Unix password attributes |
| `unixuserpwd` | 30 | Get-UnixPasswordAccounts | unixUserPassword attribute |

### Конфигурация LAPS (база 20–35)

Проблемы внедрения LAPS.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `laps not configured` | 35 | Get-LAPSConfiguration | LAPS missing |
| `laps` | 20 | Get-LAPSConfiguration | LAPS informational |

### Информационные сведения (база 10–15)

Информационные сообщения низкой серьёзности.

| Ключевое слово | Базовый балл | Модуль проверки | Описание |
|---------|------------|--------------|-------------|
| `privileged group` | 15 | Get-PrivilegedGroupMembers | Privileged group membership |
| `trust` | 15 | Get-DomainTrusts | Domain trust |
| `group member` | 10 | Get-PrivilegedGroupMembers | Group membership info |
| `protected users` | 10 | Get-ProtectedUsersStatus | Protected Users status |
| `password policy` | 10 | Get-DomainPasswordPolicy | Password policy info |
| `domain controller` | 10 | Get-InfrastructureServers | Domain controller info |
| `infrastructure server` | 10 | Get-InfrastructureServers | Infrastructure server info |

### Резервные оценки

Если ключевое слово не найдено, используется значение по категории серьёзности:

| Категория | Резервный балл |
|----------------|----------------|
| `finding` | 35 |
| `hint` | 15 |
| `note` | 0 |
| `secure` | 0 |

---

## Коэффициенты влияния (уровень записи)

Коэффициент влияния корректирует базовую оценку в зависимости от привилегий затронутой записи.

### Модель уровней Microsoft

adPEAS использует [модель привилегированного доступа Microsoft](https://docs.microsoft.com/en-us/security/privileged-access-workstations/) для определения уровня:

| Уровень | Коэффициент | Шаблон SID | Группы | Область |
|------|------------|-------------|--------|-------|
| **Tier 0** | ×2.0 | `-512`, `-519`, `-518` | Domain Admins, Enterprise Admins, Schema Admins | Контроллеры домена |
| **Tier 1** | ×1.5 | `-548`, `-549`, `-551`, `-550` | Account Operators, Server Operators, Backup Operators, Print Operators | Серверы |
| **Tier 2** | ×1.2 | Other privileged | Прочие административные группы | Рабочие станции |
| **None** | ×1.0 | Standard | Обычные учётные записи | — |

### Пример расчёта

```
Kerberoastable Domain Admin:
  Base: 35 (kerberoastable)
  × Impact: 2.0 (Tier 0 - Domain Admin)
  = 70 (before other modifiers)

Kerberoastable Standard User:
  Base: 35 (kerberoastable)
  × Impact: 1.0 (None)
  = 35 (before other modifiers)
```

---

## Коэффициенты эксплуатируемости

Этот коэффициент зависит от того, насколько легко воспользоваться уязвимостью.

### Возраст пароля (относительно политики)

Возраст оценивается **относительно maxPwdAge доменной политики**, а не по абсолютному числу дней.

| Кратность политике | Коэффициент | Описание |
|------------------|----------|-------------|
| ≥10× maxPwdAge | ×1.6 | Очень старый пароль |
| ≥5× maxPwdAge | ×1.4 | Значительно устаревший пароль |
| ≥3× maxPwdAge | ×1.3 | Старый пароль |
| ≥2× maxPwdAge | ×1.2 | Умеренно старый пароль |
| ≥1× maxPwdAge | ×1.1 | Превышен предел политики |
| <1× maxPwdAge | ×1.0 | В пределах политики |

**Пример:** если maxPwdAge = 90 дней:
- Пароль старше на 900 дней → 10× политики → множитель ×1.6.
- Пароль старше на 180 дней → 2× политики → множитель ×1.2.
- Пароль старше на 45 дней → 0.5× политики → множитель ×1.0.

### Надёжность парольной политики

Политика паролей домена влияет на баллы атак, требующих подбора.

#### Минимальная длина пароля

| Минимальная длина | Коэффициент | Описание |
|------------|----------|-------------|
| Меньше 8 символов | ×1.4 | Очень слабый, легко подобрать |
| 8–11 символов | ×1.2 | Слабый |
| 12–15 символов | ×1.0 | Стандартный |
| От 16 символов | ×0.8 | Надёжный, подобрать труднее |

#### Сложность пароля

| Сложность | Коэффициент | Описание |
|------------|----------|-------------|
| Отключена | ×1.25 | Вероятны слабые пароли |
| Включена | ×1.0 | Стандартное требование сложности |

**Примечание:** сложность читается из атрибута `pwdProperties` (бит 0 = DOMAIN_PASSWORD_COMPLEX).

### Типы шифрования (атаки на Kerberos)

| Шифрование | Коэффициент | Описание |
|------------|----------|-------------|
| Только RC4 (etype 23) | ×1.3 | Быстрый подбор |
| AES128 (etype 17) | ×1.0 | Стандарт |
| AES256 (etype 18) | ×0.9 | Подбирать медленнее |

---

## Коэффициенты защиты (смягчающие факторы)

Когда действуют меры защиты, коэффициенты **уменьшают** оценку риска.

### Флаги UAC

| Флаг | Коэффициент | Применение | Описание |
|------|----------|------------|-------------|
| `ACCOUNTDISABLE` | ×0.1 | Все находки | Учётная запись отключена |
| `SMARTCARD_REQUIRED` | ×0.15 | Атаки с подбором | Пароль случайный или неизвестный |
| `USE_DES_KEY_ONLY` | ×1.3 | Атаки Kerberos | Слабое шифрование (повышает риск) |

Не применяются:

- **Заблокированная запись или истёкший пароль.** Контроллер домена вычисляет
  `LOCKOUT` и `PASSWORD_EXPIRED` в `msDS-User-Account-Control-Computed`, но не сохраняет
  их в `userAccountControl`, откуда отчёт читает флаги.
- **`NOT_DELEGATED`** («учётная запись чувствительная, делегирование запрещено»): защищает
  от делегирования этой записи другим субъектом, но ничего не говорит о делегировании,
  которое сама запись выполняет; а проверка делегирования касается именно последнего.
  Множитель (×0.3) остаётся в таблице для будущей версии, где измеряется защищённость
  записей, от имени которых стоило бы представляться.

### Группа Protected Users

| Состояние | Коэффициент | Описание |
|--------|----------|-------------|
| Участник Protected Users | ×0.2 | Усиленная защита Kerberos |
| Не участник | ×1.0 | Дополнительной защиты нет |

Членство в Protected Users определяется по:
1. SID с окончанием `-525` в `memberOf`.
2. Флагу `isProtectedUser` в контексте расчёта.

### Порядок применения коэффициентов

```javascript
// Cracking attacks: Kerberoast, AS-REP Roast
if (isCrackingAttack && hasSmartcardRequired) {
    modifier *= 0.15;  // Password is random, can't crack
}

// All attacks: Account disabled
if (hasAccountDisable) {
    modifier *= 0.1;   // Account can't be used
}
```

---

## Надбавка за корреляцию находок

Корреляция повышает оценку, когда одна запись фигурирует в нескольких опасных находках. **Для неадминистраторов надбавки выше**, так как сочетания проблем показывают возможный путь повышения привилегий.

### Обычная корреляция (привилегированные записи)

```javascript
correlationBonus = (numberOfFindings - 1) * 5
// Capped at 15 points
```

| Количество находок | Надбавка |
|----------|-------|
| 1 находка | +0 |
| 2 находки | +5 |
| 3 находки | +10 |
| 4 и более | +15 (максимум) |

### Усиленная корреляция (неадминистративные записи)

**Причина:** три и более находки у неадминистративного пользователя часто означают возможную цепочку атаки (например, User → чтение LAPS → компьютер → gMSA → DCSync). Такие записи требуют более пристального внимания.

```javascript
// Non-admin accounts with 3+ findings get enhanced scoring
if (isNonAdmin && findingCount >= 3) {
    correlationBonus = (numberOfFindings - 1) * 8
    // Capped at 30 points
}
```

| Количество находок | Надбавка без админправ | Обычная надбавка |
|----------|-----------------|----------------|
| 1 находка | +0 | +0 |
| 2 находки | +8 | +5 |
| 3 находки | +16 | +10 |
| 4 находки | +24 | +15 (максимум) |
| 5 и более | +30 (максимум) | +15 (максимум) |

### Значения параметров

| Параметр | Обычные записи | Без прав администратора |
|-----------|----------|-----------|
| Баллов за находку | 5 | 8 |
| Максимальная надбавка | 15 | 30 |
| Порог | 2 | 3 |

### Пример: обнаружение цепочки атаки

Неадминистративный пользователь `john.doe` обнаружен в:
1. **Правах чтения LAPS** на OU=Servers.
2. **Владении компьютером** SRV-SQL01.
3. **Чтении пароля gMSA** svc_backup$.
4. *(svc_backup$ имеет право DCSync)*.

Анализ:
- Учётная запись не имеет админправ (adminTier = 'none').
- Встречается в трёх находках → усиленная корреляция.
- Надбавка: (3-1) × 8 = **+16 баллов**.

Повышенный балл отражает возможную цепочку: `john.doe` → LAPS/владелец → компьютер → gMSA → DCSync.

### Опасные сочетания

Некоторые сочетания находок всегда получают максимальную надбавку:

| Сочетание | Надбавка (администратор) | Надбавка (неадминистратор) |
|-------------|---------------|-------------------|
| DCSync + Kerberoast/ASREP | +15 | +30 |
| Delegation + Kerberoast | +10 | +16 |

---

## Полные примеры расчёта

### Пример 1: опасный Kerberoast у Domain Admin

**Находка:** Domain Admin с SPN для Kerberoast, старым паролем и только RC4.

| Компонент | Значение | Расчёт |
|-----------|-------|-------------|
| Базовый балл | 35 | Kerberoastable |
| Влияние | ×2.0 | Tier 0 (Domain Admin) |
| Возраст пароля | ×1.4 | 5× maxPwdAge |
| Шифрование | ×1.3 | Только RC4 |
| Длина по политике | ×1.2 | Минимум 8 символов |
| Защита | ×1.0 | Нет смягчающих факторов |
| Корреляция | +10 | 3 находки |

**Итог:** min(max((35 × 2.0 × 1.4 × 1.3 × 1.2 × 1.0) + 10, 0), 100) = **100** (верхняя граница).

### Пример 2: менее опасный Kerberoast с защитой

**Находка:** обычный пользователь, возможен Kerberoast, требуется смарт-карта, состоит в Protected Users.

| Компонент | Значение | Расчёт |
|-----------|-------|-------------|
| Базовый балл | 35 | Kerberoastable |
| Влияние | ×1.0 | None (обычный пользователь) |
| Эксплуатируемость | ×1.0 | Недавно заданный пароль |
| Защита (смарт-карта) | ×0.15 | Случайный пароль |
| Защита (Protected Users) | ×0.2 | Участник Protected Users |
| Корреляция | +0 | 1 находка |

**Итог:** (35 × 1.0 × 1.0 × 0.15 × 0.2) + 0 = **1** (очень низкий риск).

### Пример 3: права DCSync

**Находка:** пользователь без админправ с DCSync.

| Компонент | Значение | Расчёт |
|-----------|-------|-------------|
| Базовый балл | 100 | DCSync |
| Влияние | ×1.0 | Обычный пользователь (неважно: DCSync означает захват домена) |
| Эксплуатируемость | ×1.0 | Неприменимо |
| Защита | ×1.0 | Нет смягчающих факторов |
| Корреляция | +0 | 1 находка |

**Итог:** 100 × 1.0 × 1.0 × 1.0 + 0 = **100**.

---

## Детали реализации

### Сбор контекста (PowerShell)

Контекст оценки формируется функцией `Build-ScoringContext` в `Export-HTMLReport.ps1`:

```powershell
$scoringContext = @{
    accounts = @{}           # Account info by sAMAccountName
    findingContext = @{}     # Finding metadata
    correlations = @{}       # Account appearance counts
    domainInfo = @{
        passwordPolicy = $null
        maxPwdAgeDays = 0
        minPwdLength = 0
        complexityEnabled = $true
        krbtgtLastReset = $null
    }
}
```

### Расчёт оценки (JavaScript)

Расчёт выполняется на стороне клиента в HTML-отчёте:

```javascript
function calculateFindingScore(card) {
    const baseScore = getBaseScore(title);
    const impactMod = impactMultipliers[accountInfo.adminTier] || 1.0;
    const exploitMod = getExploitabilityModifier(accountInfo, title);
    const securityMod = getSecurityModifier(accountInfo, title);
    const correlationBonus = getCorrelationBonus(accountInfo);

    let finalScore = Math.round(baseScore * impactMod * exploitMod * securityMod) + correlationBonus;
    return Math.min(Math.max(finalScore, 0), 100);
}
```

### Отображение оценки

Риски выводятся как цветные индикаторы:

| Баллы | Цвет | Класс CSS |
|-------------|-------|-----------|
| 80–100 | Красный | `score-critical` |
| 60–79 | Оранжевый | `score-high` |
| 40–59 | Жёлтый | `score-medium` |
| 20–39 | Синий | `score-low` |
| 0–19 | Серый | `score-info` |

---

## Настройка модели

Все значения оценки централизованно находятся в `src/modules/Core/adPEAS-ScoringDefinitions.ps1`.

### Добавление базовых оценок

Редактируйте хеш-таблицу `$Script:FindingBaseScores`:

```powershell
$Script:FindingBaseScores = @{
    # ... existing scores ...
    'new finding keyword'  = 45    # Add your keyword (lowercase)
}
```

### Настройка коэффициентов

Редактируйте соответствующие хеш-таблицы:

```powershell
# Коэффициенты влияния (модель уровней Microsoft)
$Script:ImpactMultipliers = @{
    'tier0' = 2.0    # Domain/Enterprise/Schema Admins (Domain Controllers)
    'tier1' = 1.5    # Operators (Servers)
    'tier2' = 1.2    # Other privileged (Workstations)
    'none'  = 1.0    # Standard accounts
}

# Коэффициенты защиты
$Script:SecurityModifiers = @{
    'ACCOUNTDISABLE'      = 0.1
    'SMARTCARD_REQUIRED'  = 0.15
    # ...
}
```


## Ограничения

## Limitations

1. **Оценка возраста пароля:** вычисляется по `pwdLastSet` и не обязательно отражает фактическую надёжность пароля.

2. **Типы шифрования:** `msDS-SupportedEncryptionTypes` не всегда соответствует реально согласованному шифрованию.

3. **Определение Protected Users:** требует правильного сопоставления SID; вложенное членство учитывается не полностью.

4. **Наследование политик:** детальные политики паролей (PSO) пока не оцениваются — используется только доменная политика по умолчанию.

---

## Источники

- [Microsoft: группа Protected Users](https://docs.microsoft.com/en-us/windows-server/security/credentials-protection-and-management/protected-users-security-group)
- [Microsoft: типы шифрования Kerberos](https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/network-security-configure-encryption-types-allowed-for-kerberos)
- [SpecterOps: Kerberoasting](https://posts.specterops.io/kerberoasting-revisited-d434351bd4d1)
- [HarmJ0y: делегирование Kerberos](https://blog.harmj0y.net/activedirectory/s4u2pwnage/)

---

## Навигация

- [Назад: архитектура](09-Architecture.md)
- [Далее: диагностика](11-Troubleshooting.md)
- [На главную](00-Home.md)