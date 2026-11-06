# File-Server-Audit RU — готовая версия без установки

Русифицированная копия проекта https://github.com/sean-aura/File-Server-Audit версии 0.7.4, исходный commit faf157d96341e1336b8b39e0751cf16aa3f79f29. Лицензия MIT (LICENSE).
Изменения уже внесены прямо в исходные файлы: **не нужны инсталляторы, отдельные патчи, копирование файлов или сетевой доступ при запуске**.

## Что исправлено

- PowerShell PS1: UTF-8 с BOM для Windows PowerShell 5.1.
- CSV: явный -Encoding UTF8, в том числе при дозаписи; логи/checkpoints в UTF-8.
- HTML: встроенная русская локализация; кнопки **Участники: N**, **Развернуть все группы**, **Свернуть все группы**.
- Если данные о группе не собраны, явно указано Состав группы не загружен.
- Статус AD-пользователя: проверка по userAccountControl / ACCOUNTDISABLE 0x2; при отсутствии подтверждения — неизвестен.
- Исправление обработки единственного CSV в Build-AccessMapHtml.ps1.
- Один запуск NTFS-аудита и HTML через Invoke-FileServerAudit-RU.ps1.
- Повторная HTML-сборка из CSV через Build-AccessMapFromFolder.ps1.

## Один запуск

Откройте Windows PowerShell 5.1 в каталоге проекта:

~~~powershell
.\Invoke-FileServerAudit-RU.ps1 -Path '\\SHARE\Network' -ExpandGroups -MaxDepth 2 -OpenHtml
~~~

Результат: NTFSAudit_yyyyMMdd_HHmmss с CSV и подпапкой AccessMap_yyyyMMdd_HHmmss, содержащей AccessMap.html и AccessMap_data. HTML открывается локально без сервера.

Все параметры оригинального сканера сохранены: -Path, -IncludeFiles, -IncludeInheritedFileAces, -MaxDepth, -NoRecursion, -BreadthFirst, -ThrottleLimit, -ExpandGroups, -ExpandGroupsExclude, -SkipInheritedAces, -OutputFolder, -NoAdLookup, -Force, -Resume.

Для раскрытия участников групп обязателен -ExpandGroups. По умолчанию исключены крупные группы Domain Users, Everyone, Authenticated Users, Users, BUILTIN\Users. Их можно переопределить через -ExpandGroupsExclude. Без раскрытия HTML честно пишет, что состав группы не загружен.

~~~powershell
.\Invoke-FileServerAudit-RU.ps1 -Path '\\SHARE\Network' -ExpandGroups -MaxDepth 2 -OutputFolder 'D:\Audit\Run1' -OpenHtml
~~~

## Сборка отчёта из ранее полученных данных

~~~powershell
.\Build-AccessMapFromFolder.ps1 'D:\Audit\Run1' -OpenHtml
.\Build-AccessMapFromFolder.ps1 'D:\Audit\Run1\AccessMap_20261106_112710' -OpenHtml
~~~

Для пересоздания HTML в уже заполненном каталоге используется -Force. Важно: повторная сборка старого CSV не обновляет статус пользователей из AD; для этого требуется новый аудит.

## Исходные сценарии

Их можно использовать отдельно: Get-FileServerShareInventory.ps1, Invoke-NTFSPermissionAudit.ps1, Build-AccessMapHtml.ps1. Функциональность SMB/NTFS/DFS исходного проекта сохранена. Системные шары и корзины специально не исключались — используйте конкретный UNC-путь через -Path.

## Проверка

~~~powershell
.\Tests\Test-Source.ps1
~~~

Проверяет синтаксис PowerShell, кодировку BOM, наличие встроенных функций HTML и AD-проверку. Интеграционная проверка на реальном AD/Windows Server проводится отдельно.

Windows PowerShell 5.1 поддерживается; исходный сканер требует PowerShell 7 для параллельного режима -ThrottleLimit более 1. Для AD нужен доступ к контроллеру домена; модуль ActiveDirectory (RSAT) не обязателен.

Отчёт показывает ACE и пользователей в группах, а не гарантированные эффективные права пользователя через SMB+NTFS. Отключение наследования не всегда является ошибкой. Отчёт с именами пользователей и структурой ACL следует хранить в защищённом каталоге.

Русский интерфейс встроен в AccessMapTemplate.html и переводит динамически появляющиеся текстовые метки страницы (без внешних файлов или инсталлятора). Поля CSV/JSON, имена команд, пути и алгоритмы остаются исходными. Часть диагностических сообщений может быть на английском.
