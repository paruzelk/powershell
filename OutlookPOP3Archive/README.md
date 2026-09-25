# OutlookPOP3Archive

PowerShell application for automated archival of Outlook POP3 mailboxes.

## Main goals

- Reduce the size of the active POP3 PST.
- Select messages primarily by age.
- Exclude IMAP accounts.
- Support multiple Outlook profiles.
- Manage archive PST capacity safely.
- Automatically create additional archive PST files when required.
- Support transactions, checkpoints and resume.
- Verify archived data.

## Architecture

The project separates Outlook COM data access from business logic. COM is used for data access only; application decisions are made outside COM.

Planned/current components include:

- Foundation
- Runtime
- Discovery
- Archive Planner
- Archive Engine
- Archive Transaction
- Transaction Storage
- Mail Mover
- Migration Checkpoint
- Archive Workflow
- Folder Mapper
- Duplicate Detector / Index
- Archive Verifier
- Archive Report
- COM Manager

Archive PST naming convention:

`{account}.Archive-YYYY.pst`

Additional PSTs for the same year use:

`{account}.Archive-YYYY-02.pst`, `-03.pst`, etc.

Status: development.