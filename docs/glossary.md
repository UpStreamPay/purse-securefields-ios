# Glossary

Quick explanations of iOS and Swift concepts used throughout this documentation.

---

## Swift Package Manager (SPM)

Apple's native dependency manager, built into Xcode 11+. Described by a `Package.swift` file at
the root of a repository. Dependencies are added in Xcode via **File → Add Package Dependencies**.
No extra tooling is needed — unlike CocoaPods or Carthage.

**Binary target:** An SPM target that resolves to a pre-built `.xcframework` zip rather than
compiling source code. The `Package.swift` for each Vault SDK release declares a binary target
pointing to the XCFramework on GitHub Releases.

---

## XCFramework

Apple's multi-platform bundle format (`.xcframework`). A single XCFramework can contain slices
for multiple platforms and architectures:

- `ios-arm64` — device builds (iPhone, iPad)
- `ios-arm64-simulator` — Simulator builds on Apple Silicon Macs
- `ios-x86_64-simulator` — Simulator builds on Intel Macs

SPM binary targets consume XCFrameworks directly. Consumers integrate the same file regardless of
their development machine.

---

## UIKit

Apple's foundational UI framework for iOS (pre-SwiftUI). Classes are prefixed `UI` — `UIView`,
`UITextField`, `UIViewController`. The Vault SDK is built on UIKit and works in both UIKit-based
and SwiftUI apps.

---

## UITextField

The standard iOS single-line text input control. `SecureBaseField` (the internal SDK base class)
subclasses `UITextField` and overrides `text` and `attributedText` getters to return `nil`,
preventing external code from reading card data even if a cast is attempted.

---

## SecureFieldsManager

The main SDK entry point. Initialised with a `SecureFieldsConfig`, it owns all card input
views and coordinates BIN lookup, validation, and tokenization. Analogous to `SecureFieldsAndroid`
in the Android SDK.

---

## SecureFieldsDelegate

A Swift protocol your view controller adopts to receive events from `SecureFieldsManager`. Analogous
to `SecureFieldsListener` in the Android SDK. All methods except `secureFieldsDidTokenize` and
`secureFieldsDidFail` have default no-op implementations.

---

## UIViewController

The base class for any screen in a UIKit app — like a web page's controller. The SDK's views are
`UIView` instances you embed into your existing view hierarchy; no additional view controller is
required.

---

## App Transport Security (ATS)

An iOS platform feature that enforces HTTPS (and TLS 1.2 minimum) for all outbound HTTP
connections made by the app. Active by default on iOS 9+. No SDK configuration is required — ATS
blocks cleartext HTTP automatically.

---

## SPKI Pinning

SubjectPublicKeyInfo pinning. Instead of pinning the full certificate (which changes on renewal),
SPKI pinning anchors to the server's public key hash — which is stable across certificate renewals
as long as the same key pair is reused. The SDK supports optional SPKI pinning via
`SecureFieldsConfig.pinnedPublicKeyHashes`.

---

## Privacy Overlay

A `UIBlurEffect` overlay the SDK places over all card input views whenever the app enters the
background (`UIApplication.willResignActiveNotification`) or screen recording is active
(`UIScreen.capturedDidChangeNotification`). Prevents card data from appearing in app-switcher
thumbnails and screen recordings. Controlled by `SecureFieldsManager.obscuresOnBackground`.

---

## Conventional Commits

A commit message convention used to drive semantic versioning. The SDK uses release-please to
parse commit subjects since the last tag and determine the next version:

| Prefix | Version bump |
|---|---|
| `feat!:` / `BREAKING CHANGE:` | Major (`1.0.0` → `2.0.0`) |
| `feat:` | Minor (`1.0.0` → `1.1.0`) |
| `fix:`, `perf:`, `refactor:` | Patch (`1.0.0` → `1.0.1`) |
| `docs:`, `chore:`, `ci:` | No release |

---

## SAQ A / SAQ A-EP

Payment Card Industry (PCI DSS) Self-Assessment Questionnaire levels:

- **SAQ A**: Card data enters a form the merchant never controls or accesses. Minimal compliance
  burden.
- **SAQ A-EP**: Card data passes through the merchant app (even encrypted before transmission).
  Moderate compliance burden — requires app binary integrity, no debug-logging of inputs, and
  regular security assessments.

See [Security](security/security.md) for how this SDK affects your SAQ classification.
