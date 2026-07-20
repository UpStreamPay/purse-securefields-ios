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
| 3 | GitHub Release published | CI builds a signed XCFramework, computes its checksum, and updates `Package.swift` to a binary target pointing to the new release |

Merging the release PR is all you need to trigger a release. There is no manual publish step.

---

## Table of Contents

- [Prerequisites (one-time setup)](#prerequisites-one-time-setup)
  - [Apple Distribution certificate](#apple-distribution-certificate)
  - [GitHub secrets](#github-secrets)
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
# Paste into the APPLE_SIGNING_CERT_P12_BASE64 secret (see below)

# Find the full identity string (needed for APPLE_SIGNING_IDENTITY):
security find-identity -v -p codesigning
# Look for the line starting with: Apple Distribution: <Team Name> (<Team ID>)
```

### GitHub secrets

Add these four secrets to the GitHub repository (**Settings → Secrets and variables → Actions**):

| Secret | Used by | Value |
|---|---|---|
| `USP_GITHUB_ADMIN_ACCES_TOKEN` | release step | Fine-grained PAT with **Contents: Read and Write** on this repository. Needed because `GITHUB_TOKEN` cannot force-push tags. |
| `APPLE_SIGNING_CERT_P12_BASE64` | build step | Base64-encoded `.p12` containing the Apple Distribution certificate and private key |
| `APPLE_SIGNING_CERT_P12_PASSWORD` | build step | Password set when exporting the `.p12` |
| `APPLE_SIGNING_IDENTITY` | build step | Full certificate common name, e.g. `Apple Distribution: Upstream Pay (XXXXXXXXXX)` |

The `USP_GITHUB_ADMIN_ACCES_TOKEN` secret already exists. Only the three Apple signing secrets
are new for SDK-11958.

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

`.github/workflows/release.yml` triggers on `release: published`:

1. Checks out the tagged commit
2. Imports the Apple Distribution certificate from `APPLE_SIGNING_CERT_P12_BASE64` into a
   temporary CI keychain
3. Builds the device archive (`ios-arm64`) with `CODE_SIGN_IDENTITY=Apple Distribution`
4. Builds the simulator archive (`ios-arm64-simulator`, `ios-x86_64-simulator`) unsigned —
   Apple does not issue distribution certs for simulator binaries
5. Creates the XCFramework with `xcodebuild -create-xcframework -codesign "$APPLE_SIGNING_IDENTITY"`
   — this signs the device slice with the distribution certificate
6. Zips the XCFramework and computes its SHA-256 checksum with `swift package compute-checksum`
7. Deletes the temporary keychain
8. Rewrites `Package.swift` to a `.binaryTarget` pointing to the GitHub Release download URL
   and the computed checksum
9. Commits the updated `Package.swift`, force-tags the release commit, and force-pushes the tag
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
