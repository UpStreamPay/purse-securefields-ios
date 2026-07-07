# UI Components

Embed the SDK's card input views into your layout. Each view renders a native iOS text field
managed by the SDK — raw card values are never accessible to your application code.

> Complete the [Getting Started](getting-started.md) guide before adding UI components.

---

## Table of Contents

- [Available views](#available-views)
- [Embed views in your layout](#embed-views-in-your-layout)
  - [UIKit (Auto Layout)](#uikit-auto-layout)
  - [SwiftUI](#swiftui)
- [PAN container and brand selector](#pan-container-and-brand-selector)
- [Applying styles](#applying-styles)
  - [Style properties](#style-properties)
- [Updating placeholders after init](#updating-placeholders-after-init)
- [Privacy overlay](#privacy-overlay)
- [See also](#see-also)

---

## Available views

| Property | Type | Description |
|---|---|---|
| `panContainer` | `SecurePANContainer` | PAN input + optional brand selector |
| `cvvView` | `UIView` | CVV / date-of-birth input |
| `expDateView` | `UIView` | Expiry date (MM/YY) |
| `holderNameView` | `UIView` | Cardholder name (free text) |

All four are `UIView` instances — place them anywhere in your view hierarchy using Auto Layout or
frame-based layout. The underlying `UITextField` subclasses (`SecureCVVField`, etc.) are
`internal` to the SDK, so your code cannot name or cast to those concrete types. A cast to the
public `UITextField` superclass will still succeed, but that is not a way to read card data: the
`text`/`attributedText` getters are overridden to always return `nil` to external callers (see
[Security](../security/security.md#what-your-application-cannot-do)), so no raw value is ever
exposed regardless of how the view is cast.

---

## Embed views in your layout

### UIKit (Auto Layout)

Add each view to your view hierarchy and constrain its height. The SDK does not impose a minimum
height but fields typically look correct at **44–56 pt**.

```swift
import UIKit
import PurseSecureFields

class CheckoutViewController: UIViewController {

    lazy var secureFields = SecureFieldsManager(
        config: SecureFieldsConfig(
            tenantId: "YOUR_TENANT_ID",
            environment: .sandbox
        )
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        secureFields.delegate = self
        setupLayout()
    }

    private func setupLayout() {
        let pan       = secureFields.panContainer
        let expDate   = secureFields.expDateView
        let cvv       = secureFields.cvvView
        let holder    = secureFields.holderNameView

        [pan, expDate, cvv, holder].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            pan.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            pan.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pan.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            pan.heightAnchor.constraint(equalToConstant: 48),

            expDate.topAnchor.constraint(equalTo: pan.bottomAnchor, constant: 12),
            expDate.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            expDate.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.45),
            expDate.heightAnchor.constraint(equalToConstant: 48),

            cvv.topAnchor.constraint(equalTo: pan.bottomAnchor, constant: 12),
            cvv.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            cvv.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.45),
            cvv.heightAnchor.constraint(equalToConstant: 48),

            holder.topAnchor.constraint(equalTo: expDate.bottomAnchor, constant: 12),
            holder.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            holder.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            holder.heightAnchor.constraint(equalToConstant: 48),
        ])
    }
}
```

### SwiftUI

Wrap each view using `UIViewRepresentable`:

```swift
import SwiftUI
import PurseSecureFields

struct SecureFieldView: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct CheckoutView: View {
    @StateObject private var vm = CheckoutViewModel()

    var body: some View {
        VStack(spacing: 12) {
            SecureFieldView(view: vm.secureFields.panContainer)
                .frame(height: 48)
            HStack(spacing: 12) {
                SecureFieldView(view: vm.secureFields.expDateView)
                    .frame(height: 48)
                SecureFieldView(view: vm.secureFields.cvvView)
                    .frame(height: 48)
            }
            SecureFieldView(view: vm.secureFields.holderNameView)
                .frame(height: 48)
        }
        .padding()
    }
}
```

---

## PAN container and brand selector

`panContainer` is a `SecurePANContainer` — it wraps the PAN field and optionally shows a brand
selector for co-branded cards (e.g. Visa + CB).

The brand selector appears automatically when two or more brands are detected from the BIN lookup.
The user taps to choose the network. When the selector is active, `secureFieldsBrandSelected(_:)`
fires on your delegate.

Pass `brands` in `SecureFieldsConfig` to restrict which card networks are accepted:

```swift
SecureFieldsConfig(
    tenantId: "...",
    environment: .sandbox,
    brands: [.visa, .mastercard, .carteBancaire, .oney]
)
```

If a BIN lookup returns brands not in your allowed list, they are filtered out. If no allowed
brand is detected, the brand selector is not shown and `secureFieldsBrandsDetected([])` fires.

---

## Applying styles

Pass a `SecureFieldsStyle` in `SecureFieldsConfig` at initialisation time. Styles are applied to
all fields at once.

```swift
SecureFieldsConfig(
    tenantId: "...",
    environment: .sandbox,
    style: SecureFieldsStyle(
        font: UIFont.systemFont(ofSize: 16, weight: .regular),
        textColor: UIColor.label,
        placeholderColor: UIColor.placeholderText,
        tintColor: UIColor.systemBlue,
        keyboardAppearance: .default
    )
)
```

### Style properties

| Property | Type | Default | Description |
|---|---|---|---|
| `font` | `UIFont` | `.systemFont(ofSize: 16)` | Text font for all fields |
| `textColor` | `UIColor` | `.label` | Input text color |
| `placeholderColor` | `UIColor` | `.placeholderText` | Placeholder text color |
| `tintColor` | `UIColor` | `.systemBlue` | Cursor and selection color |
| `keyboardAppearance` | `UIKeyboardAppearance` | `.default` | Light or dark keyboard |

---

## Updating placeholders after init

Placeholders are set at init time through `SecureFieldsPlaceholders`:

```swift
SecureFieldsConfig(
    tenantId: "...",
    environment: .sandbox,
    placeholders: SecureFieldsPlaceholders(
        pan: "1234 5678 9012 3456",
        cvv: "CVV",
        expDate: "MM/YY",
        holderName: "Cardholder name"
    )
)
```

---

## Privacy overlay

The SDK automatically places a `UIBlurEffect` overlay over all card fields when the app
enters the background or screen recording starts. This prevents card numbers from appearing
in app-switcher thumbnails or screen recordings.

The default behaviour is on. Disable it if your app handles backgrounding separately:

```swift
secureFields.obscuresOnBackground = false
```

See [Security](../security/security.md#built-in-mitigations) for details on all privacy protections.

---

## See also

- [Collect Data](collect-data.md) — implement the delegate, submit, and handle the result
- [Getting Started](getting-started.md)
- [API Reference](api-reference.md)
