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
}

public extension SecureFieldsDelegate {
    func secureFieldsBrandSelected(_ brand: CardBrand) {}
    func secureFieldsContentChanged() {}
    func secureFieldsFocusChanged(field: SecureField, isFocused: Bool) {}
    func secureFieldsScreenshotDetected() {}
}
