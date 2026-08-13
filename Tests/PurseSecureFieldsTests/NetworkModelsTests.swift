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

    @Test func binLookupEmptyBrands() {
        let result = BinLookupResponse(brands: nil).toBinLookupResult()
        #expect(result.brands.isEmpty)
        #expect(result.panLengths == [16])
        #expect(result.cvvLengths == [3])
    }
}
