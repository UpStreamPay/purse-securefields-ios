public enum CardBrand: String, CaseIterable, Equatable {
    case visa = "VISA"
    case mastercard = "MASTERCARD"
    case amex = "AMEX"
    case maestro = "MAESTRO"
    case carteBancaire = "CARTE_BANCAIRE"
    case oney = "ONEY"

    /// Accepts the enum raw values and the vault API's scheme vocabulary — the API says
    /// "AMERICAN_EXPRESS" where the enum raw value is "AMEX". Any configuration that crosses a
    /// JSON boundary (React Native / Flutter bridge, server-pushed config, test harness) can use
    /// either spelling instead of silently dropping the brand.
    public init?(apiValue: String) {
        switch apiValue {
        case "AMERICAN_EXPRESS": self = .amex
        default: self.init(rawValue: apiValue)
        }
    }
}

extension CardBrand {
    /// The CVV lengths a card of this brand carries — what a BIN lookup would answer for it.
    /// `nil` for Oney, whose "CVV" is a birth date, not digits.
    ///
    /// **Fallback only.** A form with a PAN field takes its lengths from the BIN lookup and never
    /// reads this table. A CVV-only form has no PAN to look up, so the brand the host already
    /// knows (`SecureFieldsConfig.brands`, or `selectBrand(_:)`) is the only source — the same
    /// static table web and Android fall back to.
    var standingCVVLengths: [Int]? {
        switch self {
        case .amex:                                    return [4]
        case .oney:                                    return nil
        case .visa, .mastercard, .maestro, .carteBancaire: return [3]
        }
    }

    /// Accepted while nothing narrows the brand: the two lengths in use.
    static let noBrandCVVLengths = [3, 4]

    /// What a CVV-only form validates its CVV against before the host names a brand: a single
    /// configured brand applies as-is (an Amex form takes 4 digits), several accept every length
    /// any of them could ask for — the card in hand could be any of them, and picking the first
    /// would reject the rest (web's `unionOfCvvLengths`, Android's `cvvOnlyDescriptionFor`).
    /// Oney contributes nothing here: its birthdate flow is not available on a CVV-only form.
    static func cvvOnlyLengths(for brands: [CardBrand]) -> [Int] {
        let union = Set(brands.compactMap(\.standingCVVLengths).joined())
        return union.isEmpty ? noBrandCVVLengths : union.sorted()
    }
}
