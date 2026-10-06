# CI and quality gates

`.github/workflows/ci.yml` runs on every pull request and every push to `main`. The `main` ruleset
requires its test jobs, so a merge is blocked on any of:

| Job | Gate | Fails when |
|---|---|---|
| Library Tests | tests | `xcodebuild test -scheme PurseSecureFields` fails on the newest iPhone simulator |
| Demo UI Tests | consumer build + UI tests | `xcodebuild test -project Demo/Demo.xcodeproj -scheme DemoUITests` fails on the same simulator |
| Release build (macos-15) | release toolchain | `scripts/build-xcframework.sh` — what `release.yml` builds, unsigned — fails on `macos-15` |

The release builds on `macos-15` on purpose: an older Xcode writes a `.swiftinterface` more
merchant toolchains can import. That compiler is not the one the test jobs use (`macos-26`), so
code that Xcode 26 accepts can still fail at release time — Headless Checkout iOS v1.2.0 did, on a
Swift 6.1 concurrency error. `Release build (macos-15)` catches that on the pull request instead.

Both boot the newest iPhone simulator through `.github/actions/ios-simulator`, which waits for the
boot to finish so a slow boot is not reported as a test failure. `DemoUITests` waits for the form
after each launch and for keyboard focus before typing. The hosted simulator's test runner still
hangs now and then on its first launch (`kAXErrorIPCTimeout`, "Failed to terminate"), so a failing
UI test is retried once (`-retry-tests-on-failure -test-iterations 2`): a real regression fails both
attempts, and a retried pass still shows as `failed` in the log.

## Pull request titles

Merges into `main` are squash-only, so a pull request's **title** becomes the commit on `main`, and
release-please reads it to decide the next version and the changelog section. `PR title`
(`.github/workflows/pr-title.yml`, a required check) fails unless the title is a Conventional Commit:
`<type>(<optional scope>)<optional !>: <description>`, with type one of `feat`, `fix`, `perf`,
`revert`, `docs`, `refactor`, `test`, `ci`, `build`, `chore` or `style`. It reruns when the title is
edited. A title that would fail here — `Feat/monitoring`, a branch name — releases nothing.

## Dependencies

`.github/workflows/dependencies.yml` runs `Dependency review` on every pull request: it fails when
the change adds or moves a dependency to a version with a known **high** or **critical**
vulnerability. GitHub reads `Package.resolved` directly, so — unlike Android — there is no graph to
submit first. The SDK declares no third-party source dependency in `Package.swift` today, so the
review covers the GitHub Actions the workflows use, and will cover the first package added.

Dependabot (`.github/dependabot.yml`) proposes weekly updates of the pinned GitHub Actions only (there
is no Swift package to watch), under a `ci:` prefix that keeps them out of the changelog.

`.github/workflows/codeql.yml` scans **Swift** and the **workflows** (`actions`) on every pull
request, every push to `main` and weekly. It is an advanced setup on purpose: GitHub's default setup
builds Swift with `swift build`, which fails for an iOS-only package, so the Swift job builds the
`PurseSecureFields` scheme for the simulator instead. Code scanning must be enabled with **default
setup off** — GitHub rejects advanced-setup results while default setup is on.

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

**`main` ruleset** ("Main prorection", Settings → Rules → Rulesets):

- no deletion, no force-push, no bypass
- pull request required, **1 approval**, **review from a code owner**, approvals dismissed on a new push
- status checks, **strict** (branch up to date with `main`): `Library Tests`, `Demo UI Tests`,
  `Dependency review`, `CodeQL (swift)`, `CodeQL (actions)`
- code scanning: CodeQL, blocking on high or critical security alerts and on errors

**`release tags` ruleset** on `refs/tags/v*` and `refs/tags/sdk-v*`: creation, update and deletion
restricted, bypass for the **repository admin** role only. SPM resolves a version from its `v*` tag,
so moving one changes the code every merchant gets. Both legitimate tag writes go out as
`RELEASE_PLEASE_TOKEN`, an admin's token: release-please creating `sdk-vX.Y.Z` on `main`, and
`release.yml` creating `vX.Y.Z` on the binary-target commit (see
[release.md](release.md#two-tags-per-version)). Neither is ever moved. The GitHub Actions app is
deliberately **not** a bypass actor: `GITHUB_TOKEN` belongs to every workflow run, and a workflow on
any branch can ask for `contents: write`, so that bypass would let anyone with write access write a
release tag.

**`release-please` environment**: no reviewers, deployments from `main` only. It holds a copy of
`RELEASE_PLEASE_TOKEN`, so only `release-please.yml` running on `main` can read it. Why this is a
separate environment from `release`:
[release.md](release.md#why-two-environments-release-please-and-release).

**`release` environment**: required reviewers `@UpStreamPay/pci-dss`, self-review prevented,
deployments only from `sdk-v*` tags. It holds the `APPLE_SIGNING_*` secrets and the other copy of
`RELEASE_PLEASE_TOKEN`. It must exist **before** a workflow naming it runs, otherwise GitHub
creates it with no protection — the same goes for `release-please`. Read it back after changing
it: an environment that exists is not one that is protected (v1.10.0 shipped through an empty one).

**Code security**: code scanning (CodeQL, default setup off — see [Dependencies](#dependencies)),
secret scanning and push protection on; Dependabot security updates on. The repository is public, so
none of these needs GitHub Advanced Security.

**Actions** (Settings → Actions → General): the default `GITHUB_TOKEN` is read-only and workflows
cannot approve pull requests.
