# Сборщик BloodHound CE

Экспорт данных Active Directory в совместимом с
**BloodHound Community Edition (CE)** формате.
Сбор следует выполнять только в домене, где вы
уполномочены проводить аудит.

## Назначение и возможности

Функция `Invoke-adPEASCollector` собирает объекты AD
и экспортирует JSON для анализа путей атак в BloodHound,
не требуя установки SharpHound.

- Реализация на PowerShell без внешних модулей.
- Выход в формате **BloodHound CE v6 JSON**.
- Метод `DCOnly`: только LDAP, **без SMB/RPC
  подключений к рядовым компьютерам**.
- Поддержка рёбер ACL (`Owns`, `GenericAll`,
  `WriteDacl`, DCSync и других).
- Автоматическая упаковка в ZIP.

## Быстрый запуск

~~~powershell
Import-Module .\adPEAS.ps1 -Force
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false

Invoke-adPEASCollector -CollectionMethod DCOnly -OutputPath '.\Reports\bloodhound.zip'
Disconnect-adPEAS
~~~

Без явного `-OutputPath` имя создаётся по шаблону
`<timestamp>_EXAMPLE.LOCAL_BloodHound.zip`
в текущем каталоге.

## Синтаксис и параметры

~~~powershell
Invoke-adPEASCollector [-Domain <String>] [-Server <String>] `
    [-Credential <PSCredential>] [-OutputPath <String>] `
    [-CollectionMethod <DCOnly|ACL|ObjectProps|Trusts|Container|CertServices>] `
    [-NoZip] [-PrettyPrint]
~~~

| Параметр | Значение по умолчанию | Назначение |
|---|---|---|
| `-OutputPath` | Текущий каталог | Путь к ZIP или каталогу файлов. |
| `-CollectionMethod` | `DCOnly` | Выбор подмножества данных. |
| `-NoZip` | выключен | Сохранить JSON без ZIP. |
| `-PrettyPrint` | выключен | Форматировать JSON с отступами. |
| `-Domain` | Домен текущей сессии | FQDN домена. |
| `-Server` | DC текущей сессии | Указать контроллер домена. |
| `-Credential` | Данные текущей сессии | Альтернативные права для чтения. |

### Доступные методы сбора

| Метод | Данные |
|---|---|
| `DCOnly` | Пользователи, группы, компьютеры, домены, OU, контейнеры, GPO, AD CS и ACL; максимально полный LDAP-сбор. |
| `ObjectProps` | Атрибуты пользователей, групп и компьютеров; без ACL/AD CS. |
| `ACL` | Объекты AD и права ACL на пользователях, группах, компьютерах, OU, GPO и объектах AD CS. |
| `Trusts` | Домены и доверительные отношения. |
| `Container` | Структура OU, контейнеров и GPO; без ACL. |
| `CertServices` | Шаблоны, Enterprise/Root/AIA CA, NTAuth, issuance policies и ACL. |

`DCOnly` концептуально соответствует SharpHound
`--collectionmethods DCOnly`, но реализован в adPEAS.

## Примеры

~~~powershell
# По умолчанию — текущая директория
Invoke-adPEASCollector

# Каталог или конкретный ZIP
Invoke-adPEASCollector -OutputPath 'C:\BloodHound\'
Invoke-adPEASCollector -OutputPath 'C:\BloodHound\domain_data.zip'

# Вывести отдельные JSON без ZIP
Invoke-adPEASCollector -NoZip -OutputPath 'C:\BloodHound\json\'

# Читаемый JSON
Invoke-adPEASCollector -PrettyPrint -NoZip

# Указанная учётная запись
Invoke-adPEASCollector -Domain 'example.local' -Credential (Get-Credential)

# Упрощённые сборы
Invoke-adPEASCollector -CollectionMethod ObjectProps
Invoke-adPEASCollector -CollectionMethod ACL
Invoke-adPEASCollector -CollectionMethod Trusts
Invoke-adPEASCollector -CollectionMethod Container
Invoke-adPEASCollector -CollectionMethod CertServices
~~~

## Какие файлы создаются

| Файл | Содержимое |
|---|---|
| `*_users.json` | Пользователи, SPN, делегирование, свойства |
| `*_groups.json` | Группы, участники и ACE |
| `*_computers.json` | Компьютеры, ОС, делегирование |
| `*_domains.json` | Домен, доверия, функциональный уровень |
| `*_ous.json` | Организационные единицы и ссылки GPO |
| `*_containers.json` | Объекты-контейнеры |
| `*_gpos.json` | Групповые политики |
| `*_certtemplates.json` | Шаблоны и разрешения выпуска |
| `*_enterprisecas.json` | Корпоративные УЦ и шаблоны |
| `*_rootcas.json` | Корневые УЦ из Configuration NC |
| `*_aiacas.json` | AIA CA |
| `*_ntauthstores.json` | Хранилище NTAuth для доменной аутентификации |
| `*_issuancepolicies.json` | Политики выдачи и привязки OID к группам (ESC13) |

### Структура BloodHound CE JSON v6

Ниже — сокращённый пример структуры. Имена полей
остаются на английском; **переводить ключи JSON нельзя**.

~~~json
{
  "meta": {
    "methods": 1601,
    "type": "users",
    "count": 1,
    "version": 6
  },
  "data": [{
    "ObjectIdentifier": "S-1-5-21-EXAMPLE-1234",
    "Properties": {
      "name": "AUDITOR@EXAMPLE.LOCAL",
      "domain": "EXAMPLE.LOCAL",
      "enabled": true
    },
    "Aces": [{
      "PrincipalSID": "S-1-5-21-EXAMPLE-512",
      "PrincipalType": "Group",
      "RightName": "Owns",
      "IsInherited": false
    }]
  }]
}
~~~

## Поддерживаемые рёбра ACL

Ниже перечислены типы связей, описанные
в исходном руководстве:

| Право / ребро | Значение |
|---|---|
| `Owns` | Владение объектом (подразумеваемый широкий контроль). |
| `GenericAll` | Полный контроль. |
| `GenericWrite` | Изменение атрибутов. |
| `WriteDacl` | Изменение прав доступа. |
| `WriteOwner` | Изменение владельца. |
| `WriteSPN` | Запись `servicePrincipalName`. |
| `AddKeyCredentialLink` | Запись `msDS-KeyCredentialLink`. |
| `AddAllowedToAct` | Настройка RBCD. |
| `AddMember` | Изменение членства в группе. |
| `WriteGPLink` | Управление привязкой GPO к OU/домену. |
| `AllExtendedRights` | Все расширенные права. |
| `ForceChangePassword` | Сброс пароля. |
| `GetChanges` | Право репликации (часть DCSync). |
| `GetChangesAll` | Репликация секретов (DCSync). |
| `GetChangesInFilteredSet` | Репликация фильтрованного набора. |
| `ReadLAPSPassword` | Чтение пароля LAPS. |
| `ReadGMSAPassword` | Чтение пароля gMSA. |
| `AddSelf` | Добавление себя в группу. |
| `Enroll` | Запрос сертификата. |
| `AutoEnroll` | Автоматический запрос сертификата. |
| `ManageCA` | Управление CA. |
| `ManageCertificates` | Одобрение/отклонение запросов CA. |
| `WritePKIEnrollmentFlag` | Изменение `msPKI-Enrollment-Flag`. |
| `WritePKINameFlag` | Изменение `msPKI-Certificate-Name-Flag`. |

Для DCSync оценивать нужно сочетания разрешений,
а не считать любое одиночное ребро достаточным
доказательством компрометации домена.

### Исключаемые субъекты

Сборщик фильтрует некоторые системные SID
из ACL-связей, аналогично SharpHound:

| SID | Субъект | Почему исключён |
|---|---|---|
| `S-1-5-18` | SYSTEM | Не обычный пользовательский субъект |
| `S-1-3-0` | Creator Owner | Системный placeholder |
| `S-1-5-10` | Self | Системный placeholder |

## Сравнение с SharpHound

| Возможность | adPEAS Collector | SharpHound |
|---|---|---|
| Язык | PowerShell | C# |
| Внешние зависимости | Нет | .NET Framework |
| Режимы | `DCOnly`, `ACL`, `ObjectProps`, `Trusts`, `Container`, `CertServices` | `All`, `DCOnly`, `Session` и др. |
| Членство локальных администраторов | Нет | Да, соответствующий метод |
| Активные сеансы компьютеров | Нет | Да |
| ACL | Да | Да |
| AD CS | Шаблоны, CA, NTAuth, issuance policies | Да |
| Доверия | Да | Да |
| Экспорт | BloodHound CE v6 JSON | BloodHound CE v6 JSON |

**Выбирайте adPEAS**, когда достаточно LDAP/DCOnly,
нужна автономная PowerShell-сборка и интеграция
с аудитом adPEAS. **Выбирайте SharpHound**,
когда требуется сбор с компьютеров, локальных групп
или активных сеансов.

## Дополнения о методах и рёбрах графа (DOC5)

### Учётные данные и сессия сборщика

Invoke-adPEASCollector использует существующую сессию Connect-adPEAS либо собственные параметры Domain, Server, Credential. Результат ограничен правами выбранного субъекта. Сборщик не требует установки SharpHound.

~~~powershell
# Работа через сессию с защищённым LDAP.
$cred = Get-Credential
Connect-adPEAS -Domain 'example.local' -Credential $cred -UseLDAPS -IgnoreSSLErrors:$false
Invoke-adPEASCollector -CollectionMethod DCOnly -OutputPath '.\Reports\bloodhound.zip'
Disconnect-adPEAS

# Прямой вызов с ограниченным методом.
Invoke-adPEASCollector -Domain 'example.local' -Credential (Get-Credential) -CollectionMethod ObjectProps -OutputPath '.\Reports\objects.zip'
~~~

### Полный перечень методов на примерах

DCOnly — наиболее полный метод LDAP-сбора adPEAS. Он не подключается к рядовым рабочим станциям/серверам для определения интерактивных сеансов или локальных администраторов. ObjectProps пропускает ACL, ACL фокусируется на правах, Trusts — на доверительных отношениях, Container — на дереве, CertServices — на объектах AD CS.

~~~powershell
Invoke-adPEASCollector -CollectionMethod DCOnly
Invoke-adPEASCollector -CollectionMethod ObjectProps
Invoke-adPEASCollector -CollectionMethod ACL
Invoke-adPEASCollector -CollectionMethod Trusts
Invoke-adPEASCollector -CollectionMethod Container
Invoke-adPEASCollector -CollectionMethod CertServices

# Доступные для просмотра файлы JSON без архива.
Invoke-adPEASCollector -NoZip -PrettyPrint -OutputPath '.\Reports\bloodhound-json'
~~~

### Как понимать связи ACL и пропущенные данные

Рёбра Owns, GenericAll, GenericWrite, WriteDacl, WriteOwner отражают владение и общие права. WriteSPN, AddKeyCredentialLink, AddAllowedToAct, AddMember и WriteGPLink относятся к конкретным атрибутам. GetChanges, GetChangesAll и GetChangesInFilteredSet характеризуют права репликации; наличие одного разрешения само по себе не доказывает возможность DCSync. ReadLAPSPassword и ReadGMSAPassword относятся к чтению секретов. Для AD CS используются Enroll, AutoEnroll, ManageCA и ManageCertificates.

В схеме BloodHound CE v6 названия прав, свойства ObjectIdentifier, PrincipalSID, RightName и имена файлов JSON остаются **без перевода**. Экспорт может исключать системные SID S-1-5-18, S-1-3-0, S-1-5-10 из части рёбер — это фильтрация представления, а не изменение AD.

SharpHound дополнительно умеет получать данные о локальных группах и сеансах рабочих станций, которых DCOnly не собирает. Отсутствие графовой связи в отчёте не следует трактовать как отсутствие возможного доступа в реальном домене.

## Навигация

[Предыдущая: Проверки безопасности](04-Security-Checks.md) ·
[Далее: Core Functions](06-Core-Functions.md) ·
[Главная](00-Home.md)
