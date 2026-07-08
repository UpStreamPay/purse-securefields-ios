#if DEBUG
import PurseSecureFields

/// `SecureFieldsDelegate` only supplies default (no-op) implementations for
/// `secureFieldsBrandSelected`, `secureFieldsContentChanged`, `secureFieldsFocusChanged` and
/// `secureFieldsScreenshotDetected` — the other four methods are required with no default. Adding
/// no-op defaults for those here lets every bug screen below implement only the callback(s) it
/// actually needs to demonstrate its bug, instead of stubbing all eight every time.
extension SecureFieldsDelegate {
    func secureFieldsDidTokenize(_ result: TokenizationResult) {}
    func secureFieldsDidFail(_ error: SecureFieldsError) {}
    func secureFieldsBrandsDetected(_ brands: [CardBrand]) {}
    func secureFieldsFormValidityChanged(_ isValid: Bool) {}
}
#endif
