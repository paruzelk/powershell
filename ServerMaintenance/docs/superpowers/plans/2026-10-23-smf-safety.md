# SMF Safety Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing SMF launcher and file-cleanup core predictable and safe while preserving the three-profile architecture.

**Architecture:** Keep the current PowerShell 5.1 scripts and module interface. Add isolated regression checks, enforce exact path deletion and reliable process outcomes, and separate Windows file logs from Event Log channels.

**Tech Stack:** Windows PowerShell 5.1, built-in PowerShell assertions; Pester/PSScriptAnalyzer when available.

**Spec:** `docs/SMF-ROADMAP.md`

## Global Constraints

- No destructive tests on real Windows directories or Event Log channels.
- PowerShell scripts use ASCII characters only.
- Reports, logs, and backups are excluded from GitHub.
- A full Event Log clear is out of scope for this milestone.

## Review Focus

- Unknown `-Profile` values and unknown CLI arguments fail rather than silently choosing Analyze.
- Missing enabled module causes failure rather than an apparent successful run.
- A module result with `Failed` causes nonzero process exit.
- A file with wildcard characters in its name is deleted literally, without deleting a neighboring file.
- An event channel is never cleared by the safety baseline.

---

### Task 1: Isolated launcher and module-loading checks

**Files:** `Tests/Invoke-RegressionTests.ps1`, `Start-SMF.ps1`, `Core/ModuleLoader.ps1`, `README.txt`

**Interfaces:** launcher accepts `-Profile Analyze|Day|Night` (with backward-compatible `-SMFProfile`) and `-WhatIf`; `Import-SMFModules` throws for a missing enabled file; process exit is nonzero for failed modules.

- [x] Write fixture-based tests for profile binding, unknown arguments, missing module, and failed result exit code.
- [x] Run tests and verify the expected failures.
- [x] Implement parameter and loader changes, then update README.
- [x] Run tests and verify pass.

### Task 2: Literal deletion and Windows file logs

**Files:** `Tests/Invoke-RegressionTests.ps1`, `Core/Common.ps1`, `Modules/Clear-*.ps1`, `Modules/Clear-WindowsFileLogs.ps1`, `Config/Config.ps1`

**Interfaces:** existing modules retain `Invoke-Clear... -Context`; Windows file logs use `Settings.WindowsFileLogs.Enabled` and `KeepDays`, with only literal file deletion.

- [x] Add disposable-file tests for wildcard names, retention, Analyze, and WhatIf.
- [x] Run tests and verify the expected failures.
- [x] Replace file deletion with literal paths and add Windows file-log module.
- [x] Run tests and verify pass.

### Task 3: Event Log and risky-category guardrails

**Files:** `Tests/Invoke-RegressionTests.ps1`, `Modules/Clear-WindowsLogs.ps1`, `Modules/Clear-ChromeCache.ps1`, `Modules/Clear-EdgeCache.ps1`, `Modules/Clear-YandexCache.ps1`, `Config/Config.ps1`

**Interfaces:** Event Log module inventories only and reports that clear is disabled; browser site storage is excluded from all default profiles.

- [x] Add tests showing no event clear command executes and no browser site-storage path is selected by default.
- [x] Run tests and verify the expected failures.
- [x] Implement guardrails and document deferred explicit policies.
- [x] Run tests and verify pass.

### Task 4: Publication gate

**Files:** `docs/SMF-ROADMAP.md`, `.gitignore`, `README.txt`, all changed source and tests.

- [ ] Run all regression checks, parse all scripts under Windows PowerShell 5.1, and review the exact upload inventory.
- [ ] Create a development branch in `paruzelk/powershell` and upload only `ServerMaintenance` source, docs, and tests.
- [ ] Open a draft PR for review; do not merge before native Windows Server validation.
