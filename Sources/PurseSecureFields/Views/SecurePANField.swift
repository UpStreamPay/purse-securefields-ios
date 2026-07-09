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
        // Prevent the PAN from being dragged out to another app — see UITextDragDelegate below.
        textDragDelegate = self
    }

    /// Block Copy and Cut to prevent the formatted PAN landing on UIPasteboard.general
    /// (readable by every other app, synced via Universal Clipboard).
    /// Paste is intentionally kept to support pasting a 19-digit Oney PAN in one shot.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) || action == #selector(cut(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc override func textDidChange() {
        let digits = rawValue

        // Preserve the caret across reformatting. Count how many digits sit before the caret in the
        // current text, reformat, then place the caret after that same number of digits (skipping
        // any separator spaces). Forcing the caret to `endOfDocument` every keystroke made
        // mid-string edits impossible.
        let oldText = storedText ?? ""
        var digitsBeforeCaret = digits.count
        if let selectedRange = selectedTextRange {
            let caretOffset = offset(from: beginningOfDocument, to: selectedRange.end)
            digitsBeforeCaret = oldText.prefix(caretOffset).filter(\.isNumber).count
        }

        let formatted = CardFormatter.formatPAN(digits)
        text = formatted

        var newOffset = 0
        var seenDigits = 0
        for ch in formatted {
            if seenDigits >= digitsBeforeCaret && ch.isNumber { break }
            newOffset += 1
            if ch.isNumber { seenDigits += 1 }
        }
        if let pos = position(from: beginningOfDocument, offset: newOffset) {
            selectedTextRange = textRange(from: pos, to: pos)
        }

        onDigitsChanged?(digits)
        setValidity(validLengths.contains(digits.count) && CardValidator.luhn(digits))
    }
}

// MARK: - Drag prevention

extension SecurePANField: UITextDragDelegate {
    /// Return an empty item list to suppress all drag operations on the PAN field.
    /// This prevents the formatted PAN from being dragged into another app.
    func textDraggableView(
        _ textDraggableView: any UIView & UITextDraggable,
        itemsForDrag dragRequest: UITextDragRequest
    ) -> [UIDragItem] {
        return []
    }
}
