# CI and quality gates

`.github/workflows/ci.yml` runs on every pull request and every push to `main`:

| Job | Gate | Fails when |
|---|---|---|
| Library Tests | tests | `xcodebuild test -scheme PurseSecureFields` fails on the newest iPhone simulator |
| Demo UI Tests | consumer build + UI tests | `xcodebuild test -project Demo/Demo.xcodeproj -scheme DemoUITests` fails on the same simulator |

Neither is a required check yet (see [Repository settings](#repository-settings)): a red PR can
still be merged.

## Dependencies

The SDK declares no third-party source dependency in `Package.swift`, so Dependabot
(`.github/dependabot.yml`) watches the pinned GitHub Actions only, weekly, under a `ci:` prefix that
keeps the updates out of the changelog. CodeQL runs as GitHub's default setup and scans the
workflows (`actions`).

## Workflow hygiene

- Every action is pinned by commit SHA with its version in a trailing comment.
- Every workflow declares `permissions:`, read-only unless a job needs more, and every job has a
  `timeout-minutes`.
- Untrusted text (a tag name, a branch name) reaches a script only through `env`, never through
  `${{ }}` interpolation into the script itself.
- No organisation-wide token: release-please uses a fine-grained token scoped to this repository
  (see [release.md](release.md#github-secrets)), stored only as an **environment** secret. A
  repository secret is readable by a workflow pushed on any branch; an environment secret only by a
  job allowed to deploy to that environment.

## Repository settings

Repository settings, not code — a repository admin applies them once. `.github/CODEOWNERS` makes
`@UpStreamPay/pci-dss` the owner of every file; the team has **write** access to the repository,
which CODEOWNERS needs to apply.

**`main` ruleset** ("Main prorection", Settings → Rules → Rulesets): no deletion, no force-push, no
bypass; pull request required, **1 approval**, **review from a code owner**. Not yet: `Library
Tests` and `Demo UI Tests` as required checks, and approvals dismissed on a new push.

**`release tags` ruleset** on `refs/tags/v*`: creation, update and deletion restricted, bypass for
the **repository admin** role only. SPM resolves a version from its tag, so moving one changes the
code every merchant gets. Both legitimate tag writes go out as `RELEASE_PLEASE_TOKEN`, an admin's
token: release-please creating the tag, and `release.yml` force-moving it onto the binary-manifest
commit. The GitHub Actions app is deliberately **not** a bypass actor: `GITHUB_TOKEN` belongs to
every workflow run, and a workflow on any branch can ask for `contents: write`, so that bypass would
let anyone with write access move a release tag.

**`release-please` environment**: no reviewers, deployments from `main` only. It holds a copy of
`RELEASE_PLEASE_TOKEN`, so only `release-please.yml` running on `main` can read it. Why this is a
separate environment from `release`:
[release.md](release.md#why-two-environments-release-please-and-release).

**`release` environment**: required reviewers `@UpStreamPay/pci-dss`, self-review prevented,
deployments only from `v*` tags. It holds the `APPLE_SIGNING_*` secrets and the other copy of
`RELEASE_PLEASE_TOKEN`. It must exist **before** a workflow naming it runs, otherwise GitHub
creates it with no protection — the same goes for `release-please`. Read it back after changing
it: an environment that exists is not one that is protected (v1.10.0 shipped through an empty one).

**Code security**: secret scanning and push protection on; Dependabot security updates on.

**Actions** (Settings → Actions → General): the default `GITHUB_TOKEN` is read-only and workflows
cannot approve pull requests.
