import Foundation
import Testing
@testable import PurseSecureFields

struct NetworkModelsTests {

    @Test func binLookupMapsAPIVocabulary() {
        let response = BinLookupResponse(brands: [
            .init(brand: "AMERICAN_EXPRESS", isMain: true, panLengths: [15], cvvLengths: [4]),
            .init(brand: "VISA", isMain: false, panLengths: [16], cvvLengths: [3]),
        ])

        let result = response.toBinLookupResult()
        #expect(result.brands == [.amex, .visa])
        #expect(result.panLengths == [15])
        #expect(result.cvvLengths == [4])
        #expect(result.perBrandLengths[.amex]?.cvvLengths == [4])
        #expect(result.perBrandLengths[.visa]?.panLengths == [16])
    }

    @Test func binLookupDropsUnsupportedSchemes() {
        let response = BinLookupResponse(brands: [
            .init(brand: "DINERS_CLUB", isMain: false, panLengths: [14], cvvLengths: [3]),
            .init(brand: "VISA", isMain: true, panLengths: nil, cvvLengths: nil),
        ])

        let result = response.toBinLookupResult()
        #expect(result.brands == [.visa])
        #expect(result.perBrandLengths.count == 1)
    }

    // MARK: Tokenization response

    @Test func tokenizationResponseDecodesCard() throws {
        let data = Data(#"{"form_token":"tok","card":{"bin":"41111111","last_four_digits":"1111"}}"#.utf8)
        let response = try JSONDecoder().decode(TokenizationResponse.self, from: data)
        #expect(response.formToken == "tok")
        #expect(response.card?.bin == "41111111")
        #expect(response.card?.lastFourDigits == "1111")
    }

    /// A CVV-only tokenization stores a cryptogram against a card the vault already holds — the
    /// response carries no `card` block (web and Android both tolerate its absence).
    @Test func tokenizationResponseDecodesWithoutCard() throws {
        let data = Data(#"{"form_token":"tok_cvv"}"#.utf8)
        let response = try JSONDecoder().decode(TokenizationResponse.self, from: data)
        #expect(response.formToken == "tok_cvv")
        #expect(response.card == nil)
    }

    @Test func binLookupEmptyBrands() {
        let result = BinLookupResponse(brands: nil).toBinLookupResult()
        #expect(result.brands.isEmpty)
        #expect(result.panLengths == [16])
        #expect(result.cvvLengths == [3])
    }
}
