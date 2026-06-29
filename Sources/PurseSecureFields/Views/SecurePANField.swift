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
        text = CardFormatter.formatPAN(digits)
        let end = endOfDocument
        selectedTextRange = textRange(from: end, to: end)
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
