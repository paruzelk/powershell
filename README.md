# PowerShell Projects

Personal PowerShell projects developed and maintained with ChatGPT.

## Projects

### OutlookPOP3Archive
PowerShell application for archiving Outlook POP3 mailboxes with age-based selection, PST capacity management, transaction/resume support, duplicate detection and verification.

Status: development.

### OutlookIMAPSync
PowerShell 5.1 script for configuring the Outlook IMAP synchronization window through the current-user registry, intended for GPO User Logon deployment.

Current documented release: v1.0 Final. Earlier development versions exist.

### Remove-StaleProfiles
PowerShell 5.1 script for auditing and safely deleting stale Windows Server user profiles, with CSV/HTML reports and regression tests.

### ServerMaintenance
PowerShell 5.1 server maintenance framework for Windows Server 2016+.

Entry point: `Start-SMF.ps1`

Includes Analyze/Day/Night profiles, preview analysis, HTML reporting and modular cleanup components.

## Repository structure

```
OutlookPOP3Archive/
OutlookIMAPSync/
ServerMaintenance/
Remove-StaleProfiles/
```

The repository is intended to become the canonical source for these projects.
## Development and releases

Use GitHub Flow: branch from `main`, open a Pull Request, run project-specific Windows PowerShell 5.1 CI, then merge approved changes. Each project has independent version tags and GitHub Releases rather than keeping every ZIP in a long-lived branch. Historical `release/*` and `package/*` branches are retained during migration.

See [Repository workflow](docs/REPOSITORY-WORKFLOW.md) for branch names, the 2.6.2/2.6.3 migration, Windows CI, release tagging, and safety gates.
