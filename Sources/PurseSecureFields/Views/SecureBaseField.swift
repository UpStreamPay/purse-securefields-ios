import UIKit

class SecureBaseField: UITextField {

    // Internal — host app has no need to observe these directly
    var onValidityChanged: ((Bool) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var onContentChanged: (() -> Void)?

    private(set) var isValid = false

    // MARK: - PCI field isolation
    //
    // The three overrides below prevent the host app from reading raw card data
    // by casting any exposed UIView back to UITextField.
    //
    // UIKit renders from its internal backing storage (bypasses these getters),
    // so display is unaffected. Only external readers are blocked.

    override var text: String? {
        get { nil }
        set { super.text = newValue }
    }

    /// Blocks `(field as? UITextField)?.attributedText` from leaking card data.
    override var attributedText: NSAttributedString? {
        get { nil }
        set { super.attributedText = newValue }
    }

    /// Blocks VoiceOver / accessibility APIs from announcing card data.
    override var accessibilityValue: String? {
        get { nil }
        set { super.accessibilityValue = newValue }
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
        // Registered after textDidChange so the restyle sees the validity that keystroke produced.
        addTarget(self, action: #selector(applyStateStyle), for: .editingChanged)
    }

    @objc func textDidChange() {}

    @objc private func didBeginEditing() {
        applyStateStyle()
        onFocusChanged?(true)
    }
    @objc private func didEndEditing() {
        applyStateStyle()
        onFocusChanged?(false)
    }

    func setValidity(_ newValid: Bool) {
        if newValid != isValid {
            isValid = newValid
            applyStateStyle()
            onValidityChanged?(isValid)
        }
    }

    func clearSensitiveData() {
        text = ""
        isValid = false
        applyStateStyle()
    }

    // MARK: - Styling

    private var style: SecureFieldsStyle?

    func applyStyle(_ style: SecureFieldsStyle) {
        self.style = style
        font = style.font
        tintColor = style.tintColor
        keyboardAppearance = style.keyboardAppearance
        layer.cornerRadius = style.cornerRadius
        applyStateStyle()
    }

    /// Repaints the state-dependent properties for the field's current focus/validity/content.
    /// Everything a state leaves unset falls back to the base style, so a field always ends up
    /// fully painted rather than keeping a colour from the state it just left.
    @objc func applyStateStyle() {
        guard let style else { return }
        let state = style.stateStyle(
            isFocused: isFirstResponder,
            isValid: isValid,
            hasContent: !(storedText?.isEmpty ?? true)
        )
        textColor = state?.textColor ?? style.textColor
        backgroundColor = state?.backgroundColor ?? style.backgroundColor
        layer.borderWidth = state?.borderWidth ?? style.borderWidth
        let border = state?.borderColor ?? style.borderColor
        layer.borderColor = border?.cgColor
    }

    func applyPlaceholder(_ text: String, color: UIColor) {
        attributedPlaceholder = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: color]
        )
    }
}
