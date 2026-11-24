# ARCH4 completed — ARCH5 development

## Operator-confirmed real checkpoint — 2026-11-24

Rollback release: `OutlookPOP3Archive-2.6.5-ARCH4-dev-gc0c185b3.zip`, commit `c0c185b3b316659572756f03eb8554b3b50d5f91`. CI 45352654463: 4752 Pester / 163 containers, no failures or skips. Real tests were performed only on the designated test POP3 PST.

| Batch | Planned | Returned | Verified | Reconciled | Indexed | NotMoved | LogicalBytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| 100 | 100 | 99 | 99 | 99 | 99 | 1 | 14506268 |
| 500 | 500 | 499 | 499 | 499 | 499 | 1 | 71236458 |

Both real batches returned BatchVerifiedReconciledAndIndexed after the independent Outlook restart. Archive WhatIf returned NoOutlookOrPersistentWrites. No replay of COM Move required. The 500-item batch took 76.4554804 s for Archive and 85.0702923 s for Resume, excluding manual restart. ARCH4 real bounded batch acceptance complete; production readiness still false.

First skip: ARCH2b unsupported attachment type/size at index 2; embedded/OLE attachments not yet certified. Second skip cause not yet confirmed; do not assume two distinct messages or identical cause. Current witness accepts olByValue only and at most 256 MiB per attachment. Preserve unsupported items at source; never bypass the witness or silently ignore payloads. No new historical SHA/PST-size preflight requirements.

## ARCH5 scope

- Inspect existing eligible POP3 folder selection and routing: Inbox, Sent Items (SentOn date), nested user folders; exclude Outbox and unwanted system folders.
- Verify year and quarter grouping, archive-part selection and folder hierarchy with executable fake Outlook scenarios, then a bounded real mixed-folder test.
- Diagnose unsupported attachment type and size separately; extend embedded-message and OLE verification only with reliable payload/content comparison, preserving fail-closed behavior for unsupported types. Revisit resource limits without disabling validation.
- Include explicit skip reason/count, correct runtime version and effective durability mode, report Resume settings from the persisted transaction rather than current CLI defaults, and progress/speed/ETA.
- Reuse ARCH4 original mover, independent verifier, journal/index commit and pending guard. Do not repeat ARCH3 or the completed real ARCH4 100/500 runs.
- Continue Windows PowerShell 5.1 CI, PSScriptAnalyzer, UTF-8 BOM for PowerShell, project-only ZIP. No live Outlook in CI. ARCH6 remains performance/recovery/large-PST release validation.

This is a documentation checkpoint and ARCH5 scope, not a new executable release.
