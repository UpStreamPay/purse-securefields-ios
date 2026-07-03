# Distribution

How the Vault iOS SDK is published and why.

---

## Table of Contents

- [The competitive baseline](#the-competitive-baseline)
- [Distribution options on iOS](#distribution-options-on-ios)
- [SPM binary target vs source package](#spm-binary-target-vs-source-package)
- [Decision: SPM binary target via GitHub Releases](#decision-spm-binary-target-via-github-releases)
- [Signing requirement (PCI SSF)](#signing-requirement-pci-ssf)
- [What this requires in practice](#what-this-requires-in-practice)

---

## The competitive baseline

Every major iOS payment SDK is distributed via Swift Package Manager and CocoaPods:

| SDK | GitHub | SPM | CocoaPods |
|---|---|---|---|
| Stripe iOS | `stripe/stripe-ios` | Source | Podspec |
| Adyen iOS | `Adyen/adyen-ios` | Source | Podspec |
| Checkout.com frames | `checkout/frames-ios` | Source | Podspec |
| Primer iOS | `primer-io/primer-sdk-ios` | Source | Podspec |
| VGS Collect iOS | `verygoodsecurity/vgs-collect-ios` | **Binary target** | Podspec |

Most distribute open-source via SPM source packages. VGS, like us, distributes as a binary target.

---

## Distribution options on iOS

### Swift Package Manager (SPM)

Apple's native package manager, built into Xcode 11+. Zero friction for merchants — dependencies
are added in Xcode without any external tooling. Two modes:

**Source package:** `Package.swift` points to a git repository. SPM clones the repo and compiles
the source directly. Merchants see the source code.

**Binary target:** `Package.swift` declares a `.binaryTarget` pointing to a `.xcframework.zip`
on GitHub Releases. SPM downloads, verifies the checksum, and uses the pre-built XCFramework.
Merchants receive a compiled binary.

### CocoaPods

Ruby-based dependency manager, available since 2011. Requires the CocoaPods CLI, a `Podfile`,
and `pod install`. `Podfile.lock` must be committed to version-control. Still widely used in
legacy projects, but adoption of new libraries through CocoaPods is declining sharply in favour
of SPM.

### Carthage

Decentralised — merchants compile the framework themselves from the source repository. Very
low current adoption. Effectively unused for new projects.

### Private registries (Artifactory, GitHub Packages)

Appropriate for internal artifacts (CI-built snapshots, pre-release candidates). Require
credential configuration on the consumer side — a significant friction barrier for a
merchant-facing SDK.

---

## SPM binary target vs source package

|  | Source package | Binary target |
|---|---|---|
| Consumer setup | Zero — same as source | Zero — same as source, no extra tooling |
| Source visibility | Full source code | Binary only (source visible on `main` branch, not on tagged releases) |
| Build time (merchant) | Compiles SDK from source | None — pre-built |
| Reproducibility | Merchants can inspect every line | Merchants can verify checksum but cannot inspect compiled artifacts |
| Certificate signing | Not applicable (source) | XCFramework can be signed with Apple Distribution certificate |
| QSA review | Easy — source is public | Possible — source visible on `main`; QSA can inspect the build pipeline |

---

## Decision: SPM binary target via GitHub Releases

Distribute the Vault iOS SDK as a **signed XCFramework via SPM binary target**, hosted on
GitHub Releases.

**Rationale:**

1. **Zero merchant friction.** Adding the dependency in Xcode via the GitHub URL is identical to
   adding a source package — no extra tooling, no credentials.

2. **Integrity verification is built in.** SPM verifies the SHA-256 checksum embedded in
   `Package.swift` before using the downloaded artifact. Any tampering with the `.xcframework.zip`
   produces a checksum mismatch and Xcode refuses to resolve the package.

3. **Signed artifact satisfies PCI SSF.** The XCFramework device slice is signed with an Apple
   Distribution certificate (see [Signing requirement](#signing-requirement-pci-ssf)). This
   proves publisher identity and is a PCI Software Security Framework requirement for distributed
   payment components.

4. **No build-time SDK compilation for merchants.** Binary targets resolve instantly after
   download. Source packages require compiling the SDK on every clean build.

5. **Xcode warns on unsigned binaries.** Starting with Xcode 15, Xcode surfaces a warning for
   SPM binary targets that contain unsigned XCFrameworks. Shipping unsigned would be a visible
   integration friction.

**CocoaPods is not supported.** The CocoaPods ecosystem requires maintaining a Podspec and
publishing to the CocoaPods trunk registry. Given that all new iOS projects default to SPM and
CocoaPods adoption is declining, the maintenance cost is not justified by the integration gain.
Merchants using CocoaPods can adopt SPM for this dependency without affecting their other
CocoaPods dependencies.

**Why binary over source?** VGS uses the same binary target approach on iOS. A signed binary
targets a specific release — the checksum in `Package.swift` pins the exact artifact consumed.
Source packages are also pinned (to a tag), but the checksum covers the zip of the whole source
tree, not the compiled output. The binary target's checksum covers exactly what runs on the
device.

---

## Signing requirement (PCI SSF)

PCI Software Security Framework (SSF) requires that distributed software components are signed
to verify authenticity and integrity. For an iOS XCFramework:

- **Integrity** is provided by the SPM checksum (`swift package compute-checksum`). Every
  `Package.swift` release commit embeds the SHA-256 of the `.xcframework.zip`. Xcode verifies
  this before using the artifact.

- **Authenticity** is provided by Apple code signing. The XCFramework device slice is signed
  with an **Apple Distribution** certificate held by the Purse developer team. Consumers can
  verify the signature:

  ```bash
  codesign -dv --verbose=4 PurseSecureFields.xcframework/ios-arm64/PurseSecureFields.framework
  ```

The simulator slice (`ios-arm64-simulator`) cannot be signed with a distribution certificate —
Apple does not issue distribution signing for simulator builds. This is standard for all
signed XCFrameworks and is not a limitation of the Purse SDK specifically.

---

## What this requires in practice

1. **An Apple Developer account** with an active "Apple Distribution" certificate (used for
   App Store and enterprise distribution). The team's current distribution certificate is stored
   as a base64-encoded P12 in the GitHub repository secrets.

2. **Three GitHub secrets** (see [Release guide](release.md#prerequisites-one-time-setup)):

   | Secret | Value |
   |---|---|
   | `APPLE_SIGNING_CERT_P12_BASE64` | Base64-encoded Apple Distribution certificate + private key (.p12) |
   | `APPLE_SIGNING_CERT_P12_PASSWORD` | Password protecting the .p12 file |
   | `APPLE_SIGNING_IDENTITY` | Full certificate common name (e.g. `Apple Distribution: Upstream Pay (XXXXXXXXXX)`) |

3. **Xcode 14+ on the CI runner.** The `-codesign` flag for `xcodebuild -create-xcframework`
   was introduced in Xcode 14. The release workflow runs on `macos-15` (Xcode 16), which
   satisfies this requirement.

4. **Automatic versioning via release-please.** The version is derived from Conventional Commit
   prefixes. There is no version number to manually maintain. See [Release](release.md) for
   details.
