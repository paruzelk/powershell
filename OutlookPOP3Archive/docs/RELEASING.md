# OutlookPOP3Archive — mandatory build and release procedure

Applies to every release and development ZIP from 2.6.2 onward. **Never package the whole `paruzelk/powershell` repository.** Only the `OutlookPOP3Archive` project may appear in the archive.

## Release checklist (strict gate)

1. Update `Core/Version.ps1` (application and any intentionally changed schema versions). Transaction and duplicate-index schema values must only change for actual format migrations.
2. Update `RELEASE.json`, `MANIFEST.txt`, the current heading in `README.md`, the active headings in `docs/ARCHITECTURE.md`, `docs/CONFIGURATION.md`, `docs/RECOVERY.md` and `docs/TESTING.md`. Historical information in `CHANGELOG.md` remains unchanged; append a new entry.
3. Review `Tests/Core/Version.Tests.ps1` and all `*.Tests.ps1` for hardcoded previous versions. Do not replace accurate historical examples in the changelog with the new version.
4. Remove obsolete files from the **Git source tree** via a reviewed commit: old `MANIFEST-RC1.txt`, `RELEASE-RC1.json`, `TEST-FIX*.md`, temporary reports, backup ZIPs and redundant build notes. Never blindly erase PST data, transaction checkpoints, `*.steps.jsonl`, DuplicateIndex or worker operation journals.
5. Run `Invoke-CI.ps1 -ExpectedBuild '<exact RELEASE.json Build>'` under **Windows PowerShell 5.1**. Both PSScriptAnalyzer and Pester 5+ are required. Failed/skipped/no tests, a missing analyzer or mismatched versions **stop the build**.
6. Use `New-OPABuildPackage.ps1` only after the version bump and full test run. This wrapper itself reruns mandatory CI, validates the intended build and stages only allowlisted files: root runtime scripts/metadata, `Core/*.ps1`, `Tests/*.Tests.ps1`, `docs/*.md`, and the two approved dotfiles.
7. The ZIP includes one top-level folder named `OutlookPOP3Archive-v<version>`, its `BUILD-INFO.json`, release metadata, source, tests and current documentation. The script also writes `<archive>.sha256`. Never overwrite an earlier ZIP.
8. Verify the ZIP name, contents, SHA-256, the exact source commit, and GitHub publication. Share a **direct ZIP download link** plus SHA-256 after uploading, never a ZIP containing unrelated GitHub projects.
9. Publish a Git tag or release branch matching the build after validation. Do not claim the package is production-ready until its gates are passed.

## Commands (example after bumping metadata)

```powershell
.\Invoke-CI.ps1 -ExpectedBuild '2.6.2-PREVIEW1'
.\New-OPABuildPackage.ps1 -ExpectedBuild '2.6.2-PREVIEW1' -OutputDirectory '.\dist' -SourceCommit '<GitCommitSha>'
```

The command deliberately fails if `Core/Version.ps1` still says `2.6.1-PREVIEW1a` while `-ExpectedBuild` is `2.6.2-PREVIEW1`. A feature branch is not an approved release merely because its Pester tests pass. For an internal snapshot, explicitly identify it as `dev` and include the short Git SHA in the filename.

**Packaging cleanliness:** the build deletes only its own newly created temporary staging directory. The source working directory and user Outlook data are never subject to automatic cleanup.

## Discovery failures are release failures

Mandatory CI must confirm the Pester run `Result=Passed`, all expected test containers were discovered and passed, `FailedContainersCount=0`, `FailedBlocksCount=0`, and no failed, skipped, inconclusive or not-run tests. Before Pester starts, all `*.Tests.ps1` files are parsed using the native PowerShell 5.1 parser. A syntax failure or discovery failure blocks ZIP creation even if `FailedCount=0` and other tests passed.
