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
}

public extension SecureFieldsDelegate {
    func secureFieldsBrandSelected(_ brand: CardBrand) {}
    func secureFieldsContentChanged() {}
    func secureFieldsFocusChanged(field: SecureField, isFocused: Bool) {}
}
