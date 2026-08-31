# Collect Data

Implement `SecureFieldsDelegate`, submit the form, and handle the tokenization result.

> Complete [Getting Started](getting-started.md) and [UI Components](ui-components.md) first.

---

## Table of Contents

- [Implement the delegate](#implement-the-delegate)
  - [Track form validity](#track-form-validity)
  - [Track individual field state](#track-individual-field-state)
  - [Handle brand detection](#handle-brand-detection)
  - [Handle errors](#handle-errors)
  - [Handle screenshot detection](#handle-screenshot-detection)
- [Submit the form](#submit-the-form)
  - [Submit with saveToken](#submit-with-savetoken)
- [Handle the tokenization result](#handle-the-tokenization-result)
- [Clear fields](#clear-fields)
- [Error reference](#error-reference)
- [See also](#see-also)

---

## Implement the delegate

Adopt `SecureFieldsDelegate` in your view controller. All methods except `secureFieldsDidTokenize`
and `secureFieldsDidFail` have default no-op implementations — override only what you need.

```swift
extension CheckoutViewController: SecureFieldsDelegate {

    func secureFieldsFormValidityChanged(_ isValid: Bool) {
        payButton.isEnabled = isValid
    }

    func secureFieldsDidTokenize(_ result: TokenizationResult) {
        // success path — see Handle the tokenization result below
    }

    func secureFieldsDidFail(_ error: SecureFieldsError) {
        // error path — see Error reference below
    }
}
```

### Track form validity

`secureFieldsFormValidityChanged(_:)` fires whenever the aggregate form validity changes. Use it
to enable or disable your submit button.

```swift
func secureFieldsFormValidityChanged(_ isValid: Bool) {
    payButton.isEnabled = isValid

    // Query individual field state without reading values:
    let panValid   = secureFields.isFieldValid(.pan)
    let cvvValid   = secureFields.isFieldValid(.cvv)
    let expValid   = secureFields.isFieldValid(.expDate)

    // Character count for PAN (useful for progress indicators):
    let digitCount = secureFields.panDigitCount
}
```

> `isFieldValid`, `isFieldFocused`, `hasFieldContent`, and `panDigitCount` never expose raw card
> data — only derived metadata.

### Track individual field state

`secureFieldsFocusChanged(field:isFocused:)` fires on focus and blur. Use it to update border
styles:

```swift
func secureFieldsFocusChanged(field: SecureField, isFocused: Bool) {
    let borderView = containerView(for: field)
    borderView.layer.borderColor = isFocused
        ? UIColor.systemBlue.cgColor
        : UIColor.separator.cgColor
}

func secureFieldsContentChanged() {
    // Fires on any keystroke in any field.
    // Useful to update auxiliary UI without querying individual fields.
}
```

### Handle brand detection

`secureFieldsBrandsDetected(_:)` fires when the BIN lookup returns results (≥ 8 digits typed)
or when the card number drops below 8 digits (empty array). The lookup is repeated as the PAN
grows, up to the 11 digits the gateway reads, so a brand may be reported after the 8th digit
returned nothing — expect more than one event per card.

```swift
func secureFieldsBrandsDetected(_ brands: [CardBrand]) {
    // brands — e.g. [.visa] or [.visa, .carteBancaire] for co-branded cards
    brandImageView.image = brands.first.map { brandImage($0) }
    brandImageView.isHidden = brands.isEmpty
}

func secureFieldsBrandSelected(_ brand: CardBrand) {
    // Fires when the user picks a brand from the in-PAN brand selector.
    // brand — the selected network
    cvvLabel.text = brand == .oney ? "Date of birth" : "CVV"
}
```

### Handle errors

`secureFieldsDidFail(_:)` fires when `submit()` encounters a problem:

```swift
func secureFieldsDidFail(_ error: SecureFieldsError) {
    payButton.isEnabled = secureFields.isFieldValid(.pan)
        && secureFields.isFieldValid(.cvv)
        && secureFields.isFieldValid(.expDate)

    switch error {
    case .fieldsIncomplete:
        showAlert("Please complete all card fields.")
    case .networkError(let underlying):
        showAlert("Network error: \(underlying.localizedDescription)")
    case .apiError(let message, let statusCode):
        showAlert("Payment error (\(statusCode)): \(message)")
    case .invalidResponse:
        showAlert("Unexpected response from the server.")
    }
}
```

### Handle screenshot detection

`secureFieldsScreenshotDetected()` fires immediately after the system screenshot notification.
The screenshot has already been saved — the SDK cannot prevent it. Respond by clearing fields
and warning the user:

```swift
func secureFieldsScreenshotDetected() {
    secureFields.clearFields()
    showAlert("Screenshot detected. For your security, please re-enter your card details.")
}
```

---

## Submit the form

Call `submit()` when the user taps Pay. The SDK validates all fields internally and fires
`secureFieldsDidTokenize` or `secureFieldsDidFail` on your delegate.

```swift
@objc func payTapped() {
    payButton.isEnabled = false
    loadingIndicator.startAnimating()
    secureFields.submit()
}
```

`submit()` is a no-op and fires `secureFieldsDidFail(.fieldsIncomplete)` if any required
field is invalid. The Pay button guard above is belt-and-suspenders only.

### Submit with saveToken

Pass `saveToken: true` to persist the card for future payments:

```swift
secureFields.submit(saveToken: true)
```

The vault stores the card and returns the same `vault_form_token`. Your backend can use the
token for subsequent charges without re-entering the card.

---

## Handle the tokenization result

`secureFieldsDidTokenize(_:)` delivers a `TokenizationResult`:

```swift
func secureFieldsDidTokenize(_ result: TokenizationResult) {
    loadingIndicator.stopAnimating()

    print("Token:      \(result.vaultFormToken)")
    print("BIN:        \(result.bin)")              // first 8 digits — never the full PAN
    print("Last four:  \(result.lastFourDigits)")
    print("Brands:     \(result.detectedBrands)")

    // Send vaultFormToken to your backend — never send raw card data
    sendTokenToBackend(result.vaultFormToken)
}
```

| Field | Description |
|---|---|
| `vaultFormToken` | Opaque server-side token — send to your backend |
| `bin` | First 8 digits of the PAN (never the full card number) |
| `lastFourDigits` | Last 4 digits of the PAN |
| `detectedBrands` | Card networks detected by the BIN lookup |

---

## Clear fields

Call `clearFields()` to wipe all card data from memory and reset the form:

```swift
@objc func clearTapped() {
    secureFields.clearFields()
    resultLabel.text = nil
    payButton.isEnabled = false
}
```

`clearFields()` zeroes all internal field buffers, cancels any pending BIN lookup, resets the
brand selector, and fires `secureFieldsBrandsDetected([])` and
`secureFieldsFormValidityChanged(false)` on your delegate.

---

## Error reference

| Case | Trigger |
|---|---|
| `.fieldsIncomplete` | `submit()` called while one or more required fields are invalid |
| `.networkError(Error)` | URLSession transport failure (no network, timeout, cancelled) |
| `.apiError(message:statusCode:)` | Non-2xx HTTP response from the vault API |
| `.invalidResponse` | Response could not be decoded |

---

## See also

- [UI Components](ui-components.md)
- [Getting Started](getting-started.md)
- [API Reference](api-reference.md)
