import Testing
import UIKit
@testable import PurseSecureFields

@MainActor
struct SecurePANFieldTests {

    // MARK: Validity

    @Test func validLuhn16() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func invalidLuhn() {
        let field = SecurePANField()
        field.text = "4111111111111112"
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func tooShortInvalid() {
        let field = SecurePANField()
        field.text = "411111111111111" // 15 digits
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func emptyInvalid() {
        let field = SecurePANField()
        field.textDidChange()
        #expect(!field.isValid)
    }

    // MARK: validLengths

    @Test func validLengths16Only_16digitPasses() {
        let field = SecurePANField()
        field.validLengths = [16]
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func validLengths16Only_19digitFails() {
        let field = SecurePANField()
        field.validLengths = [16]
        // 19-digit number — length alone disqualifies
        field.text = "4111111111111111111"
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func validLengths19Only_16digitFails() {
        let field = SecurePANField()
        field.validLengths = [19]
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func validLengths16And19_16digitPasses() {
        let field = SecurePANField()
        field.validLengths = [16, 19]
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.isValid)
    }

    // MARK: PCI — text always nil

    @Test func textGetterAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        #expect(field.text == nil)
    }

    // MARK: rawValue and storedText

    @Test func rawValueFiltersSpaces() {
        let field = SecurePANField()
        field.text = "4111 1111 1111 1111"
        #expect(field.rawValue == "4111111111111111")
    }

    @Test func hasContentFalseWhenEmpty() {
        let field = SecurePANField()
        #expect(!field.hasContent)
    }

    @Test func hasContentTrueWhenDigitsPresent() {
        let field = SecurePANField()
        field.text = "4111"
        field.textDidChange()
        #expect(field.hasContent)
    }

    // MARK: clearSensitiveData

    @Test func clearResetsValidityAndText() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.isValid)

        field.clearSensitiveData()
        #expect(!field.isValid)
        #expect(field.storedText == "")
    }

    // MARK: Callbacks

    @Test func onValidityChangedFires() {
        let field = SecurePANField()
        var changes: [Bool] = []
        field.onValidityChanged = { changes.append($0) }

        field.text = "4111111111111111"
        field.textDidChange()
        #expect(changes == [true])

        field.text = "411111111111111" // 15 digits
        field.textDidChange()
        #expect(changes == [true, false])
    }

    @Test func onValidityChangedDoesNotFireIfNoChange() {
        let field = SecurePANField()
        var count = 0
        field.onValidityChanged = { _ in count += 1 }

        field.text = "4111111111111111"
        field.textDidChange()
        #expect(count == 1)

        field.text = "4111111111111111"
        field.textDidChange()
        #expect(count == 1) // no change in validity — callback not fired again
    }

    @Test func onDigitsChangedFiresWithRawDigits() {
        let field = SecurePANField()
        var lastDigits = ""
        field.onDigitsChanged = { lastDigits = $0 }

        field.text = "4111111111111111"
        field.textDidChange()
        #expect(lastDigits == "4111111111111111")
    }

    // MARK: Formatting

    @Test func textDidChangeFormatsDisplayValue() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.storedText == "4111 1111 1111 1111")
    }

    @Test func amexFormattedCorrectly() {
        let field = SecurePANField()
        field.text = "378282246310005"
        field.textDidChange()
        #expect(field.storedText == "3782 822463 10005")
    }
}
