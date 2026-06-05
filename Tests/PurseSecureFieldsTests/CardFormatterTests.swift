import Testing
@testable import PurseSecureFields

struct CardFormatterTests {

    @Test(arguments: [
        // 16-digit (4-4-4-4)
        ("4111111111111111",    "4111 1111 1111 1111"),
        ("4111",               "4111"),
        ("41111111",           "4111 1111"),
        ("411111111111",       "4111 1111 1111"),
        // Amex 15-digit (4-6-5)
        ("378282246310005",    "3782 822463 10005"),
        ("370000000000002",    "3700 000000 00002"),
        ("3782",               "3782"),
        ("3782822463",         "3782 822463"),
        // 19-digit (4-4-4-4-3)
        ("4000000000000000000", "4000 0000 0000 0000 000"),
        ("40000000000000000",  "4000 0000 0000 0000 0"),
        // Edge cases
        ("",  ""),
        ("4", "4"),
    ])
    func formatPAN(input: String, expected: String) {
        #expect(CardFormatter.formatPAN(input) == expected)
    }
}
