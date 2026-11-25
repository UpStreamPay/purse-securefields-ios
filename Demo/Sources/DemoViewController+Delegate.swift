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
        // The SDK has already reset the form (and reported it invalid) by the time this fires.
        payButton.isEnabled = formValid
        resultLabel.textColor = .systemGreen
        // `bin`/`lastFourDigits` are nil on a CVV-only tokenization — the vault stored a cryptogram
        // against a card it already knows, and echoes no card block.
        // `threeDSServerTransID` / `sdk` are filled only when the Pay tap asked for Purse 3DS
        // and the `PurseSecureFields3DS` product is linked.
        let summary = """
        vault_form_token: \(result.vaultFormToken)
        bin: \(result.bin ?? "—")
        last_four: \(result.lastFourDigits ?? "—")
        brands: \(result.detectedBrands.map(\.rawValue).joined(separator: ", "))
        3ds trans: \(result.threeDSServerTransID ?? "—")
        3ds sdk: \(Self.prettySDK(result.sdk))
        """
        resultLabel.text = summary
        // The advanced flow carries on at the merchant backend: payment, then challenge.
        if result.threeDSServerTransID != nil, DemoBackend.baseURL != nil {
            pay(with: result, summary: summary)
        }
    }

    /// The `sdk` block exactly as it goes on the wire — what you paste into the payment call
    /// (`authentication.sdk`) to get a `challenge_data` back.
    private static func prettySDK(_ sdk: ThreeDSSDKBlock?) -> String {
        guard let sdk else { return "—" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sdk), let json = String(data: data, encoding: .utf8) else {
            return "app \(sdk.appID)"
        }
        return "\n\(json)"
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
        case .threeDS(let threeDSError):
            resultLabel.text = "3DS error: \(threeDSError)"
        }
    }
}
