# Remove-StaleProfiles

Утилита для аудита и удаления неиспользуемых профилей на терминальных серверах Windows Server. По умолчанию запускается в режиме `Audit` и ничего не удаляет.

## Требования

- Windows PowerShell 5.1, запуск от администратора.
- Модуль ActiveDirectory и доступ к AD для режима `Delete`.
- Файл скрипта сохранён в UTF-8 с BOM для PowerShell 5.1.

## Запуск

```powershell
.\Remove-StaleProfiles.ps1
.\Remove-StaleProfiles.ps1 -Mode Delete -Days 120
.\Remove-StaleProfiles.ps1 -Mode Delete -NoConfirm
```

Перед удалением скрипт проверяет состояние профиля, AD и защищённых групп повторно. Если проверка не завершилась успешно, профиль не удаляется. Настройки порога размера, отчётов и режима AD находятся в начале скрипта в `$Config`.

Отчёты CSV, HTML и журнал создаются в `C:\Logs\ProfileCleanup`. Если журнал создать или записать нельзя, выполнение останавливается до удаления. Код возврата: `0` — без ошибок, `1` — ошибки отдельных операций, `2` — критическая ошибка.

## Проверка без удаления

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Remove-StaleProfiles.Tests.ps1
```

Тесты загружают отдельные функции и подменяют вызовы CIM и AD; основной блок удаления не запускается.
