# Setting Up the Project

This guide walks through the structure of the Vault iOS SDK project and how to set it up
from scratch for SDK contributors.

> This guide is for **SDK contributors**. Merchants integrating the published SDK start with
> [Getting Started](../integration/getting-started.md).

---

## Table of Contents

- [Project structure](#project-structure)
- [Step 1 — Create the Swift package](#step-1--create-the-swift-package)
- [Step 2 — Add source targets](#step-2--add-source-targets)
- [Step 3 — Add the demo app](#step-3--add-the-demo-app)
- [Step 4 — Configure CI](#step-4--configure-ci)
- [Step 5 — Configure release-please](#step-5--configure-release-please)
- [Step 6 — First release](#step-6--first-release)
- [Running tests locally](#running-tests-locally)

---

## Project structure

```
purse-securefields-ios/
├── Package.swift              ← Source package (main branch). Rewritten to binary target on release.
├── Sources/
│   └── PurseSecureFields/     ← SDK source
│       ├── Internal/          ← CardValidator, CardFormatter
│       ├── Models/            ← CardBrand, SecureFieldsConfig, SecureFieldsError, TokenizationResult
│       ├── Networking/        ← VaultAPIClient, NetworkModels
│       ├── Resources/         ← Badges.xcassets (card brand SVGs)
│       ├── Views/             ← SecureBaseField, SecurePANField, SecureCVVField, etc.
│       ├── SecureFieldsManager.swift
│       └── SecureFieldsDelegate.swift
├── Tests/
│   └── PurseSecureFieldsTests/ ← Unit tests
├── Demo/
│   ├── Demo.xcodeproj         ← UIKit demo app project
│   └── Sources/               ← DemoViewController and extensions
├── .github/
│   └── workflows/
│       ├── ci.yml             ← Tests on every PR
│       ├── release.yml        ← Build, sign, and publish XCFramework on release
│       └── release-please.yml ← Automated release PR management
├── release-please-config.json
└── .release-please-manifest.json
```

---

## Step 1 — Create the Swift package

```bash
mkdir purse-securefields-ios && cd purse-securefields-ios
swift package init --name PurseSecureFields --type library
```

Update `Package.swift` to require iOS 15 and add the resource bundle for card brand assets:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PurseSecureFields",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "PurseSecureFields", type: .dynamic, targets: ["PurseSecureFields"])
    ],
    targets: [
        .target(
            name: "PurseSecureFields",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PurseSecureFieldsTests",
            dependencies: ["PurseSecureFields"]
        )
    ]
)
```

The `.dynamic` library type ensures the package builds as a `.framework` (dynamic linking) rather
than a static archive. This matches the XCFramework format used for distribution.

---

## Step 2 — Add source targets

Create the directory structure under `Sources/PurseSecureFields/`:

```
Sources/PurseSecureFields/
├── Internal/
│   ├── CardValidator.swift      ← Luhn check, expiry date validation
│   └── CardFormatter.swift      ← digit-group formatting per brand
├── Models/
│   ├── CardBrand.swift          ← CardBrand enum
│   ├── SecureFieldsConfig.swift ← SecureFieldsConfig, SecureFieldsStyle, SecureFieldsPlaceholders
│   ├── SecureFieldsError.swift  ← SecureFieldsError enum
│   └── TokenizationResult.swift ← TokenizationResult struct
├── Networking/
│   ├── NetworkModels.swift      ← Request/response Codable types, SPKI pinning
│   └── VaultAPIClient.swift     ← binLookup(), tokenize(), PinningDelegate
├── Resources/
│   └── Badges.xcassets/         ← SVG assets for each CardBrand
├── Views/
│   ├── SecureBaseField.swift    ← UITextField subclass with text getter override
│   ├── SecurePANField.swift     ← PAN formatting + Luhn validation
│   ├── SecureCVVField.swift     ← pin mode / Oney date-of-birth mode
│   ├── SecureExpDateField.swift ← MM/YY formatting + date validation
│   ├── SecureHolderNameField.swift ← trimmed non-empty validation
│   ├── SecurePANContainer.swift ← layout container for PAN + brand selector
│   └── SecureBrandSelectorView.swift ← horizontal brand picker
├── SecureFieldsManager.swift    ← public entry point
└── SecureFieldsDelegate.swift   ← protocol + SecureField enum
```

---

## Step 3 — Add the demo app

The `Demo/` directory contains a standalone Xcode project that imports `PurseSecureFields` as a
local package. It is not published — it serves as a manual test harness and the source for
automated UI tests.

Create `Demo/Demo.xcodeproj` in Xcode (**File → New → Project → App**) and add the local package
as a dependency (**File → Add Package Dependencies → Add Local → select the purse-securefields-ios root**).

The demo app structure:

```
Demo/
├── Demo.xcodeproj
├── Resources/
│   └── Info.plist
└── Sources/
    ├── AppDelegate.swift
    ├── DemoViewController.swift         ← SecureFieldsManager init + layout
    ├── DemoViewController+Layout.swift  ← UIStackView layout
    ├── DemoViewController+Delegate.swift ← SecureFieldsDelegate conformance
    └── MockURLProtocol.swift            ← URLProtocol stub for UI tests
```

The demo uses a `--uitesting` launch argument in UI tests to inject a `MockURLProtocol` session,
allowing the tokenization and BIN lookup endpoints to return fixed responses without a real network.

---

## Step 4 — Configure CI

The CI workflow (`.github/workflows/ci.yml`) runs on every pull request:

1. **Library Tests:** runs `xcodebuild test -scheme PurseSecureFields` on the Swift package
2. **Demo UI Tests:** runs `xcodebuild test -project Demo/Demo.xcodeproj -scheme DemoUITests`
   with the `--uitesting` launch argument

Both jobs run on `macos-15` and use a dynamically selected iOS Simulator. Code signing is
disabled (`CODE_SIGNING_ALLOWED=NO`) — CI tests do not require a signed build.

---

## Step 5 — Configure release-please

release-please manages version bumps and changelog generation from Conventional Commits.

**`release-please-config.json`:**

```json
{
  "packages": {
    ".": {
      "release-type": "simple",
      "changelog-sections": [
        {"type": "feat",     "section": "Features"},
        {"type": "fix",      "section": "Bug Fixes"},
        {"type": "perf",     "section": "Performance"},
        {"type": "revert",   "section": "Reverts"},
        {"type": "docs",     "section": "Documentation"},
        {"type": "refactor", "section": "Refactoring"},
        {"type": "test",     "section": "Tests",  "hidden": true},
        {"type": "ci",       "section": "CI",     "hidden": true}
      ]
    }
  }
}
```

**`.release-please-manifest.json`:** tracks the current version:

```json
{".": "1.0.4"}
```

The `.github/workflows/release-please.yml` workflow runs on every push to `main` and calls
the `googleapis/release-please-action` action.

---

## Step 6 — First release

1. Add the GitHub secrets described in the [Release guide](release.md#prerequisites-one-time-setup).
2. Push a `feat:` commit to `main` — release-please opens a release PR.
3. Merge the release PR.
4. The CI builds and signs the XCFramework and attaches it to the GitHub Release.

---

## Running tests locally

```bash
# List available simulators
xcrun simctl list devices available

# Run SDK unit tests
xcodebuild test \
  -scheme PurseSecureFields \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  CODE_SIGNING_ALLOWED=NO

# Run demo UI tests
xcodebuild test \
  -project Demo/Demo.xcodeproj \
  -scheme DemoUITests \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60 \
  CODE_SIGNING_ALLOWED=NO
```

---

## See also

- [Internals](internals.md) — SecureFieldsManager architecture, field isolation, BIN lookup
- [Distribution](distribution.md) — why SPM binary target, signing requirements
- [Release](release.md) — step-by-step release runbook
