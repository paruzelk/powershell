# Server Maintenance Framework: goals and roadmap

## Sources and current scope

The accessible tail of the ChatGPT conversation "Очистка логов Windows" describes a PowerShell 5.1 modular framework with Analyze, Day and Night profiles, one logger, one result API, reliable module loading, and HTML/JSON reports. The repository README adds Windows Server 2016/2019/2022/2025 and workstation testing. The user clarified on 2026-10-23 that "Windows logs" includes both Event Log channels and files under `C:\Windows\Logs`. Earlier messages in that conversation were not available through the thread reader, so this document does not claim to reproduce all original requirements.

## Safety contract

- Analyze previews candidates without deleting them. Day removes only age-qualified file targets. Night may add explicitly documented categories, but must never silently clear all Event Log records or browser site storage.
- Event Log channels are analyzed separately from ordinary log files. Full-channel clear requires an explicit future policy with channel allowlist, successful export, and auditable confirmation. `KeepDays` cannot be implemented by `wevtutil cl`.
- Every destructive file operation targets an exact literal path. Missing enabled modules and module failures are visible in reports and process exit codes.
- A report distinguishes scanned, eligible, deleted, skipped, partial, and failed work. Logs and reports are not committed to GitHub.

## Milestones

1. **Safety baseline:** repair the profile CLI, literal file paths, missing-module handling, failure exit codes, configuration flags, and documentation. Add isolated regression checks that never touch real cleanup paths.
2. **Two Windows-log workflows:** age-based cleanup of ordinary files in `Windows\Logs`; read-only Event Log inventory with a separate, explicitly opted-in export-and-clear design. Test on Windows PowerShell 5.1 and a disposable Windows Server VM before enabling any full clear.
3. **Reliable inventory and reports:** discover real profile and IIS log paths, report inaccessible trees and partial results, bound per-file detail output, escape HTML fields, and measure free space before/after.
4. **Operations:** configurable retention per target, scheduled noninteractive runs, log/report rotation, PSScriptAnalyzer and Pester CI, and a versioned release process.
5. **Optional modules:** review profile cleanup as a separate project and integrate only after its own safety tests; treat browser IndexedDB and Service Worker databases as user data requiring separate opt-in.

## Repository workflow

`paruzelk/powershell/ServerMaintenance` is the canonical target. Develop on a branch and submit a draft PR against `main`. Publish source and tests only; do not upload local `Logs`, `Reports`, backups, or machine-specific files. Merge and tag after native Windows PowerShell 5.1 verification.
