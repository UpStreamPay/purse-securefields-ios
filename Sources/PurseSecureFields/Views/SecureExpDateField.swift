import UIKit

final class SecureExpDateField: SecureBaseField {

    var hasContent: Bool { !(storedText?.isEmpty ?? true) }

    var parsedExpiry: (month: Int, year: Int) {
        let digits = (storedText ?? "").filter { $0.isNumber }
        guard digits.count == 4 else { return (0, 0) }
        let month = Int(digits.prefix(2)) ?? 0
        let shortYear = Int(digits.suffix(2)) ?? 0
        return (month, 2000 + shortYear)
    }

    override func setup() {
        super.setup()
        keyboardType = .numberPad
        autocorrectionType = .no
        placeholder = "MM/YY"
    }

    @objc override func textDidChange() {
        let digits = (storedText ?? "").filter { $0.isNumber }
        let truncated = String(digits.prefix(4))
        text = truncated.count > 2
            ? String(truncated.prefix(2)) + "/" + String(truncated.dropFirst(2))
            : truncated
        let (month, year) = parsedExpiry
        onContentChanged?()
        setValidity(month >= 1 && month <= 12 && CardValidator.isExpiryValid(month: month, year: year))
    }
}
