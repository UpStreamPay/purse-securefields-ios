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
- [Limits of in-process isolation](#limits-of-in-process-isolation)
- [Required hardening for production](#required-hardening-for-production)
- [Built-in mitigations](#built-in-mitigations)
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

### Read through `UITextInput`

`UITextField` also conforms to `UITextInput`, whose `text(in:)` and `attributedText(in:)` read
the document without going through `text`. Both are overridden to return a mask instead of the
value: one `•` per character, whitespace kept.

```swift
let input = cvvView as! UITextInput
let all = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)!
input.text(in: all)   // "•••" (never "123")
```

The mask is the same length as the value rather than `nil`, because UIKit's own keyboard bridge
builds the keyboard's document context from `text(in:)` on every keystroke. A consistent length
and word boundaries keep deletion and autocapitalization working, while the system keyboard and
any third-party keyboard extension receive only bullets. Field length and the PAN grouping stay
visible, but your app already gets both through `panDigitCount` and the detected brand.

The fields also force tabular (fixed-width) digits on the font you set in `SecureFieldsStyle`.
With proportional digits, the per-character rectangles `UITextInput` exposes
(`firstRect(for:)`, `selectionRects(for:)`) differ by digit (a system-font `1` is about 3pt
narrower), which would let code measure the PAN it cannot read. A custom font with no tabular
figures cannot honour this, so prefer one that has them.

### Read via accessibility

`accessibilityValue` is also overridden to return `nil`, so code in your app reading the
property gets nothing. This does not reach UIKit's accessibility runtime, which serves assistive
technologies through a private path of its own: VoiceOver and UI-testing tools can still read
what is in the field, which is also what lets a VoiceOver user check what they typed.

### Access the internal field views

All card field classes (`SecurePANField`, `SecureCVVField`, etc.) are `internal` to the SDK.
They are not reachable via the public API.

---

## Limits of in-process isolation

The controls above close the read paths in UIKit's **public** API: the properties a
`UITextField` exposes, and the `UITextInput` protocol it conforms to. They keep card data out of
your code paths, including SDKs that read text fields as a matter of course (analytics,
session replay). They are not a boundary against code built to attack the SDK from inside your
app's process, and no SDK running in that process can be one.

### Swizzling and runtime access: assessment

Your app, and every third-party SDK linked into it, runs in the same process as the card fields,
with the same privileges. The Objective-C runtime offers that code several ways around the
overrides:

| Technique | Example |
|---|---|
| Method swizzling | Replacing `-[SecureBaseField text]` with the original implementation, or `-[UITextField insertText:]` with one that records each keystroke |
| Calling the superclass implementation | Looking up `UITextField`'s own `text` getter with `class_getMethodImplementation` and calling it on the field (no swizzling needed) |
| Private keys and views | Key-value coding on undocumented keys (`_text`, `textStorage`), or `UITextInput` reads on UIKit's private field-editor subview |
| Accessibility runtime | Querying the field through UIKit's private accessibility interfaces (see [Read via accessibility](#read-via-accessibility)) |
| Memory and pixels | Reading the process heap, or rendering the window to an image and running OCR on it |

**Decision: accepted, not countered in code** (SDK-12548, October 2026). Options considered:

1. **Runtime integrity checks.** Compare the implementations of the overridden methods with
   the expected ones at mount and before submit, and refuse to tokenize on a mismatch.
   Rejected: a check only sees the methods it knows about, the check itself can be swizzled
   out, and it is blind to every other row of the table. It would also fail real checkouts
   on false positives, since analytics, APM, session-replay and UI-testing SDKs legitimately
   swizzle UIKit.
2. **A custom input view instead of `UITextField`.** Keep the value in private Swift storage
   and draw it ourselves. Rejected: it removes only the `UITextField`-specific rows.
   Keystrokes still arrive through `insertText(_:)`, which can be swizzled; the value still
   lives in process memory; the digits are still on screen. It would also give up UIKit
   behaviours the SDK relies on: selection, pasting a 19-digit Oney PAN, and Wallet autofill
   and card scanning through `textContentType`.
3. **Accept and document.** Retained. The SDK guarantees that no public API returns card
   data, whether a property read, a `UITextInput` call, a documented KVC key, or a cast to
   `UITextField` or `UITextInput`. Against deliberately hostile code, the control is what you
   ship: review the third-party SDKs you link, do not load code at runtime, and, if your risk
   model calls for it, refuse to render the form on a compromised device (see
   [Jailbreak detection](#jailbreak-detection-optional-high-security-environments)).
   Raise this with your QSA when scoping.

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
| **Field value getter override** | `UITextField.text` and `attributedText` return `nil` — external code cannot read card data through a cast to `UITextField` |
| **`UITextInput` reads masked** | `text(in:)` and `attributedText(in:)` return one `•` per character (whitespace kept) — the protocol path, and the keyboard's document context, never carry the value |
| **Tabular digits** | Fonts are forced to fixed-width digits, so the character geometry `UITextInput` exposes does not depend on which digit was typed |
| **`accessibilityValue` returns `nil`** | Code reading the property gets nothing. UIKit's accessibility runtime still serves the value to assistive technologies (see [Read via accessibility](#read-via-accessibility)) |
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
| **`VaultEnvironment.test` cannot reach a merchant's users** | Guarded at runtime: honoured only on a development build (simulator, or `get-task-allow` in the provisioning profile), downgraded to `.production` with a warning in a release-signed app. The case ships in the binary because the distributed XCFramework is archived in Release, so a compile-time guard would remove it from every shipped build — which is why the guard is a runtime one |


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
