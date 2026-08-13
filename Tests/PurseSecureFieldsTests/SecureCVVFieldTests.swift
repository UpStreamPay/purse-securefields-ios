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

    // MARK: validLengths

    @Test func validLengths4Only_3digitInvalid() {
        let field = SecureCVVField()
        field.validLengths = [4]

        field.text = "123"
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func validLengths4Only_4digitValid() {
        let field = SecureCVVField()
        field.validLengths = [4]

        field.text = "1234"
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func validLengths3Or4_3digitValid() {
        let field = SecureCVVField()
        field.validLengths = [3, 4]

        field.text = "123"
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func validLengths3Or4_4digitValid() {
        let field = SecureCVVField()
        field.validLengths = [3, 4]

        field.text = "1234"
        field.textDidChange()
        #expect(field.isValid)
    }

    // MARK: Truncation

    @Test func truncatesToMaxValidLength() {
        let field = SecureCVVField()
        field.text = "12345" // 5 digits, max valid = 3
        field.textDidChange()
        #expect(field.storedText == "123")
    }

    @Test func truncatesToMaxWhenMultipleLengths() {
        let field = SecureCVVField()
        field.validLengths = [3, 4]
        field.text = "12345" // 5 digits, max valid = 4
        field.textDidChange()
        #expect(field.storedText == "1234")
    }

    // MARK: Expected-length change (brand detection / chip tap)

    @Test func lengthShrinkKeepsValueAndInvalidates() {
        let field = SecureCVVField()
        field.validLengths = [4]
        field.text = "1234"
        field.textDidChange()
        #expect(field.isValid)

        // AMEX → VISA: the typed value must survive and turn invalid — silently truncating it
        // made an amputated CVV look valid (web keeps the value and sets aria-invalid).
        field.validLengths = [3]
        #expect(field.storedText == "1234")
        #expect(!field.isValid)
    }

    @Test func lengthGrowKeepsValueAndInvalidates() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.isValid)

        field.validLengths = [4]
        #expect(field.storedText == "123")
        #expect(!field.isValid)
    }

    @Test func lengthChangeFiresValidityCallback() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()

        var changes: [Bool] = []
        field.onValidityChanged = { changes.append($0) }
        field.validLengths = [4]
        #expect(changes == [false])
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

    // MARK: onValidityChanged

    @Test func onValidityChangedFires() {
        let field = SecureCVVField()
        var changes: [Bool] = []
        field.onValidityChanged = { changes.append($0) }

        field.text = "123"
        field.textDidChange()
        #expect(changes == [true])

        field.text = "12"
        field.textDidChange()
        #expect(changes == [true, false])
    }

    // MARK: Birthdate mode

    @Test func birthdateModeHasContentFalseWhenEmpty() {
        let field = SecureCVVField()
        field.setInputMode(.birthdate)
        // The mode switch just cleared the field and no date has been picked — `hasContent`
        // must say so instead of hardcoding true (the field is empty AND invalid here).
        #expect(!field.hasContent)
    }

    @Test func birthdateModeHasContentTrueOncePicked() {
        let field = SecureCVVField()
        field.setInputMode(.birthdate)
        field.text = "2000-01-01"
        #expect(field.hasContent)
    }

    @Test func birthdateModeInvalidUntilUserPicks() {
        let field = SecureCVVField()
        field.setInputMode(.birthdate)
        // The birth date must NOT auto-populate/auto-validate — the user has to pick a date first.
        #expect(!field.isValid)
    }

    @Test func birthdateModeClearsOldCVV() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()

        field.setInputMode(.birthdate)
        // Old CVV digits must be gone; the field is left empty until the user picks a date.
        #expect(field.storedText != "123")
    }

    @Test func birthdateModeTextDidChangeIsNoop() {
        let field = SecureCVVField()
        field.setInputMode(.birthdate)
        field.text = "should-be-ignored"
        field.textDidChange()
        #expect(field.storedText == "should-be-ignored") // not truncated/filtered
    }

    @Test func switchBackToCVVClearsAndInvalidates() {
        let field = SecureCVVField()
        field.setInputMode(.birthdate)

        field.setInputMode(.cvv)
        #expect(!field.isValid)
        #expect(field.storedText == "")
    }
}
