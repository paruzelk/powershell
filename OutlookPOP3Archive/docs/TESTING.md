# Testing — 2.6.1-PREVIEW1a

Run in Windows PowerShell 5.1 under the intended Windows user:

```powershell
.\Invoke-CI.ps1
.\Invoke-OPAWorkerSelfTest.ps1
.\Invoke-OPAWorkerSelfTest.ps1 -IncludeOutlookProbe -TimeoutSeconds 30
.\OutlookPOP3Archive.ps1 -Mode Plan -ProfileName 'Outlook' -Limit 50
.\OutlookPOP3Archive.ps1 -Mode Auto -ProfileName 'Outlook' -WhatIf
```

CI begins with a build/release/schema/documentation consistency gate and forbidden-artifact check. It retains parser/generic collection safety, PSScriptAnalyzer (if installed) and all prior archive Pester tests. 2.6.0-PREVIEW1a previously passed 170 tests on ADMIN-5; 2.6.1 adds a control suite and extra release tests. No tests move real Outlook messages.

Self-test runs synthetic Ping, Echo, Fail, Delay and new controlled status checks. `-IncludeOutlookProbe` is opt-in and may start Outlook; it only reads account/store counts. For failure simulation Pester exercises `Crash` and forced `Delay` timeout in a disposable worker. Do not exercise forced worker termination against actual mail mutations.

Unverified scenarios: real PST capacity rollover, deep folder integration, COM Move timeout and reconciliation, OS power-loss recovery and Outlook Compact. FIX13b remains baseline for actual mail moves.
