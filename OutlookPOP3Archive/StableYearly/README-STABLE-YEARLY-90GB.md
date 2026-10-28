# STABLE 2.5.7-FIX13b — controlled continuous YEARLY archive of a 90 GB POP3 PST

This is the established production FIX13b, NOT the experimental 2.6.5
BW4a..BW4e2 Worker branch. The original FIX13b Move, verifier, durability,
per-source DuplicateIndex and manual Resume logic are retained.

Only two operator behaviors are configured:
- ArchiveGrouping=Year: physical output file YEAR is selected from the
  message date. Files are named SOURCE.Archive-2025.pst,
  SOURCE.Archive-2024.pst, SOURCE.Archive-2023.pst, etc.
  Subfolders inside each year PST reproduce Inbox / Sent Items /
  nested custom user folder paths.
- ArchiveThroughYear=2025: messages with archive date earlier than
  2026-01-01T00:00:00 only, excluding 2026 messages including the
  quarantined original synthetic LIVE3/BW3a evidence from 2026.
  This exact cutoff is PERSISTED into FIX13b checkpoint for manual Resume.

The former arbitrary 10 GB per-archive file cap is REMOVED FROM OPERATOR
CONFIGURATION. The archive maximum now follows the machine's configured
Outlook Unicode PST warning/maximum values from HKCU for the matching
Office/Outlook version. Without overrides, Outlook 2016+ defaults near
50 GB hard / 47.5 GB warning. A separate 0.5 GB safety margin remains
and the original FIX12a verified size rollover stays active. If one
year exceeds the **real Outlook** safe size, FIX13b MUST create a -02 PST
part for that year; an unconditional "one PST however large" would
risk corruption. This is NOT infinite PST capacity and does not alter
the Outlook registry or use the dangerous 1000 GB fake cap. The source
PST itself may be 90 GB only if Windows Outlook PST policy supports it;
contradictory limits cause a startup STOP.

The runner:
- Attaches ONLY to the already-running Outlook profile under this
  Windows user; requires exactly one POP3 account and exactly one
  matching mounted source PST (won't move mail from unrelated accounts).
- Previews an existing FIX13b Plan without Move unless -Execute supplied.
- With -Execute, runs successive 1000-item controlled verified batches,
  with DurabilityMode=Safe, no target-driven Auto storage stop.
- Checks local fixed disk space before each batch. Leaves messages in
  original PST until each Move has returned; all actual move correctness
  is subject to the original FIX13b verifier.
- Keeps existing FIX13b append-only step journal and transaction files,
  refuses unreadable/unfinished previous transaction rather than
  automatic risky Resume. A failed batch is a STOP and needs manual
  review/Resume; not an automatic repeated Move.
- Stops when a completed batch reports 0 moves.
- Writes transcript to StableYearly/Logs in the unpacked folder.
- Does not run any BW/Worker code, create a new Outlook session,
  auto-adjust registry, compact the source PST or archive active Outbox.
  Default Inbox, Sent Items and nested user folders are included;
  unsent Outbox is ALWAYS excluded by original FIX13b.

## Exact Windows PowerShell 5.1 STA use

1. Before the first live run, make a VERIFIED backup of the source
   POP3 PST and confirm disk free space large enough for output PSTs.
   Leave Outlook running and do not modify source PST externally.
2. Extract the CI-verified stable operator ZIP to its own folder.
3. Open native Windows PowerShell 5.1 under the SAME Windows user.

Preview the exact 2025-and-earlier YEAR grouping (NO MOVE):

    .\StableYearly\Start-StableYearlyArchive.ps1 -SourcePst "$env:USERPROFILE\Documents\Файлы Outlook\info@stios.ru.pst" -ProfileName 'Outlook'

Execute continuous verified batches, NO arbitrary 10 GB application cap:

    .\StableYearly\Start-StableYearlyArchive.ps1 -SourcePst "$env:USERPROFILE\Documents\Файлы Outlook\info@stios.ru.pst" -ProfileName 'Outlook' -ArchiveThroughYear 2025 -BatchSize 1000 -MinimumFreeGB 20 -Execute

This really MOVES mail. Run only after verified backup and successful
Preview with the correct POP3 source and folders. Monitor transcript,
free disk and Outlook responsiveness. The launcher runs in foreground
until all eligible 2025-and-earlier mail is handled OR a protective
stop is required. It does NOT promise immunity to Outlook COM hangs,
power failure, disk errors, or disabled Outlook PST registry limits.
It will NOT retry an incomplete transaction without manual review.

A newly registered PST is placed next to the source PST; ensure disk
capacity for BOTH original (PST size often does not shrink on Move) and
all generated archive files. Do NOT rely on the original 90 GB shrinking
automatically. Do not delete or compress source or archive until audits
and independent backups are complete.

Version of application remains 2.5.7-FIX13b; the YEARLY-OPERATOR build
is a separately packaged/pinned configuration branch, not the
experimental BW dev branch and not a statement that 90 GB/Outlook
long-run automation has been tested live.
