# Быстрый запуск

Откройте Windows PowerShell 5.1 в каталоге `adPEAS-RU`.

**Полный аудит:**

```powershell
.\Run-AD-Audit-RU.ps1 -Domain "example.local" -OPSEC
```

**Выборочные проверки без BloodHound:**

```powershell
.\Run-AD-Audit-RU.ps1 -Domain "example.local" -Module Domain,Accounts,GPO,Rights -Format All -OPSEC
```

**Другой контроллер домена и учётные данные:**

```powershell
.\Run-AD-Audit-RU.ps1 -Domain "example.local" -Server "dc01.example.local" -Credential (Get-Credential)
```

По умолчанию создаются TXT, HTML и JSON в `Reports`. В HTML доступны поиск, фильтры, раскрытие карточек, оценка рисков и печать в PDF. Режим `-OPSEC` уменьшает объём активных проверок, но не устраняет любую сетевую активность.

В самом инструменте также доступен режим сессии: `Import-Module .\adPEAS.ps1`, затем `Connect-adPEAS`, `Invoke-adPEAS`, `Disconnect-adPEAS`.