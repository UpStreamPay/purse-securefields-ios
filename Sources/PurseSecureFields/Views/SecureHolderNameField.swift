import UIKit

final class SecureHolderNameField: SecureBaseField {

    var rawValue: String { storedText ?? "" }
    var hasContent: Bool { !rawValue.trimmingCharacters(in: .whitespaces).isEmpty }

    override func setup() {
        super.setup()
        keyboardType = .default
        autocorrectionType = .no
        autocapitalizationType = .words
        spellCheckingType = .no
        textContentType = .name
    }

    @objc override func textDidChange() {
        onContentChanged?()
        setValidity(!(storedText ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
    }


}
