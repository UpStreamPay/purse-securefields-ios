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
  Models/           — CardBrand, SecureFieldsConfig (+ Style + Placeholders + FieldsConfig), SecureFieldsError, TokenizationResult, VaultEnvironment
  Networking/       — VaultAPIClient, NetworkModels (BIN lookup + tokenization payloads)
  Monitoring/       — RemoteLogger, RemoteLogClient, LogQueue, SecureFieldsLog (remote log monitoring, separate from VaultAPIClient)
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
- API returns `pan_lengths: [Int]` and `cvv_lengths: [Int]`. These drive `panField.validLengths` and `cvvField.validLengths` — on a form with a PAN field the lookup is the only source of lengths, never a hardcoded table. The one exception is the CVV-only form, which has no PAN to look up: `CardBrand.standingCVVLengths` (Amex 4, other PIN brands 3, Oney nil) stands in for the lookup there, exactly as web's `DEFAULT_BRANDS` and Android's `BrandDescription` table do. Never read that table on a form that has a PAN field.
- Validity: `validLengths.contains(digits.count) && luhn` — supports multi-length brands (e.g. Visa 16 or 19).
- Scheme normalisation: API returns `AMERICAN_EXPRESS` → map to `AMEX`, `DINERS_CLUB` → `DINERS` in `NetworkModels.normaliseScheme`.

### Oney specifics
- 19-digit PAN (4-4-4-4-3 display), detected when `digits.count > 16` in `CardFormatter`.
- CVV field switches to `UIDatePicker` (birthdate mode) when brand is Oney.
- Tokenization payload sends `birth_date` instead of `cvv` for Oney.

### Field buffers cleared on submit
- `submit()` calls `clearSensitiveData()` on all four fields immediately after building the tokenization payload (before the network call), per PCI compliance requirements. This only zeroes text/validity — it does NOT reset BIN lookup state, detected brands, or the brand selector. Host app still calls `manager.clearFields()` for a full reset (e.g. to start a new form).

## Networking
- All requests are HTTPS by construction — `VaultEnvironment.apiRoot` is a fixed `https://` literal per case, so there's no raw URL for a host app to get wrong. `SecureFieldsConfig` no longer takes a `baseURL` parameter at all.
- `X-Purse-SDK-Version` header on every request. Version string is in `VaultAPIClient.sdkVersion`.
- `X-Request-ID` (UUID) on tokenization only.
- No card data in logs. Body logging is fully removed. `#if DEBUG` guards on status codes only.
- **SPKI certificate pinning**: `SecureFieldsConfig.pinnedPublicKeyHashes` accepts Base64-encoded SHA-256 SPKI hashes. When set, `VaultAPIClient` enforces pinning via `PinningDelegate` (a private `URLSessionDelegate`). Supported key types: RSA-2048, RSA-4096, EC-256, EC-384. Provide ≥ 2 hashes (primary + rotation backup). A `#if DEBUG` warning is printed when hashes are empty. **Production integrations must set this field.**
- `VaultAPIClient` has two inits: `init(baseURL:pinnedPublicKeyHashes:)` for production (creates pinned session), and `init(baseURL:session:)` for test injection only (pinning skipped). Never call the test init in production code.

## Remote log monitoring
- `SecureFieldsManager` carries **no monitoring state** — no counters, no payload-building. It owns one `MonitoringCoordinator` (in `Monitoring/`) and only ever calls `start(config:)`/`unmount()` (construction/`deinit`) and `recordFocusChanged`/`recordBrandsDetected`/`recordBrandSelected`/`recordSubmitStart`/`recordSubmitSuccess`/`recordSubmitFailure` at the same points it already calls its own `delegate`. If you're about to add a counter or `JSONValue` payload directly to `SecureFieldsManager`, stop — that logic belongs in `MonitoringCoordinator`.
- `MonitoringCoordinator` owns a `RemoteLogger` — a separate, opt-out logger from `VaultAPIClient`'s local `#if DEBUG` prints — which forwards `info`/`warn`/`error` events to Purse's monitoring ingestion endpoint for Datadog. Configured via `SecureFieldsConfig.apiKey`/`monitoringEnabled`/`environment`; disables itself silently when `apiKey` is missing.
- **No suppression window.** Events are sent continuously, as they happen — including while the secure fields are on screen. PCI safety comes from every payload being structural metadata only (field names, brand lists, outcome codes) — `MonitoringCoordinator` never has access to raw field values in the first place, so there's nothing to accidentally log. If you're adding a new event, the question is never "should this wait until `deinit`" — it's "does this payload contain anything other than a field name, brand, count, or non-sensitive code."
- Log payloads carry only structural metadata (brand list, submit outcome counts, non-sensitive error codes like `"NETWORK_ERROR"` or an HTTP status string) — never the error `message`, which could echo back arbitrary server text.
- Kept as a separate class/network stack from `VaultAPIClient` on purpose, so a telemetry failure can never affect PCI flows.
- `VaultEnvironment.test` is wrapped in `#if DEBUG` — never remove that guard or add a similar always-compiled "internal/test" option. The distributed XCFramework is always built in `Release` configuration (`xcodebuild archive` in release.yml), so `#if DEBUG` is the only mechanism that actually keeps something out of what merchants integrate — a runtime check (like Android's `FLAG_DEBUGGABLE` guard) would NOT work here, since this framework isn't recompiled per host app.

## Style / placeholder config
- Applied once at init via `applyConfig(_:)` in the manager.
- `SecureFieldsStyle` sets font, textColor, tintColor, keyboardAppearance, placeholderColor.
- `SecureFieldsPlaceholders` sets per-field placeholder strings. A `SecureFieldConfig.placeholder` in `fields` wins over it.
- No `setPlaceholders` runtime method — config is the single source.

## Per-field config / CVV-only mode
- `SecureFieldsConfig.fields: SecureFieldsFieldsConfig` decides which fields exist. **Presence decides rendering** (nil = not part of the form), mirroring Android's `SecureFieldsFieldsConfig`. `cvv` is the only mandatory field; `.all` is the default, `.cvvOnly` the CVV alone.
- All four fields are still constructed in the manager whatever `fields` says, so state accessors (`isFieldValid`, `panDigitCount`, `expectedLengths`…) keep answering for unconfigured fields — the E2E harness state probe reads all four. Unconfigured views are `isHidden = true` and `isUserInteractionEnabled = false`. Do not make the view accessors optional.
- `configuredFields` (public) drives form validity and the `submit()` guard: every configured field counts, except `holderName` which also needs `requiresHolderName`.
- `isCVVOnly` = no PAN field. Then `submit()` skips brand resolution, ignores `selectedNetwork`/`saveToken` with an `NSLog`, and builds `TokenizationPayload(cvv:, card: nil)` → body is literally `{"cvv": "…"}`. **Never emit `card`, even empty** — the gateway rejects a `card` without expiry (`INVALID_FORM`).
- Default CVV lengths (`defaultCVVLengths`) are `[3]` on a form with a PAN field. In CVV-only they come from the brand the host named through `selectBrand(_:)` (`cvvOnlySelectedBrand`), else from `CardBrand.cvvOnlyLengths(for: config.brands)`: one PIN brand its exact length, several the union, none `[3, 4]`. Applied at init, in `clearFields()` and in the BIN-lookup reset branch. Keep those three in sync. The CVV-only selection deliberately survives `clearFields()` — the saved card does not change between attempts.
- `selectBrand(_:)` is public and mirrors Android's `setBrandSelection`: CVV-only → narrows the CVV length (Oney refused with a warning, field stays in `.cvv` mode); full form → `SecureBrandSelectorView.select(_:)`, a programmatic chip tap, refused when the brand is not in `detectedBrands`. The brand never goes on the wire in CVV-only.
- `TokenizationResponse.card` and `TokenizationResult.bin`/`lastFourDigits` are optional: a CVV-only response is `{"form_token": "…"}` with no card block. There is no `cvv_token` in any SDK — the form token is the result.
- A configured `pan` requires a configured `expDate` (precondition) until `submit()` gains an expiry override.
- Not supported yet: Oney birthdate in CVV-only (field stays in `.cvv` mode; web/Android skip the network call and return only a birth date — needs its own result shape).

## Delegate events
- `secureFieldsContentChanged()` — fires on every keystroke/change in any field.
- `secureFieldsFocusChanged(field:isFocused:)` — fires on focus in/out.
- `secureFieldsFormValidityChanged(_:)` — fires only when overall form validity flips.
- `secureFieldsBrandsDetected(_:)` — fires after BIN lookup.
- `secureFieldsBrandSelected(_:)` — fires when user taps a brand chip (multi-brand card) or the host calls `selectBrand(_:)` (both modes).

## CardFormatter grouping rules
- Amex (prefix 34/37): 4-6-5
- Digits > 16: 4-4-4-4-3 (Oney 19-digit)
- Default: 4-4-4-4

## Luhn implementation
Standard Luhn in `CardValidator.luhn(_:)`. Double every second digit from the right (index 1, 3, 5…). Sum > 9 subtract 9. Total % 10 == 0 is valid.

## What NOT to do
- Do not add logging of card data anywhere, including in debug builds.
- Do not add a `RemoteLogger.info/warn/error` call anywhere between `SecureFieldsManager.init` setting `mounted = true` and `deinit` setting it back to `false` — that entire window must stay silent by design (PCI). If you need new telemetry, add it to the `INIT_SDK` or `DESTROY` payloads instead.
- Do not add `public` to `SecureBaseField`, `SecurePANField`, `SecureCVVField`, `SecureExpDateField`, or `SecureHolderNameField`.
- Do not re-add `setPlaceholders` to the manager — use `SecureFieldsConfig`.
- Do not truncate PAN input — `maxLength` was replaced by `validLengths` for a reason (pasting a 19-char Oney PAN before BIN lookup would be truncated).
- Do not use `self.text` inside field implementations — always `super.text`.
- Do not call the full `clearFields()` automatically after `submit()` — only `clearSensitiveData()` per field runs there; BIN/brand state reset is still host-triggered.

## Adding a new card brand
1. Add case to `CardBrand` enum with the API raw value string.
2. Add SVG badge to `Sources/PurseSecureFields/Resources/Badges.xcassets/`.
3. Add normalisation entry in `NetworkModels.normaliseScheme` if API scheme string differs from enum raw value.
4. Add its CVV length to `CardBrand.standingCVVLengths` — used by CVV-only forms only. Everywhere else BIN lookup drives lengths; do not add PAN lengths anywhere.

## Demo app
The Demo target is for manual testing only. It is not shipped. `DemoViewController` is split into three files: main state/lifecycle, `+Layout` (UI construction + border logic), `+Delegate` (delegate conformance).
A "Mode" segmented control (`Full form` / `CVV only`, id `mode_control`) sits at the top of the form and rebuilds the screen in the chosen mode — `SecureFieldsConfig` is immutable, so `DemoViewController(isCVVOnly:)` is re-created and swapped into the navigation stack. The `--cvv-only` launch argument starts directly in CVV-only mode (used by the XCUITests). Keep the control out of the navigation bar: the UI tests tap the bar to dismiss the keyboard, and a title-view control would swallow that tap.
`TENANT_ID`/`MONITORING_API_KEY` come from `Demo/Resources/Info.plist`'s `$(VAR)` build-setting substitution, sourced from a gitignored `.env` at the repo root (see `.env.example`) via `source scripts/load-env.sh` — never hardcode real values in `DemoViewController.swift`. That script sets values with both `export` (for `xcodebuild` in the same shell) and `launchctl setenv` (so Xcode.app opened via Finder/Dock, which does not inherit shell env, still resolves them). Both vars fall back gracefully when unset — `TENANT_ID` to a shared sandbox tenant, `MONITORING_API_KEY` to `nil` (monitoring disabled) — so the demo still builds and runs without any `.env` file at all.
