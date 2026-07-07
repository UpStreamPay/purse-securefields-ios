# Vault iOS SDK — Documentation

The Vault iOS SDK lets you collect sensitive card data (PAN, CVV, expiry, holder name) in
your iOS app without exposing raw values to your application code. Card inputs are rendered
as native UIKit views; your app only receives field validity events and a `vault_form_token`
after submission.

---

## I want to integrate the SDK

Follow these three guides in order:

1. **[Getting Started](integration/getting-started.md)** — add the SPM dependency, pick Sandbox vs.
   Production, and initialise `SecureFieldsManager` in your view controller.

2. **[UI Components](integration/ui-components.md)** — place the SDK views in your layout and apply
   styles.

3. **[Collect Data](integration/collect-data.md)** — implement `SecureFieldsDelegate`, call
   `submit()`, and handle the result.

---

## I need the API specification

**[API Reference](integration/api-reference.md)** — every public class, method, property, and
delegate method. Covers `SecureFieldsManager`, `SecureFieldsConfig`, `SecureFieldsDelegate`,
`SecureFieldsStyle`, `TokenizationResult`, `SecureFieldsError`, `CardBrand`, and all supporting
types.

---

## I'm reviewing the security model or PCI posture

- **[Security](security/security.md)** — what your app receives vs. what it can never access, the
  card data lifecycle, required production hardening, and the full list of built-in mitigations
  (privacy overlay, screenshot detection, keyboard learning, accessibility blocking, memory wipe,
  remote monitoring suppressed during card entry).

- **[iOS Payment SDK Comparison](security/pci-comparison.md)** — SAQ A vs SAQ A-EP analysis
  comparing five payment SDKs (Stripe, Adyen, Checkout.com, Primer, VGS) across iOS-specific PCI
  DSS controls, with a detailed implementation comparison.

---

## I want to understand how the SDK works internally

- **[Internals](contributing/internals.md)** — native field layer architecture: `SecureFieldsManager`,
  `SecureBaseField`, BIN lookup, card number formatting, expiry validation, CVV/birthdate mode,
  privacy overlay mechanics, and remote log monitoring (`RemoteLogger`).

---

## I need to understand how the SDK is distributed or released

- **[Distribution](contributing/distribution.md)** — why SPM binary target over CocoaPods, GitHub
  Releases as the hosting mechanism, the signing requirements (PCI SSF), and the competitive
  distribution landscape.

- **[Release](contributing/release.md)** — step-by-step release runbook: Apple Developer certificate
  setup, CI signing, release-please versioning, and GitHub Actions automation.

---

## I'm setting up the project from scratch (SDK contributors)

**[Project Setup](contributing/project-setup.md)** — create the Swift package, add the source
targets, configure the demo app, and publish the first release.

---

## Requirements

| | |
|---|---|
| Minimum iOS | iOS 15 |
| Swift | 5.9+ |
| Xcode | 15+ |
| Distribution | Swift Package Manager (SPM) — binary target |
| Package name | `PurseSecureFields` |
