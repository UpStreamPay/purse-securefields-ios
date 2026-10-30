import UIKit

final class SecureHolderNameField: SecureBaseField {

    var rawValue: String { storedText ?? "" }
    var hasContent: Bool { !rawValue.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The name for the tokenization request, trimmed of `.whitespaces` as
    /// `trimmingCharacters(in:)` would: a wipeable copy, never a `String`.
    func copyTrimmedValue() -> SensitiveBuffer {
        let scalars = (storedText ?? "").unicodeScalars
        let buffer = SensitiveBuffer()
        guard let first = scalars.firstIndex(where: { !CharacterSet.whitespaces.contains($0) }),
              let last = scalars.lastIndex(where: { !CharacterSet.whitespaces.contains($0) }) else {
            return buffer
        }
        for scalar in scalars[first...last] {
            UTF8.encode(scalar) { buffer.append($0) }
        }
        return buffer
    }

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
