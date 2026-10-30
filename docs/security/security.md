# Security

Card inputs in the Vault iOS SDK are rendered as native UIKit views inside the SDK module.
Field values are held in the SDK's internal state and are never surfaced to your application
code. The SDK handles tokenization directly — your app only receives the resulting
`vault_form_token`.

> For PCI DSS compliance review, share this page with your QSA. The SDK is designed to support
> SAQ A eligibility, but formal scope determination requires a QSA assessment.

---

## Table of Contents

- [What your application receives](#what-your-application-receives)
- [Card data lifecycle](#card-data-lifecycle)
- [What your application cannot do](#what-your-application-cannot-do)
- [Required hardening for production](#required-hardening-for-production)
- [Built-in mitigations](#built-in-mitigations)
- [Card data in memory](#card-data-in-memory)
- [What the SDK sends to monitoring](#what-the-sdk-sends-to-monitoring)
- [Export compliance](#export-compliance)
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
3. On `submit()`, the SDK copies the raw values out of its fields into zeroable byte buffers,
   builds the request body from them, makes a single HTTP POST to the vault API, and zeroes its
   copies — see [Card data in memory](#card-data-in-memory). If tokenization fails, the fields
   on screen keep their text, so the user can retry without re-entering the card. If it
   succeeds, the SDK resets the form with `clearFields()`.
4. Your app receives only `TokenizationResult` (with the token) or `SecureFieldsError`.
5. Your app can call `clearFields()` at any other time the form should be emptied — after a
   screenshot, or when the user abandons the payment.

Raw card data exists only within the SDK module's memory: in the fields until they are cleared or
the manager is released, and in the SDK's request copies until the gateway answers. It is not
passed to your application code at any point.

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
| **Card copies zeroed after send** | The PAN, CVV and cardholder name the SDK copies to build the tokenization request are held in `SensitiveBuffer`s, never `String`s, and are zeroed as soon as they have been sent — see [Card data in memory](#card-data-in-memory) |
| **Fields cleared on clearFields()** | All fields are emptied, pending BIN lookups are cancelled and brand state is reset. A successful `submit()` calls it; a failed one leaves the fields for a retry |
| **Ephemeral URLSession** | No URL cache, no cookie storage, `reloadIgnoringLocalCacheData` policy — no card data persists in the HTTP layer |
| **HTTPS by construction** | `SecureFieldsConfig` takes a `VaultEnvironment`, not a raw URL — `apiRoot` is a fixed `https://` literal per case, so there's no host-app-supplied string that could be `http://` |
| **No card data logging** | Debug prints are guarded by `#if DEBUG` — they produce no output in production builds |
| **Remote monitoring never carries card data** | `RemoteLogger` (separate from local debug prints, opt-out via `monitoringEnabled`/omitting `apiKey`) sends events continuously as they happen — safety comes from every payload being structural metadata only (field names, brand lists, outcome codes), not from a time window. No caller has raw field values (PAN, CVV, expiry, cardholder name) to log in the first place |
| **`VaultEnvironment.test` cannot reach a merchant's users** | Guarded at runtime: honoured only on a development build (simulator, or `get-task-allow` in the provisioning profile), downgraded to `.production` with a warning in a release-signed app. The case ships in the binary because the distributed XCFramework is archived in Release, so a compile-time guard would remove it from every shipped build — which is why the guard is a runtime one |

---

## Card data in memory

A Swift `String` is immutable and its storage is released without being cleared: a PAN or CVV
held in one stays in memory until the allocator happens to reuse it, which a memory dump can
catch. So the copies the SDK makes **to build the tokenization request** never go through a
`String`:

1. On `submit()`, the PAN, CVV and cardholder name are copied straight from the fields' text into
   `SensitiveBuffer`s — byte buffers the SDK allocates itself and can overwrite in place.
2. The JSON request body is written from those buffers into another `SensitiveBuffer`
   (`SensitiveJSONWriter`) — no `JSONEncoder`, no intermediate `String` or `Data`. Every
   allocation outgrown along the way is zeroed before it is freed.
3. The card buffers are zeroed as soon as the body is built. The body is handed to `URLSession`
   without a copy, and zeroed once the gateway has answered or the request has failed — not
   before, since a 5xx is retried with the same body. A buffer is also zeroed when it is freed,
   whatever the path.

The expiry date is not copied this way: on its own it is not sensitive authentication data, and
it is sent as JSON integers.

**What this does not cover:**

- **The fields on screen after a failure.** Their text is left intact when tokenization fails, by
  design: it is what lets the user retry without re-entering the card. No PCI DSS requirement
  calls for clearing them — requirement 3.3.1 forbids *storing* sensitive authentication data
  after authorization, and a field still displayed during the session is not storage.
  Comparable SDKs (VGS Collect, Checkout.com Frames, Basis Theory Elements) keep them too. Once
  tokenization succeeds the SDK clears them itself; at any other point clearing is up to you,
  through `clearFields()`.
- **UIKit's own storage.** A `UITextField` keeps its text in a `String` the SDK cannot zero,
  and `clearFields()` can only replace it with an empty one. Formatting, validation and the BIN
  lookup also read the field text as short-lived `String`s on each keystroke.
- **Below the SDK.** `URLSession` and the TLS stack make their own copies of the bytes they send,
  which no app code can reach.
- **The Oney birth date on success.** `TokenizationResult.birthDate` hands the entered date back
  to your app as a `String`, as public API output.

None of this changes the SDK's exposure surface — this memory is never accessible to your app —
but it narrows how long the SDK's own copies of card data survive in memory. The SDK persists
nothing: no disk, no `UserDefaults`, no keychain, and an ephemeral `URLSession` with no cache.

---

## What the SDK sends to monitoring

Remote monitoring is **off unless you supply an `apiKey`**, and can be disabled outright with
`monitoringEnabled: false`. When it is on, the SDK posts batched health events to Purse's
monitoring ingestion endpoint, which forwards them to Datadog.

Every event has the same flat shape:

| Field | Value |
|---|---|
| `tenantId` | Your merchant identifier |
| `instanceId` | A random `UUID` generated per SDK instance, never persisted and never reused across launches |
| `version`, `platform`, `env` | SDK version, `"ios"`, and the environment name |
| `date` | ISO 8601 timestamp |
| `level`, `code` | Severity, and the event code (e.g. `INIT_SDK`, `FIELD_FOCUS`, `BRAND_DETECTED`, `SUBMIT_SUCCESS`, `ERROR`) |
| `payload` | Structural metadata only — see below |

The `payload` for every event type the SDK emits:

| Event | Payload |
|---|---|
| `INIT_SDK` | Configured brand names, configured field names |
| `FIELD_FOCUS` / `FIELD_BLUR` | The field's name (`pan`, `cvv`, `expDate`, `holderName`) |
| `BRAND_DETECTED` / `BRAND_SELECTION_CHANGED` | Detected or selected brand names |
| `SUBMIT` / `SUBMIT_SUCCESS` | Empty |
| `DESTROY` | Counts of submit attempts and successes, and the error codes seen |
| `ERROR` | A fixed code — `FIELDS_INCOMPLETE`, `NETWORK_ERROR`, `INVALID_RESPONSE`, or an HTTP status |

**No cardholder data can reach a log.** The payload type is a closed enum accepting only strings,
numbers, booleans and arrays of them, and the internal API that records events accepts only a
field identifier, a brand, a count or a fixed error code — it is never handed a field value. The
error *message* from a failed API call is deliberately discarded rather than logged, because it
could echo arbitrary text back from the gateway.

The SDK collects **no device or advertising identifier**. It does not read the IDFA or IDFV, and
writes nothing to disk, `UserDefaults` or the keychain.

---

## Export compliance

The SDK performs no cryptography of its own beyond SHA-256 hashing (via Apple's CryptoKit) for
certificate-pin comparison, and relies on the operating system's TLS stack for transport
security. That is exempt encryption under Apple's export rules, so integrators can normally
answer `ITSAppUsesNonExemptEncryption = false` in their app's `Info.plist`.

This is guidance, not legal advice — confirm it against your own app's full feature set.

---

## See also

- [Getting Started](../integration/getting-started.md)
- [API Reference](../integration/api-reference.md)
