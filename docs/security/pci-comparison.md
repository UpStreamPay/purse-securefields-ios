# iOS Payment SDK — PCI DSS & Data Routing Analysis

> **Date:** June 2026

---

## The core question

When a user types their card number into a payment form on a mobile app, where does that number
actually go — and who can see it?

The answer determines the merchant's PCI DSS compliance obligations. The simpler the answer,
the less burden the merchant carries.

---

## What PCI DSS SAQ levels mean in practice

| SAQ | What it means | Merchant burden |
|---|---|---|
| **SAQ A** | Card data is entered directly into a form the merchant never controls or accesses | Minimal — just ensure HTTPS and don't log anything |
| **SAQ A-EP** | Card data passes through or is briefly held by the merchant app, even if encrypted before transmission | Moderate — app binary integrity, no debug logging of inputs, regular security assessments |
| **SAQ D** | Card data is processed, stored, or transmitted by the merchant | Full PCI audit — very costly |

The goal for any payment SDK is to keep merchants at SAQ A. The tradeoff is that SAQ A
typically means giving up UI control — the payment form is owned by the SDK provider, not the
merchant.

---

## How each SDK routes card data

### Stripe iOS (`stripe-ios`)

**SAQ level: SAQ A (via PaymentSheet) or SAQ A-EP (via CardElement / PaymentElement)**

Stripe offers two distinct integration paths on iOS:

**PaymentSheet (SAQ A):** Stripe presents a full-screen `UIViewController` managed entirely by
Stripe. The merchant app calls `paymentSheet.present(from:)` and receives only a
`PaymentSheetResult` — the merchant never interacts with the card input views. Card data stays
inside Stripe's VC, encrypted, and sent directly to `api.stripe.com`.

```
User types PAN
  → Stripe-owned UIViewController (merchant code has no access)
  → Encrypted in-process by Stripe SDK
  → Sent directly to api.stripe.com
  → Merchant app receives: PaymentSheetResult (.completed / .failed / .canceled)
```

**CardElement / PaymentElement (SAQ A-EP):** When the merchant uses Stripe's lower-level API
(`STPCardFormView` or the `PaymentElement` in embedded mode), the card form is rendered inline
in the merchant app. The raw card data briefly exists within the merchant app's process.

---

### Adyen iOS (`adyen-ios`)

**SAQ level: SAQ A-EP**

Adyen offers a Drop-in UI and embeddable Components. In both modes, card data is entered into
UIKit views running inside the merchant app's process.

Adyen's Client-Side Encryption (CSE) is explicit: raw card data is placed into an `EncryptedCard`
struct using a session RSA public key fetched from Adyen's servers. The plaintext PAN exists as a
named Swift struct in memory before the encryption call.

```
User types PAN
  → UITextField inside Adyen Component (in merchant app process)
  → SDK reads field values → builds an EncryptedCard struct
  → Encrypts with RSA session key
  → Encrypted payload sent to Adyen's API
  → Merchant app receives: a payment method token
```

Adyen ships a standalone CSE module that merchants can call directly with their own UI —
the plaintext card data is a first-class type (`EncryptedCard.encryptedCardNumber`,
`EncryptedCard.encryptedExpiryMonth`, etc.) before encryption. The encryption happens
immediately, but the plaintext window exists as a Swift value type on the stack.

---

### Checkout.com frames-ios (`frames-ios`)

**SAQ level: SAQ A-EP**

Checkout.com provides `CardNumberView`, `ExpiryDateView`, and `CVVInputView` — `UIView`
subclasses that wrap `UITextField`. They are embedded directly in the merchant app's layout.
The merchant calls `CheckoutAPIClient.createToken(paymentData:)` with a `PaymentData` struct
containing the card details, encrypting them client-side with a public key before sending to
Checkout's API.

```
User types PAN
  → CardNumberView (UITextField subclass) in merchant app
  → Merchant calls createToken() with PaymentData(cardNumber:expiryDate:cvv:)
  → SDK encrypts and POSTs to api.checkout.com
  → Merchant app receives: a card token
```

The plaintext PAN is placed into a `PaymentData` struct that the merchant constructs directly
from the field values — the SDK provides no internal isolation between the field and the
tokenization call.

---

### Primer iOS (`primer-sdk-ios`)

**SAQ level: SAQ A-EP**

Primer follows the same pattern as Adyen and Checkout.com: native UIKit inputs inside the
merchant app's process, client-side encryption before leaving the device. The Drop-in UI
presents a `UIViewController` that Primer manages, but it runs inside the merchant app's process.

```
User types PAN
  → Native inputs inside Primer Drop-in VC or Headless Components (in merchant process)
  → SDK reads values, encrypts, sends to Primer's API
  → Merchant app receives: a PrimerPaymentMethodTokenData
```

---

### VGS Collect iOS (`vgs-collect-ios`)

**SAQ level: SAQ A-EP (VGS markets it as SAQ A — see note below)**

VGS uses a proxy model: `VGSTextField` (a `UIView` wrapping `UITextField`) captures card
input, and `VGSCollect.submit()` routes the data through a VGS vault proxy URL rather than
directly to the merchant's backend. The VGS proxy tokenizes the card fields server-side before
forwarding the request.

```
User types PAN
  → VGSTextField inside merchant app (in merchant process)
  → submit() — SDK sends data to VGS vault proxy
  → VGS proxy tokenizes card fields
  → Tokenized request forwarded to merchant's real backend
  → Merchant backend receives: VGS token (never the raw PAN)
```

**SAQ note:** VGS claims SAQ A eligibility on iOS, drawing an analogy to cross-origin iframes
in web browsers. This analogy does not translate. On the web, a cross-origin iframe is enforced
by the browser at the OS level — the parent page's JavaScript literally cannot access iframe
content. On iOS, `VGSTextField` is a `UIView` subclass running inside the merchant app's
process. There is no OS-level isolation. The merchant app's code can read the field value
directly. The security guarantee is behavioral (VGS intercepts the network call) rather than
architectural (the OS enforcing process isolation). By strict PCI DSS interpretation, card
data that passes through the merchant app's process places the app in scope — SAQ A-EP
territory.

---

### Purse Vault iOS (this SDK)

**SAQ level: SAQ A-EP**

The Vault iOS SDK uses native UITextField-based views with an explicit isolation layer. Card
inputs are `SecureBaseField` subclasses that override `text`, `attributedText`, and
`accessibilityValue` getters to return `nil`. Raw card values can only be read through
`storedText` — an internal-only property not accessible from outside the module.

```
User types PAN
  → SecurePANField (UITextField subclass, text getter returns nil)
  → SDK reads rawValue via storedText (internal) to build tokenization request
  → SDK POSTs directly to api.vault.purse-test.com (or purse-secure.com)
  → Merchant app receives: vault_form_token only
```

The PAN briefly exists within the SDK module's memory during active input and the brief
tokenization window. It is never passed to merchant code — delegate callbacks carry only
validity flags and character counts. The SDK calls `clearSensitiveData()` on all fields
immediately after the tokenization request body is built.

---

## Side-by-side comparison

| | Stripe (PaymentSheet) | Adyen | Checkout.com | Primer | VGS Collect | Purse Vault |
|---|---|---|---|---|---|---|
| Where is PAN entered | Stripe-owned UIViewController | UITextField in merchant app | UITextField subclass in merchant app | UITextField in merchant app | VGSTextField in merchant app | SecurePANField inside Vault SDK (in merchant app) |
| Does PAN exist in merchant app memory | No (Stripe VC is isolated) | Yes — named `EncryptedCard` struct before encryption | Yes — `PaymentData` struct built by merchant code | Yes (briefly) | Yes (in VGSTextField buffer) | Yes — briefly, inside SDK module only; never accessible to merchant code |
| Who makes the tokenization API call | Stripe SDK (directly) | Adyen SDK (directly) | Checkout SDK (directly) | Primer SDK (directly) | VGS cloud proxy | Vault SDK (directly to Purse API) |
| What merchant backend receives | Payment confirmation | Token | Token | Token | VGS token (PAN never reaches merchant backend) | `vault_form_token` |
| PCI SAQ level | SAQ A | SAQ A-EP | SAQ A-EP | SAQ A-EP | SAQ A-EP (VGS claims SAQ A — disputed) | SAQ A-EP |
| Native look and feel | Full (native UIKit) | Full | Full | Full | Full | Full (UIKit) |
| Merchant UI customisation | Limited (Stripe controls the sheet) | High | High | High | High | High (UIView, any Auto Layout) |

---

## The tradeoff

Stripe's PaymentSheet achieves SAQ A by placing the payment UI entirely under Stripe's control
inside a presented `UIViewController`. The merchant app cannot style it freely, pre-fill
sensitive fields, or access card data. This is the maximum compliance simplification — at the
cost of UI flexibility.

Adyen, Checkout.com, Primer, and the Vault SDK all operate at SAQ A-EP: native inputs inside
the merchant app's process, with the SDK responsible for tokenization before any sensitive data
reaches the merchant's backend. The plaintext PAN exists in memory briefly. iOS Swift structs
are value types allocated on the stack, which are deterministically released when they go out
of scope. Unlike the JVM (where `String` is immutable and GC-managed), Swift allows zeroing
stack memory through `withUnsafeMutableBytes` — the SDK uses this in `clearSensitiveData()`.

The key distinction in the Vault SDK compared to Adyen and Checkout.com is that raw card values
are never passed through a public API. Adyen's `EncryptedCard(cardNumber:...)` and Checkout.com's
`PaymentData(cardNumber:...)` are structs built with the plaintext value as a parameter —
merchant code necessarily touches the value to construct them. Vault's `SecureBaseField` makes
the `.text` getter return `nil` architecturally, not just by convention.

---

## iOS-specific implementation details

The sections below compare how each SDK handles iOS-specific security controls.

---

### UITextField security hardening

How each SDK prevents keyboard apps and system services from learning card data:

| Control | Stripe | Adyen | Checkout.com | VGS | Purse Vault |
|---|---|---|---|---|---|
| `autocorrectionType = .no` | Yes | Yes | Yes | Partial | Yes — all fields |
| `spellCheckingType = .no` | Yes | Yes | Varies | Partial | Yes — all fields |
| `textContentType = .none` | Yes | Yes | Yes | Partial | Yes — all fields |
| `isSecureTextEntry` on CVV | Yes | Yes | Yes | No | Yes — CVV field |
| Keyboard learning prevention | Yes | Yes | Partial | No | Yes — `.no` on all relevant types |

---

### Privacy overlay and screen recording

| Behaviour | Stripe | Adyen | Checkout.com | VGS | Purse Vault |
|---|---|---|---|---|---|
| Blur on app background | Yes (UIViewController dismiss) | Partial | No | No | Yes — `UIBlurEffect` overlay on all fields |
| Screen recording detection | No | No | No | No | Yes — `UIScreen.capturedDidChangeNotification` |
| Screenshot notification | No | No | No | No | Yes — fires `secureFieldsScreenshotDetected()` on delegate |

---

### Certificate pinning

| Approach | Stripe | Adyen | Checkout.com | VGS | Purse Vault |
|---|---|---|---|---|---|
| Built-in | Yes (Stripe's own servers) | No | No | No | Optional — SPKI pinning via `pinnedPublicKeyHashes` |
| Mechanism | `URLSessionDelegate` + cert hash | — | — | — | `URLSessionDelegate` + SPKI SHA-256 |
| Key rotation support | Managed by Stripe | — | — | — | Multiple hashes — primary + backup |

---

### TLS enforcement

All five SDKs benefit from iOS App Transport Security (ATS), which enforces HTTPS and TLS 1.2
minimum for all outbound connections by default. No SDK-level TLS version configuration is
needed — unlike Android, where the minimum TLS version must be set explicitly.

| | Stripe | Adyen | Checkout.com | VGS | Purse Vault |
|---|---|---|---|---|---|
| TLS enforcement | ATS (platform) | ATS (platform) | ATS (platform) | ATS (platform) | ATS (platform) + HTTPS enforced at `SecureFieldsConfig` init |
| ATS exceptions | None for payment calls | None | None | None | None — `baseURL` must start with `https://` or init crashes |

---

### Distribution format

| | Stripe | Adyen | Checkout.com | Primer | VGS | Purse Vault |
|---|---|---|---|---|---|---|
| SPM | Source | Source | Source | Source | Binary target | Binary target |
| CocoaPods | Podspec | Podspec | Podspec | Podspec | Podspec | Not supported |
| XCFramework signed | Yes (Apple) | Yes (Apple) | Yes (Apple) | Yes (Apple) | Yes (Apple) | Yes (Apple Distribution) |

Purse Vault and VGS both distribute as SPM binary targets rather than source packages. For
trade-off analysis see [Distribution](../contributing/distribution.md).

---

*June 2026*
