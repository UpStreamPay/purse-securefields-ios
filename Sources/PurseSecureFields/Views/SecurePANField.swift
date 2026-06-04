import UIKit

final class SecurePANField: SecureBaseField {

    var onDigitsChanged: ((String) -> Void)?

    var rawValue: String { (storedText ?? "").filter(\.isNumber) }
    var hasContent: Bool { !rawValue.isEmpty }

    var validLengths: [Int] = [16] {
        didSet { if oldValue != validLengths { textDidChange() } }
    }

    override func setup() {
        super.setup()
        keyboardType = .numberPad
        autocorrectionType = .no
        spellCheckingType = .no
        textContentType = .creditCardNumber
    }

    @objc override func textDidChange() {
        let digits = rawValue
        text = CardFormatter.formatPAN(digits)
        let end = endOfDocument
        selectedTextRange = textRange(from: end, to: end)
        onDigitsChanged?(digits)
        setValidity(validLengths.contains(digits.count) && CardValidator.luhn(digits))
    }
}
