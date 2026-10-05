# Release

How to cut a release of the Vault iOS SDK.

> This guide is for **SDK contributors**. Merchants integrating the published SDK do not need it —
> start with [Getting Started](../integration/getting-started.md).

---

## Overview

The release process is fully driven from GitHub:

| Step | Trigger | What happens |
|---|---|---|
| 1 | Push to `main` | release-please opens or updates a release PR with a changelog and version bump |
| 2 | Merge the release PR | release-please creates the GitHub Release and tag (e.g. `v1.1.0`) |
| 3 | GitHub Release published | A codeowner approves the `release` environment; CI then builds a signed XCFramework, computes its checksum, and updates `Package.swift` to a binary target pointing to the new release |

Merging the release PR triggers the release; a codeowner then approves it before anything is built
or signed (see [Release approval](#release-approval)).

---

## Table of Contents

- [Prerequisites (one-time setup)](#prerequisites-one-time-setup)
  - [Apple Distribution certificate](#apple-distribution-certificate)
  - [GitHub secrets](#github-secrets)
  - [Release approval](#release-approval)
  - [Why two environments, `release-please` and `release`](#why-two-environments-release-please-and-release)
- [Versioning](#versioning)
- [Step 1 — Push to main](#step-1--push-to-main)
- [Step 2 — Merge the release PR](#step-2--merge-the-release-pr)
- [Step 3 — CI builds and signs the XCFramework](#step-3--ci-builds-and-signs-the-xcframework)
- [Verifying the signature locally](#verifying-the-signature-locally)
- [Verifying the SPM checksum](#verifying-the-spm-checksum)

---

## Prerequisites (one-time setup)

### Apple Distribution certificate

The XCFramework device slice must be signed with an Apple Distribution certificate — required for
PCI SSF compliance and expected by Xcode (unsigned binary targets produce a warning in Xcode 15+).

Generate or locate the certificate in your Apple Developer account
([developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles →
Certificates → + → Apple Distribution):

```bash
# Export the certificate + private key as a .p12 from Keychain Access:
# 1. Open Keychain Access → My Certificates
# 2. Right-click "Apple Distribution: <Your Team Name>" → Export
# 3. Choose .p12 format and set a strong password
# 4. Save as signing-cert.p12

# Base64-encode it for the CI secret:
base64 -i signing-cert.p12 | pbcopy
# Paste into the APPLE_SIGNING_CERT_P12_BASE64 secret of the `release` environment (see below)

# Check the identity is valid (CI signs with the first valid one it finds):
security find-identity -v -p codesigning
# Look for the line starting with: Apple Distribution: <Team Name> (<Team ID>)
```

### GitHub secrets

**Settings → Environments → the environment → Environment secrets.** None is organisation-wide,
and none is a repository secret.

| Secret | Where | Value |
|---|---|---|
| `RELEASE_PLEASE_TOKEN` | `release-please` **and** `release` environments (the same value in both; never a repository secret) | Fine-grained PAT on this repository alone with **Contents**, **Pull requests** and **Issues: Read and Write**, so CI runs on the release PR and the published release triggers `release.yml` (events raised by `GITHUB_TOKEN` start no workflow). Its account must be a repository admin: the `v*` tag ruleset lets only admins create or move a tag, and both release-please and `release.yml`'s retag write one. It expires — put the rotation in a calendar, and update both copies. |
| `APPLE_SIGNING_CERT_P12_BASE64` | `release` environment | The Apple Distribution certificate **and its private key**, exported as `.p12`, base64-encoded |
| `APPLE_SIGNING_CERT_P12_PASSWORD` | `release` environment | The `.p12` export password |

The workflow picks the first valid codesigning identity in the imported `.p12`, so there is no
identity secret to keep in sync.

`release.yml` checks its three secrets inside the gated job and **fails** with their names when one
is missing, instead of dying inside the certificate import or at the retag.

`GITHUB_TOKEN` covers the asset upload, under the job's `contents: write`. The tag move does not use
it: `GITHUB_TOKEN` cannot bypass the `release tags` ruleset (see
[ci.md](ci.md#repository-settings)). `RELEASE_PLEASE_TOKEN` is used for that one `git push` only and
never given to checkout, so it is not in `.git/config` while package code builds.

### Release approval

`release.yml` runs in the **`release` environment**. Each run waits until a member of
`@UpStreamPay/pci-dss` approves it under **Actions → the run → Review deployments**; GitHub emails
the reviewers. The person who started the run cannot approve it, and only `v*` tags may deploy to
the environment (PCI-DSS 6.5.1).

**The owner of `RELEASE_PLEASE_TOKEN` can never approve a release.** release-please publishes the
GitHub release with that token, so GitHub counts its owner as the person who started every release
run, and *Prevent self-review* excludes them. Another member of `@UpStreamPay/pci-dss` approves.
Do not turn self-review prevention off to work around it. A GitHub App instead of a personal token
would start releases as `<app>[bot]` and let every reviewer approve; it needs an org admin to create.

The environment must be configured **before** a workflow naming it runs: GitHub creates a missing
environment on the first run, with no protection at all. Configuring it is not enough either — read
it back. v1.10.0 was signed and published without any approval because `release` existed with no
reviewers and no tag policy when its release ran.

Two more guards keep unreviewed or untrusted output out of a release:

- **The workflow refuses a tag that is not on `main`.** Only code that went through a reviewed PR
  is built and signed.
- **It signs only with a valid identity.** An expired or untrusted one would still sign, and ship
  a signature no consumer can trust.

Around them, repository settings (applied once by an admin, see [ci.md](ci.md#repository-settings)):
the `main` ruleset and the `v*` tag ruleset.

### Why two environments, `release-please` and `release`

SPM resolves a version from the git tag itself: moving `v1.10.0` changes what every merchant
resolving 1.10.0 gets. Only the `release tags` ruleset prevents that, and its bypass must be a token
no branch workflow can read:

- **Not the GitHub Actions app.** `GITHUB_TOKEN` belongs to every workflow run, and a workflow on
  any branch can ask for `contents: write`, so that bypass would let anyone with write access move a
  release tag.
- **Not a repository secret.** `RELEASE_PLEASE_TOKEN` is an admin's token, so it bypasses an
  admin-only ruleset, and a workflow pushed on any branch can read a repository secret. An
  environment secret is readable only by a job allowed to deploy to that environment.

Both jobs that need the token must then run under different rules, and an environment holds only
one set of rules (one reviewer list, one list of refs allowed to deploy):

| | `release-please` | `release` |
|---|---|---|
| Job | `release-please.yml` | `release.yml` |
| Runs | on every push to `main`, unattended | on a published release (`v*` tag) |
| Approval | none: it only opens or updates the release PR, which is reviewed anyway | `@UpStreamPay/pci-dss`: it signs and publishes binaries |
| Deploys from | `main` | `v*` tags |
| Secrets | `RELEASE_PLEASE_TOKEN` | `RELEASE_PLEASE_TOKEN`, `APPLE_SIGNING_*` |

Every way of collapsing them into one gives one of the jobs the wrong rules:

- **One environment with reviewers** (`main` and `v*`): every merge to `main` waits for a pci-dss
  approval before release-please can run. An approval per merge, for a job that publishes nothing,
  trains reviewers to click through the one approval that matters.
- **One environment without reviewers**: the release loses its approval gate (PCI-DSS 6.5.1).
- **No environment for release-please, token as a repository secret**: a workflow pushed on any
  branch can read a repository secret, and this one is an admin's token that bypasses the `release
  tags` ruleset.

A job also runs in exactly one environment, so `release.yml` cannot borrow the token from
`release-please` — and it runs from a tag, which that environment's `main`-only policy rejects.

The cost is **two copies of the same token**: rotate them together. A GitHub App (short-lived
installation tokens, nothing to rotate) would remove the rotation but not the two environments; it
needs an org admin to create.

The Android SDK keeps a single environment, and that is not an inconsistency: Maven Central is
immutable, so a moved tag there changes nothing merchants download. Here the tag *is* the release.

---

## Versioning

The version is **not stored in any file**. It is computed automatically from
[Conventional Commits](https://www.conventionalcommits.org) by release-please and lives only in
the git tag. `Package.swift` is updated by CI after the release is created.

| Commit prefix | Version bump | Example |
|---|---|---|
| `feat!:` or `BREAKING CHANGE:` | Major | `1.2.3` → `2.0.0` |
| `feat:` | Minor | `1.2.3` → `1.3.0` |
| `fix:`, `perf:`, `refactor:` | Patch | `1.2.3` → `1.2.4` |
| `docs:`, `chore:`, `style:`, `test:`, `ci:` | No release | — |

Pushes that contain only non-releasable commits produce no release PR and no tag.

### Known issue: the release PR lists the whole history

release-please finds the previous release by walking `main` back to the commit its tag points to.
`release.yml` then moves every tag onto its binary-target commit (the `Package.swift` rewrite), which
is never on `main`, so release-please never finds it. It walks back to the first commit instead:
every release PR lists the whole history in its changelog, and any push to `main` — even `ci:` or
`docs:` only — reopens a release PR for the next minor version, because old `feat:` commits count
again. Until this is fixed, **check the changelog of every release PR**, and close it when `main`
holds nothing new to ship (#55 and #56 were closed for that reason).

---

## Step 1 — Push to main

Merge a branch with Conventional Commit messages into `main`. release-please runs on every push
and either opens a new release PR or adds the new commits to an existing one.

The release PR contains:
- A `CHANGELOG.md` update with the new version's entry
- A `.release-please-manifest.json` bump

Do not merge the release PR immediately — wait until all intended commits for this version
are included.

---

## Step 2 — Merge the release PR

When the version is ready to ship, merge the release PR. release-please:

1. Creates an annotated git tag (e.g. `v1.1.0`)
2. Creates a GitHub Release with the changelog as the body
3. Sets the release status to `published` — this fires the `.github/workflows/release.yml`
   workflow

---

## Step 3 — CI builds and signs the XCFramework

`.github/workflows/release.yml` triggers on `release: published`, then waits for a codeowner to
approve the `release` environment:

1. Checks out the tagged commit, and fails unless it is on `main`
2. Fails with their names if any of its three secrets is missing
3. Imports the Apple Distribution certificate from `APPLE_SIGNING_CERT_P12_BASE64` into a
   temporary CI keychain
4. Builds the device (`ios-arm64`) and simulator (`ios-arm64_x86_64-simulator`) archives unsigned,
   then repackages `Modules/`, the resource bundle and the privacy manifest into each framework
5. Creates the XCFramework with `xcodebuild -create-xcframework`, then signs the whole bundle with
   `codesign` using the first **valid** identity from the certificate
6. Zips the XCFramework and computes its SHA-256 checksum with `swift package compute-checksum`
7. Verifies the XCFramework (`.swiftinterface` and resource bundle in every slice, and
   `import PurseSecureFields` compiles against it)
8. Rewrites `Package.swift` to a `.binaryTarget` pointing to the GitHub Release download URL
   and the computed checksum
9. Commits the updated `Package.swift`, force-tags the release commit, and force-pushes the tag
   with `RELEASE_PLEASE_TOKEN` (the only token the `release tags` ruleset lets through)
10. Uploads `PurseSecureFields.xcframework.zip` to the GitHub Release as a binary asset

After CI completes, the GitHub Release contains the signed XCFramework zip and the updated
`Package.swift` (on the tag) declares the binary target. Merchants who add the package in
Xcode will get the signed XCFramework.

---

## Verifying the signature locally

After a release, verify the XCFramework is properly signed:

```bash
# Download the zip from the GitHub Release
curl -L https://github.com/UpStreamPay/purse-securefields-ios/releases/download/v1.x.x/PurseSecureFields.xcframework.zip -o PurseSecureFields.xcframework.zip
unzip PurseSecureFields.xcframework.zip

# Verify the device slice signature
codesign -dv --verbose=4 \
  PurseSecureFields.xcframework/ios-arm64/PurseSecureFields.framework/PurseSecureFields

# Expected output includes:
# Authority=Apple Distribution: Upstream Pay (XXXXXXXXXX)
# Authority=Apple Worldwide Developer Relations Certification Authority
# Authority=Apple Root CA

# Confirm the simulator slice is unsigned (expected — not an error)
codesign -dv --verbose=4 \
  PurseSecureFields.xcframework/ios-arm64-simulator/PurseSecureFields.framework/PurseSecureFields
# Expected: code object is not signed at all
```

---

## Verifying the SPM checksum

Verify that the checksum in `Package.swift` matches the downloaded artifact:

```bash
swift package compute-checksum PurseSecureFields.xcframework.zip
# Compare with the `checksum:` field in Package.swift for the same release tag
```

A mismatch means either the artifact or the Package.swift was modified after the CI run. Do not
distribute the release if checksums do not match.

---

## See also

- [CI and quality gates](ci.md) — what blocks a merge, and the repository settings
