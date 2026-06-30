# AGENTS.md — PurseSecureFields iOS SDK

Instructions for AI agents working on this codebase.

## Build & verify

```bash
xcodebuild -scheme PurseSecureFields -destination 'generic/platform=iOS Simulator' build
```

Always run a clean build after changes. BUILD SUCCEEDED is the acceptance bar.

## Project layout

```
Sources/PurseSecureFields/
  Models/           — CardBrand, SecureFieldsConfig (+ Style + Placeholders), SecureFieldsError, TokenizationResult
  Networking/       — VaultAPIClient, NetworkModels (BIN lookup + tokenization payloads)
  Internal/         — CardFormatter (PAN display grouping), CardValidator (Luhn, expiry)
  Views/            — SecureBaseField, SecurePAN/CVV/ExpDate/HolderNameField, SecurePANContainer, SecureBrandSelectorView
  SecureFieldsManager.swift   — public API entry point
  SecureFieldsDelegate.swift  — delegate protocol + SecureField enum
Demo/Sources/       — DemoViewController (3 files), AppDelegate
Tests/              — SecureFieldsTests
```

## Key design invariants — do not break

### Field isolation (PCI)
- `SecureBaseField` is `internal` — never make it or its subclasses `public`
- Three read-blocking overrides in `SecureBaseField` prevent the host app from reading card data via UITextField casts. Do not remove any of them:
  - `override var text: String? { get { nil } … }` — blocks `(field as? UITextField)?.text`
  - `override var attributedText: NSAttributedString? { get { nil } … }` — blocks `attributedText` reads (which would expose card data even with the `text` override)
  - `override var accessibilityValue: String? { get { nil } … }` — blocks VoiceOver / accessibility API reads
- UIKit renders from its internal backing storage and is unaffected by these getter overrides.
- All internal reads use `super.text` (bypasses the nil override). Never change these to `self.text`.
- PAN, CVV, expDate, holderName fields are `private` in the manager. They are exposed only as `UIView` (`cvvView`, `expDateView`, `holderNameView`) or `SecurePANContainer` (`panContainer`).
- CVV paste is blocked via `canPerformAction`. Do not remove.
- PAN copy and cut are blocked via `canPerformAction` on `SecurePANField`. Paste is intentionally allowed (required for 19-digit Oney PAN pasting). Do not add a paste block to SecurePANField.
- PAN drag-out is blocked by `SecurePANField` conforming to `UITextDragDelegate` and returning `[]` from `itemsForDrag`. Do not remove.
- Screenshot detection: `setupPrivacyObservers()` observes `UIApplication.userDidTakeScreenshotNotification` and calls `delegate?.secureFieldsScreenshotDetected()`. Host app should call `manager.clearFields()` in response.

### BIN lookup behaviour
- Triggered at ≥ 6 digits, debounced 300ms, cached by 8-digit prefix.
- API returns `pan_lengths: [Int]` and `cvv_lengths: [Int]`. These drive `panField.validLengths` and `cvvField.expectedLength` — never hardcode lengths per brand.
- Validity: `validLengths.contains(digits.count) && luhn` — supports multi-length brands (e.g. Visa 16 or 19).
- Scheme normalisation: API returns `AMERICAN_EXPRESS` → map to `AMEX`, `DINERS_CLUB` → `DINERS` in `NetworkModels.normaliseScheme`.

### Oney specifics
- 19-digit PAN (4-4-4-4-3 display), detected when `digits.count > 16` in `CardFormatter`.
- CVV field switches to `UIDatePicker` (birthdate mode) when brand is Oney.
- Tokenization payload sends `birth_date` instead of `cvv` for Oney.

### No auto-clear on submit
- `submit()` does NOT clear fields on success. Host app calls `manager.clearFields()` explicitly.

## Networking
- All requests require HTTPS (enforced via `precondition` in `SecureFieldsConfig`).
- `X-Purse-SDK-Version` header on every request. Version string is in `VaultAPIClient.sdkVersion`.
- `X-Request-ID` (UUID) on tokenization only.
- No card data in logs. Body logging is fully removed. `#if DEBUG` guards on status codes only.
- **SPKI certificate pinning**: `SecureFieldsConfig.pinnedPublicKeyHashes` accepts Base64-encoded SHA-256 SPKI hashes. When set, `VaultAPIClient` enforces pinning via `PinningDelegate` (a private `URLSessionDelegate`). Supported key types: RSA-2048, RSA-4096, EC-256, EC-384. Provide ≥ 2 hashes (primary + rotation backup). A `#if DEBUG` warning is printed when hashes are empty. **Production integrations must set this field.**
- `VaultAPIClient` has two inits: `init(baseURL:pinnedPublicKeyHashes:)` for production (creates pinned session), and `init(baseURL:session:)` for test injection only (pinning skipped). Never call the test init in production code.

## Style / placeholder config
- Applied once at init via `applyConfig(_:)` in the manager.
- `SecureFieldsStyle` sets font, textColor, tintColor, keyboardAppearance, placeholderColor.
- `SecureFieldsPlaceholders` sets per-field placeholder strings.
- No `setPlaceholders` runtime method — config is the single source.

## Delegate events
- `secureFieldsContentChanged()` — fires on every keystroke/change in any field.
- `secureFieldsFocusChanged(field:isFocused:)` — fires on focus in/out.
- `secureFieldsFormValidityChanged(_:)` — fires only when overall form validity flips.
- `secureFieldsBrandsDetected(_:)` — fires after BIN lookup.
- `secureFieldsBrandSelected(_:)` — fires when user taps a brand chip (multi-brand card).

## CardFormatter grouping rules
- Amex (prefix 34/37): 4-6-5
- Digits > 16: 4-4-4-4-3 (Oney 19-digit)
- Default: 4-4-4-4

## Luhn implementation
Standard Luhn in `CardValidator.luhn(_:)`. Double every second digit from the right (index 1, 3, 5…). Sum > 9 subtract 9. Total % 10 == 0 is valid.

## What NOT to do
- Do not add logging of card data anywhere, including in debug builds.
- Do not add `public` to `SecureBaseField`, `SecurePANField`, `SecureCVVField`, `SecureExpDateField`, or `SecureHolderNameField`.
- Do not re-add `setPlaceholders` to the manager — use `SecureFieldsConfig`.
- Do not truncate PAN input — `maxLength` was replaced by `validLengths` for a reason (pasting a 19-char Oney PAN before BIN lookup would be truncated).
- Do not use `self.text` inside field implementations — always `super.text`.
- Do not call `clearFields()` automatically after `submit()` — the host app decides lifecycle.

## Adding a new card brand
1. Add case to `CardBrand` enum with the API raw value string.
2. Add SVG badge to `Sources/PurseSecureFields/Resources/Badges.xcassets/`.
3. Add normalisation entry in `NetworkModels.normaliseScheme` if API scheme string differs from enum raw value.
4. No hardcoded lengths — BIN lookup drives them.

## Demo app
The Demo target is for manual testing only. It is not shipped. `DemoViewController` is split into three files: main state/lifecycle, `+Layout` (UI construction + border logic), `+Delegate` (delegate conformance).
