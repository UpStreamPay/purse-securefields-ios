# Security

Card inputs in the Vault iOS SDK are rendered as native UIKit views inside the SDK module.
Field values are held in the SDK's internal state and are never surfaced to your application
code. The SDK handles tokenization directly — your app only receives the resulting
`vault_form_token`.

> For PCI DSS compliance review, share this page with your QSA. The SDK is designed to support
> SAQ A-EP eligibility, but formal scope determination requires a QSA assessment.

---

## Table of Contents

- [What your application receives](#what-your-application-receives)
- [Card data lifecycle](#card-data-lifecycle)
- [What your application cannot do](#what-your-application-cannot-do)
- [Required hardening for production](#required-hardening-for-production)
- [Built-in mitigations](#built-in-mitigations)
- [See also](#see-also)

---

## What your application receives

| Data | What you get |
|---|---|
| Field state | Validity (`Bool`), character count (via `panDigitCount`), touched state — **never the value** |
| Brand detection | Detected `[CardBrand]` (e.g. `[.visa, .carteBancaire]`) |
| Tokenization result | `vault_form_token`, BIN (first 8 digits), last four digits — **never the raw PAN or CVV** |

---

## Card data lifecycle

1. The user types into a native SDK field (`SecurePANField`, `SecureCVVField`,
   `SecureExpDateField`, `SecureHolderNameField`).
2. Field state (validity, character count — never the raw value) is delivered as delegate
   callbacks to your app.
3. On `submit()`, the SDK reads raw values from its internal fields, makes a single HTTP POST
   to the vault API, and immediately zeroes the in-memory buffers via `clearSensitiveData()`.
4. Your app receives only `TokenizationResult` (with the token) or `SecureFieldsError`.

Raw card data exists only within the SDK module's memory during active user input and the brief
tokenization window. It is not passed to your application code at any point.

---

## What your application cannot do

### Read field values

`SecureBaseField` (the internal UITextField subclass) overrides `text` and `attributedText`
getters to return `nil`:

```swift
override var text: String? {
    get { nil }           // external reads always return nil
    set { super.text = newValue }
}
```

Any attempt to cast a card field to `UITextField` and read `.text` returns `nil`. Display is
unaffected — UIKit renders from its internal backing storage, bypassing the getter.

### Read via accessibility

`accessibilityValue` is also overridden to return `nil`, blocking VoiceOver and third-party
accessibility services from announcing card field content.

### Access the internal field views

All card field classes (`SecurePANField`, `SecureCVVField`, etc.) are `internal` to the SDK.
They are not reachable via the public API.

---

## Required hardening for production

### Enable certificate pinning

App Transport Security (ATS) enforces HTTPS and TLS 1.2+ by default, but a rogue root CA
installed via an MDM profile or malware can still perform MITM attacks. Enable SPKI pinning
for production deployments:

```swift
SecureFieldsConfig(
    tenantId: "...",
    environment: .production,
    pinnedPublicKeyHashes: [
        "YOUR_PRIMARY_SPKI_HASH",
        "YOUR_BACKUP_SPKI_HASH",    // rotation backup — prevents downtime on cert renewal
    ]
)
```

Provide at least two hashes (primary + backup) so a certificate renewal does not break
existing app versions in the field.

### Handle screenshot detection

The SDK fires `secureFieldsScreenshotDetected()` after the system saves a screenshot. The OS
does not allow apps to prevent screenshots, but you can limit the exposure window:

```swift
func secureFieldsScreenshotDetected() {
    secureFields.clearFields()
    showAlert("Screenshot detected. For security, please re-enter your card details.")
}
```

### Jailbreak detection (optional, high-security environments)

On jailbroken devices, an attacker with physical access can attach a debugger or memory
scanner regardless of SDK protections. If your risk model requires it, check before rendering
the payment form:

```swift
if deviceIsJailbroken() {
    showAlert("Payments are not available on this device.")
    return
}
```

---

## Built-in mitigations

| Mitigation | Detail |
|---|---|
| **Field value getter override** | `UITextField.text` and `attributedText` return `nil` — external code cannot read card data through any cast |
| **Accessibility blocked** | `accessibilityValue` returns `nil` — VoiceOver and third-party accessibility services cannot read field content |
| **Privacy overlay on background** | `UIBlurEffect` placed over all card fields on `willResignActiveNotification` — card data not visible in app-switcher thumbnails |
| **Screen recording detection** | `UIScreen.capturedDidChangeNotification` triggers the privacy overlay automatically when screen recording starts |
| **Screenshot notification** | `UIApplication.userDidTakeScreenshotNotification` fires `secureFieldsScreenshotDetected()` — host app can clear fields and warn the user |
| **Keyboard learning disabled** | `autocorrectionType = .no` on all four fields; `spellCheckingType = .no` on PAN and cardholder name — keyboard never stores PAN, CVV, or name input |
| **Autofill scoped intentionally** | PAN uses `textContentType = .creditCardNumber` (enables Wallet-saved-card suggestions and camera card scan); cardholder name uses `.name` (contact autofill); CVV and expiry leave it unset since no matching autofill type exists — password managers and iCloud Keychain never see or cache these values, as none are exposed via `text`/`attributedText` getters (see above) |
| **isSecureTextEntry on CVV** | CVV field uses `isSecureTextEntry = true` — input is masked and excluded from screenshots |
| **Memory cleared on submit** | `clearSensitiveData()` zeroes internal field content immediately after the tokenization request is built |
| **Memory cleared on clearFields()** | All field buffers are zeroed; pending BIN lookups are cancelled |
| **Ephemeral URLSession** | No URL cache, no cookie storage, `reloadIgnoringLocalCacheData` policy — no card data persists in the HTTP layer |
| **HTTPS by construction** | `SecureFieldsConfig` takes a `VaultEnvironment`, not a raw URL — `apiRoot` is a fixed `https://` literal per case, so there's no host-app-supplied string that could be `http://` |
| **No card data logging** | Debug prints are guarded by `#if DEBUG` — they produce no output in production builds |
| **Remote monitoring never carries card data** | `RemoteLogger` (separate from local debug prints, opt-out via `monitoringEnabled`/omitting `apiKey`) sends events continuously as they happen — safety comes from every payload being structural metadata only (field names, brand lists, outcome codes), not from a time window. No caller has raw field values (PAN, CVV, expiry, cardholder name) to log in the first place |
| **`VaultEnvironment.test` cannot ship to merchants** | Wrapped in `#if DEBUG`; the distributed XCFramework is always built in `Release` configuration, so the case is compiled out of every merchant integration entirely |

---

## See also

- [Getting Started](../integration/getting-started.md)
- [API Reference](../integration/api-reference.md)
- [iOS Payment SDK Comparison](pci-comparison.md) — SAQ classification and implementation comparison across SDKs
