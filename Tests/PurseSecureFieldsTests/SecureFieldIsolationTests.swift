import Testing
import UIKit
@testable import PurseSecureFields

/// Regression tests for the PCI field-isolation controls.
/// These guard against host-app bypass of the text/attributedText/accessibilityValue nil overrides
/// and pasteboard-leakage via copy/cut on the PAN field.
@MainActor
struct SecureFieldIsolationTests {

    // MARK: - SecureBaseField text isolation (F1)

    @Test func panField_textAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.text == nil)
    }

    @Test func panField_attributedTextAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.attributedText == nil)
    }

    @Test func panField_accessibilityValueAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.accessibilityValue == nil)
    }

    @Test func panField_kvcTextAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        // KVC calls the Swift property getter, which returns nil
        #expect(field.value(forKey: "text") == nil)
    }

    @Test func cvvField_textAlwaysNil() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.text == nil)
    }

    @Test func cvvField_attributedTextAlwaysNil() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.attributedText == nil)
    }

    @Test func cvvField_accessibilityValueAlwaysNil() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.accessibilityValue == nil)
    }

    @Test func expDateField_attributedTextAlwaysNil() {
        let field = SecureExpDateField()
        field.text = "12/30"
        field.textDidChange()
        #expect(field.attributedText == nil)
    }

    @Test func holderNameField_attributedTextAlwaysNil() {
        let field = SecureHolderNameField()
        field.text = "John Doe"
        field.textDidChange()
        #expect(field.attributedText == nil)
    }

    // MARK: - UITextField cast bypass (the original attack vector)

    @Test func panField_castToUITextField_textStillNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        let casted = field as UITextField
        #expect(casted.text == nil)
        #expect(casted.attributedText == nil)
        #expect(casted.accessibilityValue == nil)
    }

    @Test func cvvField_castToUITextField_textStillNil() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        let casted = field as UITextField
        #expect(casted.text == nil)
        #expect(casted.attributedText == nil)
        #expect(casted.accessibilityValue == nil)
    }

    // MARK: - storedText / rawValue still accessible internally

    @Test func panField_rawValueStillReadable() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        // Internal API works; public API returns nil
        #expect(field.rawValue == "4111111111111111")
    }

    // MARK: - PAN copy/cut blocked (F4)

    @Test func panField_copyBlocked() {
        let field = SecurePANField()
        #expect(field.canPerformAction(#selector(UIResponder.copy(_:)), withSender: nil) == false)
    }

    @Test func panField_cutBlocked() {
        let field = SecurePANField()
        #expect(field.canPerformAction(#selector(UIResponder.cut(_:)), withSender: nil) == false)
    }

    @Test func panField_dragDelegateInstalled() {
        // The field sets itself as UITextDragDelegate and returns [] from itemsForDrag,
        // which suppresses all drag operations. Verify the delegate is wired.
        let field = SecurePANField()
        #expect(field.textDragDelegate === field)
    }
}
