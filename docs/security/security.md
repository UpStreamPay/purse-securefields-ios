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

### Copy, cut or archive the PAN

Copy and Cut are hidden from the PAN field's edit menu, and the `copy(_:)` and `cut(_:)`
actions themselves do nothing on it, so calling them directly (`selectAll(nil); copy(nil)`)
does not put the PAN on the general pasteboard either.

The card fields encode nothing when archived. `NSKeyedArchiver` run on an exposed view
(`panContainer`, `cvvView`…) or on a view containing it does not capture the value.

### Access the internal field views

All card field classes (`SecurePANField`, `SecureCVVField`, etc.) are `internal` to the SDK.
They are not reachable via the public API.

---

## Limits of in-process isolation

The controls above close specific read paths on the card fields themselves: the properties a
`UITextField` exposes, the `UITextInput` protocol it conforms to, the `text` KVC key, casts to
`UITextField` or `UITextInput`, the pasteboard actions and keyed archiving. They keep card data
out of your code paths, including SDKs that read text fields as a matter of course (analytics,
session replay). They are not a boundary against code built to attack the SDK from inside your
app's process, and no SDK running in that process can be one.

### Known limit: the field editor while a field is focused

While a card field is first responder, UIKit adds a private field-editor view (`UIFieldEditor`)
under it, and that view answers `UITextInput` with the unmasked value. The class is private,
but reaching it takes only public API: walk the exposed view's `subviews` recursively, cast
each to `UITextInput` and call `text(in:)`. The SDK cannot override a private UIKit class, and
hiding the subview would not help, since the same view is reachable through `layer.sublayers`
and `CALayer.delegate`. Once the field resigns first responder the editor is gone and the walk
returns only the mask.

This read requires code that looks for the editor on purpose; analytics and session-replay
SDKs read the text field itself, which is masked. It is grouped with the other deliberate
in-process techniques below.

### Swizzling and runtime access: assessment

Your app, and every third-party SDK linked into it, runs in the same process as the card fields,
with the same privileges. The Objective-C runtime offers that code several ways around the
overrides:

| Technique | Example |
|---|---|
| Method swizzling | Replacing `-[SecureBaseField text]` with the original implementation, or `-[UITextField insertText:]` with one that records each keystroke |
| Calling the superclass implementation | Looking up `UITextField`'s own `text` getter with `class_getMethodImplementation` and calling it on the field (no swizzling needed) |
| Private keys and views | Key-value coding on undocumented keys (`_text`, `textStorage`), or `UITextInput` reads on UIKit's field-editor subview while the field is focused (public calls on a private view, see above) |
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
3. **Accept and document.** Retained. The SDK guarantees that the card fields themselves never
   return card data, whether through a property read, a `UITextInput` call, the `text` KVC key,
   a cast to `UITextField` or `UITextInput`, the copy and cut actions, or keyed archiving. It
   does not cover the focused field's editor subview described above. Against deliberately
   hostile code, the control is what you ship: review the third-party SDKs you link, do not
   load code at runtime, and, if your risk model calls for it, refuse to render the form on a
   compromised device (see
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
| **Card copies zeroed after send** | The PAN, CVV and cardholder name the SDK copies to build the tokenization request are held in `SensitiveBuffer`s, never `String`s. They are zeroed as soon as the request body is built from them, and the body once the gateway has answered (after any 5xx retries) — see [Card data in memory](#card-data-in-memory) |
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
