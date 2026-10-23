# Server Maintenance Framework

PowerShell 5.1 framework for Windows Server 2016, 2019, 2022 and 2025. It inventories and cleans temporary files, old Windows and IIS log files, WER files, recycle bins, and browser caches through ordered modules. Windows 10/11 can be used for workstation-side checks.

## Run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-SMF.ps1 -Profile Analyze
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-SMF.ps1 -Profile Day -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-SMF.ps1 -Profile Day
```

`Analyze` is the default. `Day` and `Night` run enabled cleanup modules; review `Config/Config.ps1` before using either on a server. `-WhatIf` previews cleanup. The launcher returns a nonzero exit code for failed modules.

## Current safeguards and limits

- Files under `%WINDIR%\Logs` are selected by `WindowsFileLogs.KeepDays` (30 days by default).
- The Windows Event Log module **inventories channels only**. It never clears them. Full-channel clear needs a separate export-and-clear policy; `wevtutil cl` cannot preserve the newest 30 days.
- Browser IndexedDB and Service Worker databases are excluded unless `BrowserCache.IncludeSiteStorage` is explicitly enabled.
- The user-profile cleanup module is disabled because its implementation is not present.
- The current Windows file-log path and several other paths are defaults, not full discovery of custom server locations. A Windows Server validation run is still required before production deployment.

Machine-specific `Logs/`, `Reports/`, and `Backup/` content is excluded from Git.

## Development

Run isolated regression checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Invoke-RegressionTests.ps1
```

See [the roadmap](docs/SMF-ROADMAP.md) for recovered goals, remaining work, and release gates.
