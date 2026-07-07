# PurseSecureFields — iOS SDK

![CI](https://github.com/UpStreamPay/vault-ios/actions/workflows/ci.yml/badge.svg)
![Release](https://img.shields.io/github/v/release/UpStreamPay/vault-ios)

Native iOS SDK for secure card data collection. Fields are fully isolated from the host application: card numbers, CVV, and cardholder data never pass through host app code.

## Requirements

- iOS 15+
- Swift 5.9+
- Xcode 15+

## Installation

The SDK is distributed as a pre-built XCFramework via Swift Package Manager. Tagged releases contain a binary package — no compilation required on the client side.

### Xcode

**File → Add Package Dependencies** → enter the URL:

```
https://github.com/UpStreamPay/vault-ios.git
```

Select **Up to Next Major Version** from `1.0.0`.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/UpStreamPay/vault-ios.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "PurseSecureFields", package: "vault-ios")
        ]
    )
]
```

## Quick Start

```swift
import PurseSecureFields

class CheckoutViewController: UIViewController, SecureFieldsDelegate {

    let manager = SecureFieldsManager(config: SecureFieldsConfig(
        tenantId: "your-tenant-id",
        baseURL: "https://api.vault.purse.com"
    ))

    override func viewDidLoad() {
        super.viewDidLoad()
        manager.delegate = self

        // Add fields to your layout
        view.addSubview(manager.panContainer)
        view.addSubview(manager.cvvView)
        view.addSubview(manager.expDateView)
        view.addSubview(manager.holderNameView)
    }

    func payTapped() {
        manager.submit()
    }

    // MARK: - SecureFieldsDelegate

    func secureFieldsDidTokenize(_ result: TokenizationResult) {
        print("token:", result.vaultFormToken)
        print("bin:", result.bin, "last4:", result.lastFourDigits)
    }

    func secureFieldsDidFail(_ error: SecureFieldsError) {
        // handle error
    }

    func secureFieldsFormValidityChanged(_ isValid: Bool) {
        payButton.isEnabled = isValid
    }
}
```

## Configuration

### `SecureFieldsConfig`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `tenantId` | `String` | required | Your Purse tenant identifier |
| `baseURL` | `String` | required | Vault API base URL (must be HTTPS) |
| `brands` | `[CardBrand]` | all | Accepted card brands |
| `style` | `SecureFieldsStyle` | `.default` | Visual appearance |
| `placeholders` | `SecureFieldsPlaceholders` | built-in | Placeholder text per field |
| `apiKey` | `String?` | `nil` | Api key for remote log monitoring (Datadog). Monitoring silently disables itself when omitted |
| `monitoringEnabled` | `Bool` | `true` | Opt-out for remote log monitoring |
| `monitoringEnvironment` | `MonitoringEnvironment` | `.production` | Which environment remote monitoring logs are tagged with and sent to |

### Remote log monitoring

The SDK forwards `info`/`warn`/`error` health logs (SDK init, teardown, submit outcome counts —
never card data) to Datadog via Purse's log ingestion worker, so we can monitor SDK health in
production. It's on by default when an `apiKey` is provided to `SecureFieldsConfig`; omit
`apiKey`, or pass `monitoringEnabled: false`, to disable it.

For PCI compliance, remote logging is fully suppressed for `SecureFieldsManager`'s entire
lifetime — nothing is sent while the cardholder is interacting with the form, and no card data is
ever placed in a log payload.

### `SecureFieldsStyle`

```swift
SecureFieldsStyle(
    font: .systemFont(ofSize: 16),
    textColor: .label,
    placeholderColor: .placeholderText,
    tintColor: .systemBlue,
    keyboardAppearance: .default
)
```

### `SecureFieldsPlaceholders`

```swift
SecureFieldsPlaceholders(
    pan: "1234 5678 9012 3456",
    cvv: "123",
    expDate: "MM/YY",
    holderName: "Cardholder Name"
)
```

### Restricting accepted brands

```swift
SecureFieldsConfig(
    tenantId: "...",
    baseURL: "...",
    brands: [.visa, .mastercard, .carteBancaire]
)
```

## Layout

Each field is exposed as an opaque `UIView`. Embed them in your own containers:

```swift
// panContainer includes the card brand selector
view.addSubview(manager.panContainer)      // SecurePANContainer: UIView
view.addSubview(manager.cvvView)           // UIView
view.addSubview(manager.expDateView)       // UIView
view.addSubview(manager.holderNameView)    // UIView
```

Recommended height: **48pt**. Fields size to fill their container.

## Manager API

### State queries

```swift
manager.isFieldValid(.pan)       // Bool
manager.isFieldFocused(.cvv)     // Bool
manager.hasFieldContent(.expDate) // Bool
manager.panDigitCount            // Int — digit count without exposing digits
```

### Actions

```swift
manager.submit()                  // tokenize — fires delegate
manager.submit(saveToken: true)   // save vault token for reuse
manager.clearFields()             // reset all fields and BIN state
```

## Delegate

```swift
public protocol SecureFieldsDelegate: AnyObject {
    // Required
    func secureFieldsDidTokenize(_ result: TokenizationResult)
    func secureFieldsDidFail(_ error: SecureFieldsError)
    func secureFieldsBrandsDetected(_ brands: [CardBrand])
    func secureFieldsFormValidityChanged(_ isValid: Bool)

    // Optional
    func secureFieldsBrandSelected(_ brand: CardBrand)
    func secureFieldsContentChanged()
    func secureFieldsFocusChanged(field: SecureField, isFocused: Bool)
}
```

### Implement border feedback

```swift
func secureFieldsContentChanged() {
    updateFieldBorders()
}

func secureFieldsFocusChanged(field: SecureField, isFocused: Bool) {
    updateFieldBorders()
}

func updateFieldBorders() {
    // green = valid, red = has content but not focused and invalid, grey = untouched
    let panValid = manager.isFieldValid(.pan)
    let panFocused = manager.isFieldFocused(.pan)
    let panContent = manager.hasFieldContent(.pan)
    // apply border to your container view…
}
```

## Supported Card Brands

| Brand | `CardBrand` case | PAN format | CVV |
|-------|-----------------|------------|-----|
| Visa | `.visa` | 4-4-4-4 (16 digits) | 3 digits |
| Mastercard | `.mastercard` | 4-4-4-4 (16 digits) | 3 digits |
| American Express | `.amex` | 4-6-5 (15 digits) | 4 digits |
| Maestro | `.maestro` | 4-4-4-4 (16 digits) | 3 digits |
| Carte Bancaire | `.carteBancaire` | 4-4-4-4 (16 digits) | 3 digits |
| Oney | `.oney` | 4-4-4-4-3 (19 digits) | Date of birth |

PAN length and CVV length are driven by the BIN lookup API response — not hardcoded.

## PCI DSS Notes

- Card fields block the `text` getter at the UIKit level — the host app cannot read PAN, CVV, expiry, or cardholder name via any UITextField API
- CVV paste is disabled
- Sensitive field classes are `internal` — inaccessible to the host app module
- No card data is logged; network logs are gated behind `#if DEBUG` and limited to status codes
- `X-Purse-SDK-Version` and `X-Request-ID` headers are sent on every request
- Memory is cleared on `clearFields()` — call this after successful tokenization if you do not need the form to persist

## TokenizationResult

```swift
public struct TokenizationResult {
    public let vaultFormToken: String
    public let bin: String
    public let lastFourDigits: String
    public let detectedBrands: [CardBrand]
}
```

## License

Copyright © Purse. All rights reserved.
