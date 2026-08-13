import Testing
@testable import PurseSecureFields

struct CardBrandTests {

    @Test func apiValueAcceptsRawValues() {
        #expect(CardBrand(apiValue: "VISA") == .visa)
        #expect(CardBrand(apiValue: "MASTERCARD") == .mastercard)
        #expect(CardBrand(apiValue: "AMEX") == .amex)
        #expect(CardBrand(apiValue: "MAESTRO") == .maestro)
        #expect(CardBrand(apiValue: "CARTE_BANCAIRE") == .carteBancaire)
        #expect(CardBrand(apiValue: "ONEY") == .oney)
    }

    @Test func apiValueAcceptsAPIAliases() {
        // The vault API says "AMERICAN_EXPRESS" where the enum raw value is "AMEX" — both must
        // resolve, or any JSON-crossing config silently loses the brand.
        #expect(CardBrand(apiValue: "AMERICAN_EXPRESS") == .amex)
    }

    @Test func apiValueRejectsUnknownSchemes() {
        #expect(CardBrand(apiValue: "DINERS_CLUB") == nil) // no Diners support on iOS
        #expect(CardBrand(apiValue: "DISCOVER") == nil)
        #expect(CardBrand(apiValue: "") == nil)
    }
}
