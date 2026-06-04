import UIKit

class SecureBaseField: UITextField {

    // Internal — host app has no need to observe these directly
    var onValidityChanged: ((Bool) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var onContentChanged: (() -> Void)?

    private(set) var isValid = false

    override var text: String? {
        get { nil }
        set { super.text = newValue }
    }

    /// Reads the real UITextField backing value. Subclasses use this instead of super.text,
    /// which would call SecureBaseField.text.get → nil.
    var storedText: String? { super.text }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setup() {
        addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        addTarget(self, action: #selector(didBeginEditing), for: .editingDidBegin)
        addTarget(self, action: #selector(didEndEditing), for: .editingDidEnd)
    }

    @objc func textDidChange() {}

    @objc private func didBeginEditing() {
        onFocusChanged?(true)
    }
    @objc private func didEndEditing()   { onFocusChanged?(false) }

    func setValidity(_ newValid: Bool) {
        if newValid != isValid {
            isValid = newValid
            onValidityChanged?(isValid)
        }
    }

    func clearSensitiveData() {
        text = ""
        isValid = false
    }

    func applyStyle(_ style: SecureFieldsStyle) {
        font = style.font
        textColor = style.textColor
        tintColor = style.tintColor
        keyboardAppearance = style.keyboardAppearance
    }

    func applyPlaceholder(_ text: String, color: UIColor) {
        attributedPlaceholder = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: color]
        )
    }
}
