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
  ThreeDS/          — ThreeDSProvider (+ PurseThreeDS registry), ThreeDSModels (+ AppSDKConfiguration), ThreeDSAPIClient, ThreeDSCoordinator, SecureFieldsManager+ThreeDS (Purse 3DS, Netcetera behind a protocol)
  Internal/         — CardFormatter (PAN display grouping), CardValidator (Luhn, expiry), SensitiveBuffer (+ SensitiveJSONWriter)
  Views/            — SecureBaseField, SecurePAN/CVV/ExpDate/HolderNameField, SecurePANContainer, SecureBrandSelectorView
  SecureFieldsManager.swift   — public API entry point
  SecureFieldsDelegate.swift  — delegate protocol + SecureField enum
Sources/PurseSecureFields3DS/
  NetceteraThreeDSProvider.swift — the optional product: the `ThreeDSProvider` adapter over the Netcetera SDK
Demo/Sources/       — DemoViewController (3 files), AppDelegate, SceneDelegate, DemoBackend (Alfred client + the advanced-flow payment and challenge)
Tests/              — SecureFieldsTests
```

## Key design invariants — do not break

### Field isolation (PCI)
- `SecureBaseField` is `internal` — never make it or its subclasses `public`
- Three read-blocking overrides in `SecureBaseField` prevent the host app from reading card data via UITextField casts. Do not remove any of them:
  - `override var text: String? { get { nil } … }` — blocks `(field as? UITextField)?.text`
  - `override var attributedText: NSAttributedString? { get { nil } … }` — blocks `attributedText` reads (which would expose card data even with the `text` override)
  - `override var accessibilityValue: String? { get { nil } … }` — blocks reads of the public property (UIKit's accessibility runtime still reads the value through its own private path; see docs/security/security.md)
- `text(in:)` and `attributedText(in:)` (the `UITextInput` read path) return `SecureBaseField.masked(_:)` — one `•` per UTF-16 unit, whitespace kept. **Never make them return `nil` or a different length**: UIKit's keyboard bridge (`UIKBRTIPartner`) builds the keyboard's document context from `text(in:)` on every keystroke, and offsets are UTF-16. `DemoUITests.testKeyboardDeleteStillEditsMaskedPAN` covers it.
- The `font` setter forces tabular digits (`withTabularDigits(_:)`). Do not bypass it with `super.font`: proportional digits make `firstRect(for:)`/`selectionRects(for:)` vary by digit, a geometry side channel on the PAN.
- `encode(with:)` is an empty override: `NSKeyedArchiver` on an exposed view would otherwise write the field's text (and, while focused, the field-editor subview's). Do not call `super` from it.
- Swizzling, calling `UITextField`'s implementation directly, private KVC keys, the `UIFieldEditor` subview (public `subviews` + `UITextInput` reach it unmasked while the field is focused — a documented known limit) and memory/pixel reads are out of reach of in-process controls. Accepted and documented in docs/security/security.md ("Limits of in-process isolation", SDK-12548). Do not add runtime integrity checks without revisiting that decision.
- UIKit renders from its internal backing storage and is unaffected by these getter overrides.
- All internal reads use `super.text` (bypasses the nil override). Never change these to `self.text`.
- PAN, CVV, expDate, holderName fields are `private` in the manager. They are exposed only as `UIView` (`cvvView`, `expDateView`, `holderNameView`) or `SecurePANContainer` (`panContainer`).
- CVV paste is blocked via `canPerformAction`. Do not remove.
- PAN copy and cut are blocked via `canPerformAction` on `SecurePANField` (menu and shortcuts), and `copy(_:)`/`cut(_:)` are no-op overrides there (direct calls skip `canPerformAction`). Paste is intentionally allowed (required for 19-digit Oney PAN pasting). Do not add a paste block to SecurePANField.
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

### Card data in memory (SDK-12549)
- `submit()` does **not** clear the fields when it sends the request, nor when tokenization fails: they keep their text so the cardholder can retry without re-entering the card. No PCI requirement calls for clearing them at submit: DSS 3.3.1 forbids *storing* SAD after authorization, and a displayed field is not storage.
- On **success** the completion calls the full `clearFields()` (fields + BIN/brand state) before `secureFieldsDidTokenize`, so a tokenized card never lingers and stale brand state cannot bleed into the next transaction. This is a deliberate divergence from Android, which keeps the fields until `destroy()`.
- What *is* zeroed is the SDK's own copy of the card. `submit()` copies the PAN, CVV and holder name into `SensitiveBuffer`s (`copyRawValue()` / `copyTrimmedValue()` on the fields — never `rawValue`, which is a `String`) to build `TokenizationPayload`. `VaultAPIClient.tokenize(tenantId:payload:)` writes the JSON body with `SensitiveJSONWriter`, wipes the payload, and wipes the body when `perform` completes (after retries). Keep `JSONEncoder` and `String` off that path.
- `SensitiveBuffer.data()` hands the body to `URLRequest` without a copy — but `Data` copies anything ≤ 14 bytes into its inline storage, so `jsonBody()` pads short bodies (the CVV-only `{"cvv":"123"}`) with trailing JSON whitespace up to `minimumSharedCount`. Don't remove that padding.
- `clearFields()` does not wipe an in-flight request body: a host may well call it right after `submit()`, and zeroing the body before URLSession has sent it would fail the tokenization. The body is wiped on completion, or on release whatever the path.
- Known limit: UIKit stores a `UITextField`'s text in a `String` the SDK cannot zero. See `docs/security/security.md`, "Card data in memory".

## Networking
- All requests are HTTPS by construction — `VaultEnvironment.apiRoot` is a fixed `https://` literal per case, so there's no raw URL for a host app to get wrong. `SecureFieldsConfig` no longer takes a `baseURL` parameter at all.
- `X-Purse-SDK-Version` header on every request. Version string is in `VaultAPIClient.sdkVersion`.
- `X-Request-ID` (UUID) on tokenization only.
- No card data in logs. Body logging is fully removed. `#if DEBUG` guards on status codes only.
- **SPKI certificate pinning**: `SecureFieldsConfig.pinnedPublicKeyHashes` accepts Base64-encoded SHA-256 SPKI hashes. When set, `VaultAPIClient` enforces pinning via `PinningDelegate` (a private `URLSessionDelegate`). Supported key types: RSA-2048, RSA-4096, EC-256, EC-384. Provide ≥ 2 hashes (primary + rotation backup). A `#if DEBUG` warning is printed when hashes are empty. **Production integrations must set this field.**
- `VaultAPIClient` has two inits: `init(baseURL:pinnedPublicKeyHashes:)` for production (creates pinned session), and `init(baseURL:session:)` for test injection only (pinning skipped). Never call the test init in production code.
- `SecureFieldsConfig.urlSessionOverride` reaches `init(baseURL:session:)` only through `VaultAPIClient.make(…, isDebugHost:)`, which ignores it (with an `NSLog`) on a release-signed host, exactly like `VaultEnvironment.resolve` does for `.test` (SDK-12425). The manager computes `isDebugHost` once and passes it to both. Never build the manager's client from the override without that guard.

## Remote log monitoring
- `SecureFieldsManager` carries **no monitoring state** — no counters, no payload-building. It owns one `MonitoringCoordinator` (in `Monitoring/`) and only ever calls `start(config:)`/`unmount()` (construction/`deinit`) and `recordFocusChanged`/`recordBrandsDetected`/`recordBrandSelected`/`recordSubmitStart`/`recordSubmitSuccess`/`recordSubmitFailure` at the same points it already calls its own `delegate`. If you're about to add a counter or `JSONValue` payload directly to `SecureFieldsManager`, stop — that logic belongs in `MonitoringCoordinator`.
- `MonitoringCoordinator` owns a `RemoteLogger` — a separate, opt-out logger from `VaultAPIClient`'s local `#if DEBUG` prints — which forwards `info`/`warn`/`error` events to Purse's monitoring ingestion endpoint for Datadog. Configured via `SecureFieldsConfig.apiKey`/`monitoringEnabled`/`environment`; disables itself silently when `apiKey` is missing.
- **No suppression window.** Events are sent continuously, as they happen — including while the secure fields are on screen. PCI safety comes from every payload being structural metadata only (field names, brand lists, outcome codes) — `MonitoringCoordinator` never has access to raw field values in the first place, so there's nothing to accidentally log. If you're adding a new event, the question is never "should this wait until `deinit`" — it's "does this payload contain anything other than a field name, brand, count, or non-sensitive code."
- Log payloads carry only structural metadata (brand list, submit outcome counts, non-sensitive error codes like `"NETWORK_ERROR"` or an HTTP status string) — never the error `message`, which could echo back arbitrary server text.
- `SUBMIT` carries the merchant's `submit` arguments as `{ arg0: { selectedNetwork?, saveToken } }`, the same shape as the web and Android SDKs, so one collector query covers every platform. Those two keys are an allowlist: never add another submit input to it.
- Kept as a separate class/network stack from `VaultAPIClient` on purpose, so a telemetry failure can never affect PCI flows.
- `VaultEnvironment.test` is wrapped in `#if DEBUG` — never remove that guard or add a similar always-compiled "internal/test" option. The distributed XCFramework is always built in `Release` configuration (`xcodebuild archive` in release.yml), so `#if DEBUG` is the only mechanism that actually keeps something out of what merchants integrate — a runtime check (like Android's `FLAG_DEBUGGABLE` guard) would NOT work here, since this framework isn't recompiled per host app.

## Purse 3DS (Netcetera, app channel)

Backend contract: `UpStreamPay/orchestration-api`, `doc/3DS/13-3DS-app-sdk-integration.md` (design in `12`,
tasks `SDK-APP-P3-1..4`, `P6-1`, `P7-1` in `02`). There is **no iframe and no 3DS Method** in the app: the 3DS SDK
collects the device data at init, `submit(threeDSEnabled:)` versions with `device_channel: APP` and builds the EMVCo
transaction locally, and the challenge runs natively.

### Two products: the Netcetera SDK stays out of the core
- `ThreeDSProvider` / `ThreeDSTransaction` are protocols in the core. The Netcetera 3DS Mobile SDK is behind them, in
  the **optional `PurseSecureFields3DS` product** of this same package (`Sources/PurseSecureFields3DS`, one file),
  which depends on the Netcetera `.binaryTarget`. Same pattern as the PayPal / Klarna products of Headless Checkout: a
  merchant who does not use Purse 3DS links no Netcetera code. So: **the `PurseSecureFields` target never depends on
  Netcetera**, and every Netcetera type name stays out of `Sources/PurseSecureFields`.
- There is no `securefields-3ds` repository. Docs 12 / 13 of `orchestration-api` still describe one (D13); that
  premise was wrong — Netcetera publish the XCFramework themselves on an unauthenticated Maven repository and their
  FAQ ("API Key & Distribution") explicitly allows bundling it in an integrator's SDK. What they forbid is embedding
  the **API key** in source or in a published artifact.
- Their own SPM package (`github.com/ios-3ds-sdk/SPM`) is pinned to **2.6.00** and stale; `Package.swift` declares
  **2.7.01** from their Nexus directly, by checksum. The two are not API-compatible: 2.6.00 is synchronous and
  `@objc`, 2.7.x is `async`. 2.7.01 is built with Xcode 26.4 — the floor for anyone linking the 3DS product.
- The provider is found at runtime: a class `@objc(PurseSecureFields3DSProvider)` with a no-argument `init`,
  conforming to `ThreeDSProvider` (`PurseThreeDS.discover()`, `NSClassFromString`). Linking the product is the whole
  switch; `PurseThreeDS.register(_:)` overrides it for tests. The class is not exported in a Release build and does
  not need to be — it is in `__objc_classlist`, which is what the lookup reads. Do not "fix" discovery by making the
  core import the 3DS target.
- **Linking, load-bearing:** the core product is `type: .dynamic` (the XCFramework build needs a framework). An app
  that links the dynamic `PurseSecureFields` product *and* `PurseSecureFields3DS` **from source** fails with
  `target 'PurseSecureFields' is linked as a static library by … but cannot be built dynamically because there is a
  package product with the same name`. That is why the Demo links `PurseSecureFields3DS` only (the core comes with
  it, statically). Merchants never hit it: in a release the core is a `.binaryTarget`, and the 3DS target is built
  from source against it — `release.yml` writes both into the tag's manifest, taking the Netcetera URL and checksum
  from the source `Package.swift`.

### The 3DS SDK's API key comes from the merchant backend
- The key is in **no artifact, no repository and no build setting of a merchant app**. The merchant backend reads it
  from `GET /v2/entities/{entityId}/app-sdk-configuration` (OAuth2, ORC-2895) and the app passes the answer's opaque
  `data` as **`SecureFieldsConfig.appSDKConfiguration`**. Secure Fields makes no call for it: the endpoint is not
  reachable from a device.
- `data` is base64 of a JSON document that **may grow without notice**. `AppSDKConfiguration` reads
  `three_ds.sdk_api_key` and ignores everything else — never make its decoding strict, never switch on `vendor`.
- The key goes `AppSDKConfiguration` → `ThreeDSCoordinator` → `ThreeDSProvider.initialize(apiKey:production:)` and nowhere else.
  **Never log it, never persist it, never put it or `appSDKConfiguration` in a monitoring payload or an error's
  associated value.**
- Absent, unreadable or keyless `data` → `.threeDS(.configurationMissing)`, with the same fail-fast as a missing
  provider: before tokenizing, and without ever calling the provider. `ThreeDSCoordinator.unavailability` is the one
  place that decides between `.providerUnavailable` and `.configurationMissing`.
- `SecureFieldsConfig` is immutable, so a rotated key reaches a running app only through a new manager built with
  freshly fetched `data`. Fine: the 3DS SDK caches its licence per key on the device.
- **Session flow is out of scope**: the endpoint serves the advanced flow, and nothing delivers the key to Headless
  Checkout yet (doc 12, Follow-ups).
- No provider or no key → `submit(threeDSEnabled: true)`, `submitSavedCard(_:)` and `challenge(_:presenting:)` all
  fail fast. Everything else in the SDK is unaffected.

### Non-production Directory Server roots
- The Netcetera SDK ships the schemes' **production** roots only. A Purse `test` / `sandbox` challenge is signed by
  Netcetera's preview ACS (`CN=3dssprevCA`), so without more `doChallenge` ends at once on `507 … Validation of
  certificate chain with DS Root certificate failed`, before drawing anything.
- `ThreeDSProvider.initialize(apiKey:production:)` carries the answer: `production` is `environment == .production`,
  and when false the adapter adds `NonProductionDirectoryServers.schemes()` — every pre-configured scheme with
  Netcetera's three non-production roots (public certificates, from `NetceteraDemoMerchant.zip` on their Nexus).
  Only the roots are overridden; the encryption keys stay the ones the SDK fetches for the API key.
- **Never add those roots when `production` is true**, and never make the flag default to false: trusting a preview
  CA in production would let anything signed under it pass as an ACS.

### Two hosts
- Tokenization and BIN lookup: the **Vault** host (`VaultEnvironment.apiRoot`, `VaultAPIClient`).
- Versioning and challenge-result: the **Orchestration** host (`VaultEnvironment.orchestrationApiRoot`,
  `https://api.purse-{test,sandbox,live}.com/payment/v2`, `ThreeDSAPIClient`). Same environment enum, two base URLs.
  Production is **`purse-live.com`**, not the `purse-secure.com` of the Vault and monitoring roots: that host serves
  no Orchestration and does not resolve. Keep `orchestrationApiRoot` equal to the web SDK's `ORCHESTRATION_API_ROOTS`.
- `ThreeDSAPIClient` does **not** pin: `SecureFieldsConfig.pinnedPublicKeyHashes` holds the *Vault* server's SPKI
  hashes, and pinning this host with them would reject every request. Same call as `RemoteLogClient`, which already
  talks to that host family unpinned, and for the same reason: no card data on the wire — versioning carries a form
  token or a wallet token id, challenge-result a transaction id. System trust evaluation still applies. Do not
  "fix" this by reusing the vault pins.
- `urlSessionOverride` reaches `ThreeDSAPIClient` only through
  `make(baseURL:apiKey:sessionOverride:isDebugHost:)`, which ignores it on a release-signed host exactly like
  `VaultAPIClient.make` (SDK-12425).
- Both 3DS calls carry `SecureFieldsConfig.apiKey` in the **`X-Api-Key` header** when the host set one, omitted
  otherwise — the Orchestration host sits behind Purse's API gateway (`usp-cf-api-gateway`, `src/proxy.ts`), which
  resolves an API client from that header or from an `api-key` query parameter on every proxied request. The web SDK
  uses the query parameter; this SDK uses the header, by the SDK-12426 decision (a URL is written to proxy and access
  logs). Never move it into the URL.

### The chain
- `submit(threeDSEnabled:)` = tokenize → await/retry the provider's `initialize` → `POST /v2/3ds/versioning` →
  `createTransaction` → `authenticationRequestParameters()`. `isSubmitting` stays latched across the whole chain.
- `ThreeDSProvider.createTransaction` is **completion-based**, like `initialize(apiKey:production:completion:)`: it is `async` on the
  Netcetera SDK from 2.7.0 on. Do not restore a synchronous `throws -> ThreeDSTransaction` — bridging it would mean blocking the
  main queue on a semaphore while the SDK hops to main itself. `warnings`, `close()` and `cleanup()` stay
  synchronous; the adapter fetches the warnings during `initialize` and serialises the rest.
- `device_channel: "APP"` is **always** sent. Absent means `BROWSER` server-side: the answer carries 3DS Method
  fields the app cannot use and the `sdk` block is refused later.
- Transport and decoding failures of the two 3DS calls are `.threeDS(.networkError)`, never `.networkError` /
  `.invalidResponse`: the host must be able to tell a 3DS failure (card already tokenized) from a tokenization one.
- A 3DS failure **after** a successful tokenization reports `.threeDS(_:)` and **keeps the fields** — same invariant
  as any other submit failure (SDK-12549). Only the fully successful chain calls `clearFields()`.
- A **CVV-only** form never versions: it has no card of its own. The saved card it belongs to is
  `submitSavedCard(_:)`'s job, exactly as web splits `submit` and `threeDSSavedCard`.
- `submitSavedCard(_:networkToken:amount:currency:)` has no fields and no tokenization. `amount` (minor units) and
  `currency` are **advanced flow only**; the session flow reads them from the session. `use_network_token` (renamed from `network_token` by ORC-2886) is sent only
  when true — absent, never `false`.
- `ThreeDSSDKBlock` is the wire shape: snake_case, the `sdk` prefix dropped, `message_version` **not** sent, and
  `ephemeral_public_key` a parsed **JWK object** — the 3DS SDK returns it as a JSON string and a string on the wire
  is a 400 on `/sdk/ephemeral_public_key`.
- The 3DS SDK's `initialize` and `createTransaction` are bounded (`sdkTimeout`, 30 s): a stalled SDK fails the chain
  with `.initializationFailed` / `.transactionFailed` instead of holding `submit()`'s latch forever. A transaction
  that arrives after the timeout, or after the coordinator is gone, is closed on the spot. When two chains overlap,
  the last one's transaction replaces the stored one, which is closed.
- Provider and SDK error text reaches the delegate and `NSLog` only through `redacted(_:)`, which strips the 3DS
  SDK's key should the SDK ever repeat it. Never build an error string from a provider error any other way.
- A challenge owns its transaction from `doChallenge` to the terminal callback (`isChallenging`): the coordinator is
  held strongly until then so challenge-result always runs, `closeTransaction()` / `release()` do nothing meanwhile,
  and a second `challenge()` gets `.challengeInProgress` — so does a new chain started meanwhile. `challenge()`
  checks `unavailability` first, like the other two entry points. A watchdog a minute past the 5-minute challenge
  timeout ends a challenge whose terminal callback never comes, through the same path (challenge-result, release).
- `release()` closes the transaction but calls the provider's `cleanup()` only when no chain, challenge or stored
  transaction remains on that provider in **any** coordinator (`busyByProvider`, main queue only): one manager's release must not tear
  the process-wide service down under another manager's chain. A chain holds its coordinator strongly until its
  completion fires: every step is time-bounded, and a host that does not keep the manager still gets an answer.
- `challenge(_:presenting:)` takes `authentication.challenge_data` **verbatim**: base64url, unpadded. A blob whose
  `deviceChannel` is not `"01"`, or whose `threeDSServerTransID` is not the live transaction's, is refused rather
  than guessed at.
- `doChallenge` timeout is **5 minutes** = the `sdkMaxTimeout` Purse announces to the ACS. Keep the two equal.
- The `ChallengeStatusReceiver` callback is **never** the outcome. `POST /v2/3ds/challenge-result` is called on
  **every** terminal callback — completed, cancelled, timed out, protocol and runtime errors alike — and its answer
  is the result. `PENDING` is a normal ending, not a spinner: do not loop on it.
- Release what you opened: the coordinator closes the transaction and calls `cleanup()` after every terminal
  challenge callback, and `SecureFieldsManager.releaseThreeDS()` exists for the **frictionless** path, which the SDK
  never hears about. A leaked transaction is the usual cause of a failure on the next `createTransaction`.
- **The 3DS service is process-wide.** `ThreeDS2Service` is a singleton and the provider is shared by every manager,
  so one manager's `cleanup()` tears it down under the others — the demo's mode switch builds a second manager over
  the first. Two consequences, both load-bearing:
  - `ensureInitialized` has **no `.ready` short-circuit**: every chain asks the provider again (`initialize` is
    required to be a no-op after a success with the same key and environment, and to re-initialize with different
    ones — so a sandbox manager never leaves the non-production roots trusted under a production one). Do not
    "optimise" it back.
  - `deinit` calls `detach()` (close this manager's transaction, and make a chain still running close the one it
    gets instead of storing it), **never** `release()`: closing this manager's own transaction is its
    business, cleaning up the shared service is not.
- `submit(threeDSEnabled: true)` with no provider fails **before** tokenizing: a vault token that can never be paid
  on a Purse 3DS entity is worse than no token.
- `monitoring.recordSubmitSuccess()` fires when the **whole** chain has succeeded, and `recordSubmitFailure` on the
  3DS error path too — the records stay paired with the delegate calls, as everywhere else.
- Retries: versioning retries twice on 5xx/408 only — never on 429, which the gateway rate-limits with a
  `Retry-After` (12 per 60 s). Challenge-result is never retried (6 per 60 s, and it always answers 200).
- Errors branch on HTTP `status` + the RFC 7807 `type`, never on free text. `card-not-versionable` →
  `.cardNotEligible` (on a saved card this is the "not eligible" answer: show the card fields, do not retry);
  `not-configured` → `.notConfigured`.
- `MonitoringCoordinator` maps `.threeDS(_:)` to a **case-name code only** — a `ThreeDSError` can carry provider or
  gateway text in its associated values and none of it belongs in a log payload. No new telemetry was added to the
  3DS path; the silent window between `init` and `deinit` still holds.

## Style / placeholder config
- Applied at init via `applyConfig(_:)` in the manager. The style (not the placeholder text) can be replaced on a mounted form with the public `updateStyle(_:)` (SDK-12749), which runs the same `applyStyle(_:)` path as init: placeholders keep their text and take the new `placeholderColor`, typed content/focus/validity are kept, and no delegate or monitoring event fires. A focused field reloads its input views so a new `keyboardAppearance` reaches the open keyboard.
- `SecureFieldsStyle` sets font (digits always rendered tabular, see Field isolation), textColor, tintColor, keyboardAppearance, placeholderColor.
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
- A configured `pan` without a configured `expDate` is **not** rejected by the SDK. It used to trap in `SecureFieldsFieldsConfig.init` — an unmessaged `precondition`, live in the Release XCFramework, so it killed the merchant's app at init (SDK-12287). The form now builds, mounts, reports valid and submits; the card block goes out with no `expiry_month`/`expiry_year` and the gateway rejects it (`INVALID_FORM`), surfaced as `.apiError`. This is deliberate parity with web and Android — Android's `buildRequestBody` drops the same keys via `toIntOrNull()` and ships the request regardless, and its `emitFormValid` counts configured fields only. Do not add an SDK-side refusal, a named error or a validity gate for this combination without changing the other two SDKs first. An `NSLog` at init is the only thing the SDK says about it.
- `SecureExpDateField.parsedExpiry` is **optional** for that reason: `nil` on an empty or partial field, so `submit()` omits the expiry keys instead of sending `expiry_month: 0`. Do not restore a `(0, 0)` fallback.
- Not supported yet: Oney birthdate in CVV-only (field stays in `.cvv` mode; web/Android skip the network call and return only a birth date — needs its own result shape).

## Delegate events
- `secureFieldsContentChanged()` — fires on every keystroke/change in any field, **after** that field has revalidated: every field calls `setValidity` before `onContentChanged`/`onDigitsChanged`, so `isFieldValid` read from this callback is current. Keep that order in any new field (`contentChangedSeesThisKeystrokesValidity` guards it).
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
- Do not clear the fields when `submit()` sends the request or on its failure path — neither `clearSensitiveData()` nor `clearFields()`. A failed tokenization must be retryable as-is. Only the success path calls `clearFields()`.
- Do not make the `PurseSecureFields` target depend on the Netcetera SDK, or name a Netcetera type in `Sources/PurseSecureFields` — it lives in the optional `PurseSecureFields3DS` product, behind `ThreeDSProvider`.
- Do not embed, default, log or persist the 3DS SDK's API key, and do not add an SDK-side call to fetch it — it comes in through `SecureFieldsConfig.appSDKConfiguration`, from the merchant backend.
- Do not pin the Orchestration host with `pinnedPublicKeyHashes` — those are the Vault server's keys.
- Do not clear the fields when the 3DS chain fails after tokenization, and do not loop on `/3ds/challenge-result`.
- Do not read the payment outcome from the `ChallengeStatusReceiver` callback — it is device-side information.
- Do not put the PAN, CVV or holder name in a `String` (or encode them with `JSONEncoder`) on the tokenization path — use `SensitiveBuffer`.

## Adding a new card brand
1. Add case to `CardBrand` enum with the API raw value string.
2. Add SVG badge to `Sources/PurseSecureFields/Resources/Badges.xcassets/`.
3. Add normalisation entry in `NetworkModels.normaliseScheme` if API scheme string differs from enum raw value.
4. Add its CVV length to `CardBrand.standingCVVLengths` — used by CVV-only forms only. Everywhere else BIN lookup drives lengths; do not add PAN lengths anywhere.

## Demo app
The Demo target is for manual testing only. It is not shipped. The window is built in `SceneDelegate` (UIScene lifecycle) — never move it back onto `AppDelegate`, which iOS 26 traps at launch. `DemoViewController` is split into three files: main state/lifecycle, `+Layout` (UI construction + border logic), `+Delegate` (delegate conformance).
A "Mode" segmented control (`Full form` / `CVV only`, id `mode_control`) sits at the top of the form and rebuilds the screen in the chosen mode — `SecureFieldsConfig` is immutable, so `DemoViewController(isCVVOnly:)` is re-created and swapped into the navigation stack. The `--cvv-only` launch argument starts directly in CVV-only mode (used by the XCUITests). Keep the control out of the navigation bar: the UI tests tap the bar to dismiss the keyboard, and a title-view control would swallow that tap.
The Demo links the `PurseSecureFields3DS` product, so the 3DS chain runs against the real Netcetera SDK through the
same runtime discovery a merchant app uses. It links that product **only** — not `PurseSecureFields` beside it (see
"Linking, load-bearing" above) — and has no Embed Frameworks entry for either: Xcode embeds the Netcetera binary
target itself, and an explicit entry fails with `The file "<product>-product" couldn't be opened`.
The Demo's merchant backend is **Alfred** (`usp-widget/packages/alfred`), reached through `DemoBackend`
(`Demo/Sources/DemoBackend.swift`) at `MERCHANT_BACKEND_URL` — on the simulator `http://localhost:9001` when unset,
so `npm run dev` in Alfred is the whole setup. It plays the advanced flow end to end, as a proof of concept:
- at launch, before the form is built (`SceneDelegate`): `GET /app_sdk_configuration` → `appSDKConfiguration`, and
  `GET /env` → the merchant's public API key, passed as `SecureFieldsConfig.apiKey` because the gateway asks for one
  on `POST /v2/3ds/challenge-result` (on `test` at least; versioning passes without). With no backend answering,
  `NETCETERA_API_KEY` is wrapped into the same document locally;
- also at launch: `GET /order` → `POST /eligible_solutions`, keeping the `creditcard` solutions for the "PSP"
  segmented control (`psp_control`, absent when the backend lists none); the pick goes on the payment's split;
- after `submit(threeDSEnabled: true)`: `POST /create_payment` with the
  `sdk` block top-level; a `challenge_data` in the answer goes straight to `manager.challenge(_:presenting:)`,
  anything else to `releaseThreeDS()`; then `GET /payment/{id}` is shown as the truth.
`ENTITY_ID` (default: the 3DS demo entity `5742b046-…`, whose tenant is the default `TENANT_ID` `61ff8a6a-…`) scopes those calls and must be the entity that owns `TENANT_ID` — a transaction versioned for another
tenant is a 400 at the payment. The Netcetera test ACS shows an OTP screen; `1234` passes it. Under `--uitesting`
there is no backend: nothing is fetched and the flow stops at the tokenization result, as before.
`TENANT_ID`/`MONITORING_API_KEY`/`MERCHANT_BACKEND_URL`/`ENTITY_ID`/`NETCETERA_API_KEY` come from `Demo/Resources/Info.plist`'s `$(VAR)` build-setting substitution, sourced from a gitignored `.env` at the repo root (see `.env.example`) via `source scripts/load-env.sh` — never hardcode real values in `DemoViewController.swift`. That script sets values with both `export` (for `xcodebuild` in the same shell) and `launchctl setenv` (so Xcode.app opened via Finder/Dock, which does not inherit shell env, still resolves them). All fall back gracefully when unset — `TENANT_ID` to a shared sandbox tenant, `MONITORING_API_KEY` to `nil` (monitoring disabled), and with neither a merchant backend answering nor `NETCETERA_API_KEY` the Demo passes no app SDK configuration, so `submit(threeDSEnabled: true)` reports `.threeDS(.configurationMissing)` — so the demo still builds and runs without any `.env` file at all.
