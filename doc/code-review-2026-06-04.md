# PurseSecureFields — Code Quality & Security Audit

**Date:** 2026-06-04
**Scope:** Full repository audit of `Sources/PurseSecureFields/` and `Tests/`
**Reviewer:** Automated review (Copilot CLI, code-review agent)

> No code-level PCI invariant from `AGENTS.md` is currently broken (field
> isolation, `super.text` discipline, CVV paste block, no body logging are all
> intact). The most important real bugs are **H1**, **H2**, **H3**, **H4**, and
> **H6**. Fixing those would close the largest correctness and PCI
> defense-in-depth gaps without restructuring the SDK.

---

## High

### H1. CVV `expectedLength` uses MAX of API `cvv_lengths`, dropping valid shorter CVVs
**Files:** `Sources/PurseSecureFields/Networking/NetworkModels.swift:68`,
`SecureFieldsManager.swift:173`, `SecureCVVField.swift:15-19, 71-78`

**Problem:** `cvvField.expectedLength` is a single `Int`. The manager sets it to
`binResult.maxCvvLength` (the max of the API's `cvv_lengths`). For any brand
where the API returns multiple valid CVV lengths (e.g. `[3, 4]`), a perfectly
valid 3-digit CVV will be `setValidity(false)` and `submit()` will block. This
is inconsistent with the deliberate `validLengths: [Int]` design used for PAN
(whose AGENTS.md note explicitly calls out multi-length support). It also
silently truncates user input to the max — a user paste of "123" then typing
won't fix the issue, but typing into a 3-digit-only context still produces a
wrong validity gate.

**Fix:** Mirror the PAN design — store `validCvvLengths: [Int]`, validate
`validCvvLengths.contains(count)`, truncate by `validCvvLengths.max() ?? 4`.

### H2. Stale BIN-lookup responses can clobber current state (race)
**File:** `Sources/PurseSecureFields/SecureFieldsManager.swift:143-183`

**Problem:** `binLookupWorkItem?.cancel()` only cancels a not-yet-started
`DispatchWorkItem`. Once the work item begins, the `URLSession.dataTask` is
in flight and is never cancelled. Sequence:

1. User types 6 digits, lookup #1 fires.
2. User keeps typing → after debounce, lookup #2 fires.
3. User backspaces below 6 digits → the `< 6` branch resets `detectedBrands`,
   `validLengths`, `selectedBrand`.
4. Lookup #1 (or #2) completes and re-applies brands/lengths/CVV mode based on
   the now-stale prefix. The cache check `prefix == lastBinPrefix` is set on
   the first arriving response, so it doesn't protect against this ordering.

This produces wrong brand chips, wrong PAN validity, and (worst) wrong CVV
input mode (birthdate vs CVV) for the digits currently in the field.

**Fix:** Track an in-flight token (e.g. the prefix or a monotonically
increasing request id) and ignore responses whose token no longer matches the
current PAN prefix. Or cancel the `URLSessionTask` itself.

### H3. CVV input mode can desync from selected brand
**File:** `Sources/PurseSecureFields/SecureFieldsManager.swift:171-176`

**Problem:** Order of operations in the BIN success closure:

```swift
let activeBrand = self.brandSelectorView.selectedBrand ?? allowed.first
...
self.applySelectedBrand(activeBrand)              // sets CVV inputMode
self.brandSelectorView.update(brands: allowed)    // resets selectedBrand to allowed.first
```

If the user had previously selected brand X (e.g. Oney) and the new `allowed`
no longer contains X, `activeBrand` is still X. `applySelectedBrand(.oney)`
flips the CVV field to the date-picker birthdate mode; then
`brandSelectorView.update` replaces `selectedBrand` with `allowed.first` (e.g.
Visa). End state: chip shows Visa, but CVV field is a date picker — and
`submit()` will send `birth_date` with no `cvv`, payload built around a
non-Oney brand.

**Fix:** Compute `activeBrand` from `allowed` first
(`allowed.contains(prev) ? prev : allowed.first`), update the brand selector,
then call `applySelectedBrand`.

### H4. `URLSession.shared` used for PCI traffic
**File:** `Sources/PurseSecureFields/Networking/VaultAPIClient.swift:11-14`

**Problem:** `URLSession.shared` is a process-wide session that uses
`URLCache.shared`, `HTTPCookieStorage.shared`, and the shared credential
storage. Side effects:

- Any cookies set by `Set-Cookie` from the vault API become visible to the host
  app and any other code sharing the session.
- Any `URLProtocol` subclasses registered by the host app (analytics SDKs,
  debug proxies, network mocks) can intercept the PAN/CVV requests in
  plaintext at the framework boundary.
- Shared session disables `URLSessionConfiguration` controls (TLS minimum
  version, waitsForConnectivity, allowsExpensiveNetworkAccess).

For a PCI SDK this is the wrong default.

**Fix:** Default to a private `URLSession(configuration: .ephemeral)` owned by
the client; set `urlCache = nil`, `httpCookieStorage = nil`,
`httpShouldSetCookies = false`,
`requestCachePolicy = .reloadIgnoringLocalCacheData`,
`tlsMinimumSupportedProtocolVersion = .TLSv12`.

### H5. Tokenize retried up to 3× on transport error — possible duplicate tokenization
**File:** `Sources/PurseSecureFields/Networking/VaultAPIClient.swift:86-119`

**Problem:** `perform(...)` retries on *any* `error` (transport timeout, lost
connection, etc.) up to 3 times. An iOS request that timed out client-side may
have been received and processed by the server. The SDK reuses the same
`X-Request-ID` across retries (good), but that only helps if the vault API
actually dedupes on it — and AGENTS.md only says "X-Request-ID (UUID) on
tokenization" without stating server semantics. If the server doesn't dedupe,
the user gets 1–4 form tokens for one card.

**Fix:** Either (a) restrict retries to `>= 500` only (don't retry transport
errors), or (b) document/contract the X-Request-ID dedup window on the server
and add a code comment pointing to it.

### H6. `submit()` has no in-flight guard
**File:** `Sources/PurseSecureFields/SecureFieldsManager.swift:196-237`

**Problem:** Nothing prevents two concurrent submits. A double-tap on the
host's pay button (or a programmatic re-call before the delegate callback)
issues two tokenization POSTs with different `X-Request-ID`s — guaranteed
duplicates. The Demo disables the button optimistically, but the SDK itself
must not depend on host UI discipline for a card-data side effect.

**Fix:** Track `isSubmitting` and short-circuit / fail-fast on re-entry until
the callback fires.

---

## Medium

### M1. BIN-lookup failures are silently swallowed
**Files:** `Sources/PurseSecureFields/Networking/VaultAPIClient.swift:38-59`,
`SecureFieldsManager.swift:165-178`

**Problem:** Two layers swallow errors:

1. On JSON decode failure, the client returns
   `.success(BinLookupResult(brands: [], panLengths: [16], cvvLengths: [3]))`
   — indistinguishable from a real "no brands detected" result.
2. In the manager, `guard case .success(let binResult) = result else { return }`
   discards genuine network failures with no delegate notification.

Consequence: a transient network failure leaves the user staring at a
never-validating PAN with no UI feedback path; the host app has no signal to
retry or surface an error.

**Fix:** Surface BIN lookup errors to a new delegate hook (or fold into the
existing error path) and stop masking decode failures as success.

### M2. No background-snapshot / screen-recording protection
**File:** Not present anywhere in `Sources/`

**Problem:** When the app is backgrounded, iOS takes a snapshot of the current
screen (visible in the app switcher and persisted to disk). With no opt-in
obfuscation in the fields, the typed PAN, expiry, and holder name remain
visible in that snapshot. CVV is mitigated by `isSecureTextEntry`, but PAN is
not. Similarly no detection / blurring on
`UIScreen.capturedDidChangeNotification` for active screen recording.

**Fix:** Provide an opt-in (or default-on) hook in `SecureFieldsManager` that
observes `UIApplication.willResignActiveNotification` and overlays/clears the
field rendering, plus a screen-recording guard.

### M3. `precondition` crashes the host app on misconfiguration
**File:** `Sources/PurseSecureFields/Models/SecureFieldsConfig.swift:60-61`

**Problem:** `precondition(baseURL.hasPrefix("https://"), ...)` and the
tenantId check abort the process on a bad config — even in release. A typo or
staging-vs-prod mistake crashes the merchant's app at startup rather than
producing a recoverable error.

**Fix:** Throw from a failable/throwing initializer, or fail at first network
call with `SecureFieldsError.invalidResponse` (or a new `.invalidConfig`).
HTTPS enforcement should be belt-and-suspenders, also rejected at the URL
build site.

### M4. `BinLookupResult.maxPanLength` fallback to 16 hides Oney
**Files:** `Sources/PurseSecureFields/Networking/NetworkModels.swift:67-68`,
`SecureFieldsManager.swift:172`

**Problem:** The manager does `panLengths.isEmpty ? [16] : panLengths` and
similar fallbacks default to `[16]` / `3`. If the API returns an Oney BIN but
with a missing/empty `pan_lengths`, the field is gated at 16 digits — making
a perfectly typed 19-digit Oney PAN invalid. AGENTS.md explicitly forbids
hardcoded per-brand lengths, but the fallback re-introduces a Visa-shaped
assumption that silently misclassifies Oney.

**Fix:** When `panLengths` is empty, derive the fallback from the detected
brand (`[19]` for Oney) or refuse to validate until a real length list is
known.

### M5. `applyConfig` ignores `expDate` placeholder set in `SecureExpDateField.setup()`
**Files:** `Sources/PurseSecureFields/Views/SecureExpDateField.swift:19`,
`SecureFieldsManager.swift:107`

**Problem:** `setup()` sets `placeholder = "MM/YY"` (non-attributed). Then
`applyConfig` calls `applyPlaceholder(ph.expDate, ...)` which sets
`attributedPlaceholder`. The two coexist; on some iOS versions setting
`attributedPlaceholder` clears `placeholder` and vice versa — but if a host
clears the attributed placeholder later or sets `placeholder` again, the
styled colour silently reverts. Minor footgun; not a correctness bug today.

**Fix:** Drop the hardcoded `placeholder` in `setup()`; treat config as the
sole source per AGENTS.md.

### M6. `localizedDescription` of network error logged in DEBUG can include URL with path
**File:** `Sources/PurseSecureFields/Networking/VaultAPIClient.swift:41`

**Problem:** `error.localizedDescription` for `URLError` often includes the
failing URL (which contains the tenant id path) but never card data, so this
is bounded. However the same file at line 132 logs the full decode error
which, for Swift's `DecodingError.dataCorrupted`, includes a snippet of the
failing JSON. If the failing body ever echoes the input (some vault APIs do on
4xx validation errors), that snippet could contain PAN/CVV. AGENTS.md says
"No card data in logs."

**Fix:** Replace the decode-error log with the error type name only
(`String(describing: type(of: error))`), or remove.

---

## Low

### L1. `lastBinPrefix` cache: bounded but no expiry / no negative-result invalidation
**File:** `SecureFieldsManager.swift:160-161`

The cache only keys by 8-digit prefix. After a successful response, the
in-flight check `if prefix == lastBinPrefix && !detectedBrands.isEmpty { return }`
short-circuits but does not re-trigger if the prior response had
`detectedBrands.isEmpty`. Marginal: empty results will refetch on every
keystroke past 6 digits.

### L2. `clearFields()` does not reset `brandSelectorView.selectedBrand` explicitly
**File:** `SecureFieldsManager.swift:55-68`

Currently it relies on `update(brands: [])` → `rebuildChips` →
`selectedBrand = brands.first` (nil). Correct today, but coupling clearing
semantics to a UI rebuild is fragile.

### L3. `SecureExpDateField` accepts and displays month > 12
**File:** `SecureExpDateField.swift:22-31`

The formatter never rejects bad months — "9/" auto-inserts "/" if user types
a second digit; "13/25" is displayed and only fails validity. Won't cause
incorrect tokenization (gated by `isValid`), but allows visibly-invalid state.

### L4. `BinLookupResponse.toBinLookupResult` picks `main` brand's lengths but returns all `brands`
**File:** `NetworkModels.swift:88-97`

If the API returns multiple brands where the non-main brand has different
`pan_lengths`, the SDK validates PAN against the main brand's lengths
regardless of which chip the user selects via `SecureBrandSelectorView`.
Switching brand chips doesn't re-apply per-brand lengths.

### L5. Test coverage gaps
- **No tests for `SecureFieldsManager`** (BIN-lookup race, in-flight
  cancellation, brand desync, submit payload shape for Oney vs non-Oney) —
  `SecureFieldsTests.swift` is 14 lines.
- **No tests for `VaultAPIClient`** (retry semantics, header presence, error
  mapping).
- **No tests for `NetworkModels.normaliseScheme`** beyond what compiles.
- **No tests for `CardFormatter` Amex 4-6-5 grouping with partial input** (a
  glance at `CardFormatterTests.swift` would confirm, but the file is 61 lines
  for what should be ~20 cases).

### L6. `panField.textContentType = .creditCardNumber`
**File:** `SecurePANField.swift:19`

Intentional for QuickType / autofill UX. Worth a doc note that the host
inherits responsibility for the iOS autofill ecosystem (cards saved to iCloud
Keychain, suggested via Wallet) being involved in the PAN flow. Not a bug.
