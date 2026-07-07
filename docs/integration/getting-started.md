# Getting Started

Integrate the Vault iOS SDK into your project in three steps.

> **New to iOS?** See the [glossary](../glossary.md) for quick explanations of SPM, UIKit, and other
> terms used below.

---

## Table of Contents

- [Step 1 — Add the dependency](#step-1--add-the-dependency)
- [Step 2 — Choose an environment](#step-2--choose-an-environment)
- [Step 3 — Initialise the SDK](#step-3--initialise-the-sdk)
- [See also](#see-also)

---

## Step 1 — Add the dependency

> **Swift Package Manager (SPM)** is Apple's built-in dependency manager — no extra tooling needed.
> Dependencies are added directly in Xcode.

1. In Xcode: **File → Add Package Dependencies…**
2. Paste the repository URL in the search bar:
   ```
   https://github.com/UpStreamPay/vault-ios
   ```
3. Select the latest version tag and click **Add Package**.
4. When prompted, add **PurseSecureFields** to your app target.

> Check the [releases page](https://github.com/UpStreamPay/vault-ios/releases) for the
> latest version. Each tagged release distributes a signed XCFramework.

---

## Step 2 — Choose an environment

Pass the correct `baseURL` for your deployment stage. The SDK enforces HTTPS — passing an
`http://` URL will crash at init time.

| Environment | Base URL |
|---|---|
| Sandbox (development) | `https://api.vault.purse-sandbox.com` |
| Production | `https://api.vault.purse-secure.com` |

For a release build, drive this from a build configuration flag:

```swift
let baseURL = Bundle.main.object(forInfoDictionaryKey: "VAULT_BASE_URL") as? String
    ?? "https://api.vault.purse-sandbox.com"
```

---

## Step 3 — Initialise the SDK

Create a `SecureFieldsManager` in your view controller and set yourself as the delegate.

```swift
import UIKit
import PurseSecureFields

class CheckoutViewController: UIViewController {

    lazy var secureFields = SecureFieldsManager(
        config: SecureFieldsConfig(
            tenantId: "YOUR_TENANT_ID",
            baseURL: "https://api.vault.purse-sandbox.com"   // or purse-secure.com in production
        )
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        secureFields.delegate = self
        setupLayout()
    }
}
```

`SecureFieldsManager` is **not** a view controller — it owns the card input views, which you
embed into your own layout. Continue to [UI Components](ui-components.md) to place them.

### Optional: configure brands and styles

Restrict accepted card networks and apply a custom style:

```swift
SecureFieldsConfig(
    tenantId: "YOUR_TENANT_ID",
    baseURL: "https://api.vault.purse-sandbox.com",
    brands: [.visa, .mastercard, .carteBancaire],
    style: SecureFieldsStyle(
        font: .systemFont(ofSize: 16),
        textColor: .label,
        placeholderColor: .placeholderText
    ),
    placeholders: SecureFieldsPlaceholders(
        pan: "1234 5678 9012 3456",
        cvv: "123",
        expDate: "MM/YY",
        holderName: "Cardholder name"
    )
)
```

### Optional: enable certificate pinning

Pin the vault server's public key to prevent MITM attacks even when a rogue CA is installed
(MDM/BYOD, enterprise proxies):

```swift
SecureFieldsConfig(
    tenantId: "YOUR_TENANT_ID",
    baseURL: "https://api.vault.purse-secure.com",
    pinnedPublicKeyHashes: [
        "YOUR_PRIMARY_SPKI_HASH",    // primary certificate
        "YOUR_BACKUP_SPKI_HASH",     // rotation backup — prevents breakage on renewal
    ]
)
```

Extract a hash from a live server:

```bash
openssl s_client -connect api.vault.purse-secure.com:443 2>/dev/null </dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | base64
```

### Optional: enable remote log monitoring

Pass an `apiKey` to enable remote log monitoring — the SDK forwards `info`/`warn`/`error` health
logs to Datadog so you and Purse can monitor SDK health in production. It's on by default whenever
`apiKey` is provided:

```swift
SecureFieldsConfig(
    tenantId: "YOUR_TENANT_ID",
    baseURL: "https://api.vault.purse-secure.com",
    apiKey: "YOUR_MONITORING_API_KEY",
    monitoringEnvironment: .production   // or .sandbox
)
```

Omit `apiKey`, or pass `monitoringEnabled: false`, to disable it entirely. No card data is ever
included, and it's fully suppressed for `SecureFieldsManager`'s entire lifetime — see
[Remote log monitoring](api-reference.md#remote-log-monitoring) in the API Reference for details.

---

## See also

- [UI Components](ui-components.md) — embed card input views in your layout
- [Collect Data](collect-data.md) — implement the delegate, submit the form, handle the result
- [API Reference](api-reference.md)
- [Glossary](../glossary.md)
