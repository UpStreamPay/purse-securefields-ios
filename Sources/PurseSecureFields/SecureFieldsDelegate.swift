public enum SecureField {
    case pan, cvv, expDate, holderName
}

public protocol SecureFieldsDelegate: AnyObject {
    func secureFieldsDidTokenize(_ result: TokenizationResult)
    func secureFieldsDidFail(_ error: SecureFieldsError)
    func secureFieldsBrandsDetected(_ brands: [CardBrand])
    func secureFieldsFormValidityChanged(_ isValid: Bool)
    func secureFieldsBrandSelected(_ brand: CardBrand)
    func secureFieldsContentChanged()
    func secureFieldsFocusChanged(field: SecureField, isFocused: Bool)
    /// Called immediately after the system fires UIApplication.userDidTakeScreenshotNotification.
    /// The screenshot has already been saved; the SDK cannot prevent it. The host app should
    /// respond by calling manager.clearFields() and, where appropriate, showing a warning to
    /// the cardholder. Default implementation is a no-op.
    func secureFieldsScreenshotDetected()
    /// Called when a BIN lookup fails (network error, HTTP error, undecodable response). Brand
    /// state is left untouched and the lookup retries on the next PAN change; this event exists
    /// so the host can tell an outage apart from "this card has no authorized brand" and degrade
    /// gracefully. Default implementation is a no-op.
    func secureFieldsBinLookupFailed(_ error: SecureFieldsError)
}

public extension SecureFieldsDelegate {
    func secureFieldsBrandSelected(_ brand: CardBrand) {}
    func secureFieldsContentChanged() {}
    func secureFieldsFocusChanged(field: SecureField, isFocused: Bool) {}
    func secureFieldsScreenshotDetected() {}
    func secureFieldsBinLookupFailed(_ error: SecureFieldsError) {}
}
