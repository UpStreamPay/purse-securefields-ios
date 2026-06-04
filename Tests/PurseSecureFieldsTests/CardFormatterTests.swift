import Testing
@testable import PurseSecureFields

struct CardFormatterTests {

    // MARK: Standard 16-digit (4-4-4-4)

    @Test func format16Full() {
        #expect(CardFormatter.formatPAN("4111111111111111") == "4111 1111 1111 1111")
    }

    @Test func format16Partial4() {
        #expect(CardFormatter.formatPAN("4111") == "4111")
    }

    @Test func format16Partial8() {
        #expect(CardFormatter.formatPAN("41111111") == "4111 1111")
    }

    @Test func format16Partial12() {
        #expect(CardFormatter.formatPAN("411111111111") == "4111 1111 1111")
    }

    // MARK: Amex 15-digit (4-6-5)

    @Test func formatAmexFull() {
        #expect(CardFormatter.formatPAN("378282246310005") == "3782 822463 10005")
    }

    @Test func formatAmex37Prefix() {
        #expect(CardFormatter.formatPAN("370000000000002") == "3700 000000 00002")
    }

    @Test func formatAmexPartial4() {
        #expect(CardFormatter.formatPAN("3782") == "3782")
    }

    @Test func formatAmexPartial10() {
        #expect(CardFormatter.formatPAN("3782822463") == "3782 822463")
    }

    // MARK: Oney 19-digit (4-4-4-4-3)

    @Test func format19Full() {
        #expect(CardFormatter.formatPAN("4000000000000000000") == "4000 0000 0000 0000 000")
    }

    @Test func format19Partial17() {
        #expect(CardFormatter.formatPAN("40000000000000000") == "4000 0000 0000 0000 0")
    }

    // MARK: Edge cases

    @Test func formatEmpty() {
        #expect(CardFormatter.formatPAN("") == "")
    }

    @Test func formatSingleDigit() {
        #expect(CardFormatter.formatPAN("4") == "4")
    }
}
