Server Maintenance Framework (SMF)
==================================

PowerShell 5.1 framework for Windows Server 2016, 2019, 2022 and 2025.
Windows 10/11 can be used for supported workstation-side checks.

Run
---
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-SMF.ps1 -Profile Analyze
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-SMF.ps1 -Profile Day -WhatIf
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-SMF.ps1 -Profile Day
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-SMF.ps1 -Profile Night

The default profile is Analyze. -SMFProfile remains an alias-compatible
parameter name for older invocations. Unknown options and profile names fail.

Profiles and safety
-------------------
Analyze scans and reports without deleting target files.
Day deletes eligible files according to each module's retention setting.
Night currently uses the same safe cleanup categories as Day. Browser site
storage is excluded by default. To include IndexedDB and Service Worker databases, explicitly set
Settings.BrowserCache.IncludeSiteStorage = $true in Config\Config.ps1.

The Windows Event Log module inventories event channels only. Neither Day
nor Night clears event channels. The Windows file log module separately
removes age-qualified files under %WINDIR%\Logs. A future full-channel
Event Log clear requires an explicit policy and successful backup first.

The user-profile cleanup module is disabled because its implementation is
not present. Enabled modules whose files are missing stop startup with an
error. Module failures produce a nonzero process exit code.

Outputs
-------
Logs\SMF.log contains execution messages. Reports\ contains JSON, HTML
and CSV reports. Do not commit these machine-specific outputs to GitHub.
The helper JSON-totalFreedMB.ps1 summarizes the newest local JSON report.

Development
-----------
Run the isolated regression checks with:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\Invoke-RegressionTests.ps1

The checks use temporary fixtures and do not clean live server paths.
See docs\SMF-ROADMAP.md for scope and release gates.
