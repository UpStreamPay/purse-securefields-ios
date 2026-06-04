import Testing
import UIKit
@testable import PurseSecureFields

@MainActor
struct SecureCVVFieldTests {

    // MARK: Validity

    @Test func valid3Digit() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func invalid2Digit() {
        let field = SecureCVVField()
        field.text = "12"
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func invalidEmpty() {
        let field = SecureCVVField()
        field.textDidChange()
        #expect(!field.isValid)
    }

    // MARK: expectedLength

    @Test func expectedLength4_3digitInvalid() {
        let field = SecureCVVField()
        field.expectedLength = 4

        field.text = "123"
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func expectedLength4_4digitValid() {
        let field = SecureCVVField()
        field.expectedLength = 4

        field.text = "1234"
        field.textDidChange()
        #expect(field.isValid)
    }

    // MARK: Truncation

    @Test func truncatesToExpectedLength() {
        let field = SecureCVVField()
        field.text = "12345" // 5 digits, expected = 3
        field.textDidChange()
        #expect(field.storedText == "123")
    }

    @Test func nonDigitsFiltered() {
        let field = SecureCVVField()
        field.text = "1a2b3"
        field.textDidChange()
        #expect(field.storedText == "123")
    }

    // MARK: PCI — text always nil

    @Test func textGetterAlwaysNil() {
        let field = SecureCVVField()
        field.text = "123"
        #expect(field.text == nil)
    }

    // MARK: clearSensitiveData

    @Test func clearResetsValidityAndText() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.isValid)

        field.clearSensitiveData()
        #expect(!field.isValid)
        #expect(field.storedText == "")
    }

    // MARK: Callbacks

    @Test func onContentChangedFires() {
        let field = SecureCVVField()
        var count = 0
        field.onContentChanged = { count += 1 }

        field.text = "1"
        field.textDidChange()
        #expect(count == 1)

        field.text = "12"
        field.textDidChange()
        #expect(count == 2)
    }

    // MARK: Input mode

    @Test func defaultInputModeIsCVV() {
        let field = SecureCVVField()
        #expect(field.inputMode == .cvv)
    }

    @Test func hasContentFalseWhenEmpty() {
        let field = SecureCVVField()
        #expect(!field.hasContent)
    }

    @Test func hasContentTrueWhenFilled() {
        let field = SecureCVVField()
        field.text = "1"
        field.textDidChange()
        #expect(field.hasContent)
    }
}
