# SDK Internals

How the native field layer works and how `SecureFieldsManager` coordinates it.

> This document is for contributors and reviewers. Integrators using the public API do not
> need it. For a summary of what the SDK exposes, see the
> [API Reference](../integration/api-reference.md).

---

## Table of Contents

- [Architecture overview](#architecture-overview)
- [SecureFieldsManager](#securefieldsmanager)
- [Field class hierarchy](#field-class-hierarchy)
- [Field isolation — the text getter override](#field-isolation--the-text-getter-override)
- [BIN detection](#bin-detection)
- [Card number formatting](#card-number-formatting)
- [Expiry formatting](#expiry-formatting)
- [CVV and Oney date-of-birth mode](#cvv-and-oney-date-of-birth-mode)
- [Tokenization](#tokenization)
- [Privacy and background blur](#privacy-and-background-blur)
- [Event dispatch](#event-dispatch)

---

## Architecture overview

The SDK uses native UIKit views for all card inputs. There are no WebViews, no remote JS
bundles, and no UIWebView. All formatting, validation, brand detection, and tokenization run
entirely in Swift within the SDK module.

```
SecureFieldsManager
├── SecurePANContainer
│   ├── SecurePANField          ← formats digits, triggers BIN lookup
│   └── SecureBrandSelectorView ← brand picker for co-branded cards
├── SecureExpDateField          ← enforces MM/YY format and date validity
├── SecureCVVField              ← digit-only or date picker (Oney)
└── SecureHolderNameField       ← free-text input

VaultAPIClient
├── binLookup()                 ← POST /v1/tenants/:id/bin-lookup
└── tokenize()                  ← POST /v1/tenants/:id/forms/secure-fields
```

---

## SecureFieldsManager

`SecureFieldsManager` is the public entry point. It:

- Instantiates all four field views and the brand selector
- Wires callbacks from each field to its own private handler methods
- Schedules BIN lookups with a 300 ms debounce when the PAN digit count changes
- Coordinates brand selector display when multiple brands are detected
- Initiates tokenization on `submit()`
- Manages the privacy overlay via `NotificationCenter` observers

---

## Field class hierarchy

```
UITextField
└── SecureBaseField          ← text getter override, validity tracking, callbacks
    ├── SecurePANField       ← digit grouping, Luhn check, brand-driven length limits
    ├── SecureCVVField       ← pin mode (numeric) or birthdate mode (date picker)
    ├── SecureExpDateField   ← auto-slash, month clamp, future-date validation
    └── SecureHolderNameField ← trimmed non-empty validation
```

`SecurePANContainer` wraps `SecurePANField` and `SecureBrandSelectorView` in a `UIView` with
horizontal layout. It has no logic of its own — it is purely a layout container.

---

## Field isolation — the text getter override

`SecureBaseField` overrides `text` and `attributedText` to return `nil`:

```swift
override var text: String? {
    get { nil }
    set { super.text = newValue }
}

override var attributedText: NSAttributedString? {
    get { nil }
    set { super.attributedText = newValue }
}

override var accessibilityValue: String? {
    get { nil }
    set { super.accessibilityValue = newValue }
}
```

UIKit renders from its internal backing store, bypassing the getter, so display is unaffected.
Subclasses read the actual value through `storedText`:

```swift
var storedText: String? { super.text }
```

This three-layer override covers direct casts (`(field as UITextField).text`), attributed text
reads, and VoiceOver/accessibility service reads.

---

## BIN detection

`SecureFieldsManager.scheduleBinLookup(digits:)` debounces lookups by 300 ms and sends the first
8 digits once the PAN has at least 6 digits:

```
POST /v1/tenants/{tenantId}/bin-lookup
{ "first_digits": "12345678" }
```

The response carries:
- `brands`: array of network strings (e.g. `["VISA", "CARTE_BANCAIRE"]`)
- `panLengths`: valid PAN lengths for this BIN
- `cvvLengths`: valid CVV lengths
- `perBrandLengths`: per-brand overrides (used when the user switches brands in the selector)

The manager filters `brands` against `SecureFieldsConfig.brands` (the allowed list) before
updating `SecureBrandSelectorView` and notifying the delegate via
`secureFieldsBrandsDetected(_:)`.

Re-lookup is skipped if the 8-digit prefix has not changed since the last successful response.
When the PAN drops below 6 digits, all brand state is cleared.

---

## Card number formatting

`SecurePANField` formats as the user types using `UITextFieldDelegate`:

| Brand | Digit groups | Max digits |
|---|---|---|
| Oney | 4 – 4 – 4 – 4 – 3 | 19 |
| Amex | 4 – 6 – 5 | 15 |
| All others | 4 – 4 – 4 – 4 | 13–19 |

After each keystroke, `SecurePANField` strips non-digit characters from the input, reformats
the raw digit string into groups, and repositions the cursor to account for added or removed
spaces.

Valid PAN lengths come from the BIN lookup response. Before a BIN result is available, the
default valid length is 16 (or 19 for Oney if `oney` is in the allowed brands list).

---

## Expiry formatting

`SecureExpDateField` enforces MM/YY format:

1. User types digits only; the `/` separator is inserted automatically after the second digit.
2. The month value is clamped to `01–12` as the user types.
3. On end-editing, the field validates that the expiry date is in the future.

The field is valid only when both month and year are entered and the date is not in the past.

---

## CVV and Oney date-of-birth mode

`SecureCVVField` operates in two modes driven by `SecureFieldsManager.applySelectedBrand(_:)`:

**Pin mode (default):** Numeric keyboard, `isSecureTextEntry = true`, length from BIN lookup
CVV lengths (default `[3]`, `[4]` for Amex).

**Birthdate mode (Oney):** The text field is hidden; tapping the field area opens a
`UIDatePicker` (`.date` mode, constrained to past dates). The selected date is stored as
`YYYY-MM-DD` in the internal buffer.

When the brand selection changes between modes, `clearSensitiveData()` is called to prevent a
CVV value from being submitted as a birthdate or vice versa.

---

## Tokenization

`VaultAPIClient.tokenize(tenantId:payload:completion:)` makes a single POST:

```
POST /v1/tenants/{tenantId}/forms/secure-fields
```

**Request:**

```json
{
  "cvv": "123",
  "card": {
    "pan": "4111111111111111",
    "card_holder_name": "Jane Doe",
    "expiry_month": 12,
    "expiry_year": 27,
    "save_token": false,
    "selected_network": "VISA"
  }
}
```

For Oney flows, `birthDate` replaces `cvv`:

```json
{
  "birth_date": "1990-06-15",
  "card": { ... }
}
```

**Response:**

```json
{
  "vault_form_token": "tok_xxx",
  "card": { "bin": "41111111", "last_four_digits": "1111" }
}
```

`VaultAPIClient` uses `URLSession(configuration: .ephemeral)` — no URL cache, no cookie
storage. 5xx responses are retried up to three times. Transport errors and 4xx responses are
not retried to avoid creating duplicate vault tokens.

---

## Privacy and background blur

`SecureFieldsManager.setupPrivacyObservers()` registers `NotificationCenter` observers:

| Notification | Effect |
|---|---|
| `UIApplication.willResignActiveNotification` | Apply blur overlay |
| `UIApplication.didBecomeActiveNotification` | Remove blur overlay |
| `UIScreen.capturedDidChangeNotification` | Apply or remove blur overlay based on `UIScreen.main.isCaptured` |
| `UIApplication.userDidTakeScreenshotNotification` | Fire `secureFieldsScreenshotDetected()` on delegate |

The blur overlay is a `UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))`
tagged `0xC1A` and added as a subview over each card view. The tag avoids adding duplicate
overlays if the notification fires multiple times before the active notification removes it.

When `obscuresOnBackground` is set to `false`, the observers are removed and the overlay is
never applied.

---

## Event dispatch

`SecureFieldsManager` wires closures on each field at init time:

```swift
panField.onDigitsChanged    = { [weak self] digits in ... }
panField.onValidityChanged  = { [weak self] _ in self?.notifyFormValidity() }
panField.onFocusChanged     = { [weak self] f in self?.delegate?.secureFieldsFocusChanged(field: .pan, isFocused: f) }
```

Events are dispatched on the main queue. Closures hold a `[weak self]` reference to prevent
retain cycles. All delegate calls are direct method invocations — no string keys, no
`NotificationCenter`, no `Combine`.
