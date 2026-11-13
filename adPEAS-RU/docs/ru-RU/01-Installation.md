# Установка и подготовка adPEAS-RU

Руководство для закреплённой версии **adPEAS 2.9.0**.
Русская сборка находится в ветке
[adpeas-ru-2.9.0](https://github.com/paruzelk/powershell/tree/adpeas-ru-2.9.0).
Это отдельная редакция английского [adPEAS](https://github.com/61106960/adPEAS).

## Системные требования

- Windows 10/11 или Windows Server 2016, 2019, 2022, 2025.
- Windows PowerShell **5.1**, .NET Framework **4.5+**.
- Не требуются RSAT, PowerShell-модуль ActiveDirectory,
  PowerView и другие сторонние модули.
- Компьютер может не входить в домен, если доступен DC
  и есть подходящие полномочия.

### Сетевые порты

| TCP | Назначение |
|---|---|
| 389 | LDAP |
| 636 | LDAPS |
| 88 | Kerberos |
| 445 | SMB, SYSVOL/NETLOGON при соответствующих проверках |
| 80/443 | HTTP/HTTPS к AD CS и Exchange |
| 3268/3269 | Global Catalog, опционально |
| DNS | Разрешение имён AD и контроллеров домена |

Доступность конкретных служб зависит от запускаемых модулей.

## Загрузка

**Русская версия:** скачайте готовый ZIP из ветки
`adpeas-ru-2.9.0` с файлом контрольной суммы `.sha256`.
После распаковки откройте каталог `adPEAS-RU`.

~~~powershell
# Вариант через Git
git clone -b adpeas-ru-2.9.0 https://github.com/paruzelk/powershell.git
Set-Location .\powershell\adPEAS-RU
~~~

**Оригинальные релизы:** доступны отдельно на
[GitHub Releases](https://github.com/61106960/adPEAS/releases).
В них четыре автономных варианта; они **не содержат русификацию**.
Команды английского руководства загружают файлы из `main`,
которые могут отличаться от фиксированного перевода:

~~~powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/61106960/adPEAS/main/adPEAS.ps1" -OutFile "adPEAS.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/61106960/adPEAS/main/adPEAS_obf.ps1" -OutFile "adPEAS_obf.ps1"
~~~

## Варианты файлов

| Файл | Использование |
|---|---|
| `adPEAS.ps1` | Читаемый код, комментарии и отладка |
| `adPEAS_min.ps1` | Минимизация без комментариев |
| `adPEAS_ultra.ps1` | Ультрасжатый вариант |
| `adPEAS_obf.ps1` | Обфускация GZip + XOR + Base64 |

Размеры в английском руководстве (~4,5 МБ, 3–4 МБ,
~3 МБ и менее 1 МБ соответственно) ориентировочны и
зависят от сборки.

## Загрузка в PowerShell

~~~powershell
Import-Module .\adPEAS.ps1 -Force
Get-Command Invoke-adPEAS
Get-Command Connect-adPEAS
Get-Command Get-DomainUser
Get-Command -Module adPEAS
~~~

Для русской обёртки можно сразу выполнить:

~~~powershell
.\Run-AD-Audit-RU.ps1 -Domain 'example.local' -OPSEC
~~~

Она по умолчанию использует LDAPS с **проверкой сертификата**.
Это отличается от значения `IgnoreSSLErrors` по умолчанию
в оригинальной `Connect-adPEAS`.

## Политика выполнения

Если корпоративная политика разрешает, в отдельной сессии:

~~~powershell
powershell.exe -ExecutionPolicy Bypass
Import-Module .\adPEAS.ps1
~~~

Для текущего пользователя:

~~~powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
~~~

Удаление метки загруженного файла — только после
проверки подлинности:

~~~powershell
Unblock-File -Path .\adPEAS.ps1
~~~

Не обходите политики организации без разрешения.

## Сборка из исходников

`Build-Release.ps1` использует `Build-Engine.ps1`
и `Build-Config.psd1` для создания четырёх вариантов.

~~~powershell
.\Build-Release.ps1
.\Build-Release.ps1 -Stable
.\Build-Release.ps1 -License '.\license.json'
~~~

Для **повторного импорта закреплённого оригинала**
и применения проверенных русских каталогов:

~~~powershell
.\Import-adPEAS-RU.ps1
# Применить локализацию, но не собирать автономные варианты:
.\Import-adPEAS-RU.ps1 -SkipBuild
~~~

Импорт проверяет закреплённую версию и контрольные
суммы исходных файлов; обычная загрузка upstream `main`
не заменяет этот процесс.

## Лицензирование

adPEAS использует подписанную лицензию **RSA-SHA256**,
которая может менять сообщение о владельце в отчётах.
Наличие всех функций без лицензии **не отменяет** её условий.

~~~powershell
# Встроить лицензию во время сборки
.\Build-Release.ps1 -License '.\license.json'

# Передать при подключении с явной проверкой LDAPS
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth `
    -UseLDAPS -IgnoreSSLErrors:$false -License '.\license.json'
Invoke-adPEAS -OPSEC
~~~

Или лицензия при прямом запуске:

~~~powershell
Invoke-adPEAS -Domain 'example.local' -UseWindowsAuth -License '.\license.json'
~~~

Приоритет: `Invoke-adPEAS -License`, затем
`Connect-adPEAS -License`, затем лицензия в сборке.

Файл лицензии выглядит так:

~~~json
{
  "Licensee": "Company Name",
  "ValidUntil": "2027-06-30",
  "Signature": "Base64-encoded RSA-SHA256 signature"
}
~~~

Подпись проверяется открытым ключом, встроенным в
продукт. Лицензии выдаёт автор. Внутренние
некоммерческие аудиты собственного домена могут быть
разрешены без оплаты; услуги клиентам, платные работы
и коммерческие контракты требуют отдельной лицензии.

Оригинальные условия:
[LICENSE](../../license/LICENSE.md),
[COMMERCIAL_AGREEMENT](../../license/COMMERCIAL_AGREEMENT.md),
[PRICING](../../license/PRICING.md).

## Обновление и устранение ошибок

Перед заменой файлов закройте старые сессии;
затем выполните:

~~~powershell
Remove-Module adPEAS -ErrorAction SilentlyContinue
Import-Module .\adPEAS.ps1 -Force
~~~

Если загрузка не проходит, проверьте
`$PSVersionTable.PSVersion`, целостность файла,
политику выполнения и путь. При отладке можно
использовать dot-sourcing:

~~~powershell
. .\adPEAS.ps1
Import-Module 'C:\Tools\adPEAS.ps1'
~~~

При ошибке LDAPS проверьте FQDN, сертификат DC,
доверенную цепочку и срок действия, а не отключайте
проверку TLS по умолчанию.

## Дополнительная диагностика установки (DOC5)

### Стабильный релиз и исходная ветка main

Английский оригинал предлагает получать стабильные варианты с [GitHub Releases](https://github.com/61106960/adPEAS/releases), где четыре сборки прикрепляются отдельно. Файлы из main оригинального проекта обновляются с исправлениями и могут иметь версию, отличающуюся от закреплённой русской 2.9.0. Для воспроизводимого русскоязычного аудита используйте ZIP конкретной сборки и проверяйте SHA-256.

~~~powershell
# Проверить файлы после распаковки, не подключаясь к AD.
Get-Item .\adPEAS.ps1 | Select-Object FullName, Length
Import-Module .\adPEAS.ps1 -Force
Get-Command -Module adPEAS
Get-Command Invoke-adPEAS, Connect-adPEAS, Get-DomainUser

# Для английского оригинала: сборка из исходного дерева.
git clone https://github.com/61106960/adPEAS.git
Set-Location .\adPEAS
.\Build-Release.ps1
~~~

Созданные Build-Release.ps1 автономные файлы не требуют RSAT. Русская редакция импортируется отдельно через Import-adPEAS-RU.ps1 с проверкой закреплённого источника.

### Встраивание лицензии и приоритет

В исходном проекте лицензия может быть встроена при сборке или передана во время подключения и сканирования. Приоритет источников: Invoke-adPEAS -License, затем Connect-adPEAS -License, затем встроенная лицензия. Подпись RSA-SHA256 проверяется инструментом, а сведения о лицензиате показываются в консоли и отчёте.

~~~powershell
# Лицензия при сборке автономных файлов.
.\Build-Release.ps1 -License '.\license.json'

# Лицензия, переданная при подключении.
Connect-adPEAS -Domain 'example.local' -UseWindowsAuth -UseLDAPS -IgnoreSSLErrors:$false -License '.\license.json'
Invoke-adPEAS -OPSEC
~~~

Отсутствие лицензии не отключает технические функции, но не отменяет юридических условий. JSON-ключи Licensee, ValidUntil и Signature сохраняются неизменными.

### Частые ошибки установки

| Симптом | Проверка |
|---|---|
| Import-Module не загружается | PowerShell 5.1, путь, целостность файла, политика исполнения |
| Команды отсутствуют | Get-Command после импорта и закрытие старой сессии |
| Запуск скриптов запрещён | Только разрешённое организацией значение ExecutionPolicy |
| Файл не найден | Текущая директория или полный путь |
| LDAPS отклоняет соединение | FQDN DC, SAN сертификата, доверенная цепочка и TCP/636 |

~~~powershell
# Полный путь из исходного руководства.
Import-Module 'C:\Tools\adPEAS.ps1' -Force
Remove-Module adPEAS -ErrorAction SilentlyContinue
Import-Module .\adPEAS.ps1 -Force
~~~

## Навигация

[Обзор](00-Home.md) ·
[Быстрый запуск](02-Quick-Start.md) ·
[Полный справочник ключей](../../README_RU.md)
