import UIKit

class SecureBaseField: UITextField {

    // Internal — host app has no need to observe these directly
    var onValidityChanged: ((Bool) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var onContentChanged: (() -> Void)?

    private(set) var isValid = false

    // MARK: - PCI field isolation
    //
    // The overrides below prevent the host app from reading raw card data
    // by casting any exposed UIView back to UITextField (or to UITextInput).
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

    /// Blocks `UITextInput.text(in:)`, which reads the document through the protocol and so is
    /// untouched by the `text` override. Masked rather than nil: UIKit's keyboard bridge
    /// (`UIKBRTIPartner`) builds the keyboard's document context from this method on every
    /// keystroke. A same-length mask keeps its offsets and word boundaries consistent (deletion,
    /// `.words` autocapitalization on the holder name) while neither the system keyboard nor a
    /// third-party one ever receives a digit.
    override func text(in range: UITextRange) -> String? {
        super.text(in: range).map(Self.masked)
    }

    /// Same leak as `text(in:)` through the attributed variant of the protocol.
    override func attributedText(in range: UITextRange) -> NSAttributedString {
        NSAttributedString(string: Self.masked(super.attributedText(in: range).string))
    }

    /// One bullet per UTF-16 unit, so lengths match the offsets UITextInput positions are measured
    /// in. Whitespace is kept: it only reveals the PAN grouping (derivable from brand and digit
    /// count, both already given to the host) and the holder name's word breaks.
    static func masked(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                result.unicodeScalars.append(scalar)
            } else {
                result += String(repeating: "•", count: scalar.utf16.count)
            }
        }
        return result
    }

    /// Forces tabular digits on whatever font is set (the style's, or UIKit's default). With
    /// proportional figures the per-character rects UITextInput exposes (`firstRect(for:)`,
    /// `selectionRects(for:)`, `caretRect(for:)`) differ by digit (a system-font `1` is ~3pt
    /// narrower than the others), which let a host locate digits of the PAN through geometry
    /// alone, masked text or not.
    override var font: UIFont? {
        get { super.font }
        set { super.font = newValue.map(Self.withTabularDigits) }
    }

    static func withTabularDigits(_ font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: 0)
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
        // Route UIKit's default font through the override above, for fields never styled.
        font = super.font
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
