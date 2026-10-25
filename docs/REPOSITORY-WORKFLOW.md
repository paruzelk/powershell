# Repository workflow: paruzelk/powershell

This repository is a **PowerShell monorepo**: OutlookPOP3Archive, OutlookIMAPSync, and ServerMaintenance have independent versions and independent releases.

## Development: GitHub Flow

- **`main`**: the reviewed and CI-checked integration branch, reflecting currently accepted code for all projects. It does **not** mean that every project's current build is a stable release. Production-ready versions are identified separately by immutable project-specific release tags.
- Create a short-lived topic branch **from current `main`** for new work:
  - `feature/outlookpop3archive-2.6.4-recovery`
  - `fix/outlookpop3archive-restart-scan`
  - `docs/repository-workflow`
- Open a Pull Request **to `main`** with scope, safety implications, test commands, observed results and links to relevant checks.
- Wait for required CI to pass and review the change. If changing code after the test, run CI again on the new exact commit. Merge only when ready. Prefer a normal merge for historically significant commits and independently verified source identities; use squash for small branches where retaining each development commit is not necessary.
- Delete merged temporary feature/fix branches once a tag and necessary references preserve their histories.
- Do not routinely merge via a perpetual `develop`; there is no separate deployment environment or large parallel team that justifies GitFlow complexity.

### Current migration (do not rewrite existing history)

1. Existing `main` still contains OutlookPOP3Archive `2.5.7-FIX13b`; `develop` has the older `2.6.1-PREVIEW1a`. Existing OutlookPOP3Archive 2.6.2/2.6.3 branches are *ahead of* `main`, not independent conflicting repositories.
2. Retarget **PR #1 (2.6.2)** to `main`; review and test its **actual merge result**, then merge. PR #2 (2.6.3) is currently **stacked** on the 2.6.2 feature branch. Only after PR #1 lands, retarget **PR #2 to `main`**, run its CI on the merge result, then merge.
3. Preview 2.6.3 is already available on `release/2.6.3-preview1`. Keep this historical branch and its ZIP until a tag and official GitHub Release exist. No rebases or force-pushes to verified source commits.
4. Only after migrating and verifying each history, consider retiring obsolete `develop` and `package/*` branches. Do not delete them merely to clean up the branch list.
5. Future `2.6.4` work should branch from the accepted `main`, rather than from package or release branches.

## Releases: tags + GitHub Releases, not one branch per ZIP

Each project gets its **own version namespace** to avoid collisions in the monorepo:

- `outlookpop3archive-v2.6.3-preview1`
- `outlookpop3archive-v2.6.4`
- `outlookimapsync-v1.0.0`

After merging a reviewed source revision to `main`, identify the **exact validated commit** and create an annotated Git tag pointing at that commit; do not imply a tag is a branch. In GitHub **Releases**, use that tag to publish a `PREVIEW` prerelease or a stable release with release notes, exact source SHA, the ZIP and `SHA256SUMS.txt` or matching `.sha256` file. Keep releases immutable if enabled; never overwrite the bytes of an existing published version.

The source commit/inventory SHA-256 and ZIP SHA-256 are different concepts. A local Windows-built ZIP and an independently assembled GitHub ZIP may have **different ZIP checksums**, even when they package byte-identical sources. Identify both explicitly; do not claim an unuploaded local ZIP is available in GitHub Releases.

For OutlookPOP3Archive `2.6.3-PREVIEW1`:
- Tested source commit: `eb163aee318c63f1c4c625f10d78befcc3f1be44`.
- Independently verified complete source inventory SHA256: `b99d0863e9c414d812f04fe9c613530d4ff1b333528600293da3bf40c31ecb12`.
- User-verified Windows PowerShell 5.1 Pester: 281/281 tests in 26 containers.
- The existing `release/2.6.3-preview1` branch contains a separately assembled ZIP. Do not replace it or change the tested source commit. Add the official tag/Release as a **separate** step after code-review integration.

Long-lived `release/*` branches are optional, used only when a supported older version genuinely requires ongoing hotfix/backport work. ZIP-only `package/*` branches are not created for future builds. For each PR, use Actions artifacts or PR attachment storage for temporary output, and GitHub Releases for versioned distribution.

## Automated Windows PowerShell 5.1 CI

The workflow `.github/workflows/outlookpop3archive-ps51.yml` tests changes to the OutlookPOP3Archive project on a Windows Server GitHub Actions image, explicitly running **Windows PowerShell 5.1** (`shell: powershell`, not `pwsh`). It installs Pester 6.2.0 and PSScriptAnalyzer, then runs `OutlookPOP3Archive/Invoke-CI.ps1`. For newer builds the command takes the current `RELEASE.json` Build, so the project's strict Pester container count and source compatibility gates are enforced.

This hosted runner test is **not** a real Outlook COM/PST test (no installed/interactively configured Outlook). COM integration remains a separate manual disposable-PST gate, recorded in the PR. A self-hosted Windows runner may be substituted in the workflow only after labels, isolation, permissions and the required modules are verified.

### Suggested GitHub repository settings (must be configured by an admin)

**Settings → Rules → Rulesets** (or Branches → branch protection) for `main`:
- Require PR before merging.
- Require the unique `OutlookPOP3Archive / windows-ps51` job when it applies; do not select a required check that is conditionally *absent* from unrelated project PRs. For a monorepo, configure appropriate per-project always-present checks before enabling globally required status checks.
- Disable force pushes and branch deletion.
- Require review or conversation resolution as appropriate to the number of actual reviewers. Do not configure a mandatory second reviewer when only one maintainer has access.
- Enable automatic deletion of *merged* feature branches only after dependent stacked PRs have been reconciled.

For tags: protect `outlookpop3archive-v*` against rewriting/deletion. Branch protection and GitHub Releases permissions must be configured in GitHub Settings; a repository Markdown document does not enforce them.

## Safety and promotion gates for OutlookPOP3Archive

- CI success establishes Pester/analyzer/parse compatibility for **that commit**; it is **not proof** that a production Outlook MailItem.Move worker is safe.
- Preserve operation journals and archive PST evidence. Disputed/ambiguous Move state remains fail-closed, with no automatic retry.
- Do not enable Worker Archive/Resume/Auto flags without separate real Outlook crash/recovery tests and approved PR.
- Keep publication and operational data separate; never commit PSTs, checkpoint JSONL files, credentials or private email content.
