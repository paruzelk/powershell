# OutlookPOP3Archive 2.6.3-PREVIEW1

Source commit: `eb163aee318c63f1c4c625f10d78befcc3f1be44`
Source inventory SHA-256 (71 files): `b99d0863e9c414d812f04fe9c613530d4ff1b333528600293da3bf40c31ecb12`

## Windows verification — reported PASS
- Windows PowerShell 5.1 CI: 281 Pester tests / 26 containers; 0 failures, 0 skipped.
- Native New-OPABuildPackage.ps1: 71 files; exact source inventory digest matches.
- Native Windows ZIP (held by tester): `OutlookPOP3Archive-v2.6.3-preview1-dev-geb163aee.zip`, SHA-256 `428ad4e3ef329259bcb13ead399e819c0579a06cb5a36c1b59afba5d9d2d50c6`. This ZIP has **not** been uploaded to GitHub.
- GitHub ZIP `OutlookPOP3Archive-v2.6.3-preview1.zip` contains the same 71 verified source files, with new BUILD-INFO.json metadata; it has its **own different SHA-256** recorded in the sibling .sha256 file.

## Verified real Outlook COM diagnostics
- SourceOnly, DestinationCandidate after real Move but before Completed, BothPresent, Ambiguous — PASS using disposable PSTs.
- New Windows PowerShell process: replayed preserved unresolved Intent and returned Ambiguous with 1 source match, 2 archive matches; journal SHA-256 unchanged.
- All outcomes retain `AutomaticRetryAllowed=False` and `ProvenMoved=False`, requiring manual review.

## Limitations
- Worker MailItem.Move for archive/resume/auto is disabled; production archive engine remains FIX13b.
- No simulated Outlook process kill mid-Move, power loss, or production recovery proof.
- PREVIEW release, not promoted to stable or merged to main.
