import Testing
import UIKit
@testable import PurseSecureFields

@MainActor
struct SecureHolderNameFieldTests {

    // MARK: Validity

    @Test func validName() {
        let field = SecureHolderNameField()
        field.text = "John Doe"
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func singleWordValid() {
        let field = SecureHolderNameField()
        field.text = "Alice"
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func emptyInvalid() {
        let field = SecureHolderNameField()
        field.text = ""
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func whitespaceOnlyInvalid() {
        let field = SecureHolderNameField()
        field.text = "   "
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func tabOnlyInvalid() {
        let field = SecureHolderNameField()
        field.text = "\t"
        field.textDidChange()
        #expect(!field.isValid)
    }

    // MARK: PCI — text always nil

    @Test func textGetterAlwaysNil() {
        let field = SecureHolderNameField()
        field.text = "John Doe"
        #expect(field.text == nil)
    }

    // MARK: rawValue

    @Test func rawValueReturnsStoredText() {
        let field = SecureHolderNameField()
        field.text = "Jane Smith"
        field.textDidChange()
        // rawValue uses storedText — after textDidChange the stored text is still "Jane Smith"
        #expect(field.rawValue == "Jane Smith")
    }

    // MARK: clearSensitiveData

    @Test func clearResetsValidityAndText() {
        let field = SecureHolderNameField()
        field.text = "John Doe"
        field.textDidChange()
        #expect(field.isValid)

        field.clearSensitiveData()
        #expect(!field.isValid)
        #expect(field.storedText == "")
    }

    // MARK: Callbacks

    @Test func onValidityChangedFires() {
        let field = SecureHolderNameField()
        var changes: [Bool] = []
        field.onValidityChanged = { changes.append($0) }

        field.text = "John Doe"
        field.textDidChange()
        #expect(changes == [true])

        field.text = ""
        field.textDidChange()
        #expect(changes == [true, false])
    }

    @Test func onContentChangedFires() {
        let field = SecureHolderNameField()
        var count = 0
        field.onContentChanged = { count += 1 }

        field.text = "J"
        field.textDidChange()
        #expect(count == 1)
    }

    // MARK: hasContent

    @Test func hasContentFalseWhenEmpty() {
        #expect(!SecureHolderNameField().hasContent)
    }

    @Test func hasContentTrueWhenNonEmpty() {
        let field = SecureHolderNameField()
        field.text = "J"
        field.textDidChange()
        #expect(field.hasContent)
    }
}
