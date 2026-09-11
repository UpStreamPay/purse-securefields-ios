import UIKit
import PurseSecureFields

extension DemoViewController: SecureFieldsDelegate {

    func secureFieldsFormValidityChanged(_ isValid: Bool) {
        formValid = isValid
        payButton.isEnabled = isValid
        panLength = manager.panDigitCount
        panValid = manager.isFieldValid(.pan)
        cvvValid = manager.isFieldValid(.cvv)
        expiryValid = manager.isFieldValid(.expDate)
        updateDebugPanel()
        updateFieldBorders()
    }

    func secureFieldsContentChanged() {
        panLength = manager.panDigitCount
        updateFieldBorders()
    }

    func secureFieldsFocusChanged(field: SecureField, isFocused: Bool) {
        updateFieldBorders()
    }

    func secureFieldsBrandsDetected(_ brands: [CardBrand]) {
        detectedBrands = brands
        updateCVVLabel(isOney: brands.first == .oney)
        updateDebugPanel()
    }

    func secureFieldsBrandSelected(_ brand: CardBrand) {
        updateCVVLabel(isOney: brand == .oney)
        updateDebugPanel()
    }

    func secureFieldsDidTokenize(_ result: TokenizationResult) {
        payButton.isEnabled = true
        resultLabel.textColor = .systemGreen
        // `bin`/`lastFourDigits` are nil on a CVV-only tokenization — the vault stored a cryptogram
        // against a card it already knows, and echoes no card block.
        resultLabel.text = """
        vault_form_token: \(result.vaultFormToken)
        bin: \(result.bin ?? "—")
        last_four: \(result.lastFourDigits ?? "—")
        brands: \(result.detectedBrands.map(\.rawValue).joined(separator: ", "))
        """
    }

    func secureFieldsDidFail(_ error: SecureFieldsError) {
        payButton.isEnabled = formValid
        resultLabel.textColor = .systemRed
        switch error {
        case .fieldsIncomplete:
            resultLabel.text = "Error: fields incomplete"
        case .networkError(let err):
            resultLabel.text = "Network error: \(err.localizedDescription)"
        case .apiError(let message, let code):
            resultLabel.text = "API error \(code): \(message)"
        case .invalidResponse:
            resultLabel.text = "Error: invalid response"
        }
    }
}
