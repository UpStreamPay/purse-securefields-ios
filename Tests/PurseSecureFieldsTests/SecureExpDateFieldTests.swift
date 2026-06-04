import Testing
import Foundation
import UIKit
@testable import PurseSecureFields

@MainActor
struct SecureExpDateFieldTests {

    private var futureShortYear: String {
        let year = (Calendar.current.component(.year, from: .now) + 1) % 100
        return String(format: "%02d", year)
    }

    // MARK: Validity

    @Test func validFutureExpiry() {
        let field = SecureExpDateField()
        field.text = "06" + futureShortYear
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func validCurrentMonthExpiry() {
        let cal = Calendar.current
        let year = cal.component(.year, from: .now) % 100
        let month = cal.component(.month, from: .now)
        let field = SecureExpDateField()
        field.text = String(format: "%02d%02d", month, year)
        field.textDidChange()
        #expect(field.isValid)
    }

    @Test func invalidPastExpiry() {
        let field = SecureExpDateField()
        field.text = "0120" // January 2020 — always in the past
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func invalidMonthZero() {
        let field = SecureExpDateField()
        field.text = "00" + futureShortYear
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func invalidMonth13() {
        let field = SecureExpDateField()
        field.text = "13" + futureShortYear
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func autoPrependsZeroForMonthDigit3to9() {
        let field = SecureExpDateField()
        field.text = "9"
        field.textDidChange()
        #expect(field.storedText == "09")
    }

    @Test func autoPrependsZeroForMonthDigit2() {
        let field = SecureExpDateField()
        field.text = "2"
        field.textDidChange()
        #expect(field.storedText == "02")
    }

    @Test func doesNotPrependZeroForMonthDigit1() {
        let field = SecureExpDateField()
        field.text = "1"
        field.textDidChange()
        #expect(field.storedText == "1") // "1" alone — could be 10, 11, or 12
    }

    @Test func partialInput2DigitsInvalid() {
        let field = SecureExpDateField()
        field.text = "06"
        field.textDidChange()
        #expect(!field.isValid)
    }

    @Test func emptyInvalid() {
        let field = SecureExpDateField()
        field.textDidChange()
        #expect(!field.isValid)
    }

    // MARK: Formatting

    @Test func formatsWithSlash() {
        let field = SecureExpDateField()
        field.text = "0627"
        field.textDidChange()
        #expect(field.storedText == "06/27")
    }

    @Test func partialInputNoSlash() {
        let field = SecureExpDateField()
        field.text = "06"
        field.textDidChange()
        #expect(field.storedText == "06")
    }

    @Test func truncatesTo4Digits() {
        let field = SecureExpDateField()
        field.text = "062799" // 6 digits — only first 4 used
        field.textDidChange()
        #expect(field.storedText == "06/27")
    }

    // MARK: parsedExpiry

    @Test func parsedExpiryCorrect() {
        let field = SecureExpDateField()
        field.text = "0627"
        field.textDidChange()
        let expiry = field.parsedExpiry
        #expect(expiry.month == 6)
        #expect(expiry.year == 2027)
    }

    @Test func parsedExpiryPartialReturnsZeros() {
        let field = SecureExpDateField()
        field.text = "06"
        field.textDidChange()
        let expiry = field.parsedExpiry
        #expect(expiry.month == 0)
        #expect(expiry.year == 0)
    }

    // MARK: PCI — text always nil

    @Test func textGetterAlwaysNil() {
        let field = SecureExpDateField()
        field.text = "0627"
        #expect(field.text == nil)
    }

    // MARK: clearSensitiveData

    @Test func clearResetsValidityAndText() {
        let field = SecureExpDateField()
        field.text = "06" + futureShortYear
        field.textDidChange()
        #expect(field.isValid)

        field.clearSensitiveData()
        #expect(!field.isValid)
        #expect(field.storedText == "")
    }

    // MARK: hasContent

    @Test func hasContentFalseWhenEmpty() {
        let field = SecureExpDateField()
        #expect(!field.hasContent)
    }

    @Test func hasContentTrueWhenFilled() {
        let field = SecureExpDateField()
        field.text = "0627"
        field.textDidChange()
        #expect(field.hasContent)
    }
}
