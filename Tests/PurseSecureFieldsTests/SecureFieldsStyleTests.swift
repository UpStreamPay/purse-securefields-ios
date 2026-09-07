import Testing
import UIKit
@testable import PurseSecureFields

/// State-dependent styling (SDK-12108, gap 17): the SDK paints focus / valid / invalid / empty
/// itself, instead of leaving every integrator to reimplement it from the delegate callbacks.
@MainActor
struct SecureFieldsStyleTests {

    private func themed() -> SecureFieldsStyle {
        SecureFieldsStyle(
            textColor: .label,
            backgroundColor: .white,
            borderColor: .gray,
            borderWidth: 1,
            cornerRadius: 8,
            focus: .init(borderColor: .systemBlue, borderWidth: 2),
            valid: .init(borderColor: .systemGreen),
            invalid: .init(textColor: .systemRed, borderColor: .systemRed),
            empty: .init(borderColor: .lightGray)
        )
    }

    // MARK: - State resolution

    @Test func focusOutranksEveryOtherState() {
        let style = themed()
        let state = style.stateStyle(isFocused: true, isValid: false, hasContent: true)
        #expect(state?.borderColor == .systemBlue)
    }

    @Test func contentResolvesToValidOrInvalid() {
        let style = themed()
        #expect(style.stateStyle(isFocused: false, isValid: true, hasContent: true)?.borderColor == .systemGreen)
        #expect(style.stateStyle(isFocused: false, isValid: false, hasContent: true)?.borderColor == .systemRed)
    }

    @Test func noContentResolvesToEmpty() {
        let style = themed()
        #expect(style.stateStyle(isFocused: false, isValid: false, hasContent: false)?.borderColor == .lightGray)
    }

    @Test func anUnthemedStyleResolvesToNoOverride() {
        let style = SecureFieldsStyle.default
        #expect(style.stateStyle(isFocused: true, isValid: true, hasContent: true) == nil)
    }

    // MARK: - Application to a field

    @Test func baseStyleIsAppliedOnConfiguration() {
        let field = SecureCVVField()
        field.applyStyle(themed())

        #expect(field.layer.cornerRadius == 8)
        #expect(field.backgroundColor == .white)
        // No content, not focused → the empty state's border.
        #expect(field.layer.borderColor == UIColor.lightGray.cgColor)
        #expect(field.layer.borderWidth == 1)
    }

    @Test func typingAnIncompleteValuePaintsTheInvalidState() {
        let field = SecureCVVField()
        field.applyStyle(themed())

        field.text = "12"
        field.textDidChange()
        field.applyStateStyle()   // stands in for the .editingChanged action

        #expect(!field.isValid)
        #expect(field.layer.borderColor == UIColor.systemRed.cgColor)
        #expect(field.textColor == .systemRed)
    }

    @Test func completingTheValuePaintsTheValidState() {
        let field = SecureCVVField()
        field.applyStyle(themed())

        field.text = "123"
        field.textDidChange()

        #expect(field.isValid)
        #expect(field.layer.borderColor == UIColor.systemGreen.cgColor)
        // The invalid state's text colour must not linger once the field turns valid.
        #expect(field.textColor == .label)
    }

    @Test func clearingRepaintsTheEmptyState() {
        let field = SecureCVVField()
        field.applyStyle(themed())
        field.text = "123"
        field.textDidChange()

        field.clearSensitiveData()

        #expect(field.layer.borderColor == UIColor.lightGray.cgColor)
    }

    @Test func anUnthemedFieldGetsNoBorder() {
        let field = SecureCVVField()
        field.applyStyle(.default)

        field.text = "12"
        field.textDidChange()

        #expect(field.layer.borderWidth == 0)
        #expect(field.layer.borderColor == nil)
        #expect(field.backgroundColor == nil)
    }
}
