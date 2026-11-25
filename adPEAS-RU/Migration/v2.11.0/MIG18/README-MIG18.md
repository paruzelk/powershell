# adPEAS-RU 2.11.0 — MIG18: интеграция исходников и CI

**Статус:** пакет интеграции; не скомпилированный релиз. Ветка GitHub на момент проверки — `daa29adc618351ba89f10fc406b225b3b1cd491c` (MIG11). Оригинал 2.11.0 закреплён за `477696f48d6b486be5d9a99b598f72e3ccfcc0c0`.

## Публикация из Windows (PowerShell 5.1, Git, Python 3.10+)

Распакуйте архив вне репозитория, например `C:\Tools\MIG18`. В чистом каталоге выполните:

```powershell
Set-Location C:\Tools
git clone --branch adpeas-ru-2.11.0 --single-branch https://github.com/paruzelk/powershell.git adpeas-mig18
python C:\Tools\MIG18\Install-MIG18.py --repo C:\Tools\adpeas-mig18
if ($LASTEXITCODE -ne 0) { throw 'MIG18 installation failed' }
Set-Location C:\Tools\adpeas-mig18
git status --short
git diff --check
```

После проверки файлов:

```powershell
git add -- adPEAS-RU/Migration/v2.11.0/MIG18 .github/workflows/adpeas-ru-211-mig18.yml
git diff --cached --check
git commit -m "MIG18: integrate verified Russian source patches and five-variant CI"
git push origin adpeas-ru-2.11.0
```

Установщик откажется работать при отличающемся HEAD, другой ветке, незакоммиченных изменениях или уже существующих путях. Он не выполняет commit/push и не запускает аудит. Не используйте force push. Старый MIG11 workflow не изменяется; его широкий фильтр путей может вызвать дополнительный прогон.

Откройте https://github.com/paruzelk/powershell/actions и найдите `adPEAS RU 2.11.0 MIG18 - integrated Russian build`. При успешной сборке появится артефакт `adPEAS-RU-2.11.0-MIG18-PREVIEW` с пятью вариантами. Срок хранения 14 дней. До зелёного CI не считать EXE или остальные варианты проверенными.

## Контрольные проверки

- Локально применены MIG12–MIG16 к полному исходному PS1 MIG11; каждый результат побайтно совпал с ранее выпущенным ZIP.
- CLI патчи MIG12–MIG16 применены к реальному JS-шаблону, извлечённому из MIG11, и синтетическому файлу статических надписей; полный нормализованный JS совпал с MIG16; Node syntax PASS.
- Все пять словарей проверены по точным SHA-256 и числу записей. Исходные команды не изменяются.
- MIG17 проверяет Git blob SHA-1 оригинальных build-файлов, переносит только подготовленные изменения оболочки и сообщений компиляции.
- CI сохраняет проверки MIG1–MIG11, добавляет миграцию MIG12–MIG17, проверку BOM, AST PowerShell 5.1, JavaScript, наличие пяти выходных файлов, контрольные суммы, метаданные EXE и побайтовое совпадение встроенного ресурса с полным PS1.
- Обфусцированный вариант проходит проверку наличия, BOM и синтаксиса, но не выполняется; содержательная проверка всех вариантов остаётся MIG19.

**Ограничения:** в текущем окружении отсутствует доступ к codeload GitHub из локального контейнера и Windows PowerShell 5.1. Полное дерево кандидата не собрано. CI не запущен. GitHub не изменён: доступный интерфейс GitHub не принимает локальные файлы ZIP как содержимое коммита. Данные реального аудита в пакет не включены. Скачанный архив содержит только исходные патчи, документацию и установщик.
