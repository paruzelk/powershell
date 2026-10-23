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

## 2.6.3 source provenance safeguard

Never use `-SourceCommit` simply as a label for a ZIP assembled from an arbitrary extracted directory. A previous build produced a misleading `gd4bc6974` filename after running **272** tests in **25** containers and packaging **70** files from the older `g8e4be719` directory. The requested Git revision actually had **26** test containers and **71** source files.

`New-OPABuildPackage.ps1` now requires an additional **independently verified** `-ExpectedSourceInventorySha256` whenever `-SourceCommit` is supplied. This digest covers each selected file's exact SHA256 and canonical relative path, with ordinal sorting and UTF-8 LF encoding. Use the published pinned SHA from the GitHub commit; computing the expected digest from the same unverified working directory would defeat independent verification.

```powershell
.\Invoke-CI.ps1 -ExpectedBuild '2.6.3-PREVIEW1'
.\New-OPABuildPackage.ps1 `
    -ExpectedBuild '2.6.3-PREVIEW1' `
    -SourceCommit '<full 40-character Git commit SHA>' `
    -ExpectedSourceInventorySha256 '<independently provided 64-character source digest>' `
    -OutputDirectory (Join-Path (Get-Location).Path 'dist')
```

CI additionally checks the expected total number of test containers and Pester cases recorded in `RELEASE.json`, so an incomplete test checkout fails before packaging. If the input source identity does not match, the packager aborts before creating any ZIP. An ordinary unpinned local package can still be made without `-SourceCommit`, but it must not be called an exact Git revision.
