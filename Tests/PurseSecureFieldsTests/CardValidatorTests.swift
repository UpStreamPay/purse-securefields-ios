import Testing
import Foundation
@testable import PurseSecureFields

struct CardValidatorTests {

    // MARK: Luhn

    @Test func luhnValidVisa() {
        #expect(CardValidator.luhn("4111111111111111"))
    }

    @Test func luhnValidAmex() {
        #expect(CardValidator.luhn("378282246310005"))
    }

    @Test func luhnValidMastercard() {
        #expect(CardValidator.luhn("5500005555555559"))
    }

    @Test func luhnValidDiscover() {
        #expect(CardValidator.luhn("6011111111111117"))
    }

    @Test func luhnInvalidLastDigit() {
        #expect(!CardValidator.luhn("4111111111111112"))
    }

    @Test func luhnInvalidTransposition() {
        #expect(!CardValidator.luhn("4111111111111161"))
    }

    @Test func luhnEmptyInvalid() {
        #expect(!CardValidator.luhn(""))
    }

    @Test func luhnSingleZeroValid() {
        // Mathematically valid: sum=0, 0%10==0. No real card, but algorithm is correct.
        #expect(CardValidator.luhn("0"))
    }

    // MARK: Expiry

    @Test func expiryFutureYearValid() {
        let futureYear = Calendar.current.component(.year, from: .now) + 1
        #expect(CardValidator.isExpiryValid(month: 1, year: futureYear))
    }

    @Test func expiryCurrentMonthCurrentYearValid() {
        let cal = Calendar.current
        let year = cal.component(.year, from: .now)
        let month = cal.component(.month, from: .now)
        #expect(CardValidator.isExpiryValid(month: month, year: year))
    }

    @Test func expiryPastYearInvalid() {
        let pastYear = Calendar.current.component(.year, from: .now) - 1
        #expect(!CardValidator.isExpiryValid(month: 12, year: pastYear))
    }

    @Test func expiryPastMonthCurrentYearInvalid() {
        let cal = Calendar.current
        let year = cal.component(.year, from: .now)
        let month = cal.component(.month, from: .now)
        guard month > 1 else { return }
        #expect(!CardValidator.isExpiryValid(month: month - 1, year: year))
    }

    @Test func expiryDecemberFarFutureValid() {
        let farFuture = Calendar.current.component(.year, from: .now) + 10
        #expect(CardValidator.isExpiryValid(month: 12, year: farFuture))
    }

    @Test func expiryPastYearMonthZeroInvalid() {
        // CardValidator only checks date expiry, not month range (1-12). Past year → always false.
        #expect(!CardValidator.isExpiryValid(month: 0, year: 2000))
    }

    @Test func expiryPastYearMonth13Invalid() {
        #expect(!CardValidator.isExpiryValid(month: 13, year: 2000))
    }
}
