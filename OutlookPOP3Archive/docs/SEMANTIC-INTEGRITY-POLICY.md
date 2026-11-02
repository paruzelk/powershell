# SEM-001 — Semantic integrity of Outlook POP3 archiving (normative)

**Approved 2026-11-02.** This policy supplements `TECHNICAL_SPECIFICATION.md`, `ARCHITECTURE.md`, `OPERATION-JOURNAL.md`, `RECOVERY.md` and `TESTING.md`. Applies to all future OutlookPOP3Archive Archive / Resume / Auto workers. **Not a production enablement or authorization to move any specific mail.**

## Purpose

Archive Outlook messages as **complete logical mail objects** through supported Outlook COM / MAPI operations, not as byte-for-byte copies of the physical PST or every internal MAPI property. Compare actual end-to-end logical content **before acknowledging a completed move**. Retain all durability, duplicate, no-blind-retry, source/target store and journal safeguards.

- Outlook `MailItem.Move(targetFolder)` (or an explicitly supported MAPI move) is responsible for moving the complete message, not custom reconstruction of a MailItem from text and attachments. The precise internal implementation of built-in Outlook AutoArchive is not asserted to invoke `MailItem.Move()`.
- A changed `MailItem.Size` / `PR_MESSAGE_SIZE` is **not by itself proof** of corruption or loss. It is diagnostic / capacity input. A strict equality condition for size must **not** be a global content-integrity condition.
- A bytewise identity requirement for the source/destination **PST** or **all MAPI properties** is prohibited as a universal acceptance criterion. A moved item may legitimately acquire new store/object identity.
- Semantic integrity is an **explicit allowlisted, versioned schema** of required fields, not a vague rule that any change can be ignored. An unavailable required field or incomplete scan fails closed. Never guess that an absent property is equivalent to one that was previously available.

## Required content preservation (SEM-001-CONTENT)

1. **Identity and scope:** profile, source POP3 store, source folder, source EntryId, exact intended destination PST/store/folder, stable operation / message correlation, and cross-store source-zero/destination-one proof with bounded **complete** scans. `InternetMessageId` where present; otherwise a documented strong fallback identity. For synthetics, maintain exact original TestId, InternetMessageId and `PR_SEARCH_KEY` where already pinned.
2. **Human-visible content:** subject, sender/address, recipients (To/Cc and Bcc when accessible and relevant to a Sent item), plain-text Body, HTMLBody (when present), message class/type, and delivery/sent timestamps and their representations. Compare normalized, explicitly documented logical values **only where normalization is justified**; otherwise compare UTF-8 data SHA-256 / lengths. For production, cover sender/recipient MAPI address semantics and Sent Items; the current BW4j witness does **not** capture the complete recipient set, hence it cannot prove production-grade completeness.
3. **Attachments:** same count, order/identity where stable, filename, by-value/payload type, exact original byte length and **SHA-256 of bytes** from bounded readback. If unavailable, unsafely oversized, or different: fail closed. Do not infer payload preservation from `PR_HASATTACH` or reported `Attachment.Size` alone.
4. **Headers and message metadata:** compare transport headers and meaningful message identifiers when available, preserving the logical message. A change or absence of required original evidence must be explained and handled by a dedicated audited rule, not an automatic waiver.
5. **Significant state:** preserve read/unread, relevant flags, categories, follow-up state and other operator-defined user-visible properties where required by policy; record any loss. `PR_MESSAGE_FLAGS` is a bitfield: compare defined meaningful bits **by mask**, not raw numeric/byte equality. The exact mask and exceptions must be separately specified and tested before production.
6. **Physical durability:** a logically matching COM read after `Move` does not prove PST persistence after power loss. Preserve backups, durable claim/intent, independent read-only reconciliation after interruption and explicit PST durability gates; test compact separately.

## Store/MAPI properties (SEM-001-MAPI)

| Property | Semantic integrity criterion |
|---|---|
| `MailItem.Size`, `PR_MESSAGE_SIZE` | Record original/current values, delta, and relevant capacity effect; **never automatically reject or accept solely for delta**. |
| `PR_ENTRYID`, `PR_RECORD_KEY` | Store/object identity may change on cross-PST move. Require correct destination correlation, not bytewise equality. |
| `PR_SEARCH_KEY` | Preserve when stable and already pinned for the chosen store/provider; differences require an independent identity rule and review, not generic ignoring. |
| `PR_MESSAGE_FLAGS` | Compare documented **semantic flag mask**, accounting for read state and attachment state; never grant unrestricted flag changes. |
| `PR_HTML` | If MAPI raw property unavailable but Outlook `HTMLBody` is independently available, compare the `HTMLBody` bytes/UTF-8 digest; do **not** claim raw `PR_HTML` equality. |
| `PR_TRANSPORT_HEADERS`, sent/delivery times, message class | Compare via independently captured digests/values when present; unexpected differences fail closed. |
| `PR_SOURCE_KEY`, `PR_CHANGE_KEY` | May be unavailable; log availability on both sides, and never synthesize equality/proof. |

Changes to service metadata are **expected possibilities**, not predefined accepted outcomes. An implementation must distinguish: exact logical match, mandatory-field mismatch, metadata-only difference needing classification, and insufficient/ambiguous evidence. No global `+38`, `+512`, or other size allowance.

## Transaction algorithm / failure contract (SEM-001-MOVE)

1. **Pre-Move:** choose mail by age (not a fixed number of messages), honor folder inclusion (Inbox, POP3 Sent Items, user folders), year-based PST naming `<account>.Archive-YYYY.pst` with safe rollover `-02`, `-03`, etc. Check capacity + safety margin; never assume PSTs are limitless.
2. Capture immutable content/attachment/identity witness once. Persist a durable per-message Intent/attempt claim **before** the single Outlook move; guard original source and destination folder/store scope; optional `-WhatIf` must make **no** Move or claim.
3. Execute **exactly one** COM move when independently authorized. A COM exception or process exit after an attempted move is **ambiguous**, never permission to retry. Never reissue `MailItem.Move` based on source absence or a changed size.
4. **Independent post-Move read:** verify source-zero/destination-one with unique message correlation; check semantic content, attachment bytes SHA-256, metadata and significant flags. Only after conclusive checks may a durable Completed/Reconciled event be appended as designed and tested. Preserve journal append-only SHA/flush invariants.
5. If required data is unavailable, content differs, identity is ambiguous, or operator cannot account for meaningful changes: stop with indeterminate state and preserve original evidence; no automatic retry, deletion, cleanup, journal patch, or global waiver. A manual per-fixture decision must be separate, immutable, hash-pinned and **does not alone permit a new Move or production**.
6. Physical PST file size may remain unchanged until Outlook compaction. Track **logical item removal, source free space and physical size after optional supported compaction** separately. Compaction requires backup/verification and is not a side effect of a successful `Move`.

## Verified disposable observations (not proof of a universal rule)

| Case | Before `MailItem.Size` | After | Difference | Result |
|---|---:|---:|---:|---|
| PlainSmall | 6768 | 6806 | +38 | independent zero-source/one-target and content review |
| UnicodePlain | 6880 | 6918 | +38 | independent zero-source/one-target and content review |
| HtmlBody | 8599 | 8637 | +38 | independent zero-source/one-target; 15-property MAPI compare: 9 same, 3 changed, 3 unavailable; Outlook `HTMLBody` matched |
| Attachment1K **before** any move | 8122 | 8634 (still source) | +512 | BW4k7a two stable live source witnesses, same 1024 attachment bytes (SHA256 `8e3ff753449392a97fa89b9ccb72f2382d22c9c864d7f8733aca32e4b33305c9`), zero other witness differences. No Move, claim, or acceptance. |

BW4k7a returned `OnlySourceMailItemSizeDriftUnapproved` with original SourceEvidence SHA256 `0c81632bceb7553d2d6bd44841c4ed06064d834cdfe1a4b3d4c04c6d1f049ae0`; `SizeDriftAccepted=False`. No assertion of why +512 occurred; no retrospective recapture of original source witness.

## Release gates (SEM-001-CI)

- Windows PowerShell 5.1 STA + PSScriptAnalyzer + Pester, every new/modified PS file UTF-8 BOM (`TZ-ENC-001`); original legacy immutable exception unchanged.
- Unit and synthetic fault matrix for identity, body/HTML, recipients, attachments/hash, flags, size-only changes, unavailable properties, source-zero/target-one and interruption states. Reject a falsely successful CI if Pester tests or containers fail.
- No deployment of archive worker until manual integration on disposable PST, multi-item batch/crash/resume, Sent Items, annual rollover, capacity and physical size/compaction validation pass.
- The isolated `BW4k7b` work validates a **read-only classification policy only**. No existing historical source witness / claim is re-authored; no production flag changes; any content match does not automatically become a writer permit.

## BW4k7c constrained manual size decision (2026-11-02)

An **operator may separately acknowledge** a proven size-only source-side difference for exactly the original disposable Attachment1K TestId `87e72fd0-9e77-4098-a403-cbe99870b9e7` with immutable source evidence and identical payload SHA256. This is a distinct, append-once **decision file** (not a new original witness, not a journal completion, not a source-field rebaseline) after repeating the original independent Outlook read-only evidence **twice**. The specifically observed discrepancy is `8122 -> 8634` (+512 bytes) in the source PST only. Such an acknowledgment **NEVER** grants WriterPermit, new Move or production enablement; it does not assert full recipient/semantic-flag coverage or physical PST durability. Verification requires user-supplied immutable SHA256 of the decision file and another fresh read-only source check. `Review` is the safe default; `Accept` requires separate explicit operator text, `Verify` never writes. See [BW4k7c runbook](2.6.5-bw4k7c-exact-source-size-decision.md).

## BW4k7d supplementary To/Cc/Bcc and user-visible flag proof

Full ordered Outlook recipients and significant user state are separately sampled read-only before any future source snapshot. Enforce message READ/HASATTACH bit consistency, record user-visible categories, importance, sensitivity, follow-up and reminder indicators. The original BW4k7c SHA `29c0c00ed73afe8b154888d335dbed24935d41fdd8cebcc82fd02dcf4afb22b6` is independently verified. Two matching reads do not constitute persistent baseline, postmove preservation, or producer-grade flag coverage; fail closed if required fields are unavailable. [BW4k7d runbook](2.6.5-bw4k7d-recipients-flags-readonly.md).

## BW4k7e independent immutable source digest snapshot

After operator-verified BW4k7d read-only source evidence, pin exact observed ordered recipient and user-state digests to one independent immutable, SHA256-verified source-only JSON file. Only an explicit separate operator action may write this record once. `Review` alone never persists; `Verify` reads and compares independently against **current** live source evidence. The original BW4j/BW4k source witnesses, 3 old Move claims, and BW4k7c size acknowledgment must not be rewritten. Matching source-side hashes cannot by themselves prove postmove/destination identity or authorize Move/production. [BW4k7e](2.6.5-bw4k7e-immutable-semantic-source.md).

## BW4k7f read-only precreated empty target PST preflight

A source semantic baseline is not a Move permit. Before any future one-shot disposable Move, twice independently verify source semantic snapshot SHA `fa6fbc343a16c0d19a9fa369b0bcb595d40647fbd8e9a6c9b66ea4851761e4ac`, original +512 decision, immutable source evidence and previous three claims. Require exact existing mounted destination PST and one empty top-level destination folder, source-one/target-zero with unique InternetMessageId and exact EntryID; ambiguous/nonempty destination fails closed. No implicit PST creation, mount, claim or MailItem.Move, even if `-WhatIf` passes. [BW4k7f runbook](2.6.5-bw4k7f-empty-target-no-move.md).
