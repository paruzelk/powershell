# Server Maintenance Framework: goals and roadmap

## Sources and current scope

The accessible tail of the ChatGPT conversation "Очистка логов Windows" describes a PowerShell 5.1 modular framework with Analyze, Day and Night profiles, one logger, one result API, reliable module loading, and HTML/JSON reports. The repository README adds Windows Server 2016/2019/2022/2025 and workstation testing. The user clarified on 2026-10-23 that "Windows logs" includes both Event Log channels and files under `C:\Windows\Logs`; Event Log must remain analysis-only, and recycle-bin cleanup must cover all users. Earlier messages in that conversation were not available through the thread reader, so this document does not claim to reproduce all original requirements.

## Safety contract

- Analyze previews candidates without deleting them. Day removes only age-qualified file targets. Night may add explicitly documented categories, but must never silently clear all Event Log records or browser site storage.
- Event Log channels are analyzed separately from ordinary log files and are never cleared by this program. `KeepDays` cannot be implemented by `wevtutil cl`.
- Recycle-bin cleanup covers all non-system user SID folders on fixed local drives by default, including users whose profiles were removed. Exact account names or SIDs can be excluded explicitly. Reparse points are skipped and access failures produce partial results.
- Every destructive file operation targets an exact literal path. Missing enabled modules and module failures are visible in reports and process exit codes.
- A report distinguishes scanned, eligible, deleted, skipped, partial, and failed work. Logs and reports are not committed to GitHub.

## Milestones

1. **Safety baseline:** repair the profile CLI, literal file paths, missing-module handling, failure exit codes, configuration flags, and documentation. Add isolated regression checks that never touch real cleanup paths.
2. **Two Windows-log workflows:** age-based cleanup of ordinary files in `Windows\Logs`; read-only Event Log inventory in every profile. Validate both on Windows PowerShell 5.1 and a disposable Windows Server VM.
3. **Reliable inventory and reports:** validate all-user recycle-bin cleanup on a disposable multi-user Windows Server VM; discover real profile and IIS log paths, report inaccessible trees and partial results, bound per-file detail output, escape HTML fields, and measure free space before/after.
4. **Operations:** configurable retention per target, scheduled noninteractive runs, log/report rotation, PSScriptAnalyzer and Pester CI, and a versioned release process.
5. **Optional modules:** review profile cleanup as a separate project and integrate only after its own safety tests; treat browser IndexedDB and Service Worker databases as user data requiring separate opt-in.

## Repository workflow

`paruzelk/powershell/ServerMaintenance` is the canonical target. Develop on a branch and submit a draft PR against `main`. Publish source and tests only; do not upload local `Logs`, `Reports`, backups, or machine-specific files. Merge and tag after native Windows PowerShell 5.1 verification.

## Current validation and release gate

The local Windows PowerShell 5.1 regression suite passes 29 isolated checks, and all 22 scripts parse. A real `Analyze -WhatIf` run generated JSON, HTML and CSV reports without deleting target files. It returned exit code 1 because this session is not elevated and cannot read Event Log channels; recycle-bin profile-name lookup and one Windows Logs subfolder produced partial results. The cleanup profiles have not been run against a live server.

Before merging, test on a disposable elevated Windows Server VM with two or more user accounts, bins on multiple fixed drives, inaccessible and locked files, custom IIS paths, and an Event Log channel that denies access. Review report totals and exit codes after Analyze, Day -WhatIf, Day, and Night. Confirm that only age-qualified ordinary files are removed, that Event Log records remain intact, and that all intended user bins are empty.

## Comparable implementations

- [Microsoft cleanmgr](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/cleanmgr) is the built-in Windows Server disk cleanup tool with scheduled profiles.
- [Alexandre-Guth/clean-windows-server](https://github.com/Alexandre-Guth/clean-windows-server) covers age-based logs and temporary files with optional all-user recycle-bin cleanup.
- [neravr/windows-server-drive-cleanup](https://github.com/neravr/windows-server-drive-cleanup) focuses on scheduled server cleanup and per-path CSV reporting.

SMF's development priority is auditable per-module inventory, strict target and retention validation, a readable failure status, and a repeatable Windows Server test matrix. Windows Update cache, DISM and user-profile deletion remain separate opt-in projects; they should not be folded into the default cleanup path.
