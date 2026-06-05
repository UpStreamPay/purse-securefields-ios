import Testing
import Foundation
@testable import PurseSecureFields

struct CardValidatorTests {

    // MARK: Luhn

    @Test(arguments: [
        ("4111111111111111", true),   // Visa
        ("378282246310005",  true),   // Amex
        ("5500005555555559", true),   // Mastercard
        ("6011111111111117", true),   // Discover
        ("0",                true),   // Mathematically valid (sum=0)
        ("4111111111111112", false),  // Bad last digit
        ("4111111111111161", false),  // Transposition
        ("",                 false),
    ])
    func luhn(pan: String, expected: Bool) {
        #expect(CardValidator.luhn(pan) == expected)
    }

    // MARK: Expiry — static cases (no Calendar dependency)

    @Test(arguments: [
        (12, 2000, false),  // past year
        (0,  2000, false),  // past year, month 0
        (13, 2000, false),  // past year, month 13
    ])
    func expiryStaticInvalid(month: Int, year: Int, expected: Bool) {
        #expect(CardValidator.isExpiryValid(month: month, year: year) == expected)
    }

    // MARK: Expiry — dynamic (relative to today)

    @Test func expiryFutureYearValid() {
        #expect(CardValidator.isExpiryValid(month: 1, year: Calendar.current.component(.year, from: .now) + 1))
    }

    @Test func expiryCurrentMonthValid() {
        let cal = Calendar.current
        #expect(CardValidator.isExpiryValid(
            month: cal.component(.month, from: .now),
            year: cal.component(.year, from: .now)
        ))
    }

    @Test func expiryPastYearInvalid() {
        #expect(!CardValidator.isExpiryValid(month: 12, year: Calendar.current.component(.year, from: .now) - 1))
    }

    @Test func expiryPastMonthCurrentYearInvalid() {
        let cal = Calendar.current
        let month = cal.component(.month, from: .now)
        guard month > 1 else { return }
        #expect(!CardValidator.isExpiryValid(month: month - 1, year: cal.component(.year, from: .now)))
    }

    @Test func expiryFarFutureValid() {
        #expect(CardValidator.isExpiryValid(month: 12, year: Calendar.current.component(.year, from: .now) + 10))
    }
}
