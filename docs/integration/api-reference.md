# API Reference

Module: `PurseSecureFields`

---

## Table of Contents

- [SecureFieldsManager](#securefieldsmanager)
- [SecureFieldsConfig](#securefieldsconfig)
- [Remote log monitoring](#remote-log-monitoring)
- [VaultEnvironment](#vaultenvironment)
- [SecureFieldsStyle](#securefieldsstyle)
- [SecureFieldsPlaceholders](#securefieldsplaceholders)
- [SecureFieldsDelegate](#securefieldsdelegate)
- [SecureField](#securefield)
- [CardBrand](#cardbrand)
- [TokenizationResult](#tokenizationresult)
- [SecureFieldsError](#securefieldsError)

---

## `SecureFieldsManager`

Main SDK entry point. Owns all card input views and coordinates BIN lookup, validation, and
tokenization.

### Initialisation

```swift
public final class SecureFieldsManager {
    public init(config: SecureFieldsConfig)
}
```

### Views

```swift
public let panContainer: SecurePANContainer   // PAN input + optional brand selector
public var cvvView: UIView                     // CVV or date-of-birth input
public var expDateView: UIView                 // Expiry date (MM/YY)
public var holderNameView: UIView              // Cardholder name
```

All views are opaque `UIView` instances. The underlying `UITextField` subclasses are `internal`
to the SDK — any attempt to read card data through a cast is blocked at the `text` getter level.

### Delegate

```swift
public weak var delegate: SecureFieldsDelegate?
```

### Field state queries

```swift
// Returns true when the field has passed all validation rules.
public func isFieldValid(_ field: SecureField) -> Bool

// Returns true when the field is the first responder (focused).
public func isFieldFocused(_ field: SecureField) -> Bool

// Returns true when the field has any content (without revealing the value).
public func hasFieldContent(_ field: SecureField) -> Bool

// Number of PAN digits typed. Never exposes the digits themselves.
public var panDigitCount: Int { get }

// PAN/CVV lengths currently accepted, as driven by BIN lookup and brand selection.
// .expDate and .holderName carry no length constraint and return [].
public func expectedLengths(for field: SecureField) -> [Int]
```

Form validity (`secureFieldsFormValidityChanged` and the `submit()` completeness check) covers
PAN, CVV and expiry date. The cardholder name is optional at tokenization and is **excluded by
default** — opt in with `requiresHolderName: true` in the config to make it count.

### Submission

```swift
// Validates all fields and initiates tokenization.
// Fires secureFieldsDidTokenize or secureFieldsDidFail on the delegate.
public func submit(selectedNetwork: CardBrand? = nil, saveToken: Bool = false)
```

Calling `submit()` while any required field is invalid is safe — it fires
`secureFieldsDidFail(.fieldsIncomplete)` without making a network request.

`selectedNetwork` names the network to submit for a co-badged card, overriding the SDK's own
resolution. It is ignored — with a console warning — when `brandSelector` is enabled, since the
cardholder's pick then wins, and when the requested network was not detected on the card. Mirrors
`SubmitOptions.selectedNetwork` on Android.

### Clear

```swift
// Zeroes all field buffers, cancels pending BIN lookup, resets brand state.
public func clearFields()

// Clears a single field through the same reformat/validate path as user typing,
// leaving the other fields untouched. Clearing .pan also resets brand detection
// once the digit count drops below the BIN threshold.
public func clearField(_ field: SecureField)
```

### Privacy

```swift
// When true (default), a UIBlurEffect overlay is placed over all card fields
// while the app is backgrounded or screen recording is active.
public var obscuresOnBackground: Bool
```

---

## `SecureFieldsConfig`

Passed to `SecureFieldsManager.init()`. All configuration is immutable after initialisation.

```swift
public struct SecureFieldsConfig {
    public init(
        tenantId: String,
        environment: VaultEnvironment = .sandbox,
        brands: [CardBrand] = CardBrand.allCases,
        brandSelector: Bool = false,
        style: SecureFieldsStyle = .default,
        placeholders: SecureFieldsPlaceholders = .init(),
        requiresHolderName: Bool = false,
        pinnedPublicKeyHashes: [String] = [],
        apiKey: String? = nil,
        monitoringEnabled: Bool = true
    )
}
```

| Parameter | Required | Description |
|---|---|---|
| `tenantId` | Yes | Your merchant/tenant identifier |
| `environment` | No | `.sandbox` or `.production` (default `.sandbox`). The SDK resolves both the tokenization gateway and the remote monitoring endpoint internally — see [VaultEnvironment](#vaultenvironment) |
| `brands` | No | Accepted card networks, **in your preference order** — for a co-badged card, the first configured brand that matches is pre-selected. Defaults to all supported brands. |
| `brandSelector` | No | Whether the cardholder may arbitrate the network of a co-badged card through the built-in selector. Defaults to `false` (selector hidden), matching web and Android; the SDK then submits the brand its own resolution picked. |
| `style` | No | Visual style applied to all fields |
| `placeholders` | No | Placeholder text for each field |
| `requiresHolderName` | No | When `true`, the cardholder name counts toward form validity and the `submit()` completeness check (default `false` — the field is optional at tokenization, and a host that never mounts `holderNameView` must not end up with a form that can never become valid) |
| `pinnedPublicKeyHashes` | No | SHA-256 SPKI hashes (Base64) for certificate pinning |
| `apiKey` | No | Api key for remote log monitoring (Datadog). Monitoring silently disables itself when omitted — see [Remote log monitoring](#remote-log-monitoring) |
| `monitoringEnabled` | No | Opt-out for remote log monitoring (default `true`) |

**Preconditions** (crash at init time if violated):
- `tenantId` must not be blank

There is no `baseURL` parameter — all requests are HTTPS by construction, since
`VaultEnvironment.apiRoot` is a fixed `https://` literal per case rather than a
host-app-supplied string.

---

## Remote log monitoring

The SDK forwards health logs (SDK init, field focus/blur, brand detection, submit attempts and
results, teardown — never card data) to Datadog via Purse's log ingestion worker
(`cf-widget-logger`), so we can monitor SDK health in production, in real time. The wire format
matches the web vault SDK's monitoring module.

- **Enable/disable**: on by default whenever `apiKey` is provided to `SecureFieldsConfig`.
  Omitting `apiKey`, or passing `monitoringEnabled: false`, disables it — nothing is sent, and no
  network calls are made.
- **PCI**: events are sent continuously, as they happen — including for `SecureFieldsManager`'s
  entire lifetime, while the secure fields are on screen. Safety comes from what's in a payload,
  not from when it's sent: every event is structural metadata only (field names, brand lists,
  outcome codes) — no card data is ever placed in a log payload, by construction.
- This is unrelated to the SDK's local `#if DEBUG` status-code prints, which never leave the
  device.
- See [Security](../security/security.md) for the full PCI rationale.

---

## `VaultEnvironment`

Selects which Purse environment the SDK talks to. Resolves **both** the vault
tokenization/BIN-lookup gateway and the `cf-widget-logger` remote monitoring endpoint internally
— no URL configuration is required in the host app.

```swift
public enum VaultEnvironment: String {
    case test          // internal only — refused in a release-signed app, see below
    case sandbox
    case production
}
```

`.test` is internal-only and guarded **at runtime**: it is honoured on a development build (the
simulator, or a binary whose provisioning profile carries `get-task-allow` — Xcode-run,
development and ad-hoc builds) and silently downgraded to `.production`, with a console warning,
anywhere else. The SDK ships as a single Release-built XCFramework used by every merchant
whatever their own build type, so the check cannot be a compile-time one. Same rule as the
Android SDK, which checks the host app's `FLAG_DEBUGGABLE`.

### `urlSessionOverride` (tests only)

```swift
public var urlSessionOverride: URLSession?   // on SecureFieldsConfig
```

Substitutes the `URLSession` used for BIN lookup and tokenization, so an automated suite can stub
the gateway. **It bypasses certificate pinning entirely and must never be set in a shipping app.**
It is available in the distributed binary because that binary is built in Release — gated behind
`#if DEBUG`, no consumer of the XCFramework could stub anything.

Remote log monitoring builds its own session and is *not* substituted; pass
`monitoringEnabled: false` when running against a stub.

---

## `SecureFieldsStyle`

Visual configuration applied to all card input fields.

```swift
public struct SecureFieldsStyle {
    public struct StateStyle {
        public init(
            textColor: UIColor? = nil,
            backgroundColor: UIColor? = nil,
            borderColor: UIColor? = nil,
            borderWidth: CGFloat? = nil
        )
    }

    public init(
        font: UIFont = .systemFont(ofSize: 16),
        textColor: UIColor = .label,
        placeholderColor: UIColor = .placeholderText,
        tintColor: UIColor = .systemBlue,
        keyboardAppearance: UIKeyboardAppearance = .default,
        backgroundColor: UIColor? = nil,
        borderColor: UIColor? = nil,
        borderWidth: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        focus: StateStyle? = nil,
        valid: StateStyle? = nil,
        invalid: StateStyle? = nil,
        empty: StateStyle? = nil
    )

    public static let `default`: SecureFieldsStyle
}
```

| Property | Type | Default | Description |
|---|---|---|---|
| `font` | `UIFont` | `.systemFont(ofSize: 16)` | Text font for all inputs |
| `textColor` | `UIColor` | `.label` | Input text color |
| `placeholderColor` | `UIColor` | `.placeholderText` | Placeholder text color |
| `tintColor` | `UIColor` | `.systemBlue` | Cursor and selection highlight color |
| `keyboardAppearance` | `UIKeyboardAppearance` | `.default` | Light or dark keyboard |
| `backgroundColor` | `UIColor?` | `nil` | Field background |
| `borderColor` | `UIColor?` | `nil` | Border colour (needs a non-zero `borderWidth`) |
| `borderWidth` | `CGFloat` | `0` | Border width |
| `cornerRadius` | `CGFloat` | `0` | Corner radius |
| `focus` / `valid` / `invalid` / `empty` | `StateStyle?` | `nil` | Per-state overrides — see below |

### State-dependent styling

The SDK repaints each field as its state changes, so you no longer have to drive borders yourself
from `secureFieldsFocusChanged` / `secureFieldsContentChanged`. States resolve in this order:
`focus` while the field is first responder, then `valid` or `invalid` once it has content, and
`empty` while it has none. Anything a `StateStyle` leaves `nil` falls back to the base style.

```swift
SecureFieldsStyle(
    backgroundColor: .secondarySystemBackground,
    borderColor: .separator,
    borderWidth: 1,
    cornerRadius: 10,
    focus:   .init(borderColor: .systemBlue, borderWidth: 2),
    valid:   .init(borderColor: .systemGreen),
    invalid: .init(borderColor: .systemRed)
)
```

The names mirror the `focus` / `valid` / `invalid` / `empty` pseudo-classes of `VaultStyles` on
Android and of the web SDK's CSS. Styles are still applied to every field at once, and are fixed
at initialisation.

---

## `SecureFieldsPlaceholders`

Placeholder strings for each field. Shown when the field is empty.

```swift
public struct SecureFieldsPlaceholders {
    public init(
        pan: String = "1234 5678 9012 3456",
        cvv: String = "123",
        expDate: String = "MM/YY",
        holderName: String = "Cardholder Name"
    )
}
```

---

## `SecureFieldsDelegate`

A protocol for receiving events from `SecureFieldsManager`. All methods except
`secureFieldsDidTokenize` and `secureFieldsDidFail` have default no-op implementations.

```swift
public protocol SecureFieldsDelegate: AnyObject {

    // MARK: Required

    /// Tokenization succeeded. `result.vaultFormToken` is the token to send to your backend.
    func secureFieldsDidTokenize(_ result: TokenizationResult)

    /// Tokenization or submission failed. See SecureFieldsError.
    func secureFieldsDidFail(_ error: SecureFieldsError)

    // MARK: Optional (default no-op)

    /// Fires when aggregate form validity changes.
    /// Use this to enable/disable the Pay button.
    func secureFieldsFormValidityChanged(_ isValid: Bool)

    /// Fires when the BIN lookup returns results (brands detected) or when
    /// the card number drops below 8 digits (brands cleared — empty array).
    func secureFieldsBrandsDetected(_ brands: [CardBrand])

    /// Fires when the user selects a brand from the in-PAN brand selector.
    func secureFieldsBrandSelected(_ brand: CardBrand)

    /// Fires on any keystroke in any field.
    func secureFieldsContentChanged()

    /// Fires on focus and blur for any field.
    func secureFieldsFocusChanged(field: SecureField, isFocused: Bool)

    /// Fires immediately after UIApplication.userDidTakeScreenshotNotification.
    /// The screenshot has already been saved — the SDK cannot prevent it.
    /// Respond by calling clearFields() and notifying the user.
    func secureFieldsScreenshotDetected()
}
```

---

## `SecureField`

Identifies a specific card input field.

```swift
public enum SecureField {
    case pan        // Primary account number
    case cvv        // Card verification value (or date-of-birth for Oney)
    case expDate    // Expiry date
    case holderName // Cardholder name
}
```

Used in:
- `isFieldValid(_ field: SecureField) -> Bool`
- `isFieldFocused(_ field: SecureField) -> Bool`
- `hasFieldContent(_ field: SecureField) -> Bool`
- `secureFieldsFocusChanged(field:isFocused:)`

---

## `CardBrand`

Supported card networks.

```swift
public enum CardBrand: String, CaseIterable, Equatable {
    case visa          = "VISA"
    case mastercard    = "MASTERCARD"
    case amex          = "AMEX"
    case maestro       = "MAESTRO"
    case carteBancaire = "CARTE_BANCAIRE"
    case oney          = "ONEY"
}
```

The `rawValue` matches the network string returned by the BIN lookup API. `CardBrand.allCases`
is the default accepted brand list if none is specified in `SecureFieldsConfig`.

**Oney special behaviour:** when `oney` is the selected brand, the CVV field switches to
date-of-birth input mode (date picker, stored as `YYYY-MM-DD`). The tokenization request then
carries no `cvv` at all, and the birth date is never sent to the gateway.

---

## `TokenizationResult`

Returned via `secureFieldsDidTokenize(_:)` on successful submission.

```swift
public struct TokenizationResult {
    public let vaultFormToken: String     // opaque token — send to your backend
    public let bin: String               // first 8 digits — never the full PAN
    public let lastFourDigits: String    // last 4 digits
    public let detectedBrands: [CardBrand]
    public let birthDate: String?        // Oney only — "yyyy-MM-dd"
    public let selectedNetwork: CardBrand?  // the network submitted as `selected_network`
}
```

> `bin` and `lastFourDigits` are safe to display in a payment confirmation UI. `vaultFormToken`
> is sent to your backend to complete the transaction — it never contains card data.

`birthDate` and `selectedNetwork` are reflected from the SDK's own state, not from the response:
the birth date never reaches the gateway, and the submitted network is not echoed back, so this
result is the only place either can be read. Matches `SubmitResult.Success` on Android and
`birth_date` on web.

---

## `SecureFieldsError`

Passed to `secureFieldsDidFail(_:)`.

```swift
public enum SecureFieldsError: Error {
    /// submit() called while one or more required fields are invalid.
    case fieldsIncomplete

    /// URLSession transport failure (no network, timeout, TLS error).
    case networkError(Error)

    /// Non-2xx HTTP response from the vault API.
    /// - message: error message from the response body
    /// - statusCode: HTTP status code (e.g. 400, 422, 500)
    case apiError(message: String, statusCode: Int)

    /// Response was received but could not be decoded.
    case invalidResponse
}
```
