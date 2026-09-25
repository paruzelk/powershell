# OutlookIMAPSync

PowerShell 5.1 script for configuring the Outlook IMAP synchronization window for the current Windows user.

## Deployment

Designed for GPO User Logon Script deployment.

The script works through the Outlook profile registry and is intended to run without interactive UI.

## Features

- Configure the IMAP synchronization period.
- Support `-DesiredMonths`.
- Support `-WhatIf`.
- Idempotent registry changes.
- Logging and return codes.
- Detect Outlook profiles.
- Avoid changing settings while Outlook is running.

Current documented release: v1.0 Final.