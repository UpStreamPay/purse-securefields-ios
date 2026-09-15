import Testing
@testable import PurseSecureFields

/// The static per-brand CVV lengths a CVV-only form falls back to: there is no PAN
/// to look up, so the brand the host knows is the only source — web and Android do the same.
struct CardBrandCVVOnlyLengthsTests {

    @Test func amexTakesFourDigitsEveryOtherPinBrandThree() {
        #expect(CardBrand.amex.standingCVVLengths == [4])
        for brand in [CardBrand.visa, .mastercard, .maestro, .carteBancaire] {
            #expect(brand.standingCVVLengths == [3], "\(brand)")
        }
        #expect(CardBrand.oney.standingCVVLengths == nil, "Oney's CVV is a birth date, not digits")
    }

    @Test func singleBrandAppliesAsIs() {
        #expect(CardBrand.cvvOnlyLengths(for: [.amex]) == [4])
        #expect(CardBrand.cvvOnlyLengths(for: [.visa]) == [3])
    }

    @Test func severalBrandsAcceptTheUnionOfTheirLengths() {
        #expect(CardBrand.cvvOnlyLengths(for: [.visa, .amex]) == [3, 4])
        #expect(CardBrand.cvvOnlyLengths(for: [.visa, .mastercard, .carteBancaire]) == [3],
                "brands that agree on 3 digits still refuse a 4th")
        #expect(CardBrand.cvvOnlyLengths(for: CardBrand.allCases) == [3, 4])
    }

    @Test func noPinBrandFallsBackToBothLengths() {
        #expect(CardBrand.cvvOnlyLengths(for: []) == [3, 4])
        #expect(CardBrand.cvvOnlyLengths(for: [.oney]) == [3, 4], "Oney alone narrows nothing on a CVV-only form")
    }
}

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
