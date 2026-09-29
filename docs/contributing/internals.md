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
- [Remote log monitoring](#remote-log-monitoring)
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

`SecureFieldsManager.scheduleBinLookup(digits:)` debounces lookups by 300 ms and starts once the
PAN has at least 8 digits:

```
POST /v1/tenants/{tenantId}/bin-lookup
{ "first_digits": "12345678" }
```

The prefix grows with the PAN up to the 11 digits the gateway accepts, so the lookup is repeated
at 8, 9, 10 and 11 digits — a BIN that only becomes discriminant past 8 digits would otherwise
never resolve. Beyond 11 digits the request body would be identical, so the prefix cache
(`lastBinPrefix`) stops re-querying. A failed lookup is not cached and retries on the next PAN
change. Responses carry the generation of the lookup that asked for them and are dropped when a
newer lookup has since been launched, so an out-of-order answer cannot undo a fresher detection.

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

`expiry_month` and `expiry_year` are omitted outright when the form configures no `expDate`
field — never sent as `0`. The gateway then rejects the request (`INVALID_FORM` / "Invalid expiry
date"); the SDK does not pre-empt it. Android does the same, via `toIntOrNull()` on an empty
expiry string.

For Oney flows the CVV field holds a birth date rather than a PIN, and the request carries
**neither** key — the gateway accepts no birth-date field and rejects a request containing one
with a 400. The date never leaves the device. Same contract as the web and Android SDKs:

```json
{
  "card": { ... }
}
```

**Response:**

```json
{
  "form_token": "tok_xxx",
  "card": { "bin": "41111111", "last_four_digits": "1111" }
}
```

`VaultAPIClient` uses `URLSession(configuration: .ephemeral)` — no URL cache, no cookie
storage. 5xx responses are retried up to three times. Transport errors and 4xx responses are
not retried to avoid creating duplicate vault tokens.

---

## Remote log monitoring

`Monitoring/` forwards health telemetry to Datadog via Purse's monitoring ingestion endpoint,
matching the wire format used by Purse's other SecureFields SDKs:

```
MonitoringCoordinator  ← SecureFieldsManager's ONLY awareness of monitoring
└── RemoteLogger       ← info()/warn()/error()
    ├── LogQueue       ← buffers events, flushes at 16 events / 2s idle / 64KB, mirrors web SimpleQueue
    └── RemoteLogClient ← POST {monitoringApiRoot}/widget/secure_fields?api-key=…
```

- **`SecureFieldsManager` carries no monitoring state** — no counters, no payload-building, no
  `RemoteLogger` reference. It constructs one `MonitoringCoordinator` and calls
  `start(config:)`/`unmount()` at construction/`deinit`, plus `recordFocusChanged`/
  `recordBrandsDetected`/`recordBrandSelected`/`recordSubmitStart`/`recordSubmitSuccess`/
  `recordSubmitFailure` at the exact points inside field callbacks / BIN lookup / `submit()`
  where it already calls into its own `delegate`. Everything else — deriving the submit-outcome
  summary, building log payloads — lives in `MonitoringCoordinator`. Unlike Android's
  `MonitoringCoordinator` (which registers itself as a `SecureFieldsListener` and observes events
  generically, since `SecureFieldsAndroid` supports multiple listeners), `SecureFieldsManager` has
  only a single `delegate` slot, so these are explicit one-line hook calls at the same call sites
  rather than a listener registration — same end result (zero monitoring state on the manager),
  different wiring mechanism because of that platform difference. The intent is unchanged:
  telemetry is derived from events the manager already reports, not threaded through its
  business logic as ad hoc state.
- `RemoteLogger` is deliberately kept **separate from `VaultAPIClient`** so remote sending can be
  opted out independently, and so a telemetry failure can never affect PCI flows (tokenization,
  BIN lookup). It has no dependency on `VaultAPIClient` or vice versa.
- **No suppression window.** Events are sent continuously, as they happen — including while the
  secure fields are on screen. PCI
  safety comes from every payload being structural metadata only (field names, brand lists,
  outcome codes) — `MonitoringCoordinator` never has access to raw field values in the first
  place, so there's nothing for it to accidentally log.
- **Enable/disable**: `RemoteLogger` resolves a `RemoteLogClient?` at construction — `nil` when
  `apiKey` is missing/empty or `monitoringEnabled` is `false`. `enabled = (client != nil)` gates
  every log call.
- **Wire format**: each event is a flat `SecureFieldsLog` — `tenantId`, `instanceId` (random UUID
  per manager instance), `version`, `date` (ISO 8601), `env`, `level`
  (`OK`/`DEBUG`/`VERBOSE`/`NOTICE`/`WARNING`/`ERROR`), `code`, `payload` (a small `JSONValue` enum
  standing in for arbitrary JSON — structural metadata only). A batch is a JSON array of these,
  POSTed as the request body. This is the same shape Purse's other SecureFields SDKs produce.
- **Emitted events** (`LogCode` in `SecureFieldsLog.swift`): `INIT_SDK` (brand list, from
  `start(config:)`), `FIELD_FOCUS`/`FIELD_BLUR` (from `recordFocusChanged`), `BRAND_DETECTED`/
  `BRAND_NOT_DETECTED` (from `recordBrandsDetected`), `BRAND_SELECTION_CHANGED` (from
  `recordBrandSelected`), `SUBMIT`/`SUBMIT_SUCCESS`/`ERROR` (from `recordSubmitStart`/
  `recordSubmitSuccess`/`recordSubmitFailure`), and `DESTROY` (submit attempt/success counts,
  non-sensitive error codes only — never the error message — from `unmount()`). Mirrors the web
  vault SDK's `LOG_CODES`; there is no `RENDER`/`FORM_READY` pair like Android's, since iOS has
  no separate render step — fields exist as soon as the manager is constructed.
- `LogQueue` is a small serial-`DispatchQueue`-backed buffer (no Combine, no async/await, matching
  the rest of the codebase) rather than a coroutine-based queue. `RemoteLogClient` follows the
  same DI pattern as `VaultAPIClient`: a production init building an ephemeral `URLSession`, and a
  test-only `init(session:)` for injecting a mock. Sends are fire-and-forget — no retry, no error
  propagation to the caller.
- A `didEnterBackgroundNotification`/`willTerminateNotification` observer pair (registered once,
  independent of `obscuresOnBackground`) flushes any buffered logs so app backgrounding doesn't
  silently drop them.

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
